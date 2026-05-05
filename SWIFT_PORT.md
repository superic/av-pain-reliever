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
2026-04-30. Swift port end-to-end runnable as of 2026-05-01:
prototypes, engine, config loader/importer, and a SwiftUI menu-bar
app target all complete. **V1 design pass landed 2026-05-01**, then
two polish rounds the same day — one-click switching restored,
"New location detected" state surfaced, runtime app icon, Launch-
at-Login, adaptive light+dark colors, wizard live icon preview,
"Suggested: untick" badges, warmer toast copy, branded Profiles-
tab empty-state, "Show welcome again" link, banner-style wizard
errors. **2026-05-02**: brand palette retired (plain native macOS
look, no custom accent colors), wizard preserves saved devices +
audio + camera when not currently attached, ⌥-click in Switch-to
opens the profile for editing, then **the repo was reorganized**
so the Mac app is at the root and the earlier Hammerspoon +
swift-research code is archived under `prototypes/`. `swift run
AVPainRelieverApp` from the repo root launches the menu-bar
agent. **145 passing tests** (144 + a known IOKit smoke flaky
when the host is undocked). Remaining work is signing/notarization
/Sparkle/GitHub Actions distribution plumbing — see the "V1
design pass" / "V1 polish pass" / "V1 fit & finish" sections near
the bottom of this doc for what's still deferred.

---

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

## Locked architectural choices for the Swift port

These can be considered final unless we discover a blocker:

- **App target**: SwiftUI app with `LSUIElement = true` (no Dock icon, menu
  bar only). Bundle ID `com.ericwillis.avpainreliever`.
- **Frameworks**:
  - `IOKit/usb` for USB device enumeration + notifications via notification
    port + run loop integration
  - `CoreAudio` for default device get/set, called directly. The C APIs
    are uniform enough that ~120 lines of `AudioController.swift` covers
    the full enumerate + read-default + set-default surface the engine
    needs. (Originally planned to wrap with `SimplyCoreAudio`; the
    CoreAudio prototype proved that's unnecessary — see "CoreAudio
    prototype findings" near the end of this doc.)
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

## Visual identity (revised 2026-05-02 — plain-native pivot)

**The earlier brand palette is retired.** The app reads as a plain
native macOS utility — no custom accent colors, no CLI-derived
magenta/cyan. Use SwiftUI defaults for everything; let the user's
chosen system accent color drive `.borderedProminent` buttons, and
let `.primary` / `.secondary` handle text contrast.

- **App display name**: AV Pain Reliever
- **Bundle ID**: `com.ericwillis.avpainreliever`
- **Tagline**: "Stop fiddling with mic, speakers, and webcam."
- **Color rules**:
  - Headlines, taglines, body text, link buttons → **no foreground
    style**. Use SwiftUI's defaults (`.primary` / `.secondary`).
  - `.borderedProminent` buttons → **no `.tint(...)`**. macOS paints
    them in the user's system accent.
  - Section headers, hint captions → use `.foregroundStyle(.secondary)`
    when you need quieter text. Don't introduce new colors.
  - Status pills + banners → semantic system colors only:
    `.green` (success), `.orange` (warn), `.red` (error). These
    survive in `Theme.Color.{success,warn,error}` as the only
    brand-surface entries left.
- **Menu bar icon (v1)**: SF Symbol `pills.fill` rendered as a template
  image. Auto-adapts to light/dark mode, native vibe, zero design effort.
- **App icon (v1)**: runtime-generated neutral gray squircle (top-down
  light→dark gray gradient) with a white `pills.fill` SF Symbol on
  top. Looks like an Apple-built utility — System Settings, Disk
  Utility, that family. The Asset Catalog version for the signed
  `.app` is still pending.
- **Menu bar UI**: native SwiftUI defaults. Status item shows the
  pill icon + current profile title (or "New location" when fallback
  resolves with USB attached).

### History note

The first design pass (2026-05-01) borrowed the Hammerspoon TUI
palette (`#FF87D7` magenta, `#00FFFF` cyan, etc.) and threaded it
through every header, tagline, button tint, and section icon. The
user reverted that direction the next day — the visual cost
(magenta accents on light-mode forms, cyan-on-white legibility,
"branded form" feel) outweighed the parity benefit with the CLI.
Plain native is the locked direction now; don't reintroduce
custom accent colors without explicit user direction.
- **Notification (`UserNotifications`) styling**: title = "Switched to
  Home Office" (pretty-cased profile name), no subtitle, no body, no
  attachment. Mimics the current `hs.notify` minimalism.

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
│   │   ├── AudioController.swift     # raw CoreAudio (no SimplyCoreAudio dep)
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
window. Menu structure (locked — confirmed 2026-04-30 that no manual override
is needed; menu is informational + admin only):

```
🎧 Home Office             ← current profile (status item title)
─────────────
Open OBS
Reveal log file in Finder
─────────────
Preferences...            ← opens SwiftUI preferences window
Quit AV Pain Reliever
```

No "Switch to" submenu. No "Auto-detect" toggle. The engine is always in
auto-resolve mode, deterministically driven by attached USB devices.

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
  → DONE 2026-05-01 as an SPM executable target (no Xcode project
    yet). `swift run AVPainRelieverApp` builds + launches a working
    menu-bar agent app driven by the engine. Xcode wrapping deferred
    to the code-signing/distribution phase since SPM can't produce a
    proper signed .app bundle. ~30 min actual.
- IOKit USB watcher (notification port + run loop): 4-6h (notoriously fiddly)
  → DONE 2026-05-01 as `IOKitUSBWatcher` in
    `Sources/AVPainReliever/Engine/USBWatcher.swift`. Lifted from
    the prototype; ~150 lines. Actual: ~25 min including 3 smoke tests.
- CoreAudio adapter (raw CoreAudio, no SimplyCoreAudio): 2-3h
  → DONE 2026-05-01 as `CoreAudioController` in
    `Sources/AVPainReliever/Adapters/AudioController.swift`. Lifted
    directly from the prototype; ~85 lines.
- ProfileResolver + Debouncer (Swift port of init.lua logic): 2-3h
  → DONE 2026-05-01 in `mac/`. Actual: ~30 min including 15 tests.
    Revise category estimate down for similar pure-logic ports.
- ProfileApplier + Notifier: 2h
  → BOTH DONE 2026-05-01. Notifier landed as `AppleScriptNotifier`
    (osascript via Process) for unbundled SPM dev builds; will swap
    for `UNUserNotificationCenter` when the .app bundle ships.
- OBSController wrapping obs-cmd Process: 1-2h
  → DONE 2026-05-01 in `Sources/AVPainReliever/Adapters/OBSController.swift`.
- ConfigLoader (TOML parser): 1-2h
  → DONE 2026-05-01 in `Sources/AVPainReliever/Config/ConfigLoader.swift`.
    Codable DTO over TOMLKit (~125 lines). Actual: ~30 min including
    14 tests covering schema, error paths, and resolver integration.
- ConfigImporter (parse profiles.lua → profiles.toml): 2-3h
  → DONE 2026-05-01 in `Sources/AVPainReliever/Config/ConfigImporter.swift`.
    Targeted Lua scanner (~350 lines). Actual: ~45 min including 14
    tests, end-to-end round-trip via ConfigLoader, and a real-world
    parse of the repo's profiles.lua.
- StatusItem menu UI: 1-2h (smaller now that there's no Switch-to submenu)
  → v1 DONE 2026-05-01 in `Sources/AVPainRelieverApp/App.swift`.
    SwiftUI `MenuBarExtra` with current profile title + Open OBS /
    Reveal Log / Quit. Live profile updates wire through Engine's
    new `onProfileApplied` callback into a `@Published` property on
    AppDelegate.
- DeviceCapture SwiftUI flow (replaces add-location subcommand): 3-5h
- PreferencesWindow SwiftUI: 3-5h
- FirstRunWizard SwiftUI: 2-3h
- Code signing + notarization setup: 3-5h
- Sparkle integration + appcast: 2-3h
- GitHub Actions release workflow: 3-4h
- README + install docs: 2h
- Real-world iteration: 4-6h

Total: ~37-56h, 10-14 sessions. Larger than my original estimate, mostly
because the original estimate didn't include a real config UI (DeviceCapture
+ PreferencesWindow + FirstRunWizard = ~10h). Slightly trimmed by the
locked "no manual override / no per-app routing" decisions.

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
  already-done state and skip cleanly. Users will re-run the wizard
  multiple times (after dependencies update, after they bail out
  partway, after they install on a second machine). Same applies to
  Swift's first-run UI — it should detect existing config and offer
  to keep it.
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

- **Busy executives are the worst-case audience.** Not because they're
  dumb but because they're impatient and have no time to read. The
  README needs to be scannable, with the install instructions early and
  detailed prose available but not required. Technical detail (file
  reference, manual install, architecture) lives in a clearly-marked
  "nerd zone" section at the bottom.
- **Numbered steps with explicit click sequences beat prose.** "In OBS,
  go to Tools → WebSocket Server Settings, tick Enable, untick Auth, click
  OK" is better than "configure OBS websocket". Swift's first-run wizard
  should follow the same pattern.
- **Dry-run is a valuable affordance, not a power-user feature.** The
  Hammerspoon wizard now ships with `--dry-run` that walks the user
  through the entire install flow, showing every command/install that
  would have happened, without actually doing any of it. Useful for:
  (a) previewing before committing to changes, (b) showing a colleague
  what their install will look like, (c) demoing the app. Implementation:
  every side-effect call goes through a `runcmd` or `runstep` wrapper
  that checks a `DRY_RUN` env var. Read-only commands (pgrep, defaults
  read, command -v) always run. Confirms always run (they're asking the
  user, not doing work).
  *Implication for Swift:* the first-run UI should have a "preview only"
  toggle that walks through every screen without writing anything to
  `~/Library/Application Support/AVPainReliever/` or running `obs-cmd`.
  Same wrapper pattern: every side-effect operation in
  `ProfileApplier`/`ConfigLoader`/`OBSController` checks an injected
  `dryRun: Bool`. Probably easiest as a property on the dependency
  injection container. The status bar UI could even have a permanent
  "Preview mode" toggle for advanced users who want to see what the
  next dock event WOULD trigger before letting it fire.

- **TUI polish matters even before a real GUI exists.** The wizard's
  bash + gum + ANSI palette is loud enough to feel like a real product:
  ASCII-art logo, double-bordered banners, step counter with progress
  bar (▰▰▰▱▱▱), gum spinners during long installs, color-coded ✓/⚠/✗.
  Swift app should match or exceed this baseline — the Hammerspoon
  wizard sets a floor, not a ceiling. Specifically:
  - **Color palette is locked**: primary 212 (magenta/pink), highlight
    51 (cyan), success 46 (green), warn 220 (yellow), error 196 (red),
    chrome 245 (gray). Map these to NSColor constants for parity.
  - **Progress bar is non-negotiable** — install/onboarding flows of
    more than ~5 steps benefit from "STEP X of Y" with a visual bar.
    Swift first-run wizard should have one.
  - **Spinners during long ops** — same pattern, brew install / curl /
    obs-cmd calls all spin. Swift equivalent: `ProgressView()` with
    a custom title, never a frozen UI.
  - **NO_COLOR env var support** — the wizard respects it (no-color.org
    standard). Swift app probably won't need this since it's GUI-native,
    but if we ever ship a CLI surface alongside the .app, respect it.
- **macOS bash is byte-oriented for `tr`.** Counting multi-byte runes
  with `tr -cd '▰' | wc -c` over-counts because `▰` and `▱` share UTF-8
  prefix bytes. Use `grep -o '▰' | wc -l` for per-character counting.
  Pure trivia for Swift (which has String.count returning real
  characters), but a useful reminder of how thin the CLI layer is.

---

## IOKit prototype findings

A throwaway single-file Swift prototype lives at
[`prototypes/usb-watcher.swift`](prototypes/usb-watcher.swift) and proves
that IOKit USB watching produces output equivalent to Hammerspoon's
`hs.usb.watcher`. Run it with `swift prototypes/usb-watcher.swift`.

### Did it work first try?

Almost. The IOKit pieces themselves (matching dict, notification port,
run-loop wiring, drained iterators) worked first compile. The two surprises
were both about Swift / Foundation behavior, not IOKit:

- **stdout was block-buffered** when the script wasn't attached to a TTY,
  so the snapshot output didn't appear until the process exited. Fix:
  `setbuf(stdout, nil)` at startup. The production app logs through
  `os.Logger`, so this is a script-only quirk — but worth remembering if
  we ever ship a CLI surface alongside the `.app`.
- **The IOKit registry entry name was the wrong fallback** for unnamed
  devices. `IORegistryEntryGetName` returns the *class name*
  (`"IOUSBHostDevice"`) when a device has no instance name set, not an
  empty string. Hammerspoon renders these as `"?"`. Fix: drop the
  `IORegistryEntryGetName` fallback entirely; just use `"?"` when
  `kUSBProductString` (the `"USB Product Name"` property) is missing.
  Affects ~2 devices on Eric's docked setup (LG UltraFine internal hub
  legs).

Snapshot output on Eric's machine matches the most recent Hammerspoon
log's `--- attached USB devices ---` block one-for-one (every vid/pid
present, every name match), plus an iPhone connected since the log was
captured. IOKit iteration order differs from Hammerspoon's — not a
problem for the engine since `ProfileResolver` works on a *set* of
fingerprints, but worth knowing: **never assume a stable enumeration
order from `IOServiceGetMatchingServices`**. If the Swift port ever
needs deterministic output (logging, hashing for change detection),
sort by `(vid, pid, name)` after enumeration.

### Anything harder than expected?

- **The Swift Clang importer doesn't surface IOUSBLib's `#define`
  constants**. `kUSBVendorID`, `kUSBProductID`, `kUSBProductString`,
  `kIOUSBDeviceClassName` — none of them are visible from Swift.
  Hard-code the literals (`"idVendor"`, `"idProduct"`, `"USB Product
  Name"`, `"IOUSBHostDevice"`). Stash these as named constants in
  `USBWatcher.swift` so it's clear they're IOKit-defined and not
  arbitrary.
- **`IOServiceMatching` consumes one CF reference per call site**.
  `IOServiceGetMatchingServices` and each `IOServiceAddMatchingNotification`
  each consume one. So for snapshot + add-notification +
  remove-notification = three calls to `IOServiceMatching`, not one.
  Cheap and obvious in retrospect, but the symptom of getting it wrong
  is `kIOReturnNoMemory` from the second consumer, which is misleading.

### Anything easier than expected?

- **The notification-port → run-loop integration is one line:**
  `CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)`.
  The `.takeUnretainedValue()` is the only Swift-vs-C ergonomic friction.
- **Captureless Swift closures convert cleanly to `@convention(c)`
  function pointers** as long as they only reference globals, not local
  variables. `IOServiceMatchingCallback` is `@convention(c)`, and the
  prototype's drain-state lives in a global `final class` so the closures
  can mutate it without capturing. The production `USBWatcher` should
  pass an `Unmanaged<Self>` via the `refCon` parameter instead — cleaner
  than globals for a real class.
- **The "first-match callback fires once per already-attached device on
  registration" gotcha was easy to handle with a single boolean flag**
  per iterator. The first manual drain after
  `IOServiceAddMatchingNotification` is silent (those are devices we
  already printed in the snapshot pass); subsequent drains print
  `[add]` lines. Same shape for `[remove]` except the initial drain is
  empty in practice.

### Patterns worth keeping for the production port

```swift
// 1. Property reads — boilerplate-heavy, factor into helpers up front:
private func intProperty(_ entry: io_object_t, _ key: String) -> Int? {
    guard let raw = IORegistryEntryCreateCFProperty(
        entry, key as CFString, kCFAllocatorDefault, 0
    ) else { return nil }
    return (raw.takeRetainedValue() as? NSNumber)?.intValue
}

// 2. Iterator drain — used in every callback; must run to exhaustion or
//    the notification port stops delivering events:
private func drain(_ iterator: io_iterator_t, body: (io_object_t) -> Void) {
    var entry = IOIteratorNext(iterator)
    while entry != 0 {
        body(entry)
        IOObjectRelease(entry)
        entry = IOIteratorNext(iterator)
    }
}

// 3. Manual first-call to arm the notification — easy to forget:
let iter = subscribe(kIOFirstMatchNotification, addedCallback)
addedCallback(nil, iter) // drains initial set + arms notification port
```

The production `USBWatcher` should also:

- Hold the notification port in a property and `IONotificationPortDestroy`
  it on deinit (not needed for a prototype, but a singleton in a
  long-running app should clean up).
- Sort the snapshot enumeration by `(vid, pid, name)` for log fidelity
  if we want the Swift app's logs to diff cleanly across runs.
- Pass `self` via `refCon` (`Unmanaged.passUnretained(self).toOpaque()`)
  rather than relying on globals for callback state.
- Match `IOUSBHostDevice` only — `IOUSBDevice` is the legacy XHCI class
  and returns nothing on Apple Silicon. Confirmed empirically on
  macOS 26 Tahoe.

### Effort estimate update

