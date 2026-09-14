#!/bin/bash
# Launch a command without letting its window steal focus from the yazi finder.
set -uo pipefail

bin="${1:-}"
[ -n "$bin" ] || exit 1
shift

case "$bin" in
omarchy-launch-editor | omarchy-launch-tui)
	setsid "$bin" "$@" >/dev/null 2>&1 &
	;;
*)
	if command -v uwsm-app >/dev/null; then
		setsid uwsm-app -- "$bin" "$@" >/dev/null 2>&1 &
	else
		setsid "$bin" "$@" >/dev/null 2>&1 &
	fi
	;;
esac

refocus() {
	hyprctl dispatch 'hl.dsp.focus({ window = "class:org.omarchy.finder" })' >/dev/null 2>&1 || true
}

# The file manager / the editor map a beat later and would steal focus via
# focus_on_activate. Grab the finder back while they appear.
refocus
for _ in $(seq 1 16); do
	sleep 0.08
	refocus
done
