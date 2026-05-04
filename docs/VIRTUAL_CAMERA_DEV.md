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
the personal Apple ID account (e@ericwillis.com).

Go to **Certificates, Identifiers & Profiles → Identifiers**.
Register two App IDs:

- **`com.ericwillis.avpainreliever`** (host app):
    - Description: "AV Pain Reliever"
    - Capabilities: tick **System Extension** and **App Groups**.
- **`com.ericwillis.avpainreliever.CameraExtension`** (extension):
    - Description: "AV Pain Reliever Camera Extension"
    - Capabilities: tick **App Groups**.

Bundle IDs must be a parent/child pair — if the host changes, the
extension's ID has to change to match.

### 2. App Group

Still in **Identifiers**, click **+** → **App Groups** →
Continue:

- Description: "AV Pain Reliever Group"
- Identifier: `group.com.ericwillis.avpainreliever`

Apple requires the `group.` prefix on new App Groups. The
team-prefixed form (`HLH4LEWS9S.group.com.ericwillis.avpainreliever`)
is what ends up in entitlements and the extension's
`CMIOExtensionMachServiceName`.

Then go back to each App ID, click **Configure** next to App
Groups, and select the newly registered group. Save.

### 3. Provisioning profile

**Profiles → New**:

- Type: **Developer ID** (under Distribution).
- App ID: `com.ericwillis.avpainreliever`.
- Certificate: your Developer ID Application cert (the same one
  v0.1.x uses).
- Name: "AV Pain Reliever Developer ID" or similar.
- Download.

Drop it into the repo at:

```
Resources/AVPainReliever.provisionprofile
```

This path is gitignored — it's team-specific and regenerable, no
need to commit. Each developer / CI runner provisions their own.

If you later add or change a capability on the host App ID, the
profile invalidates — re-download and overwrite.

### 4. Confirm your signing identity is in keychain

The build script reads `$MAC_CERT_NAME` to pick the cert. Same one
you use for v0.1.x. Verify it's in keychain:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see the cert with your team ID in parens. Note the
exact display name — that's what `MAC_CERT_NAME` should be set to.

### 5. Notarization keychain profile

System extensions can't be activated by macOS without a notarized
bundle, even with valid Developer ID signing. The build script
runs notarization via `xcrun notarytool` against a keychain
profile you've already set up for v0.1.x — see
`docs/RELEASING.md` for the one-time
`xcrun notarytool store-credentials avpain-notary` step.

If you've ever notarized a v0.1.x release locally, you have it.
Confirm:

```sh
xcrun notarytool history --keychain-profile avpain-notary
```

## Build + install loop

### Build the bundle

From the repo root:

```sh
MAC_CERT_NAME="Developer ID Application: Eric Willis (TEAMID)" \
    NOTARIZE_KEYCHAIN_PROFILE=avpain-notary \
    scripts/make-app-with-virtual-camera.sh
```

Replace the cert name with whatever `security find-identity`
showed you. The script:
1. Builds both Swift products (universal arm64+x86_64).
2. Assembles `AVPainReliever.app` and the embedded
   `.systemextension` bundle, substituting the team ID into the
   extension's `CMIOExtensionMachServiceName`.
3. Embeds Sparkle.framework + the provisioning profile.
4. Signs inside-out: Sparkle nested → Sparkle.framework →
   Camera Extension → host app.
5. Notarizes via `xcrun notarytool` and staples the ticket.

Output: `dist/AVPainReliever.app`. Notarization adds ~30s–2 min
per build. If you're iterating on something that doesn't need
fresh activation, omit `NOTARIZE_KEYCHAIN_PROFILE` to skip — the
script will warn that the build can't activate as a system
extension. The script will fail loudly if the provisioning
profile is missing.

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
launch. **Important**: pass it via `--env`, not the shell-prefix
form — `open` strips the calling shell's environment when handing
off to launchd.

```sh
open --env AVPR_ACTIVATE_VIRTUAL_CAMERA=1 /Applications/AVPainReliever.app
```

macOS prompts you to approve in **System Settings → General →
Login Items & Extensions → Camera Extensions**. Find "AV Pain
Reliever Camera Extension" and toggle it on.

Watch sysextd state transitions:

```sh
log stream --predicate 'process == "sysextd"' --style compact
```

Healthy sequence: `validating → validating_by_category → activated_waiting_for_user → activated_enabled` after you click Allow.

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
pkill -f AVPainRelieverApp
MAC_CERT_NAME="…" NOTARIZE_KEYCHAIN_PROFILE=avpain-notary \
    scripts/make-app-with-virtual-camera.sh
rm -rf /Applications/AVPainReliever.app
ditto dist/AVPainReliever.app /Applications/AVPainReliever.app
# Re-activate if the extension was uninstalled or the bundle ID changed:
open --env AVPR_ACTIVATE_VIRTUAL_CAMERA=1 /Applications/AVPainReliever.app
```

macOS handles in-place upgrades transparently when the bundle ID
matches and the new build is properly signed and notarized — no
need to uninstall first for routine code changes.

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

Each error below is the message you'll see in the `sysextd` log
stream, followed by what to fix.

- **"system extension does not appear to belong to any extension
  categories"**: the extension's Info.plist is missing the
  `CMIOExtension` dict. The build script substitutes
  `__TEAM_ID__` into the Mach service name; if you see literal
  `__TEAM_ID__` in the bundle, `MAC_CERT_NAME` parsing failed.
- **"bundle code signature is not valid - does not satisfy
  requirement: -67050"** with **"Error checking with
  notarization daemon"**: the build wasn't notarized. Set
  `NOTARIZE_KEYCHAIN_PROFILE=avpain-notary` and rebuild.
- **"invalid mach service name or is not signed, the value must
  be prefixed with one of the App Groups in the entitlement"**:
  the App Group in the extension's entitlements doesn't match the
  prefix of the `CMIOExtensionMachServiceName`. Both should be
  `HLH4LEWS9S.group.com.ericwillis.avpainreliever`.
- **"Failed to parse entitlements: AMFIUnserializeXML: syntax
  error"** during codesign: the entitlements plist contains XML
  comments. AMFI's parser rejects them — strip all `<!-- -->`
  blocks.
- **State stuck at `activated_waiting_for_user`**: open System
  Settings → General → Login Items & Extensions → Camera
  Extensions and toggle the extension on. The state advances to
  `activated_enabled` after you approve.
- **"No matching profile found"** at codesign: the App ID in the
  provisioning profile doesn't match the bundle's
  CFBundleIdentifier. Check the profile is bound to
  `com.ericwillis.avpainreliever` and includes the App Groups
  capability.
- **Extension is `[activated enabled]` but doesn't appear in
  Zoom**: quit and relaunch Zoom — its camera-device cache is
  populated at process start. FaceTime and browsers re-enumerate
  per call.
- **App didn't get the env var**: the shell-prefix form
  (`AVPR_ACTIVATE_VIRTUAL_CAMERA=1 open ...`) sets the var only
  for `open` itself. Use `open --env AVPR_ACTIVATE_VIRTUAL_CAMERA=1`.

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
