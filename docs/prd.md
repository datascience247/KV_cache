# kv-cache-timer — Product Requirements Document

## Problem Statement

When working in Claude Code, Anthropic's KV (prompt) cache expires silently after 5 minutes of inactivity. Users have no way to know whether their context prefix is still cached — so they can't make informed decisions about when to take a break, when to keep momentum, or whether they're about to pay the full re-processing cost on their next message.

## Solution

A lightweight status-line widget installed into Claude Code that displays a live countdown (`🔥 HOT 4:23`) while the cache is warm and switches to `❄ COLD` when it expires. A Claude Code hook (`UserPromptSubmit`) writes a per-session Unix timestamp on every exchange; the status-line script reads that timestamp each polling cycle and computes the remaining window.

## User Stories

1. As a Claude Code user, I want to see a live countdown in the status line, so that I know how much cache time I have left before the next message costs more.
2. As a Claude Code user, I want the display to immediately reset to `🔥 HOT 5:00` the moment I send a message, so that the timer reflects real activity rather than lagging behind.

3. As a user with multiple Claude Code windows open, I want each window to track its own cache independently, so that one active session doesn't mask an expiring session in another window.
4. As a user, I want the timer to show `❄ COLD` when there has been no activity, so that I know when I have already paid the re-processing cost.
5. As a user, I want an optional visual progress bar (`[████████░░]`), so that I can gauge urgency at a glance without reading the clock.
6. As a user, I want to configure the progress bar width via `BAR_WIDTH`, so that I can tune how smoothly the bar counts down. The bar uses fractional Unicode block characters (▏▎▍▌▋▊▉█) giving 8 sub-steps per block — default width 10 moves every ~3.75s at standard TTL.
7. As a user, I want to configure the TTL and progress bar via a config file, so that I can tune the widget without editing the script.
8. As a user, I want environment variables to override config-file values, so that I can test or temporarily override settings without touching files.
9. As a developer, I want stale session files cleaned up automatically, so that my home directory doesn't accumulate leftover timestamp files from old sessions.
10. As a developer, I want the widget to handle missing, empty, malformed, and future-dated timestamp files gracefully, so that edge cases never produce a crash or misleading display.
11. As a developer, I want a one-command install that patches `settings.json` non-destructively, so that existing hooks and settings are preserved.
12. As a developer, I want a one-command uninstall that fully reverses the install, so that I can remove the widget cleanly without manual JSON editing.
13. As a developer, I want a test suite I can run with `bash test.sh` and no external dependencies, so that I can verify correctness after any change.
14. As a CI system, I want the test suite to run on every push, so that regressions are caught automatically.

## Implementation Decisions

- **Per-session timestamp files** — timestamp files are namespaced by `CLAUDE_CODE_SESSION_ID` (`~/.claude_cache_ts_<session>`), so multiple windows track independently. Files older than 60 minutes are cleaned up by the hook on each invocation.

- **Single shared hook script** — `UserPromptSubmit` calls `kv-cache-timer-hook`. The hook writes a fresh timestamp, ensuring immediate visual feedback on send.

- **Future timestamp capped at TTL** — if the system clock skews backward between hook write and timer read, `remaining` is clamped to `TTL` before display, preventing misleading "HOT 15:00" output.

- **`refreshInterval: 1` in `settings.json`** — the status line re-runs every second. This field is documented in Claude Code's public spec and is the recommended approach for time-based status displays.

- **Config loaded via `source`** — the config file (`~/.config/kv-cache-timer/config.sh`) is sourced as shell. This is intentional for a single-user local tool; it allows shell expressions in config values.

- **Python 3 used only for install/uninstall** — `settings.json` patching uses Python 3 for reliable JSON round-tripping. The timer and hook scripts are pure Bash with no runtime dependencies.

## Testing Decisions

A good test exercises the external behavior of the timer script — what it prints to stdout for a given timestamp file state — not how it computes internally. Tests inject state via `TS_FILE`, `TTL`, and `CONFIG_FILE=/dev/null` environment variables rather than mocking internals.

**Modules tested:**

- `kv-cache-timer` — core timer output for: missing file, expired, boundary, one-second-before-expiry, hot, fresh, malformed, empty, whitespace, future (capped) timestamps; progress bar rendering.
- `kv-cache-timer-hook` — timestamp file creation on invocation.

**Not tested:** install/uninstall Python scripts (JSON patching).

## Out of Scope

- `PreToolUse` hook support — resetting on tool calls would make the timer more conservative but adds complexity; deferred.
- Remote or push-based timestamp updates — the polling/file approach is sufficient; sockets or named pipes are not needed.
- Windows support — the widget targets Bash environments (Linux, macOS, WSL).

## Future Features

- **PreToolUse hook support** — reset timer when Claude invokes tools, not just on user input, for more accurate tracking in tool-heavy workflows.
- **Stats/analytics** — track how often cache hits, average session length, total tokens saved to help users optimize workflow.

## Further Notes

The 5-minute TTL is determined by Anthropic. The `TTL` config option only affects the display; it cannot extend the actual cache lifetime. If Anthropic changes the TTL, the default in the script should be updated to match.
