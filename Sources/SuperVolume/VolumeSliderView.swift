import AppKit

/// Ligne de menu avec un curseur de volume local pour une app (appliqué en direct, sans fermer le menu).
final class VolumeSliderView: NSView {
    private let key: String
    private let label = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)

    init(key: String, value: Float) {
        self.key = key
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
        label.font = .menuFont(ofSize: 13)
        label.frame = NSRect(x: 16, y: 6, width: 92, height: 18)
        slider.frame = NSRect(x: 110, y: 5, width: 128, height: 20)
        slider.isContinuous = true
        slider.doubleValue = Double(value)
        slider.target = self
        slider.action = #selector(changed)
        addSubview(label)
        addSubview(slider)
        refreshLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }

    private func refreshLabel() {
        label.stringValue = "Volume local \(Int((slider.doubleValue * 100).rounded())) %"
    }

    @objc private func changed() {
        AppRouter.shared.setVolume(key: key, Float(slider.doubleValue))
        refreshLabel()
    }
}
