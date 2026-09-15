#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-doctor.sh
# Diagnostic, Environment Health & Self-Healing Engine
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/surface.sh"
source "${SCRIPT_DIR}/lib/qa.sh"

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
FIX_MODE=false
CHECK_AUTH=false

JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)
            FIX_MODE=true
            shift
            ;;
        --check-auth)
            CHECK_AUTH=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            echo "Usage: harness doctor [--fix] [--check-auth] [--json]"
            exit 0
            ;;
        *)
            # `harness doctor --fixx` used to run the diagnosis and repair nothing, while
            # reading as though --fix had been honoured.
            log_error "Unknown doctor option: $1"
            echo "Usage: harness doctor [--fix] [--check-auth] [--json]"
            exit 1
            ;;
    esac
done

# The banner, the section headers and every diagnostic line are prose written by dozens of
# call sites. Moving stdout aside once takes all of them with it, the same swap scan, qa all
# and config validate use, and leaves fd 3 for the one document.
if [ "${JSON_OUTPUT}" = true ]; then
    exec 3>&1 1>&2
fi
JSON_CHECKS=()

# Records a check's outcome for the machine form alongside the line a human reads. The
# states are the ones the counters already distinguish, so "could not be determined" stays
# separable from "passed" here too.
#
# Every branch of a check calls this, including the one where it passes. It used to be
# called only where a check had something to complain about, so `.checks[]` held the
# problems and nothing else -- and the documented filter for reading it,
# `select(.state != "ok")`, cannot tell a check that passed from a check that was never
# reported. A machine form that omits the passes is a machine form that cannot be used to
# establish that anything was actually checked.
#
# Section 2 is deliberately not recorded: which agent harnesses are installed on the machine
# is context for the reader, not a check -- it touches neither counter and has no pass or
# fail to report.
record_check() {
    [ "${JSON_OUTPUT}" = true ] || return 0
    JSON_CHECKS+=("$(jq -nc --arg section "$1" --arg name "$2" --arg state "$3" --arg detail "${4:-}" \
        '{section: $section, name: $name, state: $state, detail: (if $detail == "" then null else $detail end)}')")
}

print_banner
echo ""
log_info "Running Agent Harness Doctor for profile: ${BOLD}${ACTIVE_PROFILE}${RESET}..."
log_info "Target Repository: ${BOLD}${REPO_DIR}${RESET}"

ERRORS_FOUND=0
WARNINGS_FOUND=0

check_cmd() {
    local name="$1"
    local required="$2"
    if command -v "${name}" >/dev/null 2>&1; then
        local version
        version=$("${name}" --version 2>/dev/null | head -n 1 || echo "installed")
        log_success "Tool installed: ${name} (${version})"
        record_check "tooling" "${name}" "ok" "${version}"
    else
        if [ "${required}" = "true" ]; then
            log_error "Missing required CLI tool: ${name}"
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
            record_check "tooling" "${name}" "error" "required CLI tool is not installed"
        else
            log_warn "Optional CLI tool not found: ${name}"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            record_check "tooling" "${name}" "warning" "optional CLI tool is not installed"
        fi
    fi
}

echo ""
log_info "--- 1. System & CLI Tooling ---"
check_cmd "git" "true"
check_cmd "jq" "true"
check_cmd "gh" "false"
check_cmd "curl" "false"

echo ""
log_info "--- 2. Agent Harnesses Detection ---"
[ -d "${HOME}/.gemini" ] && log_success "Harness detected: Google Antigravity (~/.gemini)" || log_info "Harness not active: ~/.gemini"
[ -d "${HOME}/.claude" ] || command -v claude >/dev/null 2>&1 && log_success "Harness detected: Claude Code (~/.claude)" || log_info "Harness not active: ~/.claude"
[ -d "${HOME}/.codex" ] || command -v codex >/dev/null 2>&1 && log_success "Harness detected: OpenAI Codex (~/.codex)" || log_info "Harness not active: ~/.codex"
[ -d "${HOME}/.cursor" ] || [ -d "/Applications/Cursor.app" ] && log_success "Harness detected: Cursor (~/.cursor)" || log_info "Harness not active: ~/.cursor"
[ -d "${HOME}/.agents" ] && log_success "Harness detected: Standard .agents (~/.agents)" || log_info "Harness not active: ~/.agents"

