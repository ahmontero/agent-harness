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
source "${SCRIPTS_DIR}/lib/surface.sh"

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
  ./setup --seed-target <path> # Install skill surfaces into an existing worktree
  ./setup --rollback          # Undo the last committed installation
  ./setup --yes               # Confirm the guided installation without a prompt

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
SYNC_TARGET=""
SEED_TARGET=""
GUIDED_MODE=false
ROLLBACK_MODE=false
SKILL_MODE="curated"
ASSUME_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --guided|-i) GUIDED_MODE=true; shift ;;
        # Each of these consumed the next argument without checking there was one. With the
        # value left off, `shift 2` failed under `set -e` and the installer exited 1 having
        # printed nothing, so a forgotten path looked exactly like a crash.
        --target)
            [ -n "${2:-}" ] || { log_error "--target requires a path to a repository."; exit 1; }
            TARGET_REPO="$2"; shift 2 ;;
        --recipe)
            [ -n "${2:-}" ] || { log_error "--recipe requires a recipe name."; exit 1; }
            RECIPE_NAME="$2"; shift 2 ;;
        --global) INSTALL_GLOBAL=true; shift ;;
        --cli-only) CLI_ONLY=true; shift ;;
        --verify) VERIFY_MODE=true; shift ;;
        --sync-only|--sync-global) SYNC_ONLY=true; shift ;;
        --sync-target)
            [ -n "${2:-}" ] || { log_error "--sync-target requires a path to a repository."; exit 1; }
            SYNC_TARGET="$2"; shift 2 ;;
        --seed-target)
            [ -n "${2:-}" ] || { log_error "--seed-target requires a path to a worktree."; exit 1; }
            SEED_TARGET="$2"; shift 2 ;;
        --rollback) ROLLBACK_MODE=true; shift ;;
        --expert) SKILL_MODE="expert"; shift ;;
        --yes|-y) ASSUME_YES=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Rollback Mode
if [ "${ROLLBACK_MODE}" = true ]; then
    if [ -n "${TARGET_REPO}" ] || [ "${INSTALL_GLOBAL}" = true ] || [ "${CLI_ONLY}" = true ] || \
       [ "${SYNC_ONLY}" = true ] || [ "${VERIFY_MODE}" = true ] || [ -n "${RECIPE_NAME}" ] || \
       [ -n "${SYNC_TARGET}" ] || [ -n "${SEED_TARGET}" ] || \
       [ "${GUIDED_MODE}" = true ] || [ "${SKILL_MODE}" != "curated" ] || \
       [ "${ASSUME_YES}" = true ]; then
        log_error "--rollback cannot be combined with installation options."
        exit 1
    fi
    transaction_rollback_last
    log_success "Last installation transaction rolled back."
    exit 0
fi

# Verification Mode
#
# Both checks run to completion and accumulate into one counter, so a single invocation
# reports every problem rather than turning the gate into a per-run bisection. Neither
# loop may run in a pipeline: a `find | while` body increments the counter in a subshell,
# which is how the frontmatter check previously lost every error it printed.
if [ "${VERIFY_MODE}" = true ]; then
    log_info "Verifying agent-harness scripts and skills..."
    VERIFY_FAILURES=0

    # 1. Check syntax of all shell scripts
    log_info "Checking shell script syntax..."
    while IFS= read -r script_file; do
        if ! bash -n "${script_file}"; then
            log_error "Shell syntax error: ${script_file}"
            VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
        fi
    done < <(find "${HARNESS_ROOT}/bin" "${HARNESS_ROOT}/core/scripts" "${HARNESS_ROOT}" -maxdepth 2 -type f \( -name "*.sh" -o -name "harness" -o -name "setup" \))
    if [ "${VERIFY_FAILURES}" -eq 0 ]; then
        log_success "All shell scripts passed syntax checks."
    fi

    # 2. Check skill frontmatter
    log_info "Verifying skills formatting..."
    while IFS= read -r skill_file; do
        if grep -q "^---" "${skill_file}" && grep -q "^name:" "${skill_file}"; then
            skill_name=$(grep "^name:" "${skill_file}" | head -n 1 | awk '{print $2}')
            log_success "Skill valid: ${skill_name} ($(basename "$(dirname "${skill_file}")"))"
        else
            log_error "Skill missing YAML frontmatter: ${skill_file}"
            VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
        fi
    done < <(find "${HARNESS_ROOT}/core/skills" -name "SKILL.md")

    if [ "${VERIFY_FAILURES}" -ne 0 ]; then
        log_error "Verification failed with ${VERIFY_FAILURES} problem(s)."
        exit 1
    fi
    log_success "Verification completed successfully!"
    exit 0
