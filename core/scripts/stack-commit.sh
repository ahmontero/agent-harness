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

        if git diff --cached --quiet 2>/dev/null; then
            log_error "Nothing is staged, so there is no commit to build."
            log_info "Stage the change with 'git add' first."
            exit 1
        fi

        BRANCH="$(get_current_branch "${REPO_DIR}")"
        # One grammar, defined in lib/issues.sh and shared with `branch check`. This used to
        # match only [A-Z]+-[0-9]+, so a branch check called conforming -- feat/P20-1234-x,
        # or feat/42-x -- produced a commit carrying no issue key at all.
        ISSUE_KEY="$(issue_key_from_branch "${BRANCH}")"

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
        # One commit was checkable; the range a pull request actually publishes was not, so
        # every rule this function knows was unenforced at the moment the work leaves the
        # machine. --branch reads the range, and `harness ship` runs it.
        CHECK_RANGE=false
        CHECK_BASE=""
        COMMIT_HASH=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --branch) CHECK_RANGE=true; shift ;;
                --base)
                    [ -n "${2:-}" ] || { log_error "--base requires a git revision."; exit 1; }
                    CHECK_BASE="$2"; shift 2 ;;
                -*) log_error "Unknown commit check option: $1"; exit 1 ;;
                *)
                    [ -z "${COMMIT_HASH}" ] || { log_error "commit check takes one revision, not two."; exit 1; }
                    COMMIT_HASH="$1"; shift ;;
            esac
        done
        if [ -n "${CHECK_BASE}" ] && [ "${CHECK_RANGE}" != true ]; then
            log_error "--base names the base of a branch range and only applies with --branch."
            exit 1
        fi
        if [ "${CHECK_RANGE}" = true ] && [ -n "${COMMIT_HASH}" ]; then
            log_error "--branch reads a range; it takes no single revision."
            exit 1
        fi

        # Each rule is satisfiable, the way a project with no linter records that it has
        # none. A convention nobody in the project follows is a gate that can never pass,
        # and the answer to that is a recorded decision, not an unenforced rule.
        REQUIRE_CONVENTIONAL="$(get_profile_value "git.requireConventionalCommits" "true")"
        REQUIRE_ISSUE_KEY="$(get_profile_value "git.requireIssueKey" "true")"
        FORBIDDEN_TRAILERS=()
        while IFS= read -r forbidden; do
            [ -n "${forbidden}" ] && FORBIDDEN_TRAILERS+=("${forbidden}")
        done < <(printf '%s' "$(get_profile_value "git.forbiddenCommitTrailers" "[]")" | jq -r '.[]? // empty' 2>/dev/null || true)

        BRANCH="$(get_current_branch "${REPO_DIR}")"
        BRANCH_KEY="$(issue_key_from_branch "${BRANCH}")"

        # Returns non-zero and reports every rule the commit breaks, rather than the first.
        check_one_commit() {
            local revision="$1"
            local subject body short problems=0 trailer
            short="$(git log -1 --pretty=%h "${revision}")"
            subject="$(git log -1 --pretty=%s "${revision}")"
            body="$(git log -1 --pretty=%B "${revision}")"

            if [ "${REQUIRE_CONVENTIONAL}" != "false" ] && \
               ! printf '%s' "${subject}" | grep -Eq '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-zA-Z0-9_.-]+\))?!?: .+'; then
                log_error "${short} does not conform to Conventional Commits: ${subject}"
                log_info "Expected '<type>(<scope>): <description>' with type one of feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert."
                problems=$((problems + 1))
            fi

            # Only when the branch carries a key: a repository that does not work from an
            # issue tracker has nothing for this rule to check against.
            if [ "${REQUIRE_ISSUE_KEY}" != "false" ] && [ -n "${BRANCH_KEY}" ] && \
               ! printf '%s' "${subject}" | grep -qF "${BRANCH_KEY}"; then
                log_error "${short} does not carry the branch's issue key ${BRANCH_KEY}: ${subject}"
                log_info "Build it with: harness commit build <type> \"<message>\"."
                problems=$((problems + 1))
            fi

            for trailer in "${FORBIDDEN_TRAILERS[@]+"${FORBIDDEN_TRAILERS[@]}"}"; do
                if printf '%s' "${body}" | grep -qiF "${trailer}"; then
                    log_error "${short} carries a trailer profiles.${ACTIVE_PROFILE}.git.forbiddenCommitTrailers forbids: ${trailer}"
                    problems=$((problems + 1))
                fi
            done

            [ "${problems}" -eq 0 ]
        }

        if [ "${CHECK_RANGE}" != true ]; then
            COMMIT_HASH="${COMMIT_HASH:-HEAD}"
            log_info "Checking commit: $(git log -1 --pretty='%h %s' "${COMMIT_HASH}")"
            check_one_commit "${COMMIT_HASH}" || exit 1
            log_success "Commit message conforms to this project's conventions."
            exit 0
        fi

        BASE_REF="${CHECK_BASE:-$(get_trunk_branch "${REPO_DIR}")}"
        if ! git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null 2>&1; then
            log_error "Cannot read this branch's commits: '${BASE_REF}' is not a revision in this repository."
            log_info "Name the base with --base <ref>, or set profiles.${ACTIVE_PROFILE}.git.trunkBranch."
            exit 2
        fi
        RANGE_BASE_COMMIT="$(git merge-base "${BASE_REF}" HEAD 2>/dev/null)" || RANGE_BASE_COMMIT=""
        if [ -z "${RANGE_BASE_COMMIT}" ]; then
            log_error "Cannot read this branch's commits: HEAD and '${BASE_REF}' share no common ancestor."
            exit 2
        fi

        RANGE_REVISIONS=()
        while IFS= read -r revision; do
            [ -n "${revision}" ] && RANGE_REVISIONS+=("${revision}")
        done < <(git rev-list --no-merges "${RANGE_BASE_COMMIT}..HEAD")

        if [ ${#RANGE_REVISIONS[@]} -eq 0 ]; then
            log_success "No commits to check: this branch adds none since ${RANGE_BASE_COMMIT}."
            exit 0
        fi

        log_info "Checking ${#RANGE_REVISIONS[@]} commit(s) since ${RANGE_BASE_COMMIT}..."
        RANGE_FAILURES=0
        for revision in "${RANGE_REVISIONS[@]}"; do
            check_one_commit "${revision}" || RANGE_FAILURES=$((RANGE_FAILURES + 1))
        done
        if [ "${RANGE_FAILURES}" -ne 0 ]; then
            log_error "${RANGE_FAILURES} of ${#RANGE_REVISIONS[@]} commit(s) do not conform."
            exit 1
        fi
        log_success "Every commit on this branch conforms to this project's conventions."
        ;;
    *)
        echo "Usage: harness commit <build|check> [args...]"
        exit 1
        ;;
esac
