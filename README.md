# kv-cache-timer

[![Tests](https://github.com/datascience247/KV_cache/actions/workflows/test.yml/badge.svg)](https://github.com/datascience247/KV_cache/actions/workflows/test.yml)
[![Shell: Bash](https://img.shields.io/badge/shell-bash%204%2B-89e051?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/github/license/datascience247/KV_cache)](LICENSE)

> See your Anthropic KV cache countdown live in your Claude Code status line.

```
🔥 HOT [████████░░] 4:23   ← cache warm, time remaining
❄ COLD                      ← cache expired or no activity yet
```

**Contents:** [Why](#why-this-matters) · [Features](#features) · [Install](#install) · [Configuration](#configuration) · [How it works](#how-it-works) · [Troubleshooting](#troubleshooting) · [Contributing](#contributing)

## Why this matters

**What is a KV cache?**
When you chat with Claude, Anthropic caches your conversation prefix (system prompt plus recent messages) so subsequent messages skip re-processing the full context. Cache hits mean faster responses and lower API costs.

**What is TTL?**
Time-to-live — how long the cache stays warm after your last activity:

| Plan | TTL |
|---|---|
| Pro / API key | 5 minutes (300s) |
| Max | 1 hour (3600s) |

**The problem**
This TTL is invisible. You can't tell whether your cache is still warm or already expired — so you don't know whether the next message will pay the full re-processing cost.

**The solution**
kv-cache-timer puts a live countdown in your Claude Code status line. Always know where you stand.

## Features

- **Live countdown** — `🔥 HOT 4:23` in your status line, updated every second
- **Optional progress bar** — `🔥 HOT [████████░░] 4:23` via `SHOW_BAR=1`
- **Per-session tracking** — multiple Claude Code windows track their caches independently
- **Zero runtime deps** — pure Bash; Python 3 only needed for install/uninstall
- **Battle-tested** — 16-test suite covers edge cases (malformed/empty/future timestamps, zero TTL, clock skew); shellcheck-clean and CI-tested on Ubuntu and macOS

> **Terminal only.** The status line appears in Claude Code's terminal interface. It does not render in the VS Code or JetBrains extensions (hooks still fire, but no display — [upstream issue #55643](https://github.com/anthropics/claude-code/issues/55643)).

## Requirements

- [Claude Code](https://claude.ai/code) installed
- Bash 4+
- Python 3 (for install/uninstall scripts only)

## Install

```bash
git clone https://github.com/datascience247/KV_cache.git
cd KV_cache
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

# Show a visual progress bar (default: 1)
# SHOW_BAR=1

# Width of the progress bar in characters (default: 10)
# BAR_WIDTH=10
```

All options can also be set as environment variables, which take priority over the config file.

## How it works

A Claude Code hook (`UserPromptSubmit`) writes the current Unix timestamp to a per-session file (`~/.local/state/kv-cache-timer/ts_<session-id>`). The status line polls that file every second and displays the time remaining.

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
The status line only renders in Claude Code's terminal interface. The VS Code and JetBrains extensions do not display it (hooks still fire correctly).

**Status line not appearing**
Run `~/.local/bin/kv-cache-timer` directly. If it prints output, the script is fine — check that you restarted Claude Code after installing.

**Always shows COLD**
Check `ls -la ~/.local/state/kv-cache-timer/ts_*`. If the file is missing, the hooks aren't firing. Verify with `grep kv-cache ~/.claude/settings.json`.

**Always shows HOT (never counts down)**
Multiple Claude Code windows were writing to the same timestamp file, keeping each other's cache warm. Each window now tracks its own cache independently.

## Contributing

Bug reports and pull requests are welcome. To work on the project locally:

```bash
git clone https://github.com/datascience247/KV_cache.git
cd KV_cache
bash test.sh       # run the full test suite (no external dependencies)
```

All contributions must pass `bash test.sh` and `shellcheck` on the changed scripts.

## License

[MIT](LICENSE)
