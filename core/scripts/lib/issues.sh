#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/issues.sh
# Universal Issue Tracker Adapter (GitHub Issues, Jira, Linear, GitLab, Standalone)
# ==============================================================================

set -eo pipefail

# One grammar for an issue key, and one list of branch types, shared by `branch check`,
# `branch create` and `commit build`. They each carried their own: check accepted a prefix
# containing digits (P20-1234) and a bare number, build matched only [A-Z]+-[0-9]+, and
# create accepted any type at all. A branch check called conforming therefore produced a
# commit with no scope -- including for the bare number normalize_issue_key yields when no
# issueTracker.defaultPrefix is configured, which is the default on GitHub -- and create
# handed the user branches check would reject.
ISSUE_KEY_PATTERN='[A-Z][A-Z0-9]*-[0-9]+|[0-9]+'
BRANCH_TYPE_PATTERN='chore|feat|fix|spike'

# The Conventional Commits types `commit check` enforces. It lived only inside that check's
# own grep, so `commit build` had nothing to validate against and accepted any word at all:
# `harness commit build feature "..."` wrote `feature(AH-2): ...`, which the same harness
# then rejected -- and by then it was already in the history, so the way back was rewriting
# it. `commit build`'s usage string carried a third, shorter list for the same reason, and
# now reads off this one.
COMMIT_TYPE_PATTERN='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'

branch_types_for_humans() {
    printf '%s\n' "${BRANCH_TYPE_PATTERN//|/, }"
}

commit_types_for_humans() {
    printf '%s\n' "${COMMIT_TYPE_PATTERN//|/, }"
}

require_branch_type() {
    local type="$1"
    local pattern="^(${BRANCH_TYPE_PATTERN})$"
    if ! [[ "${type}" =~ ${pattern} ]]; then
        log_error "Unsupported branch type '${type}'."
        log_info "Use one of: $(branch_types_for_humans)."
        log_info "'harness branch check' accepts no other, so creating one would hand you a branch the harness itself rejects."
        return 1
    fi
}

require_commit_type() {
    local type="$1"
    local pattern="^(${COMMIT_TYPE_PATTERN})$"
    if ! [[ "${type}" =~ ${pattern} ]]; then
        log_error "Unsupported commit type '${type}'."
        log_info "Use one of: $(commit_types_for_humans)."
        log_info "'harness commit check' accepts no other, so building one would write a commit the harness itself rejects."
        return 1
    fi
}

# The issue key a branch carries, or nothing.
#
# The structured form <type>/<KEY>-<slug> is authoritative: it is the shape `branch create`
# writes, and reading the key from its own position is what lets a bare numeric key be
# recognised without mistaking a version for one.
#
# A branch in no such form is still scanned for a prefixed key, because branches written by
# hand or by another tool are why this is tolerant at all. A bare number is deliberately not
# looked for there: every version string in every branch name would answer to it.
issue_key_from_branch() {
    local branch="$1"
    local structured="^[^/]+/(${ISSUE_KEY_PATTERN})(-.*)?$"
    if [[ "${branch}" =~ ${structured} ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return
    fi
    if [[ "${branch}" =~ ([A-Z][A-Z0-9]*-[0-9]+)($|[^0-9.]) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
}

get_issue_provider() {
    get_profile_value "issueTracker.provider" "standalone"
}

normalize_issue_key() {
    local raw_input="$1"
    # Uppercase
    local upper
    upper="$(echo "${raw_input}" | tr '[:lower:]' '[:upper:]')"
    
    # If it's a pure number (e.g. 123 for GitHub issue #123)
    if [[ "${upper}" =~ ^[0-9]+$ ]]; then
        local prefix
        prefix="$(get_profile_value "issueTracker.defaultPrefix" "")"
        if [ -n "${prefix}" ]; then
            echo "${prefix}-${upper}"
        else
            echo "${upper}"
        fi
        return
    fi

    echo "${upper}"
}

fetch_issue_title() {
    local issue_key="$1"
    local provider
    provider="$(get_issue_provider)"

    case "${provider}" in
        github)
            if command -v gh >/dev/null 2>&1; then
                local num="${issue_key//[^0-9]/}"
                gh issue view "${num}" --json title -q .title 2>/dev/null || echo "Task ${issue_key}"
            else
                echo "Task ${issue_key}"
            fi
            ;;
        jira)
            if command -v jira >/dev/null 2>&1; then
                jira issue view "${issue_key}" --plain 2>/dev/null | grep -i "summary:" | head -n 1 | sed 's/^[sS]ummary:[[:space:]]*//' || echo "Task ${issue_key}"
            else
                echo "Task ${issue_key}"
            fi
            ;;
        linear)
            echo "Task ${issue_key}"
            ;;
        *)
            echo "Task ${issue_key}"
            ;;
    esac
}
