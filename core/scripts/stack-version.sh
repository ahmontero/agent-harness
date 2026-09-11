#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-version.sh
# Reports the installed version and the checkout it is running from
# ==============================================================================
#
# The whole drift model turns on which version is installed: every surface manifest records
# one, and `harness sync` compares against it. There was no way to ask, so the number could
# only be deduced by finding the checkout and reading its package.json -- and finding the
# checkout is the other half of the question, because a CLI symlink can point anywhere.
#
# The revision is reported too. A released version and a working checkout sitting on the
# same version number are not the same thing, and only one of them is reproducible.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

usage() {
    cat <<USAGE_EOF
Usage:
  harness version
USAGE_EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown version option: $1"; usage; exit 1 ;;
    esac
done

HARNESS_ROOT="$(get_harness_root)"
MANIFEST="${HARNESS_ROOT}/package.json"

if [ ! -f "${MANIFEST}" ]; then
    log_error "Cannot determine the version: ${MANIFEST} is missing."
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    log_error "Cannot determine the version: jq is not available to read ${MANIFEST}."
    exit 1
fi

VERSION="$(jq -r '.version // empty' "${MANIFEST}")"
if [ -z "${VERSION}" ]; then
    log_error "Cannot determine the version: ${MANIFEST} declares none."
    exit 1
fi

printf 'agent-harness %s\n' "${VERSION}"
printf 'checkout: %s\n' "${HARNESS_ROOT}"

if git -C "${HARNESS_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REVISION="$(git -C "${HARNESS_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    if [ -n "$(git -C "${HARNESS_ROOT}" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        REVISION="${REVISION} (modified)"
    fi
    printf 'revision: %s\n' "${REVISION}"
else
    printf 'revision: not a Git checkout\n'
fi
