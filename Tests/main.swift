import AppKit
import Carbon

checkSessionState()

var key = KeyBehavior()
assert(!key.isPressed && !key.isHoldingControl)
assert(key.release(at: 0) == [])
assert(key.promote() == [])

// A tap emits Escape only when Caps Lock is released.
assert(key.press(at: 0) == [])
assert(key.isPressed && !key.isHoldingControl)
assert(key.release(at: 0.05) == [.escape])
assert(!key.isPressed)

// The threshold is a hold, even if its timer has not run yet.
assert(key.press(at: 0) == [])
assert(key.release(at: KeyBehavior.holdDelay) == [.controlDown, .controlUp])
assert(key.press(at: 0) == [])
assert(key.release(at: 1) == [.controlDown, .controlUp])

// A timer or another input promotes a pending press to Control immediately.
assert(key.press(at: 0) == [])
assert(key.promote() == [.controlDown])
assert(key.isPressed && key.isHoldingControl)
assert(key.promote() == [])
assert(key.release(at: 0.01) == [.controlUp])
assert(!key.isPressed && !key.isHoldingControl)

// Repeated presses cannot change the initial timestamp or release held Control.
assert(key.press(at: 0) == [])
assert(key.press(at: 0.17) == [])
assert(key.release(at: 0.2) == [.controlDown, .controlUp])
assert(key.press(at: 0) == [])
assert(key.promote() == [.controlDown])
assert(key.press(at: 0.1) == [])
assert(key.release(at: 0.2) == [.controlUp])

// Disabling or losing the event tap cancels Escape and releases held Control.
assert(key.press(at: 0) == [])
assert(key.reset() == [])
assert(key.release(at: 0.05) == [])
assert(key.press(at: 0) == [])
assert(key.promote() == [.controlDown])
assert(key.reset() == [.controlUp])
assert(!key.isPressed && !key.isHoldingControl)
assert(key.reset() == [])
assert(key.release(at: 0.05) == [])

let source = "HIDKeyboardModifierMappingSrc"
let destination = "HIDKeyboardModifierMappingDst"
let caps: KeyboardMapping.Entry = [source: KeyboardMapping.capsUsage, destination: 0x7_0000_0004]
let unrelated: KeyboardMapping.Entry = [source: 0x7_0000_00E3, destination: 0x7_0000_00E0, "vendor": 99]
let owned: KeyboardMapping.Entry = [source: KeyboardMapping.capsUsage, destination: KeyboardMapping.reservedUsage]

let installed = try KeyboardMapping.installing(in: [caps, unrelated])
assert(installed == [unrelated, owned])
let installedWithoutPreviousCaps = try KeyboardMapping.installing(in: [unrelated])
assert(installedWithoutPreviousCaps == [unrelated, owned])
let restored = try KeyboardMapping.restoring(in: installed, originalCaps: [caps])
assert(restored == [unrelated, caps])
let restoredWithoutPreviousCaps = try KeyboardMapping.restoring(in: installed, originalCaps: [])
assert(restoredWithoutPreviousCaps == [unrelated])

let externallyChanged = [unrelated, caps]
let restoredAfterExternalChange = try KeyboardMapping.restoring(in: externallyChanged, originalCaps: [])
assert(restoredAfterExternalChange == externallyChanged)
let restoredAfterExternalRemoval = try KeyboardMapping.restoring(in: [unrelated], originalCaps: [caps])
assert(restoredAfterExternalRemoval == [unrelated])

func expectMappingError(_ operation: () throws -> [KeyboardMapping.Entry]) {
    do {
        _ = try operation()
        assertionFailure("Expected a malformed mapping or reserved-key collision to fail")
    } catch {}
}

expectMappingError { try KeyboardMapping.installing(in: [[source: KeyboardMapping.capsUsage]]) }
expectMappingError { try KeyboardMapping.installing(in: [[destination: 0x7_0000_0004]]) }
expectMappingError {
    try KeyboardMapping.installing(in: [
        [
            source: KeyboardMapping.reservedUsage,
            destination: 0x7_0000_0004,
        ]
    ])
}
expectMappingError {
    try KeyboardMapping.installing(in: [
        [
            source: 0x7_0000_0004,
            destination: KeyboardMapping.reservedUsage,
        ]
    ])
}
expectMappingError { try KeyboardMapping.restoring(in: [[source: KeyboardMapping.capsUsage]], originalCaps: []) }

