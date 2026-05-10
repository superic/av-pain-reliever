#!/usr/bin/env bash
# Regression tests for scripts/upsert-appcast-item.awk.
#
# Why these exist: a 2026-05-10 publish run (v0.2.0.17-dev.1)
# corrupted appcast.xml by matching `<item>` inside a comment block,
# entering item-buffer mode mid-comment, then overwriting the buffer
# when the real `<item>` opened. The resulting unterminated `<!--`
# made Sparkle's feed parser bail with "An error occurred while
# parsing the update feed." These tests pin the hardened
# start-of-line anchors so that regression class can't slip back in.
#
# Runs three fixture-driven checks:
#   1. Comment with `<item>` in prose is preserved verbatim, new
#      item is spliced before </channel> (the live-broken scenario).
#   2. Existing item with matching <sparkle:version> is REPLACED
#      with the new signed item, not duplicated.
#   3. Output of every scenario passes xmllint.
#
# Bash 3.2 compatible (no associative arrays, no `${var,,}`,
# nothing fancy), per the project's macOS-stock-bash rule.
#
# Usage: scripts/test-upsert-appcast.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AWK_SCRIPT="$ROOT/scripts/upsert-appcast-item.awk"

if [ ! -f "$AWK_SCRIPT" ]; then
    echo "FAIL: $AWK_SCRIPT not found" >&2
    exit 2
fi

if ! command -v xmllint >/dev/null 2>&1; then
    echo "FAIL: xmllint required but not on PATH" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# ----- helpers --------------------------------------------------------------

# Reusable signed item the tests splice in.
cat > "$WORK/new-item.xml" <<'EOF'
        <item>
            <title>Version 9.9.9-test</title>
            <pubDate>Sun, 10 May 2026 22:00:00 +0000</pubDate>
            <sparkle:channel>dev</sparkle:channel>
            <sparkle:version>9.9.9-test</sparkle:version>
            <sparkle:shortVersionString>9.9.9-test</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="https://example.invalid/x.zip"
                       type="application/octet-stream"
                       sparkle:edSignature="AAAA" length="100" />
        </item>
EOF

# Run the awk script and capture stdout to $1; stdin is the fixture path.
run_upsert() {
    local out="$1"
    local fixture="$2"
    local version="$3"
    awk \
        -v item_file="$WORK/new-item.xml" \
        -v target_version="$version" \
        -f "$AWK_SCRIPT" \
        "$fixture" > "$out"
}

assert_xml_valid() {
    local file="$1"
    local label="$2"
    if xmllint --noout "$file" 2>/dev/null; then
        echo "  PASS: $label parses as XML"
        pass=$((pass + 1))
    else
        echo "  FAIL: $label is not valid XML"
        xmllint --noout "$file" 2>&1 | sed 's/^/    /'
        fail=$((fail + 1))
    fi
}

assert_grep() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    if grep -q "$pattern" "$file"; then
        echo "  PASS: $label"
        pass=$((pass + 1))
    else
        echo "  FAIL: $label (pattern not found: $pattern)"
        fail=$((fail + 1))
    fi
}

assert_count() {
    local file="$1"
    local pattern="$2"
    local expected="$3"
    local label="$4"
    local actual
    actual=$(grep -c "$pattern" "$file" || true)
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $label (count=$actual)"
        pass=$((pass + 1))
    else
        echo "  FAIL: $label (expected count=$expected, got=$actual)"
        fail=$((fail + 1))
    fi
}

# ----- fixture 1: comment with <item> in prose preserved --------------------

echo "Test 1: comment containing <item> in prose is preserved verbatim"

cat > "$WORK/fixture-1.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Feed</title>
        <!--
            Stub feed. The workflow appends a new <item> here on
            every signed-and-notarized release. Until the first tag
            lands, an installed app fetching this feed correctly
            resolves to "you're up to date."
        -->
        <item>
            <title>Version 1.0.0</title>
            <sparkle:version>1.0.0</sparkle:version>
        </item>
    </channel>
</rss>
EOF

run_upsert "$WORK/out-1.xml" "$WORK/fixture-1.xml" "9.9.9-test"
assert_xml_valid "$WORK/out-1.xml" "fixture 1 output"
assert_grep "$WORK/out-1.xml" "appends a new <item> here" "comment middle survives"
assert_grep "$WORK/out-1.xml" "    -->" "comment closer survives"
assert_grep "$WORK/out-1.xml" "9.9.9-test" "new item spliced in"
assert_count "$WORK/out-1.xml" "<sparkle:version>" 2 "exactly two items in output"

# ----- fixture 2: replace existing item with same version -------------------

echo "Test 2: existing item with matching version is REPLACED, not duplicated"

cat > "$WORK/fixture-2.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Feed</title>
        <item>
            <title>Version 1.0.0</title>
            <sparkle:version>1.0.0</sparkle:version>
        </item>
        <item>
            <title>Version 9.9.9-test (OLD)</title>
            <sparkle:version>9.9.9-test</sparkle:version>
        </item>
    </channel>
</rss>
EOF

run_upsert "$WORK/out-2.xml" "$WORK/fixture-2.xml" "9.9.9-test"
assert_xml_valid "$WORK/out-2.xml" "fixture 2 output"
assert_count "$WORK/out-2.xml" "<sparkle:version>9.9.9-test</sparkle:version>" 1 \
    "9.9.9-test appears exactly once (replaced, not appended)"
assert_grep "$WORK/out-2.xml" "<sparkle:version>1.0.0</sparkle:version>" \
    "untouched 1.0.0 item still present"
# The replacement should carry the new signature, not the OLD title.
if ! grep -q "OLD" "$WORK/out-2.xml"; then
    echo "  PASS: stale 'OLD' marker dropped (replacement succeeded)"
    pass=$((pass + 1))
else
    echo "  FAIL: stale 'OLD' marker still in output"
    fail=$((fail + 1))
fi

# ----- fixture 3: empty feed (no items yet) ---------------------------------

echo "Test 3: empty feed (no existing items) splices new item before </channel>"

cat > "$WORK/fixture-3.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Feed</title>
        <description>Empty feed.</description>
    </channel>
</rss>
EOF

run_upsert "$WORK/out-3.xml" "$WORK/fixture-3.xml" "9.9.9-test"
assert_xml_valid "$WORK/out-3.xml" "fixture 3 output"
assert_grep "$WORK/out-3.xml" "9.9.9-test" "new item appears in previously-empty feed"
assert_count "$WORK/out-3.xml" "<sparkle:version>" 1 "exactly one item after splice"

# ----- summary --------------------------------------------------------------

echo
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
    exit 1
fi
