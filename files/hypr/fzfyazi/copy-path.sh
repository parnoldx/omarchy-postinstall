#!/bin/bash
# Copy a file/folder path to the clipboard (wl-copy) and toast.
set -euo pipefail
path="${1:-}"
[ -n "$path" ] || exit 1
if command -v realpath >/dev/null 2>&1; then
	path="$(realpath -s -- "$path")"
fi
printf '%s' "$path" | wl-copy
notify-send -t 2500 "Path copied" "$path"