The original estimate had IOKit USB watcher at **4-6h** (with the
"notoriously fiddly" caveat). After the prototype, revise down to
**2-3h** for the production version: the heavy lifting (matching dict,
notification port, run-loop integration, iterator draining, callback
shape) is now de-risked. What's left is:

- Wrapping the prototype's globals in a real class with `init`/`deinit`
- Routing events through a Combine `PassthroughSubject` or
  delegate-style callback to the `Debouncer` → `ProfileResolver`
- `os.Logger` integration in place of `print`
- Unit-testable seams (probably an injected `USBEnumerator` protocol so
  `ProfileResolver` tests don't actually touch IOKit)

### Open questions resolved

None of the "Open questions" above were directly answered by this
prototype — it was a feasibility check, not a UX experiment. But the
"locked architectural choices" entry for **"`IOKit/usb` for USB device
enumeration + notifications via notification port + run loop
integration"** can now be considered **validated**, not just locked.

---

## CoreAudio prototype findings

A second throwaway single-file Swift prototype lives at
[`prototypes/audio-defaults.swift`](prototypes/audio-defaults.swift) and
proves CoreAudio can do everything `hs.audiodevice` does for us in the
engine: enumerate input/output devices, read the current system defaults,
and switch defaults by `AudioDeviceID` (which `AudioController` will look
up by name). Run it with `swift prototypes/audio-defaults.swift` — it
prints a snapshot + current defaults + a non-destructive set-default
verification (sets each default to its *current* value, exercising the
write codepath without disrupting the user's audio).

### Did it work first try?

Yes. Snapshot output matches the engine's `--- audio devices ---` log
block **line-for-line, in the same order** — including the cosmetic
detail that some devices (CalDigit, Yeti, LG UltraFine) appear twice as
separate `AudioDeviceID`s with `in=true/out=false` and
`in=false/out=true`, while a few (Microsoft Teams Audio) appear once
with `in=true out=true`. Unlike IOKit, CoreAudio's
`kAudioHardwarePropertyDevices` returns devices in a stable order — no
need to sort for log fidelity.

Default-device set verification: `noErr` for both input and output. The
production `AudioController` can use the same
`AudioObjectSetPropertyData(kAudioObjectSystemObject,
DefaultInput|OutputDevice, …)` call to actually switch when a profile
applies.

### Anything harder than expected?

- **Generic property-read helper hits a Swift compiler warning.** The
  obvious `func readProperty<T>(...) -> T?` that wraps
  `AudioObjectGetPropertyData` produces *"forming
  UnsafeMutableRawPointer to a variable of type 'T'; this is likely
  incorrect because 'T' may contain an object reference."* The compiler
  can't prove `T` is trivially copyable. For a production
  `AudioController` we should either constrain to non-class types or
  just write per-type helpers (`readUInt32(...)`,
  `readCFString(...)`); the prototype takes the per-type route after
  hitting the warning. Minor friction, not a blocker.
- **`kAudioObjectPropertyName` returns `Unmanaged<CFString>`, not
  `CFString`.** Easy to miss until you look at the readProperty signature.
  Pattern: read into `Unmanaged<CFString>?`, then `takeRetainedValue() as
  String`. The CoreAudio docs do say "the caller is responsible for
  releasing", which is the Unmanaged hint.

### Anything easier than expected?

- **The C-style API is more uniform than I expected.** Every read is
  `AudioObjectGetPropertyData(object, &address, 0, nil, &size, &out)` —
  same shape regardless of what you're reading. Wrapping this in a
  small `address(selector, scope:)` helper kills 80% of the boilerplate
  and the rest reads almost like Swift. The "notoriously fiddly" part
  of the original effort estimate was overblown — at least for the
  default-device subset we need.
- **The original plan to wrap CoreAudio behind `SimplyCoreAudio` may be
  unnecessary** for the engine's actual needs. The full read+write
  surface for `AudioController` is exactly four operations:
  enumerate-devices, get-name, get-streams-by-scope, and
  set-default-device-for-role. With ~80 lines of helpers we have all of
  them in pure Swift + CoreAudio. SimplyCoreAudio adds an SPM dep, an
  observation/notification surface we don't need (the engine doesn't
  watch for audio device changes — only USB events trigger reapplies),
  and a Combine layer that doesn't fit our otherwise-imperative
  `ProfileApplier`. **Recommendation: drop SimplyCoreAudio from the
  locked architectural choices**, write `AudioController.swift` as
  ~120 lines of CoreAudio directly. Saves a dep and cuts a layer.
- **Set-default verification with current value is a clean test
  pattern.** Setting input→input and output→output exercises the entire
  write path with zero user-visible side effect. Worth keeping for
  `AudioController`'s init: a one-time self-set on launch as a
  smoke-check that the codepath is healthy. (Or a unit test seam.)

### Patterns worth keeping for the production port

```swift
// Address helper — kills CoreAudio's biggest source of boilerplate:
private func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
}

// Capability check — does this device have streams in a given scope?
private func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    var addr = address(kAudioDevicePropertyStreams, scope: scope)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
    return size > 0
}

// Find a device by name + capability — what AudioController.setInput(name:)
// will need. The prototype only iterates; the production version is the
// same loop with `==` matching:
func findDevice(named target: String, scope: AudioObjectPropertyScope) -> AudioDeviceID? {
    for id in allDeviceIDs() where deviceName(id) == target && hasStreams(id, scope: scope) {
        return id
    }
    return nil
}
```

### Effort estimate update

The original estimate had **CoreAudio adapter via SimplyCoreAudio: 2-3h**.
After this prototype, the estimate is unchanged at **2-3h** but the work
shifts: instead of wrapping SimplyCoreAudio, we wrap raw CoreAudio in
`AudioController.swift`. Same amount of code, one fewer dep. The SPM
manifest gets shorter.

### Architectural choice update

Update the "Locked architectural choices" section: replace
> `CoreAudio` for default device get/set, wrapped with `SimplyCoreAudio`
> SPM dep to hide the worst of the C APIs

with:

> `CoreAudio` for default device get/set, called directly. The C APIs
> are uniform enough that ~120 lines of `AudioController.swift` covers
> the full enumerate + read-default + set-default surface the engine
> needs. **No SimplyCoreAudio dep** — see "CoreAudio prototype
> findings" for why.

(Done — this section already updated in the same change.)

### Open questions resolved

None — same as the IOKit prototype, this was a feasibility check, not a
UX experiment. But two locked architectural choices were validated AND
revised: CoreAudio direct (instead of via SimplyCoreAudio) is now the
plan for `AudioController`.

---

## Engine core port (ProfileResolver + Debouncer)

The first production Swift code (originally under `mac/`, now at
the repo root after the 2026-05-02 reorganization) lives as a Swift
Package, set up to be wrapped by the eventual menu-bar app's Xcode
project. Run `swift test` to exercise the engine in isolation —
no AppKit/IOKit/CoreAudio imports yet, so the package builds +
tests in under 10 seconds on a cold cache.

### What's there

```
av-pain-reliever/
├── Package.swift
├── Sources/AVPainReliever/
│   ├── Engine/
│   │   ├── Debouncer.swift        # 1.5s coalescing, injectable DebouncerClock
│   │   ├── Engine.swift           # top-level coordinator (start/stop)
│   │   ├── ProfileApplier.swift   # orchestrates audio + OBS side effects
│   │   ├── ProfileResolver.swift  # init.lua's resolveProfile()
│   │   ├── USBDevice.swift        # Hashable (vid, pid)
│   │   └── USBWatcher.swift       # protocol + IOKitUSBWatcher
│   ├── Adapters/
│   │   ├── AudioController.swift  # protocol + CoreAudioController
│   │   └── OBSController.swift    # protocol + ProcessOBSController
│   └── Config/
│       ├── ConfigImporter.swift   # profiles.lua → TOML / [Profile]
│       ├── ConfigLoader.swift     # TOML → [Profile] via TOMLKit
│       └── Profile.swift          # name + fingerprint + audio + scene
└── Tests/AVPainRelieverTests/
    ├── ConfigImporterTests.swift       # 14 tests (incl. real profiles.lua)
    ├── ConfigLoaderTests.swift         # 14 tests (schema + errors)
    ├── DebouncerTests.swift            # 7 tests
    ├── EngineTests.swift               # 10 integration-style tests
    ├── IOKitUSBWatcherTests.swift      # 3 smoke tests (real IOKit)
    ├── ProfileApplierTests.swift       # 10 tests
    ├── ProfileResolverTests.swift      # 8 tests
    ├── RecordingUSBWatcher.swift       # in-memory USBWatcher fake
    └── TestClock.swift                 # virtual-time DebouncerClock
```

### Lessons learned

- **The init.lua resolution algorithm ports to ~15 lines of Swift**
  with no behavior changes. The Lua `>` (strictly greater specificity)
  becomes Swift `>`; alphabetical-first iteration → first-match-wins
  semantics is identical between Lua's `pairs` + `table.sort` and
  Swift's `profiles.sorted { $0.name < $1.name }`. Don't be afraid to
  port pure-logic engines verbatim — the line-count ratio is ~1:1, and
  every "improvement" is risk.
- **`DebouncerClock` injection makes the timer tests sub-millisecond
  AND deterministic.** A naive `DispatchQueue.asyncAfter`-backed
  Debouncer would either need `Thread.sleep` in tests (slow + flaky)
  or `expectation(description:).fulfill()` plumbing. The protocol +
  `TestClock` pattern adds ~30 lines and gives us 7 tests that all run
  in <1ms total. Worth doing this for *any* Swift code that calls
  `asyncAfter`/`DispatchSourceTimer` — the tests-first cost is
  immediately repaid.
- **Swift Testing (`@Suite` / `@Test` / `#expect`) is markedly cleaner
  than XCTest** for new code on Swift 5.10+. Suite-level fixtures live
  as `static let`s, no `setUp`/`tearDown`, no `XCTAssertEqual` noise.
  Apple Silicon + Swift 6.3 toolchain runs both side by side in the
  same target if we ever need to mix; for this package, it's pure
  Swift Testing. Adopt for all new Swift test files.
- **Profile fixture data is best drawn from the actual engine
  snapshot** in `~/.hammerspoon/logs/av-pain-reliever.log` — using
  real (vid, pid) pairs from the user's docked setup makes test
  failures legible ("CalDigit + LG won't match home-office") instead
  of "0xdeadbeef + 0xcafebabe doesn't match TestProfile1".
- **Don't speculate on `Profile`'s schema beyond what
  `ProfileResolver` needs.** Audio + OBS fields land alongside
  `ProfileApplier`, not now — adding them speculatively would force
  test fixtures to specify defaults for fields nothing here uses.

### Effort estimate update

Revising the estimate for similar pure-logic Swift ports:
**4-6h was 2-3h was actually 30 min** for resolver + debouncer + 15
tests + Swift Package bootstrap. Most of that was bootstrapping the
package; the algorithm port itself was ~10 minutes. Implication: the
remaining pure-Swift pieces in the original effort estimate
(`ProfileApplier`, `ConfigLoader` TOML, `ConfigImporter` profiles.lua
parser) are likely overestimated by 2-3x. Don't re-budget yet — wait
until each lands to see if framework integration drags them back up.

### What's next in the engine

- **`USBWatcher`** — wrap the IOKit prototype as a real class with a
  delegate-style callback into `Debouncer.bump`. (Last engine piece.)
- **`Engine`** — top-level coordinator that wires
  USBWatcher → Debouncer → ProfileResolver → ProfileApplier and
  exposes the current profile to `StatusItem`.

After those, the project shifts from engine to UI/distribution.

---

## Apply layer port (ProfileApplier + adapters)

`ProfileApplier` is the side-effects half of the engine — given a
resolved `Profile`, switch the system audio defaults and the OBS scene
to match. Mirrors `init.lua`'s `applyProfile`, including its
`lastAppliedProfile` no-op short-circuit. Two adapter protocols
(`AudioController`, `OBSController`) keep the side effects mockable so
the applier itself is fully unit-tested.

### Lessons learned

- **`AudioApplyResult` enum-with-payload preserves the engine's
  three-way error log without dragging the protocol surface into a
  Result/throws shape.** init.lua distinguishes "device not found" /
  "device exists but is not an input" / "set call failed" — three
  different log lines that point the user at three different
  remediations (plug the device in / fix the profile config / file a
  CoreAudio bug). Returning `enum AudioApplyResult { ok, notFound,
  wrongScope, setFailed(OSStatus) }` from `setDefault(named:role:)`
  lets `ProfileApplier` map each case to the correct log line without
  the protocol leaking `AudioDeviceID`/`OSStatus`/CoreAudio at all to
  callers. Result-with-cases beats `throws` when the cases ARE the
  message.
- **`OBSController` as `init?()` with executable auto-discovery
  matches the engine's "obs-cmd not installed → log warning, keep
  running" behavior cleanly.** `ProfileApplier` takes
  `obs: OBSController?`; passing nil mirrors a missing `obs-cmd`. No
  separate "OBS available?" boolean flag, no error case for "no OBS";
  the optional-typed dependency carries the entire signal.
- **The applier's `lastAppliedName` dedup is a property of the apply
  layer, not the engine layer.** init.lua puts it inside
  `applyProfile`. The Swift port follows that — keeps the engine's
  `evaluate → resolve → apply` pipeline stateless except for the
  applier itself. If we ever add a "force re-apply" command (e.g. for
  a wizard step), it goes here as a `forceNextApply()` toggle.
- **Recording-mocks beat protocol-witnesses for these tests.**
  Function-witness style (a struct with a `setDefault` closure inside)
  reads cleanly for one-shot tests but hides assertion targets behind
  per-test capture variables. A reference-typed mock with `private(set)
  var calls: [Call]` lets every test do `#expect(audio.calls == [...])`
  in one line. 10 tests, ~1ms total, no flakes.
- **`Process` + `Pipe` capture stderr/stdout for diagnostics
  free-of-charge.** The OBSError.nonZeroExit case carries both — when
  `obs-cmd` fails because OBS isn't running or auth is misconfigured,
  the warning log gets the full error message instead of just an exit
  code. Worth doing every time we shell out.

### Effort estimate updates

| Original | Actual | Notes |
|---|---|---|
| ProfileApplier + Notifier: **2 h** | ~30 min | Notifier still open. |
| OBSController wrapping obs-cmd Process: **1-2 h** | ~10 min | One file, ~70 lines. |
| CoreAudio adapter via SimplyCoreAudio: **2-3 h** | ~15 min | Lifted from prototype; ~85 lines, no SPM dep. |

The pure-engine parts of the original 37-56h estimate (resolver,
debouncer, applier, audio adapter, OBS adapter) totaled **9-15 h** in
the budget; actual is **~70 min**. The remaining items (USBWatcher,
config loader, importer, status item, preferences, first-run wizard,
signing/notarization, GitHub Actions, README/install docs, real-world
iteration) total **~28-41 h** in the original budget. Some of those
will compress similarly (USBWatcher: prototype already done, expect
~30 min for the class wrapper); the UI items probably won't.

### What's next

The engine is one class away from end-to-end. `USBWatcher` (wrapping
the IOKit prototype) gives `Debouncer.bump()` a real input source;
then a thin `Engine` coordinator wires
USBWatcher → Debouncer → ProfileResolver → ProfileApplier. After that
the work shifts to the menu-bar app target (Xcode project, status
item, first-run wizard, code signing, distribution).

---

## USBWatcher port

`USBWatcher` is the input source for the engine — it surfaces both
"current attached set" snapshots and "something changed" notifications.
The prototype already proved the C-API dance (matching dict,
notification port, run-loop wiring, drained iterators); the production
class wraps that as `IOKitUSBWatcher` with a `start`/`stop` lifecycle
and a closure-based `onChange` callback that calls into
`Debouncer.bump()` at the engine layer.

### Lessons learned

- **The protocol's mockability lives in `start(onChange:)` + an
  injectable `currentDevices()`** — not in trying to fake IOKit's
  notification port. A `RecordingUSBWatcher` test fake (when the
  Engine class lands) just stores the closure, exposes a
  `triggerChange()` method that invokes it, and a `setDevices(_:)`
  method that updates what `currentDevices()` returns. Trying to fake
  a real `IONotificationPort` would need a whole shim layer that no
  other engine piece needs.
- **`Unmanaged.passUnretained(self).toOpaque()` in the `refCon` is the
  clean way to bridge `self` into the C-style callbacks.** `self`
  owns the notification port and iterators, so the iterators can't
  outlive `self` — a retained reference would be redundant. The C
  callback unwraps via `Unmanaged<IOKitUSBWatcher>.fromOpaque(refcon)
  .takeUnretainedValue()`. Worth lifting this pattern into other
  CoreFoundation/IOKit wrappers when they arrive.
- **`stop()` must be idempotent.** The class calls `stop()` from
  `deinit` AND exposes it publicly so the menu-bar app can stop the
  watcher when the user quits. A second `stop()` is a no-op;
  start-after-stop works cleanly. Tested via the third smoke test —
  catches lifecycle bugs that `leaks(1)` would otherwise be the only
  detector for.
- **Smoke tests beat unit tests for thin IOKit wrappers.** "Does
  `currentDevices()` return what `IOServiceGetMatchingServices`
  delivered, parsed into Swift types?" is a question the Swift
  compiler doesn't fully verify. A test that just calls the method on
  the host's real IOKit graph and checks for non-empty + stable
  output catches the realistic regression modes (wrong matching dict
  string, wrong property keys, type-bridging breakage) without
  inventing a fake IOKit. Cheaper to write, more honest.

### Effort estimate update

The original IOKit USB watcher estimate was **4-6 h** with the
"notoriously fiddly" caveat. After both the prototype (~30 min) AND
the production wrapper (~25 min), the total is **~1 h**. The "fiddly"
part was real but front-loaded into the prototype phase — the
production refactor was straight transcription. Subsequent IOKit work
(if any) should track closer to **30-60 min per piece**, not 4-6 h.

### What's next

`Engine` — the top-level coordinator class. Wires
`USBWatcher.start { debouncer.bump() }` →
`debouncer = Debouncer { applier.apply(resolver.resolve(attached: watcher.currentDevices()) ?? fallback) }`.
Roughly 50 lines + tests using protocol-based fakes for the watcher
and applier. After that, the engine is end-to-end and we move to the
menu-bar app target.

---

## Engine coordinator port

`Engine` is the last engine piece — a thin (~70 line) class that wires
USBWatcher → Debouncer → ProfileResolver → ProfileApplier together and
exposes a `start()` / `stop()` lifecycle. With this in, the
framework-independent half of the Swift port is complete.

### Lessons learned

- **The "fallback profile" model is implicit, not explicit.** init.lua
  has `FALLBACK_PROFILE = "laptop"` baked in, but profiles.lua already
  has a `laptop` entry with empty fingerprint that always matches with
  specificity 0. The hardcoded constant is redundant. The Swift Engine
  drops it: if the resolver returns nil, log a warning and skip; if the
  caller wants a fallback, they include an empty-fingerprint profile in
  the list. One less concept, same behavior.
- **Initial evaluate-and-apply on `start()` is non-negotiable.**
  Without it, reloading the engine (or relaunching the app) leaves the
  system in whatever state the previous run last applied, NOT the
  state that matches the currently-attached devices. init.lua does
  this at the bottom of the file (`applyProfile(resolveProfile())`);
  the Swift Engine does it at the end of `start()`. Test:
  `start applies the matching profile immediately, no debounce`.
- **The applier's `lastAppliedName` dedup is preserved across
  engine restarts** because the applier instance survives the
  Engine.stop()/start() cycle. This bit me in the first cut of the
  "engine can be restarted" test — I expected a re-apply, but the
  dedup correctly no-op'd it. Fixed the test to actually change the
  attached set between stop and start, which DOES trigger an
  observable apply. The dedup behavior is correct: if nothing
  changed, nothing should reapply, even across restarts.
- **Integration-style tests beat layered unit tests for the
  coordinator.** Each test sets up a real `Debouncer` (with
  `TestClock`), a real `ProfileResolver` (with fixture profiles), and
  a real `ProfileApplier` (against recording-mock `AudioController` /
  `OBSController`). Only `USBWatcher` is faked. Each test reads as a
  scenario: "given a docked setup, when X happens, the engine applies
  Y". This catches wiring bugs across all four layers without
  re-testing each layer's algorithms (which already have dedicated
  unit tests). 10 tests, all sub-millisecond.
