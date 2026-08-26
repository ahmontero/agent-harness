#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/utils.sh
# Universal Shell Utilities, ANSI Logging & Path Resolution
# ==============================================================================

set -eo pipefail

# ANSI Colors
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
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
