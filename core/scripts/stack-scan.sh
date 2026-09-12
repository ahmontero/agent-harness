#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-scan.sh
# JSON-Driven Static Landmine & Security Scanner
# ==============================================================================
#
# Exit status:
#   0  the scan ran and found no error-level finding
#   1  the scan ran and found at least one
#   2  the scan could not run: no rules could be read, or no range could be resolved
#
# 2 is the same status stack-qa.sh reports as GATE_UNRUNNABLE, so a scanner that could not
# determine what to read is aggregated as "could not run" rather than as a gate that
# passed. Every refusal below exits 2 for that reason.

set -eo pipefail

SCAN_UNRUNNABLE=2

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
  --branch        Scan everything this branch changes since its merge base with the trunk
  --base <ref>    With --branch, name the base revision instead of detecting the trunk
  --all           Scan all tracked source files
  --json          Emit one JSON document on stdout; every human line goes to stderr
  --rules <file>  Path to custom landmines.json rules file
  --install-hook  Install scanner as git pre-commit hook in target repo
  --force         With --install-hook, replace a foreign hook after backing it up
  -h, --help      Show this help message
USAGE_EOF
}

SCAN_MODE="staged"
JSON_OUTPUT=false
CUSTOM_RULES=""
INSTALL_HOOK=false
FORCE_HOOK=false
RANGE_BASE=""
BASE_GIVEN=false

# An option this scanner does not define used to be discarded, so `harness scan --al`
# scanned the staged set -- empty on a clean tree -- and exited 0. A mistyped flag must
# never quietly become a different, passing question.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_OUTPUT=true; shift ;;
        --staged) SCAN_MODE="staged"; shift ;;
        --diff) SCAN_MODE="diff"; shift ;;
        --branch) SCAN_MODE="branch"; shift ;;
        --all) SCAN_MODE="all"; shift ;;
        --base)
            [ -n "${2:-}" ] || { log_error "--base requires a git revision."; exit 1; }
            RANGE_BASE="$2"
            BASE_GIVEN=true
            shift 2
            ;;
        --rules)
            [ -n "${2:-}" ] || { log_error "--rules requires a path."; exit 1; }
            CUSTOM_RULES="$2"
            shift 2
            ;;
        --install-hook) INSTALL_HOOK=true; shift ;;
        --force) FORCE_HOOK=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown scan option: $1"; usage; exit 1 ;;
    esac
done

# A modifier that modifies nothing was accepted and ignored, which reads as if it applied.
if [ "${BASE_GIVEN}" = true ] && [ "${SCAN_MODE}" != "branch" ]; then
    log_error "--base names the base of a branch range and only applies with --branch."
    exit 1
fi
if [ "${FORCE_HOOK}" = true ] && [ "${INSTALL_HOOK}" != true ]; then
    log_error "--force replaces a foreign pre-commit hook and only applies with --install-hook."
    exit 1
fi

# In JSON mode stdout belongs to the document and nothing else. Moving the stream aside once
# is what makes that true without guarding 44 emitting call sites or redefining the logging
# functions: log_info and log_success write to stdout, and a JSON mode correct in 43 places
# and prose in the 44th is worse than none. fd 3 is the real stdout, written only at the end.
if [ "${JSON_OUTPUT}" = true ]; then
    exec 3>&1 1>&2
fi

