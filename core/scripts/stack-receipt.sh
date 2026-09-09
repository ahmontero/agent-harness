#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-receipt.sh
# Local privacy-preserving workflow execution receipts
# ==============================================================================

set -eo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"

ACTIVE_PROFILE="$(get_active_profile)"
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

if ! command -v jq >/dev/null 2>&1; then
    log_error "The receipt command requires jq."
    exit 1
fi

COMMON_DIR="$(git -C "${REPO_DIR}" rev-parse --git-common-dir)"
if [[ "${COMMON_DIR}" != /* ]]; then
    COMMON_DIR="$(cd "${REPO_DIR}/${COMMON_DIR}" && pwd -P)"
fi
RECEIPTS_DIR="${COMMON_DIR}/agent-harness/runs"
mkdir -p "${RECEIPTS_DIR}"

usage() {
    cat <<USAGE_EOF
Usage:
  harness receipt start <implement|fix|investigate> [--issue <token>]
  harness receipt phase <run_id> <phase_token> <started|passed|failed|blocked|skipped>
  harness receipt finish <run_id> <completed|failed|blocked|cancelled>
USAGE_EOF
}

validate_token() {
    local label="$1"
    local value="$2"
    if ! [[ "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
        log_error "Invalid ${label}. Use 1-64 letters, numbers, dots, dashes, or underscores."
        return 1
    fi
}

validate_workflow() {
    case "$1" in
        implement|fix|investigate|orchestrate) ;;
        *)
            log_error "Unsupported workflow '$1'. Use implement, fix, investigate, or orchestrate."
            return 1
            ;;
    esac
}

validate_phase() {
    local workflow="$1"
    local phase="$2"
    case "${workflow}:${phase}" in
        implement:understand|implement:scope|implement:tdd|implement:simplify|implement:qa|implement:review|\
        fix:reproduce|fix:diagnose|fix:root-cause|fix:regression|fix:fix|fix:qa|fix:review|\
        investigate:frame|investigate:evidence|investigate:constraints|investigate:options|investigate:tradeoffs|investigate:recommendation|\
        orchestrate:admit|orchestrate:dispatch|orchestrate:review|orchestrate:resolve|orchestrate:close)
            ;;
        *)
            log_error "Unsupported phase '${phase}' for workflow '${workflow}'."
            return 1
            ;;
    esac
}

timestamp_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

RECEIPT_LOCK=""

release_receipt_lock() {
    if [ -n "${RECEIPT_LOCK}" ]; then
        rmdir "${RECEIPT_LOCK}" 2>/dev/null || true
        RECEIPT_LOCK=""
    fi
}

acquire_receipt_lock() {
    local run_id="$1"
    validate_token "run ID" "${run_id}" || return 1
    RECEIPT_LOCK="${RECEIPTS_DIR}/.${run_id}.lock"
    if ! mkdir "${RECEIPT_LOCK}" 2>/dev/null; then
        log_error "Receipt is busy: ${run_id}"
        RECEIPT_LOCK=""
        return 1
    fi
    trap release_receipt_lock EXIT
}

load_active_receipt() {
    local run_id="$1"
    validate_token "run ID" "${run_id}" || return 1
    local path="${RECEIPTS_DIR}/${run_id}.jsonl"
    if [ -L "${path}" ] || [ ! -f "${path}" ]; then
        log_error "Receipt not found: ${run_id}"
        return 1
    fi
    if ! jq -s -e --arg run_id "${run_id}" '
        def sorted_keys: keys | sort;
        length > 0 and
        .[0].schemaVersion == 1 and
        .[0].runId == $run_id and
        .[0].event == "workflow_started" and
        (.[0].workflow as $w | ["implement", "fix", "investigate", "orchestrate"] | index($w)) != null and
        (.[0].workflow as $workflow | all(.[];
            .schemaVersion == 1 and
            .runId == $run_id and
            .workflow == $workflow and
            (
                (.event == "workflow_started" and sorted_keys == ["branch", "event", "issue", "profile", "runId", "schemaVersion", "timestamp", "workflow"]) or
                (.event == "phase" and sorted_keys == ["event", "phase", "runId", "schemaVersion", "status", "timestamp", "workflow"]) or
                (.event == "workflow_finished" and sorted_keys == ["event", "outcome", "runId", "schemaVersion", "timestamp", "workflow"])
            )
        ))
    ' "${path}" >/dev/null 2>&1; then
        log_error "Receipt is invalid or has been tampered with: ${run_id}"
        return 1
    fi
    if jq -e 'select(.event == "workflow_finished")' "${path}" >/dev/null 2>&1; then
        log_error "Receipt is already terminal: ${run_id}"
        return 1
    fi
    echo "${path}"
}

ACTION="${1:-}"
shift || true

case "${ACTION}" in
    start)
        WORKFLOW="${1:-}"
        shift || true
        validate_workflow "${WORKFLOW}"

        ISSUE=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --issue)
                    ISSUE="${2:-}"
                    [ -n "${ISSUE}" ] || { log_error "--issue requires a token."; exit 1; }
                    shift 2
                    ;;
                *)
                    log_error "Unknown receipt start option: $1"
                    usage
                    exit 1
                    ;;
            esac
        done
        [ -z "${ISSUE}" ] || validate_token "issue token" "${ISSUE}"

        TEMP_PATH="$(mktemp "${RECEIPTS_DIR}/${WORKFLOW}-XXXXXX")"
        RUN_ID="$(basename "${TEMP_PATH}")"
        BRANCH="$(get_current_branch "${REPO_DIR}")"
        jq -nc \
            --arg run_id "${RUN_ID}" \
            --arg timestamp "$(timestamp_now)" \
            --arg workflow "${WORKFLOW}" \
            --arg issue "${ISSUE}" \
            --arg profile "${ACTIVE_PROFILE}" \
            --arg branch "${BRANCH}" \
            '{
                schemaVersion: 1,
                runId: $run_id,
                timestamp: $timestamp,
                workflow: $workflow,
                event: "workflow_started",
                issue: (if $issue == "" then null else $issue end),
                profile: $profile,
                branch: $branch
            }' > "${TEMP_PATH}"
        mv "${TEMP_PATH}" "${TEMP_PATH}.jsonl"
        printf '%s\n' "${RUN_ID}"
        ;;
    phase)
        RUN_ID="${1:-}"
        PHASE="${2:-}"
        STATUS="${3:-}"
        [ $# -eq 3 ] || { usage; exit 1; }
        validate_token "phase token" "${PHASE}"
        case "${STATUS}" in
            started|passed|failed|blocked|skipped) ;;
            *) log_error "Unsupported phase status: ${STATUS}"; exit 1 ;;
        esac
        acquire_receipt_lock "${RUN_ID}"
        RECEIPT_FILE="$(load_active_receipt "${RUN_ID}")"
        WORKFLOW="$(jq -r 'select(.event == "workflow_started") | .workflow' "${RECEIPT_FILE}" | head -n 1)"
        validate_workflow "${WORKFLOW}"
        validate_phase "${WORKFLOW}" "${PHASE}"
        jq -nc \
            --arg run_id "${RUN_ID}" \
            --arg timestamp "$(timestamp_now)" \
            --arg workflow "${WORKFLOW}" \
            --arg phase "${PHASE}" \
            --arg status "${STATUS}" \
            '{schemaVersion: 1, runId: $run_id, timestamp: $timestamp, workflow: $workflow, event: "phase", phase: $phase, status: $status}' \
            >> "${RECEIPT_FILE}"
        release_receipt_lock
        ;;
    finish)
        RUN_ID="${1:-}"
        OUTCOME="${2:-}"
        [ $# -eq 2 ] || { usage; exit 1; }
        case "${OUTCOME}" in
            completed|failed|blocked|cancelled) ;;
            *) log_error "Unsupported workflow outcome: ${OUTCOME}"; exit 1 ;;
        esac
        acquire_receipt_lock "${RUN_ID}"
        RECEIPT_FILE="$(load_active_receipt "${RUN_ID}")"
        WORKFLOW="$(jq -r 'select(.event == "workflow_started") | .workflow' "${RECEIPT_FILE}" | head -n 1)"
        validate_workflow "${WORKFLOW}"
        jq -nc \
            --arg run_id "${RUN_ID}" \
            --arg timestamp "$(timestamp_now)" \
            --arg workflow "${WORKFLOW}" \
            --arg outcome "${OUTCOME}" \
            '{schemaVersion: 1, runId: $run_id, timestamp: $timestamp, workflow: $workflow, event: "workflow_finished", outcome: $outcome}' \
            >> "${RECEIPT_FILE}"
        release_receipt_lock
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        log_error "Unknown receipt action: ${ACTION:-<none>}"
        usage
        exit 1
        ;;
esac
