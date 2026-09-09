#!/usr/bin/env bash
# ==============================================================================
# agent-harness: install.sh
# Universal Multi-Harness Installer & Self-Healing Engine
# Compatible with Google Antigravity, Claude Code, OpenAI Codex, Cursor & .agents
# ==============================================================================

set -Eeo pipefail

SOURCE="${BASH_SOURCE[0]:-}"

bootstrap_remote_install() {
    local repository="${AGENT_HARNESS_REPOSITORY:-https://github.com/ahmontero/agent-harness.git}"
    local ref="${AGENT_HARNESS_REF:-main}"
    local data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
    local install_dir="${AGENT_HARNESS_INSTALL_DIR:-${data_home}/agent-harness}"

    if ! command -v git >/dev/null 2>&1; then
        printf '%s\n' "agent-harness remote installation requires git." >&2
        return 1
    fi

    if [ -d "${install_dir}/.git" ]; then
        printf '%s\n' "Updating agent-harness in ${install_dir}..."
        git -C "${install_dir}" pull --ff-only origin "${ref}"
    elif [ -e "${install_dir}" ]; then
        printf '%s\n' "Cannot install agent-harness: ${install_dir} exists and is not a Git checkout." >&2
        return 1
    else
        printf '%s\n' "Downloading agent-harness to ${install_dir}..."
        mkdir -p "$(dirname "${install_dir}")"
        git clone --depth 1 --branch "${ref}" -- "${repository}" "${install_dir}"
    fi

    if [ "$#" -eq 0 ]; then
        set -- --global
    fi
    exec "${install_dir}/install.sh" "$@"
}

if [ -z "${SOURCE}" ]; then
    bootstrap_remote_install "$@"
fi

while [ -L "${SOURCE}" ]; do
    DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
    SOURCE="$(readlink "${SOURCE}")"
    [[ ${SOURCE} != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
HARNESS_ROOT="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
SCRIPTS_DIR="${HARNESS_ROOT}/core/scripts"

source "${SCRIPTS_DIR}/lib/utils.sh"
source "${SCRIPTS_DIR}/lib/config.sh"
source "${SCRIPTS_DIR}/lib/transaction.sh"

usage() {
    print_banner
    cat << USAGE_EOF

${BOLD}Usage:${RESET}
  ./setup                     # Guided interactive installer (Default)
  ./setup --target <path>     # Initialize harness in target repository
  ./setup --target <path> --expert # Expose advanced primitive skills too
  ./setup --recipe <name>     # Initialize with recipe (python-fastapi, typescript-fullstack, go-microservices)
  ./setup --global            # Install skills & rules globally to user home
  ./setup --global --expert   # Install public workflows and advanced primitives
  ./setup --cli-only          # Install only CLI binaries to ~/.local/bin
  ./setup --verify            # Verify installation health, script syntax & skill frontmatter
  ./setup --sync-only         # Re-sync skills and rules across harnesses
  ./setup --rollback          # Undo the last committed installation

${BOLD}Examples:${RESET}
  ./setup --target ~/projects/my-saas
  ./setup --target ~/projects/my-api --recipe python-fastapi
  ./setup --verify
USAGE_EOF
}

TARGET_REPO=""
RECIPE_NAME=""
INSTALL_GLOBAL=false
CLI_ONLY=false
VERIFY_MODE=false
SYNC_ONLY=false
GUIDED_MODE=false
ROLLBACK_MODE=false
SKILL_MODE="curated"

if [ $# -eq 0 ]; then
    GUIDED_MODE=true
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --guided|-i) GUIDED_MODE=true; shift ;;
        --target) TARGET_REPO="$2"; shift 2 ;;
        --recipe) RECIPE_NAME="$2"; shift 2 ;;
        --global) INSTALL_GLOBAL=true; shift ;;
        --cli-only) CLI_ONLY=true; shift ;;
        --verify) VERIFY_MODE=true; shift ;;
        --sync-only) SYNC_ONLY=true; shift ;;
        --rollback) ROLLBACK_MODE=true; shift ;;
        --expert) SKILL_MODE="expert"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Rollback Mode