# Every exit below the swap goes through here, so the document is emitted exactly once and
# the exit status is the one the human form would have returned. --json changes the shape of
# the answer, never the verdict.
JSON_FINDINGS=()
scan_exit() {
    local status="$1" code="$2"
    if [ "${JSON_OUTPUT}" = true ]; then
        local findings="[]"
        [ ${#JSON_FINDINGS[@]} -eq 0 ] || findings="$(printf '%s\n' "${JSON_FINDINGS[@]}" | jq -s '.')"
        jq -n \
            --arg mode "${SCAN_MODE}" \
            --arg status "${status}" \
            --arg rules "${RULES_SOURCE_PATH:-}" \
            --argjson baseline "$([ "${BASELINE_ENABLED:-true}" = "false" ] && echo false || echo true)" \
            --argjson errors "${ERRORS_FOUND:-0}" \
            --argjson warnings "${WARNINGS_FOUND:-0}" \
            --argjson findings "${findings}" \
            '{mode: $mode, status: $status, rules: {source: $rules, securityBaseline: $baseline},
              errors: $errors, warnings: $warnings, findings: $findings}' >&3
    fi
    exit "${code}"
}

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
    scan_exit "unrunnable" 1
fi

# Rules that were asked for and cannot be read abort the scan. They used to be replaced by
# the built-in template, so a project whose rules/landmines.json had been renamed was
# scanned by rules nobody there wrote and told it passed -- and a missing template made the
# scan exit 0 outright. The template is the default for a project that requested nothing,
# never a stand-in for a request that could not be honoured.
#
# A --rules path stays relative to the caller's working directory, the way a path typed on
# a command line is; a configured one is relative to the repository it configures.
RULES_FILE=""
RULES_SOURCE=""
if [ -n "${CUSTOM_RULES}" ]; then
    RULES_FILE="$(expand_config_path "${CUSTOM_RULES}")"
    RULES_SOURCE="--rules"
else
    CONFIGURED_RULES="$(get_profile_value "rules.scanner" "")"
    if [ -n "${CONFIGURED_RULES}" ]; then
        RULES_FILE="$(expand_config_path "${CONFIGURED_RULES}")"
        [[ "${RULES_FILE}" != /* ]] && RULES_FILE="${REPO_DIR}/${RULES_FILE}"
        RULES_SOURCE="profiles.${ACTIVE_PROFILE}.rules.scanner"
    fi
fi

if [ -n "${RULES_FILE}" ] && [ ! -f "${RULES_FILE}" ]; then
    log_error "The rule file named by ${RULES_SOURCE} does not exist: ${RULES_FILE}"
    log_error "A scan whose rules could not be read is not a passing scan."
    log_info "Restore the file, correct ${RULES_SOURCE}, or pass --rules <file> explicitly."
    scan_exit "unrunnable" "${SCAN_UNRUNNABLE}"
fi

if [ -z "${RULES_FILE}" ]; then
    RULES_FILE="$(get_harness_root)/core/templates/landmines-template.json"
    RULES_SOURCE="the built-in template"
    if [ ! -f "${RULES_FILE}" ]; then
        log_error "No rule file is configured and the built-in template is missing: ${RULES_FILE}"
        log_error "A scan whose rules could not be read is not a passing scan."
        scan_exit "unrunnable" "${SCAN_UNRUNNABLE}"
    fi
fi

# One trap for every temporary path this scan creates. There used to be a single
# `trap ... EXIT` for the staged-content directory; a second trap would have silently
# replaced it and leaked the first, because a shell keeps one handler per signal.
SCAN_TEMP_PATHS=()
scan_cleanup() {
    [ ${#SCAN_TEMP_PATHS[@]} -eq 0 ] || rm -rf "${SCAN_TEMP_PATHS[@]}"
}
trap scan_cleanup EXIT

# The security baseline is applied on top of whatever rule file was resolved, because the
# scanner resolves exactly one rule file and `harness init` copies the template into the
# project. Improving the template therefore reached new repositories only: every project
# that had already run init kept its copy of the rules for good, and choosing a recipe
# substituted a different and equally partial set. A baseline the scanner always applies is
# the only shape that reaches an installed project, and it keeps one copy of the security
# rules rather than one per template and recipe.
#
# A project rule whose id matches a baseline rule replaces it. That is the per-rule escape
# hatch: redefining SEC-010 with your own pattern or a level of "warning" is how a project
# disagrees with one baseline rule without giving up the rest.
BASELINE_FILE="$(get_harness_root)/core/templates/security-baseline.json"
BASELINE_ENABLED="$(get_profile_value "rules.securityBaseline" "true")"
BASELINE_NOTE=""
# The path a reader can open. RULES_FILE becomes a temporary merged file below, and naming
# that in the report would tell them nothing they can act on.
RULES_SOURCE_PATH="${RULES_FILE}"

if [ "${BASELINE_ENABLED}" = "false" ]; then
    BASELINE_NOTE=" (security baseline disabled by profiles.${ACTIVE_PROFILE}.rules.securityBaseline)"
else
    # A baseline that could not be read is not a baseline that found nothing, for the same
    # reason a rule file that could not be read is not a passing scan.
    if [ ! -f "${BASELINE_FILE}" ] || ! jq empty "${BASELINE_FILE}" >/dev/null 2>&1; then
        log_error "The security baseline is missing or unreadable: ${BASELINE_FILE}"
        log_error "A scan whose baseline could not be read is not a passing scan."
        log_info "Disable it deliberately with profiles.${ACTIVE_PROFILE}.rules.securityBaseline: false."
        scan_exit "unrunnable" "${SCAN_UNRUNNABLE}"
    fi

    EFFECTIVE_RULES="$(mktemp "${TMPDIR:-/tmp}/harness-rules.XXXXXX")"
    SCAN_TEMP_PATHS+=("${EFFECTIVE_RULES}")
    if ! jq -s '
            .[0] as $baseline
            | .[1] as $project
            | ($project | map(.id)) as $overridden
            | ($baseline | map(select(.id as $id | ($overridden | index($id)) == null))) + $project
        ' "${BASELINE_FILE}" "${RULES_FILE}" > "${EFFECTIVE_RULES}"; then
        log_error "The security baseline could not be combined with ${RULES_FILE}."
        scan_exit "unrunnable" "${SCAN_UNRUNNABLE}"
    fi
    # Both counts are read off the merged file, so they cannot disagree with the merge. The
    # baseline's contribution is the difference: a project that overrides SEC-010 sees "3 of
    # the security baseline's rules", which is the override reporting itself.
    PROJECT_RULE_COUNT="$(jq -r 'length' "${RULES_SOURCE_PATH}")"
    TOTAL_RULE_COUNT="$(jq -r 'length' "${EFFECTIVE_RULES}")"
    BASELINE_NOTE=" + $(( TOTAL_RULE_COUNT - PROJECT_RULE_COUNT )) of the security baseline's rules (${TOTAL_RULE_COUNT} rules in force)"
    RULES_FILE="${EFFECTIVE_RULES}"
fi

RULES_DISPLAY="${RULES_SOURCE_PATH}${BASELINE_NOTE}"

log_info "Running Landmine Scanner [${SCAN_MODE}] using rules: ${RULES_DISPLAY}..."

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
            log_error "[${rule_id}] Unusable ${kind} in ${RULES_DISPLAY}: '(?' is a PCRE construct and grep -E has no lookaround."
            return 1
            ;;
    esac

    printf '' | grep -Eq -- "${expression}" >/dev/null 2>&1 || compile_status=$?
    if [ "${compile_status}" -ge 2 ]; then
        log_error "[${rule_id}] Unusable ${kind} in ${RULES_DISPLAY}: grep -E cannot compile it."
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
            log_error "Rule ${index} in ${RULES_DISPLAY} has no id."
            invalid=$((invalid + 1))
            continue
        fi

        if [ "${has_pattern}${has_path_pattern}" = "00" ]; then
            log_error "[${rule_id}] Rule in ${RULES_DISPLAY} names neither 'pattern' nor 'pathPattern', so it can never match."
            invalid=$((invalid + 1))
            continue
        fi
        if [ "${has_pattern}${has_path_pattern}" = "11" ]; then
            log_error "[${rule_id}] Rule in ${RULES_DISPLAY} names both 'pattern' and 'pathPattern'; a rule matches content or paths, not both."
            invalid=$((invalid + 1))
            continue
        fi

        if [ "$(jq -r "if .[${index}] | has(\"ignoreCase\") then (.[${index}].ignoreCase | type) else \"boolean\" end" "${RULES_FILE}")" != "boolean" ]; then
            log_error "[${rule_id}] ignoreCase in ${RULES_DISPLAY} must be true or false."
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

# A rule that cannot be used is the same class as a rule file that cannot be read, so it
# leaves through the same status and `qa all` aggregates both as "could not run".
validate_rule_patterns || scan_exit "unrunnable" "${SCAN_UNRUNNABLE}"

ERRORS_FOUND=0
WARNINGS_FOUND=0

FILES_TO_SCAN=()
cd "${REPO_DIR}"

# The commit this branch grew from. --diff answers "what have I not committed yet", which
# is empty on a finished branch and was therefore the wrong question for a pre-flight gate:
# a secret committed three commits ago was reported as nothing to scan. --branch answers
# "what does this branch change", from the merge base to the working tree, so committed and
# uncommitted work are both read.
#
# A base that cannot be resolved exits 2 rather than scanning an empty set: on a shallow CI
# clone the trunk ref is often absent, and that is precisely when a silent zero would be
# read as a clean branch.
resolve_branch_base() {
    local base_ref base_commit
    if [ -n "${RANGE_BASE}" ]; then
        base_ref="${RANGE_BASE}"
    else
        base_ref="$(get_trunk_branch "${REPO_DIR}")"
    fi

    if ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null 2>&1; then
        log_error "Cannot scan this branch: '${base_ref}' is not a revision in this repository."
        log_info "Name the base with --base <ref>, set profiles.${ACTIVE_PROFILE}.git.trunkBranch, or scan the whole tree with --all."
        return "${SCAN_UNRUNNABLE}"
    fi

    base_commit="$(git merge-base "${base_ref}" HEAD 2>/dev/null)" || base_commit=""
    if [ -z "${base_commit}" ]; then
        log_error "Cannot scan this branch: HEAD and '${base_ref}' share no common ancestor."
        log_info "Name the base with --base <ref>, or scan the whole tree with --all."
        return "${SCAN_UNRUNNABLE}"
    fi

    printf '%s\n' "${base_commit}"
}

if [ "${SCAN_MODE}" = "branch" ]; then
    BRANCH_BASE="$(resolve_branch_base)" || exit $?
    log_info "Scanning every change this branch makes since ${BRANCH_BASE}..."
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && FILES_TO_SCAN+=("$f")
    done < <(git diff --name-only --diff-filter=ACMR "${BRANCH_BASE}" 2>/dev/null || true)
elif [ "${SCAN_MODE}" = "staged" ]; then
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
    # Named so the zero can be judged. "No files to scan" alone reads the same whether the
    # selection is genuinely empty or the mode was the wrong question to ask.
    log_success "No files to scan: the ${SCAN_MODE} selection is empty."
    scan_exit "passed" 0
fi

# --staged answers a question about the next commit, so it must read the index, not the
# working tree. Content is materialized once here and reused by every rule; doing it inside
# the rule loop would multiply git show invocations by the rule count for no benefit.
# SCAN_SOURCES is index-parallel to FILES_TO_SCAN: findings still cite the repository path,
# while grep reads the bytes that are about to be committed.
SCAN_SOURCES=()
if [ "${SCAN_MODE}" = "staged" ]; then
    STAGED_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-scan.XXXXXX")"
    SCAN_TEMP_PATHS+=("${STAGED_ROOT}")
    staged_index=0
    for file in "${FILES_TO_SCAN[@]}"; do
        staged_blob="${STAGED_ROOT}/$(printf '%06d' "${staged_index}")"
        if ! git show ":${file}" > "${staged_blob}" 2>/dev/null; then
            log_error "Cannot read staged content for ${file}."
            scan_exit "unrunnable" 1
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
    local kind="${7:-content}"

    if [ "${JSON_OUTPUT}" = true ]; then
        if [ "${kind}" = "path" ]; then
            JSON_FINDINGS+=("$(jq -nc --arg rule "${rule_id}" --arg name "${rule_name}" --arg level "${level}" \
                --arg file "${file}" --arg message "${message}" \
                '{rule: $rule, name: $name, level: $level, file: $file, line: null, text: $file, message: $message}')")
        else
            local json_row
            while IFS= read -r json_row; do
                [ -n "${json_row}" ] || continue
                JSON_FINDINGS+=("$(jq -nc --arg rule "${rule_id}" --arg name "${rule_name}" --arg level "${level}" \
                    --arg file "${file}" --argjson line "${json_row%%:*}" --arg text "${json_row#*:}" \
                    --arg message "${message}" \
                    '{rule: $rule, name: $name, level: $level, file: $file, line: $line, text: $text, message: $message}')")
            done <<< "${detail}"
        fi
    fi

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
    IGNORE_CASE=$(jq -r ".[$i].ignoreCase // false" "${RULES_FILE}")
    MSG=$(jq -r ".[$i].message" "${RULES_FILE}")
    EXTS=$(jq -r ".[$i].fileExtensions[]? // empty" "${RULES_FILE}")

    EXCLUDES=()
    while IFS= read -r exclude_glob; do
        [ -n "${exclude_glob}" ] && EXCLUDES+=("${exclude_glob}")
    done < <(jq -r ".[$i].excludePaths[]? // empty" "${RULES_FILE}")

    GREP_FLAGS=(-E -I)
    [ "${IGNORE_CASE}" = "true" ] && GREP_FLAGS+=(-i)

    # The files this rule is scoped to, and the source each one is read from. Scoping is
    # decided once here so the grep below is a single invocation rather than one per file:
    # the scan used to spawn one grep per (rule, file) pair, which on a 500-file repository
    # was 4000 processes and about 94% of its wall clock.
    RULE_FILES=()
    RULE_SOURCES=()
    for (( f=0; f<${#FILES_TO_SCAN[@]}; f++ )); do
        file="${FILES_TO_SCAN[f]}"

        if [ ${#EXCLUDES[@]} -gt 0 ] && path_is_excluded "${file}" "${EXCLUDES[@]}"; then
            continue
        fi

        if [ -z "${PATH_PATTERN}" ] && [ -n "${EXTS}" ]; then
            MATCH_EXT=false
            for ext in ${EXTS}; do
                if [[ "${file}" == *"${ext}" ]]; then
                    MATCH_EXT=true
                    break
                fi
            done
            [ "${MATCH_EXT}" = true ] || continue
        fi

        RULE_FILES+=("${file}")
        RULE_SOURCES+=("${SCAN_SOURCES[f]}")
    done
    [ ${#RULE_FILES[@]} -gt 0 ] || continue

    # A path rule matches names, so the names go through one grep instead of one each. grep
    # preserves the order it was given, which is the order the findings are reported in.
    if [ -n "${PATH_PATTERN}" ]; then
        while IFS= read -r matched_name; do
            [ -n "${matched_name}" ] || continue
            report_finding "${LEVEL}" "${ID}" "${NAME}" "${matched_name}" "${matched_name}" "${MSG}" path
        done < <(printf '%s\n' "${RULE_FILES[@]}" | grep "${GREP_FLAGS[@]}" -- "${PATH_PATTERN}" 2>/dev/null || true)
        continue
    fi

    # -H forces the filename prefix grep omits when it is given a single file, and xargs -0
    # chunks the list: 5000 paths exceed ARG_MAX on macOS, and a scan that silently dropped
    # the files past the limit would be worse than a slow one.
    RULE_MATCHES="$(printf '%s\0' "${RULE_SOURCES[@]}" \
        | xargs -0 grep "${GREP_FLAGS[@]}" -H -n -- "${PATTERN}" 2>/dev/null || true)"
    [ -n "${RULE_MATCHES}" ] || continue

    MATCH_LINES=()
    while IFS= read -r match_row; do
        [ -n "${match_row}" ] && MATCH_LINES+=("${match_row}")
    done <<< "${RULE_MATCHES}"

    # grep emits the files in the order it was handed them, so its output is walked
    # alongside the rule's own list in one pass. The source is matched as a literal prefix
    # rather than by splitting on the first colon, which is what keeps a path containing a
    # colon parsing correctly -- and in --staged mode the source is an index blob, so the
    # repository path is what gets reported either way.
    MATCH_INDEX=0
    MATCH_TOTAL=${#MATCH_LINES[@]}
    for (( r=0; r<${#RULE_SOURCES[@]} && MATCH_INDEX<MATCH_TOTAL; r++ )); do
        source_path="${RULE_SOURCES[r]}"
        KEPT_MATCHES=""
        while [ "${MATCH_INDEX}" -lt "${MATCH_TOTAL}" ]; do
            match_row="${MATCH_LINES[MATCH_INDEX]}"
            case "${match_row}" in
                "${source_path}:"*) ;;
                *) break ;;
            esac
            raw_match="${match_row#"${source_path}:"}"
            match_line="${raw_match%%:*}"
            if ! line_is_suppressed "${source_path}" "${match_line}" "${ID}"; then
                KEPT_MATCHES="${KEPT_MATCHES}${raw_match}"$'\n'
            fi
            MATCH_INDEX=$((MATCH_INDEX + 1))
        done
        [ -n "${KEPT_MATCHES%$'\n'}" ] || continue
        report_finding "${LEVEL}" "${ID}" "${NAME}" "${RULE_FILES[r]}" "${KEPT_MATCHES%$'\n'}" "${MSG}"
    done
done

echo ""
if [ ${ERRORS_FOUND} -eq 0 ]; then
    log_success "Landmine scan passed with 0 errors (${WARNINGS_FOUND} warnings)."
    scan_exit "passed" 0
else
    log_error "Landmine scan failed with ${ERRORS_FOUND} error(s). Commit blocked."
    scan_exit "failed" 1
fi
