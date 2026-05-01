# AV Pain Reliever 💊

> Stop fiddling with your microphone, speakers, and webcam every time you switch desks. Your Mac will do it for you.

When you carry a MacBook between locations — say, your home office to your work desk to a conference room — your audio defaults usually need fixing every time. Different microphone, different speakers, sometimes a different camera. **AV Pain Reliever** notices which dock you've connected to and automatically:

- Sets your **system default microphone** to the right one for that location.
- Sets your **system default speaker** to the right one for that location.
- Switches your **video conferencing camera scene** to one that's pre-configured for that location (with overlays, lower-thirds, whatever you've set up).

You configure your video apps (Zoom, Slack, etc.) once to follow the system, and after that you never touch a microphone or camera setting again. Plug in, the right setup is active. Unplug, it goes back to your laptop's built-in mic and speakers.

---

## What you'll need

Three things, all free:

| What | Why | How to get it |
|---|---|---|
| A Mac running macOS | This only works on Mac. | You presumably already have one. |
| Homebrew | A free tool that installs other tools. We need it for the next steps. | See ["Installing Homebrew" below](#installing-homebrew). |
| GitHub CLI (`gh`), signed in | Needed to download the repo. | See ["Installing the GitHub CLI" below](#installing-the-github-cli). |

About 10 minutes for the whole thing if you've never done any of this before.

### Installing Homebrew

Open the **Terminal** app (press Cmd+Space, type `Terminal`, press Enter). Paste this and press Enter:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

It'll ask for your Mac password. After it finishes (a couple of minutes), close the Terminal window and open a new one. Type `brew --version` and press Enter. You should see something like `Homebrew 4.x.x`. If you do, you're done.

### Installing the GitHub CLI

In Terminal, type each of these commands one at a time, pressing Enter after each:

```sh
brew install gh
```

```sh
gh auth login
```

The second command opens an interactive prompt. Use the arrow keys and Enter to choose:
1. **GitHub.com**
2. **HTTPS**
3. **Login with a web browser**

It shows you an 8-character code like `ABCD-EFGH`. Copy it, then press Enter — your browser opens to GitHub. Paste the code, click Continue, then Authorize.

Back in Terminal, you should see `✓ Logged in as <your-username>`. Type `gh auth status` to double-check. You should see `Logged in to github.com account <yourname>`.

If you get stuck, the [GitHub CLI docs](https://cli.github.com/manual/) have the canonical instructions.

---

## Installing AV Pain Reliever

Once you have Homebrew and `gh`, paste this single command into Terminal:

```sh
gh repo clone superic/av-pain-reliever ~/av-pain-reliever && ~/av-pain-reliever/wizard.sh
```

This downloads the repo into a folder called `av-pain-reliever` in your home directory, then starts the setup wizard. The wizard takes you through every step.

You don't need to read any further unless you want to know exactly what to expect.

---

## What the wizard does (a walkthrough)

The wizard is **15 numbered steps**. Each one starts with a header like `▶ Step 4/15 — Install Hammerspoon` and a paragraph explaining what's about to happen. You'll see colored prompts asking you to confirm or pick from a menu.

**You can stop and re-run the wizard any time.** It remembers what's already done and skips it. Closing your laptop or quitting Terminal mid-wizard is fine — just run the command above again to pick up where you left off.

Here's what each step does. Most are automatic; a few need a click or two from you.

### Step 1: Pre-flight checks
Confirms you're on macOS and have Homebrew + the GitHub CLI installed. If anything's missing, the wizard tells you exactly what to install and stops cleanly so you can fix it.

**You do nothing.**

### Step 2: Install gum
Installs a small program called `gum` that gives the wizard nice colored menus and prompts. Takes 5–10 seconds.

**You do nothing.**

### Step 3: Welcome
Shows you the plan and asks if you're ready. Press Enter to start, or `n` to bail.

**You confirm.**

### Step 4: Install Hammerspoon
Hammerspoon is a free Mac automation tool — it's the engine that watches for your dock and switches things. It runs as a small icon (a hammer) in your menu bar. The wizard installs it via Homebrew. Takes 30–60 seconds.

**You do nothing.**

### Step 5: Install OBS Studio
OBS Studio is the camera scene switcher. It's the same app streamers use; we use it for its scene-switching API. The wizard installs it via Homebrew, or if you already have it, it checks the version. Takes 1–2 minutes if installing fresh.

**You do nothing.**

### Step 6: Install obs-cmd
A small command-line tool that lets us talk to OBS. Not in Homebrew, so the wizard downloads it directly from GitHub. **You'll be prompted for your Mac password** (it's installing into a system folder).

**You enter your password once.**

### Step 7: Wire up the engine's config folder
Hammerspoon looks for its config in a folder called `~/.hammerspoon`. The wizard makes that folder a "shortcut" (symlink) to the AV Pain Reliever folder, so when you update AV Pain Reliever, Hammerspoon picks up the changes automatically. **If you already have a `~/.hammerspoon` folder** (because you've used Hammerspoon before), the wizard backs it up to a timestamped folder so nothing is lost.

**You confirm if a backup is needed; otherwise nothing.**

### Step 8: Grant Accessibility permission
Hammerspoon needs permission to read USB events (so it can detect your dock) and change the system audio settings. macOS treats this as a security-sensitive permission. The wizard opens System Settings to the right pane for you. **You toggle the switch next to "Hammerspoon" to ON.** macOS will ask for your Mac password — that's normal.

You only have to do this once, ever.

**You toggle one switch and enter your password.**

### Step 9: Name your locations
The wizard asks you to type the names of the physical setups you switch between. Type one per line. Common examples:

```
Home Office
Work Office
Conference Room
Coffee Shop
```

When you're done, press Ctrl+D (or leave a blank line and press Enter). Don't worry about being exhaustive — you can add locations later. The wizard automatically adds **Laptop** to your list — that's the fallback profile for when you're undocked (just your MacBook on its own).

**You type your location names.**

### Step 10: Generate the config file
The wizard writes a file called `profiles.lua` that maps each of your locations to (eventually) the right microphone, speaker, and camera scene. At this stage the file has placeholders for everything except the basic structure — you'll fill in the real device data in Step 15.

**You do nothing.**

### Step 11: Turn on OBS's WebSocket server
OBS has a built-in feature that lets external tools (like AV Pain Reliever) control it. It's off by default. The wizard tells you exactly which menu items to click:

1. In OBS's menu bar (at the top of your screen when OBS is the active app): **Tools → WebSocket Server Settings**
2. Tick the box that says **"Enable WebSocket server"**
3. **Untick** the box that says **"Enable Authentication"** (the server only listens to your own Mac, so a password adds friction without real benefit)
4. Click **Apply** or **OK**

The wizard then sends a test signal to confirm it worked. If something's off (you missed a checkbox, OBS isn't open, etc.) it tells you and offers to retry.

**You click 3 settings in OBS.**

### Step 12: Create the OBS scenes
Each location you named in Step 9 gets its own OBS scene. The wizard creates them all automatically. Empty scenes are fine for now — you'll add the actual camera in Step 13.

**You do nothing.**

### Step 13: Start the OBS Virtual Camera and add your real cameras to each scene
The wizard turns on OBS's "Virtual Camera" output — that's what Zoom, Slack, etc. will see as your camera. You only do this once; OBS remembers it.

Then you add the actual physical camera you use at each location to the scene that matches it. The wizard can't do this part for you because OBS doesn't tell us what cameras you have. Instructions:

1. In the OBS window, find the **Scenes** panel in the lower-left.
2. Click on a scene name (e.g., `Home Office`).
3. In the **Sources** panel next to it, click the **+** button.
4. Pick **Video Capture Device** from the menu.
5. Give it any name and click OK.
6. From the **Device** dropdown, pick the camera you use at this location.
7. Click OK.
8. Repeat for each scene.

If you don't have a camera for a location yet (e.g., you're not at the coffee shop right now), you can skip it. The scene just needs to *exist* — you can add the camera later when you're there.

**You spend ~30 seconds per scene clicking through OBS.**

### Step 14: Configure Zoom and Slack
The whole point of this setup: Zoom and Slack should follow what your system is doing, instead of being told the specific microphone every time. The wizard opens each app for you and tells you what to set:

For each app:
- **Microphone** → "Same as System" (or "System Default" — same thing)
- **Speaker** → "Same as System"
- **Camera** → "OBS Virtual Camera"

You only do this once per app. After that, you never touch these settings again — Zoom and Slack inherit whatever AV Pain Reliever sets.

If you don't have Zoom or Slack installed, the wizard skips that app silently.

**You click through each app's settings.**

### Step 15: Capture your first dock location
The last step. To make sure you finish with at least one fully working profile, the wizard asks you to capture the location you're at right now.

For this to work, **be physically at one of your docked locations with everything plugged in** — your dock, monitor, microphone, speakers, anything else that's part of that setup. Wait ~5 seconds after plugging in the last thing for everything to register.

Then the wizard:
1. Asks which location you're at (pick from the menu).
2. Reloads the engine to take a fresh snapshot of all attached devices.
3. Shows you a multi-select list of USB devices and asks which ones identify this location. **Pick the dock itself** — that's almost always the right answer. Add a monitor or unique peripheral if you have the same dock model at multiple locations.
4. Shows you a list of microphones. Pick the one you want as the default here.
5. Shows you a list of speakers. Pick the one you want as the default here.
6. Shows you a summary, asks you to confirm.
7. Saves everything to `profiles.lua`.
8. Reloads the engine and confirms the new profile is active.

You'll see a notification ("Switched to: Home Office") and your system audio defaults change immediately.

**You make 3 picks from menus.**

After this, you have one fully working profile. To capture additional locations later, see [Adding more locations](#adding-more-locations) below.

---

## Adding more locations

Whenever you visit a location for the first time after the initial install — or any time you want to change what an existing location uses — open Terminal and run:

```sh
~/av-pain-reliever/wizard.sh add-location
```

It runs the same 12-step capture flow as Step 15 of the install wizard. You need to be physically at the location with everything plugged in.

---

## Checking that everything's working

In Terminal:

```sh
~/av-pain-reliever/wizard.sh status
```

This shows you a snapshot of everything: which dependencies are installed, which apps are running, whether the config file is in good shape, and the most recent activity log. Read-only — won't change anything.

You'll see something like this:

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

A green ✓ means good. A red ✗ tells you what's missing and usually how to fix it.

---

## Updating to a newer version

When the project gets a fix or new feature, update with:

```sh
git -C ~/av-pain-reliever pull
```

Then click the Hammerspoon icon (the hammer) in your menu bar and choose **Reload Config**. The engine picks up the changes immediately. Your `profiles.lua` (with all your captured locations) is preserved.

---

## Troubleshooting

If something looks off, the **first thing to do** is run the status command:

```sh
~/av-pain-reliever/wizard.sh status
```

It surfaces most issues immediately, with hints on how to fix them.

If you need to dig deeper, the engine writes everything to a log file. Tail it live in Terminal:

```sh
tail -f ~/.hammerspoon/logs/av-pain-reliever.log
```

Now plug or unplug your dock — you'll see exactly what the engine is doing. Press Ctrl+C to stop tailing.

### Common issues

**Nothing happens when I dock.**
1. Run the status command. Are all your profiles filled in (no red ✗ marks)?
2. Tail the log file. Plug in your dock. Are USB events being recorded? If not, the engine might not have Accessibility permission. Open System Settings → Privacy & Security → Accessibility and check that Hammerspoon is toggled ON.

**Audio doesn't switch but a notification fires.**
The audio device name in your profile doesn't match a real device on your Mac. Re-run `~/av-pain-reliever/wizard.sh add-location` for that location to re-capture.

**OBS doesn't switch scenes.**
1. Is OBS open? It needs to be running.
2. Is OBS's WebSocket server still on? OBS → Tools → WebSocket Server Settings → "Enable WebSocket server" should be ticked.
3. Does the OBS scene name match what's in your config? The status command will tell you.

**The wrong location is firing.**
If two locations have *some* of the same USB devices (e.g., the same dock at home and at the office), the location with **more** required devices wins. So if your conference room shares the office dock, your `Conference Room` profile needs to require something the conference room has that the office doesn't (like a specific speakerphone). Re-run `add-location` and add it to the fingerprint.

**I broke the config file.**
The wizard makes a backup before any major edit. Find the most recent one in Terminal:

```sh
ls -lt ~/av-pain-reliever/profiles.lua.backup-*
```

Then restore it:

```sh
cp ~/av-pain-reliever/profiles.lua.backup-<the-latest-timestamp> ~/av-pain-reliever/profiles.lua
```

Click Hammerspoon → Reload Config. You're back to working.

**"AppleScript not enabled" warning the first time.**
The very first time you ever run the wizard on a Mac, you may see a one-time message asking you to manually click "Reload Config" in Hammerspoon's menu. After that, the wizard reloads automatically.

---

## Uninstalling

If you want to remove AV Pain Reliever from your Mac, paste these into Terminal one at a time:

```sh
osascript -e 'tell application "Hammerspoon" to quit'
```

```sh
rm ~/.hammerspoon
```

That stops the engine and removes the config link. Your profile data and the project folder still exist. To remove those too:

```sh
rm -rf ~/av-pain-reliever
```

To remove Hammerspoon and OBS themselves (only do this if no other tools rely on them):

```sh
brew uninstall --cask hammerspoon
brew uninstall --cask obs
sudo rm /opt/homebrew/bin/obs-cmd
```

If you had a `~/.hammerspoon` folder before AV Pain Reliever was installed, it was backed up. To restore it:

```sh
mv ~/.hammerspoon.backup-<timestamp> ~/.hammerspoon
```

(Replace `<timestamp>` with the actual one. List backups with `ls -d ~/.hammerspoon.backup-*`.)

---

## License

MIT. See the [LICENSE](LICENSE) file.

---

# Nerd zone

Everything below this line is for technically-curious users and contributors. **You don't need any of it to install or use AV Pain Reliever.** Skip to the bottom of the page if you came here for the install instructions.

---

## How it works under the hood

AV Pain Reliever is a single Lua file (`init.lua`, ~200 lines) that runs inside [Hammerspoon](https://www.hammerspoon.org/), a free macOS automation framework. The flow:

1. **Watch USB events.** `hs.usb.watcher` fires every time a USB device connects or disconnects. The engine subscribes.
2. **Debounce.** When you connect a dock, dozens of devices enumerate in a burst over a couple of seconds. We don't want to evaluate the profile mid-burst (we'd see a partial picture). So every USB event resets a 1.5-second timer; we only evaluate after the dust settles.
3. **Enumerate currently-attached devices.** `hs.usb.attachedDevices()` returns every USB device with vendor and product IDs.
4. **Match against profiles.** Each profile in `profiles.lua` lists a "fingerprint": one or more USB devices that must all be present for that profile to match. The engine checks each profile, keeps the matches, picks the most specific one (highest fingerprint count). Ties are broken alphabetically. If nothing matches, it falls back to `laptop`.
5. **Apply the profile.** If the resolved profile is different from the last one applied:
   - `hs.audiodevice.findDeviceByName(...):setDefaultInputDevice()` — switch the system mic
   - `hs.audiodevice.findDeviceByName(...):setDefaultOutputDevice()` — switch the system speaker
   - `hs.task.new("/opt/homebrew/bin/obs-cmd", ..., {"scene", "switch", "<name>"})` — switch the OBS scene
   - `hs.notify.new(...):send()` — show a notification
6. **Same profile resolving twice in a row is a no-op.** If you unplug a peripheral but the dock stays connected, the resolved profile doesn't change, so we don't re-set everything.

The Lua file is small and easy to read. [`init.lua`](init.lua) is the place to start.

---

## File reference

```
av-pain-reliever/
├── init.lua                    # The engine. Watches USB, switches audio + OBS.
├── profiles.lua                # Your location → device mappings. Wizard generates and updates this.
├── README.md                   # You are here.
├── LICENSE                     # MIT.
├── .gitignore                  # macOS junk + log files.
├── SWIFT_PORT.md               # Living design plan for an eventual Swift native app.
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

## Manual install (without the wizard)

If you'd rather do it yourself:

```sh
# Dependencies.
brew install --cask hammerspoon
brew install --cask obs

# obs-cmd (Apple Silicon — for Intel, swap arm64 → x64 and /opt/homebrew → /usr/local).
curl -L -o /tmp/obs-cmd.tar.gz https://github.com/grigio/obs-cmd/releases/latest/download/obs-cmd-arm64-macos.tar.gz
tar -xzf /tmp/obs-cmd.tar.gz -C /tmp/
sudo mv /tmp/obs-cmd /opt/homebrew/bin/obs-cmd
chmod +x /opt/homebrew/bin/obs-cmd

# Repo + symlink.
git clone https://github.com/superic/av-pain-reliever ~/av-pain-reliever
ln -s ~/av-pain-reliever ~/.hammerspoon

# Launch Hammerspoon, accept Accessibility prompt.
open -a Hammerspoon

# Edit profiles.lua to match your locations and devices.
$EDITOR ~/av-pain-reliever/profiles.lua

# Configure OBS WebSocket (Tools → WebSocket Server Settings → Enable, no auth, port 4455).
# Create one OBS scene per profile, matching the obsScene field.
# Start OBS Virtual Camera (button bottom-right).
# In Zoom and Slack: mic + speaker = "Same as System", camera = "OBS Virtual Camera".
```

To capture USB IDs by hand:

```sh
system_profiler SPUSBDataType | less
```

Each entry has a `Vendor ID` and `Product ID`.

To capture exact macOS audio device names, open the Hammerspoon Console (menu bar icon → Console), paste this, press Enter:

```lua
for _, d in ipairs(hs.audiodevice.allDevices()) do
  print(d:name(), d:isInputDevice() and "in" or "", d:isOutputDevice() and "out" or "")
end
```

Use the printed strings exactly in `profiles.lua`.

---

## Tests

The wizard has a test suite covering the helpers, profile generation, profile updates, and snapshot parsing:

```sh
~/av-pain-reliever/tests/run.sh
```

Currently 49 tests, all passing. They run in isolated tempdirs and don't touch the real `profiles.lua` or `~/.hammerspoon`.

If you contribute changes, run the tests before committing.

---

## Bash compatibility

All wizard scripts work under macOS's system bash 3.2 (`/bin/bash`). No `mapfile`, no `declare -A`, no `${var,,}`. The `tests/test_wizard.sh` suite has explicit checks for bash-4-only features so we don't regress.

---

## Engine reload mechanism

`init.lua` calls `hs.allowAppleScript(true)` so the wizard can reload Hammerspoon programmatically:

```sh
osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"'
```

The wizard's `lib.sh` exposes `hammerspoon_reload` and `hammerspoon_reload_with_fallback` helpers; the latter prompts the user to manually click "Reload Config" if AppleScript isn't enabled yet (one-time chicken-and-egg on the very first install before `init.lua` has run).

---

## Why OBS instead of Camo / Restream / Ecamm

OBS Studio is the only Mac webcam tool with a documented, stable scene-switch-by-name API (`obs-websocket` v5, exposed via `obs-cmd`). Camo Studio for Mac has overlays but no API for switching saved scene/overlay combos. Ecamm Live is hotkey-driven (no API). OBS's UI is rougher but it's the only tool that fits the automation requirement. Verified during planning; see [SWIFT_PORT.md](SWIFT_PORT.md) for the full decision log.

---

## Long-term direction

The Hammerspoon prototype is the research vehicle. The ultimate target is a distributable native macOS menu-bar app (signed, notarized, auto-updating). See [SWIFT_PORT.md](SWIFT_PORT.md) for the running design plan, including which decisions are locked, which are still open, and lessons learned from real-world use of the prototype.

---

## Contributing

Standard GitHub flow: fork, branch, PR. Run `tests/run.sh` and `shellcheck wizard.sh wizard/*.sh` before opening a PR. Follow the existing wizard messaging style: each step starts with a paragraph explaining what's about to happen, in plain language.
