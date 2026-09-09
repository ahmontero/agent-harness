#!/usr/bin/env bash
# ==============================================================================
# agent-harness: test/test_transaction_lib.sh
# Unit suite for the reversible installer transaction library
# ==============================================================================

set -Eeuo pipefail

HARNESS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-harness-transaction-lib-tests.XXXXXX")"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

pass() {
    printf '  [PASS] %s\n' "$1"
}

fail() {
    printf '  [FAIL] %s\n' "$1" >&2
    exit 1
}

new_state_root() {
    local root="${TEST_ROOT}/state-$1"
    mkdir -p "${root}"
    printf '%s' "${root}"
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

# shellcheck source=core/scripts/lib/utils.sh
source "${HARNESS_ROOT}/core/scripts/lib/utils.sh"
# shellcheck source=core/scripts/lib/transaction.sh
source "${HARNESS_ROOT}/core/scripts/lib/transaction.sh"

printf '%s\n' '=== transaction_state_root resolves HARNESS_STATE_DIR > XDG_STATE_HOME > HOME ==='
home_dir="${TEST_ROOT}/home"
mkdir -p "${home_dir}"
[[ "$(HARNESS_STATE_DIR='' XDG_STATE_HOME='' HOME="${home_dir}" transaction_state_root)" \
    == "${home_dir}/.local/state/agent-harness" ]] \
    || fail 'HOME fallback produced an unexpected state root'
[[ "$(HARNESS_STATE_DIR='' XDG_STATE_HOME="${TEST_ROOT}/xdg" HOME="${home_dir}" transaction_state_root)" \
    == "${TEST_ROOT}/xdg/agent-harness" ]] \
    || fail 'XDG_STATE_HOME was not honored over the HOME fallback'
[[ "$(HARNESS_STATE_DIR="${TEST_ROOT}/explicit" XDG_STATE_HOME="${TEST_ROOT}/xdg" HOME="${home_dir}" transaction_state_root)" \
    == "${TEST_ROOT}/explicit" ]] \
    || fail 'HARNESS_STATE_DIR did not take priority over XDG_STATE_HOME'
pass 'transaction_state_root resolves HARNESS_STATE_DIR > XDG_STATE_HOME > HOME in order'

printf '%s\n' '=== transaction_validate_path rejects empty and newline-bearing paths ==='
validate_output=""
if validate_output="$(transaction_validate_path '' 2>&1)"; then
    fail 'transaction_validate_path accepted an empty path'
fi
[[ "${validate_output}" == *'cannot be empty'* ]] || fail 'unexpected message for an empty path'
if validate_output="$(transaction_validate_path "$(printf 'a\nb')" 2>&1)"; then
    fail 'transaction_validate_path accepted a path containing a newline'
fi
[[ "${validate_output}" == *'newlines are not supported'* ]] || fail 'unexpected message for a newline-bearing path'
transaction_validate_path "${TEST_ROOT}/ordinary/path" || fail 'transaction_validate_path rejected an ordinary path'
pass 'transaction_validate_path enforces non-empty, single-line paths'

printf '%s\n' '=== transaction_record refuses a mutation with no active transaction ==='
[ "${INSTALL_TRANSACTION_ACTIVE}" = false ] || fail 'test invariant violated: a transaction was already active'
record_output=""
if record_output="$(transaction_record "${TEST_ROOT}/untracked" 2>&1)"; then
    fail 'transaction_record accepted a mutation outside an active transaction'
fi
[[ "${record_output}" == *'Refusing an untracked installer mutation'* ]] \
    || fail 'unexpected message for an untracked mutation'
pass 'transaction_record refuses to record a mutation without an active transaction'

printf '%s\n' '=== transaction_ensure_directory fails closed on non-directory path components ==='
HARNESS_STATE_DIR="$(new_state_root ensure-dir)"
export HARNESS_STATE_DIR
transaction_begin lib-test
blocked="${TEST_ROOT}/blocked-file"
printf 'not a directory\n' > "${blocked}"
ensure_output=""
if ensure_output="$(transaction_ensure_directory "${blocked}" 2>&1)"; then
    fail 'transaction_ensure_directory accepted a path that is itself a file'
fi
[[ "${ensure_output}" == *'found another object'* ]] || fail 'unexpected message for a blocked leaf path'
if ensure_output="$(transaction_ensure_directory "${blocked}/child" 2>&1)"; then
    fail 'transaction_ensure_directory created a directory below an existing file'
fi
[[ "${ensure_output}" == *'below non-directory'* ]] || fail 'unexpected message for a blocked ancestor path'
[[ "${INSTALL_TRANSACTION_SEQUENCE}" -eq 0 ]] || fail 'a rejected ensure_directory call still recorded an operation'
transaction_commit
[[ "${INSTALL_TRANSACTION_ACTIVE}" = false ]] || fail 'commit left the transaction marked active'
[[ ! -f "${HARNESS_STATE_DIR}/latest" ]] || fail 'a zero-operation transaction still published a rollback pointer'
pass 'transaction_ensure_directory fails closed and an empty transaction commits as a no-op'

printf '%s\n' '=== transaction_record classifies every kind of preexisting filesystem object ==='
HARNESS_STATE_DIR="$(new_state_root record-kinds)"
export HARNESS_STATE_DIR
transaction_begin lib-test

existing_symlink="${TEST_ROOT}/kind-target/existing-link"
mkdir -p "$(dirname -- "${existing_symlink}")"
ln -s /etc/hosts "${existing_symlink}"
transaction_record "${existing_symlink}"
op_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
[[ "$(<"${op_dir}/kind")" == symlink ]] || fail 'transaction_record misclassified an existing symlink'
[[ "$(<"${op_dir}/link-target")" == /etc/hosts ]] || fail 'transaction_record captured the wrong symlink target'

existing_file="${TEST_ROOT}/kind-target/existing-file"
printf 'original contents\n' > "${existing_file}"
transaction_record "${existing_file}"
op_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
[[ "$(<"${op_dir}/kind")" == file ]] || fail 'transaction_record misclassified an existing file'
[[ "$(<"${op_dir}/backup")" == 'original contents' ]] \
    || fail 'transaction_record did not back up the existing file content'

existing_dir="${TEST_ROOT}/kind-target/existing-dir"
mkdir -p "${existing_dir}"
transaction_record "${existing_dir}"
op_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
[[ "$(<"${op_dir}/kind")" == directory ]] || fail 'transaction_record misclassified an existing directory'

absent_path="${TEST_ROOT}/kind-target/absent-entry"
transaction_record "${absent_path}"
op_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
[[ "$(<"${op_dir}/kind")" == absent ]] || fail 'transaction_record misclassified a path that does not exist'

if command -v mkfifo >/dev/null 2>&1; then
    existing_fifo="${TEST_ROOT}/kind-target/existing-fifo"
    mkfifo "${existing_fifo}"
    fifo_output=""
    if fifo_output="$(transaction_record "${existing_fifo}" 2>&1)"; then
        fail 'transaction_record accepted an unsupported filesystem object'
    fi
    [[ "${fifo_output}" == *'Unsupported filesystem object'* ]] \
        || fail 'unexpected message for an unsupported object'
fi

transaction_commit
pass 'transaction_record classifies symlink, file, directory, absent, and unsupported entries correctly'

printf '%s\n' '=== transaction_unlink only ever removes a symlink ==='
HARNESS_STATE_DIR="$(new_state_root unlink)"
export HARNESS_STATE_DIR
transaction_begin lib-test
not_a_symlink="${TEST_ROOT}/unlink-target/plain-file"
mkdir -p "$(dirname -- "${not_a_symlink}")"
printf 'plain file\n' > "${not_a_symlink}"
unlink_output=""
if unlink_output="$(transaction_unlink "${not_a_symlink}" 2>&1)"; then
    fail 'transaction_unlink removed a non-symlink'
fi
[[ "${unlink_output}" == *'Refusing to unlink a non-symlink'* ]] \
    || fail 'unexpected message for a non-symlink target'
[[ -f "${not_a_symlink}" ]] || fail 'transaction_unlink deleted a file it should have refused to touch'

real_symlink="${TEST_ROOT}/unlink-target/real-link"
ln -s "${not_a_symlink}" "${real_symlink}"
transaction_unlink "${real_symlink}"
[[ ! -e "${real_symlink}" ]] || fail 'transaction_unlink did not remove a genuine symlink'
transaction_commit
pass 'transaction_unlink refuses non-symlinks and removes genuine ones'

printf '%s\n' '=== transaction_copy refuses a missing source ==='
HARNESS_STATE_DIR="$(new_state_root copy)"
export HARNESS_STATE_DIR
transaction_begin lib-test
copy_output=""
if copy_output="$(transaction_copy "${TEST_ROOT}/does-not-exist" "${TEST_ROOT}/copy-target/dest" 2>&1)"; then
    fail 'transaction_copy accepted a missing source file'
fi
[[ "${copy_output}" == *'Copy source is missing'* ]] || fail 'unexpected message for a missing copy source'
transaction_commit
pass 'transaction_copy fails closed when its source file is missing'

printf '%s\n' '=== transaction_write_command journals generated file content ==='
HARNESS_STATE_DIR="$(new_state_root write-command)"
export HARNESS_STATE_DIR
transaction_begin lib-test
generated="${TEST_ROOT}/write-target/marker"
transaction_write_command "${generated}" 644 printf '%s\n' 'generated marker'
[[ "$(<"${generated}")" == 'generated marker' ]] || fail 'transaction_write_command wrote unexpected content'
journal_write_dir="${INSTALL_TRANSACTION_DIR}"
transaction_commit
transaction_rollback_dir "${journal_write_dir}" manual-test
[[ ! -e "${generated}" ]] || fail 'rolling back transaction_write_command left the generated file behind'
pass 'transaction_write_command is journaled and reversible'

printf '%s\n' '=== transaction_remove_tree journals a managed directory bottom-up ==='
HARNESS_STATE_DIR="$(new_state_root remove-tree)"
export HARNESS_STATE_DIR
managed_root="${TEST_ROOT}/remove-tree-target"
mkdir -p "${managed_root}/bundle/references"
printf 'skill body\n' > "${managed_root}/bundle/SKILL.md"
printf 'marker\n' > "${managed_root}/bundle/.managed"
printf 'primitive body\n' > "${managed_root}/bundle/references/tdd.md"
ln -s "${managed_root}/bundle/SKILL.md" "${managed_root}/bundle/references/alias.md"
before_remove_tree="$(snapshot_tree "${managed_root}")"
transaction_begin lib-test
transaction_remove_tree "${managed_root}/bundle"
[[ ! -e "${managed_root}/bundle" ]] || fail 'transaction_remove_tree did not remove the managed directory'
journal_remove_dir="${INSTALL_TRANSACTION_DIR}"
transaction_commit
transaction_rollback_dir "${journal_remove_dir}" manual-test
[[ "$(snapshot_tree "${managed_root}")" == "${before_remove_tree}" ]] \
    || fail 'rolling back transaction_remove_tree did not restore the exact tree'
pass 'transaction_remove_tree removes a managed tree and rollback restores it exactly'

printf '%s\n' '=== transaction_remove_tree tolerates an absent path and refuses unsupported objects ==='
HARNESS_STATE_DIR="$(new_state_root remove-tree-edge)"
export HARNESS_STATE_DIR
transaction_begin lib-test
transaction_remove_tree "${TEST_ROOT}/remove-tree-edge/never-existed" \
    || fail 'transaction_remove_tree failed on an absent path'
[[ "${INSTALL_TRANSACTION_SEQUENCE}" -eq 0 ]] || fail 'an absent path still recorded an operation'
if command -v mkfifo >/dev/null 2>&1; then
    edge_fifo="${TEST_ROOT}/remove-tree-edge/fifo"
    mkdir -p "$(dirname -- "${edge_fifo}")"
    mkfifo "${edge_fifo}"
    remove_tree_output=""
    if remove_tree_output="$(transaction_remove_tree "${edge_fifo}" 2>&1)"; then
        fail 'transaction_remove_tree accepted an unsupported filesystem object'
    fi
    [[ "${remove_tree_output}" == *'Unsupported filesystem object'* ]] \
        || fail 'unexpected message for an unsupported remove_tree target'
    [[ -p "${edge_fifo}" ]] || fail 'transaction_remove_tree destroyed an object it should have refused'
fi
transaction_commit
pass 'transaction_remove_tree is a no-op on absent paths and fails closed on unsupported objects'

printf '%s\n' '=== transaction_restore_operation replays symlink, file, and directory journal entries ==='
HARNESS_STATE_DIR="$(new_state_root restore)"
export HARNESS_STATE_DIR
transaction_begin lib-test

restore_symlink="${TEST_ROOT}/restore-target/link"
mkdir -p "$(dirname -- "${restore_symlink}")"
ln -s /etc/hosts "${restore_symlink}"
transaction_record "${restore_symlink}"
symlink_op_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
rm -f "${restore_symlink}"
transaction_restore_operation "${symlink_op_dir}"
[[ "$(readlink "${restore_symlink}")" == /etc/hosts ]] \
    || fail 'restoring a symlink journal entry did not recreate the original link'

restore_file="${TEST_ROOT}/restore-target/file"
printf 'restore me\n' > "${restore_file}"
transaction_record "${restore_file}"
file_op_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
printf 'overwritten\n' > "${restore_file}"
transaction_restore_operation "${file_op_dir}"
[[ "$(<"${restore_file}")" == 'restore me' ]] \
    || fail 'restoring a file journal entry did not recover the original content'

restore_dir="${TEST_ROOT}/restore-target/dir"
mkdir -p "${restore_dir}"
transaction_record "${restore_dir}"
dir_op_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
rmdir "${restore_dir}"
transaction_restore_operation "${dir_op_dir}"
[[ -d "${restore_dir}" ]] || fail 'restoring a directory journal entry did not recreate the directory'

bogus_op_dir="${TEST_ROOT}/restore-target/bogus-op"
mkdir -p "${bogus_op_dir}"
printf '%s' "${TEST_ROOT}/restore-target/whatever" > "${bogus_op_dir}/path"
printf '%s\n' 'not-a-real-kind' > "${bogus_op_dir}/kind"
restore_output=""
if restore_output="$(transaction_restore_operation "${bogus_op_dir}" 2>&1)"; then
    fail 'transaction_restore_operation accepted an unknown journal entry kind'
fi
[[ "${restore_output}" == *'Unknown journal entry kind'* ]] \
    || fail 'unexpected message for an unknown journal entry kind'

transaction_commit
pass 'transaction_restore_operation replays every recorded kind and rejects unknown ones'

printf '%s\n' '=== restore and replace fail closed instead of writing through a stale path ==='
HARNESS_STATE_DIR="$(new_state_root write-through)"
export HARNESS_STATE_DIR
transaction_begin lib-test
write_through_root="${TEST_ROOT}/write-through-target"
mkdir -p "${write_through_root}"

# A journal entry whose path can no longer be removed must not be restored by
# writing *through* whatever now occupies that path.
stale_symlink="${write_through_root}/stale-link"
ln -s /etc/hosts "${stale_symlink}"
transaction_record "${stale_symlink}"
stale_symlink_op="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
rm -f "${stale_symlink}"
mkdir -p "${stale_symlink}"
printf 'user data\n' > "${stale_symlink}/keep"
restore_symlink_status=0
transaction_restore_operation "${stale_symlink_op}" >/dev/null 2>&1 || restore_symlink_status=$?
[[ "${restore_symlink_status}" -ne 0 ]] \
    || fail 'restoring a symlink over an unremovable path reported success'
[[ ! -e "${stale_symlink}/hosts" ]] \
    || fail 'restoring a symlink wrote through the stale path into an unrelated directory'
[[ "$(<"${stale_symlink}/keep")" == 'user data' ]] || fail 'a failed symlink restore damaged unrelated data'

stale_file="${write_through_root}/stale-file"
printf 'original\n' > "${stale_file}"
transaction_record "${stale_file}"
stale_file_op="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
rm -f "${stale_file}"
mkdir -p "${stale_file}"
printf 'user data\n' > "${stale_file}/keep"
restore_file_status=0
transaction_restore_operation "${stale_file_op}" >/dev/null 2>&1 || restore_file_status=$?
[[ "${restore_file_status}" -ne 0 ]] || fail 'restoring a file over an unremovable path reported success'
[[ ! -e "${stale_file}/backup" ]] \
    || fail 'restoring a file wrote through the stale path into an unrelated directory'

# The same rule applies to the forward direction: a destination that cannot be
# replaced must abort the mutation rather than write inside it.
occupied="${write_through_root}/occupied"
mkdir -p "${occupied}"
printf 'user data\n' > "${occupied}/keep"
symlink_status=0
transaction_symlink /etc/hosts "${occupied}" >/dev/null 2>&1 || symlink_status=$?
[[ "${symlink_status}" -ne 0 ]] || fail 'transaction_symlink reported success over an unremovable destination'
[[ ! -e "${occupied}/hosts" ]] || fail 'transaction_symlink wrote through an unremovable destination'
copy_status=0
transaction_copy "${stale_file_op}/backup" "${occupied}" >/dev/null 2>&1 || copy_status=$?
[[ "${copy_status}" -ne 0 ]] || fail 'transaction_copy reported success over an unremovable destination'
[[ ! -e "${occupied}/backup" ]] || fail 'transaction_copy wrote through an unremovable destination'
write_status=0
transaction_write_command "${occupied}" 644 printf '%s\n' generated >/dev/null 2>&1 || write_status=$?
[[ "${write_status}" -ne 0 ]] || fail 'transaction_write_command reported success over an unremovable destination'
transaction_commit
pass 'restore and replace fail closed instead of writing through a stale path'

printf '%s\n' '=== transaction_rollback_dir restores operations in reverse order ==='
HARNESS_STATE_DIR="$(new_state_root reverse-order)"
export HARNESS_STATE_DIR
order_root="${TEST_ROOT}/reverse-order-target"
mkdir -p "${order_root}"
before_order="$(snapshot_tree "${order_root}")"
transaction_begin lib-test
transaction_ensure_directory "${order_root}/nested/deeper"
transaction_write_command "${order_root}/nested/deeper/file" 644 printf '%s\n' 'created'
transaction_symlink "${order_root}/nested/deeper/file" "${order_root}/nested/alias"
journal_order_dir="${INSTALL_TRANSACTION_DIR}"
transaction_commit
transaction_rollback_dir "${journal_order_dir}" manual-test
[[ "$(snapshot_tree "${order_root}")" == "${before_order}" ]] \
    || fail 'reverse-order rollback did not restore the exact tree'
[[ "$(<"${journal_order_dir}/status")" == rolled-back ]] || fail 'a successful rollback was not marked rolled-back'
[[ "$(<"${journal_order_dir}/rollback-reason")" == manual-test ]] || fail 'the rollback reason was not recorded'
pass 'transaction_rollback_dir restores nested creations in reverse order'

printf '%s\n' '=== transaction_rollback_dir fails closed and preserves a journal it cannot fully restore ==='
HARNESS_STATE_DIR="$(new_state_root rollback-failed)"
export HARNESS_STATE_DIR
transaction_begin lib-test
broken_path="${TEST_ROOT}/rollback-failed-target/entry"
mkdir -p "$(dirname -- "${broken_path}")"
transaction_record "${broken_path}"
broken_op_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
printf '%s\n' 'bogus-kind' > "${broken_op_dir}/kind"
journal_dir="${INSTALL_TRANSACTION_DIR}"
transaction_commit
rollback_status=0
transaction_rollback_dir "${journal_dir}" manual-test || rollback_status=$?
[[ "${rollback_status}" -ne 0 ]] || fail 'transaction_rollback_dir reported success over a corrupted journal entry'
[[ "$(<"${journal_dir}/status")" == rollback-failed ]] \
    || fail 'a failed rollback did not mark the journal rollback-failed'
[[ -d "${journal_dir}/operations" ]] \
    || fail 'a failed rollback discarded the journal instead of preserving it'
pass 'transaction_rollback_dir fails closed and preserves a journal it could not fully restore'

printf '%s\n' '=== transaction_rollback_last refuses an unsafe journal pointer ==='
HARNESS_STATE_DIR="$(new_state_root unsafe-pointer)"
export HARNESS_STATE_DIR
outside_marker="${TEST_ROOT}/unsafe-outside-marker"
printf 'do not touch\n' > "${outside_marker}"
printf '%s' "${outside_marker}" > "${HARNESS_STATE_DIR}/latest"
unsafe_output=""
if unsafe_output="$(transaction_rollback_last 2>&1)"; then
    fail 'transaction_rollback_last accepted a pointer outside its own journal root'
fi
[[ "${unsafe_output}" == *'Unsafe transaction pointer'* ]] \
    || fail 'unexpected message for an unsafe transaction pointer'
[[ "$(<"${outside_marker}")" == 'do not touch' ]] || fail 'an unsafe pointer rollback touched an unrelated file'
pass 'transaction_rollback_last refuses a journal pointer outside its own state directory'

printf '%s\n' '=== transaction_rollback_last fails closed with no committed transaction ==='
HARNESS_STATE_DIR="$(new_state_root no-transaction)"
export HARNESS_STATE_DIR
missing_output=""
if missing_output="$(transaction_rollback_last 2>&1)"; then
    fail 'transaction_rollback_last succeeded with no committed transaction'
fi
[[ "${missing_output}" == *'No committed installation transaction is available'* ]] \
    || fail 'unexpected message for a missing transaction pointer'
pass 'transaction_rollback_last fails closed when nothing has been committed'

printf '%s\n' '=== transaction_begin and transaction_commit preserve a preexisting ERR trap ==='
HARNESS_STATE_DIR="$(new_state_root err-trap)"
export HARNESS_STATE_DIR
outer_trap_marker="${TEST_ROOT}/outer-trap-fired"
# shellcheck disable=SC2064 # intentional: bake in the marker path now, not at signal time
trap "printf 'fired' > '${outer_trap_marker}'" ERR
transaction_begin lib-test
[[ "$(trap -p ERR)" == *'transaction_on_error'* ]] || fail 'transaction_begin did not install its own ERR trap'
transaction_record "${TEST_ROOT}/err-trap-target/entry"
transaction_commit
[[ "${INSTALL_TRANSACTION_SEQUENCE}" -gt 0 ]] \
    || fail 'test invariant violated: commit took the no-op path, not the committed path'
[[ "$(trap -p ERR)" == *"${outer_trap_marker}"* ]] \
    || fail "transaction_commit did not restore the caller's previous ERR trap after a real commit"
trap - ERR
pass "transaction_begin and transaction_commit save and restore the caller's ERR trap"

printf '%s\n' '=== transaction_begin refuses a second transaction while one is active ==='
HARNESS_STATE_DIR="$(new_state_root double-begin)"
export HARNESS_STATE_DIR
transaction_begin lib-test
begin_output=""
if begin_output="$(transaction_begin lib-test-again 2>&1)"; then
    fail 'transaction_begin allowed a second transaction to start while one was active'
fi
[[ "${begin_output}" == *'A transaction is already active'* ]] || fail 'unexpected message for a nested transaction_begin'
transaction_commit
pass 'transaction_begin refuses to start a second transaction while one is already active'

printf '%s\n' 'All transaction.sh unit tests passed.'
