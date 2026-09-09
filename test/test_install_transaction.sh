#!/usr/bin/env bash
# ==============================================================================
# agent-harness: test/test_install_transaction.sh
# End-to-end suite for transactional installation and rollback
# ==============================================================================

set -Eeuo pipefail

HARNESS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-harness-install-transaction-tests.XXXXXX")"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

pass() {
    printf '  [PASS] %s\n' "$1"
}

fail() {
    printf '  [FAIL] %s\n' "$1" >&2
    exit 1
}

snapshot_tree() {
    local root="$1"
    if [ ! -d "${root}" ]; then
        printf '%s\n' '<absent>'
        return 0
    fi
    find "${root}" -mindepth 1 | sort | while IFS= read -r path; do
        if [ -L "${path}" ]; then
            printf 'link\t%s\t%s\n' "${path#"${root}"/}" "$(readlink "${path}")"
        elif [ -f "${path}" ]; then
            printf 'file\t%s\t' "${path#"${root}"/}"
            cksum < "${path}"
        elif [ -d "${path}" ]; then
            printf 'dir\t%s\n' "${path#"${root}"/}"
        fi
    done
}

journal_status() {
    local state_root="$1"
    find "${state_root}/transactions" -mindepth 2 -maxdepth 2 -name status -exec cat {} \; 2>/dev/null
}

printf '%s\n' '=== Injected mid-install failure restores the target tree ==='
failure_target="${TEST_ROOT}/failure-target"
failure_home="${TEST_ROOT}/failure-home"
failure_state="${TEST_ROOT}/failure-state"
mkdir -p "${failure_target}" "${failure_home}" "${failure_state}"
printf 'user-owned notes\n' > "${failure_target}/NOTES.md"
before_failure="$(snapshot_tree "${failure_target}")"
failure_status=0
HOME="${failure_home}" HARNESS_STATE_DIR="${failure_state}" \
    HARNESS_ENABLE_FAILURE_INJECTION=true HARNESS_TEST_FAIL_AFTER=8 \
    "${HARNESS_ROOT}/install.sh" --target "${failure_target}" >/dev/null 2>&1 \
    || failure_status=$?
[[ "${failure_status}" -eq 97 ]] || fail "injected failure returned ${failure_status}, expected 97"
[[ "$(snapshot_tree "${failure_target}")" == "${before_failure}" ]] \
    || fail 'injected partial failure did not restore the exact target tree'
[[ "$(journal_status "${failure_state}")" == rolled-back ]] \
    || fail 'automatic rollback journal was not marked rolled-back'
[[ ! -f "${failure_state}/latest" ]] || fail 'a rolled-back transaction published a rollback pointer'
pass 'an injected mid-install failure restores every prior mutation'

printf '%s\n' '=== Successful target apply and explicit rollback ==='
apply_target="${TEST_ROOT}/apply-target"
apply_home="${TEST_ROOT}/apply-home"
apply_state="${TEST_ROOT}/apply-state"
mkdir -p "${apply_target}" "${apply_home}" "${apply_state}"
before_apply="$(snapshot_tree "${apply_target}")"
HOME="${apply_home}" HARNESS_STATE_DIR="${apply_state}" \
    "${HARNESS_ROOT}/install.sh" --target "${apply_target}" >/dev/null
[[ -d "${apply_target}/.claude/skills/harness-implement" ]] || fail 'apply omitted the public skill bundles'
[[ -f "${apply_target}/AGENTS.md" ]] || fail 'apply omitted canonical context'
[[ -L "${apply_target}/CLAUDE.md" ]] || fail 'apply omitted the Claude context alias'
[[ -f "${apply_target}/rules/floor.md" ]] || fail 'apply omitted the default quality floor'
[[ "$(journal_status "${apply_state}")" == committed ]] || fail 'a successful apply was not marked committed'

HOME="${apply_home}" HARNESS_STATE_DIR="${apply_state}" "${HARNESS_ROOT}/install.sh" --rollback >/dev/null
[[ "$(snapshot_tree "${apply_target}")" == "${before_apply}" ]] \
    || fail 'explicit rollback did not restore the exact target tree'
