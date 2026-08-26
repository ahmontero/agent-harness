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

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

JSON_MODE=false
SEARCH_PATH="${REPO_DIR}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --path) SEARCH_PATH="$2"; shift 2 ;;
        -h|--help) echo "Usage: harness debt [--json] [--path <path>]"; exit 0 ;;
        *) shift ;;
    esac
done

cd "${REPO_DIR}"

if command -v rg >/dev/null 2>&1; then
    if [ "${JSON_MODE}" = true ]; then
        rg --json "# pragmatism:|# defer:" "${SEARCH_PATH}" 2>/dev/null || echo "[]"
    else
        log_info "Scanning for technical debt markers in ${SEARCH_PATH}..."
        rg -n --color=always "# pragmatism:|# defer:" "${SEARCH_PATH}" 2>/dev/null || log_success "No technical debt markers found!"
    fi
else
    grep -rnE "# pragmatism:|# defer:" "${SEARCH_PATH}" 2>/dev/null || log_success "No technical debt markers found."
fi
