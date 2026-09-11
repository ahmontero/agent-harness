#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-upgrade.sh
# Updates the checkout and re-synchronizes every managed surface
# ==============================================================================
#
# Upgrading was `cd` to a checkout nobody's notes name, `git pull`, then
# `./setup --sync-only`. Every step was correct and none of it was discoverable, so
# installations sat on old versions while `harness sync --check` reported drift nobody knew
# how to clear.
#
# The whole body lives in main() and is called on the last line. `git pull` rewrites the
# file bash is reading, and bash reads a script incrementally: without this the interpreter
# would resume at a byte offset in a file that had changed underneath it.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"

usage() {
    cat <<USAGE_EOF
Usage:
  harness upgrade [--check]

Updates the agent-harness checkout and re-synchronizes every managed skill surface.

Options:
  --check       Report what an upgrade would do. Mutates nothing.
  -h, --help    Show this help message
USAGE_EOF
}

main() {
    local check_only=false
    local checkout branch upstream behind revision

    while [ $# -gt 0 ]; do
        case "$1" in
            --check) check_only=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) log_error "Unknown upgrade option: $1"; usage; exit 1 ;;
        esac
    done

    # HARNESS_TEST_CHECKOUT lets the suite drive the refusals against a throwaway directory
    # rather than against the checkout the tests are running from.
    checkout="${HARNESS_TEST_CHECKOUT:-$(get_harness_root)}"

    if [ -f "${checkout}/package.json" ] && command -v jq >/dev/null 2>&1; then
        log_info "Installed: agent-harness $(jq -r '.version // "unknown"' "${checkout}/package.json")"
    fi
    log_info "Checkout:  ${checkout}"

    # --check is a report, not a gate: it prints what it found, names what it could not
    # determine, and exits 0. `harness sync --check` is the gate for surface currency, and
    # a report that refused to answer would be least useful exactly when something is wrong.
    report_surfaces_and_stop() {
        log_info "Surface state:"
        "${SCRIPT_DIR}/stack-sync.sh" --check || true
        log_info "Nothing was changed."
        return 0
    }

    if ! git -C "${checkout}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if [ "${check_only}" = true ]; then
            log_warn "${checkout} is not a Git checkout, so its currency could not be determined."
            report_surfaces_and_stop
            return 0
        fi
        log_error "${checkout} is not a Git checkout, so there is nothing to pull."
        log_info "Reinstall with: curl -fsSL https://raw.githubusercontent.com/ahmontero/agent-harness/main/install.sh | bash"
        return 1
    fi

    revision="$(git -C "${checkout}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    branch="$(get_current_branch "${checkout}")"
    log_info "Revision:  ${revision} on ${branch:-a detached HEAD}"

    if [ -z "${branch}" ] || [ "${branch}" = "HEAD" ]; then
        if [ "${check_only}" = true ]; then
            log_warn "The checkout has a detached HEAD, so its currency could not be determined."
            report_surfaces_and_stop
            return 0
        fi
        log_error "The checkout has a detached HEAD, so there is no branch to update."
        return 1
    fi

    upstream="$(git -C "${checkout}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [ -z "${upstream}" ]; then
        if [ "${check_only}" = true ]; then
            log_warn "'${branch}' tracks no upstream branch, so its currency could not be determined."
            report_surfaces_and_stop
            return 0
        fi
        log_error "'${branch}' tracks no upstream branch, so there is nothing to pull from."
        return 1
    fi

    if ! git -C "${checkout}" fetch --quiet "${upstream%%/*}" "${branch}" 2>/dev/null; then
        log_warn "Could not reach ${upstream%%/*}; the comparison below is against what was already fetched."
    fi
    behind="$(git -C "${checkout}" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)"

    # --check reports; it does not refuse. A dirty checkout is something an upgrade would
    # stop at, so it belongs in the report -- but refusing to *report* because the tree is
    # dirty would deny the answer at the exact moment the reader needs it.
    if [ "${check_only}" = true ]; then
        if [ "${behind}" -eq 0 ]; then
            log_success "The checkout is up to date with ${upstream}."
        else
            log_warn "The checkout is ${behind} commit(s) behind ${upstream}. Run 'harness upgrade'."
        fi
        if [ -n "$(git -C "${checkout}" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
            log_warn "It has uncommitted changes to tracked files, which an upgrade would refuse to pull over."
        fi
        report_surfaces_and_stop
        return 0
    fi

    if [ -n "$(git -C "${checkout}" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        log_error "${checkout} has uncommitted changes to tracked files; nothing was pulled."
        git -C "${checkout}" status --short --untracked-files=no | sed 's/^/  /'
        log_info "Commit or stash them, then re-run 'harness upgrade'."
        return 1
    fi

    if [ "${behind}" -eq 0 ]; then
        log_success "Already up to date with ${upstream}; re-synchronizing surfaces anyway."
    else
        log_info "Pulling ${behind} commit(s) from ${upstream}..."
        if ! git -C "${checkout}" merge --ff-only "${upstream}"; then
            log_error "The checkout could not be fast-forwarded onto ${upstream}; nothing was synchronized."
            log_info "Resolve the divergence in ${checkout} and re-run 'harness upgrade'."
            return 1
        fi
        log_success "Updated to $(git -C "${checkout}" rev-parse --short HEAD)."
    fi

    # exec, so the synchronization runs from the version that was just pulled rather than
    # from the one this process started as.
    log_info "Re-synchronizing skill surfaces..."
    exec "${checkout}/bin/harness" sync
}

main "$@"
