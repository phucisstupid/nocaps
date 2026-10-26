#include <windows.h>
#include <shellapi.h>
#include <wtsapi32.h>
#include <dbt.h>

#include <string>

#include "ControlState.h"
#include "KeyBehavior.h"

#define NOCAPS_WIDEN_(text) L##text
#define NOCAPS_WIDEN(text) NOCAPS_WIDEN_(text)

namespace {
constexpr wchar_t windowClass[] = L"NoCaps.Native.Windows";
constexpr wchar_t preferences[] = L"Software\\NoCaps";
constexpr wchar_t loginKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr ULONG_PTR marker = 0x4E6F4361;
constexpr UINT trayMessage = WM_APP + 1;
constexpr UINT failureMessage = WM_APP + 2;
constexpr UINT_PTR holdTimer = 1;
constexpr UINT_PTR safetyTimer = 2;
constexpr UINT toggleCommand = 1, loginCommand = 2, errorCommand = 3, quitCommand = 4;

HWND window = nullptr;
HHOOK hook = nullptr;
HICON icon = nullptr;
KeyBehavior behavior;
ControlState control;
bool enabled = true;
bool sessionActive = true;
bool sleeping = false;
bool acceptingInput = false;
bool capsDown = false;
bool escapeReleasePending = false;
bool trayVisible = false;
std::wstring lastTip;
std::wstring executable;
const wchar_t* lastError = nullptr;
UINT taskbarCreated = 0;
decltype(&SendInput) sendInput = SendInput;

void updateTray();
void refresh();

bool inputDesktopIsActive() {
    HDESK desktop = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
    if (!desktop) return false;
    wchar_t inputName[256]{}, threadName[256]{};
    DWORD length = 0;
    const bool active = GetUserObjectInformationW(desktop, UOI_NAME, inputName, sizeof(inputName), &length)
        && GetUserObjectInformationW(GetThreadDesktop(GetCurrentThreadId()), UOI_NAME,
                                     threadName, sizeof(threadName), &length)
        && lstrcmpW(inputName, threadName) == 0;
    CloseDesktop(desktop);
    return active;
}

INPUT keyInput(WORD key, bool up) {
    INPUT input{};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = key;
    input.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    input.ki.dwExtraInfo = marker;
    return input;
}

void fail(const wchar_t* message) {
    acceptingInput = false;
    enabled = false;
    lastError = message;
    PostMessageW(window, failureMessage, 0, 0);
}

bool releaseKeys() {
    if (control.syntheticLeftDown) {
        if (control.physicalLeftDown) {
            control.released();
        } else {
            INPUT up = keyInput(VK_LCONTROL, true);
            if (sendInput(1, &up, sizeof(INPUT)) == 1) control.released();
        }
    }
    if (escapeReleasePending) {
        INPUT up = keyInput(VK_ESCAPE, true);
        if (sendInput(1, &up, sizeof(INPUT)) == 1) escapeReleasePending = false;
    }
    return !control.syntheticLeftDown && !escapeReleasePending;
}

void cancelPress() {
    KillTimer(window, holdTimer);
    behavior.reset();
    if (!releaseKeys()) acceptingInput = false;
}

// Replay the first chord in the same batch so Control always reaches the app first.
bool sendActions(const KeyActions& actions, const KBDLLHOOKSTRUCT* chord = nullptr) {
    INPUT inputs[4]{};
    UINT count = 0;
    bool releasingControl = false;
    bool replayedChord = false;
    bool releasingEscape = false;
    for (const auto action : actions) {
        switch (action) {
        case KeyAction::none:
            break;
        case KeyAction::controlDown:
            if (control.press()) {
                inputs[count++] = keyInput(VK_LCONTROL, false);
                if (chord) {
                    INPUT replay{};
                    replay.type = INPUT_KEYBOARD;
                    replay.ki.wScan = static_cast<WORD>(chord->scanCode);
                    replay.ki.dwFlags = KEYEVENTF_SCANCODE
                        | ((chord->flags & LLKHF_EXTENDED) ? KEYEVENTF_EXTENDEDKEY : 0);
                    // Pause uses an E1 scan sequence rather than an extended E0 key.
                    if (replay.ki.wScan == 0 || chord->vkCode == VK_PAUSE) {
                        replay.ki.wVk = static_cast<WORD>(chord->vkCode);
                        replay.ki.wScan = 0;
                        replay.ki.dwFlags &= ~static_cast<DWORD>(KEYEVENTF_SCANCODE);
                    }
                    replay.ki.dwExtraInfo = marker;
                    inputs[count++] = replay;
                    replayedChord = true;
                }
            }
            break;
        case KeyAction::controlUp:
            if (control.needsRelease()) {
                inputs[count++] = keyInput(VK_LCONTROL, true);
                releasingControl = true;
            } else {
                control.released();
            }
            break;
        case KeyAction::escape:
            inputs[count++] = keyInput(VK_ESCAPE, false);
            inputs[count++] = keyInput(VK_ESCAPE, true);
            escapeReleasePending = true;
            releasingEscape = true;
            break;
        }
    }
    if (count && sendInput(count, inputs, sizeof(INPUT)) != count) {
        fail(L"Windows could not send a key. NoCaps is paused. Elevated apps and secure desktops are not supported.");
        return false;
    }
    if (releasingControl) control.released();
    if (releasingEscape) escapeReleasePending = false;
    return replayedChord;
}

LRESULT CALLBACK keyboardHook(int code, WPARAM message, LPARAM data) {
    if (code != HC_ACTION) return CallNextHookEx(hook, code, message, data);
    const auto& key = *reinterpret_cast<const KBDLLHOOKSTRUCT*>(data);
    if (key.dwExtraInfo == marker || (key.flags & LLKHF_INJECTED)) {
        return CallNextHookEx(hook, code, message, data);
    }
    const bool down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
    const bool leftControl = key.vkCode == VK_LCONTROL
        || (key.vkCode == VK_CONTROL && !(key.flags & LLKHF_EXTENDED));
    if (acceptingInput && (key.vkCode == VK_CAPITAL || behavior.isPressed()) && !inputDesktopIsActive()) {
        acceptingInput = false;
        if (leftControl) control.physicalEvent(down, false);
        cancelPress();
        return CallNextHookEx(hook, code, message, data);
    }
    if (leftControl && control.physicalEvent(down, acceptingInput && behavior.isHoldingControl())) return 1;
    if (!acceptingInput) return CallNextHookEx(hook, code, message, data);

    if (key.vkCode == VK_CAPITAL) {
        // shortcut: hooks merge keyboards; overlapping Caps presses need a per-device driver.
        if (down) {
            if (!capsDown) {
                capsDown = true;
                behavior.press(GetTickCount64());
                if (!SetTimer(window, holdTimer, static_cast<UINT>(KeyBehavior::holdDelay), nullptr)) {
                    fail(L"Windows could not start the hold timer.");
                }
            }
        } else {
            capsDown = false;
            KillTimer(window, holdTimer);
            sendActions(behavior.release(GetTickCount64()));
        }
        return 1;
    }
    if (down && behavior.isPressed()) {
        KillTimer(window, holdTimer);
        if (sendActions(behavior.promote(), &key)) return 1;
    }
    return CallNextHookEx(hook, code, message, data);
}

void saveEnabled() {
    HKEY key = nullptr;
    const DWORD value = enabled ? 1 : 0;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, preferences, 0, nullptr, 0, KEY_SET_VALUE,
                        nullptr, &key, nullptr) == ERROR_SUCCESS) {
        if (RegSetValueExW(key, L"WindowsEnabled", 0, REG_DWORD,
                          reinterpret_cast<const BYTE*>(&value), sizeof(value)) != ERROR_SUCCESS) {
            lastError = L"Could not save the enabled preference.";
        }
        RegCloseKey(key);
    } else {
        lastError = L"Could not save the enabled preference.";
    }
}

