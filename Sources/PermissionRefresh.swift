import AppKit

func observePermissionChanges(
    center: NotificationCenter = NSWorkspace.shared.notificationCenter,
    bundleIdentifier: @escaping (Notification) -> String? = {
        ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    },
    needsRefresh: @escaping () -> Bool,
    scheduleRetry: @escaping (@escaping () -> Void) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: $0)
    },
    refresh: @escaping () -> Void
) -> [NSObjectProtocol] {
    return [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map {
        name in
        center.addObserver(forName: name, object: nil, queue: .main) { notification in
            guard
                notification.name == NSWorkspace.didActivateApplicationNotification
                    || bundleIdentifier(notification) == "com.apple.systempreferences",
                needsRefresh()
            else { return }
            refresh()
            guard needsRefresh() else { return }
            // Settings may apply consent just after the app-switch notification.
            scheduleRetry {
                if needsRefresh() {
                    refresh()
                }
            }
        }
    }
}
