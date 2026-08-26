#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/config.sh
# Dynamic Configuration Parser, Profile Resolver & Heuristic Detector
# ==============================================================================

set -eo pipefail

resolve_config_file() {
    local harness_root
    harness_root="$(get_harness_root)"

    # 1. Local project-level config
    if [ -f "./harness.config.json" ]; then
        echo "$(pwd)/harness.config.json"
        return
    elif [ -f "./.harnessrc.json" ]; then
        echo "$(pwd)/.harnessrc.json"
        return
    elif [ -f "./stack.config.json" ]; then
        echo "$(pwd)/stack.config.json"
        return
    elif [ -f "./.stackrc.json" ]; then
        echo "$(pwd)/.stackrc.json"
        return
    elif [ -f "./config.json" ]; then
        echo "$(pwd)/config.json"
        return
    fi

    # 2. Global / root harness config
    if [ -f "${harness_root}/config.json" ]; then
        echo "${harness_root}/config.json"
        return
    elif [ -f "${harness_root}/config.example.json" ]; then
        echo "${harness_root}/config.example.json"
        return
    fi

    # 3. User home config
    if [ -f "${HOME}/.config/agent-harness/config.json" ]; then
        echo "${HOME}/.config/agent-harness/config.json"
        return
    fi

    echo ""
}

get_active_profile() {
    if [ -n "${STACK_PROFILE:-}" ]; then
        echo "${STACK_PROFILE}"
        return
    fi

    local config_file
    config_file="$(resolve_config_file)"

    if [ -n "${config_file}" ] && [ -f "${config_file}" ] && command -v jq >/dev/null 2>&1; then
        local current_dir
        current_dir="$(pwd)"

        # Check profiles for exact targetRepoPath match
        local matched_profile
        matched_profile=$(jq -r --arg dir "${current_dir}" '
            .profiles | to_entries[] | select(.value.targetRepoPath != null and ($dir == .value.targetRepoPath or ($dir | startswith(.value.targetRepoPath + "/")))) | .key
        ' "${config_file}" 2>/dev/null | head -n 1)

        if [ -n "${matched_profile}" ]; then
            echo "${matched_profile}"
            return
        fi

        # Check heuristics (files / directories)
        for profile in $(jq -r '.profiles | keys[]' "${config_file}" 2>/dev/null); do
            local detect_files
            detect_files=$(jq -r ".profiles[\"${profile}\"].detect.files[]? // empty" "${config_file}" 2>/dev/null)
            for f in ${detect_files}; do
                if [ -f "./${f}" ]; then
                    echo "${profile}"
                    return
                fi
            done

            local detect_dirs
            detect_dirs=$(jq -r ".profiles[\"${profile}\"].detect.directories[]? // empty" "${config_file}" 2>/dev/null)
            for d in ${detect_dirs}; do
                if [ -d "./${d}" ]; then
                    echo "${profile}"
                    return
                fi
            done
        done

        # Default profile from config if set
        local default_prof
        default_prof=$(jq -r '.project.defaultProfile // empty' "${config_file}" 2>/dev/null)
        if [ -n "${default_prof}" ]; then
            echo "${default_prof}"
            return
        fi

        # First profile in list
        local first_prof
        first_prof=$(jq -r '.profiles | keys[0] // empty' "${config_file}" 2>/dev/null)
        if [ -n "${first_prof}" ]; then
            echo "${first_prof}"
            return
        fi
    fi

    echo "default"
}

get_profile_value() {
    local key="$1"
    local default_val="${2:-}"
    local profile="${STACK_PROFILE:-$(get_active_profile)}"
    local config_file
    config_file="$(resolve_config_file)"

    if [ -z "${config_file}" ] || [ ! -f "${config_file}" ] || ! command -v jq >/dev/null 2>&1; then
        echo "${default_val}"
        return
    fi

    local val
    val=$(jq -r ".profiles[\"${profile}\"].${key} // .project.${key} // empty" "${config_file}" 2>/dev/null)
    if [ -n "${val}" ] && [ "${val}" != "null" ]; then
        echo "${val}"
    else
        echo "${default_val}"
    fi
}

get_target_repo() {
    local profile="${1:-$(get_active_profile)}"
    local config_file
    config_file="$(resolve_config_file)"

    if [ -n "${config_file}" ] && [ -f "${config_file}" ] && command -v jq >/dev/null 2>&1; then
        local configured_path
        configured_path=$(jq -r ".profiles[\"${profile}\"].targetRepoPath // empty" "${config_file}" 2>/dev/null)
        if [ -n "${configured_path}" ]; then
            # Expand ~ if present
            eval configured_path="${configured_path}"
            if [ -d "${configured_path}" ]; then
                echo "${configured_path}"
                return
            fi
        fi
    fi

    pwd
}
