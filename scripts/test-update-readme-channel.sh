#!/bin/bash
# Tiny shell-test harness for scripts/update-readme-channel.awk.
# Exits non-zero on the first failure so test.yml fails loudly.
#
# Each case writes a tiny README fragment to a temp file, runs the
# awk script with the case's `channel` and `tag` parameters, and
# diffs the output against the expected fragment. Idempotency is
# explicitly tested by running the same call twice and confirming
# the second invocation is a no-op.

set -euo pipefail

# bash 3.2 on macOS — no associative arrays, no `mapfile`. Keep it
# simple.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AWK_SCRIPT="$SCRIPT_DIR/update-readme-channel.awk"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

run_case() {
    local name="$1"
    local channel="$2"
    local tag="$3"
    local input="$4"
    local expected="$5"

    printf "%s\n" "$input" > "$TMP/in.md"
    awk -v channel="$channel" -v tag="$tag" -f "$AWK_SCRIPT" "$TMP/in.md" > "$TMP/out.md"

    if [ "$(cat "$TMP/out.md")" = "$expected" ]; then
        printf '  ✓ %s\n' "$name"
        pass=$((pass + 1))
    else
        printf '  ✗ %s\n' "$name"
        printf '    expected:\n'
        printf '%s\n' "$expected" | sed 's/^/      /'
        printf '    got:\n'
        sed 's/^/      /' "$TMP/out.md"
        fail=$((fail + 1))
    fi
}

# Case 1: dev channel updates the dev line, stable + experimental untouched.
run_case "dev tag rewrites only the Dev line" \
    "dev" "v0.2.0.17-dev.5" \