if [ "${ROLLBACK_MODE}" = true ]; then
    if [ -n "${TARGET_REPO}" ] || [ "${INSTALL_GLOBAL}" = true ] || [ "${CLI_ONLY}" = true ] || \
       [ "${SYNC_ONLY}" = true ] || [ "${VERIFY_MODE}" = true ] || [ -n "${RECIPE_NAME}" ] || \
       [ "${GUIDED_MODE}" = true ] || [ "${SKILL_MODE}" != "curated" ]; then
        log_error "--rollback cannot be combined with installation options."
        exit 1
    fi
    transaction_rollback_last
    log_success "Last installation transaction rolled back."
    exit 0
fi

# Verification Mode
if [ "${VERIFY_MODE}" = true ]; then
    log_info "Verifying agent-harness scripts and skills..."
    
    # 1. Check syntax of all shell scripts
    log_info "Checking shell script syntax..."
    find "${HARNESS_ROOT}/bin" "${HARNESS_ROOT}/core/scripts" "${HARNESS_ROOT}" -maxdepth 2 -type f \( -name "*.sh" -o -name "harness" -o -name "setup" \) -exec bash -n {} \;
    log_success "All shell scripts passed syntax checks."

    # 2. Check skill frontmatter
    log_info "Verifying skills formatting..."
    find "${HARNESS_ROOT}/core/skills" -name "SKILL.md" | while read -r skill_file; do
        if grep -q "^---" "${skill_file}" && grep -q "^name:" "${skill_file}"; then
            skill_name=$(grep "^name:" "${skill_file}" | head -n 1 | awk '{print $2}')
            log_success "Skill valid: ${skill_name} ($(basename "$(dirname "${skill_file}")"))"
        else
            log_error "Skill missing YAML frontmatter: ${skill_file}"
        fi
    done

    log_success "Verification completed successfully!"
    exit 0
fi

# Ensure executable permissions
find "${HARNESS_ROOT}/bin" "${HARNESS_ROOT}/core/scripts" -type f \( -name "*.sh" -o -name "harness" \) -exec chmod +x {} + 2>/dev/null || true
chmod +x "${HARNESS_ROOT}/install.sh" "${HARNESS_ROOT}/setup" 2>/dev/null || true

SKILL_CATALOG="${HARNESS_ROOT}/core/skills/catalog.json"
MANAGED_MARKER="agent-harness-skill-bundle-v1"
SKILL_NAMESPACE=""

require_skill_catalog() {
    local skill

    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required to install the curated skill surface."
        return 1
    fi
    if [ ! -f "${SKILL_CATALOG}" ] || ! jq empty "${SKILL_CATALOG}" >/dev/null 2>&1; then
        log_error "Invalid or missing skill catalog: ${SKILL_CATALOG}"
        return 1
    fi

    SKILL_NAMESPACE="$(jq -r '.namespace // empty' "${SKILL_CATALOG}")"
    case "${SKILL_NAMESPACE}" in
        ""|*[!a-z0-9_-]*)
            log_error "Unsafe or missing skill namespace in catalog: ${SKILL_NAMESPACE}"
            return 1
            ;;
    esac

    while IFS= read -r skill; do
        case "${skill}" in
            ""|*[!a-z0-9_-]*)
                log_error "Unsafe skill name in catalog: ${skill}"
                return 1
                ;;
        esac
        if [ ! -f "${HARNESS_ROOT}/core/skills/${skill}/SKILL.md" ]; then
            log_error "Catalog references missing skill: ${skill}"
            return 1
        fi
    done < <(jq -r '(.public | keys[]), .internal[], (.public[] | .[])' "${SKILL_CATALOG}" | sort -u)

    while IFS= read -r skill; do
        case "${skill}" in
            ""|*[!a-z0-9_-]*)
                log_error "Unsafe removed skill name in catalog: ${skill}"
                return 1
                ;;
        esac
        if [ -e "${HARNESS_ROOT}/core/skills/${skill}" ]; then
            log_error "Removed skill is still present in source: ${skill}"
            return 1
        fi
    done < <(jq -r '.removed[]' "${SKILL_CATALOG}")

    local gated_workflow gated_runtime
    while IFS= read -r gated_workflow; do
        if ! jq -e --arg workflow "${gated_workflow}" '.public | has($workflow)' "${SKILL_CATALOG}" >/dev/null; then
            log_error "Catalog gates a workflow that is not public: ${gated_workflow}"
            return 1
        fi
    done < <(jq -r '(.runtimes // {}) | keys[]' "${SKILL_CATALOG}")

    while IFS= read -r gated_runtime; do
        case "${gated_runtime}" in
            agents|claude|codex|gemini) ;;
            *)
                log_error "Unknown runtime label in catalog: ${gated_runtime}"
                return 1
                ;;
        esac
    done < <(jq -r '(.runtimes // {}) | to_entries[] | .value[]' "${SKILL_CATALOG}")
}

