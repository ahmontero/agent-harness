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

# The issue key is a whole segment of the branch name, or the head of one. The previous
# pattern was unanchored, so `feat/add-2fa-support` committed as `feat(add-2)`: any letters
# followed by a dash and a digit matched, wherever they appeared.
#
# Segments are examined in order, whole-segment matches first, so both conventions work:
# feat/AH-54-real-key and task/ONE-12345/update-order-snapshot.
extract_branch_issue_key() {
    local branch="$1"
    local segment
    local -a segments=()

    IFS='/' read -r -a segments <<< "${branch}"

    for segment in "${segments[@]}"; do
        if [[ "${segment}" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]]; then
            printf '%s\n' "${segment}"
            return 0
        fi
    done

    for segment in "${segments[@]}"; do
        if [[ "${segment}" =~ ^([A-Za-z][A-Za-z0-9]*-[0-9]+)- ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    done

    printf '%s\n' ""
}

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

        if git diff --cached --quiet 2>/dev/null; then
            log_error "Nothing is staged, so there is no commit to build."
            log_info "Stage the change with 'git add' first."
            exit 1
        fi

        BRANCH="$(get_current_branch "${REPO_DIR}")"
        ISSUE_KEY="$(extract_branch_issue_key "${BRANCH}")"

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
            log_error "Commit message does not conform to Conventional Commits: ${RAW_MSG}"
            log_info "Expected '<type>(<scope>): <description>' with type one of feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert."
            exit 1
        fi
        ;;
    *)
        echo "Usage: harness commit <build|check> [args...]"
        exit 1
        ;;
esac
