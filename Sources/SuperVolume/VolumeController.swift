import Foundation

enum VolumeKey: Int {
    case up = 0
    case down = 1
    case mute = 7
}

/// Logique de volume : décide si une touche doit être interceptée, puis règle les sous-périphériques.
final class VolumeController {
    static let shared = VolumeController()

    /// File série : tout l'état mutable (muted, savedLevel) et les appels CoreAudio qui écrivent passent ici.
    let queue = DispatchQueue(label: "supervolume.audio")

    private let excludedKey = "excludedSubDeviceUIDs"
    private var muted = false
    private var savedLevel: Float = 0

    var excludedUIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: excludedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: excludedKey) }
    }

    private let overrideKey = "overrideOutputUID"

    /// UID de la sortie forcée par l'utilisateur ; nil = suivre la sortie active du Mac.
    var overrideUID: String? {
        get { UserDefaults.standard.string(forKey: overrideKey) }
        set { UserDefaults.standard.set(newValue, forKey: overrideKey) }
    }

    /// Sortie à piloter : l'override s'il est défini et branché, sinon la sortie active du Mac.
    func resolveTarget() -> (dev: AudioDev, overridden: Bool)? {
        if let uid = overrideUID, let d = Audio.outputDevices().first(where: { $0.uid == uid }) {
            return (d, true)
        }
        guard let d = Audio.defaultOutput() else { return nil }
        return (d, false)
    }

    /// Sous-périphériques pilotés pour une sortie donnée (réglables, non exclus).
    func managedSubDevices(of out: AudioDev) -> [AudioDev] {
        let excluded = excludedUIDs
        return Audio.subDevices(of: out).filter { Audio.canSetVolume($0) && !excluded.contains($0.uid) }
    }

    /// Périphériques dont on règle réellement le volume pour une sortie cible.
    func controlled(for out: AudioDev, overridden: Bool) -> [AudioDev] {
        if overridden && Audio.canSetVolume(out) { return [out] }
        return managedSubDevices(of: out)
    }

    /// Évalué à chaque appui (pas de cache). Mode suivi : on n'intercepte que si macOS ne sait pas régler
    /// la sortie active. Mode override : on intercepte dès que la cible est pilotable.
    func shouldIntercept() -> Bool {
        guard let t = resolveTarget() else { return false }
        if !t.overridden && Audio.canSetVolume(t.dev) { return false }
        return !controlled(for: t.dev, overridden: t.overridden).isEmpty
    }

    private func currentLevel(_ subs: [AudioDev]) -> Float {
        let levels = subs.compactMap(Audio.volume)
        return levels.isEmpty ? 0 : levels.reduce(0, +) / Float(levels.count)
    }

    private func apply(level: Float, to subs: [AudioDev]) {
        for d in subs { Audio.setVolume(d, level) }
    }

    private func setMuted(_ on: Bool, subs: [AudioDev]) {
        for d in subs {
            if Audio.canMute(d) {
                Audio.setMute(d, on)
            } else {
                Audio.setVolume(d, on ? 0 : savedLevel)
            }
        }
        muted = on
    }

    /// Appelé sur `queue`. Retourne (niveau, muet) pour le HUD, ou nil si rien à piloter.
    func press(_ key: VolumeKey, fine: Bool) -> (level: Float, muted: Bool)? {
        guard let t = resolveTarget() else { return nil }
        let subs = controlled(for: t.dev, overridden: t.overridden)
        guard !subs.isEmpty else { return nil }

        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0

        switch key {
        case .mute:
            if muted {
                setMuted(false, subs: subs)
            } else {
                savedLevel = currentLevel(subs)
                setMuted(true, subs: subs)
            }
        case .up, .down:
            if muted {
                // Comme macOS : une touche volume sort du mode muet.
                setMuted(false, subs: subs)
            }
            let base = currentLevel(subs)
            let snapped = (base / step).rounded()
            let next = min(max((snapped + (key == .up ? 1 : -1)) * step, 0), 1)
            apply(level: next, to: subs)
        }
        return (muted ? 0 : currentLevel(subs), muted)
    }

    /// Réglage direct (mode CLI). Applique sur les sous-périphériques, ou sur la sortie elle-même si elle est réglable.
    func setLevel(_ level: Float) -> Bool {
        guard let t = resolveTarget() else { return false }
        let subs = controlled(for: t.dev, overridden: t.overridden)
        if !subs.isEmpty { apply(level: level, to: subs); return true }
        return Audio.setVolume(t.dev, level)
    }
}
