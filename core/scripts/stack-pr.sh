#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-pr.sh
# Universal Pre-Flight Verification & Pull Request Creator (GitHub, GitLab, Azure)
# ==============================================================================
#
# Publication is outward-facing and effectively irreversible: a pushed branch is visible to
# everyone with access to the remote, and a pull request notifies people. This command
# therefore decides what it is about to publish before it publishes anything, refuses on
# anything it cannot justify, and asks before the push.
#
# Every guard below exists because the command did the opposite. Run on the trunk it pushed
# the trunk and opened a pull request from main into main. Run with uncommitted work it
# pushed a branch missing it and said nothing. `harness ship --force` targeted a branch
# named "--force", because the first positional argument was read as the target with no
# parsing at all.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/issues.sh"

usage() {
    cat <<USAGE_EOF
Usage:
  harness ship [target_branch] [options]

Runs the full QA suite, pushes the current branch, and opens a pull request against
<target_branch> (default: the trunk). It does not create commits.

Options:
  --yes, -y     Confirm the push in advance. Required where there is no terminal to ask on.
  --dry-run     Report every decision and mutate nothing.
  -h, --help    Show this help message
USAGE_EOF
}

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

TARGET_BRANCH=""
ASSUME_YES=false
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) ASSUME_YES=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        -*)
            log_error "Unknown ship option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -n "${TARGET_BRANCH}" ]; then
                log_error "ship takes one target branch, not two: '${TARGET_BRANCH}' and '$1'."
                exit 1
            fi
            TARGET_BRANCH="$1"
            shift
            ;;
    esac
done

cd "${REPO_DIR}"

[ -n "${TARGET_BRANCH}" ] || TARGET_BRANCH="$(get_trunk_branch "${REPO_DIR}")"
CI_PROVIDER="$(get_profile_value "ci.provider" "github")"
CURRENT_BRANCH="$(get_current_branch "${REPO_DIR}")"

# --- Guards. All of them run before the QA suite, so a refusal costs no test run. ---

# `git branch --show-current` prints nothing on a detached HEAD and still exits 0, so the
# push became `git push -u origin ''`.
if [ -z "${CURRENT_BRANCH}" ] || [ "${CURRENT_BRANCH}" = "HEAD" ]; then
    log_error "HEAD is detached, so there is no branch to publish."
    log_info "Check out a branch first: 'harness branch create <type> <issue_key> <slug>'."
    exit 1
fi

if [ "${CURRENT_BRANCH}" = "${TARGET_BRANCH}" ]; then
    log_error "The current branch and the target are both '${CURRENT_BRANCH}'; nothing was pushed."
    log_info "A pull request proposes one branch be merged into another. Create a branch for this work:"
    printf '  harness branch create <type> <issue_key> <slug>\n'
    exit 1
fi

if ! git rev-parse --verify --quiet "${TARGET_BRANCH}^{commit}" >/dev/null 2>&1 && \
   ! git rev-parse --verify --quiet "origin/${TARGET_BRANCH}^{commit}" >/dev/null 2>&1; then
    log_error "Target branch '${TARGET_BRANCH}' does not exist here or on origin; nothing was pushed."
    exit 1
fi

TARGET_REF="${TARGET_BRANCH}"
git rev-parse --verify --quiet "${TARGET_REF}^{commit}" >/dev/null 2>&1 || TARGET_REF="origin/${TARGET_BRANCH}"

COMMITS_AHEAD="$(git rev-list --count "${TARGET_REF}..HEAD" 2>/dev/null || echo 0)"
if [ "${COMMITS_AHEAD}" -eq 0 ]; then
    log_error "'${CURRENT_BRANCH}' has no commits that '${TARGET_BRANCH}' does not already have."
    log_info "There is nothing to open a pull request about; nothing was pushed."
    exit 1
fi

