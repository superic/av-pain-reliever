# prototypes/

Throwaway research code that de-risks specific pieces of the eventual Swift
native app port (see [`SWIFT_PORT.md`](../SWIFT_PORT.md) for the full plan).

These prototypes are **not** part of the shipping Hammerspoon engine and
are **not** the production Swift app. They exist to answer one focused
question per file before we commit to building the real thing. Code here
does not need to be production quality — it needs to compile, run, and
teach us something.

## What's here

| File | What it proves | Status |
| --- | --- | --- |
| [`usb-watcher.swift`](usb-watcher.swift) | IOKit USB watching produces output equivalent to Hammerspoon's `hs.usb.watcher` (initial snapshot + live add/remove events). | ✅ Working |

## Running

Each prototype is a single Swift file runnable directly with the system
Swift toolchain (Xcode CLI tools — no Xcode project needed):

```sh
swift prototypes/usb-watcher.swift
```

Stop with **Ctrl+C**.

## Findings

When a prototype answers its question, the takeaways get written into
[`SWIFT_PORT.md`](../SWIFT_PORT.md) under a dedicated section so the
production Swift port starts from real data rather than guesses. See
[`SWIFT_PORT.md` → "IOKit prototype findings"](../SWIFT_PORT.md#iokit-prototype-findings).