- **The 14-event burst test is the only test that mirrors real
  hardware behavior.** Iterates 14 watcher.triggerChange() calls at
  ~70 ms intervals (the actual cadence of a CalDigit dock burst per
  the engine logs), advances the test clock past the debounce window,
  and asserts exactly one apply. Worth keeping as a regression guard
  if anyone ever tunes the debounce interval — too short and the
  burst fires multiple applies; too long and quick changes feel
  laggy.

### Effort estimate update

The original engine-coordinator estimate wasn't broken out separately
(rolled into "ProfileApplier + Notifier: 2 h"). Actual: ~25 min for
the class + 10 tests. The full engine (resolver, debouncer, applier,
audio + OBS adapters, USB watcher, coordinator) totaled **~2 h**
against an original 9-15 h budget for the same set.

### What's next

The engine is complete. Next phases (in rough order):

1. **`ConfigImporter`** — one-shot read of an existing `profiles.lua`
   to bootstrap a `profiles.toml` for users migrating from Phase 1.
2. **Xcode project** wrapping the Swift Package + adding a SwiftUI
   `App` target with `LSUIElement = true` (menu bar only, no Dock).
3. **`StatusItem`** — `NSStatusItem` driven by Engine's current
   profile name.
4. **`Notifier`** — UserNotifications wrapper.
5. **First-run wizard / preferences SwiftUI** — the bulk of the
   remaining work.
6. **Code signing + notarization + Sparkle + GitHub Actions release** —
   distribution plumbing.

The pure-engine + config work is done (~2.5 h actual against
~10-17 h budgeted for the same set). Steps 2-6 are the AppKit /
SwiftUI / distribution slog where original estimates probably
hold.

---

## ConfigLoader port

`ConfigLoader` parses TOML into `[Profile]`. Lives at
`Sources/AVPainReliever/Config/ConfigLoader.swift`. ~125 lines
(including doc comments) over TOMLKit's Codable interface.

### Schema

The TOML schema parallels `profiles.lua`:

```toml
[profiles.laptop]
audioInput  = "MacBook Pro Microphone"
audioOutput = "MacBook Pro Speakers"
obsScene    = "Laptop"
# fingerprint omitted = empty list (always matches with specificity 0,
# making this profile the implicit fallback)

[profiles.home-office]
audioInput  = "Yeti Stereo Microphone"
audioOutput = "CalDigit Thunderbolt 3 Audio"
obsScene    = "Home Office"
fingerprint = [
  { vendorID = 0x2188, productID = 0x6533, name = "CalDigit Thunderbolt 3 Audio (dock)" },
  { vendorID = 0x043e, productID = 0x9a68, name = "LG UltraFine Display Camera" },
]
```

The `[profiles.<name>]` namespace reserves the file's top level for
future settings (debounce override, log path, etc.) without breaking
the existing schema. Inside a fingerprint entry, `vendorID` and
`productID` are required; `name` is for human reading and is ignored
at match time (the resolver matches on `(vendorID, productID)` only).

### Lessons learned

- **TOMLKit picked for production over a hand-rolled parser.** TOML
  has more edge cases than it looks (escapes, datetimes, multi-line
  strings, mixed table syntaxes); rolling our own would have been a
  distraction. TOMLKit wraps tomlplusplus (well-tested C++) and
  exposes a clean Codable interface, so adoption is one SPM dep and
  one `import` line. Worth the dep.
- **Codable's "ignore unknown keys" default gets us forward
  compatibility for free.** A future `[profiles.foo].wallpaper = ...`
  added by a newer Swift app version is silently ignored by older
  versions of the loader. Documented as a deliberate behavior in two
  tests.
- **The dictionary-keyed name pattern (`[profiles.<name>]`) requires
  an intermediate DTO.** TOML's inline keying means the profile name
  is the dict key, not a body field — so `Profile` itself can't be
  directly Decodable. Three small private DTOs (`ConfigFile`,
  `ProfileBody`, `FingerprintEntry`) decode cleanly, then the
  `ConfigFile.toProfiles()` method maps `[String: ProfileBody]` →
  `[Profile]` by injecting the key as `Profile.name`. Cleaner than
  trying to hack name into the body.
- **Map `DecodingError` cases onto a flat domain `enum` at the
  loader boundary.** Codable surfaces `keyNotFound`,
  `dataCorrupted`, `typeMismatch` etc. as separate cases of a
  generic enum; the menu-bar app's first-run flow shouldn't have to
  know about Codable. The `ConfigError.malformed` /
  `.schemaViolation` split gives the UI a simple two-way branch
  ("syntax issue" vs "field issue") with a `reason` string for the
  details.
- **End-to-end test that loaded profiles drive the resolver.** One
  test (`config drives the resolver end-to-end`) parses TOML, builds
  a `ProfileResolver`, and verifies that resolving a real attached
  set picks the right profile. Catches integration breakage between
  the loader and the engine that pure-loader tests miss.
- **`Package.resolved` IS committed for this package.** The
  `mac/` package is independently testable via `swift test` (we run
  it on every commit), so reproducibility benefits from pinning the
  TOMLKit version. Apple's "libraries don't commit Package.resolved"
  guidance applies when downstream apps pin via their own resolved
  files — that pattern still holds for the eventual Xcode app
  target, but doesn't help anyone running `swift test` directly here.

### Effort estimate update

The original ConfigLoader estimate was **1-2 h**. Actual: ~30 min
including 14 tests. The TOMLKit dep paid for itself within the first
hour saved over a hand-roll.

### What's next

The pure-Swift portion of the port is complete. Remaining work is
all in the Xcode app target — see "Phase 2 status" at the bottom
of this section.

---

## ConfigImporter port

`ConfigImporter` is the one-shot Lua → TOML conversion path the
menu-bar app's first-run wizard will offer to users with an existing
Hammerspoon setup. Lives at
`Sources/AVPainReliever/Config/ConfigImporter.swift`. ~350 lines
including doc comments.

### Lessons learned

- **A targeted Lua scanner beats a general parser for this scope.**
  The wizard's `profiles.lua` follows a tight, well-defined shape:
  a single `return { ["name"] = { ... }, ... }` table. Building a
  full Lua tokenizer + parser would have been ~500-700 lines for
  edge cases the wizard never produces (block comments, multi-line
  strings, function calls, metatables). The scanner here uses
  brace-balanced block extraction + per-block regex-style field
  extraction, in ~250 working lines of Swift, and rejects any
  off-shape input with a `.syntax` error so the wizard can fall
  through to the "create from scratch" path.
- **Comment stripping must respect string boundaries.** Naive
  `--.*$` line-comment removal corrupts profile fields like
  `audioInput = "My Mic -- with dashes"`. The scanner walks the
  source character-by-character, tracking string-literal state, and
  drops comments only when not inside a string. ~30 lines, one
  dedicated test (`string values containing -- are not treated as
  comments`).