# Tracked changes only. Untracked files are not going to be pushed either way, and refusing
# on a scratch file would retire the command; they are reported instead.
if ! git diff --quiet || ! git diff --cached --quiet; then
    log_error "'${CURRENT_BRANCH}' has uncommitted changes to tracked files, which a push would not carry."
    git status --short --untracked-files=no | sed 's/^/  /'
    log_info "Commit or stash them, then re-run 'harness ship'."
    exit 1
fi

UNTRACKED="$(git ls-files --others --exclude-standard | head -n 5)"
if [ -n "${UNTRACKED}" ]; then
    log_warn "Untracked files are present and will not be part of this pull request:"
    printf '%s\n' "${UNTRACKED}" | sed 's/^/  /'
fi

log_info "Publishing ${BOLD}${CURRENT_BRANCH}${RESET} (${COMMITS_AHEAD} commit(s)) into ${BOLD}${TARGET_BRANCH}${RESET} on origin."

if [ "${DRY_RUN}" = true ]; then
    log_info "Dry run: the QA suite, the push, and the pull request were all skipped. Nothing was changed."
    exit 0
fi

log_info "Running pre-flight QA checks before opening PR..."
"${SCRIPT_DIR}/stack-qa.sh" all

# The project's own branch conventions forbid an agent from pushing or opening a pull
# request without explicit confirmation. Enforcing it here rather than leaving it to the
# operator is the difference between a rule and a hope.
if [ "${ASSUME_YES}" != true ]; then
    if [ ! -t 0 ]; then
        log_error "Publishing needs a confirmation and there is no terminal to ask on; nothing was pushed."
        log_info "Re-run with --yes to confirm, or with --dry-run to see what it would do."
        exit 1
    fi
    printf 'Push %s and open a pull request into %s? [y/N] ' "${CURRENT_BRANCH}" "${TARGET_BRANCH}"
    read -r CONFIRMATION
    case "${CONFIRMATION}" in
        [yY]|[yY][eE][sS]) ;;
        *)
            log_error "Cancelled; nothing was pushed."
            exit 1
            ;;
    esac
fi

# A failed push used to degrade to a warning, and the pull request was opened anyway --
# for a branch that was never pushed. A rejected non-fast-forward, a missing remote, and an
# expired credential all arrive here, and none of them is a branch that is up to date.
log_info "Pushing branch ${BOLD}${CURRENT_BRANCH}${RESET} to origin..."
if ! git push -u origin "${CURRENT_BRANCH}"; then
    log_error "Push failed, so no pull request was opened. Resolve the push and re-run 'harness ship'."
    exit 1
fi

# From here the branch is published. Anything that goes wrong leaves that half done, so it
# is reported as exactly that rather than as a completed ship.
report_unopened() {
    log_error "The branch is pushed but no pull request was opened: $1"
    log_info "Open it against '${TARGET_BRANCH}' yourself, or configure profiles.${ACTIVE_PROFILE}.ci.prCommand."
    exit 1
}

case "${CI_PROVIDER}" in
    github|github-actions)
        command -v gh >/dev/null 2>&1 || report_unopened "the GitHub CLI ('gh') is not installed."
        log_info "Opening GitHub Pull Request targeting '${TARGET_BRANCH}'..."
        # No interactive retry: the previous fallback re-ran `gh pr create` without --fill,
        # which prompts, and hangs wherever there is no terminal.
        gh pr create --base "${TARGET_BRANCH}" --fill || report_unopened "'gh pr create' failed."
        ;;
    gitlab)
        command -v glab >/dev/null 2>&1 || report_unopened "the GitLab CLI ('glab') is not installed."
        glab mr create --target-branch "${TARGET_BRANCH}" --fill || report_unopened "'glab mr create' failed."
        ;;
    *)
        CUSTOM_PR_CMD="$(get_profile_value "ci.prCommand" "")"
        [ -n "${CUSTOM_PR_CMD}" ] || report_unopened "provider '${CI_PROVIDER}' has no ci.prCommand configured."
        eval "${CUSTOM_PR_CMD}" || report_unopened "the configured ci.prCommand failed."
        ;;
esac

log_success "Published ${CURRENT_BRANCH} and opened a pull request into ${TARGET_BRANCH}."
