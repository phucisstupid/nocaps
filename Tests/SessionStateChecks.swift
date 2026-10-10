import CoreGraphics

func checkSessionState() {
    let active = [kCGSessionOnConsoleKey as String: true] as CFDictionary
    let inactive = [kCGSessionOnConsoleKey as String: false] as CFDictionary
    var session = SessionState()
    assert(!session.isActive)
    session.resume(from: inactive)
    assert(!session.isActive)

    session.resume(from: active)
    assert(session.isActive)
    session.suspend()  // Switch away, then sleep and wake while another user stays active.
    session.suspend()
    session.resume(from: inactive)
    assert(!session.isActive)
    session.resume(from: active)
    assert(session.isActive)
    session.suspend()
    assert(!session.isActive)
    session.resume(from: active)
    assert(session.isActive)

    session.resume(from: nil)
    assert(!session.isActive)
    session.resume(from: [:] as CFDictionary)
    assert(!session.isActive)
    session.resume(from: [kCGSessionOnConsoleKey as String: "unknown"] as CFDictionary)
    assert(!session.isActive)
    print("Session state: inactive startup, sleep/wake, switching, and missing state passed")
}
