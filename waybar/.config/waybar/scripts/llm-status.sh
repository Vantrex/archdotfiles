#!/usr/bin/env bash
# Waybar custom module — shows all active llama-swap models.
# Output: hidden (empty) when no model loaded or llama-swap not running.
# Waybar config: "interval": 5, "exec": "~/.config/waybar/scripts/llm-status.sh"

ENDPOINT="http://127.0.0.1:5099/running"
API_KEY="llama-local"

response=$(curl -sf --max-time 1 \
  -H "Authorization: Bearer ${API_KEY}" \
  "${ENDPOINT}" 2>/dev/null) || exit 0   # llama-swap not running — hide module

printf '%s' "${response}" | python3 -c "
import json, sys

data = json.load(sys.stdin)
models = data.get('running', [])

ready   = [m for m in models if m.get('state') == 'ready']
loading = [m for m in models if m.get('state') != 'ready']

if not models:
    sys.exit(0)

if ready:
    label = '🤖 ' + ' · '.join(m['name'] for m in ready)
    if loading:
        label += ' ⏳ ' + ' · '.join(m['name'] for m in loading)
    css_class = 'active'
else:
    label = '⏳ ' + ' · '.join(m['name'] for m in loading)
    css_class = 'loading'

lines = []
for m in models:
    state_icon = '✓' if m.get('state') == 'ready' else '…'
    desc = m.get('description', '')
    lines.append(f\"{state_icon} {m['name']}\" + (f'  —  {desc}' if desc else ''))
tooltip = 'llama-swap\\n' + '\\n'.join(lines)

print(json.dumps({'text': label, 'tooltip': tooltip, 'class': css_class}))
" 2>/dev/null
