#!/usr/bin/env bash
# wizard/_parse-snapshot.sh — parse the most recent device snapshot from the
# av-pain-reliever log and emit a structured digest.
#
# Args:
#   $1  log_file (default: ~/.hammerspoon/logs/av-pain-reliever.log)
#
# Output (on stdout, in three sections separated by blank lines):
#   AUDIO
#   <name>\t<in?>\t<out?>
#   ...
#   USB
#   <vid>\t<pid>\t<name>
#   ...
#
# Exit codes:
#   0  parsed successfully
#   1  no snapshot found (log doesn't have one yet)
#   2  log file missing

# shellcheck disable=SC1091
set -euo pipefail

log_file="${1:-$HOME/.hammerspoon/logs/av-pain-reliever.log}"

[[ -f "$log_file" ]] || { echo "log file not found: $log_file" >&2; exit 2; }

start=$(grep -n -- '--- audio devices ---' "$log_file" | tail -1 | cut -d: -f1 || true)
[[ -n "$start" ]] || { echo "no snapshot in log" >&2; exit 1; }

snapshot=$(
  tail -n "+$start" "$log_file" \
    | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} (INFO|WARN)[[:space:]]+//' \
    | sed -E 's/^[[:space:]]+//'
)

echo "AUDIO"
echo "$snapshot" | awk '
  /^"/ && /in=/ && /out=/ {
    name = ""
    if (match($0, /"[^"]+"/)) {
      name = substr($0, RSTART+1, RLENGTH-2)
    }
    is_in  = ($0 ~ /in=true/)  ? "in"  : ""
    is_out = ($0 ~ /out=true/) ? "out" : ""
    if (name != "") printf "%s\t%s\t%s\n", name, is_in, is_out
  }
'

echo
echo "USB"
echo "$snapshot" | awk '
  /^vid=/ {
    vid = ""; pid = ""; name = ""
    if (match($0, /vid=0x[0-9a-fA-F]+/)) vid = substr($0, RSTART+6, RLENGTH-6)
    if (match($0, /pid=0x[0-9a-fA-F]+/)) pid = substr($0, RSTART+6, RLENGTH-6)
    if (match($0, /"[^"]*"/)) name = substr($0, RSTART+1, RLENGTH-2)
    if (vid != "" && pid != "") printf "%s\t%s\t%s\n", vid, pid, (name == "" ? "(unnamed)" : name)
  }
'
