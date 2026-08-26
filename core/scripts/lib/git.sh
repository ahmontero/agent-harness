#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/git.sh
# Git Automation, Trunk Resolution & Worktree Helpers
# ==============================================================================

set -eo pipefail

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
