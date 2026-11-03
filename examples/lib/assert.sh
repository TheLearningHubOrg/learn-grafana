#!/usr/bin/env bash
# Tiny assertion helpers shared by every example script.
# Usage: source "$(dirname "$0")/../lib/assert.sh"

PASS=0
FAIL=0

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n       expected: %q\n       actual:   %q\n' "$label" "$expected" "$actual"
  fi
}

assert_match() {
  local pattern="$1" actual="$2" label="$3"
  if [[ "$actual" =~ $pattern ]]; then
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n       /%s/ did not match %q\n' "$label" "$pattern" "$actual"
  fi
}

finish() {
  printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}
