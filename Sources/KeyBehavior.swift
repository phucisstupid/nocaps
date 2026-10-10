import Foundation

enum KeyAction: Equatable {
    case controlDown, controlUp, escape
}

struct KeyBehavior {
    static let holdDelay: TimeInterval = 0.18

    private enum State {
        case idle
        case pending(TimeInterval)
        case holding
    }

    private var state = State.idle

    var isPressed: Bool {
        if case .idle = state {
            return false
        }
        return true
    }

    var isHoldingControl: Bool {
        if case .holding = state {
            return true
        }
        return false
    }

    mutating func press(at time: TimeInterval) -> [KeyAction] {
        guard !isPressed else { return [] }
        state = .pending(time)
        return []
    }

    mutating func promote() -> [KeyAction] {
        guard case .pending = state else { return [] }
        state = .holding
        return [.controlDown]
    }

    mutating func release(at time: TimeInterval) -> [KeyAction] {
        let previous = state
        state = .idle
        switch previous {
        case .idle: return []
        case .pending(let pressedAt):
            return time - pressedAt < Self.holdDelay ? [.escape] : [.controlDown, .controlUp]
        case .holding: return [.controlUp]
        }
    }

    mutating func reset() -> [KeyAction] {
        let actions: [KeyAction] = isHoldingControl ? [.controlUp] : []
        state = .idle
        return actions
    }
}
