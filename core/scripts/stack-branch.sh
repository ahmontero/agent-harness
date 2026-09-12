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
        # This printed the current branch, discarded its argument, and exited 0 on any name
        # at all, while the dispatcher advertised it as validating issue-driven branches. A
        # check that cannot fail is the same shape as a gate that cannot run.
        #
        # What makes a branch an issue branch is that `harness commit build` can derive a key
        # from it, so the shape checked here is the shape `branch create` writes and
        # `commit build` reads -- including the bare-number key `normalize_issue_key` yields
        # when no issueTracker.defaultPrefix is configured.
        #
        # The trunk and a release branch are legitimate names that are simply not issue
        # branches. Calling them violations would fail on every repository's default branch.
        BRANCH_TO_CHECK="${1:-}"
        [ $# -le 1 ] || { log_error "branch check takes one branch name, not two."; exit 1; }

        if [ -z "${BRANCH_TO_CHECK}" ]; then
            BRANCH_TO_CHECK="$(get_current_branch "${REPO_DIR}")"
            if [ -z "${BRANCH_TO_CHECK}" ] || [ "${BRANCH_TO_CHECK}" = "HEAD" ]; then
                log_error "HEAD is detached, so there is no branch to check."
                log_info "Check one out, or name the branch: harness branch check <branch>."
                exit 1
            fi
        fi

        TRUNK="$(get_trunk_branch "${REPO_DIR}")"
        RELEASE_PREFIX="$(get_profile_value "git.releaseBranchPrefix" "release/")"
        BRANCH_TYPES="chore|feat|fix|spike"

        if [ "${BRANCH_TO_CHECK}" = "${TRUNK}" ]; then
            log_success "'${BRANCH_TO_CHECK}' is the trunk, not an issue branch."
            log_info "Create one before changing behavior: harness branch create <type> <issue_key> <slug>"
            exit 0
        fi

        if [ -n "${RELEASE_PREFIX}" ] && [ "${BRANCH_TO_CHECK}" != "${BRANCH_TO_CHECK#"${RELEASE_PREFIX}"}" ]; then
            log_success "'${BRANCH_TO_CHECK}' is a release branch, not an issue branch."
            exit 0
        fi

        if [[ "${BRANCH_TO_CHECK}" =~ ^(${BRANCH_TYPES})/([A-Z][A-Z0-9]*-[0-9]+|[0-9]+)-(.+)$ ]]; then
            log_success "'${BRANCH_TO_CHECK}' is an issue branch: type '${BASH_REMATCH[1]}', issue key '${BASH_REMATCH[2]}', slug '${BASH_REMATCH[3]}'."
            exit 0
        fi

        log_error "'${BRANCH_TO_CHECK}' does not follow the branch convention."
        log_info "Expected <type>/<ISSUE-KEY>-<slug>, with type one of: ${BRANCH_TYPES//|/, }."
        log_info "Create one with: harness branch create <type> <issue_key> <slug>"
        exit 1
        ;;
    *)
        echo "Usage: harness branch <create|list|check> [args...]"
        exit 1
        ;;
esac
