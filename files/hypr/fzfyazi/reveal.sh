#!/bin/bash
# Reveal a file or folder in the current default file manager.
# Nautilus is still the FileManager1 D-Bus owner, so ShowItems would
# ignore inode/directory and open Nautilus. Dispatch by the xdg default.
set -euo pipefail

path="${1:-}"
[ -n "$path" ] || exit 1

if [ -e "$path" ]; then
	path="$(realpath -s -- "$path")"
fi

desktop="$(xdg-mime query default inode/directory 2>/dev/null || true)"

case "$desktop" in
com.thisisgm.flea.desktop | flea.desktop)
	exec flea --gui --select "$path"
	;;
org.gnome.Nautilus.desktop | nautilus.desktop)
	exec nautilus --select "$path"
	;;
org.kde.dolphin.desktop)
	exec dolphin --select "$path"
	;;
nemo.desktop)
	exec nemo --no-desktop "$path"
	;;
*)
	if [ -d "$path" ]; then
		exec xdg-open "$path"
	fi
	exec xdg-open "$(dirname -- "$path")"
	;;
esac
