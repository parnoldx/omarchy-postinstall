#!/bin/bash
# Insert path into the window focused before the finder opened.
trap '' HUP INT TERM
set -uo pipefail

# setsid can drop session bus — needed for notify-send
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

LOG="/tmp/fzfyazi-insert.log"
log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG"; }

path="${1:-}"
log "start pid=$$ path=$path"
if [ -z "$path" ]; then
	notify-send "Insert path" "No path provided" 2>/dev/null || true
	exit 1
fi
if command -v realpath >/dev/null 2>&1; then
	path="$(realpath -s -- "$path" 2>/dev/null || printf '%s' "$path")"
fi
log "resolved=$path"

printf '%s' "$path" | wl-copy 2>/dev/null || true
printf '%s' "$path" | wl-copy --primary 2>/dev/null || true

close_finder() {
	hyprctl dispatch 'hl.dsp.window.close({ window = "class:org.omarchy.finder" })' >/dev/null 2>&1 || true
	hyprctl dispatch 'hl.dsp.window.kill({ window = "class:org.omarchy.finder" })' >/dev/null 2>&1 || true
	hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "org.omarchy.finder") | .pid' | while read -r pid; do
		[ -n "$pid" ] && [ "$pid" != "0" ] && kill -TERM "$pid" 2>/dev/null || true
	done
}

close_finder
for _ in $(seq 1 30); do
	if ! hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class == "org.omarchy.finder")' >/dev/null 2>&1; then
		break
	fi
	close_finder
	sleep 0.05
done
log "finder closed"

prev_file="${XDG_RUNTIME_DIR:-/tmp}/fzfyazi-prev-window"
prev=""
[ -f "$prev_file" ] && prev="$(tr -d '[:space:]' <"$prev_file" 2>/dev/null || true)"
log "prev=$prev"

target="$prev"
if [ -n "$target" ]; then
	exists="$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$target" '.[] | select(.address == $a) | .address' | head -1)"
	[ -z "$exists" ] && target=""
fi
if [ -z "$target" ]; then
	target="$(hyprctl clients -j 2>/dev/null | jq -r '
		sort_by(.focusHistoryID)[]
		| select(.class != "org.omarchy.finder")
		| .address
	' | head -1)"
fi
log "target=$target"

if [ -z "$target" ]; then
	notify-send "Path copied" "No window to insert into — Ctrl+V" 2>/dev/null || true
	exit 0
fi

hyprctl dispatch "hl.dsp.focus({ window = \"address:$target\" })" >/dev/null 2>&1 || true

focused=0
for _ in $(seq 1 40); do
	addr="$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')"
	class="$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')"
	if [ "$addr" = "$target" ] && [ "$class" != "org.omarchy.finder" ]; then
		log "focus ok class=$class"
		focused=1
		break
	fi
	if [ "$class" = "org.omarchy.finder" ]; then
		close_finder
	fi
	hyprctl dispatch "hl.dsp.focus({ window = \"address:$target\" })" >/dev/null 2>&1 || true
	sleep 0.05
done

if [ "$focused" != 1 ]; then
	log "ABORT no focus; active=$(hyprctl activewindow -j 2>/dev/null | jq -c '{class,address}')"
	notify-send "Path copied" "Could not focus chat — Ctrl+V" 2>/dev/null || true
	exit 0
fi

sleep 0.15

if ! command -v wtype >/dev/null 2>&1; then
	notify-send "Path copied" "wtype missing — Ctrl+V" 2>/dev/null || true
	exit 0
fi

# Prefer paste: wtype text drops "/" on this setup (path becomes homepaWork...).
# Re-assert clipboard right before paste.
printf '%s' "$path" | wl-copy 2>/dev/null || true
sleep 0.05
if wtype -M ctrl -k v -m ctrl; then
	log "paste ok"
	notify-send -t 2000 "Path inserted" "$path" 2>/dev/null || true
	exit 0
fi
log "paste failed — typing with explicit slash keys"

# Fallback: type char-by-char; send "/" as key "slash"
i=0
len=${#path}
while [ "$i" -lt "$len" ]; do
	c="${path:i:1}"
	if [ "$c" = "/" ]; then
		wtype -k slash || wtype -- /
	else
		wtype -- "$c"
	fi
	i=$((i + 1))
done
log "typed fallback done"
notify-send -t 2000 "Path inserted" "$path" 2>/dev/null || true
