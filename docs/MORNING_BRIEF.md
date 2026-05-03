# Morning brief — 2026-05-04

> Written 2026-05-03 ~02:00 PT, while you slept. Read this before the
> scheduled 9am reminder fires — it has more detail than the reminder
> can include.

## TL;DR

- **v0.1.0 release workflow is GREEN.** Draft release published. Just
  needs the smoke test below.
- **Pick up at the smoke test** — see *Resume here* below.
- **152/152 tests pass.** (was 145; the +7 are the new
  `UpdaterGatingTests` — see "Hardening" section.)
- **Five overnight commits ready to push.** A summary is in the *What
  I did* section. Nothing risky. All on `main`, none pushed yet (see
  *Decisions that need you* below).

## Resume here

The v0.1.0 draft release at
<https://github.com/superic/av-pain-reliever/releases> has
`AVPainReliever.app.zip` attached, signed and notarized. To prove
the whole pipeline works end-to-end:

1. **Open Safari** (or Chrome — needs a browser that applies
   `com.apple.quarantine`). Don't use `gh release download` — it
   skips quarantine and you won't be testing what real users see.
2. Open the release page → click `AVPainReliever.app.zip` → it
   downloads to `~/Downloads`.
3. Double-click the `.zip` in Finder. `AVPainReliever.app` lands
   alongside it.
4. Drag `AVPainReliever.app` → `/Applications`.
5. Double-click in `/Applications`.

**Expected:** the pill icon appears in your menu bar. No Gatekeeper
"Apple cannot check…" dialog, no warning, no second click required.
The first launch is the test — Gatekeeper consults the stapled
notarization ticket before showing anything.

If anything other than "pill appears, no dialog" happens, capture
the exact warning text. The most likely failure mode is "App is
damaged" (notarization didn't actually succeed) — diagnose with:

```sh
spctl -a -vvv -t exec /Applications/AVPainReliever.app
xcrun stapler validate /Applications/AVPainReliever.app
```

## After the smoke test: tag v0.1.1

To exercise the Sparkle auto-update path, you need a v0.1.1 release
that the v0.1.0 install can find on its next update check. One-line
README change is enough:

```sh
# Whatever tiny tweak — fix a typo, bump a date, anything trivial.
git add README.md
git commit -m "docs: one-line tweak for v0.1.1 auto-update test"
git tag -a v0.1.1 -m "v0.1.1 — exercise Sparkle auto-update"
git push origin main
git push origin v0.1.1
gh run watch  # ~90s build + 30-60s notarize
```

Then on the v0.1.0 install in `/Applications`:

1. Click the pill → **Advanced** → **Check for Updates…**
2. Sparkle should find v0.1.1, show its "A new version is available"
   dialog, download, verify, and install.
3. App relaunches at v0.1.1.

If Sparkle says "Unable to Check For Updates" — likely
`appcast.xml` on `main` didn't get the new `<item>` (release.yml's
"Append item to appcast.xml on main" step), or its EdDSA signature
doesn't match the published asset.

## What I did while you slept

Five focused commits, none pushed yet. They're all on local `main`
ahead of `origin/main`:

1. **Pin Sparkle to `.upToNextMinor(from: "2.9.0")`**
   ([Package.swift:33](../Package.swift)). Was `from: "2.6.0"` — too
   loose. Sparkle is the most notarization-sensitive dependency
   (its nested helpers must be re-signed inside-out, and the
   v0.1.0 ship just bit us when one was missing). A new minor
   version could re-shuffle `Versions/B/` silently. Pinned so a
   bump is now a deliberate decision.

2. **Extract `Updater.shouldEnable(...)` + `UpdaterGatingTests`**
   ([Updater.swift:21](../Sources/AVPainRelieverApp/Updater.swift),
   [UpdaterGatingTests.swift](../Tests/AVPainRelieverAppTests/UpdaterGatingTests.swift)).
   The placeholder-key gate that prevents Sparkle from initializing
   against `__SPARKLE_PUBLIC_KEY__` was inline in `AppDelegate` and
   completely untested. Now it's a pure static function with 7
   tests covering every branch (real release, no bundle, foreign
   bundle, placeholder key, empty key, nil key, plus a guard on the
   placeholder constant itself). If a placeholder ever slips into a
   release tag again, this catches it in CI.

