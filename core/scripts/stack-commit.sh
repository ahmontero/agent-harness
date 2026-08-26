#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-commit.sh
# Conventional Commit Builder with Issue Key Prefix
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

ACTION="${1:-build}"
shift || true

cd "${REPO_DIR}"

case "${ACTION}" in
    build)
        TYPE="${1:-feat}"
        MSG="${2:-}"
        if [ -z "${MSG}" ]; then
            log_error "Usage: harness commit build <feat|fix|docs|refactor|test|chore> \"<message>\""
            exit 1
        fi

        BRANCH="$(get_current_branch "${REPO_DIR}")"
        # Extract issue key from branch if present (e.g. feat/PROJ-123-slug -> PROJ-123)
        ISSUE_KEY=$(echo "${BRANCH}" | grep -Eo '[A-Za-z0-9]+-[0-9]+' | head -n 1 || echo "")

        FINAL_MSG=""
        if [ -n "${ISSUE_KEY}" ]; then
            FINAL_MSG="${TYPE}(${ISSUE_KEY}): ${MSG}"
        else
            FINAL_MSG="${TYPE}: ${MSG}"
        fi

        log_info "Generated commit message: ${BOLD}${CYAN}${FINAL_MSG}${RESET}"
        git commit -m "${FINAL_MSG}"
        log_success "Committed successfully."
        ;;
    check)
        COMMIT_HASH="${1:-HEAD}"
        RAW_MSG=$(git log -1 --pretty=%B "${COMMIT_HASH}")
        log_info "Checking commit format: ${RAW_MSG}"
        if echo "${RAW_MSG}" | grep -Eq '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-zA-Z0-9_-]+\))?: .+'; then
            log_success "Commit message conforms to Conventional Commits standard."
        else
            log_warn "Commit message does not strictly conform to Conventional Commits."
        fi
        ;;
    *)
        echo "Usage: harness commit <build|check> [args...]"
        exit 1
        ;;
esac
