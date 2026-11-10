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
    case "--procs":
        for p in Audio.processes() {
            print("pid=\(p.pid) key=\(p.key) bundle=\(p.bundleID.isEmpty ? "-" : p.bundleID) sortie-active=\(p.running)")
        }
    case "--route-test":
        // --route-test <clé app> <nom ou UID du périphérique> <secondes> : route et affiche le pic capté chaque seconde.
        guard args.count > 3, let secs = Double(args[3]) else { print("usage: --route-test <clé> <périph> <secondes>"); return true }
        let ids = Set(Audio.processes().filter { $0.key == args[1] }.map(\.id))
        guard !ids.isEmpty else { print("aucun processus audio pour \(args[1])"); return true }
        guard let dest = Audio.outputDevices().first(where: { $0.uid == args[2] || $0.name.localizedCaseInsensitiveContains(args[2]) }) else {
            print("périphérique introuvable: \(args[2])"); return true
        }
        let (session, status) = RouteSession.start(key: args[1], processIDs: ids, dest: dest)
        guard let session else { print("échec OSStatus \(status)"); return true }
        print("routé \(args[1]) (\(ids.count) processus) → \(dest.name)")
        for _ in 0..<Int(secs) {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            print(String(format: "pic capté: %.4f", session.peak.pointee))
            session.peak.pointee = 0
        }
        session.stop()
        print("arrêté")
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
