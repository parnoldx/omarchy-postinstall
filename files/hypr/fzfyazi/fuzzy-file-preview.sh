#!/bin/bash
# Preview pane renderer for browse-mode fzf (called by fzf --preview).
# Takes one path. fzf exports FZF_PREVIEW_COLUMNS / FZF_PREVIEW_LINES.

set -uo pipefail

TARGET="${1:-}"
[ -e "$TARGET" ] || { echo "gone: $TARGET"; exit 0; }

COLS="${FZF_PREVIEW_COLUMNS:-80}"
LINES_="${FZF_PREVIEW_LINES:-40}"

if [ -d "$TARGET" ]; then
    if command -v eza >/dev/null; then
        eza --long --header --group-directories-first --color=always \
            --time-style=long-iso --no-user "$TARGET" | head -n "$LINES_"
    else
        ls -lAh --color=always "$TARGET" | head -n "$LINES_"
    fi
    exit 0
fi

MIME=$(file --brief --mime-type "$TARGET" 2>/dev/null || echo "")

case "$MIME" in
image/*)
    if command -v chafa >/dev/null; then
        chafa --size="${COLS}x$((LINES_ - 6))" "$TARGET"
    elif command -v magick >/dev/null; then
        magick "$TARGET" -resize "${COLS}x$((LINES_ - 6))" sixel:-
    fi
    echo
    file --brief "$TARGET"
    ;;
application/pdf)
    file --brief "$TARGET"
    echo "---"
    pdftotext -l 3 -nopgbrk "$TARGET" - 2>/dev/null | head -n $((LINES_ - 8))
    ;;
video/* | audio/*)
    file --brief "$TARGET"
    ;;
text/* | application/json | application/xml | application/javascript | inode/x-empty)
    if command -v bat >/dev/null; then
        bat --style=numbers --color=always --paging=never \
            --line-range=":$((LINES_ * 2))" "$TARGET" 2>/dev/null
    else
        head -n "$((LINES_ * 2))" "$TARGET"
    fi
    ;;
*)
    file --brief "$TARGET"
    echo "---"
    ls -lh "$TARGET" | awk '{print $5, $6, $7, $8}'
    ;;
esac
