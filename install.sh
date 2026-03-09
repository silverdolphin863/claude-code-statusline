#!/bin/bash
# Claude Code Status Line — Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/silverdolphin863/claude-code-statusline/main/install.sh | bash

set -e

CLAUDE_DIR="${HOME}/.claude"
SCRIPT_URL="https://raw.githubusercontent.com/silverdolphin863/claude-code-statusline/main/bin/statusline.sh"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
SCRIPT_FILE="${CLAUDE_DIR}/statusline.sh"

echo "Installing Claude Code Status Line..."

# Download script
mkdir -p "${CLAUDE_DIR}"
curl -fsSL "${SCRIPT_URL}" -o "${SCRIPT_FILE}"
chmod +x "${SCRIPT_FILE}"
echo "  ✓ Downloaded statusline.sh"

# Update settings.json
if [ -f "${SETTINGS_FILE}" ]; then
  # Check if statusLine already configured
  if grep -q '"statusLine"' "${SETTINGS_FILE}" 2>/dev/null; then
    echo "  ⚠ statusLine already configured in settings.json — skipping"
    echo "    Update manually if needed:"
    echo '    "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }'
  else
    # Add statusLine to existing settings (before last closing brace)
    node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync('${SETTINGS_FILE}', 'utf8'));
      s.statusLine = { type: 'command', command: 'bash ~/.claude/statusline.sh' };
      fs.writeFileSync('${SETTINGS_FILE}', JSON.stringify(s, null, 2) + '\n');
    " 2>/dev/null && echo "  ✓ Updated settings.json" || echo "  ⚠ Could not update settings.json — add manually"
  fi
else
  # Create new settings.json
  cat > "${SETTINGS_FILE}" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
EOF
  echo "  ✓ Created settings.json"
fi

echo ""
echo "Done! Restart Claude Code to see the status line."
echo ""
echo "Optional: customize via environment variables in your shell profile:"
echo "  export STATUSLINE_SHOW_COST=false"
echo "  export STATUSLINE_SHOW_RATE_LIMITS=true"
echo "  export STATUSLINE_SHOW_PACE=true"