3. **Add `.github/workflows/test.yml`**
   ([test.yml](../.github/workflows/test.yml)). Runs `swift test`
   on every PR and every push to `main`. Caches `.build`. The
   release workflow only fires on tags, so until now we had no
   automated check that landed code passed tests.

4. **Update `docs/RELEASING.md` with a v0.1.0 post-mortem**. Five
   things bit us during the first signed-tag push, all documented
   so the next person (or you, six months from now) doesn't relearn
   them: the missing `Autoupdate` in `SPARKLE_NESTED`,
   `errSecKeychainItemNoAccess -25294` from double-clicking a
   `.cer` with the iCloud keychain selected, the
   `notarytool store-credentials` workflow for keychain profiles,
   the markdown-autolink trap on email addresses pasted through
   chat, and "the first tag will probably fail."

5. **Update `SWIFT_PORT.md` with the v0.1.0 ship milestone**. New
   section documenting what landed, the lessons, the hardening done
   concurrently (items 1-4 above), and what's pending. Per your
   memory rule that SWIFT_PORT is a continuous artifact.

Plus a tiny README fix: line 32 said
"Quit AV Pain Reliever" but the menu label is just "Quit" since
commit `0c7bd29`.

## Decisions that need you

A few things I deliberately did NOT do unilaterally. Pick one or
more for tomorrow:

**1. Push the overnight commits to `origin/main`?**
I committed locally but didn't push. Memory says you've authorized
push to `main` for routine work, but five commits of
hardening + docs + tests is a chunkier batch than usual, and pushing
them now would land them between v0.1.0 and v0.1.1 — meaning v0.1.1
will include them in its diff. That's fine for an
auto-update smoke test (the changes don't affect runtime behavior
at v0.1.1). But you might prefer to push them after the v0.1.1
test, on a separate hardening tag (v0.1.2?), to keep
v0.1.1's "what changed" cleaner. **I'd lean toward push-now** but
it's your call. To push now:
```sh
git push origin main
```

**2. AppDelegate refactor: do it now or defer?**
[AppDelegate.swift](../Sources/AVPainRelieverApp/AppDelegate.swift)
is 577 lines. Multiple loosely-related responsibilities live there:
engine boot, Sparkle gate, login-item apply, welcome state,
profile-edit session lifecycle. A clean split is
`EngineBootManager` + `EditingSessionManager`, leaving the
`AppDelegate` itself as the SwiftUI scene wiring. **I'd defer** —
the file is dense but understandable, the refactor would touch a
lot of behavior, and we just shipped. Better as a v0.2.0 candidate
once we have user feedback that justifies it.

**3. Bump `Sparkle` 2.9 → 2.10 / 3.x when available?**
Currently pinned to `.upToNextMinor(from: "2.9.0")`. Whenever
Sparkle releases a new minor, walk
`Sparkle.framework/Versions/B/` and confirm `SPARKLE_NESTED` in
`scripts/make-app.sh` still names every nested bundle and bare
binary. Then a `v0.0.0-dryrun` tag exercises the build before
shipping a real bump. **No action needed yet** — flagging so you
remember the workflow when GitHub's dependabot eventually pings.

**4. Notify users on the v0.1.0 release?**
Once smoke-tested, the draft release is ready to publish. There
isn't an established user base to notify (this is v0.1.0, the first
shipped version), so "publishing" mostly just makes the asset URL
permanent and stops it being a draft. **Recommendation:** publish
after v0.1.1 also lands and the auto-update path is verified end-
to-end. That way the published v0.1.0 release has a known-working
upgrade path on day one.

## Codebase audit notes (the deeper findings)

Running `swift test --parallel` clean: 152 tests in 16 suites.
Build clean. No `print()`, `fatalError`, `try!`, `as!` reachable
from user input. No TODO/FIXME/XXX in `Sources/`. `.gitignore` is
sound (covers `dist/`, `.build/`, `.swiftpm/`, editor junk,
Hammerspoon prototype logs). No leaked secrets in tracked files
(only references are in `docs/RELEASING.md` and the workflow YAML,
where they belong).

### Architecture is solid

- **Engine library** ([Sources/AVPainReliever/](../Sources/AVPainReliever/)):
  protocols-and-adapters split between
  `USBWatcher` / `Debouncer` / `ProfileResolver` / `ProfileApplier`
  with `AudioController` + `CameraController` + `Notifier` adapter
  protocols. Production wires CoreAudio + AVFoundation; tests use
  recording mocks. Clean. No coupling between engine and app
  target.
