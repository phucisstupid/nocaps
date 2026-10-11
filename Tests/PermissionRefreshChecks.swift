import AppKit

func checkPermissionRefresh() {
    var access = PermissionAccess(isGranted: false)
    assert(!access.isGranted && !access.needsRestart)
    access.update(false)
    assert(!access.isGranted && !access.needsRestart)
    access.update(true)
    assert(access.isGranted && access.needsRestart)
    access.update(true)
    assert(access.isGranted && access.needsRestart)
    access.update(false)
    assert(!access.isGranted && access.needsRestart)
    access.update(true)
    assert(access.isGranted && access.needsRestart)
    access = PermissionAccess(isGranted: true)
    assert(access.isGranted && !access.needsRestart)
    access.update(false)
    assert(!access.isGranted && !access.needsRestart)
    access.update(true)
    assert(access.isGranted && access.needsRestart)

    let center = NotificationCenter()
    var granted = false
    var trusted = false
    var active = true
    var checks = 0
    var clock = 0.0
    var retries: [(deadline: Double, work: () -> Void)] = []
    let observers = observePermissionChanges(
        center: center,
        bundleIdentifier: { $0.userInfo?["bundleIdentifier"] as? String },
        needsRefresh: { !trusted && active },
        scheduleRetry: { retries.append((clock + 1, $0)) },
        refresh: {
            trusted = granted
            checks += 1
        }
    )
    defer { observers.forEach(center.removeObserver) }

    func post(_ name: Notification.Name, app: String? = nil) {
        let userInfo = app.map { ["bundleIdentifier": $0] }
        center.post(name: name, object: nil, userInfo: userInfo)
    }

    assert(checks == 0 && retries.isEmpty)
    post(NSWorkspace.didDeactivateApplicationNotification)
    post(NSWorkspace.didTerminateApplicationNotification, app: "app.nocaps.NoCaps")
    post(NSWorkspace.didTerminateApplicationNotification)
    assert(checks == 0)

    post(NSWorkspace.didActivateApplicationNotification, app: "app.nocaps.NoCaps")
    assert(checks == 1 && !trusted && retries.count == 1)
    clock = 0.95
    post(NSWorkspace.didActivateApplicationNotification, app: "com.apple.systempreferences")
    assert(checks == 2 && retries.map(\.deadline) == [1, 1.95])
    clock = 1
    retries.removeFirst().work()
    assert(checks == 3 && !trusted && retries.count == 1)
    clock = 1.1
    granted = true
    clock = 1.95
    retries.removeFirst().work()
    assert(checks == 4 && trusted && retries.isEmpty)
    post(NSWorkspace.didActivateApplicationNotification, app: "app.nocaps.NoCaps")
    assert(checks == 4 && retries.isEmpty)

    granted = false
    trusted = false
    post(NSWorkspace.didTerminateApplicationNotification, app: "com.apple.systempreferences")
    assert(checks == 5 && !trusted && retries.count == 1)
    granted = true
    post(NSWorkspace.didActivateApplicationNotification, app: "app.nocaps.NoCaps")
    assert(checks == 6 && trusted)
    retries.removeFirst().work()
    assert(checks == 6 && retries.isEmpty)

    trusted = false
    active = false
    post(NSWorkspace.didActivateApplicationNotification, app: "app.nocaps.NoCaps")
    assert(checks == 6 && retries.isEmpty)

    active = true
    granted = false
    post(NSWorkspace.didActivateApplicationNotification, app: "app.nocaps.NoCaps")
    assert(checks == 7 && retries.count == 1)
    retries.removeFirst().work()
    assert(checks == 8 && !trusted && retries.isEmpty)

    post(NSWorkspace.didActivateApplicationNotification, app: "app.nocaps.NoCaps")
    assert(checks == 9 && retries.count == 1)
    active = false
    retries.removeFirst().work()
    assert(checks == 9 && retries.isEmpty)

    print("Permission refresh: restart state, app switching, Settings quit, delayed grants, and bounded retries passed")
}
