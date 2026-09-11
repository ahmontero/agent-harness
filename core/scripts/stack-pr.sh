#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-pr.sh
# Universal Pre-Flight Verification & Pull Request Creator (GitHub, GitLab, Azure)
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

TARGET_BRANCH="${1:-$(get_trunk_branch "${REPO_DIR}")}"
CI_PROVIDER="$(get_profile_value "ci.provider" "github")"

cd "${REPO_DIR}"
CURRENT_BRANCH="$(get_current_branch "${REPO_DIR}")"

log_info "Running pre-flight QA checks before opening PR..."
"${SCRIPT_DIR}/stack-qa.sh" all

# A failed push used to degrade to a warning, and the pull request was opened anyway --
# for a branch that was never pushed. A rejected non-fast-forward, a missing remote, and an
# expired credential all arrive here, and none of them is a branch that is up to date.
log_info "Pushing branch ${BOLD}${CURRENT_BRANCH}${RESET} to origin..."
if ! git push -u origin "${CURRENT_BRANCH}"; then
    log_error "Push failed, so no pull request was opened. Resolve the push and re-run 'harness ship'."
    exit 1
fi

case "${CI_PROVIDER}" in
    github|github-actions)
        if command -v gh >/dev/null 2>&1; then
            log_info "Opening GitHub Pull Request targeting '${TARGET_BRANCH}'..."
            gh pr create --base "${TARGET_BRANCH}" --fill || gh pr create --base "${TARGET_BRANCH}"
        else
            log_warn "GitHub CLI ('gh') not found. Please create PR via GitHub web UI."
        fi
        ;;
    gitlab)
        if command -v glab >/dev/null 2>&1; then
            glab mr create --target-branch "${TARGET_BRANCH}" --fill
        else
            log_warn "GitLab CLI ('glab') not found."
        fi
        ;;
    *)
        CUSTOM_PR_CMD="$(get_profile_value "ci.prCommand" "")"
        if [ -n "${CUSTOM_PR_CMD}" ]; then
            eval "${CUSTOM_PR_CMD}"
        else
            log_info "Branch pushed. Create Pull Request targeting '${TARGET_BRANCH}' in your web UI."
        fi
        ;;
esac
