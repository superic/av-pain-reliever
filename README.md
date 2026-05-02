# AV Pain Reliever 💊

> Stop fiddling with your microphone, speakers, and webcam every time you switch desks. Your Mac will do it for you.

When you carry a MacBook between locations — your home office, a work desk, a conference room, a café — your audio defaults usually need fixing every time. Different microphone, different speakers, sometimes a different camera. **AV Pain Reliever** notices which dock you've connected to and automatically:

- Sets your **system default microphone** to the right one for that location.
- Sets your **system default speaker** to the right one for that location.
- Sets your **system preferred camera** to the right one for that location.

You configure your video apps (Zoom, Slack, Teams) once to follow the system, and after that you never touch a microphone or camera setting again. Plug in, the right setup is active. Unplug, it goes back to your laptop's built-in mic and speakers.

The app lives in your menu bar — no Dock icon, no windows that get in your way. The current location's name shows next to a small pill icon. Click it for status, profile switching, and settings.

---

## What you'll need

A Mac running **macOS 14 (Sonoma) or later**. That's it.

---

## Install

1. Download the latest **AVPainReliever.app.zip** from the [Releases page](https://github.com/superic/av-pain-reliever/releases/latest).
2. Unzip and drag **AVPainReliever.app** into your **Applications** folder.
3. Double-click to launch. The pill icon shows up in your menu bar; the engine starts watching USB events immediately.
4. Open **Settings…** and toggle **Launch at Login** if you want it running every time you sign in.

The app updates itself: a new version downloads in the background and prompts you to install on next launch. Or check on demand via the menu → **Advanced → Check for Updates…**

To stop it: click the pill icon → **Quit AV Pain Reliever** (or ⌘Q with the menu open).

---

## First-run setup

If you've never used AV Pain Reliever before, you'll see a welcome window the first time the app launches. Click **Add Your First Location** and the wizard walks you through capturing the dock you're at right now:

1. **Name the location.** "Home Office", "Work Desk", "Studio", "Conference Room" — anything human-readable. The app slugifies internally; you'll see the name as you typed it everywhere in the UI.
2. **Pick which USB devices identify this location.** The wizard pre-checks every device currently attached. Untick anything that travels with you (keyboards, mice, phones) — the app shows yellow "Suggested: untick" pills next to the obvious ones to make this easy.
3. **Pick the audio + camera defaults.** The wizard pre-fills with whatever is currently set in System Settings, so if you've already configured this location manually, you can usually just click Save.
4. Hit Save. Done.

Repeat once per location. The app switches automatically whenever you dock there.

---

## Using the app

The menu bar shows the current location ("Home Office", "Laptop", etc.) next to the pill icon. Click for the menu:

- **Switch to ▶** — manually apply a different profile. ⌥-click any profile to edit it instead of switching.
- **Add Profile…** — capture the dock you're at right now (⌘N).
- **Settings…** — toggle notifications, set the debounce window, manage profiles, enable Launch-at-Login (⌘,).
- **About** — version + a link to re-show the welcome window.
- **Advanced** — power-user actions: re-evaluate immediately (⌘R), reload config from disk (⌘L), reveal the log in Console.

When you dock somewhere AV Pain Reliever doesn't have a profile for, the menu bar shows **"New location"** with a `?` icon and a banner-style **Set Up This Location…** button at the top of the menu. The wizard pre-selects all currently-attached devices, so you just type a name and save.

---

## How it works

A small in-process engine watches IOKit USB events on the main run loop. Each event triggers a 1.5-second debounce (so a dock-burst lands as a single evaluation), then resolves the currently-attached set against your configured profiles using a "most-specific match wins" algorithm. The chosen profile applies via CoreAudio (`kAudioHardwarePropertyDefaultInputDevice` / `Output`) and AVFoundation (`AVCaptureDevice.userPreferredCamera`).

Profiles live in plain TOML at `~/Library/Application Support/AVPainReliever/profiles.toml`. The wizard reads + writes this file; nothing stops you from editing it by hand, and the app's "Reload Config" menu item picks up your changes without a restart.

The engine has no network calls, no analytics, no telemetry, no third-party services. It's the whole product.

---

## What's NOT in V1

- **Per-app routing.** "Same as System" in Zoom/Slack/Teams is the supported pattern. The app does not poke their plists or UI-script them — too fragile, too fiddly.
- **Detection signals beyond USB.** No WiFi, Bluetooth, calendar, or time-of-day matching. USB-device fingerprints have been sufficient for every location tested.

If you have a use case either of these blocks, file an issue.

---

## Nerd zone

The rest of this section is for developers / contributors. Skip if you just want to use the app.

### Project layout

```
av-pain-reliever/
├── Package.swift              # SPM manifest — single source of truth for deps + targets
├── Sources/
│   ├── AVPainReliever/        # Engine library (resolver, debouncer, applier, USB/audio/camera adapters, config loader)
│   └── AVPainRelieverApp/     # SwiftUI menu-bar app target (App, AppDelegate, views)
├── Tests/
│   ├── AVPainRelieverTests/         # Engine + adapter tests
│   └── AVPainRelieverAppTests/      # App-target helper tests (Theme, ProfileIcon, NotificationCopy, SettingsStore, view model)
├── SWIFT_PORT.md              # Running design log + lessons learned
├── prototypes/                # Archive of earlier research code (see prototypes/README.md)
├── LICENSE
└── README.md                  # This file
```

### Build from source

If you'd rather run from source than download the signed `.app` (e.g. you want to hack on it), you'll need the Swift toolchain — installed automatically with [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12), or via `xcode-select --install` for the command-line tools alone.

```sh
git clone https://github.com/superic/av-pain-reliever ~/av-pain-reliever
cd ~/av-pain-reliever
swift run AVPainRelieverApp
```

Login items via `SMAppService` only register when running from a signed `.app` bundle, so the **Launch at Login** toggle is a no-op when you launch this way. Quit by clicking the pill icon → **Quit**.

### Build, run, test

```sh
swift build                                  # compile
swift run AVPainRelieverApp                  # launch the menu-bar app
swift test                                   # full test suite
swift test --filter ConfigLoader             # narrow to one suite
scripts/make-app.sh                          # build a signed .app under dist/ (see docs/RELEASING.md for signed builds)
```

### Architecture in one paragraph

`Engine` (`Sources/AVPainReliever/Engine/Engine.swift`) wires `USBWatcher → Debouncer → ProfileResolver → ProfileApplier`. The watcher is a thin IOKit wrapper; the debouncer collapses USB event bursts; the resolver picks the best-matching `Profile` against attached devices; the applier orchestrates the audio + camera side effects via the `AudioController` and `CameraController` adapter protocols (production: CoreAudio + AVFoundation, tests: recording mocks). `ConfigLoader` parses `profiles.toml` via TOMLKit; `ProfileWriter` handles append/replace/delete on the TOML, preserving comments and surrounding content. The SwiftUI app target (`AVPainRelieverApp`) owns an `AppDelegate` that wires the engine to a `MenuBarExtra` plus four `Window` scenes (Add Profile wizard, Settings, About, Welcome).

### Design log

[`SWIFT_PORT.md`](SWIFT_PORT.md) is the running design document — locked architectural choices, open questions, lessons learned by section, effort estimates, and what's deferred. If you're contributing or just curious about why a thing is the way it is, start there.

### Research archive

[`prototypes/`](prototypes/) holds earlier research code that informed the current implementation — kept for reference, no longer maintained. See [`prototypes/README.md`](prototypes/README.md) for what's there and why.

### License

MIT. See [LICENSE](LICENSE).
