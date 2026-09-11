#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/specs.sh
# Active delta spec enumeration
# ==============================================================================
#
# One definition of "active", shared by `harness spec status` and `harness context`.
# They used to answer separately -- status with -maxdepth 1 and context with a recursive
# find -- so a repository with twelve archived specs and none active was reported as
# having twelve active ones by the command whose whole purpose is to brief an agent.

set -eo pipefail

# Active means: directly in specs/, not filed under specs/archive/.
active_delta_specs() {
    local specs_dir="$1"
    [ -d "${specs_dir}" ] || return 0
    find "${specs_dir}" -maxdepth 1 -type f -name 'delta-*.md' 2>/dev/null | LC_ALL=C sort
}

active_delta_spec_count() {
    local specs_dir="$1"
    active_delta_specs "${specs_dir}" | grep -c . || true
}
