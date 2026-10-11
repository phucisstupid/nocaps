import AppKit
import Carbon
import Darwin
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let remapper = KeyRemapper()
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private var statusItem: NSStatusItem!
    private var status = "Starting…"
    private let toggle = NSMenuItem(title: "Enable NoCaps", action: #selector(toggleEnabled), keyEquivalent: "")
    private let launchAtLogin = NSMenuItem(
        title: "Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )
    private let permissions = NSMenuItem(
        title: "Allow Keyboard Access…",
        action: #selector(openPermissions),
        keyEquivalent: ""
    )
    private let details = NSMenuItem(title: "Show Error…", action: #selector(showLastError), keyEquivalent: "")
    private var timer: Timer?
    private var permissionObservers: [NSObjectProtocol] = []
    private var session = SessionState()
    private var access = PermissionAccess(isGranted: false)
    private var trusted: Bool { access.isGranted }
    private var restartPromptShown = false
    private var restartRequested = false
    private var secureInput = false
    private var cleanupPending = false
    private var keyboardCount = 0
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var lastError: String?

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = Bundle.main.url(forResource: "NoCapsMenu", withExtension: "pdf").flatMap(NSImage.init(contentsOf:))
        icon?.isTemplate = true
        icon?.accessibilityDescription = "NoCaps \(version)"
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "NoCaps \(version)"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "NoCaps \(version)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        toggle.target = self
        menu.addItem(toggle)
        launchAtLogin.target = self
        menu.addItem(launchAtLogin)
        permissions.target = self
        menu.addItem(permissions)
        details.target = self
        menu.addItem(details)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About NoCaps", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit NoCaps", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(self, selector: #selector(suspend), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(resume), name: name, object: nil)
        }
        permissionObservers = observePermissionChanges(
            needsRefresh: { [weak self] in
                guard let self else { return false }
                return !trusted && session.isActive
            },
            refresh: { [weak self] in self?.refresh() }
        )
        session.resume()
        remapper.onAccessChanged = { [weak self] in self?.refresh(keyboardsChanged: true) }
        remapper.monitorKeyboards { [weak self] in self?.refresh(keyboardsChanged: true) }

        do { try remapper.recoverMapping() } catch {
            enabled = false
            lastError = error.localizedDescription
            cleanupPending = true
        }
        access = PermissionAccess(isGranted: CGPreflightPostEventAccess())
        if !trusted {
            openPermissions()
        } else {
            refresh(checkPermission: false)
        }
        updateLoginItem()
    }

    private func refresh(checkPermission: Bool = true, keyboardsChanged: Bool = false) {
        if checkPermission {
            access.update(CGPreflightPostEventAccess())
        }
        secureInput = IsSecureEventInputEnabled()
        do {
            if cleanupPending {
                try remapper.stop()
                cleanupPending = false
            }
            if enabled, trusted, !access.needsRestart, !secureInput, session.isActive {
                if !remapper.isRunning || keyboardsChanged {
                    keyboardCount = try remapper.start()
                }
                status = keyboardCount > 0 ? "Active" : "Waiting for a keyboard"
                lastError = nil
            } else {
                if remapper.isRunning || keyboardsChanged {
                    cleanupPending = true
                    try remapper.stop()
                    cleanupPending = false
                }
                if !enabled {
                    status = lastError == nil ? "Paused" : "Paused — needs attention"
                } else if !trusted {
                    status = "Keyboard access required"
                } else if access.needsRestart {
                    status = "Restart NoCaps to apply keyboard access"
                } else if secureInput {
                    status = "Paused during Secure Input"
                } else {
                    status = "Paused while session is inactive"
                }
            }
        } catch {
            handleError(error)
        }
        updateMenu()
        updateSafetyTimer()
        offerRestart()
    }

    private func pollSafety() {
        if cleanupPending {
            refresh(checkPermission: false)
            return
        }
        let nextTrusted = CGPreflightPostEventAccess()
        let nextSecureInput = IsSecureEventInputEnabled()
        if trusted != nextTrusted || secureInput != nextSecureInput {
            access.update(nextTrusted)
            refresh(checkPermission: false)
            return
        }
        guard remapper.isRunning else { return }
        do { try remapper.verifyMapping() } catch {
            handleError(error)
            updateMenu()
            updateSafetyTimer()
        }
    }

    private func updateSafetyTimer() {
        guard session.isActive, cleanupPending || (enabled && trusted && !access.needsRestart) else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.pollSafety() }
        timer.tolerance = 0.1
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handleError(_ error: Error) {
        enabled = false
        UserDefaults.standard.set(false, forKey: "enabled")
        lastError = error.localizedDescription
        status = "Paused — needs attention"
        cleanupPending = true
        // A partial install must be restored before removing the event listener.
        do {
            try remapper.stop()
            cleanupPending = false
        } catch {}
    }

    private func updateMenu() {
        toggle.state = enabled ? .on : .off
        permissions.isHidden = trusted && !access.needsRestart
        permissions.title = trusted ? "Restart NoCaps…" : "Allow Keyboard Access…"
        permissions.action = trusted ? #selector(restartNoCaps) : #selector(openPermissions)
        details.isHidden = lastError == nil
        statusItem.button?.appearsDisabled = status != "Active"
        statusItem.button?.toolTip = lastError ?? "NoCaps \(version) — \(status.lowercased())"
    }

    private func updateLoginItem() {
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin.state = loginStatus == .enabled ? .on : .off
        launchAtLogin.title =
            loginStatus == .requiresApproval ? "Launch at Login — Allow in Settings…" : "Launch at Login"
    }

    func menuWillOpen(_: NSMenu) {
        refresh(keyboardsChanged: true)
        updateLoginItem()
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        lastError = nil
        UserDefaults.standard.set(enabled, forKey: "enabled")
        access.update(CGPreflightPostEventAccess())
        if enabled, !trusted {
            openPermissions()
        } else {
            refresh(checkPermission: false)
        }
        if let lastError {
            showError(lastError)
        }
    }

    @objc private func openPermissions() {
        access.update(CGPreflightPostEventAccess())
        if trusted {
            refresh(checkPermission: false)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        _ = CGRequestPostEventAccess()
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        refresh()
        if !trusted,
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                showError("Could not change Launch at Login. \(error.localizedDescription)")
            }
        }
        updateLoginItem()
    }

    @objc private func suspend() {
        session.suspend()
        refresh()
    }

    @objc private func resume() {
        session.resume()
        refresh()
    }

    @objc private func openAbout() {
        if let url = URL(string: "https://github.com/phucisstupid/nocaps") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func offerRestart() {
        guard access.needsRestart, trusted, session.isActive, !restartPromptShown else { return }
        restartPromptShown = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard trusted, session.isActive else {
                restartPromptShown = false
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Restart NoCaps"
            alert.informativeText = "Keyboard access has been granted. Restart NoCaps to apply it."
            alert.addButton(withTitle: "Restart NoCaps")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                restartNoCaps()
            }
        }
    }

    @objc private func restartNoCaps() {
        restartRequested = true
        NSApp.terminate(nil)
    }

    @objc private func showLastError() {
        if let lastError {
            showError(lastError)
        }
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        do {
            try remapper.stop()
            if restartRequested {
                do {
                    try restartAppAfterExit(
                        of: ProcessInfo.processInfo.processIdentifier, bundleURL: Bundle.main.bundleURL)
                } catch {
                    restartRequested = false
                    showError("NoCaps could not restart. \(error.localizedDescription)")
                    refresh(checkPermission: false)
                    return .terminateCancel
                }
            }
            return .terminateNow
        } catch {
            restartRequested = false
            handleError(error)
            updateMenu()
            updateSafetyTimer()
            showError(
                "Caps Lock could not be restored. \(error.localizedDescription)\nTry quitting again, or restart your Mac to clear the temporary remap."
            )
            return .terminateCancel
        }
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "NoCaps needs attention"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

let app = NSApplication.shared
if let bundleID = Bundle.main.bundleIdentifier,
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
{
    exit(0)
}

app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
