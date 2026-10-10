<img src="docs/icon.png" alt="NoCaps app icon" width="128" height="128">

# NoCaps

Give Caps Lock a useful job: **tap for Escape, hold for Control**.
Press Caps Lock with another key for an immediate Control shortcut.
NoCaps handles keyboard shortcuts; Caps Lock with clicking, scrolling, or dragging
is not supported.

NoCaps lives in your menu bar and works on macOS 13 or later, on Apple silicon
and Intel Macs.

## Install

Download [NoCaps.zip from the latest release](https://github.com/phucisstupid/nocaps/releases/latest),
unzip it, and move NoCaps to Applications.

Or install with Homebrew:

```sh
brew tap phucisstupid/nocaps https://github.com/phucisstupid/nocaps
brew trust --cask phucisstupid/nocaps/nocaps
brew install --cask phucisstupid/nocaps/nocaps
```

Release builds are not notarized, so macOS may require approval before opening.

## Use

Open NoCaps and allow keyboard access in **System Settings → Privacy & Security
→ Accessibility** (called **Device Control and Data Access** on newer macOS).
Turn Caps Lock off first if its light is on.
After granting access, open NoCaps's menu or click **Enable NoCaps** to recheck
permission. Grant access to the copy installed in Applications.

Use the menu to pause NoCaps or enable **Launch at Login**. Quitting restores
Caps Lock. If NoCaps crashes or is force-quit, reopen it or restart your Mac to
restore the key.

NoCaps pauses during Secure Input. It reserves F20 while running, so avoid using
another Caps Lock remapper alongside it.
If a newly connected keyboard is not remapped yet, open NoCaps's menu to retry.

For development and build instructions, see [AGENTS.md](AGENTS.md).
