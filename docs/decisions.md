# Decisions

What we know to be true about this product, captured before the Swift code was written. The "Validated decisions" section was settled by Phase 1 use of the Hammerspoon prototype; the "Open questions" section is the punchlist of things that still need real-world data to answer.

For ongoing implementation work see [docs/architecture.md](architecture.md). For the V2 virtual-camera design see [docs/virtual-camera.md](virtual-camera.md).

## Target product

A distributable macOS menu-bar app that does what `init.lua` + `profiles.lua`
do today, but:

- Ships as a signed + notarized `.app` from GitHub Releases
- Auto-updates via Sparkle 2
- Has a real menu-bar UI for status, manual override, profile management
- Doesn't require Hammerspoon, Lua, or shell scripts to install or use
- Configurable for non-developers (a typical non-coder collaborator should be
  able to install it without ever opening a terminal — though we accept that
  the wizard's "open OBS and click these settings" steps will probably remain
  manual until OBS adds API surface for them)

Same external behavior as the Hammerspoon engine: USB-driven location detection
→ switch system audio defaults + OBS scene → notify.

---

## Validated design decisions

These are settled by Phase 1 use and can be assumed when we start Swift:

- **USB vendor + product ID is enough for fingerprinting** (no serial number
  matching needed). Confirmed by user not having two identical docks; revisit
  if a future user reports collisions.
- **1.5 second debounce window** correctly collapses dock-enumeration bursts
  into a single evaluation. Tested on CalDigit TS3 + LG UltraFine — full burst
  takes ~1 second, well under the window.
- **"Most-specific match wins" with alphabetical tiebreak** is the right
  resolution rule. Tested by having work-office + conference-room share the
  office dock; conference-room wins when its extra device is present.
- **`obs-cmd` shell-out is fine** as the OBS integration. No need to write a
  native obs-websocket WebSocket client — the CLI is stable, fast, and handles
  the auth dance for us.
- **OBS scenes are the right unit of switching.** Each scene bundles camera +
  overlays + audio routing. The "one scene per location" mental model is clean.
- **Camo is not a viable alternative.** Verified during planning: Camo's only
  automation surface is macOS Shortcuts, which can switch the *device* but not
  a saved overlay/scene combo by name. If overlays are wanted, OBS is the
  answer.
- **"Same as System" + OBS Virtual Camera in Zoom/Slack is the right
  pattern.** No per-app routing complexity needed.
- **`hs.notify` notifications are useful.** No real-world annoyance reported
  yet; will revisit if user complains.
- **Profile change triggers don't need WiFi BSSID, Bluetooth, or calendar
  signals as a fallback.** USB alone has been sufficient for Eric's 4
  locations. Revisit if a real user can't disambiguate USB-only.
- **profiles.lua hand-editing is acceptable for power users**, but the wizard
  is the right onboarding for non-power-users. The Swift app should not
  require config-file editing for normal use, but should allow it as escape
  hatch.
- **No manual override.** Profile resolution is always driven by the
  currently-attached USB devices. The user has no use case for "force
  profile X regardless of what's plugged in." Implication: the menu bar
  UI does NOT need a "Switch to ▶" submenu in v1. The status item is
  display-only — current profile name + an icon, no profile picker.
  Confirmed by user 2026-04-30.
- **No per-app audio routing.** "Same as System" in every app is sufficient.
  No use case for Slack mic ≠ Zoom mic. Implication: Swift never needs to
  integrate with app-specific audio APIs (no Audio Hijack-style aggregate
  device hacks, no per-app `defaults` plist editing). Engine only ever
  touches system default input/output. Confirmed by user 2026-04-30.

---

## Open questions

These can only be answered by real-world Phase 1 use. Each one is tagged with
the trigger condition that should prompt asking the user.

### Detection accuracy

- **Q: Do you ever own two devices with identical (vid, pid)?**
  Trigger: a profile resolves wrong because two locations share peripheral
  models. Implication: Swift may need USB serial number matching, which is
  cheap to add via IOKit but absent in `hs.usb.attachedDevices()` (the Lua
  wrapper doesn't expose it).
- **Q: Has the 1.5s debounce ever been wrong?**
  Trigger: profile fires twice, fires with wrong fingerprint, or takes
  noticeably long. Implication: tune the constant in Swift, or make it
  configurable.
- **Q: Have you ever needed a non-USB signal to disambiguate locations?**
  Trigger: two locations have the same USB peripherals. Implication: Swift
  may need WiFi BSSID, Bluetooth peripherals, time of day, or calendar event
  matching. Each is a real chunk of work.

### User experience

- **Q: After a couple weeks of use, are the notifications useful or
  annoying?** Trigger: user complaint OR explicit ask after ~2 weeks.
  Options: silent / banner-only / banner+sound / configurable per-profile.
- **Q: Should the menu bar icon show the current profile name?**
  Trigger: user asks how to tell which profile is active without opening
  the menu. Implication: status item title shows pretty profile name.
  *(Default: yes. Cheap to implement, useful at-a-glance signal. Revisit if
  user finds the title bar noise distracting.)*

### Scope creep candidates

These are things a real user might ask for. Not in v1, but capture them as
they come up so we can prioritize for v2:

- Per-profile *display arrangement* (move windows when docking)
- Per-profile *wallpaper*
- Per-profile *Karabiner profile* switching
- Per-profile *Bluetooth device* connect/disconnect
- Per-profile *VPN* enable/disable
- Per-profile *focus mode* / *Do Not Disturb*
- Hammerspoon → Swift *config import* (read existing `profiles.lua` and
  generate `profiles.toml`)

### Onboarding

- **Q: Did the first external user get all the way through the Phase 1.5
  wizard without asking for help? Where did they stick?** Trigger: after
  the first non-author user runs the wizard. Implication: directly
  informs whether the bash + gum approach is scalable, OR if the Swift
  app needs a full GUI installer (DMG with drag-to-Applications, then
  in-app first-run wizard).
- **Q: How often does Hammerspoon get reloaded vs. the engine just running
  in the background?** Trigger: usage data over 2-3 weeks. Implication: if
  reloads are frequent, Swift needs a clean "reload config" menu item; if
  rare, we can require quit-and-relaunch.

---

