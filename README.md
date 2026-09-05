<p align="center">
  <img src="MicCheck/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="Mic Check icon">
</p>

<h1 align="center">Mic Check</h1>

<p align="center">A small macOS menu bar app for switching your microphone and seeing that it actually hears you.</p>

---

Switching mics on a Mac means a trip to System Settings, and even then you can't tell whether the mic you picked is live. Mic Check puts the input list one click away in the menu bar, with a live level meter next to every device, so you can see which one is hearing you before you join the call.

## Features

- **One-click input switching.** Every input device in a dropdown, current one checked. Click to make it the system default.
- **Live level meters.** A meter on every row while the panel is open, plus a large meter and gain slider for the current input. The menu bar icon fills with level too.
- **Sound test.** Click **Test** to record five seconds and hear it played back through your speakers. Press and hold to record for as long as you hold, up to a minute.
- **Lock input.** Stop macOS or other apps from silently switching your mic. When locked, Mic Check switches it straight back.
- **Rename and hide devices.** Right-click any row to give a device a friendly name ("Lapel mic" instead of "USB Audio Device") or hide it. Virtual devices from meeting apps are hidden by default, and the iPhone Continuity mic is never listed.
- **Stays out of the way.** No Dock icon, no windows, and no microphone use while the panel is closed.

## Install

Download the latest DMG from [Releases](https://github.com/bryceadams/mic-check-mac/releases), open it, and drag Mic Check to Applications. The app is signed and notarized, so it opens without warnings.

Requires macOS 15 or later. On first open of the panel, macOS asks for microphone access. That's needed for the level meters; nothing is recorded or stored.

Turn on **Launch at login** in Settings if you want it always there.

## Privacy

Mic Check has no network access. Audio from your microphones is used only to draw the meters and, when you run a sound test, to play the clip back to you from memory. Nothing is written to disk or sent anywhere. Preferences and device names are stored locally in the app's own defaults.

## Building from source

Requirements: Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project MicCheck.xcodeproj -scheme MicCheck -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Mic Check.app"
```

The project is described in `project.yml`; the generated `.xcodeproj` is not checked in. Signing uses a Developer ID identity, so set your own team in `project.yml` or switch `CODE_SIGN_STYLE` to `Automatic` to build with a development certificate.

`scripts/release.sh` builds a Release binary, notarizes it, and packages a DMG. See the comments at the top of that script for the one-time notarization credential setup.

## How it works

Device enumeration, default-input switching, and gain use the CoreAudio HAL directly. Each level meter is a CoreAudio IO proc on its device, started only while the panel is open. The dropdown is a SwiftUI `MenuBarExtra` in window style. There are no third-party dependencies.

## License

[MIT](LICENSE)
