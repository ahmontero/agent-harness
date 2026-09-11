#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/transaction.sh
# Reversible filesystem transactions for the installer
# ==============================================================================
#
# Every installer mutation is journaled before it happens, so a failure part-way
# through an install restores the previous filesystem state instead of leaving a
# half-installed skill surface behind.
#
# The caller must source core/scripts/lib/utils.sh first, and must run under
# `set -E` for the ERR trap to propagate into installer functions.

INSTALL_TRANSACTION_ACTIVE=false
INSTALL_TRANSACTION_DIR=""
INSTALL_TRANSACTION_SEQUENCE=0
INSTALL_TRANSACTION_PREVIOUS_ERR_TRAP=""
# Each journal holds a full backup of every file its installation replaced, and nothing
# removed one, so a long-lived machine accumulated every installation it had ever run.
# Only the newest is reachable by --rollback; the rest are history with a disk cost.
INSTALL_TRANSACTION_RETAIN=10

transaction_state_root() {
    if [ -n "${HARNESS_STATE_DIR:-}" ]; then
        printf '%s\n' "${HARNESS_STATE_DIR}"
    elif [ -n "${XDG_STATE_HOME:-}" ]; then
        printf '%s/agent-harness\n' "${XDG_STATE_HOME}"
    else
        printf '%s/.local/state/agent-harness\n' "${HOME}"
    fi
}

transaction_validate_path() {
    local path="$1"
    [ -n "${path}" ] || { log_error "Transaction path cannot be empty."; return 1; }
    case "${path}" in
        *$'\n'*) log_error "Paths containing newlines are not supported: ${path}"; return 1 ;;
    esac
}

transaction_record() {
    local path="$1"
    local operation_dir=""
    transaction_validate_path "${path}"
    [ "${INSTALL_TRANSACTION_ACTIVE}" = true ] || {
        log_error "Refusing an untracked installer mutation: ${path}"
        return 1
    }

    INSTALL_TRANSACTION_SEQUENCE=$((INSTALL_TRANSACTION_SEQUENCE + 1))
    operation_dir="${INSTALL_TRANSACTION_DIR}/operations/$(printf '%06d' "${INSTALL_TRANSACTION_SEQUENCE}")"
    mkdir -p "${operation_dir}"
    printf '%s' "${path}" > "${operation_dir}/path"

    if [ -L "${path}" ]; then
        printf '%s\n' symlink > "${operation_dir}/kind"
        readlink "${path}" > "${operation_dir}/link-target"
    elif [ -f "${path}" ]; then
        printf '%s\n' file > "${operation_dir}/kind"
        cp -p "${path}" "${operation_dir}/backup"
    elif [ -d "${path}" ]; then
        printf '%s\n' directory > "${operation_dir}/kind"
    elif [ -e "${path}" ]; then
        log_error "Unsupported filesystem object: ${path}"
        return 1
    else
        printf '%s\n' absent > "${operation_dir}/kind"
    fi
}

transaction_maybe_inject_failure() {
    local configured="${HARNESS_TEST_FAIL_AFTER:-}"
    [ "${HARNESS_ENABLE_FAILURE_INJECTION:-false}" = true ] || return 0
    [ -n "${configured}" ] || return 0
    case "${configured}" in *[!0-9]*) return 0 ;; esac
    if [ "${INSTALL_TRANSACTION_SEQUENCE}" -ge "${configured}" ]; then
        log_error "Injected installer failure after operation ${INSTALL_TRANSACTION_SEQUENCE}."
        return 97
    fi
}

