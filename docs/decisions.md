# Decisions

What we know to be true about this product. The "Validated decisions" section is settled by the shipped implementation; the "Open questions" section is the punchlist of things that still need real-world data to answer.

For ongoing implementation work see [docs/architecture.md](architecture.md). For the V2 virtual-camera design see [docs/virtual-camera.md](virtual-camera.md).

## Target product

A distributable macOS menu-bar app that:

- Ships as a signed + notarized `.app` from GitHub Releases
- Auto-updates via Sparkle 2
- Has a real menu-bar UI for status and profile management
- Runs self-contained: no shell scripts, no third-party tools
- Configurable for non-developers (a typical non-coder collaborator should
  be able to install it without ever opening a terminal)

External behavior: USB-driven location detection → switch system audio
defaults + camera selection → notify.

---

## Validated design decisions

These are settled and validated by the shipped Swift implementation:

- **USB vendor + product ID is enough for fingerprinting** (no serial number
  matching needed). Confirmed by user not having two identical docks; revisit
  if a future user reports collisions.
- **1.5 second debounce window** correctly collapses dock-enumeration bursts
  into a single evaluation. Tested on CalDigit TS3 + LG UltraFine; full burst
  takes ~1 second, well under the window.
- **"Most-specific match wins" with alphabetical tiebreak** is the right
  resolution rule. Tested by having work-office + conference-room share the
  office dock; conference-room wins when its extra device is present.
- **"Same as System" for audio + the app's own virtual camera in Zoom/Slack
  is the right pattern.** No per-app routing complexity needed.
- **Notifications are useful, with a Settings toggle for users who prefer
  them off.** No structural changes needed; users who find toasts annoying
  can disable via Settings ("Send notifications when profiles change").
- **Profile change triggers don't need WiFi BSSID, Bluetooth, or calendar
  signals as a fallback.** USB alone has been sufficient for Eric's 4
  locations. Revisit if a real user can't disambiguate USB-only.
- **`profiles.toml` hand-editing is acceptable for power users**, but the
  wizard is the right onboarding for non-power-users. The Swift app should
  not require config-file editing for normal use, but should allow it as
  escape hatch.
- **No manual override.** Profile resolution is always driven by the
  currently-attached USB devices. The user has no use case for "force
  profile X regardless of what's plugged in." Implication: the menu bar
  UI does NOT need a "Switch to ▶" submenu in v1. The status item is
  display-only — current profile name + an icon, no profile picker.
  Confirmed by user 2026-04-30.
- **No per-app audio routing.** "Same as System" in every app is sufficient.
  No use case for Slack mic ≠ Zoom mic. Implication: Swift never needs to
  integrate with app-specific audio APIs (no aggregate device hacks, no
  per-app `defaults` plist editing). Engine only ever
  touches system default input/output. Confirmed by user 2026-04-30.

---

## Open questions

These can only be answered by real-world use. Each one is tagged with the
trigger condition that should prompt asking the user.

### Detection accuracy

- **Q: Has the 1.5s debounce ever been wrong?**
  Trigger: profile fires twice, fires with wrong fingerprint, or takes
  noticeably long. Implication: tune the constant, or make it configurable.
- **Q: Have you ever needed a non-USB signal to disambiguate locations?**
  Trigger: two locations have the same USB peripherals. Implication: app
  may need WiFi BSSID, Bluetooth peripherals, time of day, or calendar event
  matching. Each is a real chunk of work.

### Scope creep candidates

Things a real user might ask for. Not in v1, but kept here for v2 prioritization:

- Per-profile *display arrangement* (move windows when docking)
- *Crash and error reporting* (opt-in telemetry for unhandled crashes,
  plus an in-app viewer for recent OSLog failures so the user notices
  silent breakage without running `log show`)

---

## Resolved on 2026-05-09 (walkthrough)

Items moved out of "Open questions" / "Scope creep" because the walkthrough
on 2026-05-09 either confirmed enough real-world signal to settle them, or
explicitly dropped them as out-of-product:

- **vid/pid collision.** No collision across the author + 2 external users.
  Already covered by the validated decision above; the open question was
  redundant.
- **Menu bar shows current profile name.** Default ("yes") shipped and
  works for all 3 users. No noisiness complaints.
- **External user wizard sticks.** 2 external users completed the wizard
  without help. Save Logs for Support (PR #78) covers future stick reports.
- **Toast notifications useful or annoying?** A Settings toggle ("Send
  notifications when profiles change", defaults on) already ships, so
  this is user preference, not a code question. The walkthrough surfaced
  the question but the answer was already in the product.
- **Dropped scope-creep candidates** (out-of-product, not pursued):
  per-profile wallpaper; per-profile Karabiner profile switching;
  per-profile Bluetooth device connect/disconnect; per-profile VPN
  enable/disable; per-profile focus mode / Do Not Disturb.

---

