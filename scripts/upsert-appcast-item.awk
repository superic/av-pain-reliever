# Upsert a single Sparkle <item> block into an appcast.xml feed.
#
# Inputs (set via `awk -v`):
#   item_file       Path to a file containing the fully-formed signed
#                   <item>...</item> block to insert or replace.
#   target_version  The <sparkle:version> string that identifies which
#                   existing item to replace (e.g. "0.2.0.17-dev.1").
#                   If no item with that version exists in the input
#                   feed, the new item is spliced in before </channel>.
#
# Behavior:
#   - Reads the input feed from stdin (or `awk -f ... appcast.xml`).
#   - Buffers each <item>...</item> block, then either replaces it
#     with the contents of item_file (if its <sparkle:version> marker
#     matches target_version) or echoes it unchanged.
#   - Lines outside any <item> block pass through verbatim — including
#     XML comments that happen to mention "<item>" in their prose.
#     The <item> / </item> matchers are anchored to start-of-line
#     (after leading whitespace) precisely so they DON'T fire on
#     comment text like "appends a new <item> here on release."
#     A 2026-05-10 regression let the unanchored regex eat the docs
#     comment and corrupt the live feed; the start-of-line anchors
#     make that class of bug impossible.
#   - If target_version is absent from the input, the new item is
#     spliced in just before </channel> so it appears at the end of
#     the feed.

BEGIN { in_item = 0; item_buf = ""; replaced = 0 }
/^[[:space:]]*<item>/ {
    in_item = 1
    item_buf = $0
    next
}
in_item == 1 && /^[[:space:]]*<\/item>/ {
    item_buf = item_buf "\n" $0
    marker = "<sparkle:version>" target_version "</sparkle:version>"
    if (index(item_buf, marker) > 0) {
        while ((getline line < item_file) > 0) print line
        close(item_file)
        replaced = 1
    } else {
        print item_buf
    }
    in_item = 0
    item_buf = ""
    next
}
in_item == 1 {
    item_buf = item_buf "\n" $0
    next
}
/<\/channel>/ && !replaced {
    while ((getline line < item_file) > 0) print line
    close(item_file)
}
{ print }
