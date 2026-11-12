import AppKit
import CoreAudio
import Darwin

// MARK: - Processus audio

struct AudioProcess {
    let id: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let running: Bool
    /// Clé stable de l'app : bundle ID sans suffixe « .helper… », sinon « proc:<nom> ».
    let key: String
}

enum AppKey {
    static func key(bundleID: String, pid: pid_t) -> String {
        if !bundleID.isEmpty {
            return bundleID.replacingOccurrences(of: #"\.[Hh]elper.*$"#, with: "", options: .regularExpression)
        }
        var buf = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buf, 256)
        let name = String(cString: buf)
        return "proc:" + (name.isEmpty ? String(pid) : name)
    }

    static func displayName(_ key: String) -> String {
        if key.hasPrefix("proc:") { return String(key.dropFirst(5)) }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: key).first,
           let name = app.localizedName { return name }
        return key.split(separator: ".").last.map(String.init) ?? key
    }
}

extension Audio {
    /// Processus connus de CoreAudio (hors SuperVolume). Un helper Electron est un processus à part.
    static func processes() -> [AudioProcess] {
        var a = addr(kAudioHardwarePropertyProcessObjectList, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var pid: Int32 = 0
            var pa = addr(kAudioProcessPropertyPID, scope: kAudioObjectPropertyScopeGlobal)
            var psize = UInt32(MemoryLayout<Int32>.size)
            guard AudioObjectGetPropertyData(id, &pa, 0, nil, &psize, &pid) == noErr, pid != getpid() else { return nil }

            var bundle = string(id, kAudioProcessPropertyBundleID)
            if bundle == "?" { bundle = "" }

            var running: UInt32 = 0
            var ra = addr(kAudioProcessPropertyIsRunningOutput, scope: kAudioObjectPropertyScopeGlobal)
            var rsize = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(id, &ra, 0, nil, &rsize, &running)

            return AudioProcess(id: id, pid: pid, bundleID: bundle, running: running != 0,
                                key: AppKey.key(bundleID: bundle, pid: pid))
        }
    }
}

// MARK: - Session de routage (tap + agrégat privé + IOProc)

