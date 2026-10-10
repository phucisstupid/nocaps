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
}