if HOME="${apply_home}" HARNESS_STATE_DIR="${apply_state}" \
    "${HARNESS_ROOT}/install.sh" --rollback >/dev/null 2>&1; then
    fail 'a completed transaction could be rolled back twice'
fi
pass 'the last successful transaction can be rolled back exactly once'

printf '%s\n' '=== Global apply and explicit rollback ==='
global_home="${TEST_ROOT}/global-home"
global_state="${TEST_ROOT}/global-state"
mkdir -p "${global_home}" "${global_state}"
before_global="$(snapshot_tree "${global_home}")"
HOME="${global_home}" HARNESS_STATE_DIR="${global_state}" \
    "${HARNESS_ROOT}/install.sh" --global >/dev/null
[[ -d "${global_home}/.claude/skills/harness-implement" ]] || fail 'global apply omitted the public skill bundles'
[[ -L "${global_home}/.local/bin/harness" ]] || fail 'global apply omitted the CLI link'
HOME="${global_home}" HARNESS_STATE_DIR="${global_state}" "${HARNESS_ROOT}/install.sh" --rollback >/dev/null
[[ "$(snapshot_tree "${global_home}")" == "${before_global}" ]] \
    || fail 'global rollback did not restore the exact home tree'
pass 'a global installation is fully reversible'

printf '%s\n' '=== Reinstalling over a managed surface stays reversible ==='
reinstall_home="${TEST_ROOT}/reinstall-home"
reinstall_state="${TEST_ROOT}/reinstall-state"
mkdir -p "${reinstall_home}" "${reinstall_state}"
HOME="${reinstall_home}" HARNESS_STATE_DIR="${reinstall_state}" \
    "${HARNESS_ROOT}/install.sh" --global >/dev/null
after_first="$(snapshot_tree "${reinstall_home}")"
HOME="${reinstall_home}" HARNESS_STATE_DIR="${reinstall_state}" \
    "${HARNESS_ROOT}/install.sh" --global >/dev/null
[[ "$(snapshot_tree "${reinstall_home}")" == "${after_first}" ]] \
    || fail 'reinstalling over a managed surface was not idempotent'
HOME="${reinstall_home}" HARNESS_STATE_DIR="${reinstall_state}" "${HARNESS_ROOT}/install.sh" --rollback >/dev/null
[[ "$(snapshot_tree "${reinstall_home}")" == "${after_first}" ]] \
    || fail 'rolling back a reinstall did not restore the previously installed surface'
pass 'reinstallation is idempotent and its rollback restores the prior managed surface'

printf '%s\n' '=== Rollback without a prior transaction ==='
no_txn_home="${TEST_ROOT}/no-txn-home"
no_txn_state="${TEST_ROOT}/no-txn-state"
mkdir -p "${no_txn_home}" "${no_txn_state}"
no_txn_status=0
no_txn_output="$(HOME="${no_txn_home}" HARNESS_STATE_DIR="${no_txn_state}" \
    "${HARNESS_ROOT}/install.sh" --rollback 2>&1)" || no_txn_status=$?
[[ "${no_txn_status}" -ne 0 ]] || fail '--rollback succeeded with no prior transaction'
[[ "${no_txn_output}" == *'No committed installation transaction is available'* ]] \
    || fail '--rollback with no prior transaction did not report the expected error'
pass '--rollback fails closed when no transaction has been committed'

printf '%s\n' '=== Rollback rejects an unsafe transaction pointer ==='
unsafe_home="${TEST_ROOT}/unsafe-home"
unsafe_state="${TEST_ROOT}/unsafe-state"
mkdir -p "${unsafe_home}" "${unsafe_state}"
outside_marker="${TEST_ROOT}/outside-marker"
printf 'do not touch\n' > "${outside_marker}"
printf '%s' "${outside_marker}" > "${unsafe_state}/latest"
unsafe_status=0
unsafe_output="$(HOME="${unsafe_home}" HARNESS_STATE_DIR="${unsafe_state}" \
    "${HARNESS_ROOT}/install.sh" --rollback 2>&1)" || unsafe_status=$?
