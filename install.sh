#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
SETTINGS="${HOME}/.claude/settings.json"
REPO="$(cd "$(dirname "$0")" && pwd)"

echo "Installing kv-cache-timer..."

# Install scripts
mkdir -p "$INSTALL_DIR"
cp "$REPO/kv-cache-timer" "$INSTALL_DIR/kv-cache-timer"
cp "$REPO/kv-cache-timer-hook" "$INSTALL_DIR/kv-cache-timer-hook"
chmod +x "$INSTALL_DIR/kv-cache-timer" "$INSTALL_DIR/kv-cache-timer-hook"
echo "  Scripts → $INSTALL_DIR"

# Install config template (only if not already present)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kv-cache-timer"
CONFIG_FILE="$CONFIG_DIR/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" << 'CONF'
# kv-cache-timer configuration
# Uncomment and edit lines to override defaults.

# Cache TTL in seconds — must match Anthropic's actual TTL (default: 300)
# TTL=300

# Show a visual progress bar alongside the countdown (0 = off, 1 = on)
# SHOW_BAR=0

# Width of the progress bar in characters (default: 10)
# BAR_WIDTH=10
CONF
  echo "  Config template → $CONFIG_FILE"
else
  echo "  Config already exists → $CONFIG_FILE (not overwritten)"
fi

# Patch settings.json
mkdir -p "$(dirname "$SETTINGS")"

python3 - "$SETTINGS" <<'EOF'
import json, sys, os

path = sys.argv[1]

if os.path.exists(path):
    with open(path) as f:
        s = json.load(f)
else:
    s = {}

HOOK_CMD = "~/.local/bin/kv-cache-timer-hook"
OLD_CMD  = "date +%s > ~/.claude_cache_ts"
HOOK_ENTRY = {"matcher": "", "hooks": [{"type": "command", "command": HOOK_CMD}]}

if "hooks" not in s:
    s["hooks"] = {}

for event in ["UserPromptSubmit"]:
    entries = s["hooks"].get(event, [])
    # Remove old inline hook if present
    entries = [
        e for e in entries
        if not any(h.get("command") == OLD_CMD for h in e.get("hooks", []))
    ]
    # Add new hook if not already present
    if not any(
        h.get("command") == HOOK_CMD
        for e in entries
        for h in e.get("hooks", [])
    ):
        entries.append(HOOK_ENTRY)
    s["hooks"][event] = entries

s["statusLine"] = {"type": "command", "command": "~/.local/bin/kv-cache-timer", "refreshInterval": 1}

with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
EOF

echo "  settings.json → $SETTINGS"
echo ""
echo "Done. Restart Claude Code to activate the status line."
