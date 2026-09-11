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
# and it previously resolved that ambiguity by overwriting and reporting success. It lives
# in lib/git.sh because `harness doctor` reports on the same hook.
HOOK_MARKER="${HARNESS_PRE_COMMIT_MARKER}"

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
    HOOKS_DIR="$(resolve_hooks_dir "${REPO_DIR}")"
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

# A scan is a claim about the files it read. Without a usable jq the rule loop was
# skipped entirely and the scanner still printed "passed with 0 errors", which is the
# same fail-open shape AH-9 closed elsewhere and left recorded here as an open question.
if ! jq --version >/dev/null 2>&1; then
    log_error "The landmine scanner requires jq; no rule could be read."
    log_error "A scan that could not run is not a passing scan."
    exit 1
fi

RULES_FILE="${CUSTOM_RULES}"
if [ -z "${RULES_FILE}" ]; then
    RULES_FILE="$(get_profile_value "rules.scanner" "")"
    if [ -n "${RULES_FILE}" ]; then
        RULES_FILE="$(expand_config_path "${RULES_FILE}")"
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

# A rule says what it matches: file content through "pattern", or the repository-relative
# path through "pathPattern". Exactly one, because a rule that names both or neither has no
# single answer to "did this match", and a rule that cannot answer that is not a rule.
#
# grep -E exits 2 on a pattern it cannot compile, and the scan loop discards stderr, so an
# unusable rule is indistinguishable from a clean file. Two checks close that gap, and both
# are needed because they catch different things on different platforms.
#
# The '(?' check is first and is the portable one. '(?' opens a PCRE group construct --
# lookahead, lookbehind, non-capturing group -- and ERE defines none of them. BSD grep
# rejects such a pattern outright, but GNU grep compiles it, treating the '?' as a literal
# inside an ordinary group, and then quietly matches something nobody wrote. Relying on the
# compile check alone would therefore catch the shipped PERF-001 lookahead on macOS and miss
# it on Linux, which is the platform most of this runs on. A rule must be refused for the
# same reason on both.
#
# The compile check stays for everything else -- an unbalanced group, a bad character class,
# a malformed interval -- which every grep rejects.
validate_rule_expression() {
    local rule_id="$1"
    local kind="$2"
    local expression="$3"
    local compile_status=0

    case "${expression}" in
        *'(?'*)
            log_error "[${rule_id}] Unusable ${kind} in ${RULES_FILE}: '(?' is a PCRE construct and grep -E has no lookaround."
            return 1
            ;;
    esac

    printf '' | grep -Eq -- "${expression}" >/dev/null 2>&1 || compile_status=$?
    if [ "${compile_status}" -ge 2 ]; then
        log_error "[${rule_id}] Unusable ${kind} in ${RULES_FILE}: grep -E cannot compile it."
        return 1
    fi
}

validate_rule_patterns() {
    local invalid=0 count index rule_id has_pattern has_path_pattern rule_pattern rule_path_pattern
    count=$(jq '. | length' "${RULES_FILE}" 2>/dev/null || echo 0)

    # Read field by field rather than through a joined line. jq's @tsv escapes backslashes,
    # which turns every '\(' in a rule into a literal backslash followed by an unbalanced
    # group -- a pattern that compiles today would have been rejected by its own validator.
    for (( index=0; index<count; index++ )); do
        rule_id=$(jq -r ".[${index}].id // \"\"" "${RULES_FILE}")
        has_pattern=$(jq -r "if .[${index}] | has(\"pattern\") then \"1\" else \"0\" end" "${RULES_FILE}")
        has_path_pattern=$(jq -r "if .[${index}] | has(\"pathPattern\") then \"1\" else \"0\" end" "${RULES_FILE}")
        rule_pattern=$(jq -r ".[${index}].pattern // \"\"" "${RULES_FILE}")
        rule_path_pattern=$(jq -r ".[${index}].pathPattern // \"\"" "${RULES_FILE}")

        if [ -z "${rule_id}" ]; then
            log_error "Rule ${index} in ${RULES_FILE} has no id."
            invalid=$((invalid + 1))
            continue
        fi

        if [ "${has_pattern}${has_path_pattern}" = "00" ]; then
            log_error "[${rule_id}] Rule in ${RULES_FILE} names neither 'pattern' nor 'pathPattern', so it can never match."
            invalid=$((invalid + 1))
            continue
        fi
        if [ "${has_pattern}${has_path_pattern}" = "11" ]; then
            log_error "[${rule_id}] Rule in ${RULES_FILE} names both 'pattern' and 'pathPattern'; a rule matches content or paths, not both."
            invalid=$((invalid + 1))
            continue
        fi

        if [ "${has_pattern}" = "1" ]; then
            validate_rule_expression "${rule_id}" "pattern" "${rule_pattern}" || invalid=$((invalid + 1))
        else
            validate_rule_expression "${rule_id}" "pathPattern" "${rule_path_pattern}" || invalid=$((invalid + 1))
        fi
    done

    if [ "${invalid}" -ne 0 ]; then
        log_error "Landmine scan aborted: ${invalid} rule(s) cannot be used. A rule that cannot run is not a passing scan."
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

# A glob list scopes a rule without switching it off. Matching uses bash's [[ == ]], so a
# '*' spans '/' too: "vendor/*" covers everything beneath vendor/, and "*.generated.js"
# covers any directory.
path_is_excluded() {
    local file="$1"
    shift
    local glob
    for glob in "$@"; do
        [ -n "${glob}" ] || continue
        # shellcheck disable=SC2053 # the glob is data and must not be quoted
        if [[ "${file}" == ${glob} ]]; then
            return 0
        fi
    done
    return 1
}

# Without an escape hatch a single false positive leaves --no-verify as the only option,
# which retires the whole gate rather than one line. The rule ID is required: a suppression
# that silenced every rule on a line would hide the findings nobody was arguing about.
line_is_suppressed() {
    local source_path="$1"
    local line_number="$2"
    local rule_id="$3"
    local token="harness-ignore: ${rule_id}"
    local text

    text="$(sed -n "${line_number}p" "${source_path}")"
    case "${text}" in
        *"${token}"*) return 0 ;;
    esac

    if [ "${line_number}" -gt 1 ]; then
        text="$(sed -n "$((line_number - 1))p" "${source_path}")"
        case "${text}" in
            *"${token}"*) return 0 ;;
        esac
    fi

    return 1
}

