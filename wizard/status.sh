#!/usr/bin/env bash
# wizard/status.sh — diagnostic snapshot. Useful when something stops working.

# shellcheck disable=SC1091,SC2088
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/lib.sh"

ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
miss()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
note()  { printf '    %s\n' "$*"; }

banner "av-pain-reliever status"

# --- prerequisites ---
step "Prerequisites"
if [[ "$(uname -s)" == "Darwin" ]]; then ok "macOS"; else miss "macOS (required)"; fi
if command -v brew >/dev/null; then ok "brew"; else miss "brew"; fi
if command -v gh   >/dev/null; then ok "gh";   else miss "gh"; fi
if command -v gum  >/dev/null; then ok "gum";  else miss "gum (run wizard.sh install to get it)"; fi

# --- Hammerspoon ---
step "Hammerspoon"
if [[ -d "/Applications/Hammerspoon.app" ]]; then
  hs_version=$(defaults read /Applications/Hammerspoon.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "?")
  ok "Installed (v$hs_version)"
else
  miss "Not installed"
fi
if pgrep -x Hammerspoon >/dev/null 2>&1; then ok "Running"; else miss "Not running"; fi

# --- OBS ---
step "OBS Studio"
if [[ -d "/Applications/OBS.app" ]]; then
  obs_version=$(defaults read /Applications/OBS.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "?")
  ok "Installed (v$obs_version)"
else
  miss "Not installed"
fi
if pgrep -x OBS >/dev/null 2>&1; then ok "Running"; else miss "Not running"; fi
if command -v obs-cmd >/dev/null 2>&1; then
  ok "obs-cmd: $(obs-cmd --version)"
  if obs-cmd info >/dev/null 2>&1; then
    ok "obs-cmd connected to OBS"
  else
    miss "obs-cmd can't reach OBS (is OBS running with WebSocket enabled?)"
  fi
else
  miss "obs-cmd not installed"
fi

# --- ~/.hammerspoon link ---
step "~/.hammerspoon"
if [[ -L "$HAMMERSPOON_DIR" ]]; then
  target=$(readlink "$HAMMERSPOON_DIR")
  if [[ "$target" == "$REPO_ROOT" ]]; then
    ok "Symlinked to this repo"
  else
    miss "Symlinked to a different path: $target"
  fi
elif [[ -d "$HAMMERSPOON_DIR" ]]; then
  miss "Exists as a real directory (should be a symlink to $REPO_ROOT)"
else
  miss "Doesn't exist"
fi

# --- profiles ---
step "Profiles"
if [[ -f "$PROFILES_FILE" ]]; then
  slugs=()
  while IFS= read -r _slug_line; do
    [[ -n "$_slug_line" ]] && slugs+=("$_slug_line")
  done < <(grep -oE '\["[^"]+"\] = \{' "$PROFILES_FILE" | sed -E 's/^\["//; s/"\] = \{$//')
  for s in "${slugs[@]}"; do
    pretty=$(to_pretty "$s")
    block=$(awk -v slug="$s" '
      $0 ~ "WIZARD_PROFILE_" slug "_BEGIN" { in_b=1; next }
      $0 ~ "WIZARD_PROFILE_" slug "_END"   { exit }
      in_b { print }
    ' "$PROFILES_FILE")
    if [[ -z "$block" ]]; then
      ok "$pretty (manually defined, not wizard-managed)"
      continue
    fi
    if echo "$block" | grep -q 'FILL ME IN'; then
      miss "$pretty (placeholders — run wizard.sh add-location)"
    elif [[ "$s" == "laptop" ]]; then
      ok "$pretty (always matches; fallback)"
    elif echo "$block" | grep -qE 'vendorID = 0x'; then
      fp_count=$(echo "$block" | grep -cE 'vendorID = 0x' || true)
      ok "$pretty ($fp_count fingerprint device(s))"
    else
      miss "$pretty (no fingerprint — run wizard.sh add-location)"
    fi
  done
else
  miss "profiles.lua not found"
fi

# --- log tail ---
step "Recent log (last 10 lines)"
if [[ -f "$LOG_FILE" ]]; then
  tail -n 10 "$LOG_FILE" | sed -E 's/^.*av: /  /'
else
  miss "Log file not found at $LOG_FILE"
fi
