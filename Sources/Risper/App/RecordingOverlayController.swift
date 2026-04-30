import AppKit
import QuartzCore

final class RecordingOverlayController {
    private var panel: NSPanel?
    private var presentationGeneration = 0
    private let signalView = RecordingSignalView(frame: .zero)

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        presentationGeneration += 1
        let generation = presentationGeneration
        let shouldAnimate = !panel.isVisible

        position(panel)
        signalView.startAnimating()

        if shouldAnimate {
            panel.alphaValue = 0
        }

        panel.orderFrontRegardless()

        guard shouldAnimate else {
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard self?.presentationGeneration == generation else { return }
            panel.alphaValue = 1
        }
    }

    func hide() {
        guard let panel else {
            signalView.stopAnimating()
            return
        }

        presentationGeneration += 1
        let generation = presentationGeneration

        guard panel.isVisible else {
            signalView.stopAnimating()
            panel.alphaValue = 1
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard self?.presentationGeneration == generation else { return }
            self?.signalView.stopAnimating()
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    func updateAudioLevel(_ level: Float) {
        signalView.updateAudioLevel(level)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 88, height: 26),
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
        container.autoresizingMask = [.width, .height]
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = RecordingTintView.baseColor.withAlphaComponent(0.58).cgColor
        container.layer?.backgroundColor = RecordingTintView.baseColor.withAlphaComponent(0.14).cgColor
        container.layer?.masksToBounds = true

        let tintView = RecordingTintView(frame: container.bounds)
        tintView.autoresizingMask = [.width, .height]
        container.addSubview(tintView)

        signalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(signalView)
        NSLayoutConstraint.activate([
            signalView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            signalView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            signalView.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            signalView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5)
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

private final class RecordingTintView: NSView {
    static let baseColor = NSColor(
        calibratedRed: 0.07,
        green: 0.64,
        blue: 0.90,
        alpha: 1
    )

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: bounds.height / 2,
            yRadius: bounds.height / 2
        )
        path.addClip()

        Self.baseColor.withAlphaComponent(0.40).setFill()
        path.fill()

        let highlightRect = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: bounds.height * 0.48
        )
        let highlightPath = NSBezierPath(
            roundedRect: highlightRect,
            xRadius: bounds.height / 2,
            yRadius: bounds.height / 2
        )
        NSColor.white.withAlphaComponent(0.14).setFill()
        highlightPath.fill()
    }
}

private final class RecordingSignalView: NSView {
    private static let barCount = 10
    private static let quietLevel: CGFloat = 0.30
    private static let creamLineColor = NSColor(
        calibratedRed: 1.0,
        green: 0.965,
        blue: 0.88,
        alpha: 0.88
    )

    private var timer: Timer?
    private var phase: CGFloat = 0
    private var targetLevel: CGFloat = RecordingSignalView.quietLevel
    private var displayedLevel: CGFloat = RecordingSignalView.quietLevel

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    func startAnimating() {
        stopAnimating()
        targetLevel = Self.quietLevel
        displayedLevel = Self.quietLevel

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            phase = 0
            needsDisplay = true
            return
        }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.075
            self.displayedLevel += (self.targetLevel - self.displayedLevel) * 0.18
            self.needsDisplay = true
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        targetLevel = Self.quietLevel
        displayedLevel = Self.quietLevel
        needsDisplay = true
    }

    func updateAudioLevel(_ level: Float) {
        let normalizedLevel = min(max(CGFloat(level), 0), 1)
        let responsiveLevel = pow(normalizedLevel, 0.58)
        targetLevel = Self.quietLevel + (1 - Self.quietLevel) * responsiveLevel

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            displayedLevel = targetLevel
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawWaveform()
    }

    private func drawWaveform() {
        let waveformBounds = bounds.insetBy(dx: 0, dy: 1)
        guard waveformBounds.width > 0, waveformBounds.height > 0 else { return }

        let barCount = Self.barCount
        let spacing: CGFloat = 3
        let barWidth = max(2.5, (waveformBounds.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
        let maximumHeight = waveformBounds.height
        let centerY = waveformBounds.midY
        let color = Self.creamLineColor

        color.setFill()

        for index in 0..<barCount {
            let progress = CGFloat(index) / CGFloat(barCount - 1)
            let envelope = 0.38 + sin(progress * .pi) * 0.62
            let wave = waveformValue(for: index, progress: progress)
            let activity = Self.quietLevel + displayedLevel * envelope * (0.42 + wave * 0.58)
            let height = min(maximumHeight, max(3.5, maximumHeight * activity))
            let x = waveformBounds.minX + CGFloat(index) * (barWidth + spacing)
            let y = centerY - height / 2
            let rect = NSRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            path.fill()
        }
    }

    private func waveformValue(for index: Int, progress: CGFloat) -> CGFloat {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return 0.5 + sin(progress * .pi * 2.6) * 0.24
        }

        let indexOffset = CGFloat(index)
        let first = sin(phase * 1.8 + indexOffset * 0.58)
        let second = sin(phase * 1.15 + indexOffset * 1.21)
        return min(max((first * 0.55 + second * 0.45 + 1) / 2, 0), 1)
    }
}