[[ "${unsafe_status}" -ne 0 ]] || fail '--rollback accepted a pointer outside its own journal root'
[[ "${unsafe_output}" == *'Unsafe transaction pointer'* ]] \
    || fail '--rollback did not reject the unsafe pointer with the expected message'
[[ "$(<"${outside_marker}")" == 'do not touch' ]] || fail 'unsafe pointer rollback touched an unrelated file'
pass '--rollback refuses a transaction pointer outside its own state directory'

printf '%s\n' '=== Corrupted journal entry preserves the transaction ==='
corrupt_home="${TEST_ROOT}/corrupt-home"
corrupt_state="${TEST_ROOT}/corrupt-state"
mkdir -p "${corrupt_home}" "${corrupt_state}"
HOME="${corrupt_home}" HARNESS_STATE_DIR="${corrupt_state}" \
    "${HARNESS_ROOT}/install.sh" --global >/dev/null
corrupt_transaction_dir="$(<"${corrupt_state}/latest")"
corrupt_operation="$(find "${corrupt_transaction_dir}/operations" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
printf '%s\n' bogus > "${corrupt_operation}/kind"
corrupt_status=0
HOME="${corrupt_home}" HARNESS_STATE_DIR="${corrupt_state}" \
    "${HARNESS_ROOT}/install.sh" --rollback >/dev/null 2>&1 || corrupt_status=$?
[[ "${corrupt_status}" -ne 0 ]] || fail 'rollback over a corrupted journal entry reported success'
[[ "$(<"${corrupt_transaction_dir}/status")" == rollback-failed ]] \
    || fail 'a failed restore did not mark the journal rollback-failed'
[[ -f "${corrupt_state}/latest" ]] || fail 'a failed rollback discarded the pointer to its own journal'
pass 'a corrupted journal entry fails closed and preserves the transaction for inspection'

printf '%s\n' '=== Rollback cannot be combined with installation options ==='
combined_home="${TEST_ROOT}/combined-home"
combined_state="${TEST_ROOT}/combined-state"
combined_target="${TEST_ROOT}/combined-target"
mkdir -p "${combined_home}" "${combined_state}" "${combined_target}"
combined_status=0
combined_output="$(HOME="${combined_home}" HARNESS_STATE_DIR="${combined_state}" \
    "${HARNESS_ROOT}/install.sh" --rollback --target "${combined_target}" 2>&1)" || combined_status=$?
[[ "${combined_status}" -ne 0 ]] || fail '--rollback was accepted alongside --target'
[[ "${combined_output}" == *'cannot be combined'* ]] \
    || fail 'combining --rollback with an installation option did not report the expected error'
[[ "$(snapshot_tree "${combined_target}")" == '<absent>' || -z "$(snapshot_tree "${combined_target}")" ]] \
    || fail 'a rejected --rollback invocation still mutated the target'
for combined_option in --global --cli-only --sync-only --guided --expert; do
    combined_status=0
    HOME="${combined_home}" HARNESS_STATE_DIR="${combined_state}" \
        "${HARNESS_ROOT}/install.sh" --rollback "${combined_option}" >/dev/null 2>&1 || combined_status=$?
    [[ "${combined_status}" -ne 0 ]] || fail "--rollback was accepted alongside ${combined_option}"
done
pass '--rollback refuses to run alongside installation options'

printf '%s\n' '=== Read-only verification opens no transaction ==='
verify_home="${TEST_ROOT}/verify-home"
verify_state="${TEST_ROOT}/verify-state"
mkdir -p "${verify_home}" "${verify_state}"
HOME="${verify_home}" HARNESS_STATE_DIR="${verify_state}" "${HARNESS_ROOT}/install.sh" --verify >/dev/null
[[ ! -d "${verify_state}/transactions" ]] || fail '--verify opened an installation transaction'
[[ "$(snapshot_tree "${verify_home}")" == '<absent>' || -z "$(snapshot_tree "${verify_home}")" ]] \
    || fail '--verify mutated the home directory'
pass '--verify performs no mutation and opens no transaction'

printf '%s\n' 'All transactional installer tests passed.'