transaction_ensure_directory() {
    local directory="$1"
    local cursor="${directory}"
    local missing=()
    local index=0
    [ -d "${directory}" ] && return 0
    [ ! -e "${directory}" ] || { log_error "Expected a directory but found another object: ${directory}"; return 1; }

    while [ ! -e "${cursor}" ]; do
        missing+=("${cursor}")
        cursor="$(dirname -- "${cursor}")"
    done
    [ -d "${cursor}" ] || { log_error "Cannot create directory below non-directory: ${cursor}"; return 1; }

    index=$((${#missing[@]} - 1))
    while [ "${index}" -ge 0 ]; do
        transaction_record "${missing[${index}]}"
        mkdir "${missing[${index}]}"
        transaction_maybe_inject_failure
        index=$((index - 1))
    done
}

transaction_remove_current_leaf() {
    local path="$1"
    if [ -L "${path}" ] || [ -f "${path}" ]; then
        unlink "${path}"
    elif [ -d "${path}" ]; then
        rmdir "${path}"
    elif [ -e "${path}" ]; then
        log_error "Cannot safely replace unsupported object: ${path}"
        return 1
    fi
}

transaction_symlink() {
    local source="$1"
    local destination="$2"
    transaction_ensure_directory "$(dirname -- "${destination}")"
    transaction_record "${destination}"
    transaction_remove_current_leaf "${destination}" || return 1
    ln -s "${source}" "${destination}"
    transaction_maybe_inject_failure
}

transaction_unlink() {
    local destination="$1"
    [ -L "${destination}" ] || { log_error "Refusing to unlink a non-symlink: ${destination}"; return 1; }
    transaction_record "${destination}"
    unlink "${destination}"
    transaction_maybe_inject_failure
}

transaction_copy() {
    local source="$1"
    local destination="$2"
    local temporary=""
    [ -f "${source}" ] || { log_error "Copy source is missing: ${source}"; return 1; }
    transaction_ensure_directory "$(dirname -- "${destination}")"
    transaction_record "${destination}"
    temporary="$(mktemp "${destination}.harness.XXXXXX")"
    cp -p "${source}" "${temporary}"
    transaction_remove_current_leaf "${destination}" || { rm -f "${temporary}"; return 1; }
    mv "${temporary}" "${destination}"
    transaction_maybe_inject_failure
}

transaction_write_command() {
    local destination="$1"
    local mode="$2"
    shift 2
    local temporary=""
    transaction_ensure_directory "$(dirname -- "${destination}")"
    transaction_record "${destination}"
    temporary="$(mktemp "${destination}.harness.XXXXXX")"
    "$@" > "${temporary}"
    chmod "${mode}" "${temporary}"
    transaction_remove_current_leaf "${destination}" || { rm -f "${temporary}"; return 1; }
    mv "${temporary}" "${destination}"
    transaction_maybe_inject_failure
}

# Removes a managed directory bottom-up so that every contained file, symlink,
# and directory is journaled individually and the whole tree stays restorable.
transaction_remove_tree() {
    local root="$1"
    local path=""
    transaction_validate_path "${root}" || return 1
    if [ ! -e "${root}" ] && [ ! -L "${root}" ]; then
        return 0
    fi
    if [ ! -L "${root}" ] && [ -d "${root}" ]; then
        while IFS= read -r path; do
            [ -n "${path}" ] || continue
            transaction_record "${path}" || return 1
            transaction_remove_current_leaf "${path}" || return 1
            transaction_maybe_inject_failure || return $?
        done < <(find "${root}" -depth -mindepth 1)
    fi
    transaction_record "${root}" || return 1
    transaction_remove_current_leaf "${root}" || return 1
    transaction_maybe_inject_failure
}

# Keeps the newest INSTALL_TRANSACTION_RETAIN journals. The directory names begin with a
# UTC timestamp, so a lexical sort is a chronological one. The journal the latest pointer
# names is never pruned, whatever its age: it is the one --rollback can still undo.
transaction_prune() {
    local state_root latest_target journal
    local journals=()
    local total excess index=0
    state_root="$(transaction_state_root)"
    [ -d "${state_root}/transactions" ] || return 0

    latest_target=""
    [ -f "${state_root}/latest" ] && latest_target="$(<"${state_root}/latest")"

    while IFS= read -r journal; do
        [ -n "${journal}" ] && journals+=("${journal}")
    done < <(find "${state_root}/transactions" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

    total=${#journals[@]}
    excess=$(( total - INSTALL_TRANSACTION_RETAIN ))
    [ "${excess}" -gt 0 ] || return 0

    while [ "${index}" -lt "${excess}" ]; do
        if [ "${journals[${index}]}" != "${latest_target}" ]; then
            rm -rf "${journals[${index}]}"
        fi
        index=$((index + 1))
    done
}

transaction_restore_operation() {
    local operation_dir="$1"
    local path=""
    local kind=""
    path="$(<"${operation_dir}/path")"
    kind="$(<"${operation_dir}/kind")"

    case "${kind}" in
        absent)
            transaction_remove_current_leaf "${path}" || return 1
            ;;
        symlink)
            transaction_remove_current_leaf "${path}" || return 1
            transaction_ensure_restore_parent "$(dirname -- "${path}")"
            ln -s "$(<"${operation_dir}/link-target")" "${path}"
            ;;
        file)
            transaction_remove_current_leaf "${path}" || return 1
            transaction_ensure_restore_parent "$(dirname -- "${path}")"
            cp -p "${operation_dir}/backup" "${path}"
            ;;
        directory)
            [ -d "${path}" ] || mkdir -p "${path}"
            ;;
        *)
            log_error "Unknown journal entry kind '${kind}' for ${path}."
            return 1
            ;;
    esac
}

transaction_ensure_restore_parent() {
    local directory="$1"
    [ -d "${directory}" ] || mkdir -p "${directory}"
}