remove_managed_skill() {
    local skill_path="$1"

    if [ -L "${skill_path}" ]; then
        case "$(readlink "${skill_path}")" in
            "${HARNESS_ROOT}/core/skills/"*) transaction_unlink "${skill_path}" ;;
        esac
    elif [ -d "${skill_path}" ] && [ -f "${skill_path}/.agent-harness-managed" ] && \
         grep -qx "${MANAGED_MARKER}" "${skill_path}/.agent-harness-managed"; then
        transaction_remove_tree "${skill_path}"
    fi
}

workflow_allowed_for_runtime() {
    local workflow="$1"
    local runtime="$2"

    jq -e --arg workflow "${workflow}" --arg runtime "${runtime}" \
        'if (.runtimes // {}) | has($workflow) then (.runtimes[$workflow] | index($runtime)) != null else true end' \
        "${SKILL_CATALOG}" >/dev/null
}

install_workflow_bundle() {
    local destination="$1"
    local workflow="$2"
    local workflow_source="${HARNESS_ROOT}/core/skills/${workflow}/SKILL.md"
    local published_workflow="${SKILL_NAMESPACE}-${workflow}"
    local workflow_destination="${destination}/${published_workflow}"

    if [ -e "${workflow_destination}" ] || [ -L "${workflow_destination}" ]; then
        log_warn "Preserving unmanaged skill path: ${workflow_destination}"
        return
    fi

    transaction_ensure_directory "${workflow_destination}/references"
    transaction_copy "${workflow_source}" "${workflow_destination}/SKILL.md"
    transaction_write_command "${workflow_destination}/.agent-harness-managed" 644 \
        printf '%s\n' "${MANAGED_MARKER}"

    while IFS= read -r primitive; do
        local primitive_source="${HARNESS_ROOT}/core/skills/${primitive}/SKILL.md"
        if [ ! -f "${primitive_source}" ]; then
            log_error "Workflow '${workflow}' references missing primitive '${primitive}'."
            return 1
        fi
        transaction_copy "${primitive_source}" "${workflow_destination}/references/${primitive}.md"
    done < <(jq -r --arg workflow "${workflow}" '.public[$workflow][]' "${SKILL_CATALOG}")
}

