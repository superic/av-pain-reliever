# Prototypes — research archive

This directory holds the pre-Swift-app research that the current `Sources/` Mac app supersedes. Two flavors:

## `hammerspoon/`

The original Phase 1 prototype: a Hammerspoon (Lua) engine plus a Bash + [gum](https://github.com/charmbracelet/gum) install/wizard. It worked end-to-end and was the canonical version of the product for several weeks while the Swift port was being designed and validated.

What's in here:

- [`init.lua`](hammerspoon/init.lua) + [`profiles.lua`](hammerspoon/profiles.lua) — the Hammerspoon engine + sample config.
- [`wizard.sh`](hammerspoon/wizard.sh) + [`wizard/`](hammerspoon/wizard) — the Bash wizard that drove install, OBS configuration, dependency setup, and per-location profile capture.
- [`tests/`](hammerspoon/tests) — Bash test suite for the wizard (snapshot parsing, profile generation, idempotency, dry-run).
- [`README.md`](hammerspoon/README.md) — the original install/usage README written for non-technical users.

**Status:** archived. No longer maintained. The Swift app's `ConfigImporter` still reads `profiles.lua` files on first launch as a one-shot migration path for users moving over from Phase 1, but the Lua/Bash code itself is no longer being changed.

**Why keep it around?** Three reasons:

1. The user's existing local Hammerspoon config (at `~/.hammerspoon/profiles.lua`) gets auto-imported by the Swift app on first launch. The importer's tests parse this directory's `profiles.lua` to verify the parser stays compatible — so the file is functionally a fixture for the Swift codebase.
2. Several of the lessons captured in [`../SWIFT_PORT.md`](../SWIFT_PORT.md) (USB debounce window, fingerprint match algorithm, "Same as System" pattern) were learned from real use of this prototype. The history is the receipts.
3. If a future user really wants to run the Hammerspoon version (no Swift, no .app bundle, no notarization), they can still follow [`hammerspoon/README.md`](hammerspoon/README.md). The Swift app is strictly more capable, but the Lua version is smaller and editable.

## `swift-research/`

Two single-file Swift prototypes used to de-risk the IOKit + CoreAudio integrations before the production engine was written.

- [`usb-watcher.swift`](swift-research/usb-watcher.swift) — proves that `IOServiceMatching` + `IONotificationPort` produces output equivalent to Hammerspoon's `hs.usb.watcher`, and shores up the C-API ergonomics (matching dictionary lifecycle, iterator draining, run-loop wiring, refCon for callback context).
- [`audio-defaults.swift`](swift-research/audio-defaults.swift) — proves that raw CoreAudio (`kAudioHardwarePropertyDevices`, `kAudioHardwarePropertyDefaultInputDevice|OutputDevice`) covers the engine's full audio surface without needing a SimplyCoreAudio wrapper.

Run either one directly:

```sh
swift prototypes/swift-research/usb-watcher.swift
swift prototypes/swift-research/audio-defaults.swift
```

Both findings (and their patterns-worth-keeping) are written up in [`../SWIFT_PORT.md`](../SWIFT_PORT.md) under "IOKit prototype findings" and "CoreAudio prototype findings".

**Status:** archived. The patterns these proved are already in the production engine at `../Sources/AVPainReliever/`. No reason to keep evolving them.
