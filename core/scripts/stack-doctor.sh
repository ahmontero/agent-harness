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

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
FIX_MODE=false
CHECK_AUTH=false

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
        -h|--help)
            echo "Usage: harness doctor [--fix] [--check-auth]"
            exit 0
            ;;
        *)
            # `harness doctor --fixx` used to run the diagnosis and repair nothing, while
            # reading as though --fix had been honoured.
            log_error "Unknown doctor option: $1"
            echo "Usage: harness doctor [--fix] [--check-auth]"
            exit 1
            ;;
    esac
done

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
    else
        if [ "${required}" = "true" ]; then
            log_error "Missing required CLI tool: ${name}"
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
        else
            log_warn "Optional CLI tool not found: ${name}"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
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
    else
        log_warn "Missing AGENTS.md in ${REPO_DIR}"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
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
                    ;;
                drifted)
                    SURFACES_DRIFTED=$((SURFACES_DRIFTED + 1))
                    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
                    log_warn "drifted   ${directory} (${runtime}) [${scope_label}]"
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
for cli_name in harness agh agent-harness; do
    cli_path="${BIN_DIR}/${cli_name}"
    if [ -L "${cli_path}" ]; then
        cli_target="$(readlink "${cli_path}")"
        if [ "${cli_target}" = "${EXPECTED_CLI}" ]; then
            log_success "CLI linked: ${cli_path}"
        elif [ -e "${cli_path}" ]; then
            log_warn "CLI ${cli_path} points at ${cli_target}, not this checkout (${EXPECTED_CLI})."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        else
            log_error "CLI ${cli_path} is a broken symlink to ${cli_target}."
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
        fi
    elif [ -e "${cli_path}" ]; then
        log_warn "CLI ${cli_path} exists but is not a symlink; agent-harness will not manage it."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    else
        log_warn "CLI not installed: ${cli_path}. Run './setup --cli-only' to link it."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    fi
done
case ":${PATH}:" in
    *":${BIN_DIR}:"*) log_success "On PATH: ${BIN_DIR}" ;;
    *)
        log_warn "${BIN_DIR} is not on PATH, so the linked CLI cannot be invoked by name."
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        ;;
esac

echo ""
log_info "--- 6. Pre-Commit Hook ---"
HOOKS_DIR="$(resolve_hooks_dir "${REPO_DIR}" 2>/dev/null || true)"
if [ -z "${HOOKS_DIR}" ]; then
    log_warn "Hook state unavailable: ${REPO_DIR} is not a Git repository."
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
elif [ ! -e "${HOOKS_DIR}/pre-commit" ]; then
    log_warn "There is no agent-harness pre-commit hook in ${HOOKS_DIR}. Run 'harness scan --install-hook'."
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
elif grep -qxF "${HARNESS_PRE_COMMIT_MARKER}" "${HOOKS_DIR}/pre-commit" 2>/dev/null; then
    log_success "Landmine pre-commit hook installed: ${HOOKS_DIR}/pre-commit"
else
    log_warn "A pre-commit hook exists that was not written by agent-harness: ${HOOKS_DIR}/pre-commit"
    log_info "Add 'harness scan --staged || exit 1' to it, or replace it with 'harness scan --install-hook --force'."
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi

echo ""
log_info "--- 7. Configuration ---"
CONFIG_REPORT_STATUS=0
CONFIG_REPORT="$("${SCRIPT_DIR}/stack-config.sh" validate 2>&1)" || CONFIG_REPORT_STATUS=$?
printf '%s\n' "${CONFIG_REPORT}" | sed 's/^/  /'
if [ "${CONFIG_REPORT_STATUS}" -ne 0 ]; then
    log_error "The resolved configuration did not validate."
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
fi

if [ "${CHECK_AUTH}" = true ]; then
    echo ""
    log_info "--- 8. Provider Authentication ---"
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

echo ""
if [ ${ERRORS_FOUND} -eq 0 ] && [ ${WARNINGS_FOUND} -eq 0 ]; then
    log_success "Doctor check passed with 0 issues! Environment is healthy."
elif [ ${ERRORS_FOUND} -eq 0 ]; then
    log_warn "Doctor check completed with ${WARNINGS_FOUND} warning(s)."
else
    log_error "Doctor check failed with ${ERRORS_FOUND} error(s) and ${WARNINGS_FOUND} warning(s)."
    [ "${FIX_MODE}" = false ] && log_info "Run 'harness doctor --fix' to attempt automatic healing."
    exit 1
fi
