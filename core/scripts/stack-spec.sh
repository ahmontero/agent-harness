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
source "${SCRIPT_DIR}/lib/specs.sh"

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

SPECS_DIR="${REPO_DIR}/specs"
ACTION="${1:-status}"
shift || true

# Both the issue key and the slug become part of a filename, and neither may leave specs/.
# `harness spec create AH-1 a/b` used to reach sed and fail with a raw redirection error
# naming a path outside the directory the command is about.
require_safe_spec_token() {
    local label="$1"
    local value="$2"
    if ! [[ "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        log_error "Unsafe ${label} '${value}'. Use letters, numbers, dots, dashes, or underscores, starting with a letter or number."
        return 1
    fi
    case "${value}" in
        *..*)
            log_error "Unsafe ${label} '${value}'. A '..' segment would leave the specs directory."
            return 1
            ;;
    esac
}

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
        done < <(active_delta_specs "${SPECS_DIR}")
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
        STATUS_JSON=false
        while [ $# -gt 0 ]; do
            case "$1" in
                --json) STATUS_JSON=true; shift ;;
                *) log_error "Unknown spec status option: $1"; exit 1 ;;
            esac
        done

        if [ "${STATUS_JSON}" = true ]; then
            # The flag was advertised in the dispatcher help and dropped with every other
            # argument, so the JSON form printed the human listing.
            active_delta_specs "${SPECS_DIR}" | jq -R -s 'split("\n") | map(select(length > 0))'
            exit 0
        fi

        log_info "Listing Active Delta Specs in ${SPECS_DIR}..."
        if [ ! -d "${SPECS_DIR}" ]; then
            log_info "No specs directory found. Run 'harness spec create <issue> <slug>' to create one."
            exit 0
        fi
        active_delta_specs "${SPECS_DIR}" || log_info "No active delta specs."
        ;;
    create)
        RAW_KEY=""
        SLUG=""
        MODULE=""
        CREATE_POSITIONAL=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --module)
                    if [ -z "${2:-}" ]; then
                        log_error "--module requires a name."
                        exit 1
                    fi
                    MODULE="$2"
                    shift 2
                    ;;
                -*)
                    log_error "Unknown spec create option: $1"
                    exit 1
                    ;;
                *)
                    CREATE_POSITIONAL+=("$1")
                    shift
                    ;;
            esac
        done
        RAW_KEY="${CREATE_POSITIONAL[0]:-}"
        SLUG="${CREATE_POSITIONAL[1]:-}"

        if [ -z "${RAW_KEY}" ] || [ -z "${SLUG}" ]; then
            log_error "Usage: harness spec create <issue_key> <slug> [--module <name>]"
            exit 1
        fi
        ISSUE_KEY="$(normalize_issue_key "${RAW_KEY}")"
        require_safe_spec_token "issue key" "${ISSUE_KEY}"
        require_safe_spec_token "slug" "${SLUG}"
        [ -z "${MODULE}" ] || require_safe_spec_token "module name" "${MODULE}"

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
        if [ -n "${MODULE}" ]; then
            SPEC_TEMP="$(mktemp "${SPEC_FILE}.harness.XXXXXX")"
            awk -v module="${MODULE}" '
                { print }
                /^- \*\*Issue \/ Ticket:\*\*/ && !done { printf "- **Module:** %s\n", module; done = 1 }
            ' "${SPEC_FILE}" > "${SPEC_TEMP}"
            mv "${SPEC_TEMP}" "${SPEC_FILE}"
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
            # A spec created with --module carries its module, so archiving it needs no
            # second statement of the same fact.
            RESOLVED_FOR_MODULE="$(resolve_spec_path "${REQUESTED_PATH}")"
            if [ -f "${RESOLVED_FOR_MODULE}" ]; then
                MODULE_NAME="$(sed -n 's/^- \*\*Module:\*\* *//p' "${RESOLVED_FOR_MODULE}" | head -n 1)"
            fi
        fi
        if [ -z "${MODULE_NAME}" ]; then
            log_error "Usage: harness spec archive <module_name> [spec_path]"
            log_info "The spec records no module, so name the one to archive it under."
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
