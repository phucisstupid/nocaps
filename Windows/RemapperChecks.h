#pragma once

#include <cassert>
#include <cstdio>
#include <limits>
#include <vector>

#ifdef NDEBUG
#error Build these checks with assertions enabled.
#endif

namespace {
std::vector<std::vector<INPUT>> capturedInputs;
UINT acceptedCount = std::numeric_limits<UINT>::max();

UINT WINAPI captureInput(UINT count, LPINPUT inputs, int size) {
    assert(size == static_cast<int>(sizeof(INPUT)));
    capturedInputs.emplace_back(inputs, inputs + count);
    return count < acceptedCount ? count : acceptedCount;
}

void resetRemapperCheck() {
    behavior = KeyBehavior{};
    control = ControlState{};
    acceptingInput = true;
    enabled = true;
    capsDown = false;
    escapeReleasePending = false;
    lastError = nullptr;
    capturedInputs.clear();
    acceptedCount = std::numeric_limits<UINT>::max();
}

void expectKey(const INPUT& input, WORD key, bool up) {
    assert(input.type == INPUT_KEYBOARD);
    assert(input.ki.wVk == key && input.ki.wScan == 0);
    assert(input.ki.dwFlags == static_cast<DWORD>(up ? KEYEVENTF_KEYUP : 0));
    assert(input.ki.dwExtraInfo == marker);
}
} // namespace

int main() {
    sendInput = captureInput;
    resetRemapperCheck();
    KBDLLHOOKSTRUCT chord{};
    chord.vkCode = VK_RIGHT;
    chord.scanCode = 0x4D;
    chord.flags = LLKHF_EXTENDED;
    behavior.press(1000);
    assert(sendActions(behavior.promote(), &chord));
    assert(capturedInputs.size() == 1 && capturedInputs[0].size() == 2);
    expectKey(capturedInputs[0][0], VK_LCONTROL, false);
    const auto& replay = capturedInputs[0][1];
    assert(replay.type == INPUT_KEYBOARD && replay.ki.wVk == 0);
    assert(replay.ki.wScan == chord.scanCode);
    assert(replay.ki.dwFlags == (KEYEVENTF_SCANCODE | KEYEVENTF_EXTENDEDKEY));
    assert(replay.ki.dwExtraInfo == marker);
    assert(control.syntheticLeftDown && acceptingInput && enabled);
    assert(!sendActions(behavior.release(1001)));
    assert(capturedInputs.size() == 2 && capturedInputs[1].size() == 1);
    expectKey(capturedInputs[1][0], VK_LCONTROL, true);
    assert(!control.syntheticLeftDown);

    resetRemapperCheck();
    chord.vkCode = VK_MEDIA_PLAY_PAUSE;
    chord.scanCode = 0;
    chord.flags = 0;
    assert(sendActions({KeyAction::controlDown}, &chord));
    assert(capturedInputs.size() == 1 && capturedInputs[0].size() == 2);
    expectKey(capturedInputs[0][1], VK_MEDIA_PLAY_PAUSE, false);

    resetRemapperCheck();
    chord.vkCode = VK_PAUSE;
    chord.scanCode = 0x45;
    assert(sendActions({KeyAction::controlDown}, &chord));
    expectKey(capturedInputs[0][1], VK_PAUSE, false);

    resetRemapperCheck();
    behavior.press(2000);
    assert(!sendActions(behavior.release(2001)));
    assert(capturedInputs.size() == 1 && capturedInputs[0].size() == 2);
    expectKey(capturedInputs[0][0], VK_ESCAPE, false);
    expectKey(capturedInputs[0][1], VK_ESCAPE, true);
    assert(!escapeReleasePending);

    resetRemapperCheck();
    behavior.press(2000);
    assert(!sendActions(behavior.release(2000 + KeyBehavior::holdDelay)));
    assert(capturedInputs.size() == 1 && capturedInputs[0].size() == 2);
    expectKey(capturedInputs[0][0], VK_LCONTROL, false);
    expectKey(capturedInputs[0][1], VK_LCONTROL, true);
    assert(!control.syntheticLeftDown);

    // Existing physical Control needs neither a synthetic press nor chord replay.
    resetRemapperCheck();
    assert(!control.physicalEvent(true, false));
    behavior.press(3000);
    assert(!sendActions(behavior.promote(), &chord));
    assert(capturedInputs.empty() && !control.syntheticLeftDown);
    assert(!sendActions(behavior.release(3001)));
    assert(capturedInputs.empty() && control.physicalLeftDown);

    // Suppressing physical key-up transfers the eventual release to NoCaps.
    behavior.press(4000);
    assert(!sendActions(behavior.promote(), &chord));
    assert(control.physicalEvent(false, behavior.isHoldingControl()));
    assert(control.syntheticLeftDown && control.needsRelease());
    assert(!sendActions(behavior.release(4001)));
    assert(capturedInputs.size() == 1 && capturedInputs[0].size() == 1);
    expectKey(capturedInputs[0][0], VK_LCONTROL, true);
    assert(!control.syntheticLeftDown);

    resetRemapperCheck();
    assert(!sendActions({KeyAction::controlDown}));
    assert(!control.physicalEvent(true, true));
    capturedInputs.clear();
    assert(releaseKeys());
    assert(capturedInputs.empty() && control.physicalLeftDown && !control.syntheticLeftDown);

    // A partial chord injection pauses input and retains Control for cleanup.
    resetRemapperCheck();
    acceptedCount = 1;
    assert(!sendActions({KeyAction::controlDown}, &chord));
    assert(!acceptingInput && !enabled && lastError);
    assert(control.syntheticLeftDown);
    acceptedCount = 0;
    assert(!releaseKeys() && control.syntheticLeftDown);
    acceptedCount = 1;
    assert(releaseKeys() && !control.syntheticLeftDown);
    expectKey(capturedInputs.back()[0], VK_LCONTROL, true);

    // A failed Control-up remains pending even after the behavior has reset.
    resetRemapperCheck();
    behavior.press(5000);
    assert(!sendActions(behavior.promote()));
    acceptedCount = 0;
    assert(!sendActions(behavior.release(5001)));
    assert(!acceptingInput && !enabled && control.syntheticLeftDown);
    assert(!behavior.isPressed());
    acceptedCount = 1;
    assert(releaseKeys() && !control.syntheticLeftDown);

    // Partial Escape pairs retain their key-up across empty actions and retries.
    resetRemapperCheck();
    acceptedCount = 1;
    assert(!sendActions({KeyAction::escape}));
    assert(escapeReleasePending && !acceptingInput && !enabled);
    const auto callsBeforeEmpty = capturedInputs.size();
    assert(!sendActions({}));
    assert(escapeReleasePending && capturedInputs.size() == callsBeforeEmpty);
    acceptedCount = 0;
    assert(!releaseKeys() && escapeReleasePending);
    acceptedCount = 1;
    assert(releaseKeys() && !escapeReleasePending);
    expectKey(capturedInputs.back()[0], VK_ESCAPE, true);

    // Device/session cancellation closes the input gate if key-up cannot be sent.
    resetRemapperCheck();
    behavior.press(6000);
    assert(!sendActions(behavior.promote()));
    acceptedCount = 0;
    cancelPress();
    assert(!acceptingInput && !behavior.isPressed() && control.syntheticLeftDown);
    acceptedCount = 1;
    assert(releaseKeys() && !control.syntheticLeftDown);

    std::puts("Windows remapper: chord batches, key ownership, partial sends, and cleanup passed");
}
