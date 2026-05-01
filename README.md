# av-pain-reliever

> Stop fiddling with your mic, speakers, and webcam every time you switch desks. This sets your Mac to do it for you.

When you dock your MacBook at a different location — say, you carry it from your home office to your work desk to a conference room — your audio defaults usually need fixing every time. Different mic, different speaker, sometimes a different camera. **av-pain-reliever** detects which dock you've connected to (by looking at the unique combination of USB devices plugged in) and automatically:

- Sets your **system default microphone** to the right one for that location.
- Sets your **system default speaker** to the right one for that location.
- Switches your **OBS Studio scene** to a per-location scene that has the right camera and overlays.

Configure Zoom and Slack once to use "Same as System" for audio and "OBS Virtual Camera" for video, and they'll inherit the correct devices everywhere you go. No menus to click, no settings to remember.

---

## Table of contents

- [Quick start (the wizard)](#quick-start-the-wizard)
- [What you'll need](#what-youll-need)
- [What the wizard does, step by step](#what-the-wizard-does-step-by-step)
- [Adding more locations later](#adding-more-locations-later)
- [Diagnostic: `wizard.sh status`](#diagnostic-wizardsh-status)
- [Updating to a newer version](#updating-to-a-newer-version)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)
- [How it works (under the hood)](#how-it-works-under-the-hood)
- [Manual install (if you don't want the wizard)](#manual-install-if-you-dont-want-the-wizard)
- [File reference](#file-reference)
- [Tests](#tests)
- [License](#license)

---

## Quick start (the wizard)

If you've already got Homebrew and the GitHub CLI (`gh`) installed and you're authenticated to GitHub, this single command does the whole thing:

```sh
gh repo clone superic/av-pain-reliever ~/av-pain-reliever && ~/av-pain-reliever/wizard.sh
```

It clones the repo into `~/av-pain-reliever`, then runs the interactive wizard. The wizard takes about 10 minutes and walks you through every step with prompts. You won't need to read this README to use it.

If you don't have Homebrew or `gh` yet, see [What you'll need](#what-youll-need) below — those two are the only prerequisites the wizard can't install for you.

---

## What you'll need

The wizard handles most of the install, but it relies on two tools you must have first.

### 1. macOS

This only works on macOS. Both Apple Silicon (M-series) and Intel Macs are supported.

### 2. Homebrew

Homebrew is the standard package manager for macOS. The wizard uses it to install Hammerspoon, OBS Studio, and a few other things.

To install Homebrew, paste this in Terminal:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then close and reopen your Terminal. Verify it's working:

```sh
brew --version
```

Should print something like `Homebrew 4.x.x`.

### 3. GitHub CLI (`gh`), authenticated

You need this to clone the private repo. Once Homebrew is installed:

```sh
brew install gh
gh auth login
```

`gh auth login` walks you through logging in to your GitHub account in a browser. Pick **GitHub.com** → **HTTPS** → **Login with a web browser**. Verify it worked:

```sh
gh auth status
```

Should show `Logged in to github.com account <yourname>`.

### 4. Repo access

You need read access to the private repo `superic/av-pain-reliever`. If you're reading this on GitHub, you've got it. If not, ask the repo owner to add you as a collaborator.

---

## What the wizard does, step by step

When you run `~/av-pain-reliever/wizard.sh`, it runs through 15 numbered steps. You'll see each one announced with a header like `Step 4/15 — Install Hammerspoon`, followed by a paragraph explaining what's about to happen, then the actual work.

You can re-run the wizard any time. It's **idempotent** — it detects what's already done and skips it. If you bail out partway through, just run it again.

Here's the full list of what each step does:

| # | What | Automated? |
|---|---|---|
| 1 | Pre-flight: check for macOS, Homebrew, `gh` | ✅ |
| 2 | Install `gum` (the wizard's UI library) via Homebrew | ✅ |
| 3 | Welcome banner + ready-to-start confirm | — |
| 4 | Install Hammerspoon via Homebrew (skipped if present) | ✅ |
| 5 | Install OBS Studio 28+ via Homebrew (skipped if present and recent enough) | ✅ |
| 6 | Download and install `obs-cmd` from GitHub releases | ✅ (sudo needed) |
| 7 | Symlink `~/.hammerspoon` to the repo (with backup if it exists) | ✅ |
| 8 | Launch Hammerspoon and open System Settings → Accessibility | 🟡 You toggle the switch |
| 9 | Type the names of locations you switch between | 🟡 You type |
| 10 | Generate `profiles.lua` from your location names | ✅ |
| 11 | Open OBS and turn on the WebSocket server | 🟡 You click 3 settings |
| 12 | Create one OBS scene per location | ✅ |
| 13 | Start OBS Virtual Camera + add camera sources to scenes | 🟡 You add cameras manually |
| 14 | Configure Zoom and Slack to "Same as System" + "OBS Virtual Camera" | 🟡 You click |
| 15 | Capture USB devices + audio for one location (run while docked) | ✅ + 🟡 |

Steps with 🟡 need a couple of clicks from you. The wizard tells you exactly what to click.

### Step 9 in detail: naming locations

The wizard asks you to type the names of every physical setup you switch between. Examples:

```
Home Office
Work Office
Conference Room
Coffee Shop
```

Type one per line, then press Ctrl+D (or leave a blank line and Enter) to finish. The wizard automatically adds **Laptop** as the fallback profile (used when no other profile matches — i.e., when you're undocked).

Don't worry about getting the list exhaustive. You can add more locations later with `~/av-pain-reliever/wizard.sh add-location`.

### Step 11 in detail: OBS WebSocket setup

This is the one place the wizard can't fully automate (OBS doesn't expose its own preferences via the API). The wizard tells you:

1. In OBS's menu bar, click **Tools → WebSocket Server Settings**
2. Tick **"Enable WebSocket server"**
3. Untick **"Enable Authentication"** (it only listens on `127.0.0.1`, low risk on a personal machine)
4. Leave the port at `4455`
5. Click **Apply** / **OK**

The wizard verifies it worked by sending a test command. If it can't reach OBS, it tells you and offers to retry.

### Step 13 in detail: adding camera sources to OBS scenes

The wizard creates the scenes (one per location) but can't add a camera to each scene because OBS's API doesn't let us enumerate the cameras attached to your Mac. So you do this part:

For each scene:
1. Click the scene name in OBS's **Scenes** panel (lower-left)
2. In the **Sources** panel, click **+**
3. Pick **Video Capture Device**
4. Name it anything and click OK
5. Pick the camera you use at that location from the **Device** dropdown

You only need to do this once per scene. If you don't have a camera for a location, you can skip it — the engine still switches audio for that profile.

### Step 15 in detail: capturing your first location

This requires you to be **physically AT one of your docked locations RIGHT NOW** with everything plugged in (dock, monitor, mic, speakers, etc.). The wizard:

1. Asks you which location this is
2. Reloads Hammerspoon to capture a fresh snapshot of attached USB devices and audio devices
3. Shows you a multi-select menu of USB devices — you pick the ones that uniquely identify this location (usually the dock, sometimes a monitor or specific peripheral)
4. Shows you a single-select menu of input devices — you pick the mic for this location
5. Shows you a single-select menu of output devices — you pick the speaker for this location
6. Shows you a summary, asks you to confirm
7. Writes everything to `profiles.lua`
8. Reloads Hammerspoon to apply the new profile
9. Optionally commits and pushes the change to your fork of the repo

After this, you've got at least one fully working profile. Capture additional locations later with the same `wizard.sh add-location` command.

---

## Adding more locations later

When you visit a new location for the first time (or re-do an existing one), run:

```sh
~/av-pain-reliever/wizard.sh add-location
```

It runs the same 12-step capture flow as Step 15 of the install wizard. You'll need to be docked at the location you're capturing.

You can also use this command to **update** an existing location — just pick its name from the menu. The new device data overwrites the old.

---

## Diagnostic: `wizard.sh status`

If something looks off, run:

```sh
~/av-pain-reliever/wizard.sh status
```

This prints a snapshot of everything: which dependencies are installed, which apps are running, whether `~/.hammerspoon` is symlinked correctly, the state of every profile in `profiles.lua`, and the last 10 lines of the engine log. Read-only — won't change anything.

Example output:

```
══ av-pain-reliever status ══

▶ Prerequisites
  ✓ macOS
  ✓ brew
  ✓ gh
  ✓ gum

▶ Hammerspoon
  ✓ Installed (v1.1.1)
  ✓ Running

▶ OBS Studio
  ✓ Installed (v32.1.2)
  ✓ Running
  ✓ obs-cmd: obs-cmd 1.0.0
  ✓ obs-cmd connected to OBS

▶ ~/.hammerspoon
  ✓ Symlinked to this repo

▶ Profiles
  ✓ Laptop (always matches; fallback)
  ✓ Home Office (2 fingerprint device(s))
  ✗ Work Office (placeholders — run wizard.sh add-location)
  ✗ Conference Room (placeholders — run wizard.sh add-location)
```

---

## Updating to a newer version

When the repo gets a fix or a new feature, update with:

```sh
git -C ~/av-pain-reliever pull
```

Then click the Hammerspoon menu bar icon (the hammer) and choose **Reload Config** — the engine picks up any changes immediately. Your `profiles.lua` is preserved across pulls (it's tracked in git, but you can commit your local edits to a branch if you want them backed up).

---

## Uninstalling

If you want to remove this entirely:

```sh
# 1. Stop the engine.
osascript -e 'tell application "Hammerspoon" to quit'

# 2. Remove the symlink (this does NOT delete the repo).
rm ~/.hammerspoon

# 3. Optionally remove Hammerspoon, OBS, and obs-cmd themselves.
brew uninstall --cask hammerspoon
brew uninstall --cask obs
sudo rm /opt/homebrew/bin/obs-cmd

# 4. Optionally delete the repo clone.
rm -rf ~/av-pain-reliever
```

If you had a `~/.hammerspoon` directory before this wizard ran, it was backed up to `~/.hammerspoon.backup-<timestamp>`. Restore it if you want:

```sh
mv ~/.hammerspoon.backup-<timestamp> ~/.hammerspoon
```

---

## Troubleshooting

**Run `wizard.sh status` first** — it'll surface most issues immediately.

For deeper digging, the engine logs everything to:

```
~/.hammerspoon/logs/av-pain-reliever.log
```

Tail it live to see what's happening as you dock/undock:

```sh
tail -f ~/.hammerspoon/logs/av-pain-reliever.log
```

### Nothing happens when I dock

1. Open the Hammerspoon Console (menu bar icon → Console). Confirm you see `av-pain-reliever loaded` near the top.
2. Tail the log file. Are USB events being recorded? If not, Hammerspoon may not have Accessibility permission. Check System Settings → Privacy & Security → Accessibility.
3. Run `wizard.sh status`. Are all profiles filled in (no placeholders)?
4. Re-run `wizard.sh add-location` for the location you're at.

### Audio doesn't switch but the notification fires

The audio device names in your profile don't match real devices. Look for `audio ... device '...' not found — skipping` warnings in the log file. Re-run `wizard.sh add-location` for that location to re-capture with current device names.

### OBS doesn't switch scenes

1. Is OBS running? `obs-cmd` requires the OBS app to be open.
2. Is the OBS WebSocket server enabled? OBS → Tools → WebSocket Server Settings → "Enable WebSocket server".
3. Does the OBS scene name match the `obsScene` in `profiles.lua` exactly? Case- and space-sensitive. (`wizard.sh status` will help you spot mismatches.)
4. Try `obs-cmd scene switch "Home Office"` from a terminal. If that fails, the engine fails too. Fix it at the CLI first.

### `obs-cmd` not found

Should have been installed during Step 6 of the wizard. To install manually:

```sh
# Apple Silicon Mac:
curl -L -o /tmp/obs-cmd.tar.gz https://github.com/grigio/obs-cmd/releases/latest/download/obs-cmd-arm64-macos.tar.gz
tar -xzf /tmp/obs-cmd.tar.gz -C /tmp/
sudo mv /tmp/obs-cmd /opt/homebrew/bin/obs-cmd
chmod +x /opt/homebrew/bin/obs-cmd
```

Intel Macs: replace `arm64-macos` with `x64-macos` and `/opt/homebrew/` with `/usr/local/`.

### The wrong profile is firing

Multiple profiles can match the same set of attached devices — when that happens, the **most specific** profile (the one with the most fingerprint devices) wins. If `work-office` is firing in the conference room, your `conference-room` profile probably needs an additional fingerprint device that's only present in the conference room (a speakerphone, a monitor, etc.). Re-run `wizard.sh add-location` for `conference-room` and pick more devices.

If two locations have the *exact same* USB devices (e.g., two identical CalDigit docks), USB vendor+product IDs alone aren't enough. We'd need to add USB serial-number matching. Open an issue.

### "AppleScript not enabled" warnings

The first time you run the wizard, Hammerspoon may not have AppleScript enabled yet, so the wizard falls back to asking you to manually click "Reload Config" in the Hammerspoon menu bar. After the first reload, `init.lua` enables AppleScript and subsequent reloads are automatic.

### Hammerspoon menu bar icon disappeared

Quit and relaunch:

```sh
osascript -e 'tell application "Hammerspoon" to quit'
open -a Hammerspoon
```

### I broke `profiles.lua`

The wizard creates a backup before any major edit, named like `profiles.lua.backup-20260430-153022`. Find the latest one and copy it over:

```sh
ls -lt ~/.hammerspoon/profiles.lua.backup-*
cp ~/.hammerspoon/profiles.lua.backup-<latest-timestamp> ~/.hammerspoon/profiles.lua
```

Then click Hammerspoon menu bar → Reload Config.

If there's no backup, the original file is in git history:

```sh
git -C ~/av-pain-reliever checkout HEAD -- profiles.lua
```

---

## How it works (under the hood)

For the curious. You don't need to read this to use it.

The engine is a single Lua file (`init.lua`, ~200 lines) that runs inside Hammerspoon, a free macOS automation framework. The flow is:

1. **Watch USB events.** `hs.usb.watcher` fires every time a USB device connects or disconnects. The engine subscribes.

2. **Debounce.** When you connect a dock, dozens of USB devices enumerate in a burst over a couple of seconds — the dock itself, then the monitor it daisy-chains, then the audio interface, then the keyboard hub, etc. We don't want to evaluate the profile mid-burst (we'd see a partial picture). So every USB event resets a 1.5-second timer; we only evaluate after the dust settles.

3. **Enumerate currently-attached devices.** `hs.usb.attachedDevices()` returns every USB device the system can see, with vendor IDs and product IDs.

4. **Match against profiles.** Each profile in `profiles.lua` lists a "fingerprint": one or more USB devices that must all be present for that profile to match. The engine checks each profile, keeps the matches, picks the most specific one (highest fingerprint count). If nothing matches, falls back to `laptop`.

5. **Apply the profile.** If the resolved profile is different from the last one applied:
   - `hs.audiodevice.findDeviceByName(...):setDefaultInputDevice()` — switch the system mic
   - `hs.audiodevice.findDeviceByName(...):setDefaultOutputDevice()` — switch the system speaker
   - `hs.task.new("/opt/homebrew/bin/obs-cmd", ..., {"scene", "switch", "<name>"})` — switch the OBS scene
   - `hs.notify.new(...):send()` — show you a notification

6. **Same profile resolving twice in a row is a no-op.** If you unplug a peripheral but the dock stays connected, the resolved profile doesn't change, so we don't re-set everything.

The Lua file is small and easy to read. If you want to understand or modify the engine, [`init.lua`](init.lua) is the place to start.

---

## Manual install (if you don't want the wizard)

If you'd rather do it yourself, here's the sequence:

```sh
# 1. Install dependencies.
brew install --cask hammerspoon
brew install --cask obs

# 2. Install obs-cmd (Apple Silicon — for Intel, swap arm64 for x64 and the install dir).
curl -L -o /tmp/obs-cmd.tar.gz https://github.com/grigio/obs-cmd/releases/latest/download/obs-cmd-arm64-macos.tar.gz
tar -xzf /tmp/obs-cmd.tar.gz -C /tmp/
sudo mv /tmp/obs-cmd /opt/homebrew/bin/obs-cmd
chmod +x /opt/homebrew/bin/obs-cmd

# 3. Clone the repo and symlink.
git clone https://github.com/superic/av-pain-reliever ~/av-pain-reliever
ln -s ~/av-pain-reliever ~/.hammerspoon

# 4. Launch Hammerspoon, accept Accessibility prompt.
open -a Hammerspoon

# 5. Edit profiles.lua by hand to match your locations and devices.
$EDITOR ~/av-pain-reliever/profiles.lua

# 6. Configure OBS websocket (Tools → WebSocket Server Settings → Enable, no auth, port 4455).
# 7. Create OBS scenes matching your profiles' obsScene names.
# 8. Start OBS Virtual Camera (button bottom-right of OBS).
# 9. In Zoom and Slack: mic = "Same as System", speaker = "Same as System", camera = "OBS Virtual Camera".
```

To capture USB IDs for `profiles.lua`:

```sh
system_profiler SPUSBDataType | less
```

Find your dock and peripherals in the output. Each entry has `Vendor ID` and `Product ID` lines.

To capture exact macOS audio device names: open the Hammerspoon Console (menu bar icon → Console), paste this Lua, press Enter:

```lua
for _, d in ipairs(hs.audiodevice.allDevices()) do
  print(d:name(), d:isInputDevice() and "in" or "", d:isOutputDevice() and "out" or "")
end
```

Use the printed strings exactly in `profiles.lua`.

---

## File reference

```
av-pain-reliever/
├── init.lua                    # The engine. Watches USB, switches audio + OBS.
├── profiles.lua                # Your location → device mappings. Wizard generates and updates this.
├── README.md                   # You are here.
├── LICENSE                     # MIT.
├── .gitignore                  # macOS junk + log files.
├── wizard.sh                   # Entry point. Dispatches to subcommands.
├── wizard/
│   ├── lib.sh                  # Shared helpers (gum prompts, slug conversions, Hammerspoon control)
│   ├── install.sh              # First-time install flow (15 steps)
│   ├── add-location.sh         # Capture-one-location flow (12 steps)
│   ├── status.sh               # Read-only diagnostic
│   ├── _generate-profiles.sh   # Generate a fresh profiles.lua from a list of names
│   ├── _update-profile.sh      # Surgically update one profile's data
│   └── _parse-snapshot.sh      # Extract device snapshot from the log
└── tests/
    ├── run.sh                  # Run all tests
    ├── _framework.sh           # Tiny bash test framework
    ├── test_lib.sh             # Pure-function tests
    ├── test_generate_profiles.sh
    ├── test_update_profile.sh
    ├── test_parse_snapshot.sh
    └── test_wizard.sh
```

`init.lua` is the only file Hammerspoon directly executes. It loads `profiles.lua` via `require`. Everything in `wizard/` and `tests/` is bash and never gets touched by Hammerspoon at runtime.

---

## Tests

The wizard has a test suite covering the helpers, profile generation, profile updates, and snapshot parsing. Run them all with:

```sh
~/av-pain-reliever/tests/run.sh
```

Currently 49 tests, all passing. They run in isolated tempdirs and don't touch your real `profiles.lua` or `~/.hammerspoon`.

If you contribute changes, run the tests before committing.

---

## License

MIT — see [LICENSE](LICENSE).