echo ""
log_info "--- 3. Repository Symlinks & Health ---"
if [ -d "${REPO_DIR}" ]; then
    if [ -f "${REPO_DIR}/AGENTS.md" ]; then
        log_success "Canonical AGENTS.md exists in target repository."
        record_check "repository" "AGENTS.md" "ok" "${REPO_DIR}/AGENTS.md"
    else
        log_warn "Missing AGENTS.md in ${REPO_DIR}"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        record_check "repository" "AGENTS.md" "warning"
        if [ "${FIX_MODE}" = true ]; then
            template="$(get_harness_root)/core/templates/AGENTS-template.md"
            if [ -f "${template}" ]; then
                cp "${template}" "${REPO_DIR}/AGENTS.md"
                log_success "Self-healed: Created AGENTS.md from template."
            fi
        fi
    fi
fi

echo ""
log_info "--- 4. Installed Skill Surfaces ---"
# Drift is staleness, not breakage: a stale surface still works, so it is a warning and
# doctor still exits 0. What it must not do is stay quiet, or let a check that could not
# run read as a check that passed.
if ! jq --version >/dev/null 2>&1; then
    log_warn "Surface drift check unavailable: jq is not usable, so no surface state was determined."
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    record_check "surfaces" "drift check" "warning"
else
    SURFACES_DRIFTED=0

    report_surface_scope() {
        local scope_label="$1"
        local listing="$2"
        local directory runtime reason

        while IFS=$'\t' read -r directory runtime; do
            [ -n "${directory}" ] || continue
            surface_evaluate "${directory}"
            case "${SURFACE_STATE}" in
                current)
                    log_success "current   ${directory} (${runtime})"
                    record_check "surfaces" "${directory}" "ok" "current (${scope_label})"
                    ;;
                drifted)
                    SURFACES_DRIFTED=$((SURFACES_DRIFTED + 1))
                    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
                    log_warn "drifted   ${directory} (${runtime}) [${scope_label}]"
                    record_check "surfaces" "${directory}" "warning" "drifted (${scope_label})"
                    for reason in "${SURFACE_REASONS[@]}"; do
                        printf '            %s\n' "${reason}" >&2
                    done
                    ;;
            esac
        done <<< "${listing}"
    }

    report_surface_scope "repository" "$(surface_repo_list "${REPO_DIR}")"
    report_surface_scope "global" "$(surface_global_list)"

    if [ "${SURFACES_DRIFTED}" -eq 0 ]; then
        log_success "Every identified skill surface is current."
    elif [ "${FIX_MODE}" = true ]; then
        log_info "Self-healing ${SURFACES_DRIFTED} drifted surface(s)..."
        if "$(get_harness_root)/install.sh" --sync-target "${REPO_DIR}" --sync-only; then
            WARNINGS_FOUND=$((WARNINGS_FOUND - SURFACES_DRIFTED))
            SURFACES_DRIFTED=0
            log_success "Self-healed: skill surfaces synchronized."
        else
            log_error "Self-healing failed; the surfaces were left as they were."
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
        fi
    else
        log_info "Run 'harness sync' to bring them up to date, or 'harness sync --check' for the report alone."
    fi
fi

echo ""
log_info "--- 5. CLI Installation ---"
# core/skills/doctor/SKILL.md has always claimed doctor diagnoses broken harness symlinks.
# It did not look at them, so a CLI pointing at a checkout that had since moved reported a
# healthy environment right up to the next command that failed.
BIN_DIR="${HOME}/.local/bin"
EXPECTED_CLI="$(get_harness_root)/bin/harness"

# Reports one link: linked here, pointing elsewhere, or broken. The three default names and
# every profile alias are the same question, so they go through the same answer.
report_cli_link() {
    local cli_name="$1"
    local cli_path="${BIN_DIR}/${cli_name}"
    local cli_target
    cli_target="$(readlink "${cli_path}")"

    if [ "${cli_target}" = "${EXPECTED_CLI}" ]; then
        log_success "CLI linked: ${cli_path}"
        record_check "cli" "${cli_name}" "ok" "${cli_path}"
    elif [ -e "${cli_path}" ]; then
        log_warn "CLI ${cli_path} points at ${cli_target}, not this checkout (${EXPECTED_CLI})."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        record_check "cli" "${cli_name}" "warning" "points at ${cli_target}"
    else
        log_error "CLI ${cli_path} is a broken symlink to ${cli_target}."
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
        record_check "cli" "${cli_name}" "error" "broken symlink to ${cli_target}"
    fi
}

