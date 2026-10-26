#pragma once

class ControlState {
public:
    bool physicalLeftDown = false;
    bool syntheticLeftDown = false;

    bool press() {
        if (physicalLeftDown || syntheticLeftDown) return false;
        syntheticLeftDown = true;
        return true;
    }

    bool needsRelease() const { return syntheticLeftDown && !physicalLeftDown; }

    void released() { syntheticLeftDown = false; }

    bool physicalEvent(bool down, bool capsHolding) {
        physicalLeftDown = down;
        if (!down && capsHolding) {
            // Suppress physical key-up until Caps releases its share of Control.
            syntheticLeftDown = true;
            return true;
        }
        return false;
    }
};
