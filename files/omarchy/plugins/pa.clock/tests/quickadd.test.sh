#!/usr/bin/env bash
# Isolates quick-add-thunderbird against a fake $HOME so a bad run cannot
# touch the real request file the add-on is watching.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/quick-add-thunderbird"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"

# Missing argument.
if "$script" >/dev/null 2>&1; then
  echo "expected usage error" >&2
  exit 1
fi

# Invalid JSON must not create the request file.
if "$script" 'not-json' >/dev/null 2>&1; then
  echo "expected invalid-json error" >&2
  exit 1
fi
if [[ -e "$HOME/.local/state/omarchy/thunderbird-new-event.json" ]]; then
  echo "invalid JSON wrote a request file" >&2
  exit 1
fi

# Valid JSON lands whole at the watched path.
payload='{"kind":"event","title":"Lunch","startMs":1}'
"$script" "$payload"
got="$(cat "$HOME/.local/state/omarchy/thunderbird-new-event.json")"
# The script appends a newline; compare after stripping it.
if [[ "${got%$'\n'}" != "$payload" ]]; then
  echo "wrote unexpected payload: $got" >&2
  exit 1
fi

echo QUICKADD-OK
