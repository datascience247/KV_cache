# kv-cache-timer

![Tests](https://github.com/datascience247/kv-cache-timer/actions/workflows/test.yml/badge.svg)

Shows Anthropic's KV (prompt) cache countdown in your Claude Code status line, with optional desktop notifications.

```
🔥 HOT 4:23   ← cache warm, time remaining
❄ COLD        ← cache expired or no activity yet
```

Anthropic's prompt cache expires after 5 minutes of inactivity (Pro/API) or 1 hour (Max plan). This widget makes that invisible countdown visible so you know when it's safe to take a break without re-paying the cache cost.

> **Terminal only.** The status line appears in Claude Code's terminal interface. It does not render in the VS Code or JetBrains extensions (hooks still fire, but no display — [upstream issue #55643](https://github.com/anthropics/claude-code/issues/55643)).

## Features

- **Optional progress bar** — `🔥 HOT [████████░░] 4:23` via `SHOW_BAR=1`
- **Optional ANSI color** — orange for HOT, blue for COLD via `SHOW_COLOR=1` *(rendering in Claude Code status bar unverified — script emits correct codes)*
- **Desktop notifications** — get a pop-up when cache is about to expire (Linux, macOS, WSL)
- **Per-session tracking** — multiple Claude Code windows track their caches independently
- **Zero runtime deps** — pure Bash; Python 3 only needed for install/uninstall

## Requirements

- [Claude Code](https://claude.ai/code) installed
- Bash 4+
- Python 3 (for install/uninstall scripts only)

## Install

```bash
git clone https://github.com/datascience247/kv-cache-timer
cd kv-cache-timer
bash install.sh
```

Restart Claude Code. The status line updates every second.

## Configuration

`install.sh` creates `~/.config/kv-cache-timer/config.sh` with all options commented out. Edit it to customize:

```bash
# ~/.config/kv-cache-timer/config.sh

# Cache TTL in seconds.
# Pro plan / API key: 300 (default)
# Max plan:          3600
# TTL=300

# Seconds before expiry to send a desktop notification (0 = disabled, default: 60)
# NOTIFY_THRESHOLD=60

# Show a visual progress bar (default: 0)
# SHOW_BAR=0

# Width of the progress bar in characters (default: 30)
# BAR_WIDTH=30

# Show ANSI colors — orange for HOT, blue for COLD (default: 0)
# SHOW_COLOR=0
```

All options can also be set as environment variables, which take priority over the config file.

## Desktop notifications

When `NOTIFY_THRESHOLD > 0`, a one-shot notification fires as the cache crosses into the warning zone. Supported platforms:

| Platform | Tool used |
|----------|-----------|
| Linux / WSL | `notify-send` (install via `apt install libnotify-bin`) |
| macOS | `terminal-notifier` (install via `brew install terminal-notifier`) or built-in `osascript` |

The notification fires once per cooling cycle and resets when you send the next message.

## How it works

Two Claude Code hooks (`UserPromptSubmit` and `Stop`) write the current Unix timestamp to a per-session file (`~/.claude_cache_ts_<session-id>`). The status line polls that file every second and displays the time remaining.

```
User sends message
  └─> Hook fires → writes timestamp → resets timer to 5:00

Status line refreshes every second
  └─> Timer reads timestamp → prints HOT M:SS or COLD

5 minutes of silence
  └─> Remaining hits 0 → displays ❄ COLD
```

## Uninstall

```bash
bash uninstall.sh
```

Removes scripts, cleans up session files, removes the hooks from `~/.claude/settings.json`, and deletes the config directory. Restart Claude Code to deactivate.

## Troubleshooting

**Using VS Code or JetBrains?**
The status line only renders in Claude Code's terminal interface. The VS Code and JetBrains extensions do not display it (hooks still fire correctly). Track support at [issue #55643](https://github.com/anthropics/claude-code/issues/55643).

**Status line not appearing**
Run `~/.local/bin/kv-cache-timer` directly. If it prints output, the script is fine — check that you restarted Claude Code after installing.

**Always shows COLD**
Check `ls -la ~/.claude_cache_ts_*`. If the file is missing, the hooks aren't firing. Verify with `cat ~/.claude/settings.json | grep kv-cache`.

**Always shows HOT (never counts down)**
This was the pre-1.0 bug where multiple windows shared one timestamp file. Install the latest version — each window now tracks its own cache independently.

**Notification not appearing**
Verify the notification tool is installed for your platform (see table above). Test with: `notify-send "test" "hello"` or `terminal-notifier -message "hello"`. Set `NOTIFY_THRESHOLD=290` temporarily to trigger it immediately after install.
