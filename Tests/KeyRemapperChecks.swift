import AppKit
import Carbon

func runKeyRemapperChecks() {
    let source = CGEventSource(stateID: .privateState)
    let syntheticControl: CGEventFlags = [.maskControl, CGEventFlags(rawValue: 1)]
    let chordFlags = syntheticControl.union(.maskShift)
    let marker: Int64 = 0x4E6F_4361_7073

    func event(_ key: Int, type: CGEventType, flags: CGEventFlags) -> CGEvent {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true) else {
            fatalError("Could not create an in-memory keyboard event")
        }
        event.type = type
        event.flags = flags
        return event
    }

    let chord = event(kVK_ANSI_A, type: .keyDown, flags: .maskShift)
    KeyRemapper.applyControl(to: chord, holdingControl: false)
    assert(chord.flags == .maskShift)
    KeyRemapper.applyControl(to: chord, holdingControl: true)
    assert(chord.flags == chordFlags)

    for key in [kVK_Control, kVK_RightControl] {
        let release = event(key, type: .flagsChanged, flags: .maskShift)
        assert(!KeyRemapper.isModifierDown(release))
        KeyRemapper.applyControl(to: release, holdingControl: true)
        assert(release.flags == chordFlags)
    }

    var down: [CGEvent] = []
    KeyRemapper.emitEvents(
        for: .controlDown, flags: .maskShift,
        physicalFlags: {
            assertionFailure("Pressing synthetic Control must not read physical flags")
            return []
        }, source: source, emit: { down.append($0) }
    )
    assert(down.count == 1 && down[0].type == .flagsChanged)
    assert(down[0].getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Control))
    assert(down[0].flags == chordFlags)
    assert(down[0].getIntegerValueField(.eventSourceUserData) == marker)

    for physical in [
        CGEventFlags(), .maskShift,
        [.maskShift, .maskControl, CGEventFlags(rawValue: 1)],
        [.maskShift, .maskControl, CGEventFlags(rawValue: 0x2000)],
    ] {
        var reads = 0
        var up: [CGEvent] = []
        KeyRemapper.emitEvents(
            for: .controlUp, flags: chordFlags,
            physicalFlags: {
                reads += 1
                return physical
            }, source: source, emit: { up.append($0) }
        )
        assert(reads == 1)
        assert(up.count == 1 && up[0].type == .flagsChanged)
        assert(up[0].getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Control))
        assert(up[0].flags == physical)
        assert(up[0].getIntegerValueField(.eventSourceUserData) == marker)
    }

    var escape: [CGEvent] = []
    KeyRemapper.emitEvents(
        for: .escape, flags: [.maskShift, .maskAlternate],
        physicalFlags: {
            assertionFailure("Escape must not read physical flags")
            return []
        }, source: source, emit: { escape.append($0) }
    )
    assert(escape.map(\.type) == [.keyDown, .keyUp])
    for event in escape {
        assert(event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape))
        assert(event.flags == [.maskShift, .maskAlternate])
        assert(event.getIntegerValueField(.eventSourceUserData) == marker)
    }
    print("Control flag preservation and in-memory synthetic events passed")
    do {
        try checkControlCleanup()
    } catch {
        fatalError("Control cleanup check failed: \(error)")
    }
}

private struct SimulatedRestoreFailure: Error {}

private func checkControlCleanup() throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent("nocaps-control-cleanup-\(UUID().uuidString)")
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: directory) }
    var held = KeyBehavior()
    _ = held.press(at: 0)
    assert(held.promote() == [.controlDown])
    let caps: KeyboardMapping.Entry = [
        KeyboardMapping.sourceKey: KeyboardMapping.capsUsage,
        KeyboardMapping.destinationKey: 0x7_0000_0004,
    ]

    func checkRelease(_ action: KeyAction, _ event: CGEvent) {
        assert(action == .controlUp)
        assert(event.type == .flagsChanged)
        assert(event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Control))
    }

    for failRestore in [false, true] {
        let journalURL = directory.appendingPathComponent("restore-\(failRestore).plist")
        var actions: [KeyAction] = []
        var current = [caps]
        var restoring = false
        var readFailure = failRestore
        let keyboard = KeyboardMapping.Keyboard(
            id: "test",
            readMappings: {
                if restoring {
                    assert(actions == [.controlUp])
                    if readFailure { throw SimulatedRestoreFailure() }
                }
                return current
            },
            writeMappings: {
                if restoring { assert(actions == [.controlUp]) }
                current = $0
            }
        )
        let mapping = KeyboardMapping(journalURL: journalURL, keyboards: { [keyboard] })
        _ = try mapping.apply()
        let remapper = KeyRemapper(
            mapping: mapping, behavior: held,
            eventCollector: {
                checkRelease($0, $1)
                actions.append($0)
            }
        )
        restoring = true
        if failRestore {
            do {
                try remapper.stop()
                assertionFailure("Expected restoration to fail after Control was released")
            } catch is SimulatedRestoreFailure {}
            assert(files.fileExists(atPath: journalURL.path))
        } else {
            try remapper.stop()
        }
        assert(actions == [.controlUp])
        readFailure = false
        try remapper.stop()
        assert(actions == [.controlUp])
        assert(current == [caps])
        assert(!files.fileExists(atPath: journalURL.path))
    }

    for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
        var actions: [KeyAction] = []
        let mapping = KeyboardMapping(journalURL: directory.appendingPathComponent("disabled.plist"), keyboards: { [] })
        let remapper = KeyRemapper(
            mapping: mapping, behavior: held,
            eventCollector: {
                checkRelease($0, $1)
                actions.append($0)
            }
        )
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_F20), keyDown: true) else {
            fatalError("Could not create an in-memory tap-disabled event")
        }
        let returned = remapper.handle(proxy: nil, type: type, event: event)
        assert(returned?.takeUnretainedValue() === event)
        assert(actions == [.controlUp])
        _ = remapper.handle(proxy: nil, type: type, event: event)
        try remapper.stop()
        assert(actions == [.controlUp])
    }
    print("Control cleanup: stop before restore, failed restore, and both tap-disabled paths passed")
}