/// Capte l'audio d'un groupe de processus (tap muet) et le rejoue sur le périphérique de destination.
final class RouteSession {
    let key: String
    let processIDs: Set<AudioObjectID>
    let destUID: String
    /// Périphérique qui reçoit aussi une copie (ex. BlackHole pour une visio), à 100 % ; nil sans copie.
    let copyUID: String?
    /// Pic du signal capté (écrit par le thread audio, lu pour le diagnostic).
    let peak = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// Pics écrits sur les branches locales (avec gain) et virtuelles (100 %) — diagnostic.
    let peakLocal = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let peakVirtual = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// Gain linéaire appliqué aux branches locales ; lu par le thread audio, modifiable à chaud.
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// Un octet par buffer de sortie : 1 = branche locale (gain), 0 = virtuelle (100 %).
    private var localFlags: UnsafeMutablePointer<UInt8>
    private var localFlagCount = 0
    /// Détail des branches (diagnostic).
    private(set) var legsDescription = ""

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "supervolume.route", qos: .userInteractive)

    /// nil + statut OSStatus en cas d'échec (typiquement : permission « Capture audio » refusée).
    static func start(key: String, processIDs: Set<AudioObjectID>, dest: AudioDev, copy: AudioDev? = nil,
                      volume: Float = 1) -> (RouteSession?, OSStatus) {
        let s = RouteSession(key: key, processIDs: processIDs, destUID: dest.uid, copyUID: copy?.uid)
        s.setVolume(volume)
        let status = s.activate(dest: dest, copy: copy)
        if status != noErr { s.stop(); return (nil, status) }
        return (s, noErr)
    }

    private init(key: String, processIDs: Set<AudioObjectID>, destUID: String, copyUID: String?) {
        self.key = key
        self.processIDs = processIDs
        self.destUID = destUID
        self.copyUID = copyUID
        peak.initialize(to: 0)
        peakLocal.initialize(to: 0)
        peakVirtual.initialize(to: 0)
        gain.initialize(to: 1)
        localFlags = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    }

    /// Volume local 0…1 (courbe quadratique, plus naturelle à l'oreille).
    func setVolume(_ v: Float) {
        let c = min(max(v, 0), 1)
        gain.pointee = c * c
    }

    private func activate(dest: AudioDev, copy: AudioDev?) -> OSStatus {
        // 1. Tap muet sur les processus de l'app
        let desc = CATapDescription(stereoMixdownOfProcesses: Array(processIDs))
        desc.uuid = UUID()
        desc.name = "SuperVolume \(key)"
        desc.isPrivate = true
        desc.muteBehavior = CATapMuteBehavior.muted
        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else { return status }

        // 2. Agrégat privé : sous-périphériques de la destination + tap.
        //    Destination multi-sortie/agrégat : on reprend ses sous-périphériques (sortie dupliquée).
        //    Copie : ses branches s'ajoutent après celles de la destination, qui reste l'horloge principale
        //    (la copie est recalée par la correction de dérive). Une branche déjà présente n'est pas doublée.
        func legsOf(_ d: AudioDev) -> [AudioDev] {
            let subs = Audio.subDevices(of: d)
            return subs.isEmpty ? [d] : subs
        }
        var legs = legsOf(dest)
        if let copy {
            for leg in legsOf(copy) where !legs.contains(where: { $0.uid == leg.uid }) { legs.append(leg) }
        }
        let uids = legs.map(\.uid)

        // Branches locales (gain) vs virtuelles (100 %), dans l'ordre des buffers de sortie de l'agrégat.
        var flags: [UInt8] = []
        for leg in legs {
            flags += [UInt8](repeating: Audio.isVirtual(leg) ? 0 : 1, count: Audio.outputStreamCount(leg))
        }
        localFlags.deallocate()
        localFlags = UnsafeMutablePointer<UInt8>.allocate(capacity: max(flags.count, 1))
        for (i, f) in flags.enumerated() { localFlags[i] = f }
        localFlagCount = flags.count
        legsDescription = legs.map { "\($0.name)[virt=\(Audio.isVirtual($0)) flux=\(Audio.outputStreamCount($0))]" }.joined(separator: " | ") + " flags=\(flags)"
        let subList: [[String: Any]] = uids.enumerated().map { i, uid in
            [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceDriftCompensationKey: i == 0 ? 0 : 1]
        }
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SuperVolume-\(key)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: uids[0],
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,   // non empilé : un buffer de sortie par branche, écrits individuellement
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subList,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID)
        guard status == noErr else { return status }

        // 3. IOProc : copie le flux du tap vers toutes les sorties de l'agrégat.
        let peakPtr = peak, gainPtr = gain, flagsPtr = localFlags, flagCount = localFlagCount
        let pLocal = peakLocal, pVirtual = peakVirtual
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { _, inData, _, outData, _ in
            RouteSession.render(inData: inData, outData: outData, peak: peakPtr, gain: gainPtr,
                                flags: flagsPtr, flagCount: flagCount, peakLocal: pLocal, peakVirtual: pVirtual)
        }
        guard status == noErr else { return status }
        return AudioDeviceStart(aggID, procID)
    }

    /// Thread audio : aucune allocation. Le flux du tap est le dernier buffer d'entrée de l'agrégat
    /// (les entrées des sous-périphériques, ex. BlackHole, passent avant).
    private static func render(inData: UnsafePointer<AudioBufferList>,
                               outData: UnsafeMutablePointer<AudioBufferList>,
                               peak: UnsafeMutablePointer<Float>, gain: UnsafeMutablePointer<Float>,
                               flags: UnsafeMutablePointer<UInt8>, flagCount: Int,
                               peakLocal: UnsafeMutablePointer<Float>, peakVirtual: UnsafeMutablePointer<Float>) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outs = UnsafeMutableAudioBufferListPointer(outData)

        guard let last = ins.last, let src = last.mData?.assumingMemoryBound(to: Float.self) else {
            for o in outs { if let p = o.mData { memset(p, 0, Int(o.mDataByteSize)) } }
            return
        }
        let sc = max(Int(last.mNumberChannels), 1)
        let frames = Int(last.mDataByteSize) / (MemoryLayout<Float>.size * sc)

        var pk: Float = 0
        for i in 0..<(frames * sc) { pk = max(pk, abs(src[i])) }
        if pk > peak.pointee { peak.pointee = pk }

        let g = gain.pointee
        for (idx, o) in outs.enumerated() {
            guard let dst = o.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let isLocal = idx < flagCount && flags[idx] == 1
            let v: Float = isLocal ? g : 1
            if isLocal { peakLocal.pointee = max(peakLocal.pointee, pk * v) } else { peakVirtual.pointee = max(peakVirtual.pointee, pk) }
            let dc = max(Int(o.mNumberChannels), 1)
            let df = Int(o.mDataByteSize) / (MemoryLayout<Float>.size * dc)
            let n = min(frames, df)
            for f in 0..<n {
                for c in 0..<dc { dst[f * dc + c] = c < sc ? src[f * sc + c] * v : 0 }
            }
            if df > n { memset(dst + n * dc, 0, (df - n) * dc * MemoryLayout<Float>.size) }
        }
    }

    func stop() {
        if aggID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggID, procID)
                AudioDeviceDestroyIOProcID(aggID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        peak.deallocate(); peakLocal.deallocate(); peakVirtual.deallocate()
        gain.deallocate(); localFlags.deallocate()
    }
}

