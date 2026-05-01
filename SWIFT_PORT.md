# Swift native app — running plan

This is a living document. The ultimate goal of this project is a distributable
native macOS menu-bar app. The Hammerspoon prototype + wizard (Phase 1 / 1.5) is
the *research vehicle* whose job is to surface real-world constraints, edge
cases, and UX decisions before we commit to ~25–30 hours of Swift work that
locks in design assumptions.

Every time we learn something during Phase 1 use that should influence the Swift
design, capture it here. Every time we hit a question we can only answer via
real-world use, log it under "Open questions" so we remember to revisit it once
we have data.

**Status:** Phase 1.5 (wizard) in progress on `wizard-hardening` branch as of
2026-04-30. Swift port not yet started.

---

## Target product

A distributable macOS menu-bar app that does what `init.lua` + `profiles.lua`
do today, but:

- Ships as a signed + notarized `.app` from GitHub Releases
- Auto-updates via Sparkle 2
- Has a real menu-bar UI for status, manual override, profile management
- Doesn't require Hammerspoon, Lua, or shell scripts to install or use
- Configurable for non-developers (a CEO should be able to install it without
  ever opening a terminal — though we accept that the wizard's "open OBS and
  click these settings" steps will probably remain manual until OBS adds API
  surface for them)

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

---

## Locked architectural choices for the Swift port

These can be considered final unless we discover a blocker:

- **App target**: SwiftUI app with `LSUIElement = true` (no Dock icon, menu
  bar only). Bundle ID `com.ericwillis.avpainreliever`.
- **Frameworks**:
  - `IOKit/usb` for USB device enumeration + notifications via notification
    port + run loop integration
  - `CoreAudio` for default device get/set, wrapped with `SimplyCoreAudio`
    SPM dep to hide the worst of the C APIs
  - `Foundation.Process` to shell out to `obs-cmd` (reuse the Phase 1
    dependency rather than write a native WebSocket client)
  - `UserNotifications` for the toast (replaces `hs.notify`)
  - `os.Logger` for logging into Console.app (replaces file appender)
  - `AppKit.NSStatusItem` for the menu bar icon + menu
  - `Sparkle` 2 (SPM) for auto-updates with EdDSA signing
- **Distribution**: GitHub Releases via GitHub Actions on tag push. Build,
  sign with Apple Developer cert (in repo secrets), notarize via `notarytool`,
  upload `.app.zip`, update Sparkle appcast.
- **Apple Developer Program** ($99/yr) — confirmed user is fine paying.
- **Config file format**: TOML. JSON is too noisy; YAML's whitespace
  sensitivity is dangerous; TOML is the cleanest fit for human-edited config.
  Lives at `~/Library/Application Support/AVPainReliever/profiles.toml`.

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
- **Q: Do you ever want to manually override the auto-detected profile?**
  Trigger: user reports they wanted X but engine fired Y, and they had to
  hand-fix audio or OBS. Implication: Swift needs a "Switch to:" submenu in
  the menu bar status item.
- **Q: Should the menu bar icon show the current profile name?**
  Trigger: user asks how to tell which profile is active without opening
  the menu. Implication: status item title shows pretty profile name.
- **Q: Per-app audio routing — does Slack ever need to differ from Zoom?**
  Trigger: user mentions wanting different mic for different apps.
  Implication: a much bigger feature; Swift would need to hook each app's
  audio (probably via `defaults` plist edits or a CoreAudio aggregate device
  hack). Defer unless explicitly requested.

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

- **Q: Did the CEO get all the way through the Phase 1.5 wizard without
  asking for help? Where did he stick?** Trigger: after CEO uses it for
  the first time. Implication: directly informs whether the bash + gum
  approach is scalable, OR if the Swift app needs a full GUI installer
  (DMG with drag-to-Applications, then in-app first-run wizard).
- **Q: How often does Hammerspoon get reloaded vs. the engine just running
  in the background?** Trigger: usage data over 2-3 weeks. Implication: if
  reloads are frequent, Swift needs a clean "reload config" menu item; if
  rare, we can require quit-and-relaunch.

---

## Architecture sketch