- **Two output paths, not one.** The engine's `Profile` model has
  `[USBDevice]` for fingerprints (no device names — the resolver
  doesn't use them). But `profiles.lua`'s fingerprint entries DO
  carry `name = "..."` strings, and they're the only readable
  signal for users editing the TOML by hand. Solution: the importer
  uses a private richer model (`ImportedProfile` /
  `ImportedDevice`) internally, then offers two public emit paths:
    - `convertToTOML(_ luaSource:)` — preserves names from the Lua
      source
    - `encodeTOML(_ profiles:)` — takes the engine's lossy `Profile`
      model, emits without names
  The first is the user-facing wizard path; the second is for any
  programmatic write-out from the engine model later.
- **Real-world input as a permanent test fixture.** One test reads
  the archived Hammerspoon `profiles.lua` via `#filePath`
  navigation (`Tests/AVPainRelieverTests/` → repo root →
  `prototypes/hammerspoon/profiles.lua`) and parses it.
  Catches any wizard format change that breaks the importer in CI
  before users hit it. The four expected profile names + the
  home-office vid/pid pairs are asserted explicitly so the failure
  message is legible if the format drifts.
- **TOML output sorted by profile name for deterministic diffs.**
  When users re-import (e.g., after the wizard updates a profile in
  Hammerspoon) the emitted TOML diff should be small and readable.
  Sorting by name guarantees consistent ordering even when Lua's
  table order changes between runs.

### Effort estimate update

The original ConfigImporter estimate was **2-3 h**. Actual: ~45 min
including 14 tests, the round-trip-via-ConfigLoader test, and the
real-profiles.lua parse test.

### Phase 2 status

Pure-Swift / framework-independent work is complete. Tally:

| Component | Original | Actual |
|---|---|---|
| ProfileResolver + Debouncer | 2-3h | ~30 min |
| ProfileApplier + Audio adapter + OBS adapter | 5-8h | ~70 min |
| USBWatcher | 4-6h | ~25 min |
| Engine coordinator | (in applier budget) | ~25 min |
| ConfigLoader | 1-2h | ~30 min |
| ConfigImporter | 2-3h | ~45 min |
| App target + StatusItem | 2-3h + 1-2h | ~30 min |
| **Through end-to-end runnable app** | **17-27h** | **~4h** |

67 tests, all sub-millisecond. `swift test` runs the full
suite in ~6 ms. `swift run AVPainRelieverApp` launches the
menu-bar agent.

Remaining work is all distribution / UI polish where speedups are
unlikely:

1. **`Notifier`** — UserNotifications wrapper for "Switched to X" toasts.
2. **First-run wizard / preferences SwiftUI** — bulk of remaining work.
3. **Xcode project** to wrap the Swift Package — required for proper
   `.app` bundle output, code signing, and notarization. Until then,
   `swift run` works for development; only the distribution phase
   needs the bundle.
4. **Code signing + notarization + Sparkle + GitHub Actions release** —
   distribution plumbing.

---

## App target port (AVPainRelieverApp)

The first runnable Swift menu-bar agent. Lives at
`Sources/AVPainRelieverApp/`. ~150 lines across four files. Run
with `swift run AVPainRelieverApp`.

### Architecture

```
Sources/AVPainRelieverApp/
├── App.swift            # @main SwiftUI App with MenuBarExtra
├── AppDelegate.swift    # NSApplicationDelegate, owns Engine, exposes
│                        # @Published currentProfileTitle
├── ConsoleLogger.swift  # ApplierLogger backed by os.Logger
└── PrettyName.swift     # "home-office" → "Home Office"
```

The `App` declares a `MenuBarExtra` scene labeled with the
current pretty profile name; AppDelegate's `@Published
currentProfileTitle` updates trigger SwiftUI re-renders. Engine's
new `onProfileApplied` callback (fires on every evaluation, even
no-op re-applies) drives the property.

Profile-config discovery in priority order:

1. `~/Library/Application Support/AVPainReliever/profiles.toml` —
   the canonical Swift-app config location (where the eventual
   first-run wizard will write).
2. `~/.hammerspoon/profiles.lua` — auto-imported via
   `ConfigImporter` for users migrating from Phase 1. Zero-touch
   migration for existing Hammerspoon users.
3. Empty list — engine logs a warning and runs idle.

### Lessons learned

- **`NSApp.setActivationPolicy(.accessory)` at runtime substitutes
  for `LSUIElement = YES` in Info.plist.** SPM-built executables
  don't have an Info.plist; setting the activation policy in
  `applicationDidFinishLaunching` hides the dock icon
  near-immediately. The eventual signed `.app` bundle will set
  `LSUIElement` declaratively (more reliable: prevents the
  flash-in-dock at launch). For developer iteration via
  `swift run`, the runtime call is fine.
- **`MenuBarExtra` (SwiftUI, macOS 13+) is sufficient for our v1
  menu surface.** No need to drop to `NSStatusItem`. The SwiftUI
  declarative form composes cleanly with `@Published` for live
  updates and `Button { }` for menu actions, and the
  `.menuBarExtraStyle(.menu)` modifier gets us the standard
  pull-down menu (vs. the popover form that we'd want for a
  full preferences pane).
- **`@Published` + `@NSApplicationDelegateAdaptor` does NOT
  propagate to `MenuBarExtra`'s label/content closures when the
  closures access the property directly inside the App's `body`.**
  The Scene-level body does re-evaluate when the AppDelegate's
  ObservableObject publishes a change, but the new label closure
  doesn't get re-rendered — the menu bar text stays stale.
  Spent ~30 min thinking the engine wasn't running before
  diagnosing this. **Fix**: wrap label + content in their own
  `View` types with `@ObservedObject var delegate: AppDelegate`.
  View-level dependency tracking does what we expect; Scene-level
  doesn't (in this version of SwiftUI on macOS 26). Also added
  stderr mirror to `ConsoleLogger` to make this kind of
  app-vs-engine confusion easier to diagnose for unbundled SPM
  builds — `os.Logger` capture under our subsystem turned out to
  be unreliable from non-bundled binaries.
- **Engine needed an `onProfileApplied` callback** to drive the
  status-item title. The applier's `lastAppliedName` is private
  and the applier dedups on it, so a public observation hook on
  the *engine* (which fires after every evaluation, including
  ones the applier no-op'd) is the right level. Adding this was
  ~3 lines on Engine + 1 test + zero impact on the existing 38
  engine/applier tests.
- **`os.Logger` replaces the file appender from Phase 1.** The
  Hammerspoon engine wrote a parallel log at
  `~/.hammerspoon/logs/av-pain-reliever.log`. Console.app's
  filtering and search make a separate file appender redundant —
  `log stream --predicate 'subsystem ==
  "com.ericwillis.avpainreliever"'` gives a live tail, and Console
  itself indexes everything. Saves a Phase 1 lesson learned (file
  rotation, mkdir-p of the log dir, etc.) from being re-implemented.
- **Config auto-import from `~/.hammerspoon/profiles.lua` on
  first launch is "free migration."** Users who installed Phase 1
  pick up the new app, run `swift run AVPainRelieverApp` (or
  later, double-click the `.app`), and it Just Works against
  their existing config. No copy-paste, no wizard click-through
  for migrating users. The eventual first-run wizard can offer to
  *write* the imported config to the canonical TOML location, but
  even before that lands, the runtime auto-import gets users
  going.
- **No-Xcode-project-yet is the right call for now.** Generating a
  valid `.xcodeproj` from CLI requires either Tuist/XcodeGen as a
  build dep or hand-crafting a file with hundreds of GUID-laden
  internal references. Neither pays for itself until we need a
  signed `.app` bundle. SPM's `executableTarget` produces a
  runnable binary today, defers the bundle question to the
  distribution phase, and keeps the project structure boringly
  vanilla SPM.

### Verification

- **Build**: `swift build --product AVPainRelieverApp` — clean.
- **Tests**: 73 passing.
- **Launch**: confirmed working — `swift run AVPainRelieverApp` boots
  the engine, auto-imports `~/.hammerspoon/profiles.lua`, resolves
  the docked profile (home-office), sets system audio defaults,
  switches OBS scene, and renders the live profile name in the menu
  bar. Real-world smoke test on Eric's docked setup 2026-05-01.

---

## Real-launch findings (post-first-run)

The first real launch surfaced two bugs and one behavior gap. All
three fixed in the same commit.

### Bug: unconfigured wizard stubs shadowing `laptop` alphabetically

**Symptom**: Undocking caused the menu-bar title to flip to
"Conference Room" instead of "Laptop".

**Root cause**: The Phase 1 wizard generates `profiles.lua` with
four template profiles (laptop, home-office, work-office,
conference-room). The latter two have empty fingerprints and
`audioInput = "FILL ME IN"` placeholders the user is supposed to
fill in. With three profiles all having empty fingerprints
(specificity 0), the resolver's alphabetical tiebreak picks the
first one — `conference-room`. The Hammerspoon engine has the same
bug; user just hadn't noticed because they're usually docked.

**Fix**: `ConfigImporter.parse` now drops any profile whose
audioInput or audioOutput equals the literal string `"FILL ME IN"`.
A new `parseAll` method preserves the unfiltered behavior for
diagnostic tools and tests. Three new tests in
`ConfigImporterTests` cover the filter, including the half-
configured case (one field FILL ME IN, the other real). The
real-world `profiles.lua` test was updated to expect filtered
output.

Also cleaned the user's actual `profiles.lua` to remove the two
stubs entirely, since they were never going to be filled in (the
user only operates from home-office and undocked-laptop).

### Feature gap: no signal when user docks somewhere unfamiliar

**Symptom**: User feedback during the real-launch session — "the
app should notice a new configuration and ask to set it up when it
happens."

**Implementation**: `Engine.onUnknownLocation: ((Set<USBDevice>) ->
Void)?` callback fires when the resolver picks the empty-fingerprint
fallback profile (i.e., specificity 0, matches anything) AND there
ARE devices currently attached. Doesn't fire on plain undocked
state (empty attached set + fallback resolution = "I'm at the
laptop", that's normal). Doesn't fire on specific-fingerprint
matches (those are known locations, not new). Three Engine tests
cover the three cases.

`AppDelegate` wires this to a one-shot toast: "New location
detected: N USB devices attached. Add it to your profiles so AV
Pain Reliever can switch automatically." The "one-shot" gating
re-arms when the user next resolves to a real-fingerprint profile,
so docking at a second new location after configuring the first
gets a fresh toast.

### Notifier (UserNotifications stand-in)

`UserNotifications` (`UNUserNotificationCenter`) requires a real
bundle identifier, which our SPM-built dev binary doesn't have.
Stop-gap: `AppleScriptNotifier` shells out to `osascript -e
'display notification ... with title ...'` via `Foundation.Process`.
Works without a bundle, surfaces under whatever app `osascript`
runs as. Will swap for `UNUserNotificationCenter` when the signed
`.app` ships. Recorded as a TODO in the file's doc comment.

`AppDelegate` fires the notifier:
- On profile change (different name from the previous evaluation)
- On unknown-location detection (one-shot per stretch of
  unknown-ness, see above)

The initial-evaluation toast on launch is intentionally
suppressed — the menu-bar title is already showing the correct
profile, so a duplicate toast would be noise.

### Effort estimate update

Original estimate was **2-3 h** (Xcode project) + **1-2 h**
(StatusItem) = **3-5 h**. Actual: ~30 min for the SPM-based app
target with menu-bar UI. The Xcode project itself is deferred to
the code-signing phase, where it's necessary for proper `.app`
bundle output.

---

## V1 design pass (2026-05-01)

The functional engine + wizard was complete (94 tests, end-to-end
working) before this pass. The brief: take the app from "trustworthy
native utility that works" to "trustworthy native utility you'd want
on your machine." Raycast-clean SwiftUI defaults with brand-color
pops, warm copy, a few moments of tasteful delight.

### What shipped

**Brand foundation**

- `Theme` namespace owns the locked palette (magenta `#FF87D7` primary,
  cyan `#00FFFF` highlight, success/warn/error/chrome) plus standard
  SF Symbols (`pills.fill` app icon, `tag.fill` / `cable.connector` /
  `speaker.wave.2.fill` / `camera.fill` for wizard sections). Views
  never hard-code hex values — a future palette tweak (or a real
  dark-mode override) is one file.
- `ProfileIcon` maps slugs → SF Symbols with prefix/contains
  heuristics. `home*` → `house.fill`, `work*`/`office` →
  `building.2.fill`, `conference`/`meeting` → `person.3.fill`,
  `studio`/`podcast` → `music.mic`, `cafe`/`coffee` →
  `cup.and.saucer.fill`, plus `library`, `garage`, `lab`, `hotel`,
  `school`. Unknown slugs fall through to `mappin.and.ellipse`.
  Specificity ordering matters: `conference-home` lands on people
  before house, `home-office` lands on house before building (the
  more-specific predicate runs first).

**Wizard polish**

- Hero header: pill icon + magenta title + cyan subhead.
- Section headers carry SF Symbol icons in primary magenta.
- Save button is brand-magenta primary with a brief green-checkmark
  "Saved" affordance for ~0.45 s before the window closes — the
  smoother feedback the brief asked for.
- Auto-suggest profile name from attached devices: a CalDigit dock
  pre-fills "Home Office", an LG monitor pre-fills "Office", a
  Yeti/Shure mic pre-fills "Studio". Suggestion only, fully editable.
  No-op when editing an existing profile.

**Menu enrichment**

- Each profile in the "Switch to" submenu shows its slug-mapped SF
  Symbol next to the name (or a checkmark when active).
- Each profile is itself a sub-submenu with Switch to / Edit… /
  Delete… entries. Right-click contextMenu would be cleaner but
  SwiftUI's `MenuBarExtra` doesn't propagate it to its child entries
  in the macOS 14 SDK; the sub-submenu chain achieves the same
  affordance.
- Optional one-line caption per profile shows the audio + camera
  it would apply (`🎙 Yeti  •  🔈 CalDigit  •  📷 Built-in`), gated
  by Settings → "Show audio + camera details in menu".
- Settings… (⌘,) and About AV Pain Reliever menu items added below
  the existing admin block.

**Notification copy with personality**

- `NotificationCopy.title(forSlug:)` rotates 2-4 alternates per
  common slug family. Selection is deterministic on day-of-year so
  the title varies between days but doesn't whiplash within a single
  docking cycle. Body is constant: "Audio + camera switched".
- Notifications are now gated by Settings → "Send notifications when
  profiles change" (default on).

**Settings scene** (`Settings { }`, opens with ⌘,)

- General tab: notifications toggle, audio+camera-in-menu toggle,
  debounce-window slider (0.5–5.0 s, default 1.5 s — engine rebuilds
  with the new value on next reload).
- Profiles tab: full list with magenta-tinted icons, "Active" pill
  on the resolved profile, Edit and Delete buttons per row. Empty
  state has a friendly tray icon + warm copy.
- Deliberately no mention of Hammerspoon, OBS, or any third-party
  tool. Per `feedback_app_self_contained`.

**About window**

- Replaces `NSApp.orderFrontStandardAboutPanel` with a SwiftUI scene:
  pulsing pill hero in magenta, title in big rounded magenta type,
  cyan tagline, version string, "Made to stop the fiddling" italic
  line.

**First-run welcome**

- Shown when no profile has a real fingerprint AND the user hasn't
  previously dismissed the welcome. Hero pill, magenta title, cyan
  tagline, warm one-paragraph explainer, magenta "Add Your First
  Location" CTA, cyan "Skip — I'll set up later" link. Suppressed
  forever once either button is clicked or any profile saves.
- Implemented as a SwiftUI `Window` scene whose visibility is
  triggered by an `@Published shouldShowWelcome` flag on
  `AppDelegate` — read by a hidden `WelcomeOpener` view inside the
  `MenuBarExtra` so it can call SwiftUI's `openWindow` (which is
  environment-only and not reachable from `AppDelegate` directly).

**Edit + delete plumbing**

- `ProfileWriter.delete(named:in:)` excises a `[profiles.<name>]`
  section while preserving surrounding content, comments, and
  header banners. Tidies trailing blank lines.
- `AddProfileViewModel` takes an optional `editing: Profile?` —
  pre-fills name (pretty-cased), audio, camera, and the selected
  fingerprint. Save dispatches to replace mode when the slug is
  unchanged; renaming during edit cleans up the prior section
  automatically.
- Native `NSAlert` confirms before delete.

**Persistent settings**

- `SettingsStore` (`UserDefaults`-backed): notificationsEnabled,
  debounceInterval, showAudioCameraInMenu, profileSwitchCount,
  suppressedWelcome. Defaults treat `object(forKey:) == nil` as
  "never set" so default-on toggles stay on across launches.
- `AppDelegate` republishes `settings.objectWillChange` through its
  own `objectWillChange` so views observing the AppDelegate (the
  menu, the About scene) re-render on a settings flip without each
  having to observe the store directly.

**Easter egg**

- Hold Option while the menu is open to reveal a cyan stats line
  under the title: "Switched 47 times. Saving your sanity since
  plug-in #1." Bumped from every actual profile change. Pluralizes
  correctly at counts 0/1/2+.

### Lessons learned

- **`MenuBarExtra` doesn't propagate `contextMenu(for:)` to its
  child Buttons.** Right-click on a profile entry in the "Switch to"
  submenu doesn't surface anything. Workaround: nest each profile
  inside its own `Menu` so Switch / Edit / Delete read as a sub-
  submenu. Discoverability is slightly worse than right-click but
  the affordance survives. Re-evaluate when SwiftUI's MenuBar APIs
  pick up `contextMenu` support (FB-pending).
- **`@MainActor`-isolating `SettingsStore` blocks the AppDelegate
  from reading from non-main contexts.** `buildEngine` is called from
  `bootEngine`, which the docs reach but which isn't yet `@MainActor`
  itself; rather than annotate the entire AppDelegate, drop the
  isolation from `SettingsStore` (`UserDefaults` is thread-safe and
  the `@Published` mutations in the wizard happen from main anyway).
  Same trick applies to any future small persistence helper.
- **Republishing one ObservableObject through another is one line
  of Combine.** `settings.objectWillChange.sink { [weak self] in
  self?.objectWillChange.send() }.store(in: &cancellables)` lets the
  SwiftUI graph treat AppDelegate as the canonical source for both
  engine state AND user preferences. Saves passing `SettingsStore`
  into every view via `@ObservedObject`.
- **First-run welcome can't open a window from the AppDelegate.**
  SwiftUI's `openWindow` is environment-only; AppDelegate has no
  `EnvironmentValues`. Workaround: AppDelegate publishes
  `shouldShowWelcome: Bool`, and a hidden helper view inside the
  `MenuBarExtra` scene watches it via `.onChange` and calls
  `openWindow` from its own environment. Clean, no AppKit cycling.
- **A pure-logic test target for the App module is worth it.**
  ProfileIcon, NotificationCopy, StatsCopy, SettingsStore, and the
  AddProfileViewModel are all unit-testable without AppKit. SPM's
  `executableTarget` can be `@testable`-imported by a sibling
  `testTarget` — no Xcode project required for coverage.
- **Save-success feedback wants 0.45 s, not 0.2 s and not 1.0 s.**
  At 0.2 s the green flash is gone before the eye registers. At 1.0 s
  the modal feels sluggish. 0.45 s reads as a confirmed beat without
  blocking flow.

### Effort estimate update

The pass touched ~1500 lines across 8 new files + 5 modified files,
plus 36 new tests. ~3 hours actual against an open-ended brief. Most
of that was the Settings + About + Welcome scenes (each is ~80–150
lines). The pure-logic helpers (ProfileIcon, NotificationCopy,
StatsCopy) took minutes each because the surface is a single function
+ a small mapping table.

### Deferred to v2

- ~~Custom app icon~~ — runtime-generated icon shipped in the polish
  pass below. Asset Catalog version still pending for the signed
  `.app`.
- User-customizable per-profile icons (auto from slug for v1).
- OBS scene routing as a Settings tab.
- ~~Sparkle / signing / GitHub Actions release pipeline~~ — landed
  2026-05-02 (see "Distribution pipeline kickoff" below); appcast
  hosted on raw.githubusercontent.com.
- "Show Welcome Again" menu/affordance — easy to add later if
  someone asks.

---

## V1 polish pass (2026-05-01)

A second design pass on the same day, focused on fit-and-finish and
on fixing one regression I'd shipped in the V1 design pass. Five
buckets:

### Menu UX restoration

The V1 design pass had wrapped each profile in the "Switch to"
submenu in its own sub-submenu (Switch / Edit / Delete) — three
clicks to switch, vs. the pre-V1 menu's one click. Restored to a
flat menu: each profile is a `Button` that applies on click; Edit
and Delete already live in Settings → Profiles.

The per-profile summary line ("🎙 Yeti  •  🔈 CalDigit  •
📷 Built-in") is now inlined onto the same row as the name. AppKit's
Menu renderer flattens VStack labels to just the first line in
`MenuBarExtra` menus, so the previous multi-line layout never
showed the summary in the actual menu — only in SwiftUI previews.

### Unknown-location state

`AppDelegate` carries two new published flags (`atUnknownLocation`,
`lastUnknownDevices`), set when `Engine.onUnknownLocation` fires
(empty-fingerprint resolution + non-empty attached set). Both reset
the moment the engine resolves to a real-fingerprint profile.

Visible effect: when fallback fires with USB attached, the menu-bar
label switches to a `questionmark.circle` icon + "New location" text;
the menu header reads "New location detected — N USB devices
attached"; a magenta "Set Up This Location…" CTA opens the wizard
with all attached devices already pre-selected (the wizard already
did this; the CTA is just a more discoverable entry point).

Without this, the user docking somewhere new sees the menu bar say
"Laptop" and assumes the engine missed the USB event. The status
toast already told them "new location" but a transient banner
isn't enough — the menu has to keep telling the truth.

### App icon (runtime-generated)

`AppIcon.makeIcon()` renders a 1024×1024 squircle with a
magenta→deep-magenta→cyan radial gradient and a white `pills.fill`
SF Symbol on top with a soft shadow. Wired at launch via
`NSApp.applicationIconImage` and reused by the About + Welcome
heroes (rounded-rect-clipped at 96/104 px).

The white-symbol-on-gradient trick uses `.destinationIn` compositing:
fill a fresh image with white, then `destinationIn`-clip by the
template SF Symbol's alpha mask. The result is a real white-filled
symbol image that draws cleanly onto the gradient. SwiftUI's
`Image(systemName:).foregroundStyle(.white)` doesn't help here
because we need an `NSImage` to composite into the AppKit graphics
context, not a SwiftUI view.

Generated in memory rather than shipped as a `.icns` so palette
tweaks don't need a regenerated Asset Catalog. The signed `.app`
will eventually carry a proper Asset Catalog AppIcon for higher-
fidelity rendering at 16/32/64-pt sizes; the runtime icon covers
the dev workflow without an Xcode project.

### Launch at Login

New `SettingsStore.launchAtLogin` (default off — fresh users opt
in, per macOS background-task etiquette). `LaunchAtLogin.apply(
enabled:)` wraps `SMAppService.mainApp.register()` /
`unregister()`. AppDelegate calls apply() on launch so a setting
toggled in a previous session takes effect.

Caveat: `SMAppService` needs a properly bundled `.app` for clean
registration. The SPM dev binary will see `register()` throw — the
helper logs and continues so the toggle stays usable in Settings;
once the signed `.app` ships, the same code starts working with no
app-side changes. This is the same SPM-dev-vs-signed-bundle
shimming pattern as `Notifier` (AppleScriptNotifier vs the eventual
UNUserNotificationCenter wrapper).

### Theme adaptive colors

The locked palette (`#FF87D7` magenta, `#00FFFF` cyan, `#00FF00`
green, `#FF0000` red) is tuned for dark backgrounds — mirrors the
Hammerspoon TUI which assumes a dark terminal, and the menu-bar
agent's most common surfaces (the menu, dark-mode windows) are
dark. On light-mode forms the canonical hex codes washed out:
`#00FFFF` cyan on white is unreadable as link text.

`Theme.Color.{primary,highlight,success,error}` now return adaptive
colors via an `NSColor` dynamic provider. The canonical hex codes
are preserved as the dark-mode value; a darker, more saturated
cousin handles light mode. The brand-pop intent stays — the user
can't tell from glancing at either appearance that anything's
adaptive, but light-mode contrast is now WCAG-respectable.

This respects the spirit of the locked palette (the brand color in
the surface that matters most — the menu, dark-mode windows — is
exactly the canonical hex) while fixing a real accessibility
concern. Documented prominently in the file's doc comment so a
future palette tweak goes through both variants.

### Lessons learned

- **`MenuBarExtra` collapses multi-line VStack labels to one line.**
  AppKit's menu renderer pulls the first line out of a VStack and
  drops the rest. Looks fine in SwiftUI previews; ships broken in
  the actual menu. Inline summary text is the only reliable way to
  add a sub-line to a menu entry.
- **SF Symbols are template images; `.foregroundStyle(.white)` /
  `setFill()` doesn't tint them when drawing into an AppKit context.**
  Use `.destinationIn` compositing (fill white → clip by symbol
  mask) to get a real white-filled image you can composite. Pattern
  generalizes to any tint of any SF Symbol when drawing into a CG
  context.
- **`SMAppService.mainApp` needs a real bundle.** The SPM dev binary
  fails the registration silently (or throws). Wrap the call so
  failures log + return — the user toggling Settings during dev
  doesn't crash anything, and the same code starts working once
  the signed `.app` ships. Same pattern we used for the
  AppleScriptNotifier dev-vs-bundle shim.
- **The locked palette needed light-mode variants for
  accessibility.** Pure cyan and pure green are unreadable on
  white. Adaptive colors via `NSColor(name:dynamicProvider:)` keep
  the dark-mode brand intact and let light-mode breathe — same
  pattern Apple uses for system colors. Honor the canonical hex
  in the appearance that matters most (dark, where the menu lives
  most of the time) and tweak the cousin for light.
- **Keyboard shortcuts in SwiftUI menus are global to the menu's
  scope.** Two `Button(...)`s with `.keyboardShortcut("n")` in the
  same menu silently breaks both. Surface a generic "Add Profile…"
  shortcut on one entry, leave the visually-prominent CTAs without
  a shortcut.

### Effort estimate update

Polish pass: ~1.5 hours, 2 new files + 8 modified files, +1 test
(menu state changes are easier to verify by smoke-launch than to
unit-test against AppKit). Total polish + design pass over the same
day: ~4.5 hours, 35+ tests added.

### Deferred to v2 (after polish)

- ~~Asset-Catalog AppIcon for the signed `.app`~~ — replaced 2026-05-02
  with a `Resources/AppIcon.icns` rendered from `AppIcon.swift`'s
  pill via `scripts/build-icon.sh`. No Asset Catalog needed.
- User-customizable per-profile icons.
- OBS scene routing as a Settings tab.
- ~~Sparkle / signing / GitHub Actions release pipeline~~ — landed
  2026-05-02.
- ~~"Show Welcome Again" affordance~~ — shipped in the fit & finish
  pass below.
- Right-click context menu on profile rows — would let us put
  Edit/Delete back on the menu without losing the one-click
  switch. SwiftUI MenuBarExtra doesn't support `contextMenu`
  propagation in macOS 14; revisit when SDK support lands.

---

## V1 fit & finish (2026-05-01 — third pass same day)

A short third pass focused on individual rough edges spotted on
the polished build. Three buckets, each landed in its own commit.

### Wizard: live profile-icon preview

The Name section now renders the SF Symbol the menu would use
for the typed slug, live, with a short crossfade. Surfaces the
"each location gets its own icon" feature visually and tells the
user what their slug matched on without forcing them to save +
inspect the menu. `AddProfileViewModel.previewSlug` exposes the
slug used for the icon; falls back to a generic placeholder slug
while the field is empty so the icon doesn't flicker on every
keystroke at the start.

### Wizard: "Suggested: untick" portability badges

`DevicePortability.portabilityCategory(deviceName:)` classifies
attached USB devices by name into "this almost certainly travels
with you" categories — keyboards, pointing devices, phones /
wearables, headphones, watches. The fingerprint list now shows a
yellow capsule "Suggested: untick (<category>)" on flagged rows.

Conservative on purpose — when in doubt, don't flag, because a
wrong-positive (silently dropping an actually-fingerprintable
peripheral) is worse than a missed flag (the user spends two
seconds unticking three rows manually). Auto-untick was
considered and rejected for the same reason.

### Warmer toast copy

The "new location detected" toast body switched from
> 5 USB devices attached. Add it to your profiles so AV Pain
> Reliever can switch automatically.

to
> 5 USB devices joined the party. Open the menu to teach me
> this spot.

Same information, half the words, voice consistent with the rest
of the app. Pulled into a public testable helper at
`NotificationCopy.unknownLocationBody(deviceCount:)`.

### Profiles tab empty state

`Settings → Profiles` previously rendered a generic SF tray icon
+ small caption when no profiles existed. Replaced with an
inviting empty-state hero: rounded-rect-clipped app icon with a
soft shadow, magenta "Set up your first location" headline, a
sentence of explainer copy, and a large magenta "Add Profile" CTA.
The empty state now reads as part of the product, not as a
placeholder.

### Show Welcome Again

The first-run welcome window is suppressed forever after the user
clicks either button. The About scene now carries a small "Show
welcome again" link below the explainer copy that flips the
published flag, dismisses About, and re-opens the welcome via the
existing `WelcomeOpener` watcher. `AppDelegate.showWelcomeAgain()`
toggles `shouldShowWelcome` false→true across runloop turns so
the `.onChange` watcher fires even if the flag was already true.

### Wizard error banner

`viewModel.lastError` previously rendered as a single line of
`.foregroundStyle(.red)` text. Now wrapped in a proper banner:
triangle warning icon, error-tinted background + border, padded
rounded rectangle, opacity+slide transition on appear. Same
information, much higher signal — the user can't miss it.

### Lessons learned

- **`MenuBarExtra` activated views can take an `@ObservedObject`
  AppDelegate** even when the AppDelegate's own properties
  changed via Combine republishing. The dependency tracking
  picks up the republished signal without complaint. This is
  what made `Show Welcome Again` work — a Settings change
  observed in the menu's stats line + an About-scene
  callback driving an AppDelegate published property all
  flow through the same single observation.
- **NSImage rounded-rect clipping inside SwiftUI doesn't need
  an `Image(uiImage:)`-style hack on macOS** — `Image(nsImage:
  AppIcon.image).resizable().clipShape(RoundedRectangle(...))`
  works directly. The signed `.app`'s Asset Catalog icon will
  still be sharper at small render sizes, but the runtime icon
  composites cleanly enough at 76+ pt.
- **Conservative classification beats aggressive defaults.** The
  Wizard's "Suggested: untick" hint is on portable devices only
  — auto-unticking would silently drop an ergonomic-keyboard
  fingerprint the user actually wanted, and that failure
  (silent data loss in a config workflow) is irrecoverable
  without re-discovery. The badge surfaces the suggestion;
  the user remains in control of every checkbox.

### Effort estimate update

Fit & finish pass: ~1 hour, 1 new file + 8 modified files,
+9 tests (140 total). Combined day-of-2026-05-01 design + polish
+ fit & finish: ~5 hours actual, 45+ tests added across three
commits' worth of UI/UX work plus the supporting library + app
helpers. The tests bias is intentional — every pure-logic
helper (Theme adaptation aside) gets a `testTarget` rather than
relying on visual smoke tests, since smoke tests can't gate CI.

### Deferred (still on the v2 list)

- ~~Asset-Catalog AppIcon for the signed `.app`~~ — superseded by
  `scripts/build-icon.sh` rendering the pill into `.icns` (2026-05-02).
- User-customizable per-profile icons.
- OBS scene routing as a Settings tab.
- ~~Sparkle / signing / GitHub Actions release pipeline~~ — landed
  2026-05-02 (Distribution pipeline kickoff section below).
- Right-click context menu on profile rows.
- Notification-action support ("Open Wizard" button on the
  unknown-location toast). Needs UNUserNotificationCenter, which
  ~~needs a real bundle~~ becomes available now that we ship a
  signed `.app` — re-evaluate when revisiting notifications.

---

## Distribution pipeline kickoff (2026-05-02)

Phase 2 distribution — turning the SPM executable into a signed,
notarized, auto-updating `.app` released via GitHub Actions on tag
push. The work landed in a single session, with one user-driven
follow-up (Apple Developer Program enrollment + Sparkle EdDSA key
generation) gating the first real release.

### What landed

- `Resources/Info.plist` — bundle metadata, `LSUIElement=YES`,
  `LSMinimumSystemVersion=14.0`, `SUFeedURL` pointing at
  `raw.githubusercontent.com/superic/av-pain-reliever/main/appcast.xml`,
  `SUPublicEDKey` placeholder waiting on first `generate_keys`.
  `__MARKETING_VERSION__` / `__BUILD_VERSION__` substituted at build
  time by `make-app.sh`.
- `Resources/AVPainReliever.entitlements` — `app-sandbox=NO`. The
  engine reads `~/Library/Application Support`, talks to IOKit and
  CoreAudio, and uses `SMAppService` for Launch-at-Login — none of
  which are sandbox-compatible. No special hardened-runtime
  exceptions needed.
- `Resources/AppIcon.icns` (455KB) — rendered from
  `Sources/AVPainRelieverApp/AppIcon.swift`'s pill design via
  `scripts/build-icon.sh` + `scripts/icon-exporter.swift`. Renders
  natively at each iconset size (16/32/64/128/256/512/1024 + @2x)
  rather than downscaling a single high-res master, which gives SF
  Symbols a chance to use size-specific glyphs and stay crisp at
  16×16.
- `scripts/make-app.sh` — universal-binary build (`swift build
  --arch arm64 --arch x86_64`), bundle assembly, version stamping
  via sed substitution, embedding of Sparkle.framework's macOS slice
  from the SPM artifact directory, `install_name_tool -add_rpath
  @executable_path/../Frameworks` (SPM only adds `../lib`),
  inside-out codesigning of Sparkle's nested helpers, and a final
  ad-hoc-or-Developer-ID sign of the main app driven by the
  `MAC_CERT_NAME` env var.
- `Sources/AVPainRelieverApp/Updater.swift` + the AppDelegate hook —
  thin wrapper around `SPUStandardUpdaterController`, plus a
  conditional gate that skips Sparkle init when running outside a
  proper bundle (`swift run`) **or** when the SUPublicEDKey is still
  the `__SPARKLE_PUBLIC_KEY__` placeholder. Without the placeholder
  guard, dev builds pop a "Unable to Check For Updates / EdDSA key
  not valid" dialog at every launch.
- `Sources/AVPainRelieverApp/App.swift` — "Check for Updates…" item
  added to the existing **Advanced** submenu (commit `8f54caf`).
- `appcast.xml` (stub) — empty `<channel>` so the first running app
  resolves to "you're up to date" against an empty feed.
- `.github/workflows/release.yml` — fires on `v*.*.*` tag push,
  imports the cert from `MACOS_CERTIFICATE` (base64 `.p12`) into a
  temp keychain, runs `make-app.sh`, runs `notarytool submit
  --wait`, staples, EdDSA-signs the zip via Sparkle's `sign_update`,
  drafts a GitHub Release with auto-generated notes, then commits
  the new `<item>` to `appcast.xml` on `main`. Each Apple- or
  Sparkle-secret-dependent step early-exits with a `::warning::` if
  the secret is empty, so a `v0.0.0-dryrun` tag exercises the
  workflow end-to-end without credentials.
- `scripts/sign-appcast.sh` — wraps `sign_update`, emits a
  ready-to-paste `<item>` block. Reads the private key from
  `$SPARKLE_PRIVATE_KEY` (CI) or the `avpainreliever` keychain
  account (local).
- `docs/RELEASING.md` — runbook for Apple Developer Program
  enrollment, Sparkle key generation, the seven `gh secret set`
  commands, the first-tag checklist, and a troubleshooting section.

### Lessons learned

- **macOS file-provider race against codesign.** Building the
  bundle directly under `dist/` in a `~/Documents`-rooted repo
  triggered a race: macOS's fileprovider daemon (visible as a
  lingering `com.apple.fileprovider.fpfs#P` xattr) re-added
  `com.apple.FinderInfo` to the bundle root in the milliseconds
  between our `xattr -cr` scrub and codesign's read, causing a
  "resource fork detritus not allowed" failure on the main-app
  sign every time. `xattr -cr "$path" && xattr -d
  com.apple.FinderInfo "$path"` immediately before codesign wasn't
  enough — the race was tighter than that. Fix: assemble + sign in
  a `mktemp -d`, `ditto` the finished bundle to `dist/` at the end.
  /tmp isn't watched by fileprovider.
- **Sparkle.framework needs an explicit rpath.** SPM only injects
  `@executable_path/../lib` into the executable. Sparkle's binary
  expects `@rpath/Sparkle.framework/Versions/B/Sparkle`, where
  `@rpath` is conventionally `@executable_path/../Frameworks`.
  Patching it post-build with `install_name_tool -add_rpath
  @executable_path/../Frameworks` is one line and avoids unsafe
  linker flags in `Package.swift`.
- **Sparkle's nested bundles (Updater.app, Downloader.xpc,
  Installer.xpc) ship pre-signed by the Sparkle project.**
  Re-distributing requires re-signing each one with our identity
  before signing the framework before signing the main app —
  Apple's `--deep` flag is deprecated and notarization rejects it.
  Inside-out, path-by-path is the supported approach.
