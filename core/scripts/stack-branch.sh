#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-branch.sh
# Issue-Driven Git Branch Creator & Validator
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
        parse_create_arguments "$@"
        TYPE="${CREATE_TYPE:-feat}"
        RAW_KEY="${CREATE_KEY}"
        SLUG="${CREATE_SLUG}"
        BASE_BRANCH="${CREATE_BASE:-$(get_trunk_branch "${REPO_DIR}")}"

        if [ -z "${RAW_KEY}" ] || [ -z "${SLUG}" ]; then
            log_error "Usage: harness branch create <feat|fix|chore|spike> <issue_key> <slug> [--base <branch>]"
            exit 1
        fi

        ISSUE_KEY="$(normalize_issue_key "${RAW_KEY}")"
        BRANCH_NAME="${TYPE}/${ISSUE_KEY}-${SLUG}"

        log_info "Creating branch '${BRANCH_NAME}' from '${BASE_BRANCH}'..."
        git checkout -b "${BRANCH_NAME}" "${BASE_BRANCH}"
        log_success "Branch created and checked out: ${BRANCH_NAME}"
        ;;
    list)
        git branch --list
        ;;
    check)
        CURR="$(get_current_branch "${REPO_DIR}")"
        log_info "Current branch: ${CURR}"
        ;;
    *)
        echo "Usage: harness branch <create|list|check> [args...]"
        exit 1
        ;;
esac
