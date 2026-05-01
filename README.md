# av-pain-reliever

Location-aware AV switcher for macOS. When you dock your MacBook, it automatically switches the system default microphone, system default speaker, and OBS scene (camera + overlays + audio routing) to match the location. Detection runs off USB device fingerprinting via Hammerspoon's `hs.usb.watcher` — not WiFi SSID, which isn't unique enough across many setups.

Set Zoom and Slack to "Same as System" for audio and "OBS Virtual Camera" for video, and they'll inherit the right devices automatically wherever you dock.

## How it works

- A small Hammerspoon Lua engine (`init.lua`) listens for USB connect/disconnect events.
- USB events arrive in bursts when a dock connects, so the engine waits 1.5s after the last event before evaluating.
- It then enumerates currently-attached USB devices and compares them against the profiles you've defined in `profiles.lua`.
- Each profile is a list of required USB devices (vendor ID + product ID). A profile matches if all its required devices are present. The most specific match (most devices) wins. If nothing matches, it falls back to `laptop`.
- On a profile *change*, it sets the system audio defaults, switches the OBS scene via `obs-cmd`, and shows a notification. Same profile resolving twice in a row is a no-op.

## Prerequisites

- **Hammerspoon** — `brew install --cask hammerspoon`
- **OBS Studio 28+** — `brew install --cask obs` (28+ ships with `obs-websocket` built in)
- **obs-cmd** — small CLI that talks to OBS's WebSocket server. Two install options:
  - **Pre-built binary**: download the macOS release from <https://github.com/grigio/obs-cmd/releases>, `chmod +x` it, drop it in `/opt/homebrew/bin/` (or `/usr/local/bin/` on Intel).
  - **From source (Rust)**: `cargo install obs-cmd` — installs to `~/.cargo/bin/obs-cmd`.

The engine looks for `obs-cmd` at `/opt/homebrew/bin/obs-cmd`, `/usr/local/bin/obs-cmd`, then `~/.cargo/bin/obs-cmd` and uses the first one that exists. If none, it logs a warning and skips OBS switching (audio still works).

## Install

1. Clone this repo wherever you keep your projects:
   ```sh
   git clone <your-fork-url> ~/Documents/Dev/av-pain-reliever
   ```
2. Symlink it into Hammerspoon's expected config location:
   ```sh
   # Make sure ~/.hammerspoon doesn't already exist (or back it up).
   ln -s ~/Documents/Dev/av-pain-reliever ~/.hammerspoon
   ```
3. Launch Hammerspoon. Approve the Accessibility permission prompt.
4. Click the Hammerspoon menu bar icon → "Console". You should see lines like:
   ```
   av-pain-reliever loaded (obs-cmd: /opt/homebrew/bin/obs-cmd)
   evaluation → laptop
   applying profile: laptop
   ```

## One-time OBS setup

1. Launch OBS Studio.
2. Tools → WebSocket Server Settings:
   - Tick "Enable WebSocket server".
   - For local-only use, untick "Enable Authentication" (everything is on `127.0.0.1:4455`, low risk on a personal machine). If you'd rather keep auth on, see "obs-cmd with authentication" in Troubleshooting.
3. Create one OBS scene per location (Scenes panel, "+"). Name them exactly the same as the `obsScene` value in `profiles.lua` — `Laptop`, `Home Office`, `Work Office`, `Conference Room`. Add to each scene:
   - A **Video Capture Device** source pointing at the camera you use at that location.
   - Any overlays (Image, Text, Browser sources) you want for that look.
4. Verify from a terminal that the integration round-trips:
   ```sh
   obs-cmd scene switch "Home"
   ```
   OBS should flip to the Home scene immediately.
5. Click "Start Virtual Camera" in OBS (bottom-right). This persists across launches; you only need to click it once.

## One-time Zoom / Slack setup

In each app:
- **Microphone**: "Same as System"
- **Speaker**: "Same as System"
- **Camera**: "OBS Virtual Camera"

Now Zoom and Slack always use the right devices wherever you dock — Hammerspoon switches the system defaults and OBS switches the camera scene, and both apps follow.

## Adding or editing a profile

