import AVFoundation
import Darwin
import Foundation

struct RecordingResult {
    let url: URL
    let duration: TimeInterval
    let peakLevel: Float
    let averageLevel: Float
}

enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case microphoneUnavailable(String)
    case inputFormatUnavailable
    case outputFormatUnavailable
    case converterUnavailable
    case bufferCopyFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording"
        case .microphoneUnavailable(let status):
            return "Microphone permission is \(status)"
        case .inputFormatUnavailable:
            return "Microphone input format is unavailable"
        case .outputFormatUnavailable:
            return "Recording output format is unavailable"
        case .converterUnavailable:
            return "Audio converter is unavailable"
        case .bufferCopyFailed:
            return "Unable to copy microphone buffer"
        case .conversionFailed:
            return "Audio conversion failed"
        }
    }
}

final class AudioRecorder {
    private enum State {
        case idle
        case recording(startedAt: Date, url: URL)
        case failed(String)
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    private let engine = AVAudioEngine()
    private let writeQueue = DispatchQueue(label: "com.risper.Risper.audio-recorder.write")
    private let writeGroup = DispatchGroup()

    private var state: State = .idle
    private var writeError: Error?
    private var lastRecording: RecordingResult?
    private var peakLevel: Float = 0
    private var levelTotal: Float = 0
    private var levelSampleCount = 0

    var onLevelChange: ((Float) -> Void)?

    var statusDescription: String {
        switch state {
        case .idle:
            return "Idle"
        case .recording(let startedAt, _):
            let duration = Self.formatDuration(Date().timeIntervalSince(startedAt))
            return "Recording (\(duration))"
        case .failed(let message):
            return "Error: \(message)"
        }
    }

    var lastRecordingDescription: String {
        guard let lastRecording else {
            return "None"
        }

        return "\(lastRecording.url.lastPathComponent) (\(Self.formatDuration(lastRecording.duration)))"
    }

    func startRecording() throws {
        if case .recording = state {
            throw AudioRecorderError.alreadyRecording
        }

        let microphoneStatus = MicrophonePermission.statusDescription
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            state = .failed("Microphone \(microphoneStatus)")
            throw AudioRecorderError.microphoneUnavailable(microphoneStatus)
        }

        do {
            try FileManager.default.createDirectory(
                at: RisperConfiguration.recordingsDirectoryURL,
                withIntermediateDirectories: true
            )

            let outputURL = RisperConfiguration.recordingsDirectoryURL
                .appendingPathComponent("risper-\(Self.filenameFormatter.string(from: Date())).wav")
            let inputNode = engine.inputNode
            inputNode.removeTap(onBus: 0)

            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                throw AudioRecorderError.inputFormatUnavailable
            }

            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: RisperConfiguration.recordingSampleRate,
                channels: 1,
                interleaved: true
            ) else {
                throw AudioRecorderError.outputFormatUnavailable
            }

            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioRecorderError.converterUnavailable
            }

            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: targetFormat.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )

            writeError = nil
            peakLevel = 0
            levelTotal = 0
            levelSampleCount = 0
            let startedAt = Date()

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self, converter, outputFile, targetFormat] buffer, _ in
                guard let self else { return }
                let level = Self.normalizedAudioLevel(from: buffer)
                self.publishAudioLevel(level)
                self.writeGroup.enter()

                guard let bufferCopy = buffer.copyForAsyncWrite() else {
                    self.writeQueue.async {
                        self.recordLevel(level)
                        if self.writeError == nil {
                            self.writeError = AudioRecorderError.bufferCopyFailed
                        }
                        self.writeGroup.leave()
                    }
                    return
                }

                self.writeQueue.async {
                    defer { self.writeGroup.leave() }
                    self.recordLevel(level)

                    do {
                        try self.write(bufferCopy, converter: converter, targetFormat: targetFormat, to: outputFile)
                    } catch {
                        if self.writeError == nil {
                            self.writeError = error
                        }
                    }
                }
            }

            engine.prepare()
            try engine.start()
            state = .recording(startedAt: startedAt, url: outputURL)
            RisperLog.app.info("Recording started")
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stopRecording() -> RecordingResult? {
        guard case .recording(let startedAt, let url) = state else {
            return nil
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writeGroup.wait()
        onLevelChange?(0)

        if let writeError {
            state = .failed(writeError.localizedDescription)
            RisperLog.app.error("Recording failed while writing WAV: \(writeError.localizedDescription, privacy: .public)")
            return nil
        }

        let result = RecordingResult(
            url: url,
            duration: max(0, Date().timeIntervalSince(startedAt)),
            peakLevel: peakLevel,
            averageLevel: averageLevel
        )
        lastRecording = result
        state = .idle
        RisperLog.app.info("Recording saved: \(url.lastPathComponent, privacy: .public)")
        return result
    }

    private var averageLevel: Float {
        guard levelSampleCount > 0 else {
            return 0
        }

        return levelTotal / Float(levelSampleCount)
    }

    private func publishAudioLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.onLevelChange?(level)
        }
    }

    private func recordLevel(_ level: Float) {
        peakLevel = max(peakLevel, level)
        levelTotal += level
        levelSampleCount += 1
    }

    private func write(
        _ inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        to outputFile: AVAudioFile
    ) throws {
        var inputConsumed = false
        var conversionComplete = false

        while !conversionComplete {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: Self.convertedFrameCapacity(for: inputBuffer, targetFormat: targetFormat)
            ) else {
                throw AudioRecorderError.outputFormatUnavailable
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                if inputConsumed {
                    inputStatus.pointee = .noDataNow
                    return nil
                }

                inputConsumed = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }

            if let conversionError {
                throw conversionError
            }

            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }

            switch status {
            case .haveData:
                continue
            case .inputRanDry, .endOfStream:
                conversionComplete = true
            case .error:
                throw AudioRecorderError.conversionFailed
            @unknown default:
                conversionComplete = true
            }
        }
    }

    private static func convertedFrameCapacity(
        for buffer: AVAudioPCMBuffer,
        targetFormat: AVAudioFormat
    ) -> AVAudioFrameCount {
        let sourceSampleRate = max(buffer.format.sampleRate, 1)
        let frameRatio = targetFormat.sampleRate / sourceSampleRate
        let convertedFrames = Int(ceil(Double(buffer.frameLength) * frameRatio)) + 512
        return AVAudioFrameCount(max(1, convertedFrames))
    }

    private static func normalizedAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var squaredTotal: Float = 0
        var sampleCount = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]

            for frame in 0..<frameLength {
                let sample = samples[frame]
                squaredTotal += sample * sample
            }

            sampleCount += frameLength
        }

        guard sampleCount > 0 else {
            return 0
        }

        let rms = sqrt(squaredTotal / Float(sampleCount))
        let floorDecibels: Float = -55
        let decibels = max(floorDecibels, 20 * log10(max(rms, 0.000_001)))
        return min(max((decibels - floorDecibels) / abs(floorDecibels), 0), 1)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.1fs", max(0, duration))
    }
}

private extension AVAudioPCMBuffer {
    func copyForAsyncWrite() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }

        copy.frameLength = frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        guard sourceBuffers.count == destinationBuffers.count else {
            return nil
        }

        for index in 0..<sourceBuffers.count {
            let sourceBuffer = sourceBuffers[index]
            var destinationBuffer = destinationBuffers[index]

            guard let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffer.mData else {
                continue
            }

            memcpy(destinationData, sourceData, Int(sourceBuffer.mDataByteSize))
            destinationBuffer.mDataByteSize = sourceBuffer.mDataByteSize
            destinationBuffers[index] = destinationBuffer
        }

        return copy
    }
}