for cli_name in harness agh agent-harness; do
    cli_path="${BIN_DIR}/${cli_name}"
    if [ -L "${cli_path}" ]; then
        report_cli_link "${cli_name}"
    elif [ -e "${cli_path}" ]; then
        log_warn "CLI ${cli_path} exists but is not a symlink; agent-harness will not manage it."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        record_check "cli" "${cli_name}" "warning" "not a symlink"
    else
        log_warn "CLI not installed: ${cli_path}. Run './setup --cli-only' to link it."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        record_check "cli" "${cli_name}" "warning" "not installed"
    fi
done
# A profile's cliAlias is linked by the same installer into the same directory, and doctor
# checked only the three names it installs by default. An alias left behind by a
# configuration nobody uses any more -- pointing at a checkout that is not this one -- was
# invisible here while `harness uninstall --dry-run` listed it, which is the wrong way round
# for the command whose whole job is to say what is wrong.
#
# A link into some checkout's bin/harness is the test, so a symlink to anything else and a
# plain script in the same directory are not this command's business.
if [ -d "${BIN_DIR}" ]; then
    for alias_path in "${BIN_DIR}"/*; do
        [ -L "${alias_path}" ] || continue
        alias_name="$(basename "${alias_path}")"
        case "${alias_name}" in
            harness|agh|agent-harness) continue ;;
        esac
        case "$(readlink "${alias_path}")" in
            */bin/harness) ;;
            *) continue ;;
        esac
        report_cli_link "${alias_name}"
    done
fi

case ":${PATH}:" in
    *":${BIN_DIR}:"*) log_success "On PATH: ${BIN_DIR}" ;;
    *)
        log_warn "${BIN_DIR} is not on PATH, so the linked CLI cannot be invoked by name."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        record_check "cli" "PATH" "warning" "${BIN_DIR} is not on PATH"
        ;;
esac

echo ""
log_info "--- 6. Git Hooks ---"
# Two managed hooks now, reported by one function. agent-harness installs the scanner's
# pre-commit hook and the message validator's commit-msg hook, and a second managed hook
# the diagnostic did not know about is the asymmetry AH-43 was about.
HOOKS_DIR="$(resolve_hooks_dir "${REPO_DIR}" 2>/dev/null || true)"
report_managed_hook() {
    local hook_name="$1"
    local marker="$2"
    local install_command="$3"
    local manual_line="$4"
    local hook_path="${HOOKS_DIR}/${hook_name}"

    if [ ! -e "${hook_path}" ]; then
        log_warn "There is no agent-harness ${hook_name} hook in ${HOOKS_DIR}. Run '${install_command}'."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        record_check "hook" "${hook_name}" "warning" "no ${hook_name} hook is installed"
    elif grep -qxF "${marker}" "${hook_path}" 2>/dev/null; then
        log_success "agent-harness ${hook_name} hook installed: ${hook_path}"
        record_check "hook" "${hook_name}" "ok" "${hook_path}"
    else
        log_warn "A ${hook_name} hook exists that was not written by agent-harness: ${hook_path}"
        log_info "Add '${manual_line}' to it, or replace it with '${install_command} --force'."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        record_check "hook" "${hook_name}" "warning" "a foreign ${hook_name} hook is installed"
    fi
}
if [ -z "${HOOKS_DIR}" ]; then
    log_warn "Hook state unavailable: ${REPO_DIR} is not a Git repository."
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    record_check "hook" "pre-commit" "warning" "not a Git repository"
    record_check "hook" "commit-msg" "warning" "not a Git repository"
else
    report_managed_hook "pre-commit" "${HARNESS_PRE_COMMIT_MARKER}" \
        "harness scan --install-hook" "harness scan --staged || exit 1"
    report_managed_hook "commit-msg" "${HARNESS_COMMIT_MSG_MARKER}" \
        "harness commit --install-hook" 'harness commit check --message-file "$1" || exit 1'
fi

echo ""
log_info "--- 7. Configuration ---"
CONFIG_REPORT_STATUS=0
CONFIG_REPORT="$("${SCRIPT_DIR}/stack-config.sh" validate 2>&1)" || CONFIG_REPORT_STATUS=$?
printf '%s\n' "${CONFIG_REPORT}" | sed 's/^/  /'
if [ "${CONFIG_REPORT_STATUS}" -ne 0 ]; then
    log_error "The resolved configuration did not validate."
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
    record_check "configuration" "config validate" "error" "the resolved configuration did not validate"
else
    record_check "configuration" "config validate" "ok"
fi

