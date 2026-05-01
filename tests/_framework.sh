#!/usr/bin/env bash
# tests/_framework.sh — minimal bash test framework. Sourced by run.sh and
# all test_*.sh files.

# shellcheck disable=SC2034
TESTS_PASSED=0
# shellcheck disable=SC2034
TESTS_FAILED=0

# Color codes (no-op if NO_COLOR is set).
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; RESET=''
fi

# Run a test function in its own subshell + tempdir. Failures don't tank the
# run; we just count and continue.
run_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  local output
  if output=$(cd "$tmpdir" && "$name" 2>&1); then
    printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$name"
    TESTS_PASSED=$((TESTS_PASSED+1))
  else
    printf '  %s✗%s %s\n' "$RED" "$RESET" "$name"
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" | sed 's/^/      /'
    fi
    TESTS_FAILED=$((TESTS_FAILED+1))
  fi
  rm -rf "$tmpdir"
}

# Run every function in the calling file whose name starts with "test_".
run_all_tests_in_file() {
  local file="$1"
  printf '%s%s%s\n' "$BOLD" "$file" "$RESET"
  local fns
  fns=$(grep -oE '^test_[a-zA-Z0-9_]+ *\(\)' "$file" | sed 's/ *()//' | sort -u)
  if [[ -z "$fns" ]]; then
    printf '  (no test functions)\n'
    return
  fi
  while IFS= read -r fn; do
    run_test "$fn"
  done <<< "$fns"
}

# ---------- assertions ----------

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" == "$actual" ]]; then return 0; fi
  printf 'assert_eq failed:\n  expected: %s\n  actual:   %s\n' "$expected" "$actual" >&2
  [[ -n "$msg" ]] && printf '  msg: %s\n' "$msg" >&2
  return 1
}

assert_neq() {
  local a="$1" b="$2"
  if [[ "$a" != "$b" ]]; then return 0; fi
  printf 'assert_neq failed: both values are %s\n' "$a" >&2
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then return 0; fi
  printf 'assert_contains failed:\n  expected to contain: %s\n  actual: %s\n' "$needle" "$haystack" >&2
  return 1
}

assert_file_contains() {
  local file="$1" pattern="$2"
  if [[ ! -f "$file" ]]; then
    printf 'assert_file_contains failed: file %s does not exist\n' "$file" >&2
    return 1
  fi
  if grep -qE "$pattern" "$file"; then return 0; fi
  printf 'assert_file_contains failed:\n  file: %s\n  pattern: %s\n' "$file" "$pattern" >&2
  return 1
}

assert_file_not_contains() {
  local file="$1" pattern="$2"
  if [[ ! -f "$file" ]]; then return 0; fi
  if ! grep -qE "$pattern" "$file"; then return 0; fi
  printf 'assert_file_not_contains failed:\n  file: %s\n  unexpected pattern: %s\n' "$file" "$pattern" >&2
  return 1
}

assert_exit_code() {
  local expected="$1"; shift
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$expected" == "$actual" ]]; then return 0; fi
  printf 'assert_exit_code failed:\n  expected: %s\n  actual:   %s\n  cmd: %s\n' "$expected" "$actual" "$*" >&2
  return 1
}

assert_lua_valid() {
  local file="$1"
  if ! command -v luac >/dev/null 2>&1; then
    printf 'assert_lua_valid skipped: luac not installed\n' >&2
    return 0
  fi
  if luac -p "$file" 2>/tmp/luac_err; then return 0; fi
  printf 'assert_lua_valid failed:\n  file: %s\n  error:\n%s\n' "$file" "$(cat /tmp/luac_err | sed 's/^/    /')" >&2
  return 1
}
