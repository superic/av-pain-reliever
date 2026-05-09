# AI Slop Review: `Sources/AVPainReliever/` (engine library)

Run on 2026-05-08 against commit `d271fea` on `main`.

**Scope:** 18 Swift files, ~2,800 LOC. Codebase audit, not a PR.

**Grade:** **B (32/100)** Mild concerns
**Local Code Score:** 28/100
**Solution-Fit Score:** 38/100
**Verdict:** Mild concerns. Engine is fundamentally well-shaped after the recent slop-review-driven refactors (PRs #43, #50, #51, #52, #54). Four real findings worth fixing, a small borderline appendix, no pervasive slop.
**Confidence:** High. Headline findings are mechanical to verify and were spot-checked against the code.

> **Reading the scores:** lower = cleaner, 0 means no findings, 100 means pervasive slop. *Confidence* uses the opposite convention (higher = more confident).

## Solution-Level Assessment

| Dimension | Score | Finding | Better Direction |
|---|---:|---|---|
| Module boundaries | 30 | `Notifier` protocol orphaned in engine (S2); `Profile` carries wizard-only fields (S5) | Move `Notifier` to app target; consider `Profile` + `ProfileMetadata` split |
| Abstraction boundary | 35 | `AudioController` / `CameraController` mix engine "apply" + wizard "discovery" verbs (S6) | Split into `AudioApplier` + `AudioInventory`, both implemented by the same concrete type |
| Existing-mechanism reuse | 25 | TOMLKit's editable doc API exists (S1), but the regex approach has a defensible rationale | Keep regex; defensible |
| Scope control | 30 | `CameraCaptureSession` does triple duty (S4) | Extract a thin wrapper for `VirtualCameraSourceController` conformance |
| Maintenance cost | 40 | Stale `os.log` doc (Q2); duplicated regex (Q5); orphan protocol (S2) | Direct fixes for each |
| Process-clean rule | 35 | `Notifier` protocol violation (S2). All other engine files genuinely clean: no AppKit / UserNotifications / SwiftUI / Combine imports | Fix S2 to clear this |

## Solution-Fit Findings (score ≥ 70)

| # | Area | Signal | Finding | Better Direction | Score | Verdict |
|---|---|---|---|---|---:|---|
| S2 | `Adapters/Notifier.swift` | Wrong target | Protocol declared in engine but zero engine consumers. Engine signals via callbacks; only the app target calls `notify(...)`. PR #54 moved both implementations to the app target. The protocol should follow. | Move `Notifier` (protocol + 2 convenience extension methods) to `Sources/AVPainRelieverApp/`. | 85 | CONFIRMED |

## File-Level Assessment (top-3 by score)

| File | LOC | AI Lik. | Idiom | Quality | Findings | Notes |
|---|---:|---:|---:|---:|---|---|
| `Adapters/VirtualCamera/CMIOSinkWriter.swift` | ~470 | 35 | I3, I4 | Q2 (88) | 1 high-confidence stale doc + 2 minor idiom nits | Stale `os.log` doc post-#52 |
| `Config/ProfileWriter.swift` | ~310 | 50 | (none) | Q4 (70), Q5 (82) | Public `render` bypasses validate; duplicated regex | Fix both as one PR |
| `Adapters/Notifier.swift` | ~40 | 60 | (none) | (none) | S2: wrong target | Move to app |

All other files calibrated AI-likelihood ≤ 35 (clean by this codebase's bar).

## AI Authorship Signals

No findings ≥ 70. Phase 1a flagged residue from the `ApplierLogger` migration (45) and minor mechanical-style nits in `ProfileWriter`'s TOML emit (18, 22). All were dismissed or downgraded after calibration confirmed they were intentional or had remaining beneficiaries (the test mock still relies on the `error → warn` default).

## Idiom Violations (score ≥ 70)

(none)

## Code Quality (score ≥ 70)

| # | File:Line | Signal | Finding | Score | Verdict |
|---|---|---|---|---:|---|
| Q2 | `Adapters/VirtualCamera/CMIOSinkWriter.swift:82-83` | Stale docs | `start()` doc says "All failures log via os.log". File no longer imports `os.log`; all errors route through injected `ApplierLogger` (post PR #52). | 88 | CONFIRMED |
| Q5 | `Config/ProfileWriter.swift:235 vs :248` | DRY | The `(?m)^[[:space:]]*\[profiles\.<escaped>\][[:space:]]*$` regex is verbatim duplicated between `containsProfile(named:in:)` and `sectionRange(named:in:)`. Trivial helper extraction. | 82 | CONFIRMED |
| Q4 | `Config/ProfileWriter.swift:95-97, :270` | Security (defense-in-depth) | The public `render(profile:deviceNames:)` interpolates `profile.name` into `[profiles.<name>]` without `validateName`. The `append`/`delete`/`replace` entry points validate; `render` bypasses. Narrow exposure (caller already holds a `Profile`), but cheap to close. | 70 | CONFIRMED |

## Positive Signals

- **Process-clean rule honored:** `grep -rn "import AppKit\|import UserNotifications\|import SwiftUI\|import Combine" Sources/AVPainReliever/` returns empty. The recent #54 refactor stuck.
- **Custom `ApplierLogger` protocol** is consistently injected through every adapter; no file-scope `os.Logger` instances remain in the engine.
- **C-API ceremonies** (IOKit `IOServiceMatching`, CoreAudio `AudioObjectGetPropertyData`, CMIO property queries) are verbose-but-correct; comments explain *why* not *what*.
- **Test seams via constructor injection** (`AudioController`, `CameraController`, `DebouncerClock`, `ApplierLogger`, `USBWatcher`, `Notifier`) are the right shape for headless / Camera-Extension embedding.
- **Hand-debugged provenance** in CMIO files: comments cite real failures (VT format-description -12743, M2 lessons, specific HDMI capture device 0x1e4e/0x701f). Strong human authorship signal.

## Borderline Findings (score 50-69)

| # | File:Line | Lens | Finding | Score |
|---|---|---|---|---:|
| I1 | `Engine/USBWatcher.swift:315-322` | IDIOM | `(raw.takeRetainedValue() as? NSNumber)?.intValue`. Modern Swift bridges via `as? Int` directly; the same file uses `as? String` for other property kinds. | 65 |
| S6 | `Adapters/AudioController.swift:77-92`, `CameraController.swift:46-59` | SOLUTION_FIT | Both protocols mix engine-only `setDefault` / `setPreferred` with wizard-only discovery methods. ISP split into `*Applier` + `*Inventory` would unmix the seams. | 60 |
| S4 | `Adapters/VirtualCamera/CameraCaptureSession.swift` | SOLUTION_FIT | One 366-line class is `AVCaptureSession` owner + sample-buffer delegate + `VirtualCameraSourceController` conformer. Extracting a thin wrapper for the controller would clarify responsibilities. | 55 |
| I3 | `Adapters/VirtualCamera/CMIOSinkWriter.swift:58, :428-443` | IDIOM | `(OSType, Int, Int)` tuple accessed via `.0/.1/.2`; the rest of the codebase uses small named structs for multi-field values. | 55 |
| (missed) | `Engine/USBWatcher.swift:217-226` | CODE_QUALITY | `stop()` sets `addedIter = 0` / `removedIter = 0` without `IOObjectRelease`. `IONotificationPortDestroy` may release them transitively, but the explicit lifecycle is unclear. Worth verifying against IOKit docs. Possible leak. | 55 |
| I4 | `Adapters/VirtualCamera/CMIOSinkWriter.swift:39, :305-327` | IDIOM | `Unmanaged.passUnretained(pixelBuffer).toOpaque()` for reference identity. `ObjectIdentifier(pixelBuffer)` is the Swift-native form (CF types bridge as `AnyObject`). | 50 |

## Dismissed Findings (score < 50)

13 findings dismissed or downgraded by calibration. Highlights:

- **A1 / S3 (45):** `ApplierLogger.error → warn` default extension. Residue claim, but the test mock still relies on it; removing the default would force test mock changes for no real benefit.
- **A3 (22):** TOML column alignment matches the loader's documented schema example; intentional consistency.
- **I5 (22):** `allowed.contains(_:)` explicit selector is sometimes load-bearing for overload disambiguation.
- **I2 (28):** `String(decoding:as: ASCII)` would silently substitute `\u{FFFD}` for non-ASCII bytes; current `?? "????"` fallback is a deliberate semantic choice.
- **Q3 (45):** Claimed undocumented `icon` exclusion from `==` / `hash`. Actually documented at the field declaration (`Profile.swift:42-44`).
- **S1 (40):** TOMLKit-vs-regex. TOMLKit doesn't fully round-trip arbitrary inline comments and whitespace, so the regex approach has a real rationale.
- Plus 7 more low-confidence nitpicks not worth listing.

## Top Actionable Fixes

| # | What | Effort | PR shape |
|---|---|---|---|
| 1 | **Q2** Fix the stale `os.log` doc-comment on `CMIOSinkWriter.start()` | 1 line | Bundle with #2 + #3 |
| 2 | **Q5** Extract the duplicated `[profiles.<name>]` regex into a `makeHeaderRegex(for:)` private static helper in `ProfileWriter` | ~10 lines | One small PR |
| 3 | **Q4** Call `try Self.validateName(profile.name)` at the top of public `render(profile:deviceNames:)` (defense-in-depth) | ~3 lines | (same PR) |
| 4 | **S2** Move `Notifier` protocol from `Sources/AVPainReliever/Adapters/Notifier.swift` to `Sources/AVPainRelieverApp/Notifiers.swift` (alongside its two implementations from #54) | <50 lines | Separate small PR |

## Methodology

Generated by the `code-quality:slop-review` skill (4-lens parallel architecture):

1. **Step 0 (Haiku):** scope, idiom baseline, project-guidance gathering.
2. **Phase 1a (Opus):** AI authorship detection.
3. **Phase 1b (Opus):** idiom fluency.
4. **Phase 1c (Sonnet):** code quality.
5. **Phase 1d (Opus):** architecture and solution-fit.
6. **Phase 2 (Opus):** calibration. Each Phase 1 finding was re-verified against the actual code, scored on 0-100, and given a verdict (CONFIRMED / DOWNGRADED / DISMISSED / ESCALATED). Cross-lens correlations were identified (A1 ↔ S3, Q3 ↔ S5).

No `.code-quality/slop-acceptances.md` was supplied; calibration scored every finding from scratch. Test files (`Tests/`) were out of scope.
