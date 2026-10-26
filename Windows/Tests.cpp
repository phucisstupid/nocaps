#include "ControlState.h"
#include "KeyBehavior.h"

#include <cassert>
#include <cstdio>

#ifdef NDEBUG
#error Build these checks with assertions enabled.
#endif

static void expect(KeyActions actions, KeyAction first = KeyAction::none,
                   KeyAction second = KeyAction::none) {
    assert(actions[0] == first && actions[1] == second);
}

static void checkControlOwnership() {
    ControlState control;
    assert(!control.physicalLeftDown && !control.syntheticLeftDown);
    assert(!control.needsRelease());
    assert(control.press());
    assert(control.syntheticLeftDown && control.needsRelease());
    assert(!control.press());
    // A failed injection leaves ownership pending for the next cleanup attempt.
    assert(control.needsRelease() && control.syntheticLeftDown);
    control.released();
    assert(!control.needsRelease() && !control.syntheticLeftDown);

    // Caps neither duplicates nor releases a physical left Control already held.
    assert(!control.physicalEvent(true, false));
    assert(control.physicalLeftDown && !control.press());
    assert(!control.needsRelease());
    control.released();
    assert(control.physicalLeftDown);
    assert(!control.physicalEvent(false, false));
    assert(!control.physicalLeftDown && !control.syntheticLeftDown);

    // Releasing physical Control during a Caps hold transfers ownership to Caps.
    assert(!control.physicalEvent(true, false));
    assert(!control.press());
    assert(control.physicalEvent(false, true));
    assert(!control.physicalLeftDown && control.syntheticLeftDown);
    assert(control.needsRelease());
    control.released();

    assert(control.press());
    assert(!control.physicalEvent(true, true));
    assert(control.physicalEvent(false, true));
    assert(control.needsRelease());
    control.released();

    // Physical Control pressed during a synthetic hold survives Caps cleanup.
    assert(control.press());
    assert(!control.physicalEvent(true, true));
    assert(!control.needsRelease());
    control.released();
    assert(control.physicalLeftDown && !control.syntheticLeftDown);
    assert(!control.physicalEvent(false, false));

    // Resetting tap/hold behavior must not forget an unsuccessful Control-up.
    KeyBehavior caps;
    expect(caps.press(0));
    expect(caps.promote(), KeyAction::controlDown);
    assert(control.press());
    expect(caps.reset(), KeyAction::controlUp);
    expect(caps.reset());
    assert(control.needsRelease());
    control.released();
    assert(!control.needsRelease());

    expect(caps.press(1000));
    expect(caps.promote(), KeyAction::controlDown);
    assert(!control.physicalEvent(true, true));
    assert(!control.press());
    expect(caps.reset(), KeyAction::controlUp);
    control.released();
    assert(control.physicalLeftDown);
    assert(!control.physicalEvent(false, false));

    std::puts("Windows ControlState: physical ownership, takeover, and failed cleanup passed");
}

int main() {
    checkControlOwnership();
    KeyBehavior key;
    assert(!key.isPressed() && !key.isHoldingControl());
    expect(key.release(0));
    expect(key.promote());
    expect(key.reset());

    // Escape is emitted only on release, strictly before the hold threshold.
    expect(key.press(1000));
    assert(key.isPressed() && !key.isHoldingControl());
    expect(key.release(1179), KeyAction::escape);
    assert(!key.isPressed());
    expect(key.press(2000));
    expect(key.release(2180), KeyAction::controlDown, KeyAction::controlUp);
    expect(key.press(3000));
    expect(key.release(4000), KeyAction::controlDown, KeyAction::controlUp);

    // A timer or fast chord promotes once, even before the hold threshold.
    expect(key.press(5000));
    expect(key.promote(), KeyAction::controlDown);
    assert(key.isPressed() && key.isHoldingControl());
    expect(key.promote());
    expect(key.release(5001), KeyAction::controlUp);
    assert(!key.isPressed() && !key.isHoldingControl());
    expect(key.release(5002));

    // Windows key repeats neither restart the clock nor add another press.
    expect(key.press(6000));
    expect(key.press(6179));
    expect(key.release(6180), KeyAction::controlDown, KeyAction::controlUp);
    expect(key.press(7000));
    expect(key.promote(), KeyAction::controlDown);
    expect(key.press(7001));
    expect(key.release(7002), KeyAction::controlUp);

    // Pause/session cleanup cancels pending taps and releases Control once.
    expect(key.press(8000));
    expect(key.reset());
    expect(key.release(8001));
    expect(key.promote());
    expect(key.press(9000));
    expect(key.promote(), KeyAction::controlDown);
    expect(key.reset(), KeyAction::controlUp);
    assert(!key.isPressed() && !key.isHoldingControl());
    expect(key.reset());
    expect(key.release(9001));
    expect(key.press(10000));
    expect(key.release(10001), KeyAction::escape);

    std::puts("Windows KeyBehavior: taps, holds, chords, repeats, and cleanup passed");
}