install_skill_surface() {
    local destination="$1"
    local runtime="$2"
    transaction_ensure_directory "${destination}"
    require_skill_catalog

    while IFS= read -r skill; do
        remove_managed_skill "${destination}/${skill}"
        remove_managed_skill "${destination}/${SKILL_NAMESPACE}-${skill}"
    done < <(jq -r '(.public | keys[]), .internal[], .removed[]' "${SKILL_CATALOG}" | sort -u)

    while IFS= read -r workflow; do
        if workflow_allowed_for_runtime "${workflow}" "${runtime}"; then
            install_workflow_bundle "${destination}" "${workflow}"
        fi
    done < <(jq -r '.public | keys[]' "${SKILL_CATALOG}")

    if [ "${SKILL_MODE}" = "expert" ]; then
        while IFS= read -r primitive; do
            local published_primitive="${SKILL_NAMESPACE}-${primitive}"
            local primitive_destination="${destination}/${published_primitive}"
            if [ -e "${primitive_destination}" ] || [ -L "${primitive_destination}" ]; then
                log_warn "Preserving unmanaged skill path: ${primitive_destination}"
                continue
            fi
            transaction_symlink "${HARNESS_ROOT}/core/skills/${primitive}" "${primitive_destination}"
        done < <(jq -r '.internal[]' "${SKILL_CATALOG}")
    fi
}

# 1. Install CLI binary into ~/.local/bin
install_cli() {
    local bin_dest="${HOME}/.local/bin"
    transaction_ensure_directory "${bin_dest}"

    log_info "Linking CLI binaries (harness, agh, agent-harness) to ${bin_dest}..."
    transaction_symlink "${HARNESS_ROOT}/bin/harness" "${bin_dest}/harness"
    transaction_symlink "${HARNESS_ROOT}/bin/harness" "${bin_dest}/agh"
    transaction_symlink "${HARNESS_ROOT}/bin/harness" "${bin_dest}/agent-harness"
    
    # Link profile aliases if defined in config
    local config_file
    config_file="$(resolve_config_file)"
    if [ -n "${config_file}" ] && [ -f "${config_file}" ] && command -v jq >/dev/null 2>&1; then
        for profile in $(jq -r '.profiles | keys[]' "${config_file}" 2>/dev/null); do
            local aliases
            aliases=$(jq -r ".profiles[\"${profile}\"].cliAlias // empty" "${config_file}" 2>/dev/null)
            for alias_name in ${aliases}; do
                if [ -n "${alias_name}" ] && [ "${alias_name}" != "harness" ] && [ "${alias_name}" != "agh" ] && [ "${alias_name}" != "agent-harness" ]; then
                    transaction_symlink "${HARNESS_ROOT}/bin/harness" "${bin_dest}/${alias_name}"
                    log_success "Linked CLI alias: ${bin_dest}/${alias_name} -> harness"
                fi
            done
        done
    fi

    log_success "CLI binaries linked. Ensure '${bin_dest}' is in your PATH."
}