- **`generate_keys` writes to the user's login keychain.** Running
  it from an automated agent isn't appropriate (it produces a
  long-lived credential the user owns); the docs walk the user
  through running it themselves, replacing the
  `__SPARKLE_PUBLIC_KEY__` placeholder in `Info.plist`, and stashing
  the private key in 1Password + `gh secret set
  SPARKLE_PRIVATE_KEY`.
- **GitHub Actions secrets can't be used in `if:` conditions
  directly.** Tried `if: ${{ secrets.X != '' }}` and it doesn't
  evaluate as expected. The clean pattern: every step runs, but
  the step body checks `[[ -z "${X:-}" ]]` and `exit 0` with a
  `::warning::` if missing. That gives us the "dryrun tag works
  with no Apple creds" property.
- **macOS bash 3.2 + `set -u` + empty arrays.** `"${arr[@]}"`
  expansion on an empty array under `set -u` errors with
  "unbound variable." Use `${arr[@]+"${arr[@]}"}` for the
  empty-safe expansion.

### Pending (gated on user)

- Apple Developer Program enrollment ($99/yr, 24–48h approval).
- Sparkle EdDSA keypair generation + Info.plist substitution.
- Setting the seven GitHub Secrets per `docs/RELEASING.md`.
- First `git tag v0.1.0` push to exercise the workflow end-to-end.
- Smoke-test auto-update by tagging `v0.1.1` immediately after
  with a one-line README change.

`docs/RELEASING.md` is the canonical handoff for these.

### Verification done in this session

- `scripts/make-app.sh` produces a valid universal-binary
  `dist/AVPainReliever.app` with embedded `Sparkle.framework`,
  ad-hoc signed, that launches and surfaces the menu-bar pill
  + engine.
- 145 of 146 tests still pass (`IOKitUSBWatcher` test depends on
  attached USB hardware, unrelated to distribution work).
