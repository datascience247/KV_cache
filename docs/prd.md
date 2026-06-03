# kv-cache-timer — Product Requirements Document

## Problem Statement

When working in Claude Code, Anthropic's KV (prompt) cache expires silently after 5 minutes of inactivity. Users have no way to know whether their context prefix is still cached — so they can't make informed decisions about when to take a break, when to keep momentum, or whether they're about to pay the full re-processing cost on their next message.

## Solution

A lightweight status-line widget installed into Claude Code that displays a live countdown (`🔥 HOT 4:23`) while the cache is warm and switches to `❄ COLD` when it expires. Two Claude Code hooks (`UserPromptSubmit`, `Stop`) write a per-session Unix timestamp on every exchange; the status-line script reads that timestamp each polling cycle and computes the remaining window.

## User Stories

1. As a Claude Code user, I want to see a live countdown in the status line, so that I know how much cache time I have left before the next message costs more.
2. As a Claude Code user, I want the display to immediately reset to `🔥 HOT 5:00` the moment I send a message, so that the timer reflects real activity rather than lagging behind.
3. As a Claude Code user, I want the timer to also reset when Claude finishes responding, so that the countdown accurately reflects when cache was last refreshed.
4. As a user with multiple Claude Code windows open, I want each window to track its own cache independently, so that one active session doesn't mask an expiring session in another window.
5. As a user, I want the timer to show `❄ COLD` when there has been no activity, so that I know when I have already paid the re-processing cost.
6. As a user, I want an optional desktop notification when the cache is close to expiring, so that I can finish my thought before the window closes.
7. As a user, I want the notification to fire only once per cooling cycle, so that I am not spammed with repeated alerts.
8. As a user, I want the notification sentinel to clear when I send a new message, so that the next cooling cycle can notify me again.
9. As a user, I want an optional visual progress bar (`[████████░░]`), so that I can gauge urgency at a glance without reading the clock.
10. As a user, I want optional ANSI color (orange for HOT, blue for COLD) via `SHOW_COLOR=1`, so that cache state is immediately visible at a glance. The `NO_COLOR` environment variable suppresses color output when set.
11. As a user, I want to configure the progress bar width via `BAR_WIDTH`, so that I can tune how smoothly the bar counts down (default 30 — each block ≈ 10s at standard TTL).
10. As a user, I want to configure the TTL, notification threshold, and progress bar via a config file, so that I can tune the widget without editing the script.
11. As a user, I want environment variables to override config-file values, so that I can test or temporarily override settings without touching files.
12. As a developer, I want stale session files cleaned up automatically, so that my home directory doesn't accumulate leftover timestamp files from old sessions.
13. As a developer, I want the widget to handle missing, empty, malformed, and future-dated timestamp files gracefully, so that edge cases never produce a crash or misleading display.
14. As a developer, I want a one-command install that patches `settings.json` non-destructively, so that existing hooks and settings are preserved.
15. As a developer, I want a one-command uninstall that fully reverses the install, so that I can remove the widget cleanly without manual JSON editing.
16. As a developer, I want a test suite I can run with `bash test.sh` and no external dependencies, so that I can verify correctness after any change.
17. As a CI system, I want the test suite to run on every push, so that regressions are caught automatically.

## Implementation Decisions

- **Per-session timestamp files** — timestamp and notification sentinel files are namespaced by `CLAUDE_CODE_SESSION_ID` (`~/.claude_cache_ts_<session>`), so multiple windows track independently. Files older than 60 minutes are cleaned up by the hook on each invocation.

- **Single shared hook script** — both `UserPromptSubmit` and `Stop` call the same `kv-cache-timer-hook` script. The hook clears the notification sentinel and writes a fresh timestamp. This ensures immediate visual feedback on send and an accurate "last refreshed" time after Claude finishes.

- **Future timestamp capped at TTL** — if the system clock skews backward between hook write and timer read, `remaining` is clamped to `TTL` before display, preventing misleading "HOT 15:00" output.

- **ANSI color codes** — HOT uses 256-color orange (`\033[38;5;208m`); COLD uses 8-color blue (`\033[34m`). 24-bit truecolor is avoided (broken in v2.1.78+). 256-color is distinct from truecolor and is widely supported in modern terminals. Color is opt-in via `SHOW_COLOR=1`; default is plain text for maximum compatibility. Fallback if 256-color fails in status bar: use `\033[33m` (yellow, 8-color). **Status: unverified in live status bar** — script emits correct ANSI codes but rendering in Claude Code's actual status line has not been end-to-end confirmed.

- **`refreshInterval: 1` in `settings.json`** — the status line re-runs every second. This field is documented in Claude Code's public spec and is the recommended approach for time-based status displays.

- **Config loaded via `source`** — the config file (`~/.config/kv-cache-timer/config.sh`) is sourced as shell. This is intentional for a single-user local tool; it allows shell expressions in config values.

- **Notification fires once per cooling cycle** — a sentinel file (`~/.claude_cache_notified_<session>`) is created when the notification threshold is crossed. It is deleted by the hook on the next user action, resetting the cycle.

- **Python 3 used only for install/uninstall** — `settings.json` patching uses Python 3 for reliable JSON round-tripping. The timer and hook scripts are pure Bash with no runtime dependencies.

## Testing Decisions

A good test exercises the external behavior of the timer script — what it prints to stdout for a given timestamp file state — not how it computes internally. Tests inject state via `TS_FILE`, `TTL`, `NOTIFY_FILE`, and `CONFIG_FILE=/dev/null` environment variables rather than mocking internals.

**Modules tested:**

- `kv-cache-timer` — core timer output for: missing file, expired, boundary, one-second-before-expiry, hot, fresh, malformed, empty, whitespace, future (capped) timestamps; progress bar rendering; notification sentinel creation and suppression.
- `kv-cache-timer-hook` — timestamp file creation on invocation; notification sentinel cleared on invocation.

**Not tested:** install/uninstall Python scripts (JSON patching), desktop notification dispatch (platform-dependent side effect).

## Out of Scope

- `PreToolUse` hook support — resetting on tool calls would make the timer more conservative but adds complexity; deferred.
- Remote or push-based timestamp updates — the polling/file approach is sufficient; sockets or named pipes are not needed.
- Windows support — the widget targets Bash environments (Linux, macOS, WSL).

## Further Notes

The 5-minute TTL is determined by Anthropic. The `TTL` config option only affects the display; it cannot extend the actual cache lifetime. If Anthropic changes the TTL, the default in the script should be updated to match.
