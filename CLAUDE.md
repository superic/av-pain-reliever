# CLAUDE.md — orientation for Claude Code

## What this app is

**AV Pain Reliever** is a macOS menu-bar utility. It watches USB devices, recognizes peripheral fingerprints as "locations" (home office, conference room, etc.), and switches the system audio defaults + camera selection to match. Embedded CMIO virtual camera so Zoom / Slack / Teams follow profile changes too.

## Repo topology

This workspace contains **two independent git repos**:

- **Public repo** (`superic/av-pain-reliever`) — the project tree at the root. CI / Sparkle / public releases.
- **Private dev repo** (`superic/av-pain-reliever-dev`) — cloned into `dev/`, gitignored from the public repo. Contains the local build helper (`dev/build`), credentials config, and recovery docs. See `dev/README.md` (private) for setup, recovery, and the cert / notary / Sparkle-key dance.

Never put the cert name or anything credential-shaped (signing identity passwords, notary keychain profile names, Sparkle EdDSA private keys) into public-repo content. See `dev/README.md` for what lives in private.

macOS sandboxing requires team-ID-prefixed names at specific call sites (Darwin notification names from the Camera Extension, App Group identifiers, mach service names, keychain access groups). Those uses are load-bearing — the OS rejects calls without the prefix. Everything else (utility scripts, CI configs, prose) keeps the team ID out.

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

## Project-wide conventions

### Git

- **PR-based workflow.** Branch off `main`, push the branch, open a PR via `gh pr create`. Don't push directly to `main` (server-side blocked anyway).
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

- **Plain native macOS look.** Use SwiftUI defaults — `.primary` / `.secondary` for text, system accent for `.borderedProminent` buttons. **No custom accent colors**, no `.tint(...)` on prominent buttons, no brand palette.
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

### Markdown filenames

- Repo-root meta files (`README.md`, `LICENSE`, `CHANGELOG.md`, `CLAUDE.md`) → UPPERCASE.
- Content under `docs/` → lowercase-hyphenated.

### Docs that move with the code

- **CHANGELOG.md**: every non-mechanical PR adds a dated H3 entry. Internal design notes are plain prose; user-facing release notes use the Vince Vaughn voice (see Release notes above).
- **README.md**: update when a PR changes user-visible behavior — a new setting, renamed menu item, removed feature, install-flow change. Skip for internal refactors, doc-only edits, and test-only changes (an executive reader wouldn't notice them).

### Avoiding slop

Patterns to watch when writing code. Detailed history lives in CHANGELOG.

- **Sweep for orphans when you remove a use site.** Grep for unused `@Published` fields, unused parameters, and helpers with a single inlined caller.
- **Update doc comments when you rename or remove a symbol.** `git grep` the old name and fix the prose along with the code.
- **Put a type in the file of its primary consumer.** If a type's only caller is in another file, move the type before adding more references.
- **Don't expand API surface ahead of need.** If a parameter would need `_ = (param)` to silence unused warnings, it doesn't belong in the API.
- **Shared visual idioms get a component, not three near-copies.** When two or three views render the same chrome, extract before the third call site lands. Drift between near-copies is where dark-mode and contrast bugs hide.
- **No defensive code for paths that can't fire.** Trust internal guarantees and framework invariants. Validate at system boundaries (user input, external APIs, file IO), not between functions you control.
- **Pre-PR `/code-quality:slop` on non-trivial work.** Run it on the diff before pushing a feature or shape-changing refactor. Mechanical cleanups, doc-only, and test-only changes don't need it.

## Dev + CI

- macOS 14+, Xcode CLT (Swift 5.9+).
- `swift build`, `swift test` work directly.
- Signed + notarized builds need the cert + notary keychain profile — see `dev/README.md` (private).
- Self-hosted runner for CI release builds (avoids the team-ID-in-public-CI problem).
- Local UI iteration: `./dev/build`. Full notarized + install-to-Applications: `./dev/build --full`.
- `.github/workflows/test.yml` runs `swift build` + `swift test` on every PR.
- `.github/workflows/release.yml` runs on `v*.*.*` tag push: build, sign, notarize, upload, sign appcast, commit appcast back to main. Tag pattern picks the Sparkle channel.
