# Virtual Camera — local dev workflow

Recipe for building, activating, and testing the v0.2.0 Camera
Extension on a development Mac. Distribution flow lives in
`docs/RELEASING.md` once we get there; for now this is the loop
used while the feature is on `feature/virtual-camera`.

The recommended path uses your normal Developer ID Application
certificate and a Developer ID provisioning profile — same trust
chain end users will see in the eventual public release. No SIP
disable, no developer mode, no ad-hoc shenanigans. There's a
fallback at the bottom for the ad-hoc + developer-mode + SIP-off
workflow if you need it for some reason.

## One-time setup

### 1. App IDs at developer.apple.com

Sign in to [developer.apple.com](https://developer.apple.com) with
the Apple ID for your developer account (the personal account
e@ericwillis.com — *not* the BACtrack one).

Go to **Certificates, Identifiers & Profiles → Identifiers**:

- **`com.ericwillis.avpainreliever`** (the host app):
    - Should already exist from v0.1.x. If not, create it as type
      "App IDs / App."
    - Edit it. Under **Capabilities**, check **System Extension**.
      Save.
- **`com.ericwillis.avpainreliever.CameraExtension`** (the
  extension):
    - Create it as type "App IDs / App."
    - No special capabilities needed beyond the defaults.

The bundle IDs must be a parent/child pair — if the host app's ID
changes, the extension's ID has to change to match.

### 2. Provisioning profile

Still at developer.apple.com, go to **Profiles → New**:

- Type: **Developer ID** (under Distribution).
- App ID: `com.ericwillis.avpainreliever`.
- Certificate: your Developer ID Application cert (the same one
  v0.1.x uses).
- Name: something descriptive like
  "AV Pain Reliever Developer ID."
- Download the `.provisionprofile` file.

Drop it into the repo at:

```
Resources/AVPainReliever.provisionprofile
```

This path is gitignored — it's team-specific and regenerable, no
need to commit. Each developer / CI runner provisions their own.

### 3. Confirm your signing identity is in keychain

The build script reads `$MAC_CERT_NAME` to pick the cert. Same one
you use for v0.1.x. Verify it's in keychain:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see the cert with your team ID in parens. Note the
exact display name — that's what `MAC_CERT_NAME` should be set to.

## Build + install loop

### Build the bundle

From the repo root:

```sh
MAC_CERT_NAME="Developer ID Application: Eric Willis (TEAMID)" \
    scripts/make-app-with-virtual-camera.sh
```

Replace the cert name with whatever `security find-identity`
showed you. The script:
1. Builds both Swift products (universal arm64+x86_64).
2. Assembles `AVPainReliever.app` and the embedded
   `.systemextension` bundle.
3. Embeds Sparkle.framework + the provisioning profile.
4. Signs inside-out: Sparkle nested → Sparkle.framework →
   Camera Extension → host app.

Output: `dist/AVPainReliever.app`. The script will fail loudly if
the provisioning profile is missing.

### Move into /Applications

System extensions can only be activated by apps running from
`/Applications`. macOS rejects activation requests from elsewhere
with an unhelpful error.

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

macOS will prompt for approval in System Settings → Privacy &
Security → "Allow extension from AV Pain Reliever." Click Allow.

Watch Console.app filtered by "AVPR" for activation lifecycle
messages.

Verify it's registered:

```sh
systemextensionsctl list
```

You should see one entry under `com.apple.cmio.cmioextension` for
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
MAC_CERT_NAME="…" scripts/make-app-with-virtual-camera.sh
ditto dist/AVPainReliever.app /Applications/AVPainReliever.app
# Optional: re-activate if the extension was uninstalled
AVPR_ACTIVATE_VIRTUAL_CAMERA=1 open /Applications/AVPainReliever.app
```

macOS handles in-place upgrades transparently when the bundle ID
matches and the new build is properly signed — no need to
uninstall first for routine code changes.

## Uninstall / clean slate

```sh
systemextensionsctl uninstall <TEAMID> com.ericwillis.avpainreliever.CameraExtension
```

Replace `<TEAMID>` with your Apple Developer team ID. Confirm with
`systemextensionsctl list` — entry should be gone.

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
  is missing `com.apple.developer.system-extension.install`. Either
  the v0.2.0 entitlements file
  (`Resources/AVPainReliever-WithVirtualCamera.entitlements`) wasn't
  used by the build script, or the provisioning profile doesn't
  declare the entitlement. Confirm both.
- **"No matching profile found"** at codesign: the App ID in the
  profile doesn't match the bundle's CFBundleIdentifier. Check the
  profile is bound to `com.ericwillis.avpainreliever`, not some
  other ID.
- **"Extension does not appear in Zoom"**: check
  `systemextensionsctl list`. If it's listed but Zoom can't see it,
  quit and relaunch Zoom — Zoom caches its device list. If it's
  not listed, re-run the activation step and check Console for
  `[AVPR]` log lines.
- **"Activation request never returns"**: usually means the user
  approval prompt is waiting in System Settings → Privacy &
  Security. Check that pane and click Allow.
- **"App can't be activated because it's not in /Applications"**:
  see the "Move into /Applications" step above.
- **"Extension found but not in /Library/SystemExtensions"** in
  Console: macOS tried to copy the extension out of the app bundle
  and failed — usually because the app was launched from a
  non-`/Applications` path or the user rejected the approval
  prompt. Uninstall, fix the path, re-activate.

## Fallback: ad-hoc + developer mode (only if you really must)

If you don't want to (or can't) provision properly — say you're
quickly testing on a machine that isn't yours and Apple ID setup
isn't worth it — you can use ad-hoc signing with developer mode
enabled. Cost: SIP has to be **disabled**, which is a real
security tradeoff. Don't do this on your daily driver unless you
plan to re-enable SIP afterward and remember to.

1. Reboot to Recovery (hold Power on Apple Silicon, ⌘R on Intel).
2. In Recovery Terminal: `csrutil disable`.
3. Reboot back to macOS.
4. `sudo systemextensionsctl developer on`.
5. Build without `MAC_CERT_NAME`:
   `scripts/make-app-with-virtual-camera.sh`.
6. Continue with the normal install + activate steps above.
7. When done with v0.2.0 dev: Recovery → `csrutil enable` →
   reboot. Don't skip this.

The ad-hoc path bypasses Path A's provisioning checks but means
your build doesn't represent what end users will run, so anything
that worked here might still break in distribution. Use Path A
unless there's a specific reason not to.