```
av-pain-reliever-mac/
├── Package.swift                     # or .xcodeproj — TBD by build complexity
├── Sources/AVPainReliever/
│   ├── App.swift                     # @main, NSApplicationDelegate, LSUIElement
│   ├── StatusItem.swift              # menu bar icon + menu (current profile,
│   │                                 # manual override submenu, settings, quit)
│   ├── Engine/
│   │   ├── ProfileResolver.swift     # USB enumeration + fingerprint matching
│   │   ├── ProfileApplier.swift      # audio + OBS switching
│   │   ├── Debouncer.swift           # 1.5s coalescing
│   │   └── USBWatcher.swift          # IOKit notification port wrapper
│   ├── Adapters/
│   │   ├── AudioController.swift     # SimplyCoreAudio wrapper
│   │   ├── OBSController.swift       # obs-cmd Process wrapper
│   │   └── Notifier.swift            # UserNotifications wrapper
│   ├── Config/
│   │   ├── Profile.swift             # Codable struct mirroring profiles.lua schema
│   │   ├── ConfigLoader.swift        # reads ~/Library/Application Support/...
│   │   └── ConfigImporter.swift      # one-shot import from existing profiles.lua
│   ├── UI/
│   │   ├── PreferencesWindow.swift   # SwiftUI preferences (profile editor)
│   │   ├── FirstRunWizard.swift      # SwiftUI first-run flow
│   │   └── DeviceCapture.swift       # SwiftUI capture flow (replaces wizard's
│   │                                 # add-location subcommand)
│   └── Logging.swift                 # os.Logger setup
├── Resources/                        # assets, default profiles.toml template
├── Tests/                            # easy unit-testable seams (resolver,
│                                     # debouncer, profile parser)
├── .github/workflows/release.yml     # build, sign, notarize, publish, appcast
├── README.md
└── LICENSE
```

`StatusItem` is the central UI surface — most users never open the preferences
window. Menu structure (provisional):

```
🎧 Home Office             ← current profile, click for context
─────────────
Switch to ▶ ┌─────────────┐
              │ ✓ Home Office │
              │   Work Office │
              │   Conference Room │
              │   Laptop      │
              ├─────────────┤
              │ Auto-detect  │  ← restore auto-resolution
              └─────────────┘
─────────────
Open OBS
Open Hammerspoon log... (or our equivalent)
─────────────
Preferences...            ← opens SwiftUI preferences window
Quit AV Pain Reliever
```

---

## Distribution plan

1. Apple Developer Program signup (one-time, $99/yr).
2. Generate Developer ID Application certificate; export to `.p12`.
3. GitHub Actions secrets:
   - `MACOS_CERTIFICATE` (base64-encoded `.p12`)
   - `MACOS_CERTIFICATE_PASSWORD`
   - `MACOS_KEYCHAIN_PASSWORD` (random)
   - `APPLE_ID` (developer email)
   - `APPLE_ID_PASSWORD` (app-specific password from appleid.apple.com)
   - `APPLE_TEAM_ID`
   - `SPARKLE_PRIVATE_KEY` (EdDSA private key, generated with Sparkle's
     `generate_keys` tool)
4. On `git tag v*.*.*` push:
   - GitHub Actions: build with Xcode → codesign with hardened runtime →
     ditto into a zip → submit to notarytool → wait for ticket → staple →
     attach to GitHub Release → sign with Sparkle private key → update
     `appcast.xml` in repo → commit-and-push appcast.
5. Sparkle in-app reads `appcast.xml` from a known URL (probably
   `https://raw.githubusercontent.com/superic/av-pain-reliever/main/appcast.xml`).

Possible v2 distribution: submit to homebrew-cask. Would let people install via
`brew install --cask av-pain-reliever` instead of GitHub download.

---

## Effort estimate (Claude doing the work)

Originally estimated 22-32h, 6-10 sessions. Updated estimate based on what
we've learned through Phase 1 / 1.5:

- Xcode project + SwiftUI menu bar skeleton: 2-3h
- IOKit USB watcher (notification port + run loop): 4-6h (notoriously fiddly)
- CoreAudio adapter via SimplyCoreAudio: 2-3h
- ProfileResolver + Debouncer (Swift port of init.lua logic): 2-3h
- ProfileApplier + Notifier: 2h
- OBSController wrapping obs-cmd Process: 1-2h
- ConfigLoader (TOML parser): 1-2h
- ConfigImporter (parse profiles.lua → profiles.toml): 2-3h
- StatusItem menu UI: 2-3h
- DeviceCapture SwiftUI flow (replaces add-location subcommand): 3-5h
- PreferencesWindow SwiftUI: 3-5h
- FirstRunWizard SwiftUI: 2-3h
- Code signing + notarization setup: 3-5h
- Sparkle integration + appcast: 2-3h
- GitHub Actions release workflow: 3-4h
- README + install docs: 2h
- Real-world iteration: 4-6h

