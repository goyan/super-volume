import AppKit

/// Petit HUD de volume façon macOS : icône + 16 segments, affiché ~1,2 s.
final class HUD {
    private let panel: NSPanel
    private let icon = NSImageView()
    private var segments: [CALayer] = []
    private var hideWork: DispatchWorkItem?

    init() {
        let size = NSSize(width: 200, height: 200)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 20
        fx.layer?.masksToBounds = true
        panel.contentView = fx

        icon.frame = NSRect(x: 58, y: 86, width: 84, height: 84)
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyUpOrDown
        fx.addSubview(icon)

        for i in 0..<16 {
            let layer = CALayer()
            layer.frame = CGRect(x: 29 + CGFloat(i) * 9, y: 40, width: 7, height: 7)
            layer.cornerRadius = 1.5
            fx.layer?.addSublayer(layer)
            segments.append(layer)
        }
    }

    private func symbol(level: Float, muted: Bool) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    func show(level: Float, muted: Bool) {
        icon.image = NSImage(systemSymbolName: symbol(level: level, muted: muted), accessibilityDescription: nil)
        let filled = muted ? 0 : Int((level * 16).rounded())
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, layer) in segments.enumerated() {
            layer.backgroundColor = NSColor.white.withAlphaComponent(i < filled ? 0.95 : 0.25).cgColor
        }
        CATransaction.commit()

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 100, y: f.minY + 120))
        }
        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                self?.panel.animator().alphaValue = 0
            }, completionHandler: { self?.panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
