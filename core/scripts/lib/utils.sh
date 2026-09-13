#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/utils.sh
# Universal Shell Utilities, ANSI Logging & Path Resolution
# ==============================================================================

set -eo pipefail

# ANSI Colors. The full palette is part of the contract offered to sourcing
# scripts, so an entry no caller uses yet is deliberate rather than dead.
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[0;32m'
# shellcheck disable=SC2034 # part of the palette contract
BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
# shellcheck disable=SC2034 # part of the palette contract
MAGENTA=$'\033[0;35m'
RESET=$'\033[0m'

get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -L "${source}" ]; do
        local dir
        dir="$(cd -P "$(dirname "${source}")" && pwd)"
        source="$(readlink "${source}")"
        [[ ${source} != /* ]] && source="${dir}/${source}"
    done
    cd -P "$(dirname "${source}")" && pwd
}

get_harness_root() {
    local lib_dir
    lib_dir="$(get_script_dir)"
    cd -P "${lib_dir}/../../.." && pwd
}

# The repository a directory belongs to, or the directory itself when it belongs to none.
# It lives here rather than in lib/git.sh because lib/config.sh resolves paths with it and
# is sourced before lib/git.sh everywhere -- and by stack-config.sh and install.sh, which
# never source lib/git.sh at all. Two implementations would eventually disagree about where
# a repository starts, and every path the harness resolves is measured from that answer.
get_repo_root() {
    local start_dir="${1:-$(pwd)}"
    git -C "${start_dir}" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "${start_dir}"
}

get_profile_tag() {
    local prof="${STACK_PROFILE:-default}"
    printf "%s%s[%s %s]%s" "${CYAN}" "${BOLD}" "$(echo "${prof}" | tr '[:lower:]' '[:upper:]')" "$1" "${RESET}"
}

log_info() {
    printf "%s %s\n" "$(get_profile_tag INFO)" "$*"
}

log_success() {
    local prof="${STACK_PROFILE:-default}"
    printf "%s%s[%s SUCCESS]%s %s\n" "${GREEN}" "${BOLD}" "$(echo "${prof}" | tr '[:lower:]' '[:upper:]')" "${RESET}" "$*"
}

log_warn() {
    local prof="${STACK_PROFILE:-default}"
    printf "%s%s[%s WARNING]%s %s\n" "${YELLOW}" "${BOLD}" "$(echo "${prof}" | tr '[:lower:]' '[:upper:]')" "${RESET}" "$*" >&2
}

log_error() {
    local prof="${STACK_PROFILE:-default}"
    printf "%s%s[%s ERROR]%s %s\n" "${RED}" "${BOLD}" "$(echo "${prof}" | tr '[:lower:]' '[:upper:]')" "${RESET}" "$*" >&2
}

print_banner() {
    cat <<BANNER_EOF
${CYAN}${BOLD}
   ___                    __     __ __                               
  / _ | ___ _ ___  ___   / /_   / // / ___ _ ____ ___  ___  ___ ___
 / __ |/ _ \`// -_)/ _ \\ / __/  / _  / / _ \`// __// _ \\/ -_)(_-<(_-<
/_/ |_|\\_, / \\__/ /_//_/ \\__/  /_//_/  \\_,_//_/  /_//_/\\__//___//___/
      /___/                                                          
${RESET}
  ${BOLD}The Universal Engineering Harness & Quality Floor for AI Coding Agents${RESET}
  ${DIM}Enforce TDD, 6-Phase Debugging, Domain Landmines & Living Specs across all Agent Harnesses${RESET}
BANNER_EOF
}
