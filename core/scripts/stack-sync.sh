#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-sync.sh
# Skill surface drift report and synchronization
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/surface.sh"

HARNESS_ROOT="$(get_harness_root)"

usage() {
    cat <<USAGE_EOF
Usage:
  harness sync [options]

Options:
  --check           Report drift and exit non-zero if any surface is stale. Mutates nothing.
  --target <path>   Act on one repository's surfaces instead of the current one
  --global          Act on the global surfaces only
  --expert          Synchronize in expert mode regardless of what the manifest records
  -h, --help        Show this help message

With neither --target nor --global, the global surfaces are synchronized, and so are the
current repository's when it already carries a managed surface. Synchronization repairs
existing surfaces; it never installs a new one. Use 'harness init' for that.
USAGE_EOF
}

CHECK_ONLY=false
EXPLICIT_TARGET=""
GLOBAL_ONLY=false
EXPERT_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK_ONLY=true; shift ;;
        --target) EXPLICIT_TARGET="$2"; shift 2 ;;
        --global) GLOBAL_ONLY=true; shift ;;
        --expert) EXPERT_MODE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown sync option: $1"; usage; exit 1 ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    log_error "harness sync requires jq."
    exit 1
fi

# Which repository, if any, is in scope. An explicit --target is taken at face value; with
# no flag the current repository qualifies only when it already carries a managed surface,
# which is the guard that keeps the flagless command from writing somewhere new.
REPO_SCOPE=""
if [ -n "${EXPLICIT_TARGET}" ]; then
    REPO_SCOPE="${EXPLICIT_TARGET}"
elif [ "${GLOBAL_ONLY}" != true ]; then
    CANDIDATE="$(get_repo_root "$(pwd)")"
    while IFS=$'\t' read -r directory _; do
        surface_evaluate "${directory}"
        case "${SURFACE_STATE}" in
            current|drifted) REPO_SCOPE="${CANDIDATE}"; break ;;
        esac
    done < <(surface_repo_list "${CANDIDATE}")
fi

INCLUDE_GLOBAL=true
[ -n "${EXPLICIT_TARGET}" ] && INCLUDE_GLOBAL=false

report_scope() {
    local scope_label="$1"
    local listing="$2"
    local directory runtime reason

    log_info "Surfaces for ${BOLD}${scope_label}${RESET}:"
    while IFS=$'\t' read -r directory runtime; do
        [ -n "${directory}" ] || continue
        surface_evaluate "${directory}"
        case "${SURFACE_STATE}" in
            current)
                log_success "  current   ${directory} (${runtime})"
                ;;
            drifted)
                DRIFT_FOUND=true
                log_warn "  drifted   ${directory} (${runtime})"
                for reason in "${SURFACE_REASONS[@]}"; do
                    printf '              %s\n' "${reason}" >&2
                done
                ;;
            *)
                log_info "  ${SURFACE_STATE} ${directory} (${runtime})"
                ;;
        esac
    done <<< "${listing}"
}

if [ "${CHECK_ONLY}" = true ]; then
    DRIFT_FOUND=false
    [ -n "${REPO_SCOPE}" ] && report_scope "${REPO_SCOPE}" "$(surface_repo_list "${REPO_SCOPE}")"
    [ "${INCLUDE_GLOBAL}" = true ] && report_scope "the global surfaces" "$(surface_global_list)"
    if [ "${DRIFT_FOUND}" = true ]; then
        log_error "At least one surface is out of date. Run 'harness sync' to repair it."
        exit 1
    fi
    log_success "Every identified surface is current."
    exit 0
fi

INSTALL_ARGS=()
[ -n "${REPO_SCOPE}" ] && INSTALL_ARGS+=(--sync-target "${REPO_SCOPE}")
[ "${INCLUDE_GLOBAL}" = true ] && INSTALL_ARGS+=(--sync-only)
[ "${EXPERT_MODE}" = true ] && INSTALL_ARGS+=(--expert)

if [ ${#INSTALL_ARGS[@]} -eq 0 ]; then
    log_info "No managed surface was identified. Run 'harness init' to install one here."
    exit 0
fi

exec "${HARNESS_ROOT}/install.sh" "${INSTALL_ARGS[@]}"
