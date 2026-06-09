#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/kv-cache-timer"
HOOK="$(cd "$(dirname "$0")" && pwd)/kv-cache-timer-hook"
PASS=0
FAIL=0

check() {
  local name="$1" expected_pattern="$2" actual="$3"
  # shellcheck disable=SC2053
  if [[ "$actual" == $expected_pattern ]]; then
    echo "PASS $name"
    (( PASS++ )) || true
  else
    echo "FAIL $name: got '$actual' expected pattern '$expected_pattern'"
    (( FAIL++ )) || true
  fi
}

# Run timer with no config file — tests core logic
run() {
  local name="$1" expected_pattern="$2" ts_offset="$3" ttl="${4:-300}"
  local tmp
  tmp=$(mktemp)

  if [ "$ts_offset" = "NOFILE" ]; then
    rm -f "$tmp"
    actual=$(CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
  elif [ "$ts_offset" = "MALFORMED" ]; then
    echo "notanumber" > "$tmp"
    actual=$(CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
    rm -f "$tmp"
  elif [ "$ts_offset" = "EMPTY" ]; then
    : > "$tmp"
    actual=$(CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
    rm -f "$tmp"
  elif [ "$ts_offset" = "WHITESPACE" ]; then
    echo "   " > "$tmp"
    actual=$(CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
    rm -f "$tmp"
  else
    echo "$(( $(date +%s) + ts_offset ))" > "$tmp"
    actual=$(CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
    rm -f "$tmp"
  fi

  check "$name" "$expected_pattern" "$actual"
}

# ── Core logic tests (ts_offset is added to current time) ─────────────────────

run "no_timestamp_file"        "❄ COLD"       NOFILE
run "expired_well_past"        "❄ COLD"       $(( -300 - 60 ))
run "exactly_at_boundary"      "❄ COLD"       $(( -300 ))
run "one_second_before_expiry" "🔥 HOT 0:01"  $(( -300 + 1 ))
run "hot_with_time_left"       "🔥 HOT *"     $(( -10 ))
run "fresh_timestamp"          "🔥 HOT 5:*"   0
run "malformed_file"           "❄ COLD"       MALFORMED
run "empty_file"               "❄ COLD"       EMPTY
run "whitespace_only"          "❄ COLD"       WHITESPACE
run "future_timestamp"         "🔥 HOT 5:*"   $(( +600 ))

# ── Progress bar test ──────────────────────────────────────────────────────────

tmp_bar=$(mktemp)
echo "$(date +%s)" > "$tmp_bar"
bar_out=$(CONFIG_FILE=/dev/null TS_FILE="$tmp_bar" TTL=300 SHOW_BAR=1 bash "$SCRIPT" 2>&1 || true)
rm -f "$tmp_bar"
if [[ "$bar_out" == "🔥 HOT ["*"]"* ]]; then
  echo "PASS show_bar_enabled"
  (( PASS++ )) || true
else
  echo "FAIL show_bar_enabled: got '$bar_out'"
  (( FAIL++ )) || true
fi

# ── Partial block test ────────────────────────────────────────────────────────

tmp_bar=$(mktemp)
# 166s elapsed → ~134s remaining; chosen to avoid full-block boundaries at multiples of 30s
echo "$(( $(date +%s) - 166 ))" > "$tmp_bar"
partial_out=$(CONFIG_FILE=/dev/null TS_FILE="$tmp_bar" TTL=300 SHOW_BAR=1 BAR_WIDTH=10 bash "$SCRIPT" 2>&1 || true)
rm -f "$tmp_bar"
if [[ "$partial_out" == *"▏"* ]] || [[ "$partial_out" == *"▎"* ]] || [[ "$partial_out" == *"▍"* ]] || \
   [[ "$partial_out" == *"▌"* ]] || [[ "$partial_out" == *"▋"* ]] || [[ "$partial_out" == *"▊"* ]] || \
   [[ "$partial_out" == *"▉"* ]]; then
  echo "PASS show_bar_partial_block"
  (( PASS++ )) || true
else
  echo "FAIL show_bar_partial_block: no partial block in '$partial_out'"
  (( FAIL++ )) || true
fi

# ── Hook tests ─────────────────────────────────────────────────────────────────

# Hook writes a timestamp file
tmp_ts=$(mktemp)
rm -f "$tmp_ts"
TS_FILE="$tmp_ts" CLAUDE_CODE_SESSION_ID="test_session_$$" \
  bash "$HOOK" >/dev/null 2>&1 || true
if [ -f "$tmp_ts" ]; then
  echo "PASS hook_writes_timestamp"
  (( PASS++ )) || true
else
  echo "FAIL hook_writes_timestamp: timestamp file not created"
  (( FAIL++ )) || true
fi
rm -f "$tmp_ts"

# Hook cleans stale session files older than the configured TTL
tmp_home=$(mktemp -d)
stale_ts="$tmp_home/kv-cache-timer/ts_stale_$$"
mkdir -p "$(dirname "$stale_ts")"
touch "$stale_ts"
python3 - "$stale_ts" <<'PYEOF'
import os, sys, time
ago = time.time() - 7200
os.utime(sys.argv[1], (ago, ago))
PYEOF
CLAUDE_CODE_SESSION_ID="new_session_$$" XDG_STATE_HOME="$tmp_home" TTL=300 \
  bash "$HOOK" >/dev/null 2>&1 || true
if [ ! -f "$stale_ts" ]; then
  echo "PASS hook_cleans_stale_files"
  (( PASS++ )) || true
else
  echo "FAIL hook_cleans_stale_files: stale file not removed"
  (( FAIL++ )) || true
fi
rm -rf "$tmp_home"

# ── Summary ────────────────────────────────────────────────────────────────────
echo
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS tests passed."
  exit 0
else
  echo "$FAIL/$((PASS + FAIL)) tests FAILED."
  exit 1
fi
