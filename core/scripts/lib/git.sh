#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/git.sh
# Git Automation, Trunk Resolution & Worktree Helpers
# ==============================================================================

set -eo pipefail

# The marker that makes "our hook" a decidable question, shared by the installer in
# stack-scan.sh and the diagnostic in stack-doctor.sh so the two cannot disagree about
# which hooks agent-harness is allowed to touch.
# shellcheck disable=SC2034 # consumed by the scripts that source this library
HARNESS_PRE_COMMIT_MARKER="# agent-harness-pre-commit-hook-v1"

# Resolves the hooks directory git will actually read, which is not ${repo}/.git/hooks in
# a linked worktree, where .git is a file.
resolve_hooks_dir() {
    local repo_dir="${1:-$(pwd)}"
    local hooks_dir
    hooks_dir="$(git -C "${repo_dir}" rev-parse --git-path hooks 2>/dev/null)" || return 1
    [[ "${hooks_dir}" = /* ]] || hooks_dir="${repo_dir}/${hooks_dir}"
    printf '%s\n' "${hooks_dir}"
}

ensure_git_repo() {
    local repo_dir="${1:-$(pwd)}"
    if [ ! -d "${repo_dir}/.git" ] && ! git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "'${repo_dir}' is not a git repository."
        exit 1
    fi
}

get_repo_root() {
    local start_dir="${1:-$(pwd)}"
    git -C "${start_dir}" rev-parse --show-toplevel 2>/dev/null || echo "${start_dir}"
}

get_current_branch() {
    local repo_dir="${1:-$(pwd)}"
    git -C "${repo_dir}" branch --show-current 2>/dev/null || echo "HEAD"
}

get_trunk_branch() {
    local repo_dir="${1:-$(pwd)}"
    local configured_trunk
    configured_trunk="$(get_profile_value "git.trunkBranch" "")"

    if [ -n "${configured_trunk}" ]; then
        echo "${configured_trunk}"
        return
    fi

    # Auto-detect main vs master
    if git -C "${repo_dir}" show-ref --verify --quiet refs/heads/main 2>/dev/null || \
       git -C "${repo_dir}" show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
        echo "main"
    elif git -C "${repo_dir}" show-ref --verify --quiet refs/heads/master 2>/dev/null || \
         git -C "${repo_dir}" show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
        echo "master"
    else
        echo "main"
    fi
}

is_working_tree_dirty() {
    local repo_dir="${1:-$(pwd)}"
    if [ -n "$(git -C "${repo_dir}" status --porcelain 2>/dev/null)" ]; then
        return 0 # Dirty
    else
        return 1 # Clean
    fi
}

# Parses the shared "<type> <issue_key> <slug>" creation form, with --base as a flag rather
# than a fourth positional argument. Both `harness branch create` and
# `harness worktree create` advertised --base and read the base positionally, so the flag
# reached git as a revision and printed git's usage text instead of creating anything. The
# fourth positional argument still works, so no existing invocation changes meaning.
parse_create_arguments() {
    CREATE_TYPE=""
    CREATE_KEY=""
    CREATE_SLUG=""
    CREATE_BASE=""
    local positional=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --base)
                if [ -z "${2:-}" ]; then
                    log_error "--base requires a branch name."
                    return 1
                fi
                CREATE_BASE="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                return 1
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    # shellcheck disable=SC2034 # read by the caller after this function returns
    CREATE_TYPE="${positional[0]:-}"
    # shellcheck disable=SC2034 # read by the caller after this function returns
    CREATE_KEY="${positional[1]:-}"
    # shellcheck disable=SC2034 # read by the caller after this function returns
    CREATE_SLUG="${positional[2]:-}"
    [ -n "${CREATE_BASE}" ] || CREATE_BASE="${positional[3]:-}"
}