Total: ~38-57h, 10-14 sessions. Larger than my original estimate, mostly
because the original estimate didn't include a real config UI (DeviceCapture
+ PreferencesWindow + FirstRunWizard = ~10h).

---

## Lessons learned from Phase 1 / Phase 1.5

These are things we figured out the hard way that should bias the Swift design.

### From building the engine

- **The audio device snapshot logging on every load is more useful than I
  expected.** Not just for first-time setup — it's the primary debugging
  tool when a profile fails to find a device. Swift should do the same:
  log full device snapshot every time the engine starts or reloads its
  config.
- **Don't wait for a USB event to apply the profile on load.** The very
  first thing the engine should do after loading config is enumerate
  current state and apply the matching profile. Otherwise reloads leave
  the system in a stale state until the next dock/undock.
- **Profile resolution must be deterministic.** Alphabetical tiebreak
  matters even when fingerprints are equal length, otherwise the
  "switched profile" notification can flip-flop on every USB event.

### From writing the wizard

- **Hammerspoon's AppleScript is disabled by default.** Took a real
  failure to notice; `hs.allowAppleScript(true)` in init.lua is the fix.
  Equivalent gotcha for Swift: any IPC mechanism we expose (URL scheme?
  XPC? CLI?) needs to be enabled in code, not assumed.
- **macOS bash is 3.2.** A whole class of niceties (`mapfile`, associative
  arrays, `${var,,}` lowercase) are off-limits. Not relevant for Swift,
  but it's a reminder that "the OS comes with version X" can be 15 years
  old.
- **`obs-cmd` install is annoying.** Not in Homebrew (no formula yet),
  release asset names changed at some point (`obs-cmd-arm64-macos.tar.gz`
  not the cargo-style triple), and the binary needs sudo to drop into
  `/opt/homebrew/bin`. Swift will still need to install obs-cmd; consider
  bundling a copy inside the .app.
- **Idempotency is everything.** Every wizard step needs to detect
  already-done state and skip cleanly. The CEO will run the wizard
  multiple times. Same applies to Swift's first-run UI — it should
  detect existing config and offer to keep it.
- **macOS Settings deep links are great.** `open
  "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`
  takes the user to the exact pane. Swift should use the same trick to
  guide first-run permission grants.
- **Test isolation matters.** My test suite accidentally clobbered the
  user's profiles.lua because lib.sh hard-set PROFILES_FILE. Swift tests
  should use dependency injection or temporary directories from the start.
- **Anchor markers in machine-edited config files.** The wizard uses
  `-- WIZARD_PROFILE_<slug>_BEGIN/END` so awk can surgically update one
  block without touching others. Swift's TOML config might not need
  anchors (TOML is structured), but the principle of "diff-friendly,
  human-readable, machine-editable config" should carry over.

### From the README/UX work

- **CEOs are the worst-case user.** Not because they're dumb but because
  they're impatient and have no time to read. The README needs to be
  scannable, with the install command in the first 3 lines and detailed
  prose available but not required.
- **Numbered steps with explicit click sequences beat prose.** "In OBS,
  go to Tools → WebSocket Server Settings, tick Enable, untick Auth, click
  OK" is better than "configure OBS websocket". Swift's first-run wizard
  should follow the same pattern.

---

## How to use this document

- **When we ship a Phase 1 fix or feature**, ask: does this teach us
  something about the Swift port? If yes, add to "Lessons learned."
- **When the user gives feedback or hits a bug**, ask: should this be
  a feature in the Swift app? If yes, add to "Open questions" or
  "Scope creep candidates."
- **When we resolve an open question** (via real-world use or explicit
  user answer), move it from "Open questions" up to "Validated design
  decisions."
- **When we hit a Swift-specific design decision before we start Swift**
  (e.g., "should we use SwiftUI or AppKit for the preferences window?"),
  capture it under "Locked architectural choices" with the rationale.
- **Before starting Phase 2**, do a final pass through this doc to confirm
  every "open question" has been answered or explicitly deferred.