std::wstring loginCommandLine() { return L"\"" + executable + L"\""; }

bool launchesAtLogin() {
    wchar_t value[32768]{};
    DWORD bytes = sizeof(value);
    return RegGetValueW(HKEY_CURRENT_USER, loginKey, L"NoCaps", RRF_RT_REG_SZ,
                        nullptr, value, &bytes) == ERROR_SUCCESS
        && loginCommandLine() == value;
}

void toggleLogin() {
    const bool remove = launchesAtLogin();
    HKEY key = nullptr;
    LSTATUS result = RegCreateKeyExW(HKEY_CURRENT_USER, loginKey, 0, nullptr, 0,
                                     KEY_SET_VALUE, nullptr, &key, nullptr);
    if (result == ERROR_SUCCESS) {
        const auto command = loginCommandLine();
        result = remove ? RegDeleteValueW(key, L"NoCaps")
            : RegSetValueExW(key, L"NoCaps", 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(command.c_str()),
                            static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(key);
    }
    if (result != ERROR_SUCCESS) {
        lastError = L"Could not change Launch at Login.";
        MessageBoxW(window, lastError, L"NoCaps", MB_OK | MB_ICONWARNING);
    }
    updateTray();
}

void updateTray() {
    const wchar_t* status = lastError ? L"Needs attention"
        : !enabled ? L"Paused" : acceptingInput ? L"Active" : L"Waiting for your desktop";
    const std::wstring tip = L"NoCaps " NOCAPS_WIDEN(NOCAPS_VERSION) L" - " + std::wstring(status);
    if (trayVisible && lastTip == tip) return;
    NOTIFYICONDATAW tray{};
    tray.cbSize = sizeof(tray);
    tray.hWnd = window;
    tray.uID = 1;
    tray.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
    tray.uCallbackMessage = trayMessage;
    tray.hIcon = icon;
    lstrcpynW(tray.szTip, tip.c_str(), ARRAYSIZE(tray.szTip));
    if (Shell_NotifyIconW(trayVisible ? NIM_MODIFY : NIM_ADD, &tray)) {
        if (!trayVisible) {
            tray.uVersion = NOTIFYICON_VERSION_4;
            Shell_NotifyIconW(NIM_SETVERSION, &tray);
        }
        trayVisible = true;
        lastTip = tip;
    } else {
        trayVisible = false;
    }
}

void refresh() {
    const bool active = sessionActive && !sleeping && inputDesktopIsActive();
    if (!active || !enabled || !acceptingInput) {
        acceptingInput = false;
        cancelPress();
        if (hook) {
            UnhookWindowsHookEx(hook);
            hook = nullptr;
        }
    }
    if (active && enabled && !hook) {
        if (!releaseKeys()) {
            updateTray();
            return;
        }
        // Wait for a held Caps key to finish before starting a new press.
        if (!(GetAsyncKeyState(VK_CAPITAL) & 0x8000)) {
            capsDown = false;
            control.physicalLeftDown = (GetAsyncKeyState(VK_LCONTROL) & 0x8000) != 0;
            hook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardHook, GetModuleHandleW(nullptr), 0);
            if (!hook) fail(L"Windows could not start the keyboard listener.");
            acceptingInput = hook != nullptr;
        }
    }
    updateTray();
}

