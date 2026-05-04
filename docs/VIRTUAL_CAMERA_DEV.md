# Virtual Camera — local dev workflow

Recipe for building, activating, and testing the v0.2.0 Camera
Extension on a development Mac. Distribution flow lives in
`docs/RELEASING.md` once we get there; for now this is the loop
used while the feature is on `feature/virtual-camera`.

## One-time setup

### 1. Enable system-extension developer mode

```sh
sudo systemextensionsctl developer on
```

This relaxes the production-entitlement requirement so locally-
signed extensions (no Apple-issued provisioning profile, no
notarization) can install and run. Check status with
`systemextensionsctl developer`. Leave it on for the duration of
v0.2.0 development.

### 2. Confirm SIP is on

System extensions need SIP **on**, not off. Check with
`csrutil status`. Disabling SIP for kext development is unrelated
and would actually break the system-extension flow.

## Build + install loop

### Build the bundle

From the repo root:

```sh
scripts/make-app-with-virtual-camera.sh
```

Produces `dist/AVPainReliever.app` with the embedded extension at
`Contents/Library/SystemExtensions/com.ericwillis.avpainreliever.CameraExtension.systemextension`.
Ad-hoc-signed unless `MAC_CERT_NAME` is set — fine for dev.

### Move into /Applications

System extensions can only be activated by apps living in
`/Applications/`. The OS rejects activation requests from
elsewhere with an unhelpful error.

```sh
rm -rf /Applications/AVPainReliever.app
ditto dist/AVPainReliever.app /Applications/AVPainReliever.app
```

### Activate

The activation is gated by an env var so it doesn't fire on every
launch:

```sh
AVPR_ACTIVATE_VIRTUAL_CAMERA=1 open /Applications/AVPainReliever.app
```

Watch Console.app filtered by "AVPR" for activation lifecycle
messages. macOS may prompt for approval in System Settings →
Privacy & Security → "Allow extension from AV Pain Reliever" — click
Allow.

Verify it's registered:

```sh
systemextensionsctl list
```

You should see one entry under
`com.apple.cmio.cmioextension` for
`com.ericwillis.avpainreliever.CameraExtension` with state
`activated enabled`.

### Test in Zoom (or any AVCapture client)

Open Zoom → Settings → Video → Camera dropdown. "AV Pain Reliever"
should appear. Selecting it shows a black 1280×720 frame at 30 fps.

FaceTime, Photo Booth, Safari `getUserMedia` test pages, and any
other AVCapture-modern client also work.

## Iteration loop

After code changes:

```sh
scripts/make-app-with-virtual-camera.sh
ditto dist/AVPainReliever.app /Applications/AVPainReliever.app
# Optional: re-activate if the extension was uninstalled
AVPR_ACTIVATE_VIRTUAL_CAMERA=1 open /Applications/AVPainReliever.app
```

macOS handles in-place upgrades transparently when the bundle ID
matches and developer mode is on — no need to uninstall first for
routine code changes.

## Uninstall / clean slate

```sh
systemextensionsctl uninstall - com.ericwillis.avpainreliever.CameraExtension
```

The leading `-` is the team identifier placeholder for ad-hoc
builds. For Developer-ID-signed builds, replace with your team ID
(e.g., `ABC1234DEF`).

Confirm with `systemextensionsctl list` — entry should be gone.

## Logs

Extension log output goes to the unified logging system under
the extension's bundle ID. Tail with:

```sh
log stream --predicate 'subsystem == "com.ericwillis.avpainreliever.CameraExtension"' --style compact
```

Or open Console.app, select "AV Pain Reliever Camera Extension"
in the sidebar.

## Common failure modes

- **"Code signature missing entitlements"** on activation: host app
  is missing `com.apple.developer.system-extension.install`. The
  v0.2.0 entitlements file
  (`Resources/AVPainReliever-WithVirtualCamera.entitlements`)
  declares it; confirm the build script picked the right one.
- **"Extension does not appear in Zoom"**: check
  `systemextensionsctl list`. If it's listed but Zoom can't see it,
  quit and relaunch Zoom — Zoom caches its device list. If it's
  not listed, re-run the activation step and check Console for
  `[AVPR]` log lines.
- **"Activation request never returns"**: usually means the user
  approval prompt is waiting in System Settings → Privacy &
  Security. Check that pane and click Allow.
- **"App can't be activated because it's not in /Applications"**:
  see the "Move into /Applications" step above. System extensions
  refuse to load from anywhere else.
