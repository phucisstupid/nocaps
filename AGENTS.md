# NoCaps contributor instructions

Use this file for development guidance. README.md is user documentation.
On the owner's machine, also read `/Users/wow/.codex/RTK.md` when available.

## Project

NoCaps is a native Swift menu bar app for macOS 13 or later and a native C++17
notification-area app for Windows 10 or later. Caps Lock taps Escape and holds
Control; pressing another key promotes Control immediately. On macOS, use
AppKit, Core Graphics, IOKit, and ServiceManagement. On Windows, use Win32 system
libraries. Keep both versions dependency-free.

- `Sources/main.swift`: menu, permissions, login item, and app lifecycle.
- `Sources/KeyBehavior.swift`: tap/hold state and timing.
- `Sources/KeyRemapper.swift`: event tap and synthetic key events.
- `Sources/KeyboardMapping.swift`: per-keyboard mapping and crash recovery.
- `Sources/SessionState.swift`: active user session state across launch and wake.
- `Tests/`: assert-based behavior, event, session, and mapping recovery checks.
- `Info.plist`: app identity, minimum macOS, and release version.
- `Windows/`: native C++17 Windows notification-area app, portable behavior
  checks, icon, manifest, and CMake build. Use Win32 system libraries only.
- `scripts/`: build, lint, and shared app/menu icon drawing.
- `tap_migrations.json`: redirects the former app tap to `phucisstupid/tap`.
  The Homebrew cask lives in `phucisstupid/homebrew-tap` as `Casks/nocaps.rb`.

## Commands

```sh
xcrun swift-format format --in-place --recursive Sources Tests scripts/render-icons.swift
bash scripts/lint.sh
bash scripts/build.sh
```

The build runs the self-checks and creates `build/NoCaps.zip`. It saves the
runnable bundle path in `.build/app-path`. Build bundles in a local temporary
directory: cloud providers can add metadata that invalidates signatures.
Use Xcode 27.0 for the native formatter and linter, matching the Actions workflow.
The lint script also checks shell syntax and Info.plist.

For keyboard or permission changes, also test the installed app manually:
tap, hold, fast chords, physical Control, pause/quit, and reconnect a keyboard.
Check permission-dependent menu visibility and Launch at Login when changing
the menu. Never report these hardware checks as passed without doing them.

On Windows, run `powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1`
with Visual Studio's C++ workload, Windows SDK, and CMake installed. The build
runs self-checks and creates `build/NoCaps-Windows-x64.zip`. Its version comes
from `Info.plist`. The reusable Windows Actions workflow builds and tests the
Windows app; tagged releases publish both platform archives and checksums.
Manually check tap, hold, fast chords, both physical Control keys, pause/quit, lock/unlock, sleep/wake, keyboard
disconnect/reconnect, Explorer restart, and Launch at Login on Windows.

## Safety

- Request keyboard permission through public macOS APIs; do not bypass consent.
- Preserve unrelated keyboard mappings. Journal originals before changing them.
- Release synthetic Control and restore Caps Lock on pause, quit, sleep, inactive
  sessions, and Secure Input. Retain recovery state when restoration fails.
- On macOS, recover mappings after a crash. F20 is reserved while NoCaps is active.
- Do not log keystrokes or add network requests.
- Quit the running app before replacing it; keep its bundle identifier stable.
- On Windows, release synthetic Control on pause, quit, suspend, and session
  changes. Use normal user privileges; never bypass UAC or secure desktops.
  Do not change system scancode mappings; registry writes are limited to the
  app's own preferences and Launch at Login entry.

## Release

Release notes contain only a bullet list of changes in that release. Omit
headings, app descriptions, installation instructions, compatibility details,
and signing or permission boilerplate.

GitHub Actions builds the tagged release for Apple silicon, Intel Macs, and
Windows x64, checks formatting/lint/tests, and publishes `NoCaps.zip` and
`NoCaps-Windows-x64.zip` with SHA-256 checksums. Keep the
app version, Git tag, release asset URL, and Homebrew cask version consistent.
Use the actual release archive's SHA-256 in the cask. Do not claim Apple
notarization unless the workflow signs and notarizes with configured credentials.
After Actions publishes a release, download its archive, update the cask version
and checksum in `phucisstupid/homebrew-tap`, and commit there. A local build's
checksum is only a preview; do not publish it as the Actions artifact's checksum.
