#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/debt.sh
# Technical debt marker scanning
# ==============================================================================
#
# One definition of a debt marker and one way to look for it, shared by `harness debt`
# and `harness context`. Context used to call ripgrep with no fallback, so a machine
# without ripgrep reported zero markers while `harness debt` -- which does fall back to
# grep -- found ten in the same tree. Zero-because-the-tool-is-missing is indistinguishable
# from zero-because-there-is-none, and it was the number an agent was told to trust.
#
# The scan reads tracked files through `git grep`, which is deterministic: ripgrep honours
# .gitignore and grep -r does not, so the same tree answered differently depending on which
# of the two happened to be installed. Untracked files are included only on request.

set -eo pipefail

DEBT_SCAN_UNAVAILABLE=2

# Both comment syntaxes: the marker is documented as `# pragmatism:`, but the recipes ship
# TypeScript and Go presets where no comment starts with a #.
debt_pattern() {
    printf '%s\n' '(#|//)[[:space:]]*(pragmatism|defer):'
}

# Prints "<path>:<line>:<text>" lines. Returns 0 whether or not anything matched, and
# DEBT_SCAN_UNAVAILABLE when the scan could not complete -- which is not a count of zero.
#
# stderr is inspected, not just the exit status. `git grep` reports an unreadable file as a
# diagnostic and still exits 1, which is its code for "no match": relying on the status
# alone would report a tree it could not fully read as a tree with nothing in it.
debt_scan() {
    local repo_root="$1"
    local search_path="$2"
    local include_untracked="${3:-false}"
    local status=0
    local pattern errors
    pattern="$(debt_pattern)"
    errors="$(mktemp)"

    if git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
       [ -e "${search_path}" ]; then
        local git_args=(-I -n --no-color -E)
        [ "${include_untracked}" = true ] && git_args+=(--untracked)
        git -C "${repo_root}" grep "${git_args[@]}" -e "${pattern}" -- "${search_path}" 2>"${errors}" || status=$?
    else
        grep -rnE "${pattern}" "${search_path}" 2>"${errors}" || status=$?
    fi

    if [ "${status}" -gt 1 ] || [ -s "${errors}" ]; then
        cat "${errors}" >&2
        rm -f "${errors}"
        return "${DEBT_SCAN_UNAVAILABLE}"
    fi
    rm -f "${errors}"
    return 0
}

# Prints the marker count, or nothing when the scan could not complete.
debt_count() {
    local output
    if ! output="$(debt_scan "$@")"; then
        return "${DEBT_SCAN_UNAVAILABLE}"
    fi
    printf '%s\n' "${output}" | grep -c . || true
}
