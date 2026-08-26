#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-scan.sh
# JSON-Driven Static Landmine & Security Scanner
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

usage() {
    cat <<USAGE_EOF
Usage:
  harness scan [options]

Options:
  --staged        Scan only staged changes (Default)
  --diff          Scan current working tree diff vs HEAD
  --all           Scan all tracked source files
  --rules <file>  Path to custom landmines.json rules file
  --install-hook  Install scanner as git pre-commit hook in target repo
  -h, --help      Show this help message
USAGE_EOF
}

SCAN_MODE="staged"
CUSTOM_RULES=""
INSTALL_HOOK=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --staged) SCAN_MODE="staged"; shift ;;
        --diff) SCAN_MODE="diff"; shift ;;
        --all) SCAN_MODE="all"; shift ;;
        --rules) CUSTOM_RULES="$2"; shift 2 ;;
        --install-hook) INSTALL_HOOK=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) shift ;;
    esac
done

if [ "${INSTALL_HOOK}" = true ]; then
    HOOK_PATH="${REPO_DIR}/.git/hooks/pre-commit"
    mkdir -p "${REPO_DIR}/.git/hooks"
    cat > "${HOOK_PATH}" << 'HOOK_EOF'
#!/usr/bin/env bash
exec harness scan --staged
HOOK_EOF
    chmod +x "${HOOK_PATH}"
    log_success "Installed Landmine pre-commit hook into ${HOOK_PATH}."
    exit 0
fi

RULES_FILE="${CUSTOM_RULES}"
if [ -z "${RULES_FILE}" ]; then
    RULES_FILE="$(get_profile_value "rules.scanner" "")"
    if [ -n "${RULES_FILE}" ]; then
        eval RULES_FILE="${RULES_FILE}"
        [[ "${RULES_FILE}" != /* ]] && RULES_FILE="${REPO_DIR}/${RULES_FILE}"
    fi
fi

if [ -z "${RULES_FILE}" ] || [ ! -f "${RULES_FILE}" ]; then
    RULES_FILE="$(get_harness_root)/core/templates/landmines-template.json"
fi

if [ ! -f "${RULES_FILE}" ]; then
    log_warn "No landmines.json found. Skipping static scan."
    exit 0
fi

log_info "Running Landmine Scanner [${SCAN_MODE}] using rules: ${RULES_FILE}..."

ERRORS_FOUND=0
WARNINGS_FOUND=0

FILES_TO_SCAN=()
cd "${REPO_DIR}"

if [ "${SCAN_MODE}" = "staged" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && FILES_TO_SCAN+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
elif [ "${SCAN_MODE}" = "diff" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && FILES_TO_SCAN+=("$f")
    done < <(git diff --name-only --diff-filter=ACMR 2>/dev/null || true)
else
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && FILES_TO_SCAN+=("$f")
    done < <(git ls-files 2>/dev/null || true)
fi

if [ ${#FILES_TO_SCAN[@]} -eq 0 ]; then
    log_success "No files to scan."
    exit 0
fi

if command -v jq >/dev/null 2>&1; then
    RULE_COUNT=$(jq '. | length' "${RULES_FILE}" 2>/dev/null || echo 0)
    for (( i=0; i<RULE_COUNT; i++ )); do
        ID=$(jq -r ".[$i].id" "${RULES_FILE}")
        NAME=$(jq -r ".[$i].name" "${RULES_FILE}")
        PATTERN=$(jq -r ".[$i].pattern" "${RULES_FILE}")
        LEVEL=$(jq -r ".[$i].level // \"error\"" "${RULES_FILE}")
        MSG=$(jq -r ".[$i].message" "${RULES_FILE}")
        EXTS=$(jq -r ".[$i].fileExtensions[]? // empty" "${RULES_FILE}")

        for file in "${FILES_TO_SCAN[@]}"; do
            MATCH_EXT=true
            if [ -n "${EXTS}" ]; then
                MATCH_EXT=false
                for ext in ${EXTS}; do
                    if [[ "${file}" == *"${ext}" ]]; then
                        MATCH_EXT=true
                        break
                    fi
                done
            fi

            if [ "${MATCH_EXT}" = true ]; then
                if grep -En "${PATTERN}" "${file}" >/dev/null 2>&1; then
                    MATCHES=$(grep -En "${PATTERN}" "${file}" || true)
                    if [ "${LEVEL}" = "error" ]; then
                        log_error "[${ID}] ${NAME} in ${file}:"
                        echo "${MATCHES}" | sed 's/^/  /'
                        echo "  ${YELLOW}Fix:${RESET} ${MSG}"
                        ERRORS_FOUND=$((ERRORS_FOUND + 1))
                    else
                        log_warn "[${ID}] ${NAME} in ${file}:"
                        echo "${MATCHES}" | sed 's/^/  /'
                        echo "  ${YELLOW}Fix:${RESET} ${MSG}"
                        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
                    fi
                fi
            fi
        done
    done
fi

echo ""
if [ ${ERRORS_FOUND} -eq 0 ]; then
    log_success "Landmine scan passed with 0 errors (${WARNINGS_FOUND} warnings)."
    exit 0
else
    log_error "Landmine scan failed with ${ERRORS_FOUND} error(s). Commit blocked."
    exit 1
fi
