#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-context.sh
# Fast, Token-Efficient Workspace Context Signal Extractor (<1s)
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            echo "Usage: harness context [--json]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

BRANCH="$(get_current_branch "${REPO_DIR}")"
TRUNK="$(get_trunk_branch "${REPO_DIR}")"
TEST_RUNNER="$(get_profile_value "qa.testRunner" "unknown")"
ISSUE_PROVIDER="$(get_profile_value "issueTracker.provider" "standalone")"
ORCHESTRATE_IMPLEMENTER="$(get_profile_value "orchestrate.models.implementer" "sonnet")"
ORCHESTRATE_REVIEWER="$(get_profile_value "orchestrate.models.reviewer" "opus")"
DIRTY="false"
is_working_tree_dirty "${REPO_DIR}" && DIRTY="true"

# Count open delta specs if any
SPECS_COUNT=0
if [ -d "${REPO_DIR}/specs" ]; then
    SPECS_COUNT=$(find "${REPO_DIR}/specs" -name "delta-*.md" 2>/dev/null | wc -l | tr -d ' ')
fi

# Count debt markers if any
DEBT_COUNT=0
if command -v rg >/dev/null 2>&1; then
    DEBT_COUNT=$(rg -c "# pragmatism:|# defer:" "${REPO_DIR}" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
fi

if [ "${JSON_OUTPUT}" = true ]; then
    cat <<JSON_EOF
{
  "profile": "${ACTIVE_PROFILE}",
  "repository": "${REPO_DIR}",
  "branch": "${BRANCH}",
  "trunkBranch": "${TRUNK}",
  "dirty": ${DIRTY},
  "testRunner": "${TEST_RUNNER}",
  "issueProvider": "${ISSUE_PROVIDER}",
  "orchestrateModels": {
    "implementer": "${ORCHESTRATE_IMPLEMENTER}",
    "reviewer": "${ORCHESTRATE_REVIEWER}"
  },
  "activeDeltaSpecs": ${SPECS_COUNT},
  "technicalDebtMarkers": ${DEBT_COUNT}
}
JSON_EOF
else
    cat <<TEXT_EOF
${BOLD}${CYAN}=== Agent Workspace Context ===${RESET}
Profile:              ${BOLD}${ACTIVE_PROFILE}${RESET}
Target Repo:          ${REPO_DIR}
Current Branch:       ${BOLD}${GREEN}${BRANCH}${RESET} (Trunk: ${TRUNK})
Working Tree Dirty:   $([ "${DIRTY}" = "true" ] && echo "${YELLOW}Yes${RESET}" || echo "${GREEN}Clean${RESET}")
Test Runner:          ${TEST_RUNNER}
Issue Provider:       ${ISSUE_PROVIDER}
Orchestrate Models:   implementer=${ORCHESTRATE_IMPLEMENTER} reviewer=${ORCHESTRATE_REVIEWER}
Active Delta Specs:   ${SPECS_COUNT}
Technical Debt Items: ${DEBT_COUNT}
TEXT_EOF
fi