report_finding() {
    local level="$1"
    local rule_id="$2"
    local rule_name="$3"
    local file="$4"
    local detail="$5"
    local message="$6"

    if [ "${level}" = "error" ]; then
        log_error "[${rule_id}] ${rule_name} in ${file}:"
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
    else
        log_warn "[${rule_id}] ${rule_name} in ${file}:"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    fi
    printf '%s\n' "${detail}" | sed 's/^/  /'
    echo "  ${YELLOW}Fix:${RESET} ${message}"
}

RULE_COUNT=$(jq '. | length' "${RULES_FILE}" 2>/dev/null || echo 0)
for (( i=0; i<RULE_COUNT; i++ )); do
    ID=$(jq -r ".[$i].id" "${RULES_FILE}")
    NAME=$(jq -r ".[$i].name" "${RULES_FILE}")
    PATTERN=$(jq -r ".[$i].pattern // \"\"" "${RULES_FILE}")
    PATH_PATTERN=$(jq -r ".[$i].pathPattern // \"\"" "${RULES_FILE}")
    LEVEL=$(jq -r ".[$i].level // \"error\"" "${RULES_FILE}")
    MSG=$(jq -r ".[$i].message" "${RULES_FILE}")
    EXTS=$(jq -r ".[$i].fileExtensions[]? // empty" "${RULES_FILE}")

    EXCLUDES=()
    while IFS= read -r exclude_glob; do
        [ -n "${exclude_glob}" ] && EXCLUDES+=("${exclude_glob}")
    done < <(jq -r ".[$i].excludePaths[]? // empty" "${RULES_FILE}")

    for (( f=0; f<${#FILES_TO_SCAN[@]}; f++ )); do
        file="${FILES_TO_SCAN[f]}"
        source_path="${SCAN_SOURCES[f]}"

        if [ ${#EXCLUDES[@]} -gt 0 ] && path_is_excluded "${file}" "${EXCLUDES[@]}"; then
            continue
        fi

        if [ -n "${PATH_PATTERN}" ]; then
            if printf '%s' "${file}" | grep -Eq -- "${PATH_PATTERN}"; then
                report_finding "${LEVEL}" "${ID}" "${NAME}" "${file}" "${file}" "${MSG}"
            fi
            continue
        fi

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
        [ "${MATCH_EXT}" = true ] || continue

        RAW_MATCHES=$(grep -En -- "${PATTERN}" "${source_path}" 2>/dev/null || true)
        [ -n "${RAW_MATCHES}" ] || continue

        KEPT_MATCHES=""
        while IFS= read -r raw_match; do
            [ -n "${raw_match}" ] || continue
            match_line="${raw_match%%:*}"
            if line_is_suppressed "${source_path}" "${match_line}" "${ID}"; then
                continue
            fi
            KEPT_MATCHES="${KEPT_MATCHES}${raw_match}"$'\n'
        done <<< "${RAW_MATCHES}"

        [ -n "${KEPT_MATCHES%$'\n'}" ] || continue
        report_finding "${LEVEL}" "${ID}" "${NAME}" "${file}" "${KEPT_MATCHES%$'\n'}" "${MSG}"
    done
done

echo ""
if [ ${ERRORS_FOUND} -eq 0 ]; then
    log_success "Landmine scan passed with 0 errors (${WARNINGS_FOUND} warnings)."
    exit 0
else
    log_error "Landmine scan failed with ${ERRORS_FOUND} error(s). Commit blocked."
    exit 1
fi