// MARK: - Routeur (règles par app + réconciliation)

struct AppEntry {
    let key: String
    let name: String
    let playing: Bool
    let destUID: String?
    let failed: Bool
    let volume: Float
    /// Périphérique qui reçoit aussi une copie (ex. BlackHole), nil sans copie.
    let copyUID: String?
}

/// Destination spéciale : suit la sortie active du Mac (permet un volume par app sans changer de périphérique).
let followDefaultUID = "@default"

/// Règles « app → périphérique », mémorisées, réappliquées dès que l'app est présente côté audio.
/// Thread principal uniquement.
final class AppRouter {
    static let shared = AppRouter()

    private let rulesKey = "appRoutes"
    private let namesKey = "appRouteNames"
    private var sessions: [String: RouteSession] = [:]
    private var failedAt: [String: Date] = [:]
    private let volumesKey = "appVolumes"
    private let copiesKey = "appCopies"
    private var timer: Timer?

    /// Copies « app → périphérique en plus » : la destination reste celle de la règle (souvent la sortie active du
    /// Mac), la copie part en parallèle à 100 %. Ex. Spotify → casque actif + BlackHole pour une visio.
    var copies: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: copiesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: copiesKey) }
    }

    var rules: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: rulesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: rulesKey) }
    }
    private var volumes: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: volumesKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: volumesKey) }
    }

    func volume(for key: String) -> Float { Float(volumes[key] ?? 1) }

    /// Volume local de l'app (0…1) : appliqué en direct sur la session, mémorisé.
    func setVolume(key: String, _ v: Float) {
        var vols = volumes
        vols[key] = Double(v)
        volumes = vols
        sessions[key]?.setVolume(v)
    }

    private var names: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: namesKey) }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
        reconcile()
    }

    func stopAll() {
        timer?.invalidate()
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
    }

    func setRoute(key: String, name: String, destUID: String?) {
        var r = rules
        var n = names
        if let destUID { r[key] = destUID; n[key] = name } else { r.removeValue(forKey: key); n.removeValue(forKey: key) }
        rules = r
        names = n
        // « Défaut du Mac » sans routage : plus de session, donc plus de copie non plus.
        if destUID == nil { var c = copies; c.removeValue(forKey: key); copies = c }
        failedAt[key] = nil
        reconcile()
    }

    /// Copie vers un périphérique en plus (nil : aucune). Sans règle, l'app suit alors la sortie active du Mac.
    func setCopy(key: String, name: String, copyUID: String?) {
        var c = copies
        if let copyUID { c[key] = copyUID } else { c.removeValue(forKey: key) }
        copies = c
        if copyUID != nil && rules[key] == nil {
            setRoute(key: key, name: name, destUID: followDefaultUID)
            return
        }
        failedAt[key] = nil
        reconcile()
    }

    /// Apps affichées dans le menu : celles qui ont un processus audio « regular » ou qui jouent, plus celles avec une règle.
    func apps() -> [AppEntry] {
        var result: [String: AppEntry] = [:]
        let rules = self.rules
        let copies = self.copies
        for p in Audio.processes() {
            let isRegular = NSRunningApplication.runningApplications(withBundleIdentifier: p.key).first?.activationPolicy == .regular
            guard isRegular || p.running || rules[p.key] != nil else { continue }
            let playing = (result[p.key]?.playing ?? false) || p.running
            result[p.key] = AppEntry(key: p.key, name: AppKey.displayName(p.key), playing: playing,
                                     destUID: rules[p.key], failed: failedAt[p.key] != nil,
                                     volume: volume(for: p.key), copyUID: copies[p.key])
        }
        for (key, uid) in rules where result[key] == nil {
            result[key] = AppEntry(key: key, name: names[key] ?? AppKey.displayName(key), playing: false,
                                   destUID: uid, failed: false, volume: volume(for: key), copyUID: copies[key])
        }
        return result.values.sorted { ($0.playing ? 0 : 1, $0.name.lowercased()) < ($1.playing ? 0 : 1, $1.name.lowercased()) }
    }

    func reconcile() {
        let rules = self.rules
        let copies = self.copies
        if rules.isEmpty && sessions.isEmpty { return }

        let procs = Audio.processes()
        let outputs = Audio.outputDevices()

        // Sessions sans règle : arrêt
        for key in sessions.keys where rules[key] == nil {
            sessions.removeValue(forKey: key)?.stop()
        }

        for (key, uid) in rules {
            let wanted = uid == followDefaultUID ? Audio.defaultOutput()?.uid : uid
            guard let dest = outputs.first(where: { $0.uid == wanted }) else {
                sessions.removeValue(forKey: key)?.stop()   // destination débranchée
                continue
            }
            let ids = Set(procs.filter { $0.key == key }.map(\.id))
            if ids.isEmpty {
                sessions.removeValue(forKey: key)?.stop()   // l'app n'a pas (encore) de processus audio
                continue
            }
            // Copie débranchée : la destination continue seule ; elle revient d'elle-même au rebranchement.
            // Copie identique à la destination (ex. sortie active = BlackHole) : inutile.
            let copy = copies[key].flatMap { uid in outputs.first { $0.uid == uid } }.flatMap { $0.uid == dest.uid ? nil : $0 }
            if let s = sessions[key], s.processIDs == ids, s.destUID == dest.uid, s.copyUID == copy?.uid { continue }
            sessions.removeValue(forKey: key)?.stop()

            if let t = failedAt[key], Date().timeIntervalSince(t) < 15 { continue }   // pas de ré-essai en boucle
            let (session, status) = RouteSession.start(key: key, processIDs: ids, dest: dest, copy: copy,
                                                       volume: volume(for: key))
            if let session {
                sessions[key] = session
                failedAt[key] = nil
            } else {
                failedAt[key] = Date()
                FileHandle.standardError.write(Data("route \(key): échec OSStatus \(status)\n".utf8))
            }
        }
    }
}
