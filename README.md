# AV Pain Reliever

> Auto-switch your microphone, speakers, and camera when you change desks.

When you carry a MacBook between locations — your home office, a work desk, a conference room, a café — your audio defaults usually need fixing every time. Different microphone, different speakers, sometimes a different camera. **AV Pain Reliever** notices which dock you've connected to and automatically:

- Sets your **system default microphone** for that location.
- Sets your **system default speaker** for that location.
- Sets your **system preferred camera** for that location.

Configure your video apps (Zoom, Slack, Teams) once to follow the system, and after that the right setup is active the moment you plug in. Unplug and it returns to your laptop's built-in mic and speakers.

The app lives in your menu bar — no Dock icon, no windows in your way.

---

## Requirements

A Mac running **macOS 14 (Sonoma) or later**.

---

## Install

1. Download the latest **AVPainReliever.app.zip** from the [Releases page](https://github.com/superic/av-pain-reliever/releases/latest).
2. Unzip and drag **AVPainReliever.app** into your **Applications** folder.
3. Double-click to launch. The icon appears in your menu bar.
4. Open **Settings…** and toggle **Launch at Login** if you want it running every time you sign in.

The app updates itself in the background. To check manually, open **About → Check for Updates**.

To stop it: click the menu bar icon → **Quit**.

---

## First-run setup

The first time you launch, the welcome window walks you through capturing the dock you're at right now:

1. **Name the location.** "Home Office", "Work Desk", "Studio", "Conference Room" — anything that makes sense to you.
2. **Pick which USB devices identify this location.** Untick anything that travels with you (keyboards, mice, phones).
3. **Pick the audio and camera defaults.** Pre-filled with your current System Settings.
4. **Save.**

Repeat once per location. The app switches automatically whenever you dock there.

When you connect to a new dock the app doesn't recognise, the menu bar shows **"New location"** and offers to set it up.

---

## Using the app

Click the menu bar icon for:

- **Switch to** — manually apply a different profile.
- **Add Profile…** — capture the dock you're at right now (⌘N).
- **Settings…** — notifications, menu bar appearance, profile management, Launch at Login (⌘,).
- **About** — version and updates.

---

## Privacy

The app makes no network calls beyond checking for its own updates. No analytics, no telemetry, no third-party services. Your profiles are stored as a plain text file on your Mac (`~/Library/Application Support/AVPainReliever/profiles.toml`) — you can read it, back it up, or edit it by hand.

---

## Support

Questions or bug reports: [open an issue](https://github.com/superic/av-pain-reliever/issues).

---

For developers: see [SWIFT_PORT.md](SWIFT_PORT.md) for the running design log and [docs/RELEASING.md](docs/RELEASING.md) for the release pipeline. Licensed MIT — see [LICENSE](LICENSE).
