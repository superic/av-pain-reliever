# CLAUDE.md — orientation for Claude Code

Auto-loaded into every Claude session. Tells future-Claude what's true about this repo regardless of who's working on it.

## What this app is

**AV Pain Reliever** is a macOS menu-bar utility that watches USB devices, recognizes a known peripheral fingerprint as a "location" (home office, conference room, etc.), and switches the system audio defaults + camera selection to match. v0.2 added a native CMIO virtual camera so Zoom / Slack / Teams pick up the active source. Bundle ID: `com.ericwillis.avpainreliever`. Deployment target: macOS 14.

## Repo topology

This workspace contains **two independent git repos**:

- **Public repo** (`superic/av-pain-reliever`) — the project tree at the root. CI / Sparkle / public releases.
- **Private dev repo** (`superic/av-pain-reliever-dev`) — cloned into `dev/`, gitignored from the public repo. Contains the local build helper (`dev/build`), credentials config, and recovery docs. See `dev/README.md` (private) for setup, recovery, and the cert / notary / Sparkle-key dance.

Never put the cert name, team ID, or anything personal-credential-shaped into public-repo content. See `dev/README.md` for what lives in private.

## Where to look for what

| concern | doc |
|---|---|
| Product decisions, target use cases, open questions | `docs/decisions.md` |
| Architecture, IOKit/CoreAudio findings, real-launch bugs | `docs/architecture.md` |
| Visual rules (chrome, colors, accent policy) | `docs/visual-identity.md` |
| Virtual camera (V2 CMIO extension) — design + impl journal | `docs/virtual-camera.md` |
| Project journal (newest-first) | `CHANGELOG.md` |
| Release process (cutting a release, secrets setup) | `docs/releasing.md` |
| Self-hosted CI runner setup + lockstep rule | `docs/self-hosted-runner.md` |
| Virtual camera developer setup (build/install loop) | `docs/virtual-camera-dev.md` |
| User-facing intro | `README.md` |

If a fact you need isn't in any of these, it likely belongs in code comments or memory, not new prose.

### Markdown filename convention

- **Repo-root meta files** (`README.md`, `LICENSE`, `CHANGELOG.md`, `CLAUDE.md`) → UPPERCASE. These speak *about* the project; GitHub renders them prominently.
- **Content under `docs/`** → lowercase-hyphenated. Modern docs convention; URL-friendly. Example: `docs/architecture.md`, `docs/self-hosted-runner.md`.

Don't mix the two conventions inside `docs/`. If a new doc belongs there, it's lowercase-hyphenated.

## Project-wide conventions

These apply to every contributor; treat them as load-bearing.

### Git

- **PR-based workflow.** Branch off `main`, push the branch, open a PR via `gh pr create`. Don't push directly to `main` (server-side block, but also against the rule).
- **Tags come AFTER the PR merges.** Branch off the merged `main`, then `git tag vX.Y.Z && git push origin vX.Y.Z`. Don't tag a feature branch.
- **No force-pushes** to `main` or any shared branch. No `--no-verify` to skip hooks unless explicitly authorized.
- **Don't commit secrets.** `.gitignore` covers the obvious paths; double-check `git status` before staging.

### Bash scripting

All shell scripts in this repo (`scripts/`, `dev/`) **must work on macOS stock bash 3.2.57**. Apple won't ship newer bash for licensing reasons; CI and other users are on the same. Avoid bash 4+ features:

- ❌ `mapfile` / `readarray` → use `while IFS= read -r line; do ... done < <(cmd)`
- ❌ Associative arrays (`declare -A`) → use parallel indexed arrays
- ❌ `${var,,}` / `${var^^}` case conversion → use `tr` / `awk`
- ❌ `**` globstar → use `find`
- ❌ `&>` shorthand redirect → use `> file 2>&1`
- ❌ `[[ -v VAR ]]` → use `[ -n "${VAR+x}" ]`

Indexed arrays, process substitution, `[[ ]]`, and parameter expansion (`${var:-default}`, `${var#prefix}`, etc.) are all bash 3.2 — fine to use.

### Visual / aesthetic

- **Plain native macOS look.** Use SwiftUI defaults — `.primary` / `.secondary` for text, system accent for `.borderedProminent` buttons. **No custom accent colors**, no `.tint(...)` on prominent buttons, no brand palette. The earlier CLI-derived magenta/cyan palette was retired 2026-05-02; do not reintroduce.
- **Status colors are the only `Theme.Color` entries.** `.green` (success), `.orange` (warn), `.red` (error). System colors only.
- **Self-contained.** The app must NOT mention any third-party tool (no OBS, no Hammerspoon, no Camo, etc.) in its UI or in user-facing docs (including README). It reads as its own product.

### Release notes

User-facing release notes (in `appcast.xml` and `gh release` bodies) are written in **Vince Vaughn's voice**: fast-talking, technically correct, a touch silly. "Money." Never open with "Listen, …" — that reads as a tic. Vary the opener.

### Settings persistence

`SettingsStore` uses a **lazy-default pattern**: on read, returns the default value if nothing's persisted, but **never writes the default to disk**. This lets us evolve the default symbol/behavior without forcing existing users to migrate manually. Pattern at `Sources/AVPainRelieverApp/SettingsStore.swift` `init`. Don't break it without thinking about migration.

### Forms

Every grouped Form surface (Settings tabs, wizard sections) ends with the `groupedFormChrome()` modifier — single source of chrome (no outer horizontal padding, no extra background). If you create a new grouped Form, apply it; don't reinvent the chrome.

### Symbols

Shared SF Symbol names live in `Theme.Symbol` enum. Don't sprinkle string literals across the codebase.

## What the dev environment expects

- macOS 14+
- Xcode CLT (for Swift 5.9+ toolchain)
- `swift build`, `swift test` work directly
- A signed + notarized build requires the cert + notary keychain profile — see `dev/README.md` (private)
- Self-hosted runner needed for CI release builds (avoids the team-ID-in-public-CI problem)

For local UI iteration, run `./dev/build` (private helper). It wraps the kill→build→install→launch loop with a polished status board. `./dev/build --full` does the notarized + install-to-Applications path.

## What CI does

`.github/workflows/test.yml` runs on every PR — `swift build` + `swift test`, fail on any failure. Self-hosted runner.
`.github/workflows/release.yml` runs on tag push (`v*.*.*`) — production build, sign, notarize, upload, sign appcast, commit appcast back to main. Tag pattern decides experimental vs stable Sparkle channel.

## When in doubt

1. Check `CHANGELOG.md` for the most recent context on what was changing.
2. Check `docs/decisions.md` for "is this still the right approach?"
3. Check `docs/architecture.md` for "where does this code live and why?"
4. If still unsure, ask the user.
