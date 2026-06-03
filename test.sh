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

# Run timer with NO_COLOR=1 and no config file — tests core logic
run() {
  local name="$1" expected_pattern="$2" ts_offset="$3" ttl="${4:-300}"
  local tmp
  tmp=$(mktemp)

  if [ "$ts_offset" = "NOFILE" ]; then
    rm -f "$tmp"
    actual=$(NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
  elif [ "$ts_offset" = "MALFORMED" ]; then
    echo "notanumber" > "$tmp"
    actual=$(NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
    rm -f "$tmp"
  elif [ "$ts_offset" = "EMPTY" ]; then
    : > "$tmp"
    actual=$(NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
    rm -f "$tmp"
  elif [ "$ts_offset" = "WHITESPACE" ]; then
    echo "   " > "$tmp"
    actual=$(NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
    rm -f "$tmp"
  else
    echo "$(( $(date +%s) + ts_offset ))" > "$tmp"
    actual=$(NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp" TTL="$ttl" bash "$SCRIPT" 2>&1 || true)
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
bar_out=$(NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp_bar" TTL=300 SHOW_BAR=1 bash "$SCRIPT" 2>&1 || true)
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
partial_out=$(NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp_bar" TTL=300 SHOW_BAR=1 BAR_WIDTH=10 bash "$SCRIPT" 2>&1 || true)
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

# ── Color tests ───────────────────────────────────────────────────────────────

# SHOW_COLOR=1 HOT output contains ANSI escape sequence
tmp_color=$(mktemp)
echo $(( $(date +%s) )) > "$tmp_color"
color_out=$(CONFIG_FILE=/dev/null TS_FILE="$tmp_color" TTL=300 SHOW_COLOR=1 bash "$SCRIPT" 2>&1 || true)
rm -f "$tmp_color"
if [[ "$color_out" == *$'\033['* ]]; then
  echo "PASS show_color_hot_has_ansi"
  (( PASS++ )) || true
else
  echo "FAIL show_color_hot_has_ansi: got '$color_out'"
  (( FAIL++ )) || true
fi

# NO_COLOR suppresses color even when SHOW_COLOR=1
tmp_color=$(mktemp)
echo $(( $(date +%s) )) > "$tmp_color"
color_out=$(NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp_color" TTL=300 SHOW_COLOR=1 bash "$SCRIPT" 2>&1 || true)
rm -f "$tmp_color"
if [[ "$color_out" != *$'\033['* ]]; then
  echo "PASS no_color_suppresses_ansi"
  (( PASS++ )) || true
else
  echo "FAIL no_color_suppresses_ansi: color leaked despite NO_COLOR"
  (( FAIL++ )) || true
fi

# ── Notification sentinel tests ────────────────────────────────────────────────

# Sentinel file is created when remaining <= NOTIFY_THRESHOLD
tmp_ts=$(mktemp)
tmp_notify=$(mktemp)
rm -f "$tmp_notify"   # must not exist for the trigger to fire
echo $(( $(date +%s) - 260 )) > "$tmp_ts"   # 40s remaining
NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp_ts" TTL=300 NOTIFY_FILE="$tmp_notify" NOTIFY_THRESHOLD=60 bash "$SCRIPT" >/dev/null 2>&1 || true
if [ -f "$tmp_notify" ]; then
  echo "PASS notify_sentinel_created"
  (( PASS++ )) || true
else
  echo "FAIL notify_sentinel_created: sentinel file not created"
  (( FAIL++ )) || true
fi
rm -f "$tmp_ts" "$tmp_notify"

# Sentinel is NOT created when remaining > NOTIFY_THRESHOLD
tmp_ts=$(mktemp)
tmp_notify=$(mktemp)
rm -f "$tmp_notify"
echo $(( $(date +%s) - 10 )) > "$tmp_ts"   # 290s remaining
NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp_ts" TTL=300 NOTIFY_FILE="$tmp_notify" NOTIFY_THRESHOLD=60 bash "$SCRIPT" >/dev/null 2>&1 || true
if [ ! -f "$tmp_notify" ]; then
  echo "PASS notify_sentinel_not_created_above_threshold"
  (( PASS++ )) || true
else
  echo "FAIL notify_sentinel_not_created_above_threshold: sentinel should not exist"
  (( FAIL++ )) || true
fi
rm -f "$tmp_ts" "$tmp_notify"

# ── Hook tests ─────────────────────────────────────────────────────────────────

# Hook writes a timestamp file
tmp_ts=$(mktemp)
rm -f "$tmp_ts"
CLAUDE_CODE_SESSION_ID="test_session_$$" HOME="$(dirname "$tmp_ts")" \
  bash "$HOOK" >/dev/null 2>&1 || true
hook_ts_file="$(dirname "$tmp_ts")/.claude_cache_ts_test_session_$$"
if [ -f "$hook_ts_file" ]; then
  echo "PASS hook_writes_timestamp"
  (( PASS++ )) || true
else
  echo "FAIL hook_writes_timestamp: timestamp file not created"
  (( FAIL++ )) || true
fi
rm -f "$hook_ts_file"

# Hook deletes the notification sentinel
tmp_sentinel="$(dirname "$tmp_ts")/.claude_cache_notified_test_sentinel_$$"
touch "$tmp_sentinel"
CLAUDE_CODE_SESSION_ID="test_sentinel_$$" HOME="$(dirname "$tmp_ts")" \
  bash "$HOOK" >/dev/null 2>&1 || true
if [ ! -f "$tmp_sentinel" ]; then
  echo "PASS hook_clears_sentinel"
  (( PASS++ )) || true
else
  echo "FAIL hook_clears_sentinel: sentinel file still exists after hook"
  (( FAIL++ )) || true
fi
rm -f "$tmp_sentinel" "$(dirname "$tmp_ts")/.claude_cache_ts_test_sentinel_$$"

# NOTIFY_THRESHOLD=0 disables notifications — sentinel must not be created
tmp_ts=$(mktemp)
tmp_notify=$(mktemp)
rm -f "$tmp_notify"
echo "$(( $(date +%s) - 260 ))" > "$tmp_ts"   # 40s remaining — within default threshold
NO_COLOR=1 CONFIG_FILE=/dev/null TS_FILE="$tmp_ts" TTL=300 NOTIFY_FILE="$tmp_notify" NOTIFY_THRESHOLD=0 bash "$SCRIPT" >/dev/null 2>&1 || true
if [ ! -f "$tmp_notify" ]; then
  echo "PASS notify_disabled_when_threshold_zero"
  (( PASS++ )) || true
else
  echo "FAIL notify_disabled_when_threshold_zero: sentinel created despite NOTIFY_THRESHOLD=0"
  (( FAIL++ )) || true
fi
rm -f "$tmp_ts" "$tmp_notify"

# Hook cleans stale session files older than the configured TTL
tmp_home=$(mktemp -d)
stale_ts="$tmp_home/.claude_cache_ts_stale_$$"
stale_notify="$tmp_home/.claude_cache_notified_stale_$$"
touch "$stale_ts" "$stale_notify"
python3 - "$stale_ts" "$stale_notify" <<'PYEOF'
import os, sys, time
ago = time.time() - 7200
for f in sys.argv[1:]:
    os.utime(f, (ago, ago))
PYEOF
CLAUDE_CODE_SESSION_ID="new_session_$$" HOME="$tmp_home" TTL=300 \
  bash "$HOOK" >/dev/null 2>&1 || true
if [ ! -f "$stale_ts" ] && [ ! -f "$stale_notify" ]; then
  echo "PASS hook_cleans_stale_files"
  (( PASS++ )) || true
else
  echo "FAIL hook_cleans_stale_files: stale files not removed"
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