Edit `profiles.lua`. Each entry needs:
- `fingerprint` — list of `{ vendorID = 0x..., productID = 0x..., name = "..." }`. The `name` is just a comment for you; only `vendorID` and `productID` are used for matching.
- `audioInput` — exact macOS device name string, or `nil` to skip.
- `audioOutput` — exact macOS device name string, or `nil` to skip.
- `obsScene` — exact OBS scene name, or `nil` to skip.

After editing, reload Hammerspoon: menu bar icon → "Reload Config", or `Cmd+Ctrl+R` if you've bound it.

### Capturing USB vendor and product IDs

Dock at the location, then run:

```sh
system_profiler SPUSBDataType
```

Find your dock and peripherals in the output. You'll see lines like:

```
CalDigit TS4:

  Product ID: 0x0fff
  Vendor ID:  0x2188  (CalDigit, Inc.)
```

Copy those `0x....` values into the matching `fingerprint` entry.

### Capturing exact audio device names

Open the Hammerspoon Console (menu bar icon → Console) and paste:

```lua
for _, d in ipairs(hs.audiodevice.allDevices()) do
  print(d:name(), d:isInputDevice() and "in" or "", d:isOutputDevice() and "out" or "")
end
```

Press Enter. Use the printed strings *exactly* — including spaces and capitalization.

## Logs and debugging

Tail the live log:

```sh
tail -f ~/.hammerspoon/logs/av-pain-reliever.log
```

You'll see every USB event, every profile evaluation, every switch, and every warning. Lines look like:

```
2026-04-30 14:22:11 INFO  USB added: CalDigit TS4 (vid=8584 pid=4095)
2026-04-30 14:22:13 INFO  evaluation → home
2026-04-30 14:22:13 INFO  applying profile: home
2026-04-30 14:22:13 INFO  set default input: Shure MV7
2026-04-30 14:22:13 INFO  set default output: AirPods Pro
2026-04-30 14:22:13 INFO  OBS scene switched: Home
```

## Troubleshooting

**Nothing happens when I dock.**
- Open the Hammerspoon Console — is the engine even loaded? You should see "av-pain-reliever loaded".
- Tail the log. Are USB events being logged at all? If not, Hammerspoon may not have USB watcher permissions.
- Check that the vendor/product IDs in `profiles.lua` actually match what `system_profiler SPUSBDataType` shows when docked.

**Audio doesn't switch but the notification fires.**
- The device name in `profiles.lua` doesn't match. Re-run the audio-name snippet above and copy the strings exactly.
- Look for `audio ... device '...' not found` warnings in the log.

**OBS doesn't switch.**
- Is OBS running? `obs-cmd` requires the OBS app to be open.
- Is obs-websocket enabled? OBS → Tools → WebSocket Server Settings → "Enable WebSocket server".
- Does the OBS scene name in `profiles.lua` match the scene name in OBS *exactly*?
- Try `obs-cmd scene switch "Home"` from a terminal. If that fails, the engine will fail too. Fix it at the CLI first.
- Check the log for `obs-cmd exit ...` lines — `stderr` is included.

**`obs-cmd` not found.**
- Confirm with `which obs-cmd`. If empty, install via one of the methods in Prerequisites.
- The engine logs `obs-cmd not found in ...` at load time. Audio still switches; only OBS is skipped.

**The wrong profile is firing.**
- Multiple profiles can match — the one with the most fingerprint devices wins. If `work-office` is firing in the conference room, add a conference-room-only USB device to the `conference-room` fingerprint so it out-specifies `work-office`.
- If two locations share *all* peripherals (e.g. two identical CalDigit docks), USB vendor+product alone isn't enough — we'll need to add USB serial number matching. Open an issue.

**`obs-cmd` with authentication.**
- If you keep auth enabled in obs-websocket, create `~/.config/obs-cmd/config.toml` with:
  ```toml
  websocket_url = "ws://127.0.0.1:4455"
  password = "your-obs-websocket-password"
  ```
- Or pass `--websocket "ws://localhost:4455" --password "..."` flags — but then you'd need to wire those into `init.lua`. The config file is simpler.

## License

MIT — see [LICENSE](LICENSE).
