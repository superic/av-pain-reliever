# Update the dev or experimental release line inside a README's
# "BEGIN CURRENT RELEASES" / "END CURRENT RELEASES" block. The stable
# line is never modified by this script — it uses GitHub's
# /releases/latest redirect, which is always correct without a tag
# fix-up. Called from .github/workflows/appcast-publish.yml on every
# release publish so the README always reflects the most recent
# release per channel.
#
# Inputs (set via `awk -v`):
#   channel  "dev" or "experimental" — which line to rewrite. If
#            channel is anything else (e.g. empty for stable),
#            every line passes through unchanged.
#   tag      The new tag (e.g. "v0.2.0.17-dev.5"). The URL gets
#            rewritten to point at /releases/tag/<tag>.
#
# Behavior:
#   - Reads README from stdin.
#   - Lines outside the BEGIN/END block pass through verbatim.
#   - Inside the block, the line whose label matches `channel`
#     ("Dev" or "Experimental") is replaced with a fresh markdown
#     bullet pointing at /releases/tag/<tag>. Other lines (including
#     the stable line) pass through.
#   - Markers themselves pass through.
#
# Style mirrors `scripts/upsert-appcast-item.awk`: start-of-line
# anchors on the markers, deliberate idempotency (running twice with
# the same input is identical to running once).

BEGIN {
    in_block = 0
    if (channel == "dev") {
        label = "Dev"
    } else if (channel == "experimental") {
        label = "Experimental"
    } else {
        label = ""
    }
}

/^[[:space:]]*<!-- BEGIN CURRENT RELEASES -->[[:space:]]*$/ {
    in_block = 1
    print
    next
}

/^[[:space:]]*<!-- END CURRENT RELEASES -->[[:space:]]*$/ {
    in_block = 0
    print
    next
}

{
    if (in_block && label != "" && $0 ~ ("\\*\\*" label "\\*\\*")) {
        printf("- **%s** — [%s](https://github.com/superic/av-pain-reliever/releases/tag/%s)\n",
               label, tag, tag)
    } else {
        print
    }
}