fi

# Guided is the default scope, as the usage text says: a run that named no scope -- no
# arguments at all, or only modifiers such as --yes, --expert, or --recipe -- is a guided
# installation. Keying it on `$# -eq 0` instead meant `./setup --yes` selected no action
# and still printed "Setup complete!", which is the failure shape this delta exists to remove.
if [ "${GUIDED_MODE}" = false ] && [ -z "${TARGET_REPO}" ] && [ -z "${SYNC_TARGET}" ] && \
   [ -z "${SEED_TARGET}" ] && \
   [ "${INSTALL_GLOBAL}" = false ] && [ "${CLI_ONLY}" = false ] && [ "${SYNC_ONLY}" = false ]; then
    GUIDED_MODE=true
fi

# ./setup is advertised as a guided interactive installer and asked nothing, so running it
# from $HOME installed AGENTS.md, a CLAUDE.md and GEMINI.md symlink, stack.config.json,
# rules/, and four skill surfaces into the home directory. It now names both destinations
# and waits. With no terminal it refuses rather than hanging or assuming consent, so a
# scripted or agent invocation has to choose a scope explicitly.
require_guided_confirmation() {
    local answer=""

    if ! git -C "$(pwd)" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "$(pwd) is not a Git repository, and every workflow the installed surface describes needs one."
        log_info "Run 'git init' first, or install elsewhere with --target <path>, or install only the global surfaces with --global."
        return 1
    fi

    log_info "Guided installation will write to:"
    log_info "  the global skill surfaces under ${HOME}"
    log_info "  this repository: $(pwd)"

    [ "${ASSUME_YES}" = true ] && return 0

    if [ ! -t 0 ]; then
        log_error "Guided installation needs a confirmation and there is no terminal to ask on; nothing was written."
        log_info "Re-run with --yes to confirm, or choose a scope explicitly: --global for the surfaces alone, --target <path> for one repository."
        return 1
    fi

    printf 'Proceed? [y/N] '
    read -r answer
    case "${answer}" in
        [yY]|[yY][eE][sS]) return 0 ;;
    esac
    log_error "Guided installation cancelled; nothing was written."
    return 1
}

if [ "${GUIDED_MODE}" = true ]; then
    print_banner
    echo ""
    require_guided_confirmation || exit 1
fi

# Ensure executable permissions
find "${HARNESS_ROOT}/bin" "${HARNESS_ROOT}/core/scripts" -type f \( -name "*.sh" -o -name "harness" \) -exec chmod +x {} + 2>/dev/null || true
chmod +x "${HARNESS_ROOT}/install.sh" "${HARNESS_ROOT}/setup" 2>/dev/null || true

SKILL_CATALOG="${HARNESS_ROOT}/core/skills/catalog.json"
MANAGED_MARKER="${SURFACE_MANAGED_MARKER}"
SKILL_NAMESPACE=""

# Manifest name, schema, and the digest functions live in lib/surface.sh, shared with the
# drift check so the two can never drift apart themselves.
SURFACE_ENTRIES=()
HARNESS_VERSION=""

# A published skill name occupied by something the installer may not touch. Counted rather
# than warned about, because a run that could not install what it was asked to install has
# not succeeded, whatever it printed on the way.
SURFACE_BLOCKED=0

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

# Removes an entry only if agent-harness installed it. The symlink test is shared with the
# drift check in lib/surface.sh and matches any checkout's core/skills, not just this one:
# pinning it to ${HARNESS_ROOT} meant a surface installed from a second checkout could
# never be repaired from anywhere else.
remove_managed_skill() {
    local skill_path="$1"

    surface_entry_is_managed "${skill_path}" || return 0

    if [ -L "${skill_path}" ]; then
        transaction_unlink "${skill_path}"
    else
        transaction_remove_tree "${skill_path}"
    fi
}

