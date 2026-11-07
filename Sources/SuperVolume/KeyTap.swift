import AppKit
import CoreGraphics

/// Intercepte les touches média volume (NX_SYSDEFINED, subtype 8) via un CGEventTap actif.
final class KeyTap {
    /// Retourne true pour avaler la touche (down ET up), false pour la laisser passer à macOS.
    var handler: ((VolumeKey, NSEvent.ModifierFlags) -> Bool)?

    private var tap: CFMachPort?
    private var swallowedDown = Set<Int>()

    private let systemDefinedType = CGEventType(rawValue: 14)!  // NX_SYSDEFINED

    var isRunning: Bool { tap != nil }

    /// Crée le tap. Retourne false si la permission Accessibilité manque (tapCreate renvoie nil).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1) << CGEventMask(systemDefinedType.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // Le système coupe un tap trop lent : on le réactive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type == systemDefinedType,
              let ns = NSEvent(cgEvent: event),
              ns.subtype.rawValue == 8 else { return pass }

        let data1 = ns.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0x0000_FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0xA
        guard let key = VolumeKey(rawValue: keyCode) else { return pass }

        if isDown {
            // Inclut les répétitions (touche maintenue) : chaque répétition est un nouveau key-down.
            if handler?(key, ns.modifierFlags) == true {
                swallowedDown.insert(keyCode)
                return nil
            }
            return pass
        }
        // Key-up : on l'avale seulement si on a avalé le key-down correspondant.
        if swallowedDown.remove(keyCode) != nil { return nil }
        return pass
    }

    /// Injecte une touche synthétique (auto-test, sans toucher au clavier).
    static func post(_ key: VolumeKey) {
        for down in [true, false] {
            let data1 = (key.rawValue << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1
            )
            event?.cgEvent?.post(tap: .cgSessionEventTap)
        }
    }
}
