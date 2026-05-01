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
2026-04-30. Swift port started 2026-05-01 — IOKit + CoreAudio prototypes
landed, engine core (`ProfileResolver` + `Debouncer`) and apply layer
(`ProfileApplier` + `CoreAudioController` + `ProcessOBSController`)
ported with tests. `USBWatcher` (`IOKitUSBWatcher`) wraps the IOKit
prototype as a real class with `start`/`stop` lifecycle. Source lives
in `mac/` as a Swift Package.

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

## Visual identity (locked 2026-05-01)

- **App display name**: AV Pain Reliever
- **Bundle ID**: `com.ericwillis.avpainreliever`
- **Tagline**: "Stop fiddling with mic, speakers, and webcam."
- **Brand colors** (carry through from the CLI's gum/ANSI palette so the
  app and wizard feel like the same product):
  - Primary: magenta/pink — ANSI 212, hex ≈ `#FF87D7` — headers, accents,
    primary CTA buttons
  - Highlight: cyan — ANSI 51, hex ≈ `#00FFFF` — emphasis, taglines, links
  - Success: green — ANSI 46, hex ≈ `#00FF00` — ✓ marks, "Switched to X" toasts
  - Warn: yellow — ANSI 220, hex ≈ `#FFAF00` — soft warnings
  - Error: red — ANSI 196, hex ≈ `#FF0000` — fatal errors
  - Chrome: gray — ANSI 245, hex ≈ `#8A8A8A` — borders, hint text
- **Menu bar icon (v1)**: SF Symbol `pills.fill` rendered as a template
  image. Auto-adapts to light/dark mode, native vibe, zero design effort.
  Upgrade to a custom mark in v2 when we have a designer (or have
  AI-generated something we like).
- **App icon (v1)**: defer custom design. During dev, use a placeholder
  (Pixelmator-mocked pill on a magenta→cyan radial gradient, or just
  Xcode's default). Custom icon = a discrete sub-project before shipping.
- **Menu bar UI**: native SwiftUI defaults, no custom theming for v1.
  Status item title is plain text showing the current profile name
  (per the locked "no manual override" decision — it's a status display,
  not a control surface).
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
- IOKit USB watcher (notification port + run loop): 4-6h (notoriously fiddly)
  → DONE 2026-05-01 as `IOKitUSBWatcher` in
    `mac/Sources/AVPainReliever/Engine/USBWatcher.swift`. Lifted from
    the prototype; ~150 lines. Actual: ~25 min including 3 smoke tests.
- CoreAudio adapter (raw CoreAudio, no SimplyCoreAudio): 2-3h
  → DONE 2026-05-01 as `CoreAudioController` in
    `mac/Sources/AVPainReliever/Adapters/AudioController.swift`. Lifted
    directly from the prototype; ~85 lines.
- ProfileResolver + Debouncer (Swift port of init.lua logic): 2-3h
  → DONE 2026-05-01 in `mac/`. Actual: ~30 min including 15 tests.
    Revise category estimate down for similar pure-logic ports.
- ProfileApplier + Notifier: 2h
  → ProfileApplier DONE 2026-05-01 in `mac/`. Notifier still open (lands
    with the menu-bar app target, since it depends on
    `UserNotifications` registration at app startup).
- OBSController wrapping obs-cmd Process: 1-2h
  → DONE 2026-05-01 in `mac/Sources/AVPainReliever/Adapters/OBSController.swift`.
- ConfigLoader (TOML parser): 1-2h
- ConfigImporter (parse profiles.lua → profiles.toml): 2-3h
- StatusItem menu UI: 1-2h (smaller now that there's no Switch-to submenu)
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

The first production Swift code lives in `mac/` as a Swift Package, set
up to be wrapped by the eventual menu-bar app's Xcode project. Run
`cd mac && swift test` to exercise the engine in isolation — no
AppKit/IOKit/CoreAudio imports yet, so the package builds + tests in
under 10 seconds on a cold cache.

### What's there

```
mac/
├── Package.swift
├── Sources/AVPainReliever/
│   ├── Engine/
│   │   ├── Debouncer.swift        # 1.5s coalescing, injectable DebouncerClock
│   │   ├── ProfileApplier.swift   # orchestrates audio + OBS side effects
│   │   ├── ProfileResolver.swift  # init.lua's resolveProfile()
│   │   ├── USBDevice.swift        # Hashable (vid, pid)
│   │   └── USBWatcher.swift       # protocol + IOKitUSBWatcher
│   ├── Adapters/
│   │   ├── AudioController.swift  # protocol + CoreAudioController
│   │   └── OBSController.swift    # protocol + ProcessOBSController
│   └── Config/
│       └── Profile.swift          # name + fingerprint + audio + scene
└── Tests/AVPainRelieverTests/
    ├── DebouncerTests.swift            # 7 tests
    ├── IOKitUSBWatcherTests.swift      # 3 smoke tests (real IOKit)
    ├── ProfileApplierTests.swift       # 10 tests
    ├── ProfileResolverTests.swift      # 8 tests
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