# 2. Install into target repository
install_target_repo() {
    local target="$1"
    local recipe="$2"
    transaction_ensure_directory "${target}"

    log_info "Installing agent-harness into target repository: ${BOLD}${target}${RESET}..."

    # Apply recipe if specified
    if [ -n "${recipe}" ] && [ -d "${HARNESS_ROOT}/recipes/${recipe}" ]; then
        log_info "Applying recipe: ${BOLD}${recipe}${RESET}..."
        if [ ! -f "${target}/stack.config.json" ]; then
            transaction_copy "${HARNESS_ROOT}/recipes/${recipe}/stack.config.json" "${target}/stack.config.json"
        fi
        transaction_ensure_directory "${target}/rules"
        local recipe_rule
        for recipe_rule in "${HARNESS_ROOT}/recipes/${recipe}/rules/"*; do
            [ -f "${recipe_rule}" ] || continue
            transaction_copy "${recipe_rule}" "${target}/rules/$(basename "${recipe_rule}")"
        done
    fi

    # Create target directories
    local gemini_skills="${target}/.gemini/skills"
    local claude_skills="${target}/.claude/skills"
    local codex_skills="${target}/.codex/skills"
    local agents_skills="${target}/.agents/skills"
    
    local gemini_rules="${target}/.gemini/rules"
    local claude_rules="${target}/.claude/rules"
    local codex_rules="${target}/.codex/rules"
    local cursor_rules="${target}/.cursor/rules"
    local agents_rules="${target}/.agents/rules"

    local target_directory
    for target_directory in "${gemini_skills}" "${claude_skills}" "${codex_skills}" "${agents_skills}" \
                            "${gemini_rules}" "${claude_rules}" "${codex_rules}" "${cursor_rules}" "${agents_rules}"; do
        transaction_ensure_directory "${target_directory}"
    done

    install_skill_surface "${gemini_skills}" gemini
    install_skill_surface "${claude_skills}" claude
    install_skill_surface "${codex_skills}" codex
    install_skill_surface "${agents_skills}" agents

    # Create AGENTS.md and symlinks
    if [ ! -f "${target}/AGENTS.md" ]; then
        transaction_copy "${HARNESS_ROOT}/core/templates/AGENTS-template.md" "${target}/AGENTS.md"
        log_success "Created canonical AGENTS.md in ${target}"
    fi

    transaction_symlink "AGENTS.md" "${target}/CLAUDE.md"
    transaction_symlink "AGENTS.md" "${target}/GEMINI.md"

    # Default rules & config if missing
    if [ ! -f "${target}/stack.config.json" ]; then
        transaction_copy "${HARNESS_ROOT}/core/templates/stack-config-template.json" "${target}/stack.config.json"
        log_success "Created default stack.config.json in ${target}"
    fi

    transaction_ensure_directory "${target}/rules"
    if [ ! -f "${target}/rules/floor.md" ]; then
        transaction_copy "${HARNESS_ROOT}/core/templates/floor-template.md" "${target}/rules/floor.md"
    fi
    if [ ! -f "${target}/rules/landmines.md" ]; then
        transaction_copy "${HARNESS_ROOT}/core/templates/landmines-template.md" "${target}/rules/landmines.md"
    fi
    if [ ! -f "${target}/rules/landmines.json" ]; then
        transaction_copy "${HARNESS_ROOT}/core/templates/landmines-template.json" "${target}/rules/landmines.json"
    fi

    log_success "agent-harness initialized in ${target}"
}

# 3. Global Installation
install_global() {
    log_info "Installing ${SKILL_MODE} skill surface globally to ~/.gemini, ~/.claude, ~/.codex, ~/.agents..."
    local gemini_skills="${HOME}/.gemini/antigravity/skills"
    local gemini_config_skills="${HOME}/.gemini/config/skills"
    local claude_skills="${HOME}/.claude/skills"
    local codex_skills="${HOME}/.codex/skills"
    local agents_skills="${HOME}/.agents/skills"

    local global_directory
    for global_directory in "${gemini_skills}" "${gemini_config_skills}" "${claude_skills}" \
                            "${codex_skills}" "${agents_skills}"; do
        transaction_ensure_directory "${global_directory}"
    done

    install_skill_surface "${gemini_skills}" gemini
    install_skill_surface "${gemini_config_skills}" gemini
    install_skill_surface "${claude_skills}" claude
    install_skill_surface "${codex_skills}" codex
    install_skill_surface "${agents_skills}" agents

    log_success "Global agent skill surface installed."
}

# Execution
transaction_begin install

if [ "${INSTALL_GLOBAL}" = true ] || [ "${CLI_ONLY}" = true ] || [ "${GUIDED_MODE}" = true ]; then
    install_cli
fi

if [ "${CLI_ONLY}" = true ]; then
    transaction_commit
    exit 0
fi

if [ -n "${TARGET_REPO}" ]; then
    install_target_repo "${TARGET_REPO}" "${RECIPE_NAME}"
elif [ "${INSTALL_GLOBAL}" = true ] || [ "${SYNC_ONLY}" = true ]; then
    install_global
elif [ "${GUIDED_MODE}" = true ]; then
    print_banner
    echo ""
    log_info "Guided Setup Mode"
    install_global
    install_target_repo "$(pwd)" "${RECIPE_NAME}"
fi

transaction_commit

log_success "Setup complete! Run 'harness doctor' to verify."
log_info "Undo this installation with './setup --rollback'."
