#!/usr/bin/env bash
# wizard/_update-profile.sh — surgically update one profile in profiles.lua.
# Pure I/O: no prompts, no side effects beyond rewriting $5.
#
# Args:
#   $1  slug          — e.g. "home-office" — must already exist in the file
#                        with WIZARD_PROFILE_<slug>_BEGIN/END anchors
#   $2  audio_in      — exact macOS device name for the system mic
#   $3  audio_out     — exact macOS device name for the system speaker
#   $4  fp_block_file — path to a file containing the new fingerprint entries,
#                        one per line, in Lua syntax (already formatted),
#                        e.g.  '      { vendorID = 0x..., productID = 0x..., name = "..." },'
#   $5  profiles_file — path to profiles.lua to edit in place

# shellcheck disable=SC1091
set -euo pipefail

[[ $# -eq 5 ]] || {
  echo "usage: $0 <slug> <audio_in> <audio_out> <fp_block_file> <profiles_file>" >&2
  exit 64
}

slug="$1"
audio_in="$2"
audio_out="$3"
fp_block_file="$4"
profiles_file="$5"

[[ -f "$profiles_file"  ]] || { echo "profiles_file not found: $profiles_file" >&2; exit 66; }
[[ -f "$fp_block_file"  ]] || { echo "fp_block_file not found: $fp_block_file" >&2; exit 66; }

grep -q "WIZARD_PROFILE_${slug}_BEGIN" "$profiles_file" || {
  echo "no WIZARD_PROFILE_${slug}_BEGIN anchor in $profiles_file" >&2
  exit 65
}

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

awk -v slug="$slug" -v audio_in="$audio_in" -v audio_out="$audio_out" -v fp_file="$fp_block_file" '
  BEGIN { in_target=0; in_fp=0 }
  $0 ~ "WIZARD_PROFILE_" slug "_BEGIN" { in_target=1; print; next }
  $0 ~ "WIZARD_PROFILE_" slug "_END"   { in_target=0; print; next }
  in_target && /WIZARD_FINGERPRINT_BEGIN/ {
    print
    while ((getline line < fp_file) > 0) print line
    close(fp_file)
    in_fp=1
    next
  }
  in_target && /WIZARD_FINGERPRINT_END/ {
    in_fp=0
    print
    next
  }
  in_target && in_fp { next }
  in_target && /audioInput[[:space:]]*=/ {
    printf "    audioInput  = \"%s\",\n", audio_in
    next
  }
  in_target && /audioOutput[[:space:]]*=/ {
    printf "    audioOutput = \"%s\",\n", audio_out
    next
  }
  { print }
' "$profiles_file" > "$tmpfile"

mv "$tmpfile" "$profiles_file"
trap - EXIT
