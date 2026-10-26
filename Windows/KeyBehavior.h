#pragma once

#include <array>
#include <cstdint>

enum class KeyAction { none, controlDown, controlUp, escape };
using KeyActions = std::array<KeyAction, 2>;

class KeyBehavior {
public:
    static constexpr std::uint64_t holdDelay = 180;

    bool isPressed() const { return state_ != State::idle; }
    bool isHoldingControl() const { return state_ == State::holding; }

    KeyActions press(std::uint64_t time) {
        if (!isPressed()) {
            state_ = State::pending;
            pressedAt_ = time;
        }
        return {};
    }

    KeyActions promote() {
        if (state_ != State::pending) return {};
        state_ = State::holding;
        return {KeyAction::controlDown};
    }

    KeyActions release(std::uint64_t time) {
        const auto previous = state_;
        state_ = State::idle;
        if (previous == State::holding) return {KeyAction::controlUp};
        if (previous == State::pending) {
            if (time - pressedAt_ < holdDelay) return {KeyAction::escape};
            return {KeyAction::controlDown, KeyAction::controlUp};
        }
        return {};
    }

    KeyActions reset() {
        const bool holding = isHoldingControl();
        state_ = State::idle;
        return holding ? KeyActions{KeyAction::controlUp} : KeyActions{};
    }

private:
    enum class State { idle, pending, holding };
    State state_ = State::idle;
    std::uint64_t pressedAt_ = 0;
};