transaction_rollback_dir() {
    local transaction_dir="$1"
    local reason="${2:-explicit}"
    local operation_dir=""
    local rollback_error=0
    [ -d "${transaction_dir}/operations" ] || { log_error "Invalid transaction journal: ${transaction_dir}"; return 1; }

    while IFS= read -r operation_dir; do
        [ -n "${operation_dir}" ] || continue
        transaction_restore_operation "${operation_dir}" || rollback_error=1
    done < <(find "${transaction_dir}/operations" -mindepth 1 -maxdepth 1 -type d | sort -r)

    [ "${rollback_error}" -eq 0 ] || {
        printf '%s\n' rollback-failed > "${transaction_dir}/status"
        log_error "Rollback was incomplete; journal preserved at ${transaction_dir}."
        return 1
    }
    printf '%s\n' rolled-back > "${transaction_dir}/status"
    printf '%s\n' "${reason}" > "${transaction_dir}/rollback-reason"
}

transaction_on_error() {
    local status="$1"
    local line="$2"
    trap - ERR
    if [ "${INSTALL_TRANSACTION_ACTIVE}" = true ]; then
        log_warn "Installer failed at line ${line}; restoring the previous filesystem state."
        INSTALL_TRANSACTION_ACTIVE=false
        transaction_rollback_dir "${INSTALL_TRANSACTION_DIR}" automatic || true
    fi
    exit "${status}"
}

transaction_begin() {
    local label="${1:-install}"
    local state_root=""
    local timestamp=""
    [ "${INSTALL_TRANSACTION_ACTIVE}" = false ] || { log_error "A transaction is already active."; return 1; }
    state_root="$(transaction_state_root)"
    timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
    umask 077
    mkdir -p "${state_root}/transactions"
    INSTALL_TRANSACTION_DIR="${state_root}/transactions/${timestamp}-$$"
    mkdir -p "${INSTALL_TRANSACTION_DIR}/operations"
    printf '%s\n' active > "${INSTALL_TRANSACTION_DIR}/status"
    printf '%s\n' "${label}" > "${INSTALL_TRANSACTION_DIR}/label"
    INSTALL_TRANSACTION_SEQUENCE=0
    INSTALL_TRANSACTION_ACTIVE=true
    INSTALL_TRANSACTION_PREVIOUS_ERR_TRAP="$(trap -p ERR || true)"
    trap 'transaction_on_error $? $LINENO' ERR
}

transaction_restore_previous_err_trap() {
    trap - ERR
    if [ -n "${INSTALL_TRANSACTION_PREVIOUS_ERR_TRAP}" ]; then
        eval "${INSTALL_TRANSACTION_PREVIOUS_ERR_TRAP}"
    fi
}

transaction_commit() {
    local state_root=""
    local latest_tmp=""
    [ "${INSTALL_TRANSACTION_ACTIVE}" = true ] || { log_error "No active transaction to commit."; return 1; }
    if [ "${INSTALL_TRANSACTION_SEQUENCE}" -eq 0 ]; then
        printf '%s\n' no-op > "${INSTALL_TRANSACTION_DIR}/status"
        INSTALL_TRANSACTION_ACTIVE=false
        transaction_restore_previous_err_trap
        transaction_prune
        return 0
    fi
    printf '%s\n' committed > "${INSTALL_TRANSACTION_DIR}/status"
    state_root="$(transaction_state_root)"
    latest_tmp="${state_root}/latest.$$"
    printf '%s' "${INSTALL_TRANSACTION_DIR}" > "${latest_tmp}"
    mv "${latest_tmp}" "${state_root}/latest"
    INSTALL_TRANSACTION_ACTIVE=false
    transaction_restore_previous_err_trap
    transaction_prune
}

transaction_rollback_last() {
    local state_root=""
    local latest_file=""
    local transaction_dir=""
    local status=""
    state_root="$(transaction_state_root)"
    latest_file="${state_root}/latest"
    [ -f "${latest_file}" ] || { log_error "No committed installation transaction is available to roll back."; return 1; }
    transaction_dir="$(<"${latest_file}")"
    case "${transaction_dir}" in
        "${state_root}/transactions/"*) ;;
        *) log_error "Unsafe transaction pointer: ${transaction_dir}"; return 1 ;;
    esac
    [ -d "${transaction_dir}" ] || { log_error "Transaction journal is missing: ${transaction_dir}"; return 1; }
    status="$(<"${transaction_dir}/status")"
    [ "${status}" = committed ] || { log_error "Transaction is not rollbackable (status: ${status})."; return 1; }
    transaction_rollback_dir "${transaction_dir}" explicit
    unlink "${latest_file}"
}
