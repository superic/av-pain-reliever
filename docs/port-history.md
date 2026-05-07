# Port history (Phase 1: Hammerspoon → Swift)

Historical record of the Hammerspoon-prototype-to-Swift transition (2026-05-01). The Swift code is the source of truth now — read these notes only when you need the Phase-1 reasoning for a particular module's design (e.g., why the engine debouncer is structured the way it is, what was learned from the IOKit prototype that survived into the production code).

The "Lessons learned" section is the high-level retrospective; the per-module sections that follow are the line-by-line port logs.

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

