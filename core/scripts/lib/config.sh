#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/config.sh
# Dynamic Configuration Parser, Profile Resolver & Heuristic Detector
# ==============================================================================

set -eo pipefail

# The resolution order stops at files a user wrote. config.example.json is documentation
# and is deliberately absent from it: while it was a fallback, every repository with no
# configuration of its own silently adopted the example's "backend" profile, its
# pytest/ruff/mypy commands, and its targetRepoPath of ~/projects/backend-api. An
# unconfigured repository must resolve to the built-in defaults, which are the same on
# every machine, rather than to a profile nobody in the project has ever seen.
resolve_config_file() {
    local harness_root candidate
    harness_root="$(get_harness_root)"

    for candidate in \
        "$(pwd)/harness.config.json" \
        "$(pwd)/.harnessrc.json" \
        "$(pwd)/stack.config.json" \
        "$(pwd)/.stackrc.json" \
        "$(pwd)/config.json" \
        "${harness_root}/config.json" \
        "${HOME}/.config/agent-harness/config.json"
    do
        if [ -f "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return
        fi
    done

    printf '%s\n' ""
}

# Expands a leading ~ without evaluating the value. A configuration file is data; passing
# it to eval let any project's configuration execute commands as whoever ran the harness.
# shellcheck disable=SC2088 # the tilde in the patterns below is matched literally, not expanded
expand_config_path() {
    local raw="$1"
    case "${raw}" in
        "~") printf '%s\n' "${HOME}" ;;
        "~/"*) printf '%s\n' "${HOME}/${raw#\~/}" ;;
        *) printf '%s\n' "${raw}" ;;
    esac
}

# Prints "<profile>\t<how it was resolved>". get_active_profile is a thin wrapper so the
# resolution order has exactly one implementation, and `harness config validate` and
# `harness doctor` report the same answer the rest of the CLI acts on.
get_active_profile_with_reason() {
    if [ -n "${STACK_PROFILE:-}" ]; then
        printf '%s\t%s\n' "${STACK_PROFILE}" "${STACK_PROFILE_REASON:-the STACK_PROFILE environment variable}"
        return
    fi

    local config_file
    config_file="$(resolve_config_file)"

    if [ -n "${config_file}" ] && [ -f "${config_file}" ] && command -v jq >/dev/null 2>&1; then
        local current_dir matched_profile
        current_dir="$(pwd)"

        matched_profile=$(jq -r --arg dir "${current_dir}" '
            .profiles | to_entries[] | select(.value.targetRepoPath != null and ($dir == .value.targetRepoPath or ($dir | startswith(.value.targetRepoPath + "/")))) | .key
        ' "${config_file}" 2>/dev/null | head -n 1)
        if [ -n "${matched_profile}" ]; then
            printf '%s\t%s\n' "${matched_profile}" "a targetRepoPath matching the current directory"
            return
        fi

        local profile detect_files detect_dirs f d
        for profile in $(jq -r '.profiles | keys[]' "${config_file}" 2>/dev/null); do
            detect_files=$(jq -r --arg p "${profile}" '.profiles[$p].detect.files[]? // empty' "${config_file}" 2>/dev/null)
            for f in ${detect_files}; do
                if [ -f "./${f}" ]; then
                    printf '%s\t%s\n' "${profile}" "the detect.files heuristic (./${f})"
                    return
                fi
            done

            detect_dirs=$(jq -r --arg p "${profile}" '.profiles[$p].detect.directories[]? // empty' "${config_file}" 2>/dev/null)
            for d in ${detect_dirs}; do
                if [ -d "./${d}" ]; then
                    printf '%s\t%s\n' "${profile}" "the detect.directories heuristic (./${d})"
                    return
                fi
            done
        done

        local default_prof first_prof
        default_prof=$(jq -r '.project.defaultProfile // empty' "${config_file}" 2>/dev/null)
        if [ -n "${default_prof}" ]; then
            printf '%s\t%s\n' "${default_prof}" "project.defaultProfile"
            return
        fi

        first_prof=$(jq -r '.profiles | keys[0] // empty' "${config_file}" 2>/dev/null)
        if [ -n "${first_prof}" ]; then
            printf '%s\t%s\n' "${first_prof}" "the first profile in the configuration"
            return
        fi
    fi

    printf '%s\t%s\n' "default" "the built-in defaults: no configuration file was resolved"
}

get_active_profile() {
    get_active_profile_with_reason | cut -f1
}

# Returns the first configured value for a dotted key, searching the active profile and
# then .project. "Configured" means present, not truthy: jq's // operator treats false as
# empty, so every boolean set to false used to be replaced by the caller's default and
# nothing could be switched off by configuration.
get_profile_value() {
    local key="$1"
    local default_val="${2:-}"
    local profile="${STACK_PROFILE:-$(get_active_profile)}"
    local config_file
    config_file="$(resolve_config_file)"

    if [ -z "${config_file}" ] || [ ! -f "${config_file}" ] || ! command -v jq >/dev/null 2>&1; then
        printf '%s\n' "${default_val}"
        return
    fi

    local val
    val=$(jq -r --arg prof "${profile}" --arg key "${key}" '
        ($key | split(".")) as $path
        | [ .profiles[$prof]?, .project? ]
        | map(if type == "object" then (try getpath($path) catch null) else null end)
        | map(select(. != null))
        | if length == 0 then ""
          else (.[0] | if type == "string" then . else tostring end)
          end
    ' "${config_file}" 2>/dev/null)

    if [ -n "${val}" ]; then
        printf '%s\n' "${val}"
    else
        printf '%s\n' "${default_val}"
    fi
}

get_target_repo() {
    local profile="${1:-$(get_active_profile)}"
    local config_file
    config_file="$(resolve_config_file)"

    if [ -n "${config_file}" ] && [ -f "${config_file}" ] && command -v jq >/dev/null 2>&1; then
        local configured_path
        configured_path=$(jq -r --arg p "${profile}" '.profiles[$p].targetRepoPath // empty' "${config_file}" 2>/dev/null)
        if [ -n "${configured_path}" ]; then
            configured_path="$(expand_config_path "${configured_path}")"
            if [ -d "${configured_path}" ]; then
                printf '%s\n' "${configured_path}"
                return
            fi
        fi
    fi

    pwd
}
