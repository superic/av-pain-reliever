# Visual identity

The plain-native macOS aesthetic and the rules that enforce it. After a brief experiment with a CLI-derived brand palette (2026-05-01), the app was reverted to system defaults — the rules below are the locked direction.

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
- **Menu bar icon (v2 — 2026-05-06)**: SF Symbol
  `externaldrive.connected.to.line.below` as a template image. Replaces
  the v1 `pills.fill` default; same SF Symbol the app icon uses, so
  Dock + menu bar + the wizard's "USB fingerprint" section header
  share one vocabulary. Picker catalog still ships every prior option
  including `pills.fill`; users who'd customized keep their choice
  (the lazy-default pattern at `SettingsStore.swift:245` never
  persists `defaultSymbol`, so unmodified installs auto-migrate).
- **App icon (v2 — 2026-05-06)**: runtime-generated icy-blue squircle
  (light-blue → white linear gradient, top-edge highlight, 16% black
  inset rim for depth) with a flat Apple-system-blue
  `externaldrive.connected.to.line.below` SF Symbol mark. Reads as
  Sparkle-update-icon family — pale chrome, single saturated mark,
  visible-but-restrained edge. Retires the v1 capsule design (gray
  squircle + rotated pharma pill) entirely. The drawing is in
  `Sources/AVPainRelieverApp/AppIcon.swift` and mirrored in
  `scripts/render-app-icon.swift` (the regen-script copy);
  `Resources/AppIcon.icns` is checked in and bundled by `make-app.sh`.
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

