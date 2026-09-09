#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-ledger.sh
# Durable append-only progress ledger for bounded workflow review loops
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

COMMON_DIR="$(git -C "${REPO_DIR}" rev-parse --git-common-dir)"
if [[ "${COMMON_DIR}" != /* ]]; then
    COMMON_DIR="$(cd "${REPO_DIR}/${COMMON_DIR}" && pwd -P)"
fi
LEDGERS_DIR="${COMMON_DIR}/agent-harness/ledgers"
mkdir -p "${LEDGERS_DIR}"

MAX_TEXT_BYTES=512

usage() {
    cat <<USAGE_EOF
Usage:
  harness ledger start <run_id>
  harness ledger append <run_id> <phase|ruling|deferred|parked|complete> <text>
  harness ledger show <run_id>
  harness ledger rulings <run_id>
USAGE_EOF
}

validate_run_id() {
    if ! [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
        log_error "Invalid run ID. Use 1-64 letters, numbers, dots, dashes, or underscores."
        return 1
    fi
}

validate_kind() {
    case "$1" in
        phase|ruling|deferred|parked|complete) ;;
        *)
            log_error "Unsupported ledger kind '$1'. Use phase, ruling, deferred, parked, or complete."
            return 1
            ;;
    esac
}

validate_text() {
    local text="$1"
    local bytes
    if [ -z "${text}" ]; then
        log_error "Ledger text must not be empty."
        return 1
    fi
    case "${text}" in
        *$'\n'*)
            log_error "Ledger text must be a single line."
            return 1
            ;;
    esac
    bytes="$(printf '%s' "${text}" | wc -c | tr -d ' ')"
    if [ "${bytes}" -gt "${MAX_TEXT_BYTES}" ]; then
        log_error "Ledger text exceeds ${MAX_TEXT_BYTES} bytes."
        return 1
    fi
}

ledger_path() {
    printf '%s/%s.md' "${LEDGERS_DIR}" "$1"
}

ledger_header() {
    printf '# Harness ledger — run: %s' "$1"
}

require_ledger() {
    local run_id="$1"
    local path
    path="$(ledger_path "${run_id}")"
    if [ -L "${path}" ] || [ ! -f "${path}" ]; then
        log_error "Ledger not found: ${run_id}"
        return 1
    fi
    if [ "$(head -n 1 "${path}")" != "$(ledger_header "${run_id}")" ]; then
        log_error "Ledger does not carry its own run identity: ${run_id}"
        return 1
    fi
    printf '%s' "${path}"
}

timestamp_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

ACTION="${1:-}"
shift || true

case "${ACTION}" in
    start)
        RUN_ID="${1:-}"
        [ $# -eq 1 ] || { usage; exit 1; }
        validate_run_id "${RUN_ID}"
        LEDGER_FILE="$(ledger_path "${RUN_ID}")"
        if [ -e "${LEDGER_FILE}" ] || [ -L "${LEDGER_FILE}" ]; then
            require_ledger "${RUN_ID}" >/dev/null
        else
            printf '%s\n' "$(ledger_header "${RUN_ID}")" > "${LEDGER_FILE}"
        fi
        printf '%s\n' "${LEDGER_FILE}"
        ;;
    append)
        RUN_ID="${1:-}"
        KIND="${2:-}"
        TEXT="${3:-}"
        [ $# -eq 3 ] || { usage; exit 1; }
        validate_run_id "${RUN_ID}"
        validate_kind "${KIND}"
        validate_text "${TEXT}"
        LEDGER_FILE="$(require_ledger "${RUN_ID}")"
        printf '%s  %s  %s\n' "$(timestamp_now)" "${KIND}" "${TEXT}" >> "${LEDGER_FILE}"
        ;;
    show)
        RUN_ID="${1:-}"
        [ $# -eq 1 ] || { usage; exit 1; }
        validate_run_id "${RUN_ID}"
        LEDGER_FILE="$(require_ledger "${RUN_ID}")"
        cat "${LEDGER_FILE}"
        ;;
    rulings)
        RUN_ID="${1:-}"
        [ $# -eq 1 ] || { usage; exit 1; }
        validate_run_id "${RUN_ID}"
        LEDGER_FILE="$(require_ledger "${RUN_ID}")"
        awk '$2 == "ruling" || $2 == "parked"' "${LEDGER_FILE}"
        ;;
    ""|-h|--help)
        usage
        ;;
    *)
        log_error "Unknown ledger action: ${ACTION}"
        usage
        exit 1
        ;;
esac
