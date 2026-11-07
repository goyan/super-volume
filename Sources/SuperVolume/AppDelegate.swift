import AppKit
import ServiceManagement
import Sparkle

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/goyan/super-volume")!
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let tap = KeyTap()
    private let hud = HUD()
    private var retryTimer: Timer?

    /// Mises à jour automatiques via Sparkle (flux : appcast.xml de la dernière release GitHub).
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "SuperVolume")
        statusItem.button?.toolTip = "SuperVolume"
        menu.delegate = self
        // Un NSMenu vide au moment du clic peut ne rien afficher : on le remplit dès maintenant.
        rebuildMenu()
        statusItem.menu = menu

        tap.handler = { [weak self] key, mods in self?.handleKey(key, mods) ?? false }
        startTap()
    }

    // MARK: - Tap & permission

    private func startTap() {
        if tap.start() { return }
        // Permission Accessibilité absente : on la demande, puis on réessaie jusqu'à son octroi.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if self?.tap.start() == true { timer.invalidate() }
        }
    }

    private func handleKey(_ key: VolumeKey, _ mods: NSEvent.ModifierFlags) -> Bool {
        guard enabled, VolumeController.shared.shouldIntercept() else { return false }
        let fine = mods.contains(.option) && mods.contains(.shift)
        let controller = VolumeController.shared
        controller.queue.async { [weak self] in
            guard let result = controller.press(key, fine: fine) else { return }
            DispatchQueue.main.async { self?.hud.show(level: result.level, muted: result.muted) }
        }
        return true
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        menu.removeAllItems()
        let controller = VolumeController.shared

        // 1. Sortie actuellement pilotée
        if let t = controller.resolveTarget() {
            let state: String
            if !t.overridden && Audio.canSetVolume(t.dev) {
                state = "volume natif macOS (non intercepté)"
            } else if controller.controlled(for: t.dev, overridden: t.overridden).isEmpty {
                state = "aucun volume réglable"
            } else {
                state = "piloté par SuperVolume"
            }
            addDisabled((t.overridden ? "Sortie forcée : " : "Sortie active : ") + t.dev.name)
            addDisabled("→ " + state)
        } else {
            addDisabled("Aucune sortie audio")
        }

        // 2. Choix de la sortie : suivre l'active ou forcer un périphérique
        menu.addItem(.separator())
        addDisabled("Sortie à piloter")
        let override = controller.overrideUID
        let outputs = Audio.outputDevices()
        let follow = NSMenuItem(title: "Suivre la sortie active du Mac", action: #selector(chooseFollow), keyEquivalent: "")
        follow.target = self
        let overrideAvailable = override.map { uid in outputs.contains { $0.uid == uid } } ?? false
        follow.state = overrideAvailable ? .off : .on
        menu.addItem(follow)
        for dev in outputs {
            let item = NSMenuItem(title: dev.name, action: #selector(chooseOutput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = dev.uid
            item.indentationLevel = 1
            item.state = (overrideAvailable && dev.uid == override) ? .on : .off
            menu.addItem(item)
        }

        // 3. Sous-périphériques (si la cible est un multi-sortie / agrégat)
        if let t = controller.resolveTarget() {
            let subs = Audio.subDevices(of: t.dev).filter { Audio.canSetVolume($0) }
            if !subs.isEmpty {
                menu.addItem(.separator())
                addDisabled("Sous-périphériques pilotés")
                let excluded = controller.excludedUIDs
                for sub in subs {
                    let item = NSMenuItem(title: sub.name, action: #selector(toggleSub(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = sub.uid
                    item.indentationLevel = 1
                    item.state = excluded.contains(sub.uid) ? .off : .on
                    menu.addItem(item)
                }
            }
        }

        // 4. Réglages
        menu.addItem(.separator())
        let enable = NSMenuItem(title: "Activer SuperVolume", action: #selector(toggleEnabled), keyEquivalent: "")
        enable.target = self
        enable.state = enabled ? .on : .off
        menu.addItem(enable)

        let login = NSMenuItem(title: "Lancer au démarrage", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if !tap.isRunning {
            let perm = NSMenuItem(title: "⚠︎ Autoriser l'Accessibilité…", action: #selector(openAccessibility), keyEquivalent: "")
            perm.target = self
            menu.addItem(perm)
        }

        // 5. Mises à jour, à propos, quitter
        menu.addItem(.separator())
        let check = NSMenuItem(title: "Rechercher des mises à jour…",
                               action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        check.target = updater
        menu.addItem(check)

        let about = NSMenuItem(title: "À propos de SuperVolume", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem(title: "Quitter SuperVolume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func chooseFollow() { VolumeController.shared.overrideUID = nil }

    @objc private func chooseOutput(_ sender: NSMenuItem) {
        VolumeController.shared.overrideUID = sender.representedObject as? String
    }

    @objc private func toggleSub(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        var set = VolumeController.shared.excludedUIDs
        if set.contains(uid) { set.remove(uid) } else { set.insert(uid) }
        VolumeController.shared.excludedUIDs = set
    }

    @objc private func toggleEnabled() { enabled.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Impossible de modifier le lancement au démarrage"
            alert.informativeText = "\(error.localizedDescription)\n\nL'app doit être dans /Applications."
            alert.runModal()
        }
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(
            string: "Pilote le volume des sorties audio sans volume natif (multi-sortie, BlackHole…) avec les touches du clavier.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        )
        credits.append(NSAttributedString(
            string: "github.com/goyan/super-volume",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: AppInfo.repoURL]
        ))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "SuperVolume",
            .credits: credits,
        ])
    }
}
