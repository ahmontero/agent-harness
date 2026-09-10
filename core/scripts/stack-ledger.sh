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
MAX_LABEL_BYTES=200
DEFAULT_STAGNATION_THRESHOLD=2
SIGNATURE_LENGTH=12
STAGNANT_EXIT=3

usage() {
    cat <<USAGE_EOF
Usage:
  harness ledger start <run_id>
  harness ledger append <run_id> <phase|ruling|deferred|parked|complete|failure> <text>
  harness ledger show <run_id>
  harness ledger rulings <run_id>
  harness ledger signature                     (failure text on stdin)
  harness ledger failure <run_id> [label]      (failure text on stdin)
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
        phase|ruling|deferred|parked|complete|failure) ;;
        *)
            log_error "Unsupported ledger kind '$1'. Use phase, ruling, deferred, parked, complete, or failure."
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

validate_label() {
    local label="$1"
    local bytes
    case "${label}" in
        *$'\n'*)
            log_error "Ledger label must be a single line."
            return 1
            ;;
    esac
    bytes="$(printf '%s' "${label}" | wc -c | tr -d ' ')"
    if [ "${bytes}" -gt "${MAX_LABEL_BYTES}" ]; then
        log_error "Ledger label exceeds ${MAX_LABEL_BYTES} bytes."
        return 1
    fi
}

# Reduce a failure capture to a stable 12-character signature. The substitutions run in a
# fixed order: timestamps, then absolute directory prefixes, then line and column suffixes,
# then long numeric IDs. Timestamps must precede the line rule, or the ':MM:SS' of a
# timestamp would be rewritten as a line number.
#
# There is deliberately no rule for the repository root. Normalizing it to a token of its
# own would make one file sign two ways -- '<target>/src/widget.py' from this checkout and
# '<path>/widget.py' from any other -- which is the opposite of what a signature is for.
# The absolute-directory rule already collapses every checkout to the same token.
#
# The capture is streamed and never assigned to a shell variable, so a multi-megabyte test
# log is bounded by pipe buffers rather than process memory. The trailing 'tr -d' is what
# makes the digest portable: BSD sed appends a final newline where GNU sed does not, and
# that one byte would otherwise change the hash between CI runners.
failure_signature() {
    local digest empty_digest
    empty_digest="$(printf '' | git -C "${REPO_DIR}" hash-object --stdin)"
    digest="$(
        sed -E \
            -e 's#[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?#<timestamp>#g' \
            -e 's#(^|[[:space:]])/([^[:space:]/]+/)+#\1<path>/#g' \
            -e 's#:[0-9]+(:[0-9]+)?#:<line>#g' \
            -e 's#[0-9]{6,}#<id>#g' |
            tr -s '[:space:]' ' ' |
            sed -e 's/^ //' -e 's/ $//' |
            tr -d '\n' |
            git -C "${REPO_DIR}" hash-object --stdin
    )"
    if [ "${digest}" = "${empty_digest}" ]; then
        log_error "Failure text is empty after normalization. A failure with no content is not a signature."
        return 1
    fi
    printf '%s' "${digest:0:${SIGNATURE_LENGTH}}"
}

resolve_stagnation_threshold() {
    local raw
    raw="$(get_profile_value 'loop.stagnationThreshold' "${DEFAULT_STAGNATION_THRESHOLD}")"
    if ! [[ "${raw}" =~ ^[0-9]+$ ]] || [ "${raw}" -lt 2 ]; then
        log_error "loop.stagnationThreshold must be an integer of at least 2; got '${raw}'."
        return 1
    fi
    printf '%s' "${raw}"
}

# Stagnant when the run's last <threshold> failure signatures are all the same. Lines of
# every other kind are ignored, because a round that records progress does not clear the
# failure history that preceded it.
is_stagnant() {
    local file="$1" threshold="$2"
    local recent
    recent="$(awk '$2 == "failure" { print $3 }' "${file}" | tail -n "${threshold}")"
    [ "$(printf '%s\n' "${recent}" | grep -c .)" -eq "${threshold}" ] || return 1
    [ "$(printf '%s\n' "${recent}" | sort -u | grep -c .)" -eq 1 ]
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
    signature)
        [ $# -eq 0 ] || { usage; exit 1; }
        failure_signature
        printf '\n'
        ;;
    failure)
        RUN_ID="${1:-}"
        [ $# -ge 1 ] && [ $# -le 2 ] || { usage; exit 1; }
        validate_run_id "${RUN_ID}"
        if [ $# -eq 2 ]; then
            validate_label "$2"
        fi
        THRESHOLD="$(resolve_stagnation_threshold)"
        LEDGER_FILE="$(require_ledger "${RUN_ID}")"
        SIGNATURE="$(failure_signature)"
        if [ $# -eq 2 ]; then
            BODY="sig:${SIGNATURE} — $2"
        else
            BODY="sig:${SIGNATURE}"
        fi
        printf '%s  failure  %s\n' "$(timestamp_now)" "${BODY}" >> "${LEDGER_FILE}"
        if is_stagnant "${LEDGER_FILE}" "${THRESHOLD}"; then
            echo "stagnant"
            exit "${STAGNANT_EXIT}"
        fi
        echo "continue"
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
