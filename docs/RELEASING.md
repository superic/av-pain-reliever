# Releasing AV Pain Reliever

The release pipeline is defined in `.github/workflows/release.yml` and
triggered by pushing a `v*.*.*` git tag. Until the seven GitHub Secrets
listed below are populated, every step that depends on Apple credentials
or the Sparkle private key skips with a warning, so a `v0.0.0-dryrun`
tag can verify the workflow shape without exposing anything sensitive.

This doc is the runbook for getting from "secrets unset" to "first
real signed release."

---

## One-time setup

You only do this once for the lifetime of the project. After it's done,
shipping a release is `git tag vX.Y.Z && git push --tags`.

### 1. Apple Developer Program enrollment

1. Sign up at <https://developer.apple.com/programs/> ($99/yr).
   Approval takes 24–48h.
2. Once approved, generate a **Developer ID Application** certificate:
   <https://developer.apple.com/account/resources/certificates> →
   **+** → "Developer ID Application." Follow the CSR flow (Keychain
   Access → Certificate Assistant → Request a Certificate from a
   Certificate Authority). Download the `.cer`, double-click to add
   to your login keychain.
3. In Keychain Access, find the new identity ("Developer ID
   Application: Eric Willis (TEAMID)"), right-click → **Export**, save
   as `cert.p12` with a strong password.
4. Generate an **app-specific password** for `notarytool`:
   <https://appleid.apple.com> → Sign-In and Security → App-Specific
   Passwords. Label it `AVPainReliever notarytool`. Save it somewhere
   safe.
5. Note your **Team ID**: <https://developer.apple.com/account> →
   Membership.

### 2. Sparkle EdDSA keypair

Sparkle 2 verifies downloaded updates with an EdDSA signature. We
generate the keypair locally, embed the public key in `Info.plist`,
and store the private key as a GitHub Secret.

```sh
# Generate, store private key in your login keychain under the
# "avpainreliever" account name. Prints the public key + Info.plist
# snippet to stdout.
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account avpainreliever

# Replace the __SPARKLE_PUBLIC_KEY__ placeholder in Resources/Info.plist
# with the printed key (the SUPublicEDKey base64 string), then commit.
$EDITOR Resources/Info.plist
git add Resources/Info.plist
git commit -m "Embed Sparkle EdDSA public key"
git push

# Export the private key for the GitHub Secret. The output is a single
# base64 line — keep it secret.
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account avpainreliever -x sparkle-private-key.txt
```

Stash a copy of `sparkle-private-key.txt` in 1Password (named e.g.
"AV Pain Reliever — Sparkle private key"), then **delete the local
file** once it's safe.

> **Warning:** Re-running `generate_keys` without `-p` or `-x` may
> generate a *different* key, breaking auto-updates for everyone
> already on the old one. Treat this key as permanent.

### 3. GitHub Secrets

In the repo: **Settings → Secrets and variables → Actions → New
repository secret**. Add these seven:

| Name                          | Source                                                                 |
| ----------------------------- | ---------------------------------------------------------------------- |
| `MACOS_CERTIFICATE`           | `base64 -i cert.p12 \| pbcopy` — paste                                  |
| `MACOS_CERTIFICATE_PASSWORD`  | The password you set when exporting the `.p12`                          |
| `MACOS_KEYCHAIN_PASSWORD`     | Random — `openssl rand -base64 32 \| pbcopy`                            |
| `APPLE_ID`                    | Your developer Apple ID email (the one you used to enrol in the Developer Program) |
| `APPLE_ID_PASSWORD`           | App-specific password from step 4 above                                 |
| `APPLE_TEAM_ID`               | 10-char Team ID from step 5 above                                       |
| `SPARKLE_PRIVATE_KEY`         | `cat sparkle-private-key.txt \| pbcopy` — paste raw (no extra newlines) |

Or via `gh` (run from the repo root once `gh auth login` is set up):

```sh
gh secret set MACOS_CERTIFICATE          < <(base64 -i cert.p12)
gh secret set MACOS_CERTIFICATE_PASSWORD --body 'your-p12-password'
gh secret set MACOS_KEYCHAIN_PASSWORD    --body "$(openssl rand -base64 32)"
gh secret set APPLE_ID                   --body 'you@example.com'
gh secret set APPLE_ID_PASSWORD          --body 'xxxx-xxxx-xxxx-xxxx'
gh secret set APPLE_TEAM_ID              --body 'XXXXXXXXXX'
gh secret set SPARKLE_PRIVATE_KEY        < sparkle-private-key.txt
```

After setting secrets, delete `cert.p12` and `sparkle-private-key.txt`
from your working directory.

---

## Cutting a release

1. Bump the version. There's no version source file — the `git tag` is
   the version. Verify `Resources/Info.plist` doesn't have anything
   stale.
2. **(Recommended)** Pre-create the GitHub release as a draft with
   curated release notes — these become the "What's New" panel in
   Sparkle's update window:
   ```sh
   gh release create v0.1.11 --draft --notes "$(cat <<'EOF'
   ## What's new
   - Confetti when you open About
   - Personalised welcome greeting
   - Update window comes to the front when checking
   EOF
   )"
   ```
   If you skip this step, the workflow falls back to
   `--generate-notes` (a "What's Changed" commit list).
3. Tag and push:
   ```sh
   git tag v0.1.11
   git push origin v0.1.11
   ```
4. Watch the run: `gh run watch` (or in the browser).
5. Once the workflow completes:
   - The release is in **draft** state — review and publish it
     manually via the Releases page.
   - `appcast.xml` on `main` has a new `<item>` referencing the
     release asset. Existing installs see the update on their next
     Sparkle check (or via Advanced → Check for Updates…), and the
     update window shows the release notes panel sourced from your
     GitHub release body.

### First-tag checklist

For the very first signed release, do a full smoke test:

- [ ] Workflow finished green
- [ ] `dist/AVPainReliever.app.zip` is attached to the draft release
- [ ] Download it on a fresh machine (or after `xattr -d com.apple.quarantine` on yours), unzip, drag to `/Applications`
- [ ] Double-click — no Gatekeeper "this app can't be opened" prompt
- [ ] Pill icon shows in the menu bar; engine works as expected
- [ ] Tag a `v0.1.1` with a one-line README change to exercise the auto-update path
- [ ] On the v0.1.0 install: Advanced → Check for Updates… → Sparkle finds v0.1.1, downloads, installs cleanly

### Dry-run (no Apple credentials)

Useful while waiting for Developer Program approval, or for sanity-
checking workflow changes:

```sh
git tag v0.0.0-dryrun
git push origin v0.0.0-dryrun
```

The build runs end-to-end; codesign falls back to ad-hoc, notarization
+ appcast steps log skipped, the draft release is created with an
unsigned `.app.zip` for inspection. Delete the tag + draft release
afterwards:

```sh
git push origin :refs/tags/v0.0.0-dryrun
gh release delete v0.0.0-dryrun --yes --cleanup-tag
```

---

## Local release (no GitHub Actions)

`scripts/make-app.sh` builds a signed `.app` bundle with a Developer
ID identity available in your local keychain:

```sh
MAC_CERT_NAME="Developer ID Application: Eric Willis (TEAMID)" \
VERSION=0.1.0 \
scripts/make-app.sh
```

You'll still need to notarize manually (`xcrun notarytool submit
dist/AVPainReliever.app.zip --keychain-profile <profile-name> --wait`)
and EdDSA-sign the appcast item (`scripts/sign-appcast.sh`). The
GitHub Actions path is the supported one; this is here for emergencies.

---

## Troubleshooting

- **Notarization fails with "The signature does not include a secure
  timestamp."** — `make-app.sh` already passes `--timestamp` to
  codesign. If this happens in CI, the runner's network probably can't
  reach Apple's timestamp server. Re-run.
- **Notarization fails with "bundle format is ambiguous (could be
  app or framework)."** — A nested bundle didn't get signed. Check
  that `Resources/AVPainReliever.entitlements` only mentions the main
  app and that `make-app.sh`'s `SPARKLE_NESTED` array has every helper
  listed.
- **Gatekeeper still blocks the .app on a fresh download.** — Either
  notarization didn't actually succeed or the staple step was skipped.
  Check the workflow's "Notarize and staple" step; verify with
  `spctl -a -vvv -t exec dist/AVPainReliever.app`.
- **Sparkle reports "EdDSA public key is not valid for AV Pain
  Reliever"** in the running app. The `SUPublicEDKey` in
  `Resources/Info.plist` is still `__SPARKLE_PUBLIC_KEY__` or got
  garbled. Re-run step 2 of the one-time setup, replace the
  placeholder, commit.

---

## Post-mortem: lessons from v0.1.0

These all bit us on the very first signed-release tag. Captured here
so the second person doing this — or you, six months from now — can
short-circuit them.

### 1. Sparkle's `Autoupdate` helper has to be in `SPARKLE_NESTED`

The notarytool log on the first v0.1.0 attempt called out the
`Sparkle.framework/Versions/B/Autoupdate` Mach-O binary as
unsigned and lacking a secure timestamp. It's a sibling of the
framework's main `Sparkle` binary inside `Versions/B/` — easy to
miss because it isn't a bundle, just a bare executable. The fix
is one line in `scripts/make-app.sh`:

```sh
SPARKLE_NESTED=(
    "$SPARKLE_DIR/XPCServices/Downloader.xpc"
    "$SPARKLE_DIR/XPCServices/Installer.xpc"
    "$SPARKLE_DIR/Updater.app"
    "$SPARKLE_DIR/Autoupdate"     # <-- add this when bumping Sparkle
)
```

If you bump the Sparkle dependency, walk
`Sparkle.framework/Versions/B/` and confirm every nested bundle
and bare executable in there is named in `SPARKLE_NESTED`. Anything
new will surface the same notarization error.

Diagnostic command for any future "Invalid" notary submission:

```sh
xcrun notarytool log <submission-id> \
    --keychain-profile avpain-notary
```

The submission ID is printed in the failed step's log. Save Apple's
JSON — it lists the exact path + architecture of every flagged
binary, which makes the fix obvious.

### 2. Double-clicking a `.cer` can fail with error `-25294`

When you install the Developer ID certificate by double-clicking
`developerID_application.cer`, Keychain Access tries to import it
into whichever keychain is currently selected in the sidebar. If
that's **iCloud**, you get error `-25294` (`errSecNoDefaultKeychain`-
adjacent — the iCloud keychain refuses the cert). The fix:

```sh
security import ~/Downloads/developerID_application.cer \
    -k ~/Library/Keychains/login.keychain-db
```

Targets `login` explicitly, no GUI ambiguity. Verify with:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 3. Save notarytool creds as a keychain profile

Once you have the app-specific password from
<https://appleid.apple.com>, store it as a `notarytool` keychain
profile right away — Apple only shows the password once, and you'll
want it again every time you debug a notarization (see Lesson 1):

```sh
xcrun notarytool store-credentials avpain-notary \
    --apple-id you@example.com \
    --team-id XXXXXXXXXX
# (interactively prompts for the app-specific password)
```

After that, every local `xcrun notarytool` invocation can use
`--keychain-profile avpain-notary` instead of typing the password
again. The CI workflow doesn't need this — it has the secret
plumbed through `APPLE_ID_PASSWORD` already.

### 4. Don't paste shell commands containing emails out of a markdown
   client

Several chat / note-taking apps autolink bare email addresses to
`[you@example.com](mailto:you@example.com)`. When you copy that
text and paste it into a terminal, the brackets and `mailto:` come
along for the ride and `gh secret set APPLE_ID` ends up storing a
broken value. Either type the email directly, or use stdin:

```sh
gh secret set APPLE_ID
# at the prompt: type the email by hand
```

`gh secret set` (no `--body`) reads the value from stdin/prompt
without going through any markdown layer.

### 5. The first tag will probably fail. Plan for it.

Notarization is the moment Apple actually inspects the bundle, and
small signing miss-matches that ad-hoc-signed dev builds happily
ignore become hard errors. Budget a tag-fail-fix-tag-fail-fix loop
into the schedule. The release workflow is fast (~90s through
`Build .app`, then ~30-60s in notarytool), so each iteration is
cheap. Don't pre-publish the draft release until after the smoke
test in **First-tag checklist** above.
