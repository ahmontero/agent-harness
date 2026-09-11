#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-debt.sh
# Technical Debt & Pragmatism Marker Harvester
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/debt.sh"

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

usage() {
    cat <<USAGE_EOF
Usage:
  harness debt [--json] [--all] [--path <path>]

Options:
  --json          Emit a JSON array of {file, line, text} objects
  --all           Include untracked files; by default only tracked files are scanned
  --path <path>   Scan this path instead of the whole repository
  -h, --help      Show this help message
USAGE_EOF
}

JSON_MODE=false
INCLUDE_UNTRACKED=false
SEARCH_PATH="${REPO_DIR}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --all) INCLUDE_UNTRACKED=true; shift ;;
        --path)
            [ -n "${2:-}" ] || { log_error "--path requires a path."; exit 1; }
            SEARCH_PATH="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown debt option: $1"; usage; exit 1 ;;
    esac
done

cd "${REPO_DIR}"

SCAN_STATUS=0
MATCHES="$(debt_scan "${REPO_DIR}" "${SEARCH_PATH}" "${INCLUDE_UNTRACKED}")" || SCAN_STATUS=$?

if [ "${SCAN_STATUS}" -ne 0 ]; then
    log_error "The debt scan could not complete for ${SEARCH_PATH}; no count is reported."
    exit "${SCAN_STATUS}"
fi

if [ "${JSON_MODE}" = true ]; then
    # A single JSON array. The previous --json emitted either a human log line or
    # ripgrep's JSON-Lines stream, and the workflow bundles instruct agents to parse it.
    #
    # The file group is greedy so a path containing a colon still parses, and a line that
    # cannot be parsed fails the command rather than being dropped: silently emitting fewer
    # findings than the text listing shows is the class of defect this delta is about.
    printf '%s\n' "${MATCHES}" | jq -R -s '
        "^(?<file>.*):(?<line>[0-9]+):(?<text>.*)$" as $row
        | (split("\n") | map(select(length > 0))) as $lines
        | ($lines | map(if test($row) then capture($row) else null end)) as $parsed
        | if ($parsed | map(select(. == null)) | length) > 0
          then ($lines - ($parsed | map(select(. != null)) | map(.file + ":" + .line + ":" + .text))
                | "unparseable scanner output: \(.)" | error)
          else $parsed
               | map({file: .file, line: (.line | tonumber), text: (.text | sub("^[[:space:]]+"; ""))})
          end'
    exit 0
fi

if [ -z "${MATCHES}" ]; then
    log_success "No technical debt markers found."
    exit 0
fi

log_info "Technical debt markers in ${SEARCH_PATH}:"
printf '%s\n' "${MATCHES}"
