#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
SETTINGS="${HOME}/.claude/settings.json"

echo "Uninstalling kv-cache-timer..."

# Remove scripts
rm -f "$INSTALL_DIR/kv-cache-timer" "$INSTALL_DIR/kv-cache-timer-hook"
echo "  Removed scripts from $INSTALL_DIR"

# Remove timestamp and sentinel files
# shellcheck disable=SC2086
count=$(find "${HOME}" -maxdepth 1 \( -name '.claude_cache_ts_*' -o -name '.claude_cache_notified_*' \) 2>/dev/null | wc -l | tr -d ' ')
find "${HOME}" -maxdepth 1 \( -name '.claude_cache_ts_*' -o -name '.claude_cache_notified_*' \) -delete 2>/dev/null || true
echo "  Removed $count session file(s)"

# Remove config directory
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kv-cache-timer"
if [ -d "$CONFIG_DIR" ]; then
  rm -rf "$CONFIG_DIR"
  echo "  Removed config → $CONFIG_DIR"
fi

# Patch settings.json
if [ -f "$SETTINGS" ]; then
  python3 - "$SETTINGS" <<'EOF'
import json, sys

path = sys.argv[1]

with open(path) as f:
    s = json.load(f)

HOOK_CMD = "~/.local/bin/kv-cache-timer-hook"

if "hooks" in s:
    for event in ["UserPromptSubmit", "Stop"]:
        if event in s["hooks"]:
            entries = [
                e for e in s["hooks"][event]
                if not any(h.get("command") == HOOK_CMD for h in e.get("hooks", []))
            ]
            if entries:
                s["hooks"][event] = entries
            else:
                del s["hooks"][event]
    if not s["hooks"]:
        del s["hooks"]

if s.get("statusLine", {}).get("command") == "~/.local/bin/kv-cache-timer" and s.get("statusLine", {}).get("type") == "command":
    del s["statusLine"]

with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
EOF
  echo "  Patched $SETTINGS"
fi

echo ""
echo "Done. Restart Claude Code to deactivate the status line."
