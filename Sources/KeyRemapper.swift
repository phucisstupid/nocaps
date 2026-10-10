import AppKit
import Carbon

final class KeyRemapper {
    private let mapping = KeyboardMapping()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdTimer: Timer?
    private var behavior = KeyBehavior()
    private let eventSource = CGEventSource(stateID: .privateState)
    private let marker: Int64 = 0x4E6F_4361_7073
    private let leftControlFlag = CGEventFlags(rawValue: 1)
    private var acceptingInput = false
    private var accessRefreshPending = false
    var onAccessChanged: (() -> Void)?

    var isRunning: Bool {
        tap != nil
    }

    func recoverMapping() throws {
        try mapping.restore()
    }

    func monitorKeyboards(_ callback: @escaping () -> Void) {
        mapping.onKeyboardsChanged = { [weak self] topologyChanged in
            if topologyChanged {
                self?.cancelPress()
            }
            callback()
        }
        mapping.startMonitoring()
    }

    func verifyMapping() throws {
        try mapping.verify()
    }

    func start() throws -> Int {
        if tap == nil {
            guard !physicalFlags().contains(.maskAlphaShift) else {
                throw NoCapsError("Turn Caps Lock off before enabling NoCaps.")
            }
            let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
            let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            guard
                let newTap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                    eventsOfInterest: mask,
                    callback: { proxy, type, event, pointer in
                        guard let pointer else { return Unmanaged.passUnretained(event) }
                        return Unmanaged<KeyRemapper>.fromOpaque(pointer).takeUnretainedValue()
                            .handle(proxy: proxy, type: type, event: event)
                    }, userInfo: Unmanaged.passUnretained(self).toOpaque()
                )
            else {
                throw NoCapsError("Allow NoCaps in Accessibility settings, then try again.")
            }
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
                CFMachPortInvalidate(newTap)
                throw NoCapsError("macOS could not start the keyboard event listener.")
            }
            tap = newTap
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        let count = try mapping.apply()
        acceptingInput = true
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return count
    }

    func stop() throws {
        acceptingInput = false
        cancelPress()
        // Keep the listener if restoration fails, but always release virtual Control.
        try mapping.restore()
        if let tap {
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelPress()
            if acceptingInput, let tap, CGPreflightPostEventAccess(), !IsSecureEventInputEnabled() {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            refreshAccess()
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == marker {
            return Unmanaged.passUnretained(event)
        }
        guard acceptingInput, Self.needsHandling(type: type, event: event, capsPressed: behavior.isPressed) else {
            return Unmanaged.passUnretained(event)
        }
        if IsSecureEventInputEnabled() || !CGPreflightPostEventAccess() {
            acceptingInput = false
            cancelPress()
            refreshAccess()
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let time = TimeInterval(event.timestamp) / 1_000_000_000
        // shortcut: F20 is reserved while enabled; use a virtual HID device if F20 support is needed.
        if type == .keyDown || type == .keyUp,
            event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_F20)
        {
            if type == .keyDown {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0, !behavior.isPressed {
                    send(behavior.press(at: time), flags: flags, proxy: proxy)
                    let timer = Timer(timeInterval: KeyBehavior.holdDelay, repeats: false) { [weak self] _ in
                        guard let self, acceptingInput else { return }
                        guard !IsSecureEventInputEnabled(), CGPreflightPostEventAccess() else {
                            acceptingInput = false
                            cancelPress()
                            refreshAccess()
                            return
                        }
                        send(behavior.promote(), flags: physicalFlags(), proxy: nil)
                    }
                    holdTimer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            } else {
                holdTimer?.invalidate()
                holdTimer = nil
                send(behavior.release(at: time), flags: flags, proxy: proxy)
            }
            return nil
        }

        if type == .keyDown
            || (type == .flagsChanged && Self.isModifierDown(event))
        {
            holdTimer?.invalidate()
            holdTimer = nil
            send(behavior.promote(), flags: flags, proxy: proxy)
        }
        if behavior.isHoldingControl {
            event.flags.formUnion([.maskControl, leftControlFlag])
        }
        return Unmanaged.passUnretained(event)
    }

    static func needsHandling(type: CGEventType, event: CGEvent, capsPressed: Bool) -> Bool {
        capsPressed
            || ((type == .keyDown || type == .keyUp)
                && event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_F20))
    }

    private func refreshAccess() {
        guard !accessRefreshPending else { return }
        accessRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            accessRefreshPending = false
            onAccessChanged?()
        }
    }

    private func cancelPress() {
        holdTimer?.invalidate()
        holdTimer = nil
        send(behavior.reset(), flags: physicalFlags(), proxy: nil)
    }

    private func physicalFlags() -> CGEventFlags {
        CGEventSource.flagsState(.hidSystemState)
    }

    static func isModifierDown(_ event: CGEvent) -> Bool {
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let bit: UInt64
        switch key {
        case kVK_Control: bit = 0x1
        case kVK_RightControl: bit = 0x2000
        case kVK_Shift: bit = 0x2
        case kVK_RightShift: bit = 0x4
        case kVK_Command: bit = 0x8
        case kVK_RightCommand: bit = 0x10
        case kVK_Option: bit = 0x20
        case kVK_RightOption: bit = 0x40
        case kVK_Function: bit = CGEventFlags.maskSecondaryFn.rawValue
        case kVK_CapsLock: bit = CGEventFlags.maskAlphaShift.rawValue
        default: return false
        }
        return event.flags.rawValue & bit != 0
    }

    private func send(_ actions: [KeyAction], flags: CGEventFlags, proxy: CGEventTapProxy?) {
        for action in actions {
            switch action {
            case .controlDown, .controlUp:
                var controlFlags = action == .controlUp ? physicalFlags() : flags
                if action == .controlDown {
                    controlFlags.formUnion([.maskControl, leftControlFlag])
                }
                post(
                    key: CGKeyCode(kVK_Control),
                    down: action == .controlDown,
                    flags: controlFlags,
                    type: .flagsChanged,
                    proxy: proxy
                )
            case .escape:
                post(key: CGKeyCode(kVK_Escape), down: true, flags: flags, type: .keyDown, proxy: proxy)
                post(key: CGKeyCode(kVK_Escape), down: false, flags: flags, type: .keyUp, proxy: proxy)
            }
        }
    }

    private func post(key: CGKeyCode, down: Bool, flags: CGEventFlags, type: CGEventType, proxy: CGEventTapProxy?) {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: down) else { return }
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }
}

struct NoCapsError: LocalizedError {
    let message: String
    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
