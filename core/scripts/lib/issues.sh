#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/issues.sh
# Universal Issue Tracker Adapter (GitHub Issues, Jira, Linear, GitLab, Standalone)
# ==============================================================================

set -eo pipefail

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
