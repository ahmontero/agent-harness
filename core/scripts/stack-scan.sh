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
  --force         With --install-hook, replace a foreign hook after backing it up
  -h, --help      Show this help message
USAGE_EOF
}

SCAN_MODE="staged"
CUSTOM_RULES=""
INSTALL_HOOK=false
FORCE_HOOK=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --staged) SCAN_MODE="staged"; shift ;;
        --diff) SCAN_MODE="diff"; shift ;;
        --all) SCAN_MODE="all"; shift ;;
        --rules) CUSTOM_RULES="$2"; shift 2 ;;
        --install-hook) INSTALL_HOOK=true; shift ;;
        --force) FORCE_HOOK=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) shift ;;
    esac
done

# The marker is what makes "our hook" a decidable question. Without it the installer
# cannot tell an idempotent re-run from silently destroying a hook the project depends on,
# and it previously resolved that ambiguity by overwriting and reporting success.
HOOK_MARKER="# agent-harness-pre-commit-hook-v1"

write_pre_commit_hook() {
    local hook_path="$1"
    local hooks_dir temporary
    hooks_dir="$(dirname -- "${hook_path}")"
    temporary="$(mktemp "${hooks_dir}/pre-commit.harness.XXXXXX")"
    cat > "${temporary}" <<HOOK_EOF
#!/usr/bin/env bash
${HOOK_MARKER}
exec harness scan --staged
HOOK_EOF
    chmod 755 "${temporary}"
    mv "${temporary}" "${hook_path}"
}

if [ "${INSTALL_HOOK}" = true ]; then
    # rev-parse resolves the hooks directory for linked worktrees too, where .git is a
    # file and ${REPO_DIR}/.git/hooks would be a directory git never reads.
    HOOKS_DIR="$(git -C "${REPO_DIR}" rev-parse --git-path hooks)"
    [[ "${HOOKS_DIR}" = /* ]] || HOOKS_DIR="${REPO_DIR}/${HOOKS_DIR}"
    HOOK_PATH="${HOOKS_DIR}/pre-commit"
    HOOK_BACKUP="${HOOK_PATH}.harness-backup"
    mkdir -p "${HOOKS_DIR}"

    if [ -e "${HOOK_PATH}" ] && ! grep -qxF "${HOOK_MARKER}" "${HOOK_PATH}" 2>/dev/null; then
        if [ "${FORCE_HOOK}" != true ]; then
            log_error "A pre-commit hook that agent-harness did not write already exists: ${HOOK_PATH}"
            log_info "Add this line to it instead, or re-run with --force to back it up and replace it:"
            printf '  harness scan --staged || exit 1\n'
            exit 1
        fi
        if [ -e "${HOOK_BACKUP}" ]; then
            log_error "Refusing to overwrite an existing backup: ${HOOK_BACKUP}"
            exit 1
        fi
        cp -p "${HOOK_PATH}" "${HOOK_BACKUP}"
        log_warn "Backed up the previous pre-commit hook to ${HOOK_BACKUP}."
    fi

    write_pre_commit_hook "${HOOK_PATH}"
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

# grep -E exits 2 on a pattern it cannot compile, and the scan loop discards stderr, so an
# unusable rule is indistinguishable from a clean file. Compiling every pattern once against
# empty input turns that silence into a refusal, before any file is read.
validate_rule_patterns() {
    local invalid=0 rule_id rule_pattern compile_status
    command -v jq >/dev/null 2>&1 || return 0
    while IFS=$'\t' read -r rule_id rule_pattern; do
        [ -n "${rule_id}" ] || continue
        compile_status=0
        printf '' | grep -Eq -- "${rule_pattern}" >/dev/null 2>&1 || compile_status=$?
        if [ "${compile_status}" -ge 2 ]; then
            log_error "[${rule_id}] Unusable pattern in ${RULES_FILE}: grep -E cannot compile it."
            invalid=$((invalid + 1))
        fi
    done < <(jq -r '.[] | "\(.id)\t\(.pattern)"' "${RULES_FILE}")
    if [ "${invalid}" -ne 0 ]; then
        log_error "Landmine scan aborted: ${invalid} rule(s) cannot be compiled. A rule that cannot run is not a passing scan."
        return 1
    fi
}

validate_rule_patterns

ERRORS_FOUND=0
WARNINGS_FOUND=0

FILES_TO_SCAN=()
cd "${REPO_DIR}"

if [ "${SCAN_MODE}" = "staged" ]; then
    # No -f filter here: a path staged as an addition and then deleted from disk is still
    # part of the next commit, and the index is where its content lives.
    while IFS= read -r f; do
        [ -n "$f" ] && FILES_TO_SCAN+=("$f")
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

# --staged answers a question about the next commit, so it must read the index, not the
# working tree. Content is materialized once here and reused by every rule; doing it inside
# the rule loop would multiply git show invocations by the rule count for no benefit.
# SCAN_SOURCES is index-parallel to FILES_TO_SCAN: findings still cite the repository path,
# while grep reads the bytes that are about to be committed.
SCAN_SOURCES=()
if [ "${SCAN_MODE}" = "staged" ]; then
    STAGED_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-scan.XXXXXX")"
    trap 'rm -rf "${STAGED_ROOT}"' EXIT
    staged_index=0
    for file in "${FILES_TO_SCAN[@]}"; do
        staged_blob="${STAGED_ROOT}/$(printf '%06d' "${staged_index}")"
        if ! git show ":${file}" > "${staged_blob}" 2>/dev/null; then
            log_error "Cannot read staged content for ${file}."
            exit 1
        fi
        SCAN_SOURCES+=("${staged_blob}")
        staged_index=$((staged_index + 1))
    done
else
    SCAN_SOURCES=("${FILES_TO_SCAN[@]}")
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

        for (( f=0; f<${#FILES_TO_SCAN[@]}; f++ )); do
            file="${FILES_TO_SCAN[f]}"
            source_path="${SCAN_SOURCES[f]}"
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
                if grep -En "${PATTERN}" "${source_path}" >/dev/null 2>&1; then
                    MATCHES=$(grep -En "${PATTERN}" "${source_path}" || true)
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
