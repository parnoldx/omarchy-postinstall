#!/bin/bash
# Regression: Super+Ctrl+F "mailbox readme" must hit mailbox-cli/README.md.
set -euo pipefail

SSP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINDER="$SSP/fuzzy-file-names.sh"
ROOT="${FZFYAZI_ROOT:-$HOME}"
WANT="Work/tries/2026-08-29-mailbox-cli/README.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

# Old yazi-like invocation: one pattern, filename only.
old_count=$(
    fd --base-directory "$ROOT" --regex --no-hidden -- 'mailbox readme' | wc -l
)
[[ "$old_count" -eq 0 ]] || fail "sanity: old filename-only search should miss (got $old_count)"

check_query() {
    local query="$1"
    local out subject args
    out=$("$FINDER" query-args "$query") || fail "query-args failed for '$query'"
    subject=$(printf '%s\n' "$out" | sed -n 's/^subject=//p')
    args=$(printf '%s\n' "$out" | sed -n 's/^args=//p')
    [[ -n "$subject" ]] || fail "empty subject for '$query'"

    # Same argv order yazi uses (see yazi-plugin/src/external/fd.rs).
    # shellcheck disable=SC2086
    if ! fd --base-directory "$ROOT" --regex --no-hidden $args -- "$subject" | grep -Fxq "$WANT"; then
        echo "subject=$subject args=$args" >&2
        fail "'$query' did not find $WANT"
    fi
    echo "ok: '$query' -> $WANT"
}

check_query "mailbox readme"
check_query "mailbox read me"
check_query "ReadMe mailbox"
check_query "readme"

echo "all passed"