- `swift build -c release --arch arm64 --arch x86_64` clean.
- Sparkle wiring confirmed by an earlier crash dialog: with the
  placeholder public key in Info.plist, Sparkle correctly
  initialized, fetched feedURL, then refused to start ("EdDSA key
  not valid") — proving every step except verification works. The
  guard in `AppDelegate` now suppresses the dialog by skipping
  Sparkle init until a real key is committed.

---

## v0.1.0 shipped (2026-05-03)

Apple Developer Program approved 2026-05-02 evening. The full
Phase 4 (cut v0.1.0) ran the same night. Tag landed, release
workflow turned green, draft GitHub Release published with a
notarized + stapled `AVPainReliever.app.zip`, and `appcast.xml`
on `main` carries a signed `<item>` for v0.1.0. The remaining
local smoke test (drag to /Applications, double-click, no
Gatekeeper warning) is queued for the morning, with the v0.1.1
auto-update exercise immediately after.

### What landed for v0.1.0

- Sparkle EdDSA keypair: public key embedded at
  `Resources/Info.plist:44`, private key in user's login keychain
  + 1Password + as `SPARKLE_PRIVATE_KEY` GitHub Secret.
- Developer ID Application certificate generated via Apple's CSR
  flow, installed in login keychain, exported to `cert.p12`,
  base64'd into `MACOS_CERTIFICATE` GitHub Secret. Cert identity:
  `Developer ID Application: Eric Willis (HLH4LEWS9S)`.
- App-specific password for `notarytool` generated at
  appleid.apple.com, stored as `APPLE_ID_PASSWORD` Secret AND
  locally as keychain profile `avpain-notary` so future
  `xcrun notarytool …` calls can use `--keychain-profile
  avpain-notary` instead of typing it.
- All seven GitHub Secrets populated. The release workflow
  (`.github/workflows/release.yml`) runs end-to-end with no
  skipped steps.
- v0.1.0 tag pushed → workflow green in 1m41s on the second
  attempt (first attempt failed at notarization; see Lessons).

### Lessons learned (v0.1.0 ship)

- **`Sparkle.framework/Versions/B/Autoupdate` was missing from
  `SPARKLE_NESTED`.** It's a bare Mach-O sibling of the framework's
  main `Sparkle` binary, not a bundle, which is why it slipped
  past the inside-out signing pass. The notarytool log called it
  out cleanly: "The binary is not signed with a valid Developer ID
  certificate" + "The signature does not include a secure
  timestamp" for both arm64 and x86_64 slices. Fix: add the path
  to the array. Documented in `docs/RELEASING.md` post-mortem
  section so a future Sparkle version bump prompts a re-walk of
  `Versions/B/`.
- **`xcrun notarytool log <id>` is the must-have diagnostic.** A
  notary submission status of `Invalid` says nothing useful on its
  own; the JSON log lists exactly which path/architecture failed
  and why. First thing to run on any failure.
- **Double-clicking a `.cer` to install can hit `errSecKeychainItemNoAccess
  -25294`** if Keychain Access has the iCloud keychain selected
  in the sidebar at install time. `security import …
  developerID_application.cer -k ~/Library/Keychains/login.keychain-db`
  bypasses the GUI ambiguity entirely.
- **Markdown-aware chat clients autolink emails inside code
  blocks.** Pasting `gh secret set APPLE_ID --body 'you@example.com'`
  back through chat → terminal yielded
  `'[you@example.com](mailto:you@example.com)'` as the literal
  Secret value. Twice. Fix is to type the email directly into the
  terminal, or use `gh secret set NAME` with no `--body` so it
  reads from a `?` prompt. Captured in the post-mortem because
  it'll happen to anyone scripting Apple-account Secrets via chat.
- **Notarization is the moment Apple actually inspects the
  bundle.** Ad-hoc dev builds happily ignore signing miss-matches
  that hard-fail under notary. Plan for at least one tag-fail-fix
  cycle on the first signed release and don't pre-publish the
  draft until smoke-tested.

### Hardening done concurrently with v0.1.0

To make a recurrence less likely:

- `Updater.shouldEnable(bundleIdentifier:publicKey:)` — the
  build-time placeholder gate is now a pure function on `Updater`
  with `UpdaterGatingTests` covering all six branches. Previously
  inline in `AppDelegate.applicationDidFinishLaunching`,
  un-testable. A placeholder slipping into a release tag would
  pop "Unable to Check For Updates" at every user; this catches
  it in CI.
- `.github/workflows/test.yml` — runs `swift test` on every PR
  and on every push to `main`. Cheap fast feedback so a
  regression doesn't have to wait for a release tag to surface.
- `Package.swift` Sparkle pin tightened from `from: "2.6.0"`
  (allows up to <3.0) to `.upToNextMinor(from: "2.9.0")` (allows
  2.9.x patches only). New minor needs a deliberate bump and a
  fresh walk of `Versions/B/` to confirm no new nested helpers.
- `docs/RELEASING.md` post-mortem section captures the four
  lessons above + the diagnostic incantations.

### Pending after v0.1.0 (small)

- Smoke test the published v0.1.0 `.app.zip` end-to-end on a
  fresh install (queued for morning of 2026-05-04).
- Tag v0.1.1 with a one-line README change to exercise Sparkle
  auto-update from a v0.1.0 install.
- (Once Sparkle bumps to 2.10/3.0) walk `Sparkle.framework/Versions/B/`,
  update `SPARKLE_NESTED`, do a `v0.0.0-dryrun` tag.

### Pending after v0.1.0 (larger, deferred)

- AppDelegate is 577 lines. Lots of small responsibilities live
  there: engine boot, Sparkle gate, login-item apply, welcome
  state, profile-edit session lifecycle. A natural break is
  `EngineBootManager` + `EditingSessionManager` + leaving
  AppDelegate as the SwiftUI scene wiring + lifecycle. Not
  blocking anything; the file is dense but understandable.
- Homebrew-cask distribution path (still on the v2 list per
  `docs/RELEASING.md`).

---

## Menu bar profile-icon toggle (2026-05-03)

Added an opt-in setting that swaps the menu bar's `pills.fill` glyph
for the active profile's SF Symbol. Default off so the product's
brand glyph stays the out-of-the-box look; users who want the menu
bar to track location flip the toggle in Settings → General →
Behavior ("Show current profile icon in the menu bar").

Implementation reused existing pieces end-to-end:

- `SettingsStore` — new `showProfileIconInMenuBar` Bool with the
  same `@Published`/`didSet`/UserDefaults pattern as the other
  toggles. Default decoded with `(object(forKey:) as? Bool) ?? false`
  so "never set" stays distinct from "explicitly off".
- `AppDelegate` — one-line passthrough mirror so `MenuLabelView`
  re-renders via the existing `objectWillChange` republish.
- `MenuLabelView` — new private `menuBarIcon` computed var routes
  through `ProfileIcon.effectiveSymbol(for:override:)`, the same
  resolver the "Switch to" submenu and Profiles list already use.
  Falls back to `Theme.Symbol.appIcon` when the toggle is off, when
  no active profile is known yet (fresh launch pre-evaluation), or
  when the active slug isn't found in `availableProfiles`.
- The unknown-location branch is intentionally untouched — when the
  user is at a new dock there's no active profile to represent, so
  the `questionmark.circle` + "New location" treatment stays the
  right signal regardless of toggle state.

No new types, no new files. Total diff: ~25 net lines across four
files.

---

## About dialog refresh (2026-05-03)

Stripped the "fiddling" framing out of the About dialog and rebuilt
it around the four things that actually matter at the About moment:
app icon, app name, version, an update affordance, and the existing
"Show welcome again" link.

What got cut:

- `Theme.Copy.tagline` ("Stop fiddling with mic, speakers, and webcam.")
- The italic "Made to stop the fiddling." line.
- The two-line description block ("Lives quietly in your menu bar / Watches your USB ports / Picks the right defaults.").
- The intervening Divider.

What got added:

- A bordered `Check for Updates` button wired to the existing
  `delegate.checkForUpdates()` Sparkle pass-through, so the same
  update path Advanced → Check for Updates… uses is now reachable
  from About too.
- A one-shot SwiftUI confetti burst overlaid on the dialog. Hand-
  rolled, no SPM dep — 36 particles (Circle / Capsule / `pills.fill`
  brand-glyph wink) with random color, size, drift, spin, and fall
  duration, each animated by a single per-particle `@State` flipped
  on appear. The whole overlay unmounts after 2.6 s via `.task` +
  `showConfetti = false` so nothing keeps ticking once the burst
  finishes. Palette uses system colors (`.accentColor`, `.yellow`,
  `.pink`, `.green`, `.blue`, `.orange`) so it inherits the user's
  macOS accent and stays plain-native.

Frame shrunk 360 × 460 → 360 × 340. `Theme.Copy.tagline` is still
defined; it just isn't used by the About dialog anymore.

---

## Refined-pills icon + menu bar symbol picker (2026-05-04)

Two related polish moves on the visual identity:

**Icon redesign.** Replaced the SF-Symbol-driven `pills.fill`
artwork with a hand-drawn pharmaceutical capsule on a cool-charcoal
gradient squircle. The dual-pill SF symbol read as cartoony /
medicine-cabinet — the new mark is a single capsule with a near-
white cap, soft warm-gray body, thin seam at the meeting point, and
a glassy top-edge highlight, tilted ~25° down-to-the-right. Same
"system utility" register as Activity Monitor / Console — preserves
the pills metaphor without the kitsch.

The drawing lives in `Sources/AVPainRelieverApp/AppIcon.swift` (no
SF symbol reference any more — fully decoupled from
`Theme.Symbol.appIcon`). `Resources/AppIcon.icns` is regenerated
from the same drawing via a new `scripts/regen-icon.sh` pipeline:

1. `scripts/render-app-icon.swift` — standalone Swift script that
   duplicates the drawing routine and writes a 1024×1024 PNG.
   Duplication is deliberate; ~80 lines of Core Graphics and the
   regen script is the only consumer, so a second SPM target would
   be overkill. Comment in both files notes the keep-in-sync
   requirement.
2. `sips` downscales to every size `iconutil` expects.
3. `iconutil -c icns` packs the iconset.

`docs/RELEASING.md` documents the regen step.

**Menu bar symbol picker.** New Settings → General → Behavior row
"Menu bar icon" with a popover-bound 6-column grid of ~12 curated
SF symbols (`MenuBarIcon.catalog`). Wired through:

- `SettingsStore.menuBarIconSymbol: String` (default
  `MenuBarIcon.defaultSymbol` = `"pills.fill"` so existing installs
  see no change).
- `AppDelegate.menuBarIconSymbol` passthrough mirror.
- `MenuLabelView.menuBarIcon` reads from
  `delegate.menuBarIconSymbol` instead of the literal
  `Theme.Symbol.appIcon`.
- `MenuBarSymbolPicker` view — visual sibling of
  `IconPickerView` (same tile size, same selection-highlight). Kept
  separate rather than generalising IconPickerView because the
  wizard picker has an "Auto" affordance keyed to a profile slug
  that doesn't translate.

Per-profile icon override (existing
`showProfileIconInMenuBar` toggle) still wins when a profile is
active. The picker controls the *fallback* symbol.

`Theme.Symbol.appIcon` left as the documented brand-glyph constant
for any future caller that wants "the original."

---

## V2 plan: native virtual camera (CMIO Camera Extension)

**Status:** planning, 2026-05-04. Decisions captured below; no code
yet. This section is the canonical record for the V2 work — update it
as the design evolves and as milestones land.

### Why this, why now

Today's app sets `AVCaptureDevice.userPreferredCamera`, which covers
FaceTime and browsers (Safari/Chrome `getUserMedia`) automatically.
It does **not** cover Zoom, Slack, or Teams — those apps store their
own camera selection and ignore the system preference. There is no
public API to change Zoom's selection from the outside.

The earlier plan was to recommend OBS Virtual Camera as the bridge:
configure OBS once with a per-scene camera, point Zoom/Slack at "OBS
Virtual Camera," and let OBS scene-switching handle the rest. That
plan was retired on 2026-05-04 — OBS is a third-party dependency
and the project mandate is "self-contained" (no Hammerspoon, no OBS,
neither in the UI nor in the docs).

The V2 path: ship a native macOS Camera Extension (CoreMedia I/O,
macOS 13+) bundled inside the app. Zoom/Slack/Teams see "AV Pain
Reliever" in their picker, the user selects it once, and from then
on the active profile drives what frames flow through. CMIO Camera
Extensions are the modern macOS API used by mmhmm, Hand Mirror,
Detail, Camo, Ecamm Live, and OBS itself (since OBS migrated off the
deprecated DAL plug-in path in 2022).

### Decisions (settled 2026-05-04)

- **Activation is opt-in.** Default install behaves exactly like
  v0.1.x — no system-extension prompt, no extra entry in Zoom's
  picker. Users enable the virtual camera from a Settings toggle,
  which triggers the system-extension approval flow at that moment.
  Rationale: most users may already be happy with FaceTime/browser
  coverage; an opt-in toggle respects that and keeps first-launch
  identical.
- **On profile switch, hold last frame.** The virtual camera holds
  the last good frame from the outgoing source for ~500 ms while
  the new source initializes, then cuts. Polite to viewers in a
  live call, no jarring black flash. Exact hold duration is a tuning
  knob, not a design decision.
- **macOS 13+ floor for v0.2.0.** This is a modern app; CMIO Camera
  Extensions need 13+. Users still on macOS 12 stay on the v0.1.x
  Sparkle channel and miss the feature, which is fine.
- **Picker name: "AV Pain Reliever".** Short, matches the app name,
  reads correctly in narrow Zoom/Slack pickers. No "Camera" suffix,
  no "Virtual" parenthetical.
- **Source mirrors the active profile.** The virtual camera vends
  frames from whatever camera the current profile says is the
  preferred camera. No separate "virtual camera source" config —
  one less knob, and it matches the user mental model ("Zoom should
  finally follow my profiles").
- **Apple entitlement request happens after a working prototype.**
  Build first on user's machine in `systemextensionsctl developer
  on` mode, prove the architecture end-to-end, then submit the
  request. Risk: turnaround is days to weeks, so we may end up with
  a finished feature waiting on Apple. Acceptable — the existing
  release line keeps shipping in parallel.

### Architecture

Three pieces, separated by process boundary:

1. **Main app (existing process).** Owns USB watching, profile
   resolution, settings, the menu-bar UI. Adds a new
   `VirtualCameraController` protocol with two implementations:
   - `NoopVirtualCameraController` — does nothing. Used in the
     default v0.1.x build. Lets the existing release pipeline
     continue untouched.
   - `CMIOVirtualCameraController` — captures from the active
     profile's source camera using AVFoundation, encodes each
     frame as an IOSurface, and pushes it to the extension over
     XPC. Receives extension-side status (active client count,
     errors).
2. **Camera Extension (`AVPainRelieverCameraExtension.systemextension`).**
   A `CMIOExtensionProvider` host with one `CMIOExtensionDevice`
   ("AV Pain Reliever") and one `CMIOExtensionStream`. **Pure
   relay** — receives `IOSurface` frames from the host app over
   XPC, wraps each in a `CMSampleBuffer`, sends downstream via
   `stream.send(...)`. Handles hold-last-frame on source-camera
   switch (i.e., when the host app pauses the XPC frame feed).
3. **XPC pipe.** Both frames and commands flow over the same XPC
   connection. Frames piggyback on `IOSurface` references (zero-
   copy across the process boundary). Commands are simple
   messages: `setSourceCamera(uniqueID:)`, `pause()`, `resume()`,
   `currentStatus()`.

**The extension never touches AVFoundation or the physical camera
hardware.** This is forced by an M2 lesson learned the hard way
(see "Why the extension can't capture" below): a CMIO Camera
Extension that calls `AVCaptureSession` enumerates devices through
the very CMIO subsystem it's plugged into, sees itself in the
list, and creates an IOKit-level deadlock that wedges every camera
app on the machine. OBS, mmhmm, Hand Mirror, Camo all use the
host-app-captures + XPC-to-extension pattern for the same reason.

`ProfileApplier` gains one new step: after setting
`userPreferredCamera`, also tell the `VirtualCameraController` to
switch its source. With the no-op implementation this is free; with
the CMIO implementation it forwards over XPC.

The extension does not own any audio. The existing `AudioController`
path is unchanged — audio still flows through the system default
device, which Zoom/Slack pick up via "Same as System" as today.

### Branch + build setup

- **Branch:** `feature/virtual-camera`, cut off `main` at whatever
  commit is current when work starts. Long-lived. `main` continues
  to ship `v0.1.x` patch releases independently.
- **Project structure shift:** A `.systemextension` target requires
  an actual Xcode bundle, which Swift Package Manager can't build
  alone. Add a thin `AVPainReliever.xcodeproj` alongside `Package.swift`
  that references the existing SPM packages and adds two targets:
  the Camera Extension and an XPC service. SPM development for the
  main app continues unchanged — `swift build`, `swift test`, the
  current scripts. The Xcode project is only invoked for v0.2.0
  release builds.
- **Build configuration:** Two configs — `Release` (existing,
  no extension embedded, no camera-extension entitlement, ships as
  v0.1.x) and `ReleaseWithVirtualCamera` (embeds the extension,
  declares the entitlement, ships as v0.2.0+). The
  `VirtualCameraController` injection is selected by build setting
  so the no-op build genuinely doesn't link the CMIO code path.
- **CI:** Existing GitHub Actions release workflow keeps working as-
  is for v0.1.x. A second workflow (or a parameter on the existing
  one) handles v0.2.0+ builds via xcodebuild. Notarization stays the
  same Developer ID flow; the only delta is the entitled
  provisioning profile after Apple approves the entitlement.

### Milestones

Rough ordering, not a timeline (this is a side project; whenever
each lands, it lands). Re-numbered after the M2 retreat (see "Why
the extension can't capture"):

1. **M1 — Project scaffold.** ~~`AVPainReliever.xcodeproj`~~ kept
   the SPM + shell-script build pattern. Empty Camera Extension
   target that activates and shows up in Zoom but vends a black
   frame. Goal: prove the activation/signing/embedding plumbing
   works. **SHIPPED 2026-05-04.**
2. **M2 — Host-side capture + CMIO sink-stream pipe.** SHIPPED
   2026-05-04. Host app opens an `AVCaptureSession` against the
   built-in webcam, opens AV Pain Reliever's sink stream via raw
   CMIO C API, and enqueues each captured `CMSampleBuffer` into
   the sink's `CMSimpleQueue`. The kernel passes the underlying
   IOSurfaces across the process boundary. Extension consumes
   from the sink via `stream.consumeSampleBuffer(from:)` on a
   timer at 3× framerate and forwards each consumed frame to the
   source stream that AVCapture clients (Zoom, Photo Booth, etc.)
   read. Initial XPC implementation was abandoned — see "Why XPC
   didn't work for the frame pipe" below.
3. **M3 — Source switching + hold-last-frame.** SHIPPED
   2026-05-04. Engine layer drives the host's running
   `AVCaptureSession` directly through a new
   `VirtualCameraSourceController` adapter — no XPC (M2's
   architecture pivot eliminated the XPC service entirely). The
   active profile's `camera` field becomes both the system
   `userPreferredCamera` (existing behavior) AND the virtual
   camera's source (new). Extension holds the most recent frame
   and re-emits it at 30 fps when the sink temporarily dries up,
   covering the ~500 ms input-swap window so Zoom doesn't see a
   freeze.
4. **M4 — Settings UI + opt-in toggle.** SHIPPED 2026-05-04.
   `SettingsStore.virtualCameraEnabled` (default off).
   `VirtualCameraActivator` refactored from a static one-shot
   into a stateful `ObservableObject` with state machine
   (`.off` / `.activating` / `.needsApproval` / `.on` /
   `.failed` / `.requiresRelaunch`) and a `relaunch()` action.
   Camera tab in Settings shows toggle + live status row +
   contextual button (Open Login Items & Extensions for
   approval, Restart AV Pain Reliever for the in-session
   re-enable quirk). `AVPR_ACTIVATE_VIRTUAL_CAMERA=1` kept as a
   debug override that locks the toggle for the launch and shows
   a "Debug override" badge.
5. **M5 — Release readiness.** SHIPPED 2026-05-04. Release
   workflow now picks the right build script per tag (v0.1.x →
   make-app.sh, v0.2.x+ → make-app-with-virtual-camera.sh) so
   the v0.1.x release line stays unblocked. New
   `MACOS_PROVISIONING_PROFILE` GitHub Secret carries the
   profile that the extension needs for activation outside
   developer mode. README has a "Virtual camera" section
   explaining the feature install-first; Settings UI's Camera
   tab is the discovery path. Sparkle/extension upgrade-replace
   verification is documented as an end-to-end test plan to be
   run with the v0.2.0 → v0.2.0.1 cycle in M6 — can't be
   shippable-verified until at least one v0.2.x release exists
   on the appcast.
6. **M6 — Tag v0.2.0.** SHIPPED 2026-05-04. CI workflow ran
   clean (1m48s) using `make-app-with-virtual-camera.sh`,
   notarized + stapled both bundles, signed appcast item
   appended to main, draft published. v0.2.0 live at
   https://github.com/superic/av-pain-reliever/releases/tag/v0.2.0.
   The Sparkle upgrade-replace verification (v0.2.0 → v0.2.0.1)
   is its own follow-up — separate small patch release whenever
   we have the next reason to cut one.

### Deferred / open items

- **Hold-last-frame exact duration.** Resolved in M3: there is no
  fixed duration — the extension repeats the cached frame at 30 fps
  for as long as the sink stays empty AND a client is watching.
  Verified on a manual switch from `home-office` → `laptop` on
  2026-05-04: cold-start gap on first client connect was covered by
  one held emit before fresh frames took over.
- **Behavior when no source camera is available** (profile says
  camera X, X is unplugged). Currently logged as
  `virtual camera source 'X' not found — skipping`; the running
  session keeps the previous source and the virtual camera continues
  to deliver that. No black frame, no placeholder. Revisit if the
  user reports it as confusing in practice.
- **Format negotiation for non-FaceTime cameras.** Resolved as
  part of M3 (2026-05-04). Diagnosis: forced
  `kCVPixelFormatType_32BGRA` at 1280×720 in the host's
  `videoSettings` works for FaceTime HD but silently dropped
  every frame from the user's HDMI to U3 capture card
  (vendor 0x1e4e / product 0x701f) which natively delivers
  `420v` (NV12) at 1920×1080. Fix: host accepts the device's
  native format; `CMIOSinkWriter` runs each frame through
  `VTPixelTransferSession` to convert to 1280×720 BGRA before
  enqueueing. `CVPixelBufferPool` recycles the destination
  buffers so steady-state capture doesn't churn allocations.
  Verified end-to-end on both `home-office` (HDMI capture, NV12
  1080p source path) and `laptop` (FaceTime HD, BGRA 720p
  passthrough path) profiles.
- **Resolution / format negotiation.** Match source for V2; revisit
  if Zoom complains about specific formats.
- **Uninstall flow.** Resolved in M4 (2026-05-04). The Settings
  toggle calls `OSSystemExtensionRequest.deactivationRequest` on
  flip-off and tears down the host capture pipeline. Surfaces in
  System Settings → Login Items & Extensions for true uninstall.
- **In-session toggle off → on quirk.** Surfaced and partially
  resolved in M4 (2026-05-04). `OSSystemExtensionRequest.deactivationRequest`
  doesn't actually stop the running extension process — it
  queues `[terminated waiting to uninstall on reboot]` while the
  extension stays alive and visible to AVCapture clients. Toggle
  back on in the same host process can't get fresh CMIO state for
  the device (the host's CMIO context already saw the device as
  "going away") so the pipeline produces a black feed. Detected
  via the activator's `deactivatedThisSession` flag; toggle-on
  routes to `.requiresRelaunch` and the Settings UI surfaces a
  "Restart AV Pain Reliever" button that quits + relaunches the
  host (fresh process → fresh CMIO context → device found
  immediately, same path that works on every cold launch). Not
  pretty, but mac OS doesn't expose a userspace API to tear down
  an extension and re-attach in the same process.
- **Sparkle + extension replacement edge cases.** Specifically the
  "user has Zoom open with the virtual camera active when v0.2.1
  installs" case. Investigate in M6.
- **Entitlement request body.** Draft once M4 lands so we can
  describe a working feature, not a hypothetical.

### M1 — project scaffold (SHIPPED 2026-05-04)

Branch: `feature/virtual-camera`. Approach: extend the existing
SPM + shell-script build pattern rather than introduce an Xcode
project. A `.systemextension` is just a different bundle wrapper
around a Swift binary; the existing `make-app.sh` already proves
hand-rolled bundle assembly works for this project.

What landed:

- `Sources/AVPainRelieverCameraExtension/` — four Swift files:
  `main.swift` (entry point), `CameraExtensionProvider.swift`
  (CMIOExtensionProviderSource), `CameraExtensionDevice.swift`
  (CMIOExtensionDeviceSource — single device, stable UUID),
  `CameraExtensionStream.swift` (CMIOExtensionStreamSource —
  vends 1280×720 BGRA black frames at 30 fps via a
  `DispatchSourceTimer` + `CVPixelBufferPool`).
- `Package.swift` — added
  `AVPainRelieverCameraExtension` as an executable target. No
  dependency on `AVPainReliever` or `AVPainRelieverApp`; clean
  process boundary from the start.
- `Resources/AVPainRelieverCameraExtension-Info.plist` — minimal
  bundle metadata (`CFBundlePackageType = SYSX`, child bundle ID
  `com.ericwillis.avpainreliever.CameraExtension`).
- `Resources/AVPainRelieverCameraExtension.entitlements` —
  sandboxed (`com.apple.security.app-sandbox = true`).
- `Resources/AVPainReliever-WithVirtualCamera.entitlements` —
  v0.2.0 host-app entitlements adding
  `com.apple.developer.system-extension.install`. The default
  `Resources/AVPainReliever.entitlements` is unchanged so the
  v0.1.x signing pipeline is byte-for-byte the same.
- `scripts/make-app-with-virtual-camera.sh` — parallel-track
  build script. Runs `swift build` for both products, assembles
  both bundles, embeds the extension at
  `Contents/Library/SystemExtensions/`, signs inside-out (Sparkle
  nested → Sparkle.framework → Camera Extension → host app).
- `Sources/AVPainRelieverApp/VirtualCameraActivator.swift` +
  `AppDelegate.applicationDidFinishLaunching` hook — env-var-gated
  (`AVPR_ACTIVATE_VIRTUAL_CAMERA=1`) `OSSystemExtensionRequest`
  activation. No-op on v0.1.x builds (entitlement absent → request
  fails harmlessly). M4 will replace this with a real Settings
  toggle.
- `docs/VIRTUAL_CAMERA_DEV.md` — local-test recipe:
  `systemextensionsctl developer on`, build, ditto into
  `/Applications`, env-var-launch, verify in Zoom, iteration loop,
  uninstall, common failure modes.

What's deliberately not done: no main-app integration with
`ProfileApplier`, no source-camera switching, no XPC service yet.
Those are M2 / M3 / M4. M1's only job is to prove the
activation/embedding/signing plumbing works.

Verification (2026-05-04, second attempt): activated successfully
end-to-end. `systemextensionsctl list` reports `[activated enabled]`,
the extension process is alive under `_cmiodalassistants`, the host
app's activation request returns success, and "AV Pain Reliever"
appears in Zoom's camera picker showing the black 1280×720 frame at
30 fps. M1 success criteria met.

### M1 lessons (gotchas the original scaffold missed)

The first build attempt failed activation because the original
plumbing was missing several non-obvious requirements. Each of
these surfaced as a distinct error from `sysextd`, requiring
re-signing and re-installing to fix. Documenting them so future
milestones don't relearn the same things:

1. **`open` strips environment variables.** The `AVPR_ACTIVATE_VIRTUAL_CAMERA=1`
   env var has to be passed via `open --env AVPR_ACTIVATE_VIRTUAL_CAMERA=1`,
   not the shell-prefix form, because `open` hands off to `launchd`
   which doesn't inherit the calling shell's environment. The
   shell-prefix form sets the var only for the `open` command
   itself, not for the launched app.
2. **Notarization is required for system extension activation,
   even with valid Developer ID signing.** `sysextd` queries the
   notary daemon during validation; an unnotarized bundle gets
   `bundle code signature is not valid - does not satisfy
   requirement: -67050`. The `make-app-with-virtual-camera.sh`
   script grew a notarization step gated by
   `NOTARIZE_KEYCHAIN_PROFILE=avpain-notary` (using the existing
   v0.1.x notarytool keychain profile). One round trip is ~30s; a
   `SKIP_NOTARIZE` style escape hatch is a future-niceness if
   non-system-extension iteration speed becomes a concern.
3. **The Info.plist `CMIOExtension` dict is the type marker.**
   Without it, `sysextd` reports "system extension does not appear
   to belong to any extension categories" — the daemon cycles
   through DriverKit / NetworkExtension / EndpointSecurity checks,
   finds no marker for any of them, and rejects the bundle. The
   correct shape is `<dict><key>CMIOExtensionMachServiceName</key>
   <string>{TEAMID}.{appgroup-id}.{suffix}</string></dict>`. We
   substitute `__TEAM_ID__` at build time, parsed out of
   `MAC_CERT_NAME`.
4. **Mach service name must be prefixed by an App Group declared
   in the extension's entitlements.** The error from `sysextd` is
   "invalid mach service name or is not signed, the value must be
   prefixed with one of the App Groups in the entitlement." This
   meant registering an App Group at developer.apple.com
   (`group.com.ericwillis.avpainreliever`), enabling the App
   Groups capability on both App IDs (host + extension),
   regenerating the Developer ID provisioning profile, and adding
   `com.apple.security.application-groups` to both entitlements
   files with the team-prefixed form
   (`HLH4LEWS9S.group.com.ericwillis.avpainreliever`).
5. **AMFI's entitlement parser doesn't tolerate XML comments.**
   The entitlement plists need to be plain key/value dicts; even
   well-formed `<!-- ... -->` comments fail signing with "Failed
   to parse entitlements: AMFIUnserializeXML: syntax error."
   Documentation has to live in adjacent files, not inline.
6. **Final activation needs explicit user approval in System
   Settings.** `[activated waiting for user]` is the
   intermediate state; the user opens **System Settings → General
   → Login Items & Extensions → Camera Extensions** and toggles
   the extension on. State then transitions to
   `[activated enabled]`.

The dev workflow (`docs/VIRTUAL_CAMERA_DEV.md`) was rewritten in a
follow-up commit to reflect the actual recipe instead of the
ad-hoc + developer-mode + SIP-off path I originally documented.

### Why the extension can't capture (M2 attempt #1, 2026-05-04)

First M2 attempt put an `AVCaptureSession` inside the Camera
Extension, opened against the built-in webcam, and forwarded the
captured `CMSampleBuffer`s to `stream.send(...)`. The extension
compiled, signed, notarized, and activated cleanly. But as soon as
any client (Photo Booth, Zoom) selected the AV Pain Reliever
camera, the entire camera pipeline on the machine wedged — Photo
Booth froze hard, requiring force-quit and (sometimes) `sudo
killall VDCAssistant` to unwedge.

Diagnosis from the extension's logs: `AVCaptureSession` triggered
`AVCaptureDALDevice _refreshPreferredCameraProperties` and full
device-list enumeration *inside* the extension process. CMIO holds
the system-wide camera-device list while waiting for the
extension's reply on `startStream`; concurrently the extension was
asking AVFoundation to enumerate cameras, which routes back through
CMIO, which sees our extension as one of the devices, which calls
back into the same path. IOKit deadlock — every camera app gets
queued behind it.

Architectural rule that fell out: **a CMIO Camera Extension cannot
use AVFoundation.** Frames have to enter the extension from the
outside, via XPC from the host app or a sibling helper. OBS,
mmhmm, Hand Mirror, Camo, Ecamm Live all use the host-app-captures
+ XPC-to-extension pattern.

This invalidates the original M2/M3 split (where M2 = "frames in
the extension" and M3 = "XPC for commands"). Re-architected:
M2 now means host-side capture + XPC frame pipe; source switching
becomes a one-line change in M3.

Concrete changes after the rollback:
- `CameraExtensionStream.swift` reverted to the M1 black-frame
  timer (no AVFoundation in the extension, ever).
- Camera entitlement (`com.apple.security.device.camera`) and
  `NSCameraUsageDescription` removed from the extension —
  permanently. The extension doesn't need either.
- `Resources/AVPainRelieverCameraExtension.entitlements` keeps
  `com.apple.security.app-sandbox` and the App Group; nothing
  else.
- M2 plan rewritten in milestones list above.

### M2 — host-side capture + CMIO sink (SHIPPED 2026-05-04)

End-to-end working: host captures from the built-in FaceTime HD
camera at 1280×720 BGRA, writes frames into the extension's sink
stream via CMIO's `CMSimpleQueueEnqueue`, the extension drains
the sink and forwards to the source stream that Zoom and Photo
Booth read. Live webcam feed flows through the AV Pain Reliever
virtual camera with no perceptible latency.

Architecture (matches OBS's `mac-virtualcam` pattern,
referenced for design):

- **Extension**: declares two streams on its single device — a
  `.source` stream (AVCapture clients read this) and a `.sink`
  stream (host writes here). Owns no AVFoundation. Runs a
  consume timer at 90 Hz that drains the sink and calls
  `stream.send(...)` on the source when there's an active
  consumer (`streamingCounter > 0`). See
  `Sources/AVPainRelieverCameraExtension/`:
  - `CameraExtensionStream.swift` — source side, just tracks
    streaming counter.
  - `CameraExtensionStreamSink.swift` — sink side, captures the
    `CMIOExtensionClient` in `authorizedToStartStream`.
  - `CameraExtensionDevice.swift` — owns both streams + the
    consume loop.

- **Host**: opens AV Pain Reliever as a CMIO consumer, queries
  each stream's `kCMIOStreamPropertyDirection` to find the sink
  (NOT the index 1 trick — direction-property check is robust
  against ID ordering changes), gets the buffer queue via
  `CMIOStreamCopyBufferQueue`, calls `CMIODeviceStartStream`,
  then enqueues each captured frame via `CMSimpleQueueEnqueue`.
  See `Sources/AVPainRelieverApp/`:
  - `CameraCaptureSession.swift` — AVFoundation capture against
    built-in camera (no recursion since host is a normal app).
  - `CMIOSinkWriter.swift` — raw CMIO sink-write path.

### Why XPC didn't work for the frame pipe

First attempt put NSXPCConnection between host and extension on
a Mach service named `HLH4LEWS9S.group.com.ericwillis.avpainreliever.framepipe`.
The XPC connection failed with `failed to do a bootstrap look-up:
xpc_error=[3: No such process]`. Root cause:
`NSXPCListener(machServiceName:)` only attaches to launchd-
registered services — system extensions don't have launchd
plists for their custom Mach names, so the listener never
registered the service and clients couldn't find it.

The OBS-style sink-stream approach sidesteps this entirely:
CMIO already has cross-process IOSurface plumbing built in,
and using the second stream as a sink reuses that plumbing for
free. No Mach services to register, no XPC code to maintain.

### M3 — profile-driven source switching + hold-last-frame (SHIPPED 2026-05-04)

End-to-end: changing the active profile (manually or by docking
to a known location) swaps the virtual camera's source camera in
the running `AVCaptureSession`, and the extension covers the
~500 ms warm-up gap by re-emitting the last good frame at 30 fps.
Zoom stays connected; the picture freezes for ~500 ms then comes
alive on the new source. No call drop.

Architecture (no XPC — M2's pivot eliminated it permanently):

- **Engine layer** (`Sources/AVPainReliever/Adapters/CameraController.swift`):
  - New `VirtualCameraSourceController` protocol with a single
    `setSource(named:) -> CameraApplyResult` method. Mirrors the
    existing `CameraController` shape so `ProfileApplier` handles
    the two adapters symmetrically.
  - `ProfileApplier` accepts an optional
    `virtualCameraSource:`. When `profile.camera` is set it
    drives BOTH the system `userPreferredCamera` (legacy
    behavior, for AVFoundation-modern apps) AND the virtual
    camera's source (new, for Zoom/Slack/Teams that ignore the
    system preference but follow the AV Pain Reliever device).
  - Nil injection = silent no-op. Production wires it only when
    the env-var-gated activator booted the host capture pipeline;
    v0.1.x and "didn't ask for virtual camera" launches inject
    nil with no behavior change.

- **Host app** (`Sources/AVPainRelieverApp/CameraCaptureSession.swift`):
  - Refactored away from the hardcoded `.builtInWideAngleCamera`
    lookup. Initial source is picked from the same fallback chain
    `AVFoundationCameraController.currentPreferredName` uses
    (`userPreferredCamera` → `systemPreferredCamera` → first
    discovered) so the first frames match what a fresh AVCapture
    client would naturally see.
  - New `switchSource(toLocalizedName:)` runs on the capture
    queue, looks up the device by `localizedName` (matches the
    profile's camera field), and swaps inputs inside a
    `beginConfiguration` / `commitConfiguration` block. The
    session keeps running across the swap — no
    `stopRunning`/`startRunning` cycle.
  - `videoSettings` no longer forces a pixel format or
    dimensions; the device delivers its native format
    (FaceTime HD ships BGRA 720p, the user's HDMI capture card
    ships NV12 1080p, etc) and the conversion happens
    downstream in `CMIOSinkWriter`. M2's forced settings worked
    for FaceTime but silently dropped every frame from the
    HDMI capture card.
  - Conforms to `VirtualCameraSourceController`. The static
    `VirtualCameraActivator.virtualCameraSource` accessor exposes
    the running session to `AppDelegate.buildEngine` so the
    `ProfileApplier` gets the live adapter.
  - `applicationDidFinishLaunching` order changed:
    `VirtualCameraActivator.activateIfRequested()` now runs
    BEFORE `bootEngine()` so the engine's first
    evaluate-and-apply pass finds a live source to drive.

- **Host's CMIO sink writer** (`Sources/AVPainRelieverApp/CMIOSinkWriter.swift`):
  - Added a `VTPixelTransferSession` + `CVPixelBufferPool` pair
    that converts every incoming frame to 1280×720 BGRA before
    `CMSimpleQueueEnqueue`. Hardware-accelerated where the GPU
    supports it; the pool recycles destination buffers so
    steady-state capture allocates nothing per frame.
  - Fast path for inputs that already match (FaceTime HD,
    Continuity Camera) — passthrough, zero copy.
  - Format description is re-derived per pool buffer (cached by
    `CVPixelBuffer` pointer). Sharing one description across
    different source frames gets rejected with -12743 because
    VT attaches source-derived colorspace metadata to the
    destination, and `CMSampleBufferCreateForImageBuffer`
    validates strictly.
  - `Host frame format: <fourcc> <w>x<h> — convert+scale|passthrough`
    is logged once per (format, dimensions) signature change
    so a profile switch is visible without flooding the log.

- **Extension** (`Sources/AVPainRelieverCameraExtension/CameraExtensionDevice.swift`):
  - Caches the most recent `(CVPixelBuffer, CMFormatDescription)`
    pair from the sink. On each consume tick that yields nil and
    the source has at least one watcher, mints a fresh
    `CMSampleBuffer` over the cached pixel buffer with the
    current host time and sends it through the source stream.
  - Held emissions are rate-limited to ~30 fps (matches the
    source's declared `frameDuration`) so the 90 Hz consume
    timer doesn't burst the source at 3× framerate.
  - Holding the underlying `CVPixelBuffer` (not the parent
    `CMSampleBuffer`) lets each repeat carry a fresh PTS without
    AVCapture clients seeing duplicate timestamps.

Wiring summary:

```
profile.camera = "Logitech BRIO"
    │
    ▼
ProfileApplier.applyVirtualCameraSource("Logitech BRIO")
    │
    ▼
CameraCaptureSession.setSource(named:)
    │
    ▼  (capture queue)
session.beginConfiguration()
remove old input
add new AVCaptureDeviceInput(BRIO)
session.commitConfiguration()
    │
    ▼  (~500 ms while BRIO warms up — sink dry)
extension consumeOne() returns nil
    │
    ▼
extension re-emits last cached frame at 30 fps to source
    │
    ▼
Zoom keeps seeing 30 fps — no freeze, no drop
```

### M4 — Settings UI + opt-in toggle (SHIPPED 2026-05-04)

The Camera Extension is now opt-in via a real Settings toggle
instead of the env-var-only path used in M1–M3. Default off, so
fresh installs see no system extension activity until the user
turns it on. The env var (`AVPR_ACTIVATE_VIRTUAL_CAMERA=1`) stays
as a debug affordance — it forces enable on launch regardless of
the persisted setting and shows a "Debug override" badge in the
Settings UI so the user understands why the toggle is greyed out.

Architecture:

- **`SettingsStore.virtualCameraEnabled`** — persisted `Bool`,
  default false. Same `UserDefaults` pattern as the other
  toggles. New unit test covers the default + persistence.

- **`VirtualCameraActivator` refactor** — was a static one-shot
  in M1; now an `ObservableObject` with a state machine:

  ```
  .off ──enable()──▶ .activating ──didFinishWithResult──▶ .on
   ▲ ▲                   │
   │ │                   ├─requestNeedsUserApproval──▶ .needsApproval
   │ │                   └─didFailWithError──────────▶ .failed
   │ └────disable()─────┐
   │                    │
   ┴────────────────────┘
       (deactivatedThisSession=true)
                ↓
       enable() → .requiresRelaunch
   ```

  `enable()` and `disable()` are both idempotent and log every
  transition for debugging. `relaunch()` quits + reopens the
  host bundle via `/usr/bin/open <path>` so the fresh process
  picks up the persisted toggle and gets a clean CMIO context.

- **AppDelegate wiring** — owns the activator (was static).
  Subscribes to `settings.$virtualCameraEnabled` via Combine;
  toggle changes route through `applyVirtualCameraToggle`. The
  activator is itself the `VirtualCameraSourceController`
  plumbed into `ProfileApplier` — silently no-ops when off
  (returns `.ok` without doing anything), forwards to the
  running `CameraCaptureSession` when on. No engine rebuild
  needed on toggle flip.

- **Settings UI — Camera tab** — third tab alongside General
  and Profiles. Shows the toggle, a live status row (colored
  dot + label that mirrors the activator state), and a
  contextual button: "Open Login Items & Extensions" when in
  `.needsApproval` / `.failed`, "Restart AV Pain Reliever" when
  in `.requiresRelaunch`. Footer hint adapts to the state
  (e.g. "Pick 'AV Pain Reliever' in Zoom" when on, "macOS holds
  the virtual camera in a stale state…" when restart is
  required). Footer rendered as a `Text` row inside the section
  body per the project memory's macOS-14 `Form(.grouped)`
  footer-slot convention.

### M5 — release readiness (SHIPPED 2026-05-04)

Three sub-tasks, all landed:

1. **README — virtual camera section.** New "Virtual camera
   (optional)" section between "Using the app" and "Privacy".
   Install-first, scannable, executive aesthetic preserved
   (per the README-audience memory). Calls out that Zoom /
   Slack / Teams ignore the system default and tells the user
   the four steps to enable it.

2. **CI release workflow updates.**
   `.github/workflows/release.yml` now picks the build script
   from the tag prefix: `v0.0.0-*` and `v0.1.*` keep using
   `scripts/make-app.sh`; everything else (`v0.2.*` and later)
   uses `scripts/make-app-with-virtual-camera.sh`. New
   `MACOS_PROVISIONING_PROFILE` GitHub Secret holds the
   base64-encoded provisioning profile; decoded into
   `Resources/AVPainReliever.provisionprofile` only for v0.2.x+
   runs (skipped silently on v0.1.x to keep that pipeline a
   no-op). `docs/RELEASING.md` updated to reflect the new
   secret + the script-selection logic.

3. **Sparkle / extension upgrade-replace verification —
   recipe documented; execution in M6.** Can't be properly
   verified until at least one v0.2.x release exists on the
   appcast and there's an installed Sparkle-capable client to
   upgrade FROM. The recipe lives in this section's "Upgrade-
   replace test plan" subsection below; M6 runs it for real.

### M5 — Sparkle upgrade-replace test plan (run during M6)

The macOS quirk we hit during M3/M4 dev iteration was: rebuilding
the extension binary marks the previous version
`[terminated waiting to uninstall on reboot]`, and CMIO stops
exposing the device until reboot or a Settings toggle off/on
cycle. **This test plan validates that Sparkle's normal upgrade
flow doesn't reproduce that quirk for end users**, because
Sparkle quits the running host before swapping the bundle (fresh
process for the new version, clean CMIO context).

Pre-requisites:
- v0.2.0 already released and live on the appcast.
- A Mac with v0.2.0 installed via Sparkle (not via dev build)
  and the virtual camera toggle ON for at least one launch (so
  the extension is `[activated enabled]` in `systemextensionsctl
  list`).

Test steps:
1. On the local dev machine, bump the source to a v0.2.0.1 patch
   (e.g. trivial README typo or release-notes copy edit).
2. `git tag v0.2.0.1 && git push --tags` — CI workflow runs.
3. Verify the workflow used `make-app-with-virtual-camera.sh` and
   notarization succeeded for both the host AND the embedded
   extension bundle.
4. Verify the workflow appended a new `<item>` to `appcast.xml`
   on `main` with the v0.2.0.1 enclosure URL + EdDSA signature.
5. On the test Mac (running v0.2.0): About → Check for Updates.
   Sparkle should detect v0.2.0.1, prompt, download, quit,
   replace the bundle, relaunch.
6. Verify on the test Mac after Sparkle's relaunch:
   - `systemextensionsctl list` — old v0.2.0 entry should
     transition cleanly to v0.2.0.1; the previous version may
     show as `[terminated waiting to uninstall on reboot]` for
     a moment (expected) but the new version should be
     `[activated enabled]`.
   - `system_profiler SPCameraDataType` — AV Pain Reliever
     entry still present.
   - Open Photo Booth → AV Pain Reliever → live frames flowing
     (no black screen).
   - Settings → Camera → status row shows "Active".
7. If step 6 shows black frames, that's the same-process CMIO
   stale-handle bug from M4's known issues; click the
   `Restart AV Pain Reliever` affordance in Settings → Camera
   (which already exists) to recover. If we see this, file a
   follow-up to investigate whether Sparkle's pre-upgrade quit
   is reaching the activator's deactivation path cleanly.

Failure modes worth watching for:
- Apple's notary service rejecting the embedded extension bundle
  for any reason (would surface in the workflow's "Notarize and
  staple" step).
- Sparkle's downloader / installer not preserving the embedded
  `Library/SystemExtensions/...` directory (the extension would
  be missing from the new bundle; would surface as the
  activation request failing on the test Mac's first launch
  after upgrade).

### v0.2.0 release notes (draft, ready to copy)

Paste this into the GitHub Release body when pre-creating the v0.2.0
draft release (per `docs/RELEASING.md`'s curated-notes flow). The CI
workflow renders it through GitHub's `/markdown` API and pipes the
HTML into the appcast `<description>`, so what you write here is
exactly what shows up in Sparkle's "What's New" panel for upgrading
v0.1.x users.

```markdown
## What's new

OK here's the deal. v0.2.0 is the big one. **AV Pain Reliever is now
a virtual camera.** That's right — the same app that's been quietly
swapping your audio defaults all this time can now also be the camera
that Zoom, Slack, Teams, and any other video app picks up. One
camera in their picker. One name. **AV Pain Reliever.** It streams
whatever real camera the active profile names — your built-in webcam
at the laptop, the HDMI capture at the home office, your iPhone via
Continuity at the conference room — whatever you've configured. The
profile changes, the picture follows. Money.

Here's what this fixes: Zoom, Slack, and Teams keep their *own*
camera selection that ignores the system default. So back in v0.1.x
when you docked at a new location, your microphone and speakers
would change, but Zoom would just sit there showing your laptop
webcam like nothing happened. That's amateur hour. With v0.2.0, you
pick "AV Pain Reliever" in Zoom once and you're done. Forever.

It's **off by default** — installing a virtual camera is a real thing
and we're not turning it on without your permission, that's not how
we do business. Open **Settings → Camera** and flip the toggle.
macOS will ask you to approve the extension once (System Settings →
Login Items & Extensions → Camera Extensions). After that, you're in.

A few technical things, briefly, because if you're reading this far
you probably care:

- **Hold-last-frame** during the swap. When you change profiles, the
  new camera takes a beat to warm up — about half a second. Instead
  of flashing black at your Zoom call, the virtual camera holds the
  last frame from the old camera until the new one's delivering
  frames. You see a soft pause; nobody on the call sees a glitch.
- **Format conversion** for any camera. Built-in webcams ship BGRA,
  USB capture cards ship YUV at 1080p, every device has its quirks.
  We accept whatever the camera natively delivers and convert to
  1280×720 BGRA on the fly, hardware-accelerated where possible.
  Means your weird HDMI capture card just works.
- **Profile-driven everywhere.** The same Add Profile wizard that
  picks your audio defaults now also picks the camera the virtual
  camera streams. No new config to learn — it's the same `camera =`
  field you've already been using. v0.1.x configs upgrade clean.

One known thing: if you toggle the virtual camera off and then back
on inside the same launch, macOS holds the extension in a stale
state and the feed goes black. The Settings UI catches this and
gives you a **Restart AV Pain Reliever** button that handles it. One
click, fresh process, you're back. Edge case — most folks turn it
on once and leave it. Not a deal-breaker.

That's the update. Virtual camera, profile-driven, hold-last-frame,
universal format support. v0.1.x will keep getting patch releases
in parallel for anyone who doesn't need any of this. **Money.**
```

### M2 lessons (gotchas the architecture or first attempts hit)

1. **`AVCaptureVideoDataOutput.sessionPreset` ≠ output
   dimensions.** Setting `session.sessionPreset = .hd1280x720`
   does not force the output to 1280×720 — the FaceTime HD camera
   shipped 1920×1080 frames anyway. Fix: add
   `kCVPixelBufferWidthKey`/`kCVPixelBufferHeightKey` to
   `output.videoSettings`. AVFoundation does the downscale.
2. **Pre-built `CMFormatDescription` is fragile.** If the format
   description's dimensions don't match the actual pixel buffer,
   `CMSampleBufferCreateForImageBuffer` fails with -12743
   (`kCMSampleBufferError_InvalidMediaFormat`). Derive the
   format description from the pixel buffer (cached when
   dimensions stay constant). See
   `CMIOSinkWriter.formatDescription(for:)`.
3. **Don't trust stream array order.** OBS's plugin uses
   `streams[1]` to find its sink, but that's not portable across
   device implementations. Query
   `kCMIOStreamPropertyDirection` (0 = output/sink,
   1 = input/source) and pick by direction.
4. **Hardened runtime needs `com.apple.security.device.camera`
   even outside the sandbox.** TCC won't even prompt — it
   silently denies. Without that key, `requestAccess` returns
   `denied` with no UI. Add the entitlement to the v0.2.0 host
   entitlements file.
5. **Swift `NSLog` doesn't reach unified logging on
   macOS 14+** in our LSUIElement host or the system extension.
   Use `os.Logger(subsystem:category:)` exclusively. Tail with
   `log stream --predicate 'subsystem CONTAINS "ericwillis.avpainreliever"' --info --style compact`.
6. **Iterating on the extension binary requires either a reboot
   OR a Settings toggle off/on cycle.** Each new extension
   version queues the previous one as
   `[terminated waiting to uninstall on reboot]`, and macOS
   stops exposing the device through `system_profiler
   SPCameraDataType` until that queue clears. Confirmed both
   paths work: full reboot or System Settings → General →
   Login Items & Extensions → Camera Extensions → toggle off,
   wait, toggle on. The toggle path is faster but doesn't
   always work; reboot is the supported recovery.
7. **`open --env VAR=val`, not `VAR=val open`.** The shell-prefix
   form is stripped by `open` before launchd handoff. Has
   bitten us in M1 too — kept as a permanent note.
8. **Don't overlay a new bundle in `/Applications` between a
   build and a reboot.** macOS picks up the new bundle during
   boot and kicks off another upgrade cycle, undoing whatever
   the reboot was supposed to clean up. Reboot first, then
   install.

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
