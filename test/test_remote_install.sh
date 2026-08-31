#!/usr/bin/env bash

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

FIXTURE_REPOSITORY="${TEST_ROOT}/repository"
INSTALL_ROOT="${TEST_ROOT}/installed-agent-harness"
TEST_HOME="${TEST_ROOT}/home"
RUN_DIRECTORY="${TEST_ROOT}/run"

mkdir -p "${FIXTURE_REPOSITORY}" "${TEST_HOME}" "${RUN_DIRECTORY}"
tar --exclude=.git -cf - -C "${HARNESS_ROOT}" . | tar -xf - -C "${FIXTURE_REPOSITORY}"
git -C "${FIXTURE_REPOSITORY}" init -q -b main
git -C "${FIXTURE_REPOSITORY}" add .
git -C "${FIXTURE_REPOSITORY}" \
    -c user.name='Agent Harness Tests' \
    -c user.email='tests@agent-harness.invalid' \
    commit -qm 'remote installer fixture'

run_remote_install() {
    (
        cd "${RUN_DIRECTORY}"
        HOME="${TEST_HOME}" \
        AGENT_HARNESS_INSTALL_DIR="${INSTALL_ROOT}" \
        AGENT_HARNESS_REPOSITORY="${FIXTURE_REPOSITORY}" \
            bash < "${HARNESS_ROOT}/install.sh"
    )
}

run_remote_install
run_remote_install

if [ ! -x "${INSTALL_ROOT}/install.sh" ]; then
    echo "Remote bootstrap did not create a persistent installation" >&2
    exit 1
fi
if [ ! -L "${TEST_HOME}/.local/bin/harness" ]; then
    echo "Remote bootstrap did not install the global CLI link" >&2
    exit 1
fi
EXPECTED_INSTALL_ROOT="$(cd -P "${INSTALL_ROOT}" && pwd)"
if [ "$(readlink "${TEST_HOME}/.local/bin/harness")" != "${EXPECTED_INSTALL_ROOT}/bin/harness" ]; then
    echo "Global CLI link does not target the persistent installation" >&2
    exit 1
fi
if [ ! -f "${TEST_HOME}/.codex/skills/harness-implement/SKILL.md" ]; then
    echo "Remote bootstrap did not install the global skill surface" >&2
    exit 1
fi
if [ -e "${RUN_DIRECTORY}/AGENTS.md" ]; then
    echo "Zero-argument remote bootstrap unexpectedly modified the working directory" >&2
    exit 1
fi

echo "[PASS] remote stdin installation"
