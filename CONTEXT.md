# kv-cache-timer — Domain Glossary

## Cache warm
The state where Anthropic's KV (prompt) cache holds the current session's context prefix and Claude can read it without re-processing. Displayed as `🔥 HOT`.

## Cache cold / COLD
The state where the cache has expired or no activity has occurred. The next message will pay the full re-processing cost. Displayed as `❄ COLD`.

## TTL (Time To Live)
The duration Anthropic keeps the KV cache alive after the last cache read. Currently 5 minutes (300s) for Pro and API-key users; 1 hour (3600s) for Max plan users. The `TTL` config option controls the *display* only — it cannot extend the actual server-side cache lifetime.

## Cooling cycle
One full HOT→COLD transition. Begins when a hook writes a timestamp; ends when `remaining` hits zero. A new hook invocation starts the next cycle. The desktop notification fires at most once per cooling cycle.

## Session
A single Claude Code window identified by `CLAUDE_CODE_SESSION_ID`. Each session writes its own timestamp file (`~/.claude_cache_ts_<session>`) and notification sentinel (`~/.claude_cache_notified_<session>`), so multiple open windows track their caches independently.

## Hook
A shell command Claude Code executes at lifecycle events (`UserPromptSubmit`, `Stop`). Both events invoke `kv-cache-timer-hook`, which resets the display timer by writing the current Unix timestamp to the session's timestamp file.

## Status line
The one-line display at the bottom of Claude Code's terminal interface, driven by `statusLine.command` in `~/.claude/settings.json`. Refreshes every second (`refreshInterval: 1`). Terminal-only — does not render in the VS Code or JetBrains extensions.

## Notification sentinel
A per-session file (`~/.claude_cache_notified_<session>`) created when the desktop notification fires. Prevents duplicate notifications within one cooling cycle. Deleted by the hook at the start of the next cycle.
