# NoCaps

A super lightweight app that does one job: make Caps Lock **tap for Escape, hold for Control**.

https://github.com/user-attachments/assets/2d6eead7-736c-41bb-a0d2-f86ebb927150

NoCaps lives in your menu bar on macOS 13 or later, on Apple silicon and Intel
Macs. The native Windows version lives in the notification area on Windows 10
and 11 (x64).

## Install on macOS

Download [NoCaps.zip from the latest release](https://github.com/phucisstupid/nocaps/releases/latest),
unzip it, and move NoCaps to Applications.

Or install with Homebrew:

```sh
brew install --cask phucisstupid/tap/nocaps
```

Release builds are not notarized, so macOS may require approval before opening.

## Usage on macOS

Open NoCaps and allow keyboard access in **System Settings → Privacy & Security
→ Accessibility** (**Device Control and Data Access** on newer macOS).
Turn Caps Lock off if its light is on. After granting access, quit and reopen NoCaps
once. Later launches use the saved permission.

Use the menu to pause NoCaps or enable **Launch at Login**. Quit to restore Caps Lock.
If NoCaps crashes, reopen it to restore the key.

## Windows

Download [NoCaps.exe from the latest release](https://github.com/phucisstupid/nocaps/releases/latest/download/NoCaps.exe)
and open it. A [ZIP archive](https://github.com/phucisstupid/nocaps/releases/latest/download/NoCaps-Windows-x64.zip)
is also available. Keep the executable in a permanent folder before enabling
**Launch at Login**. There is no installer
or runtime to install. Windows builds are unsigned.

Turn Caps Lock off before enabling NoCaps. Tap Caps Lock for Escape, hold it for
180 ms for Control, or press another key while holding it for an immediate
Control chord. Right-click the notification icon to pause, enable **Launch at
Login**, or quit. Pausing and quitting restore normal Caps Lock behavior.

The app uses a Windows keyboard hook without changing system keyboard mappings.
It pauses when your session locks, sleeps, or switches to a secure desktop, then
resumes on your normal desktop. It runs with normal user permissions and cannot
remap input in elevated applications, the sign-in screen, or UAC prompts;
[Windows restricts sending input to higher-privilege apps](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput).
Games that read raw keyboard input may ignore the remapping. Simultaneous Caps
Lock presses on multiple keyboards cannot be distinguished; use one at a time.
If NoCaps crashes while holding Control, tap and release left Control to
clear it, then reopen NoCaps. Normal Caps Lock behavior returns when the app exits.

## Development

### macOS

Requires Xcode 27. Run from the project folder:

```sh
bash scripts/lint.sh
bash scripts/build.sh
```

The build creates `build/NoCaps.zip`. See [AGENTS.md](AGENTS.md) for contributor instructions.

### Windows

Install Visual Studio 2022 or later with **Desktop development with C++**, a
Windows SDK, and CMake 3.21 or later. Run from PowerShell in the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1
```

The build runs the assert-based self-checks and creates
`build/NoCaps-Windows-x64.zip` with a SHA-256 checksum. The app uses C++17 and
Windows system libraries; it has no third-party dependencies.
