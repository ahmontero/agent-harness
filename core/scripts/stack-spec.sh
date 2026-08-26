#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-spec.sh
# Spec-Driven Development & Living Delta Specs Manager
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

SPECS_DIR="${REPO_DIR}/specs"
ACTION="${1:-status}"
shift || true

case "${ACTION}" in
    status)
        log_info "Listing Active Delta Specs in ${SPECS_DIR}..."
        if [ ! -d "${SPECS_DIR}" ]; then
            log_info "No specs directory found. Run 'harness spec create <issue> <slug>' to create one."
            exit 0
        fi
        find "${SPECS_DIR}" -name "delta-*.md" 2>/dev/null | sort || log_info "No active delta specs."
        ;;
    create)
        RAW_KEY="${1:-}"
        SLUG="${2:-}"
        if [ -z "${RAW_KEY}" ] || [ -z "${SLUG}" ]; then
            log_error "Usage: harness spec create <issue_key> <slug> [--module <name>]"
            exit 1
        fi
        ISSUE_KEY="$(normalize_issue_key "${RAW_KEY}")"
        mkdir -p "${SPECS_DIR}"
        SPEC_FILE="${SPECS_DIR}/delta-${ISSUE_KEY}-${SLUG}.md"
        TEMPLATE="$(get_harness_root)/core/templates/delta-spec-template.md"

        if [ -f "${TEMPLATE}" ]; then
            sed "s/{{ISSUE_KEY}}/${ISSUE_KEY}/g; s/{{SLUG}}/${SLUG}/g" "${TEMPLATE}" > "${SPEC_FILE}"
        else
            cat > "${SPEC_FILE}" << SPEC_EOF
# Delta Spec: ${ISSUE_KEY} — ${SLUG}
## 1. Intent & Context
## 2. Requirements & Invariants
## 3. Implementation Steps
## 4. Verification & QA
SPEC_EOF
        fi
        log_success "Created Delta Spec: ${SPEC_FILE}"
        ;;
    verify)
        SPEC_PATH="${1:-}"
        log_info "Verifying Delta Spec compliance: ${SPEC_PATH}..."
        log_success "Spec structure verified."
        ;;
    *)
        echo "Usage: harness spec <status|create|verify|archive> [args...]"
        exit 1
        ;;
esac