# Removes every managed skill this runtime and mode no longer publishes, by name. Repair
# means the surface ends up as the catalog describes it; a stale skill left competing with
# its namespaced replacement in an agent's skill list is the failure the manifest exists
# to prevent.
prune_unpublished_managed_skills() {
    local destination="$1"
    local runtime="$2"
    local expected entry name
    expected="$(surface_expected_entries "${runtime}" "${SKILL_MODE}" | cut -f1 | LC_ALL=C sort)"

    for entry in "${destination}"/*; do
        [ -e "${entry}" ] || [ -L "${entry}" ] || continue
        name="$(basename "${entry}")"
        [ "${name}" = "${SURFACE_MANIFEST_NAME}" ] && continue
        surface_entry_is_managed "${entry}" || continue
        if ! printf '%s\n' "${expected}" | grep -qxF "${name}"; then
            log_warn "Removing ${name}: a managed skill this surface no longer publishes."
            remove_managed_skill "${entry}"
        fi
    done
}

workflow_allowed_for_runtime() {
    surface_workflow_allowed "$1" "$2"
}

install_workflow_bundle() {
    local destination="$1"
    local workflow="$2"
    local workflow_source="${HARNESS_ROOT}/core/skills/${workflow}/SKILL.md"
    local published_workflow="${SKILL_NAMESPACE}-${workflow}"
    local workflow_destination="${destination}/${published_workflow}"

    if [ -e "${workflow_destination}" ] || [ -L "${workflow_destination}" ]; then
        log_warn "Preserving unmanaged skill path: ${workflow_destination}"
        SURFACE_BLOCKED=$((SURFACE_BLOCKED + 1))
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

    SURFACE_ENTRIES+=("$(jq -nc \
        --arg name "${published_workflow}" \
        --arg digest "$(surface_source_digest "${workflow}")" \
        '{name: $name, kind: "bundle", digest: $digest}')")
}

install_skill_surface() {
    local destination="$1"
    local runtime="$2"

    case "${runtime}" in
        agents|claude|codex|gemini) ;;
        *)
            log_error "install_skill_surface requires a known runtime label, got: '${runtime}'"
            return 1
            ;;
    esac

    transaction_ensure_directory "${destination}"
    require_skill_catalog
    SURFACE_ENTRIES=()
    HARNESS_VERSION="$(surface_harness_version)"

    # Pruning comes first so that a skill this surface no longer publishes is reported by
    # name rather than disappearing inside the reinstall loop below.
    prune_unpublished_managed_skills "${destination}" "${runtime}"

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
                SURFACE_BLOCKED=$((SURFACE_BLOCKED + 1))
                continue
            fi
            transaction_symlink "${HARNESS_ROOT}/core/skills/${primitive}" "${primitive_destination}"
            SURFACE_ENTRIES+=("$(jq -nc --arg name "${published_primitive}" '{name: $name, kind: "symlink"}')")
        done < <(jq -r '.internal[]' "${SKILL_CATALOG}")
    fi

    write_surface_manifest "${destination}" "${runtime}"
}

# Written last, and through the transaction, so a mid-install failure rolls it back with
# everything else. A manifest that outlived the surface it describes would be worse than
# no manifest: the drift check would read it and report a surface that is not there.
write_surface_manifest() {
    local destination="$1"
    local runtime="$2"
    local skills_json="[]"

    if [ ${#SURFACE_ENTRIES[@]} -gt 0 ]; then
        skills_json="$(printf '%s\n' "${SURFACE_ENTRIES[@]}" | jq -sc 'sort_by(.name)')"
    fi

    transaction_write_command "${destination}/${SURFACE_MANIFEST_NAME}" 644 \
        jq -n \
            --argjson schemaVersion "${SURFACE_MANIFEST_SCHEMA}" \
            --arg namespace "${SKILL_NAMESPACE}" \
            --arg harnessVersion "${HARNESS_VERSION}" \
            --arg mode "${SKILL_MODE}" \
            --arg runtime "${runtime}" \
            --argjson skills "${skills_json}" \
            '{schemaVersion: $schemaVersion, namespace: $namespace, harnessVersion: $harnessVersion, mode: $mode, runtime: $runtime, skills: $skills}'
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

# ------------------------------------------------------------------------------
# Project detection
#
# init used to copy a fixed template declaring every repository a Python "backend" running
# pytest, with a GitHub issue prefix of PROJ and a trunk branch of main. In a Node, Go, or
# Rust project the first command a new user ran -- `harness qa all` -- therefore invoked
# pytest. The README already promised detection, so the claim existed and the code did not
# honour it.
#
# The rule here is that every command written is evidenced by a file in the target: a
# `test` script in package.json, `[tool.ruff]` in pyproject.toml, manage.py for Django,
# .golangci.yml for golangci-lint. What is not evidenced is left unset, because a gate that
# reports it could not run is correct and a gate that runs the wrong tool is not.
#
# One profile per ecosystem, each with its own detect block, so a polyglot repository
# resolves the right one per directory through the mechanism the format already provides.
# ------------------------------------------------------------------------------

DETECTED_PROFILES=()
DETECTED_UNSET=()

# "<jq object>" per profile, combined into .profiles by write_detected_config.
add_detected_profile() {
    local name="$1" display="$2" detect_files="$3" qa_json="$4"
    DETECTED_PROFILES+=("$(jq -nc \
        --arg name "${name}" \
        --arg display "${display}" \
        --argjson files "${detect_files}" \
        --argjson qa "${qa_json}" \
        '{name: $name, profile: ({displayName: $display, detect: {files: $files}}
            + (if ($qa | length) > 0 then {qa: $qa} else {} end)
            + {rules: {invariants: "./rules/floor.md", landmines: "./rules/landmines.md", scanner: "./rules/landmines.json"}})}')")
}

note_unset_gate() {
    DETECTED_UNSET+=("$1")
}

detect_python_profile() {
    local target="$1"
    local pyproject="${target}/pyproject.toml"
    local qa='{}'

    [ -f "${pyproject}" ] || [ -f "${target}/setup.py" ] || [ -f "${target}/requirements.txt" ] || return 0

    if [ -f "${target}/manage.py" ]; then
        qa="$(jq -nc '{testRunner: "django", testCommand: "python manage.py test", tddCommand: "python manage.py test {path}"}')"
    elif grep -qs 'pytest' "${pyproject}" "${target}"/requirements*.txt 2>/dev/null || \
         [ -f "${target}/pytest.ini" ]; then
        qa="$(jq -nc '{testRunner: "pytest", testCommand: "pytest", tddCommand: "pytest {path}"}')"
    else
        note_unset_gate "qa.testCommand for the python profile: no manage.py and no pytest in the dependencies"
    fi

    if grep -qs '\[tool\.ruff' "${pyproject}" 2>/dev/null; then
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {lintCommand: "ruff check ."}')"
    else
        note_unset_gate "qa.lintCommand for the python profile: no [tool.ruff] in pyproject.toml"
    fi

    if grep -qs '\[tool\.mypy' "${pyproject}" 2>/dev/null || [ -f "${target}/mypy.ini" ]; then
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {typeCheckCommand: "mypy ."}')"
    else
        note_unset_gate "qa.typeCheckCommand for the python profile: no [tool.mypy] and no mypy.ini"
    fi

    add_detected_profile python "Python" '["pyproject.toml","setup.py","requirements.txt"]' "${qa}"
}

detect_node_profile() {
    local target="$1"
    local manifest="${target}/package.json"
    local qa='{}'
    [ -f "${manifest}" ] || return 0
    jq empty "${manifest}" >/dev/null 2>&1 || {
        log_warn "${manifest} is not valid JSON, so no Node commands could be detected."
        add_detected_profile node "Node.js" '["package.json"]' '{}'
        return 0
    }

    if jq -e '.scripts.test // empty' "${manifest}" >/dev/null 2>&1; then
        qa="$(jq -nc '{testCommand: "npm test"}')"
    else
        note_unset_gate "qa.testCommand for the node profile: package.json declares no test script"
    fi

    if jq -e '(.devDependencies // {}) + (.dependencies // {}) | has("vitest")' "${manifest}" >/dev/null 2>&1; then
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {testRunner: "vitest", tddCommand: "npx vitest run {path}"}')"
    elif jq -e '(.devDependencies // {}) + (.dependencies // {}) | has("jest")' "${manifest}" >/dev/null 2>&1; then
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {testRunner: "jest", tddCommand: "npx jest {path}"}')"
    else
        note_unset_gate "qa.tddCommand for the node profile: neither vitest nor jest is a dependency"
    fi

    if jq -e '.scripts.lint // empty' "${manifest}" >/dev/null 2>&1; then
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {lintCommand: "npm run lint"}')"
    else
        note_unset_gate "qa.lintCommand for the node profile: package.json declares no lint script"
    fi

    if jq -e '.scripts.typecheck // empty' "${manifest}" >/dev/null 2>&1; then
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {typeCheckCommand: "npm run typecheck"}')"
    elif [ -f "${target}/tsconfig.json" ]; then
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {typeCheckCommand: "npx tsc --noEmit"}')"
    else
        note_unset_gate "qa.typeCheckCommand for the node profile: no typecheck script and no tsconfig.json"
    fi

    add_detected_profile node "Node.js" '["package.json"]' "${qa}"
}

# false, not unset, for the type gate: the Go and Rust compilers type-check as part of
# building, so "this project has none" is a decision the target evidences rather than a
# gap the user still has to fill.
detect_go_profile() {
    local target="$1"
    local qa
    [ -f "${target}/go.mod" ] || return 0
    qa="$(jq -nc '{testRunner: "go", testCommand: "go test ./...", tddCommand: "go test -run {path} ./...", typeCheckCommand: false}')"
    if [ -f "${target}/.golangci.yml" ] || [ -f "${target}/.golangci.yaml" ]; then
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {lintCommand: "golangci-lint run"}')"
    else
        qa="$(jq -nc --argjson qa "${qa}" '$qa + {lintCommand: "go vet ./..."}')"
    fi
    add_detected_profile go "Go" '["go.mod"]' "${qa}"
}

detect_rust_profile() {
    local target="$1"
    [ -f "${target}/Cargo.toml" ] || return 0
    add_detected_profile rust "Rust" '["Cargo.toml"]' \
        "$(jq -nc '{testRunner: "cargo", testCommand: "cargo test", tddCommand: "cargo test {path}", lintCommand: "cargo clippy --all-targets -- -D warnings", typeCheckCommand: false}')"
}

# Read from the remote rather than assumed. The previous template asserted a GitHub issue
# tracker with a prefix of PROJ, which is a fact about no repository in particular.
detect_forge_block() {
    local target="$1"
    local remote
    remote="$(git -C "${target}" remote get-url origin 2>/dev/null || true)"
    case "${remote}" in
        *github.com*) jq -nc '{ci: {provider: "github"}, issueTracker: {provider: "github"}}' ;;
        *gitlab*)     jq -nc '{ci: {provider: "gitlab"}, issueTracker: {provider: "gitlab"}}' ;;
        *)            printf '%s' '{}' ;;
    esac
}

emit_detected_config() {
    local target="$1"
    local profiles_json='{}' default_profile forge

    if [ ${#DETECTED_PROFILES[@]} -gt 0 ]; then
        profiles_json="$(printf '%s\n' "${DETECTED_PROFILES[@]}" | jq -sc 'map({key: .name, value: .profile}) | from_entries')"
        default_profile="$(printf '%s\n' "${DETECTED_PROFILES[0]}" | jq -r '.name')"
    else
        profiles_json="$(jq -nc '{default: {displayName: "Project", rules: {invariants: "./rules/floor.md", landmines: "./rules/landmines.md", scanner: "./rules/landmines.json"}}}')"
        default_profile="default"
    fi

    forge="$(detect_forge_block "${target}")"
    jq -n \
        --arg schema "https://raw.githubusercontent.com/ahmontero/agent-harness/main/schema.json" \
        --arg name "$(basename "${target}")" \
        --arg default "${default_profile}" \
        --argjson profiles "${profiles_json}" \
        --argjson forge "${forge}" \
        '{"$schema": $schema, project: {name: $name, defaultProfile: $default},
          profiles: ($profiles | with_entries(.value = (.value + $forge)))}'
}

write_detected_config() {
    local target="$1"
    local destination="${target}/stack.config.json"
    local gate

    DETECTED_PROFILES=()
    DETECTED_UNSET=()
    detect_python_profile "${target}"
    detect_node_profile "${target}"
    detect_go_profile "${target}"
    detect_rust_profile "${target}"

    transaction_write_command "${destination}" 644 emit_detected_config "${target}"

    if [ ${#DETECTED_PROFILES[@]} -eq 0 ]; then
        log_warn "No Python, Node, Go, or Rust project was found in ${target}."
        log_info "Set profiles.default.qa.testCommand, .lintCommand and .typeCheckCommand in ${destination}, or false where this project has none."
        return 0
    fi

    log_success "Detected $(printf '%s\n' "${DETECTED_PROFILES[@]}" | jq -r '.name' | tr '\n' ' ')in ${target}."
    if [ ${#DETECTED_UNSET[@]} -gt 0 ]; then
        log_warn "No evidence in the target for these, so they are left unset in ${destination}:"
        for gate in "${DETECTED_UNSET[@]}"; do
            printf '  %s\n' "${gate}"
        done
        log_info "Set each to this project's command, or to false to record that it has none."
    fi
}

GITIGNORE_MARKER="# agent-harness: installed skill surfaces"

# Prints the .gitignore the target should have: whatever it already has, then the block.
# A separate function because transaction_write_command runs a command and captures its
# output, which is what keeps the file inside the installation transaction.
emit_gitignore_with_surfaces() {
    local existing="$1"
    if [ -f "${existing}" ]; then
        cat "${existing}"
        [ -n "$(tail -c 1 "${existing}")" ] && printf '\n'
        printf '\n'
    fi
    cat <<GITIGNORE_BLOCK_EOF
${GITIGNORE_MARKER}
# Rebuilt by 'harness sync'; 'harness worktree seed <path>' installs them into a worktree.
# AGENTS.md, CLAUDE.md, GEMINI.md, rules/ and stack.config.json are yours -- commit those.
.claude/skills/
.gemini/skills/
.codex/skills/
.agents/skills/
GITIGNORE_BLOCK_EOF
}

# Whether a worktree carries the harness was decided by a .gitignore the user wrote by
# accident: init installed four surfaces and said nothing about Git, so a project that
# happened to commit them got working worktrees and a project that happened to ignore them
# got empty ones. The decision is now recorded, once, where Git will read it.
#
# The CLAUDE.md and GEMINI.md symlinks are deliberately absent from the block. They are the
# project's own configuration, they cost nothing in Git, and committing them is what lets
# every worktree inherit AGENTS.md without seeding anything.
record_surfaces_in_gitignore() {
    local target="$1"
    local gitignore="${target}/.gitignore"

    git -C "${target}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    if [ -f "${gitignore}" ] && grep -qxF "${GITIGNORE_MARKER}" "${gitignore}"; then
        return 0
    fi

    transaction_write_command "${gitignore}" 644 emit_gitignore_with_surfaces "${gitignore}"
    log_success "Recorded the installed skill surfaces in ${gitignore}."
}

# Installs the skill surfaces and the AGENTS.md symlinks into a directory that is already a
# checkout of this project, and nothing else. A worktree gets its tracked files from Git;
# what it cannot get from Git is an installation artifact, and that is all this writes.
seed_worktree_surfaces() {
    local target="$1"

    log_info "Seeding skill surfaces into ${BOLD}${target}${RESET}..."
    install_skill_surface "${target}/.gemini/skills" gemini
    install_skill_surface "${target}/.claude/skills" claude
    install_skill_surface "${target}/.codex/skills" codex
    install_skill_surface "${target}/.agents/skills" agents

    if [ -f "${target}/AGENTS.md" ]; then
        [ -e "${target}/CLAUDE.md" ] || transaction_symlink "AGENTS.md" "${target}/CLAUDE.md"
        [ -e "${target}/GEMINI.md" ] || transaction_symlink "AGENTS.md" "${target}/GEMINI.md"
    else
        log_warn "${target} carries no AGENTS.md, so no CLAUDE.md or GEMINI.md symlink was written."
    fi

    log_success "Seeded ${target}."
}

# 2. Install into target repository
install_target_repo() {
    local target="$1"
    local recipe="$2"
    transaction_ensure_directory "${target}"

    log_info "Installing agent-harness into target repository: ${BOLD}${target}${RESET}..."

    if ! git -C "${target}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_warn "${target} is not a Git repository; branch, worktree, spec, receipt, ledger, and scan commands will not work there until it is one."
    fi

    # An unknown recipe used to be tested with [ -d ... ] and skipped in silence, so a
    # typo installed no recipe at all and the run still reported success.
    if [ -n "${recipe}" ] && [ ! -d "${HARNESS_ROOT}/recipes/${recipe}" ]; then
        log_error "Unknown recipe: ${recipe}"
        log_info "Available recipes: $(find "${HARNESS_ROOT}/recipes" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort | tr '\n' ' ')"
        return 1
    fi

    # Apply recipe if specified
    if [ -n "${recipe}" ]; then
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
    
    # There were five more directories here -- .gemini/rules, .claude/rules, .codex/rules,
    # .cursor/rules and .agents/rules -- created on every install and never written into.
    # No runtime reads them: the four agents read AGENTS.md, and the quality floor and the
    # landmines live in rules/ at the root, named there and in stack.config.json. Git does
    # not carry an empty directory either, so they did not even survive a clone.
    local target_directory
    for target_directory in "${gemini_skills}" "${claude_skills}" "${codex_skills}" "${agents_skills}"; do
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

    record_surfaces_in_gitignore "${target}"

    # Default rules & config if missing
    if [ ! -f "${target}/stack.config.json" ]; then
        write_detected_config "${target}"
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

# Repair, never initialize. Only a surface that already exists and already carries a
# managed bundle is synchronized; anything else is named and left alone. The flagless
# `harness sync` reaches into the current repository, so its blast radius has to stop at
# directories agent-harness created itself -- installing a new one is `harness init`.
sync_scope() {
    local scope_label="$1"
    local listing="$2"
    local directories=() runtimes=()
    local directory runtime scope_mode previous_mode

    while IFS=$'\t' read -r directory runtime; do
        [ -n "${directory}" ] || continue
        surface_evaluate "${directory}"
        case "${SURFACE_STATE}" in
            absent|unmanaged)
                log_info "Skipping ${directory}: ${SURFACE_STATE}. Run 'harness init' to install a surface there."
                ;;
            *)
                # Enumerated before anything is written: a command that modifies a
                # repository must say which paths, not report a count afterwards.
                log_info "Will synchronize ${directory} (${SURFACE_STATE}, runtime ${runtime})"
                directories+=("${directory}")
                runtimes+=("${runtime}")
                ;;
        esac
    done <<< "${listing}"

    if [ ${#directories[@]} -eq 0 ]; then
        log_info "Nothing to synchronize for scope: ${scope_label}"
        return 0
    fi

    previous_mode="${SKILL_MODE}"
    if [ "${SKILL_MODE}" != "expert" ]; then
        scope_mode="$(surface_scope_mode <<< "${listing}")"
        if [ -n "${scope_mode}" ]; then
            SKILL_MODE="${scope_mode}"
            log_info "Synchronizing ${scope_label} in ${SKILL_MODE} mode, as recorded in its manifest."
        else
            log_info "Synchronizing ${scope_label} in ${SKILL_MODE} mode: no manifest records a mode."
        fi
    fi

    local index=0
    while [ "${index}" -lt ${#directories[@]} ]; do
        install_skill_surface "${directories[${index}]}" "${runtimes[${index}]}"
        log_success "Synchronized ${directories[${index}]}"
        index=$((index + 1))
    done
    SKILL_MODE="${previous_mode}"
}

# A run that could not install what it was asked to install has not succeeded. Failing
# through the ERR trap rather than a bare exit is deliberate: it rolls the transaction
# back, so the alternative to a complete surface is the previous one, never a partial one.
require_unblocked_surfaces() {
    [ "${SURFACE_BLOCKED}" -eq 0 ] && return 0
    log_error "${SURFACE_BLOCKED} published skill name(s) are occupied by paths agent-harness may not replace."
    log_error "Move or remove them and re-run; the installation has been rolled back."
    return 1
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

if [ -n "${SEED_TARGET}" ]; then
    require_skill_catalog
    seed_worktree_surfaces "${SEED_TARGET}"
elif [ "${SYNC_ONLY}" = true ] || [ -n "${SYNC_TARGET}" ]; then
    require_skill_catalog
    if [ -n "${SYNC_TARGET}" ]; then
        sync_scope "${SYNC_TARGET}" "$(surface_repo_list "${SYNC_TARGET}")"
    fi
    if [ "${SYNC_ONLY}" = true ]; then
        sync_scope "the global surfaces" "$(surface_global_list)"
    fi
elif [ -n "${TARGET_REPO}" ]; then
    install_target_repo "${TARGET_REPO}" "${RECIPE_NAME}"
elif [ "${INSTALL_GLOBAL}" = true ]; then
    install_global
elif [ "${GUIDED_MODE}" = true ]; then
    log_info "Guided Setup Mode"
    install_global
    install_target_repo "$(pwd)" "${RECIPE_NAME}"
fi

require_unblocked_surfaces
transaction_commit

log_success "Setup complete! Run 'harness doctor' to verify."
log_info "Undo this installation with './setup --rollback'."
