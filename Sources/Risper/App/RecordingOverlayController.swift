import AppKit

final class RecordingOverlayController {
    private var panel: NSPanel?
    private let waveformView = RecordingWaveformView(frame: .zero)

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        position(panel)
        waveformView.startAnimating()
        panel.orderFrontRegardless()
    }

    func hide() {
        waveformView.stopAnimating()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 152, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let container = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.masksToBounds = true

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(waveformView)
        NSLayoutConstraint.activate([
            waveformView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            waveformView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            waveformView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            waveformView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        panel.contentView = container
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = activeScreen()
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 28
        )
        panel.setFrameOrigin(origin)
    }

    private func activeScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class RecordingWaveformView: NSView {
    private var timer: Timer?
    private var phase: CGFloat = 0

    override var isFlipped: Bool {
        true
    }

    func startAnimating() {
        stopAnimating()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            phase = 0
            needsDisplay = true
            return
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.16
            self.needsDisplay = true
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barCount = 7
        let availableWidth = bounds.width
        let spacing: CGFloat = 7
        let barWidth = max(4, (availableWidth - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
        let maximumHeight = bounds.height
        let color = NSColor.systemRed.withAlphaComponent(0.95)

        color.setFill()

        for index in 0..<barCount {
            let progress = CGFloat(index) / CGFloat(barCount)
            let wave = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 0.45
                : (sin(phase + progress * .pi * 2) + 1) / 2
            let height = max(6, maximumHeight * (0.35 + wave * 0.65))
            let x = CGFloat(index) * (barWidth + spacing)
            let y = (maximumHeight - height) / 2
            let rect = NSRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            path.fill()
        }
    }
}