void showMenu() {
    HMENU menu = CreatePopupMenu();
    if (!menu) return;
    AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, L"NoCaps " NOCAPS_WIDEN(NOCAPS_VERSION));
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING | (enabled ? MF_CHECKED : 0), toggleCommand, L"Enable NoCaps");
    AppendMenuW(menu, MF_STRING | (launchesAtLogin() ? MF_CHECKED : 0), loginCommand, L"Launch at Login");
    if (lastError) AppendMenuW(menu, MF_STRING, errorCommand, L"Show Error...");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, quitCommand, L"Quit NoCaps");
    POINT point{};
    GetCursorPos(&point);
    SetForegroundWindow(window);
    const UINT command = static_cast<UINT>(TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                                         point.x, point.y, 0, window, nullptr));
    DestroyMenu(menu);
    PostMessageW(window, WM_NULL, 0, 0);
    if (command) PostMessageW(window, WM_COMMAND, command, 0);
}

LRESULT CALLBACK windowProcedure(HWND handle, UINT message, WPARAM wParam, LPARAM lParam) {
    if (taskbarCreated && message == taskbarCreated) {
        trayVisible = false;
        updateTray();
        return 0;
    }
    switch (message) {
    case trayMessage:
        if (LOWORD(lParam) == WM_CONTEXTMENU || LOWORD(lParam) == NIN_SELECT
            || LOWORD(lParam) == NIN_KEYSELECT) showMenu();
        return 0;
    case failureMessage:
        saveEnabled();
        refresh();
        return 0;
    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case toggleCommand:
            enabled = !enabled;
            lastError = nullptr;
            saveEnabled();
            refresh();
            break;
        case loginCommand:
            toggleLogin();
            break;
        case errorCommand:
            if (lastError) MessageBoxW(handle, lastError, L"NoCaps", MB_OK | MB_ICONWARNING);
            break;
        case quitCommand:
            SendMessageW(handle, WM_CLOSE, 0, 0);
            break;
        }
        return 0;
    case WM_TIMER:
        if (wParam == holdTimer) {
            KillTimer(handle, holdTimer);
            if (acceptingInput && inputDesktopIsActive()) sendActions(behavior.promote());
            else cancelPress();
        } else if (wParam == safetyTimer) {
            refresh();
        }
        return 0;
    case WM_WTSSESSION_CHANGE:
        switch (wParam) {
        case WTS_SESSION_LOCK:
        case WTS_CONSOLE_DISCONNECT:
        case WTS_REMOTE_DISCONNECT:
        case WTS_SESSION_LOGOFF:
            sessionActive = false;
            break;
        case WTS_SESSION_UNLOCK:
        case WTS_CONSOLE_CONNECT:
        case WTS_REMOTE_CONNECT:
        case WTS_SESSION_LOGON:
            sessionActive = true;
            break;
        }
        refresh();
        return 0;
    case WM_POWERBROADCAST:
        if (wParam == PBT_APMSUSPEND) sleeping = true;
        if (wParam == PBT_APMRESUMEAUTOMATIC || wParam == PBT_APMRESUMESUSPEND) sleeping = false;
        refresh();
        return TRUE;
    case WM_DEVICECHANGE:
        if (wParam == DBT_DEVNODES_CHANGED || wParam == DBT_DEVICEREMOVECOMPLETE) cancelPress();
        return TRUE;
    case WM_QUERYENDSESSION:
        acceptingInput = false;
        cancelPress();
        return TRUE;
    case WM_ENDSESSION:
        if (wParam) DestroyWindow(handle);
        else refresh();
        return 0;
    case WM_CLOSE:
        acceptingInput = false;
        cancelPress();
        if (!releaseKeys()) {
            enabled = false;
            lastError = L"Control could not be released. Return to your normal desktop and try quitting again.";
            refresh();
            MessageBoxW(handle, lastError, L"NoCaps", MB_OK | MB_ICONWARNING);
        } else {
            DestroyWindow(handle);
        }
        return 0;
    case WM_DESTROY: {
        acceptingInput = false;
        cancelPress();
        if (hook) UnhookWindowsHookEx(hook);
        hook = nullptr;
        KillTimer(handle, safetyTimer);
        WTSUnRegisterSessionNotification(handle);
        NOTIFYICONDATAW tray{};
        tray.cbSize = sizeof(tray);
        tray.hWnd = handle;
        tray.uID = 1;
        Shell_NotifyIconW(NIM_DELETE, &tray);
        PostQuitMessage(0);
        return 0;
    }
    }
    return DefWindowProcW(handle, message, wParam, lParam);
}
} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    HANDLE singleton = CreateMutexW(nullptr, FALSE, L"Local\\NoCaps.Native.Windows");
    if (!singleton) return 1;
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        CloseHandle(singleton);
        return 0;
    }
    wchar_t path[32768]{};
    const DWORD pathLength = GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
    if (!pathLength || pathLength >= ARRAYSIZE(path)) {
        CloseHandle(singleton);
        return 1;
    }
    executable = path;
    DWORD value = 1, bytes = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, preferences, L"WindowsEnabled", RRF_RT_REG_DWORD,
                     nullptr, &value, &bytes) == ERROR_SUCCESS) enabled = value != 0;
    LPWSTR sessionData = nullptr;
    DWORD sessionBytes = 0;
    sessionActive = WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, WTS_CURRENT_SESSION,
                                                WTSConnectState, &sessionData, &sessionBytes)
        && sessionBytes >= sizeof(WTS_CONNECTSTATE_CLASS)
        && *reinterpret_cast<WTS_CONNECTSTATE_CLASS*>(sessionData) == WTSActive;
    if (sessionData) WTSFreeMemory(sessionData);
    icon = static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(1), IMAGE_ICON, 0, 0, LR_DEFAULTSIZE));
    WNDCLASSW type{};
    type.lpfnWndProc = windowProcedure;
    type.hInstance = instance;
    type.lpszClassName = windowClass;
    type.hIcon = icon;
    if (!RegisterClassW(&type)) {
        if (icon) DestroyIcon(icon);
        CloseHandle(singleton);
        return 1;
    }
    taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
    window = CreateWindowExW(WS_EX_TOOLWINDOW, windowClass, L"NoCaps", WS_OVERLAPPED,
                             0, 0, 0, 0, nullptr, nullptr, instance, nullptr);
    if (!window || !icon) {
        MessageBoxW(nullptr, L"Windows could not create the NoCaps tray app.", L"NoCaps", MB_OK | MB_ICONERROR);
        if (window) DestroyWindow(window);
        if (icon) DestroyIcon(icon);
        CloseHandle(singleton);
        return 1;
    }
    if (!WTSRegisterSessionNotification(window, NOTIFY_FOR_THIS_SESSION)
        || !SetTimer(window, safetyTimer, 250, nullptr)) {
        MessageBoxW(window, L"Windows could not monitor session changes safely.", L"NoCaps", MB_OK | MB_ICONERROR);
        DestroyWindow(window);
        DestroyIcon(icon);
        CloseHandle(singleton);
        return 1;
    }
    refresh();
    MSG message{};
    int result = 0;
    while ((result = static_cast<int>(GetMessageW(&message, nullptr, 0, 0))) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    if (result == -1 && IsWindow(window)) DestroyWindow(window);
    DestroyIcon(icon);
    CloseHandle(singleton);
    return result == -1 ? 1 : 0;
}

#ifdef NOCAPS_CHECKS
#include "RemapperChecks.h"
#endif
