#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-uninstall.sh
# Removes what agent-harness installed, and nothing else
# ==============================================================================
#
# Installation writes into four global skill surfaces, ~/.local/bin, and the repository,
# and the only way back was `./setup --rollback` -- which undoes the last transaction, once,
# and is useless a week later. Something that writes into a user's home directory owes them
# an exit that still works after they have stopped thinking about it.
#
# What it removes is decided by the same managed-entry test the installer and the drift
# check use, so a skill somebody else put in ~/.claude/skills is never a candidate. What it
# deliberately leaves is the project's own: AGENTS.md, the CLAUDE.md and GEMINI.md symlinks,
# rules/ and stack.config.json are files a repository commits and owns.
#
# Every removal is journalled through the installer's transaction, so `./setup --rollback`
# undoes an uninstall exactly as it undoes an install.

set -Eeo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/surface.sh"
source "${SCRIPT_DIR}/lib/transaction.sh"

usage() {
    cat <<USAGE_EOF
Usage:
  harness uninstall [options]

Removes the skill surfaces, CLI symlinks and pre-commit hook agent-harness installed.
With no scope flag it removes all three: the global surfaces, the CLI, and this
repository's. It never removes AGENTS.md, rules/, stack.config.json, or a skill
agent-harness did not install.

Options:
  --global          The global surfaces and the CLI symlinks only
  --target <path>   One repository's surfaces and hook only
  --dry-run         Name every path it would remove and remove none
  --yes, -y         Confirm in advance. Required where there is no terminal to ask on.
  -h, --help        Show this help message
USAGE_EOF
}

DRY_RUN=false
ASSUME_YES=false
GLOBAL_ONLY=false
EXPLICIT_TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --yes|-y) ASSUME_YES=true; shift ;;
        --global) GLOBAL_ONLY=true; shift ;;
        --target)
            [ -n "${2:-}" ] || { log_error "--target requires a path to a repository."; exit 1; }
            EXPLICIT_TARGET="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown uninstall option: $1"; usage; exit 1 ;;
    esac
done

if [ "${GLOBAL_ONLY}" = true ] && [ -n "${EXPLICIT_TARGET}" ]; then
    log_error "--global and --target name different scopes; pass one."
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    log_error "harness uninstall requires jq to identify managed surfaces."
    exit 1
fi

INCLUDE_GLOBAL=true
[ -z "${EXPLICIT_TARGET}" ] || INCLUDE_GLOBAL=false
REPO_SCOPE=""
if [ -n "${EXPLICIT_TARGET}" ]; then
    REPO_SCOPE="${EXPLICIT_TARGET}"
elif [ "${GLOBAL_ONLY}" != true ]; then
    REPO_SCOPE="$(get_repo_root "$(pwd -P)")"
fi

# Every path, decided before anything is removed. A command that mutates a home directory
# says which paths first; reporting a count afterwards is not the same promise.
REMOVALS=()
SURFACE_DIRECTORIES=()

collect_surface() {
    local directory="$1"
    local entry
    [ -d "${directory}" ] || return 0
    SURFACE_DIRECTORIES+=("${directory}")
    while IFS= read -r entry; do
        [ -n "${entry}" ] || continue
        REMOVALS+=("${directory}/${entry}")
    done < <(surface_published_managed_names "${directory}")
    [ -f "${directory}/${SURFACE_MANIFEST_NAME}" ] && REMOVALS+=("${directory}/${SURFACE_MANIFEST_NAME}")
    return 0
}

if [ "${INCLUDE_GLOBAL}" = true ]; then
    while IFS=$'\t' read -r directory _; do
        [ -n "${directory}" ] && collect_surface "${directory}"
    done < <(surface_global_list)

    # Any name in ~/.local/bin that is a symlink into some checkout's bin/harness, which
    # covers the three default names and every cliAlias a configuration ever added.
    BIN_DIR="${HOME}/.local/bin"
    if [ -d "${BIN_DIR}" ]; then
        for candidate in "${BIN_DIR}"/*; do
            [ -L "${candidate}" ] || continue
            case "$(readlink "${candidate}")" in
                */bin/harness) REMOVALS+=("${candidate}") ;;
            esac
        done
    fi
fi

if [ -n "${REPO_SCOPE}" ]; then
    if [ ! -d "${REPO_SCOPE}" ]; then
        log_error "Not a directory: ${REPO_SCOPE}"
        exit 1
    fi
    while IFS=$'\t' read -r directory _; do
        [ -n "${directory}" ] && collect_surface "${directory}"
    done < <(surface_repo_list "${REPO_SCOPE}")

    HOOKS_DIR="$(resolve_hooks_dir "${REPO_SCOPE}" 2>/dev/null || true)"
    if [ -n "${HOOKS_DIR}" ] && [ -f "${HOOKS_DIR}/pre-commit" ] && \
       grep -qxF "${HARNESS_PRE_COMMIT_MARKER}" "${HOOKS_DIR}/pre-commit" 2>/dev/null; then
        REMOVALS+=("${HOOKS_DIR}/pre-commit")
    fi
fi

if [ ${#REMOVALS[@]} -eq 0 ]; then
    log_success "Nothing to uninstall: no path in scope carries an agent-harness installation."
    exit 0
fi

log_info "These ${#REMOVALS[@]} path(s) were installed by agent-harness and would be removed:"
printf '  %s\n' "${REMOVALS[@]}"
log_info "Left alone: AGENTS.md, CLAUDE.md, GEMINI.md, rules/ and stack.config.json are the project's own."

if [ "${DRY_RUN}" = true ]; then
    log_info "Dry run: nothing was removed."
    exit 0
fi

if [ "${ASSUME_YES}" != true ]; then
    if [ ! -t 0 ]; then
        log_error "Uninstalling needs a confirmation and there is no terminal to ask on; nothing was removed."
        log_info "Re-run with --yes to confirm, or with --dry-run to see what it would do."
        exit 1
    fi
    printf 'Remove these %s path(s)? [y/N] ' "${#REMOVALS[@]}"
    read -r CONFIRMATION
    case "${CONFIRMATION}" in
        [yY]|[yY][eE][sS]) ;;
        *) log_error "Cancelled; nothing was removed."; exit 1 ;;
    esac
fi

transaction_begin uninstall
for path in "${REMOVALS[@]}"; do
    if [ -L "${path}" ]; then
        transaction_unlink "${path}"
    else
        transaction_remove_tree "${path}"
    fi
done

# A surface directory the harness created and nobody else uses is part of the installation.
# One holding somebody else's skill is not, and rmdir is what tells the two apart.
for directory in "${SURFACE_DIRECTORIES[@]}"; do
    [ -d "${directory}" ] || continue
    [ -z "$(ls -A "${directory}" 2>/dev/null)" ] || continue
    transaction_remove_tree "${directory}"
done

transaction_commit
log_success "Removed ${#REMOVALS[@]} installed path(s)."
log_info "Undo this with './setup --rollback'."
