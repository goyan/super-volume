import AppKit

// Mode CLI de diagnostic : permet de vérifier CoreAudio sans les touches physiques.
//   SuperVolume --status            sortie active, mode, sous-périphériques et volumes
//   SuperVolume --set 0.5           règle le volume (0…1)
//   SuperVolume --post-key up|down|mute   injecte une touche média synthétique
func runCLI(_ args: [String]) -> Bool {
    guard let cmd = args.first, cmd.hasPrefix("--") else { return false }
    switch cmd {
    case "--status":
        guard let t = VolumeController.shared.resolveTarget() else { print("aucune sortie"); return true }
        let out = t.dev
        print("sortie: \(out.name) [\(out.uid)] forcée=\(t.overridden)")
        print("volume natif: \(Audio.canSetVolume(out))")
        print("sorties: " + Audio.outputDevices().map(\.name).joined(separator: ", "))
        for sub in Audio.subDevices(of: out) {
            let vol = Audio.volume(sub).map { String(format: "%.3f", $0) } ?? "n/a"
            print("  sous-périph: \(sub.name) volume=\(vol) réglable=\(Audio.canSetVolume(sub)) mute=\(Audio.canMute(sub))")
        }
        print("intercepté par SuperVolume: \(VolumeController.shared.shouldIntercept())")
    case "--set":
        guard args.count > 1, let v = Float(args[1]) else { print("usage: --set 0..1"); return true }
        print(VolumeController.shared.setLevel(v) ? "ok" : "échec")
    case "--post-key":
        let map: [String: VolumeKey] = ["up": .up, "down": .down, "mute": .mute]
        guard args.count > 1, let key = map[args[1]] else { print("usage: --post-key up|down|mute"); return true }
        KeyTap.post(key)
        print("posté: \(args[1])")
    default:
        print("option inconnue: \(cmd)")
    }
    return true
}

if runCLI(Array(CommandLine.arguments.dropFirst())) { exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
