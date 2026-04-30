import Foundation

final class ASRServerManager {
    private enum State: Equatable {
        case idle
        case checking
        case missingModel
        case missingBinary
        case starting
        case readyExternal
        case readyAppOwned
        case unhealthy(String)
        case crashed(Int32)
        case restarting(Int)
        case stopped

        var description: String {
            switch self {
            case .idle:
                return "Not started"
            case .checking:
                return "Checking"
            case .missingModel:
                return "Missing model"
            case .missingBinary:
                return "Missing whisper-server"
            case .starting:
                return "Starting"
            case .readyExternal:
                return "Ready (external)"
            case .readyAppOwned:
                return "Ready (managed)"
            case .unhealthy(let reason):
                return "Unhealthy: \(reason)"
            case .crashed(let status):
                return "Crashed (\(status))"
            case .restarting(let attempt):
                return "Restarting (\(attempt))"
            case .stopped:
                return "Stopped"
            }
        }

        var isStartupInProgress: Bool {
            switch self {
            case .checking, .starting, .restarting:
                return true
            case .idle, .missingModel, .missingBinary, .readyExternal, .readyAppOwned, .unhealthy, .crashed, .stopped:
                return false
            }
        }
    }

    private struct HealthResponse: Decodable {
        let status: String?
    }

    var onStatusChange: (() -> Void)?

    private let fileManager: FileManager
    private let modelURL: URL
    private let healthURL: URL
    private let host: String
    private let port: Int
    private let session: URLSession

    private var process: Process?
    private var healthTimer: Timer?
    private var readinessTimer: Timer?
    private var isStopping = false
    private var restartAfterTermination = false
    private var restartAttempts = 0
    private var consecutiveHealthFailures = 0

    private let maximumRestartAttempts = 3
    private let readinessTimeout: TimeInterval = 90
    private let healthCheckInterval: TimeInterval = 5

    private var state: State = .idle {
        didSet {
            guard oldValue != state else { return }
            RisperLog.app.info("ASR server state: \(self.state.description, privacy: .public)")
            onStatusChange?()
        }
    }

    init(
        fileManager: FileManager = .default,
        modelURL: URL = RisperConfiguration.modelURL,
        healthURL: URL = RisperConfiguration.asrHealthURL,
        host: String = RisperConfiguration.asrHost,
        port: Int = RisperConfiguration.asrPort,
        session: URLSession = ASRServerManager.makeSession()
    ) {
        self.fileManager = fileManager
        self.modelURL = modelURL
        self.healthURL = healthURL
        self.host = host
        self.port = port
        self.session = session
    }

    var statusDescription: String {
        state.description
    }

    var isReady: Bool {
        state == .readyExternal || state == .readyAppOwned
    }

    func start() {
        isStopping = false
        startHealthMonitoring()
        guard !state.isStartupInProgress else { return }
        beginStartup()
    }

    func restart() {
        restartAttempts = 0
        consecutiveHealthFailures = 0
        readinessTimer?.invalidate()
        readinessTimer = nil

        guard let process else {
            guard !state.isStartupInProgress else { return }
            beginStartup()
            return
        }

        if process.isRunning {
            restartAfterTermination = true
            state = .restarting(1)
            RisperLog.app.info("Stopping app-owned ASR server for restart")
            process.terminate()
        } else {
            self.process = nil
            beginStartup()
        }
    }

    func stop() {
        isStopping = true
        restartAfterTermination = false
        healthTimer?.invalidate()
        readinessTimer?.invalidate()
        healthTimer = nil
        readinessTimer = nil

        guard let process else {
            state = .stopped
            return
        }

        self.process = nil
        process.terminationHandler = nil

        if process.isRunning {
            RisperLog.app.info("Stopping app-owned ASR server")
            process.terminate()
        }

        state = .stopped
    }

    private func beginStartup() {
        guard !isStopping else { return }

        if let process, process.isRunning {
            state = .starting
            pollUntilReady(deadline: Date().addingTimeInterval(readinessTimeout))
            return
        }

        state = .checking
        checkHealth { [weak self] isHealthy in
            guard let self, !self.isStopping else { return }

            if isHealthy {
                self.consecutiveHealthFailures = 0
                self.restartAttempts = 0
                self.state = .readyExternal
            } else {
                guard self.fileManager.fileExists(atPath: self.modelURL.path) else {
                    self.state = .missingModel
                    return
                }

                guard let serverURL = self.locateWhisperServer() else {
                    self.state = .missingBinary
                    return
                }

                self.startAppOwnedServer(at: serverURL)
            }
        }
    }