echo ""
log_info "--- 8. QA Gates ---"
# doctor answered "0 errors" for a repository whose lint, type and test gates cannot run,
# and the very next command -- `qa all`, or the `ship` that runs it -- failed on exactly
# that. `harness init` warns once at install time and nothing reported it afterwards, so
# the command whose whole job is to say what is wrong was silent about the one thing that
# stops the next one.
#
# Unrunnable is an error rather than a warning, because it is the verdict `qa all` already
# reaches: rules/floor.md invariant 1 is that a gate which could not run is not a gate that
# passed, and reporting that as a warning here would be this command disagreeing with the
# floor. A gate the configuration declares absent with false is a recorded decision and is
# not a problem -- which is what keeps the error satisfiable.
#
# The states come from lib/qa.sh, so nothing is executed here and doctor cannot reach a
# verdict `qa all` would contradict.
for qa_gate in "${QA_COMMAND_GATES[@]}"; do
    QA_GATE_KEY="$(qa_gate_config_key "${qa_gate}")"
    case "$(qa_gate_state "${qa_gate}")" in
        runnable)
            log_success "QA gate '${qa_gate}' is configured: $(qa_gate_command "${qa_gate}")"
            record_check "qa" "${qa_gate}" "ok" "runnable"
            ;;
        declared-absent)
            log_success "QA gate '${qa_gate}': this project records that it has none (${QA_GATE_KEY}: false)."
            record_check "qa" "${qa_gate}" "ok" "declared-absent"
            ;;
        *)
            log_error "QA gate '${qa_gate}' cannot run: nothing is configured for it."
            log_info "Set profiles.${ACTIVE_PROFILE}.${QA_GATE_KEY} to the command this project uses, or to false to record that it has none."
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
            record_check "qa" "${qa_gate}" "error" "unrunnable"
            ;;
    esac
done

if [ "${CHECK_AUTH}" = true ]; then
    echo ""
    log_info "--- 9. Provider Authentication ---"
    # One shape for every provider that has a CLI: the tool, and the command that says
    # whether it is signed in. Adding a provider is a row, not a branch.
    report_provider_auth() {
        local label="$1"
        local provider="$2"
        local cli=""

        case "${provider}" in
            github) cli="gh" ;;
            gitlab) cli="glab" ;;
            standalone)
                log_info "${label} provider is standalone; there is nothing to authenticate."
                return 0
                ;;
            *)
                log_warn "${label} provider '${provider}' has no authentication check, so its state is unknown."
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
                return 0
                ;;
        esac

        if ! command -v "${cli}" >/dev/null 2>&1; then
            log_warn "${label} provider is ${provider} but the '${cli}' CLI is not installed."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        elif "${cli}" auth status >/dev/null 2>&1; then
            log_success "${label} provider ${provider}: authenticated."
        else
            log_warn "${label} provider ${provider}: not authenticated. Run '${cli} auth login'."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    }

    report_provider_auth "Issue tracker" "$(get_profile_value "issueTracker.provider" "standalone")"
    report_provider_auth "CI" "$(get_profile_value "ci.provider" "standalone")"
fi

emit_doctor_json() {
    [ "${JSON_OUTPUT}" = true ] || return 0
    local checks="[]"
    [ ${#JSON_CHECKS[@]} -eq 0 ] || checks="$(printf '%s\n' "${JSON_CHECKS[@]}" | jq -s '.')"
    jq -n --arg status "$1" --arg profile "${ACTIVE_PROFILE}" --arg repository "${REPO_DIR}" \
        --argjson errors "${ERRORS_FOUND}" --argjson warnings "${WARNINGS_FOUND}" \
        --argjson checks "${checks}" \
        '{status: $status, profile: $profile, repository: $repository,
          errors: $errors, warnings: $warnings, checks: $checks}' >&3
}

echo ""
if [ ${ERRORS_FOUND} -eq 0 ] && [ ${WARNINGS_FOUND} -eq 0 ]; then
    log_success "Doctor check passed with 0 issues! Environment is healthy."
    emit_doctor_json "healthy"
elif [ ${ERRORS_FOUND} -eq 0 ]; then
    log_warn "Doctor check completed with ${WARNINGS_FOUND} warning(s)."
    emit_doctor_json "warnings"
else
    log_error "Doctor check failed with ${ERRORS_FOUND} error(s) and ${WARNINGS_FOUND} warning(s)."
    [ "${FIX_MODE}" = false ] && log_info "Run 'harness doctor --fix' to attempt automatic healing."
    emit_doctor_json "failed"
    exit 1
fi
