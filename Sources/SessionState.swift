import CoreGraphics

struct SessionState {
    private(set) var isActive = false

    mutating func resume(from session: CFDictionary? = CGSessionCopyCurrentDictionary()) {
        isActive = (session as? [String: Any])?[kCGSessionOnConsoleKey as String] as? Bool ?? false
    }

    mutating func suspend() {
        isActive = false
    }
}