    private func startAppOwnedServer(at serverURL: URL) {
        guard !isStopping else { return }

        let process = Process()
        process.executableURL = serverURL
        process.arguments = [
            "--host", host,
            "--port", "\(port)",
            "--model", modelURL.path,
            "--language", "he"
        ]

        if let nullDevice = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = nullDevice
            process.standardError = nullDevice
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async {
                self?.handleTermination(of: terminatedProcess)
            }
        }

        do {
            try process.run()
            self.process = process
            state = .starting
            RisperLog.app.info("Started app-owned ASR server")
            pollUntilReady(deadline: Date().addingTimeInterval(readinessTimeout))
        } catch {
            state = .unhealthy("Launch failed")
            RisperLog.app.error("Unable to launch ASR server: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pollUntilReady(deadline: Date) {
        readinessTimer?.invalidate()

        readinessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, !self.isStopping else {
                timer.invalidate()
                return
            }

            if Date() > deadline {
                timer.invalidate()
                self.state = .unhealthy("Startup timed out")
                return
            }

            self.checkHealth { [weak self] isHealthy in
                guard let self, !self.isStopping else { return }
                guard isHealthy else { return }

                timer.invalidate()
                self.consecutiveHealthFailures = 0
                self.restartAttempts = 0
                self.state = self.process?.isRunning == true ? .readyAppOwned : .readyExternal
            }
        }
    }

    private func startHealthMonitoring() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            self?.performPeriodicHealthCheck()
        }
    }

    private func performPeriodicHealthCheck() {
        guard !isStopping else { return }
        guard !state.isStartupInProgress else { return }

        checkHealth { [weak self] isHealthy in
            guard let self, !self.isStopping else { return }

            if isHealthy {
                self.consecutiveHealthFailures = 0
                if self.process?.isRunning == true {
                    self.state = .readyAppOwned
                } else if self.isReady || self.state == .unhealthy("Health check failed") {
                    self.state = .readyExternal
                }
                return
            }

            self.consecutiveHealthFailures += 1
            guard self.consecutiveHealthFailures >= 2 else { return }

            if let process = self.process, process.isRunning {
                self.state = .unhealthy("Health check failed")
                RisperLog.app.warning("App-owned ASR server failed health checks; terminating for restart")
                process.terminate()
            } else {
                self.state = .unhealthy("Health check failed")
                self.beginStartup()
            }
        }
    }

    private func handleTermination(of terminatedProcess: Process) {
        guard process === terminatedProcess else { return }
        process = nil
        readinessTimer?.invalidate()
        readinessTimer = nil

        guard !isStopping else { return }

        let wasRestartRequested = restartAfterTermination
        restartAfterTermination = false
        let status = terminatedProcess.terminationStatus
        if !wasRestartRequested {
            state = .crashed(status)
        }

        guard restartAttempts < maximumRestartAttempts else {
            RisperLog.app.error("ASR server restart limit reached")
            return
        }

        restartAttempts += 1
        let attempt = restartAttempts
        let delay = min(TimeInterval(attempt * 2), 10)
        state = .restarting(attempt)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isStopping else { return }
            self.beginStartup()
        }
    }

    private func checkHealth(completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 2

        session.dataTask(with: request) { data, response, _ in
            let isHealthy: Bool

            isHealthy = {
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data,
                      let decoded = try? JSONDecoder().decode(HealthResponse.self, from: data) else {
                    return false
                }

                return decoded.status == "ok"
            }()

            DispatchQueue.main.async {
                completion(isHealthy)
            }
        }.resume()
    }

    private func locateWhisperServer() -> URL? {
        var candidates: [URL] = []

        if let overridePath = ProcessInfo.processInfo.environment["RISPER_WHISPER_SERVER"],
           !overridePath.isEmpty {
            candidates.append(URL(fileURLWithPath: overridePath))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("whisper.cpp/bin/whisper-server"))
            candidates.append(resourceURL.appendingPathComponent("whisper-server"))
        }

        let bundleURL = Bundle.main.bundleURL
        let repoRootFromDist = bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(repoRootFromDist.appendingPathComponent("third_party/whisper.cpp/build/bin/whisper-server"))

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectory.appendingPathComponent("third_party/whisper.cpp/build/bin/whisper-server"))

        return candidates.first { url in
            fileManager.isExecutableFile(atPath: url.path)
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        return URLSession(configuration: configuration)
    }
}
