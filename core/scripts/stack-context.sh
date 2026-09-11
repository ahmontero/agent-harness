#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-context.sh
# Fast, Token-Efficient Workspace Context Signal Extractor (<1s)
# ==============================================================================
#
# Every number here is read by an agent that cannot check it, so each one is produced by
# the same helper as the command a human would run to verify it. The JSON is emitted by jq
# rather than a heredoc: a quote or a backslash anywhere in a path, branch, or profile name
# used to produce a document no consumer could parse.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/specs.sh"
source "${SCRIPT_DIR}/lib/debt.sh"

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
            # An unrecognised option used to be discarded, so `harness context --jsonn`
            # printed the human report and an agent parsing JSON got prose.
            log_error "Unknown context option: $1"
            echo "Usage: harness context [--json]"
            exit 1
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

SPECS_COUNT="$(active_delta_spec_count "${REPO_DIR}/specs")"

# An unavailable count is reported as unavailable. Reporting it as zero is the same
# failure as a gate that prints success after suppressing its own error.
DEBT_COUNT="$(debt_count "${REPO_DIR}" "${REPO_DIR}" false 2>/dev/null)" || DEBT_COUNT=""

if [ "${JSON_OUTPUT}" = true ]; then
    jq -n \
        --arg profile "${ACTIVE_PROFILE}" \
        --arg repository "${REPO_DIR}" \
        --arg branch "${BRANCH}" \
        --arg trunkBranch "${TRUNK}" \
        --argjson dirty "${DIRTY}" \
        --arg testRunner "${TEST_RUNNER}" \
        --arg issueProvider "${ISSUE_PROVIDER}" \
        --arg implementer "${ORCHESTRATE_IMPLEMENTER}" \
        --arg reviewer "${ORCHESTRATE_REVIEWER}" \
        --argjson activeDeltaSpecs "${SPECS_COUNT}" \
        --argjson technicalDebtMarkers "${DEBT_COUNT:-null}" \
        '{
            profile: $profile,
            repository: $repository,
            branch: $branch,
            trunkBranch: $trunkBranch,
            dirty: $dirty,
            testRunner: $testRunner,
            issueProvider: $issueProvider,
            orchestrateModels: { implementer: $implementer, reviewer: $reviewer },
            activeDeltaSpecs: $activeDeltaSpecs,
            technicalDebtMarkers: $technicalDebtMarkers
        }'
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
Technical Debt Items: ${DEBT_COUNT:-${YELLOW}unavailable: the scan could not complete${RESET}}
TEXT_EOF
fi