print("KeyBehavior and KeyboardMapping: all checks passed")

func modifierEvent(_ keyCode: Int, flags: CGEventFlags) -> CGEvent {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else {
        fatalError("Could not create an in-memory keyboard event")
    }
    event.type = .flagsChanged
    event.flags = flags
    return event
}

/// Generic flags stay set when the modifier on the other side remains pressed.
let modifiers: [(Int, UInt64, UInt64, CGEventFlags)] = [
    (kVK_Shift, 0x2, 0x4, .maskShift),
    (kVK_RightShift, 0x4, 0x2, .maskShift),
    (kVK_Control, 0x1, 0x2000, .maskControl),
    (kVK_RightControl, 0x2000, 0x1, .maskControl),
    (kVK_Command, 0x8, 0x10, .maskCommand),
    (kVK_RightCommand, 0x10, 0x8, .maskCommand),
    (kVK_Option, 0x20, 0x40, .maskAlternate),
    (kVK_RightOption, 0x40, 0x20, .maskAlternate),
]
for (keyCode, pressedBit, otherBit, genericFlag) in modifiers {
    let down = modifierEvent(keyCode, flags: CGEventFlags(rawValue: pressedBit | genericFlag.rawValue))
    let up = modifierEvent(keyCode, flags: CGEventFlags(rawValue: otherBit | genericFlag.rawValue))
    assert(KeyRemapper.isModifierDown(down))
    assert(!KeyRemapper.isModifierDown(up))

    var pendingCaps = KeyBehavior()
    _ = pendingCaps.press(at: 0)
    if KeyRemapper.isModifierDown(up) {
        _ = pendingCaps.promote()
    }
    assert(!pendingCaps.isHoldingControl)
    assert(pendingCaps.release(at: 0.05) == [.escape])
}

assert(KeyRemapper.isModifierDown(modifierEvent(kVK_Function, flags: .maskSecondaryFn)))
assert(!KeyRemapper.isModifierDown(modifierEvent(kVK_Function, flags: [])))
assert(!KeyRemapper.isModifierDown(modifierEvent(kVK_ANSI_A, flags: .maskShift)))
print("Modifier events: left/right Shift, Control, Command, Option, Fn, and modifier-release Caps taps passed")

let ordinaryKey = modifierEvent(kVK_ANSI_A, flags: [])
let capsKey = modifierEvent(kVK_F20, flags: [])
assert(!KeyRemapper.needsHandling(type: .keyDown, event: ordinaryKey, capsPressed: false))
assert(!KeyRemapper.needsHandling(type: .keyUp, event: ordinaryKey, capsPressed: false))
assert(!KeyRemapper.needsHandling(type: .flagsChanged, event: capsKey, capsPressed: false))
assert(KeyRemapper.needsHandling(type: .keyDown, event: capsKey, capsPressed: false))
assert(KeyRemapper.needsHandling(type: .keyUp, event: capsKey, capsPressed: false))
assert(KeyRemapper.needsHandling(type: .keyDown, event: ordinaryKey, capsPressed: true))
assert(KeyRemapper.needsHandling(type: .keyUp, event: ordinaryKey, capsPressed: true))
assert(KeyRemapper.needsHandling(type: .flagsChanged, event: ordinaryKey, capsPressed: true))

try KeyboardMapping.verify(in: [unrelated, owned])
for conflicting in [
    [unrelated],
    [unrelated, caps],
    [owned, [source: KeyboardMapping.reservedUsage, destination: 0x7_0000_0004]],
    [owned, [source: 0x7_0000_0004, destination: KeyboardMapping.reservedUsage]],
    [owned, [source: 0x7_0000_0004]],
] {
    do {
        try KeyboardMapping.verify(in: conflicting)
        assertionFailure("Expected an external mapping change to fail verification")
    } catch {}
}
print("Idle keyboard filtering and active mapping-conflict checks passed")

try checkKeyboardMappingRecovery()
runKeyRemapperChecks()
