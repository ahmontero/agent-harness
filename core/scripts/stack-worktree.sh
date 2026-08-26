#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-worktree.sh
# Git Worktree Workspace Isolation Manager
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/issues.sh"

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

ACTION="${1:-list}"
shift || true

cd "${REPO_DIR}"

case "${ACTION}" in
    create)
        TYPE="${1:-feat}"
        RAW_KEY="${2:-}"
        SLUG="${3:-}"
        BASE="${4:-$(get_trunk_branch "${REPO_DIR}")}"

        if [ -z "${RAW_KEY}" ] || [ -z "${SLUG}" ]; then
            log_error "Usage: harness worktree create <type> <issue_key> <slug> [base_branch]"
            exit 1
        fi

        ISSUE_KEY="$(normalize_issue_key "${RAW_KEY}")"
        BRANCH_NAME="${TYPE}/${ISSUE_KEY}-${SLUG}"
        PARENT_DIR="$(dirname "${REPO_DIR}")"
        REPO_NAME="$(basename "${REPO_DIR}")"
        WORKTREE_DIR="${PARENT_DIR}/${REPO_NAME}-${ISSUE_KEY}"

        log_info "Creating worktree for ${BOLD}${BRANCH_NAME}${RESET} in ${WORKTREE_DIR}..."
        git worktree add -b "${BRANCH_NAME}" "${WORKTREE_DIR}" "${BASE}"
        log_success "Worktree created: ${WORKTREE_DIR}"
        ;;
    list)
        git worktree list
        ;;
    remove)
        KEY="${1:-}"
        if [ -z "${KEY}" ]; then
            log_error "Usage: harness worktree remove <issue_key|path>"
            exit 1
        fi
        log_info "Removing worktree matching '${KEY}'..."
        git worktree list | grep "${KEY}" | awk '{print $1}' | while read -r wt_path; do
            if [ -n "${wt_path}" ] && [ "${wt_path}" != "${REPO_DIR}" ]; then
                git worktree remove --force "${wt_path}"
                log_success "Removed worktree at ${wt_path}"
            fi
        done
        ;;
    *)
        echo "Usage: harness worktree <create|list|remove> [args...]"
        exit 1
        ;;
esac
