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
            shift
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
check_cmd "curl" "true"
check_cmd "ollama" "false"

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
            local template="$(get_harness_root)/core/templates/AGENTS-template.md"
            if [ -f "${template}" ]; then
                cp "${template}" "${REPO_DIR}/AGENTS.md"
                log_success "Self-healed: Created AGENTS.md from template."
            fi
        fi
    fi
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
