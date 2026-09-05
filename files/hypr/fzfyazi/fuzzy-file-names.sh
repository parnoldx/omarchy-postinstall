#!/bin/bash
set -uo pipefail

# Live file/folder finder with real previews -- Walker `-m files` replacement.
#
# Modes:
#   (no arg)  prompt for a name, then fd-search inside yazi
#   browse    yazi's built-in fzf plugin (live fuzzy-as-you-type)
#   type      pick a file type, then fd-search that type inside yazi
#
# Priming without yazi's search prompt:
#   ya emit-to <id> search_do "<term>" --via=fd
# SearchOpt takes the subject as its first positional argument.

SSP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_ROOT="${FZFYAZI_ROOT:-$HOME}"
MODE="${1:-search}"

need() {
    if ! command -v "$1" >/dev/null; then
        notify-send "File Search" "$1 is not installed"
        exit 1
    fi
}

need yazi
need ya
need fd

# The fzf plugin spawns a bare `Command("fzf")` with stdin INHERIT, so fzf
# falls back to its own walker (every dotdir). FZF_DEFAULT_COMMAND replaces
# that with fd.
FD_SOURCE="fd --type f --type d --exclude node_modules --exclude .git"
FD_SOURCE+=" --exclude target --exclude __pycache__ --exclude .venv"
FD_SOURCE+=" --exclude .cache --exclude 'Trash*'"

FZF_OPTS="--layout=reverse --info=inline --preview '$SSP/fuzzy-file-preview.sh {}'"
FZF_OPTS+=" --preview-window=right,55%,border-left"

fd_type_args() {
    case "$1" in
    Images) echo "-e png -e jpg -e jpeg -e gif -e webp -e svg -e bmp -e tif -e tiff -e heic -e avif" ;;
    PDFs) echo "-e pdf" ;;
    Videos) echo "-e mp4 -e mkv -e webm -e mov -e avi -e m4v" ;;
    Audio) echo "-e mp3 -e flac -e wav -e ogg -e m4a -e aac -e opus" ;;
    Documents) echo "-e md -e txt -e doc -e docx -e odt -e rtf -e org" ;;
    Spreadsheets) echo "-e csv -e tsv -e xlsx -e xls -e ods" ;;
    Code) echo "-e rs -e py -e js -e ts -e go -e lua -e c -e h -e cpp -e java -e rb -e sh -e bash -e toml -e json -e yaml -e yml" ;;
    Archives) echo "-e zip -e tar -e gz -e tgz -e 7z -e rar -e xz" ;;
    *) echo "" ;;
    esac
}

# Walker-style: every whitespace token must appear somewhere in the *full path*,
# case-insensitive, order-independent. fd's default (and yazi's search_do) only
# matches the filename, so "mailbox readme" misses .../mailbox-cli/README.md.
#
# yazi runs: fd --base-directory <cwd> --regex --no-hidden <args...> <subject>
# --fixed-strings after --regex wins; extra tokens become fd --and.
fd_search_from_query() {
    local query="$1"
    local -a tokens=()
    read -r -a tokens <<< "$query"
    ((${#tokens[@]} > 0)) || return 1
    FD_SUBJECT="${tokens[0]}"
    FD_ARGS="--full-path --ignore-case --fixed-strings"
    local t
    for t in "${tokens[@]:1}"; do
        FD_ARGS+=" --and $(printf '%q' "$t")"
    done
}

ACTION=()
case "$MODE" in
query-args)
    # Test helper: print the search_do argv that Super+Ctrl+F would emit.
    fd_search_from_query "${2:-}" || exit 1
    printf 'subject=%s\nargs=%s\n' "$FD_SUBJECT" "$FD_ARGS"
    exit 0
    ;;
browse)
    ACTION=(plugin fzf)
    ;;
type)
    KIND=$(omarchy-menu-select "File type" \
        "Images" "PDFs" "Videos" "Audio" "Documents" "Spreadsheets" "Code" "Archives") || exit 0
    [ -n "$KIND" ] || exit 0
    TYPE_ARGS=$(fd_type_args "$KIND")
    ACTION=(search_do "" --via=fd --args="$TYPE_ARGS")
    ;;
search | *)
    QUERY=$(omarchy-menu-input "Search files & folders") || exit 0
    [ -n "$QUERY" ] || exit 0
    fd_search_from_query "$QUERY" || exit 0
    ACTION=(search_do "$FD_SUBJECT" --via=fd --args="$FD_ARGS")
    ;;
esac

# `ya emit-to` addresses a yazi instance by its client id, so pick one up front.
CLIENT_ID=$((RANDOM + 20000))

# yazi is wrapped in a shell so the fzf env reaches it -- uwsm-app hands the
# terminal off to systemd, which does not carry arbitrary exported vars across.
# The app-id is what looknfeel.lua floats and sizes.
setsid omarchy-launch-tui --app-id=org.omarchy.finder bash -c "
    export FZF_DEFAULT_COMMAND=$(printf '%q' "$FD_SOURCE")
    export FZF_DEFAULT_OPTS=$(printf '%q' "$FZF_OPTS")
    exec yazi --client-id $CLIENT_ID $(printf '%q' "$SEARCH_ROOT")
" >/dev/null 2>&1 &

# `ya emit-to` exits 1 with "Connection refused" until the instance is listening.
for _ in $(seq 1 100); do
    if ya emit-to "$CLIENT_ID" "${ACTION[@]}" 2>/dev/null; then
        exit 0
    fi
    sleep 0.1
done

notify-send "File Search" "yazi did not come up in time"
exit 1