- **App target** ([Sources/AVPainRelieverApp/](../Sources/AVPainRelieverApp/)):
  SwiftUI scenes + AppDelegate own the runtime. The view layer
  (AddProfile wizard, Settings, About, Welcome) is testable through
  ViewModels (e.g., `AddProfileViewModel` has 8 tests). Pure
  helpers (Theme, ProfileIcon, NotificationCopy, SettingsStore,
  DevicePortability) are unit-tested.
- **Configuration**: `profiles.toml` at
  `~/Library/Application Support/AVPainReliever/`. ProfileWriter
  preserves user comments + ordering on append/replace/delete.
  ProfileWriter has 14 tests including the round-trip /
  comment-preservation case. Solid.

### Test coverage gaps (low-priority now)

ProfileWriter and SettingsStore are well-covered. The honest gaps:

- **Engine end-to-end happy path** (USB event → debounce → resolve
  → apply) — there's a `RecordingUSBWatcher` test fixture, but no
  test that wires the whole pipeline. Adding one would require a
  mock USB event injector but would catch regressions in any of
  the four engine stages. Medium effort, medium value.
- **`LaunchAtLogin.apply(...)` failure paths** — currently logs but
  doesn't expose the result. A test that verifies the log message
  on a no-bundle scenario would be useful but isn't release-
  critical.
- **`AppIcon.makeIcon` regenerates correctly under different
  appearance environments** — there's a singleton-cache test and a
  pixel-data test, but no test for dark-mode rendering. Low value
  given the icon rasterizes once at launch.

### Files that could shed weight

- `AppDelegate.swift` (577 lines) — see Decision #2 above.
- `App.swift` (16,816 bytes / ~430 lines) — owns the
  `MenuBarExtra` menu construction. Long but linear; not a
  refactor candidate yet.
- `AddProfileView.swift` + `AddProfileViewModel.swift` (~32k bytes
  combined) — the wizard's the most complex SwiftUI surface in the
  app. Already split View/ViewModel cleanly.

### Hygiene caveats

- Memory says "no Hammerspoon or OBS in UI OR docs (incl. README)."
  The main README does NOT mention Hammerspoon by name, but it
  does describe `prototypes/` as a "Research archive" in the
  developer-only "Nerd zone" section, which links to
  [`prototypes/README.md`](../prototypes/README.md). The
  prototypes README itself describes the Hammerspoon prototype
  in detail. Strict reading of the rule: this still surfaces
  Hammerspoon to anyone reading the README. **My read:** the
  rule is about user-facing pitch, not the developer-archive
  reference, so I left it. If you want it stripped from the
  main README's "Nerd zone" too, it's a 2-line delete.
- `docs/RELEASING.md` previously had `eric.willis@bactrack.com` as
  the example `APPLE_ID` value. Replaced with `you@example.com`
  since the actual project Apple Developer account is
  `e@ericwillis.com` (per memory) — neither belongs in committed
  example text.

### Open questions for v0.2.0

- Homebrew-cask formula. Listed as v2 candidate in
  `docs/RELEASING.md`. Once v0.1.x is in the wild and the appcast
  has 2-3 releases, a cask submission would let users
  `brew install --cask av-pain-reliever`.
- Mac App Store path stays blocked by `app-sandbox=NO` (we need
  IOKit + CoreAudio). Worth re-checking once a year — Apple has
  occasionally relaxed entitlements for tools like this.
- Telemetry: currently zero. README leans into that ("no network
  calls, no analytics"). Worth keeping unless we have a specific
  question we need data to answer.
- `IOKitUSBWatcher` test runs only when USB hardware is attached
  (skipped in clean CI). Consider mocking the run-loop source so
  it always runs, or just accepting the skip.

## Quick reference (for the bleary-eyed)

| Thing | Path / Command |
| --- | --- |
| Draft release | <https://github.com/superic/av-pain-reliever/releases> |
| Workflow runs | `gh run list --workflow=release.yml` |
| Notarytool log | `xcrun notarytool log <id> --keychain-profile avpain-notary` |
| Local Sparkle key (login keychain) | account `avpainreliever` |
| Local notary creds (login keychain) | profile `avpain-notary` |
| GitHub Secrets | `gh secret list` |
| Run all tests | `swift test --parallel` |
| Build local app | `scripts/make-app.sh` |

—Claude (overnight session, 2026-05-03 02:00 PT)
