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

# The message validator had no enforcement point until `harness ship` or CI, by which time
# the commit is in the history and the only remedy is rewriting it. The scanner ships a
# pre-commit hook; this is the same idea one hook later, and it goes through the same
# installer in lib/git.sh so the refusal, the backup and the PATH fallback cannot drift.
INSTALL_HOOK=false
FORCE_HOOK=false
COMMIT_ARGUMENTS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --install-hook) INSTALL_HOOK=true; shift ;;
        --force) FORCE_HOOK=true; shift ;;
        *) COMMIT_ARGUMENTS+=("$1"); shift ;;
    esac
done
set -- "${COMMIT_ARGUMENTS[@]+"${COMMIT_ARGUMENTS[@]}"}"

if [ "${FORCE_HOOK}" = true ] && [ "${INSTALL_HOOK}" != true ]; then
    log_error "--force replaces a foreign commit-msg hook and only applies with --install-hook."
    exit 1
fi
if [ "${INSTALL_HOOK}" = true ]; then
    HOOK_PATH="$(install_managed_hook "${REPO_DIR}" commit-msg "${HARNESS_COMMIT_MSG_MARKER}" \
        'exec "${HARNESS_CLI}" commit check --message-file "$1"' \
        'harness commit check --message-file "$1" || exit 1' "${FORCE_HOOK}")" || exit 1
    log_success "Installed the commit message hook into ${HOOK_PATH}."
    exit 0
fi

ACTION="${1:-build}"
shift || true

cd "${REPO_DIR}"

case "${ACTION}" in
    build)
        TYPE="${1:-feat}"
        MSG="${2:-}"
        if [ -z "${MSG}" ]; then
            log_error "Usage: harness commit build <type> \"<message>\""
            log_info "Use one of: $(commit_types_for_humans)."
            exit 1
        fi

        # The creator is held to the list the validator enforces, the way `branch create` is
        # held to the list `branch check` enforces. Without this the command wrote a commit
        # `harness commit check` rejects and `harness ship` refuses to publish, discovered
        # once the work was already committed.
        require_commit_type "${TYPE}"

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
        MESSAGE_FILE=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --message-file)
                    [ -n "${2:-}" ] || { log_error "--message-file requires a path."; exit 1; }
                    MESSAGE_FILE="$2"; shift 2 ;;
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
        if [ -n "${MESSAGE_FILE}" ] && { [ "${CHECK_RANGE}" = true ] || [ -n "${COMMIT_HASH}" ]; }; then
            log_error "--message-file judges a message that is not a commit yet; it takes no revision or range."
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

        # The rules, applied to a subject and a body from wherever they came: a revision that
        # exists, or a message file the commit-msg hook is holding before one does. Two
        # copies of three rules is the divergence this repository keeps closing, and the
        # copy in the hook would be the one nobody noticed had fallen behind.
        #
        # Returns non-zero and reports every rule the message breaks, rather than the first.
        check_message() {
            local short="$1"
            local subject="$2"
            local body="$3"
            local problems=0 trailer

            if [ "${REQUIRE_CONVENTIONAL}" != "false" ] && \
               ! printf '%s' "${subject}" | grep -Eq "^(${COMMIT_TYPE_PATTERN})(\([a-zA-Z0-9_.-]+\))?!?: .+"; then
                log_error "${short} does not conform to Conventional Commits: ${subject}"
                log_info "Expected '<type>(<scope>): <description>' with type one of $(commit_types_for_humans)."
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

        check_one_commit() {
            local revision="$1"
            check_message \
                "$(git log -1 --pretty=%h "${revision}")" \
                "$(git log -1 --pretty=%s "${revision}")" \
                "$(git log -1 --pretty=%B "${revision}")"
        }

        # A message file, judged before it becomes a commit.
        #
        # Comment lines go first: git hands the hook the raw file including its own template,
        # and a forbidden trailer quoted in a comment is not a trailer the commit carries.
        #
        # Three kinds of message are not the project's to conform. A merge and a revert are
        # written by git, and this repository's own history is mostly merge commits -- a hook
        # that rejected them would be uninstalled the first time someone merged. A fixup! or
        # squash! subject is rewritten by the rebase it exists for.
        if [ -n "${MESSAGE_FILE}" ]; then
            if [ ! -f "${MESSAGE_FILE}" ]; then
                log_error "The commit message file does not exist: ${MESSAGE_FILE}"
                exit 1
            fi
            GIT_DIR_PATH="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
            if [ -e "${GIT_DIR_PATH}/MERGE_HEAD" ] || [ -e "${GIT_DIR_PATH}/REVERT_HEAD" ]; then
                exit 0
            fi
            MESSAGE_BODY="$(grep -v '^#' "${MESSAGE_FILE}" || true)"
            MESSAGE_SUBJECT="$(printf '%s\n' "${MESSAGE_BODY}" | grep -v '^[[:space:]]*$' | head -n 1)"
            case "${MESSAGE_SUBJECT}" in
                "fixup! "*|"squash! "*|"Merge "*|"Revert "*) exit 0 ;;
            esac
            check_message "the commit message" "${MESSAGE_SUBJECT}" "${MESSAGE_BODY}" || exit 1
            exit 0
        fi

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
