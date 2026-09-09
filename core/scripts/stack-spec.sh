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

resolve_spec_path() {
    local requested="${1:-}"
    if [ -n "${requested}" ]; then
        if [[ "${requested}" = /* ]]; then
            echo "${requested}"
        else
            echo "${REPO_DIR}/${requested}"
        fi
        return
    fi

    local candidates=()
    if [ -d "${SPECS_DIR}" ]; then
        while IFS= read -r candidate; do
            candidates+=("${candidate}")
        done < <(find "${SPECS_DIR}" -maxdepth 1 -type f -name "delta-*.md" | sort)
    fi

    if [ ${#candidates[@]} -eq 0 ]; then
        log_error "No active delta spec found. Pass an explicit spec path."
        return 1
    fi
    if [ ${#candidates[@]} -gt 1 ]; then
        log_error "Multiple active delta specs found. Pass an explicit spec path."
        return 1
    fi
    echo "${candidates[0]}"
}

verify_spec_file() {
    local spec_path="$1"
    local required_headings=(
        "## 1. Intent & Context"
        "## 2. Requirements & Domain Floor Invariants"
        "## 3. Implementation Plan"
        "## 4. Verification & QA"
    )

    if [ ! -f "${spec_path}" ]; then
        log_error "Delta spec not found: ${spec_path}"
        return 1
    fi
    if [ ! -s "${spec_path}" ]; then
        log_error "Delta spec is empty: ${spec_path}"
        return 1
    fi
    if ! grep -q '^# Delta Spec:' "${spec_path}"; then
        log_error "Delta spec is missing its title: # Delta Spec:"
        return 1
    fi

    local heading
    for heading in "${required_headings[@]}"; do
        if ! grep -Fxq "${heading}" "${spec_path}"; then
            log_error "Delta spec is missing required heading: ${heading}"
            return 1
        fi
    done

    if grep -Eq '\[(Brief|Paths?|TODO|TBD|Describe)[^]]*\]|:[[:space:]]*\.\.\.[[:space:]]*$' "${spec_path}"; then
        log_error "Delta spec still contains template placeholders: ${spec_path}"
        return 1
    fi
}

case "${ACTION}" in
    status)
        log_info "Listing Active Delta Specs in ${SPECS_DIR}..."
        if [ ! -d "${SPECS_DIR}" ]; then
            log_info "No specs directory found. Run 'harness spec create <issue> <slug>' to create one."
            exit 0
        fi
        find "${SPECS_DIR}" -maxdepth 1 -type f -name "delta-*.md" 2>/dev/null | sort || log_info "No active delta specs."
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
        SPEC_PATH="$(resolve_spec_path "${1:-}")"
        log_info "Verifying Delta Spec compliance: ${SPEC_PATH}..."
        verify_spec_file "${SPEC_PATH}"
        log_success "Delta spec structure and content verified: ${SPEC_PATH}"
        ;;
    archive)
        MODULE_NAME="${1:-}"
        REQUESTED_PATH="${2:-}"
        if [ -z "${MODULE_NAME}" ]; then
            log_error "Usage: harness spec archive <module_name> [spec_path]"
            exit 1
        fi
        if ! [[ "${MODULE_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
            log_error "Unsafe module name '${MODULE_NAME}'. Use letters, numbers, dots, dashes, or underscores."
            exit 1
        fi

        SPEC_PATH="$(resolve_spec_path "${REQUESTED_PATH}")"
        verify_spec_file "${SPEC_PATH}"

        SPECS_ROOT="$(mkdir -p "${SPECS_DIR}" && cd "${SPECS_DIR}" && pwd -P)"
        SPEC_PARENT="$(cd "$(dirname "${SPEC_PATH}")" 2>/dev/null && pwd -P)" || {
            log_error "Cannot resolve spec path: ${SPEC_PATH}"
            exit 1
        }
        case "${SPEC_PARENT}/" in
            "${SPECS_ROOT}/"*) ;;
            *)
                log_error "Refusing to archive a file outside ${SPECS_ROOT}: ${SPEC_PATH}"
                exit 1
                ;;
        esac

        ARCHIVE_DIR="${SPECS_DIR}/archive/${MODULE_NAME}"
        ARCHIVE_PATH="${ARCHIVE_DIR}/$(basename "${SPEC_PATH}")"
        if [ -e "${ARCHIVE_PATH}" ]; then
            log_error "Archive destination already exists: ${ARCHIVE_PATH}"
            exit 1
        fi
        mkdir -p "${ARCHIVE_DIR}"
        mv "${SPEC_PATH}" "${ARCHIVE_PATH}"
        log_success "Archived Delta Spec: ${ARCHIVE_PATH}"
        ;;
    *)
        echo "Usage: harness spec <status|create|verify|archive> [args...]"
        exit 1
        ;;
esac
