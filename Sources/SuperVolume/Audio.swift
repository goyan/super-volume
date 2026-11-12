import CoreAudio
import Foundation

struct AudioDev {
    let id: AudioObjectID
    let name: String
    let uid: String
}

/// Accès CoreAudio bas niveau : volume, mute, sous-périphériques d'un agrégat / multi-sortie.
enum Audio {
    /// kAudioHardwareServiceDeviceProperty_VirtualMainVolume ('vmvc') — évite l'API AudioHardwareService dépréciée.
    static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    static func addr(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    // MARK: - Primitives

    private static func isSettable(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Bool {
        var a = addr(selector, element: element)
        guard AudioObjectHasProperty(id, &a) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
    }

    private static func getFloat(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Float? {
        var a = addr(selector, element: element)
        guard AudioObjectHasProperty(id, &a) else { return nil }
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func setFloat(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement, _ value: Float) -> Bool {
        var a = addr(selector, element: element)
        var v = Float32(value)
        return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = addr(selector, scope: kAudioObjectPropertyScopeGlobal)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &ref) {
            AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0)
        }
        guard status == noErr, let ref else { return "?" }
        return ref.takeRetainedValue() as String
    }

    // MARK: - Périphériques

    static func device(_ id: AudioObjectID) -> AudioDev {
        AudioDev(id: id, name: string(id, kAudioObjectPropertyName), uid: string(id, kAudioDevicePropertyDeviceUID))
    }

    /// ID actuel du périphérique portant cet UID (agrégats privés de ce processus compris), nil s'il n'existe plus.
    static func deviceID(forUID uid: String) -> AudioObjectID? {
        var a = addr(kAudioHardwarePropertyTranslateUIDToDevice, scope: kAudioObjectPropertyScopeGlobal)
        var cfUID = uid as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    static func defaultOutput() -> AudioDev? {
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return device(id)
    }

    private static func hasOutputChannels(_ id: AudioObjectID) -> Bool {
        var a = addr(kAudioDevicePropertyStreamConfiguration)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    /// Nombre de flux de sortie (= buffers de sortie) d'un périphérique.
    static func outputStreamCount(_ dev: AudioDev) -> Int {
        var a = addr(kAudioDevicePropertyStreams)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev.id, &a, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioObjectID>.size
    }

    /// Périphérique virtuel (BlackHole, loopback…) : il reste à 100 % dans un routage.
    static func isVirtual(_ dev: AudioDev) -> Bool {
        var a = addr(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev.id, &a, 0, nil, &size, &t) == noErr && t == kAudioDeviceTransportTypeVirtual
    }

    /// Périphérique (entrée ou sortie) par nom — diagnostic.
    static func inputDevice(named name: String) -> AudioDev? {
        var a = addr(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return nil }
        return ids.map(device).first { $0.name.localizedCaseInsensitiveContains(name) }
    }

    /// Tous les périphériques ayant au moins un canal de sortie.
    static func outputDevices() -> [AudioDev] {
        var a = addr(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
        // On masque les agrégats privés de routage créés par SuperVolume lui-même.
        return ids.filter(hasOutputChannels).map(device).filter { !$0.name.hasPrefix("SuperVolume-") }
    }

    /// Sous-périphériques actifs d'un agrégat / multi-sortie. Vide pour un périphérique ordinaire.
    static func subDevices(of dev: AudioDev) -> [AudioDev] {
        var a = addr(kAudioAggregateDevicePropertyActiveSubDeviceList, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        guard AudioObjectHasProperty(dev.id, &a),
              AudioObjectGetPropertyDataSize(dev.id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(dev.id, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map(device)
    }

    // MARK: - Volume

    /// Vrai si le périphérique expose un volume réglable (donc macOS sait le piloter nativement).
    static func canSetVolume(_ dev: AudioDev) -> Bool {
        isSettable(dev.id, virtualMainVolume, element: kAudioObjectPropertyElementMain)
            || [0, 1, 2].contains { isSettable(dev.id, kAudioDevicePropertyVolumeScalar, element: AudioObjectPropertyElement($0)) }
    }

    static func volume(_ dev: AudioDev) -> Float? {
        if let v = getFloat(dev.id, virtualMainVolume, element: kAudioObjectPropertyElementMain) { return v }
        let channels = [1, 2].compactMap { getFloat(dev.id, kAudioDevicePropertyVolumeScalar, element: AudioObjectPropertyElement($0)) }
        if !channels.isEmpty { return channels.reduce(0, +) / Float(channels.count) }
        return getFloat(dev.id, kAudioDevicePropertyVolumeScalar, element: 0)
    }

    @discardableResult
    static func setVolume(_ dev: AudioDev, _ value: Float) -> Bool {
        let v = min(max(value, 0), 1)
        if isSettable(dev.id, virtualMainVolume, element: kAudioObjectPropertyElementMain) {
            return setFloat(dev.id, virtualMainVolume, element: kAudioObjectPropertyElementMain, v)
        }
        var ok = false
        for ch in [1, 2, 0] as [AudioObjectPropertyElement] where isSettable(dev.id, kAudioDevicePropertyVolumeScalar, element: ch) {
            ok = setFloat(dev.id, kAudioDevicePropertyVolumeScalar, element: ch, v) || ok
        }
        return ok
    }

    // MARK: - Mute

    static func canMute(_ dev: AudioDev) -> Bool {
        isSettable(dev.id, kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
    }

    @discardableResult
    static func setMute(_ dev: AudioDev, _ muted: Bool) -> Bool {
        var a = addr(kAudioDevicePropertyMute)
        var v: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(dev.id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }
}