"# Hi
<!-- BEGIN CURRENT RELEASES -->
- **Stable** — [latest](https://github.com/superic/av-pain-reliever/releases/latest)
- **Dev** — [v0.2.0.17-dev.4](https://github.com/superic/av-pain-reliever/releases/tag/v0.2.0.17-dev.4)
- **Experimental** — _no current release_
<!-- END CURRENT RELEASES -->
trailer" \
"# Hi
<!-- BEGIN CURRENT RELEASES -->
- **Stable** — [latest](https://github.com/superic/av-pain-reliever/releases/latest)
- **Dev** — [v0.2.0.17-dev.5](https://github.com/superic/av-pain-reliever/releases/tag/v0.2.0.17-dev.5)
- **Experimental** — _no current release_
<!-- END CURRENT RELEASES -->
trailer"

# Case 2: experimental channel updates the experimental line.
run_case "experimental tag rewrites only the Experimental line" \
    "experimental" "v0.3.0-experimental.1" \
"<!-- BEGIN CURRENT RELEASES -->
- **Stable** — [latest](https://github.com/superic/av-pain-reliever/releases/latest)
- **Dev** — [v0.2.0.17-dev.4](https://github.com/superic/av-pain-reliever/releases/tag/v0.2.0.17-dev.4)
- **Experimental** — _no current release_
<!-- END CURRENT RELEASES -->" \
"<!-- BEGIN CURRENT RELEASES -->
- **Stable** — [latest](https://github.com/superic/av-pain-reliever/releases/latest)
- **Dev** — [v0.2.0.17-dev.4](https://github.com/superic/av-pain-reliever/releases/tag/v0.2.0.17-dev.4)
- **Experimental** — [v0.3.0-experimental.1](https://github.com/superic/av-pain-reliever/releases/tag/v0.3.0-experimental.1)
<!-- END CURRENT RELEASES -->"

# Case 3: empty channel (the stable case) is a total no-op even on
# matching lines. release.yml passes channel="" for bare tags.
run_case "empty channel is a no-op" \
    "" "v1.0.0" \
"<!-- BEGIN CURRENT RELEASES -->
- **Stable** — [latest](https://github.com/superic/av-pain-reliever/releases/latest)
- **Dev** — _no current release_
<!-- END CURRENT RELEASES -->" \
"<!-- BEGIN CURRENT RELEASES -->
- **Stable** — [latest](https://github.com/superic/av-pain-reliever/releases/latest)
- **Dev** — _no current release_
<!-- END CURRENT RELEASES -->"

# Case 4: lines OUTSIDE the markers are never modified, even if they
# look like a Dev or Experimental bullet. Defends against accidental
# global rewrites if a maintainer pastes the snippet into a doc.
run_case "no rewrite outside the markers" \
    "dev" "v9.9.9-dev.1" \
"- **Dev** — outside the block, do not touch
<!-- BEGIN CURRENT RELEASES -->
- **Dev** — _no current release_
<!-- END CURRENT RELEASES -->
- **Dev** — also outside, also untouched" \
"- **Dev** — outside the block, do not touch
<!-- BEGIN CURRENT RELEASES -->
- **Dev** — [v9.9.9-dev.1](https://github.com/superic/av-pain-reliever/releases/tag/v9.9.9-dev.1)
<!-- END CURRENT RELEASES -->
- **Dev** — also outside, also untouched"

# Case 5: empty tag for dev resets the row to "no current release".
# Used when a stable release ships and dev no longer has anything
# newer than stable; the workflow calls with tag="" to clear the row.
run_case "dev with empty tag resets to 'no current release'" \
    "dev" "" \
"<!-- BEGIN CURRENT RELEASES -->
- **Stable** — [latest](https://github.com/superic/av-pain-reliever/releases/latest)
- **Dev** — [v0.2.0.17-dev.5](https://github.com/superic/av-pain-reliever/releases/tag/v0.2.0.17-dev.5)
- **Experimental** — _no current release_
<!-- END CURRENT RELEASES -->" \
"<!-- BEGIN CURRENT RELEASES -->
- **Stable** — [latest](https://github.com/superic/av-pain-reliever/releases/latest)
- **Dev** — _no current release_
- **Experimental** — _no current release_
<!-- END CURRENT RELEASES -->"

# Case 6: same reset behavior for experimental.
run_case "experimental with empty tag resets to 'no current release'" \
    "experimental" "" \
"<!-- BEGIN CURRENT RELEASES -->
- **Experimental** — [v0.3.0-experimental.1](https://github.com/superic/av-pain-reliever/releases/tag/v0.3.0-experimental.1)
<!-- END CURRENT RELEASES -->" \
"<!-- BEGIN CURRENT RELEASES -->
- **Experimental** — _no current release_
<!-- END CURRENT RELEASES -->"

# Case 7: reset is idempotent — calling reset on an already-reset
# row is a no-op.
run_case "reset on an already-reset row is a no-op" \
    "dev" "" \
"<!-- BEGIN CURRENT RELEASES -->
- **Dev** — _no current release_
<!-- END CURRENT RELEASES -->" \
"<!-- BEGIN CURRENT RELEASES -->
- **Dev** — _no current release_
<!-- END CURRENT RELEASES -->"

# Case 8: idempotency — running twice with the same inputs is the
# same as running once. Catches a class of bug where a sub() pattern
# accidentally re-eats its own output.
INPUT="<!-- BEGIN CURRENT RELEASES -->
- **Dev** — _no current release_
<!-- END CURRENT RELEASES -->"
EXPECTED="<!-- BEGIN CURRENT RELEASES -->
- **Dev** — [v0.5-dev.1](https://github.com/superic/av-pain-reliever/releases/tag/v0.5-dev.1)
<!-- END CURRENT RELEASES -->"
printf "%s\n" "$INPUT" > "$TMP/in.md"
awk -v channel="dev" -v tag="v0.5-dev.1" -f "$AWK_SCRIPT" "$TMP/in.md" > "$TMP/once.md"
awk -v channel="dev" -v tag="v0.5-dev.1" -f "$AWK_SCRIPT" "$TMP/once.md" > "$TMP/twice.md"
if [ "$(cat "$TMP/once.md")" = "$EXPECTED" ] && [ "$(cat "$TMP/twice.md")" = "$EXPECTED" ]; then
    printf '  ✓ idempotent: second run leaves output unchanged\n'
    pass=$((pass + 1))
else
    printf '  ✗ idempotent: second run changed output\n'
    fail=$((fail + 1))
fi

echo
echo "Passed: $pass"
echo "Failed: $fail"
[ "$fail" -eq 0 ]
