#!/usr/bin/env bash

set -u
set -o pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_CATALOG="${HARNESS_ROOT}/core/skills/catalog.json"
SCOPE="all"
MODE="all"
REPORT_PATH=""

usage() {
    cat <<'USAGE'
Usage: test/e2e/test_install_matrix.sh [options]

Options:
  --scope target|global  Run one installation scope (default: all)
  --mode default|expert  Run one skill-surface mode (default: all)
  --report <path>        Write one cell's machine-readable JSON result
  -h, --help             Show this help
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --scope)
            [ "$#" -ge 2 ] || { echo "Missing value for --scope" >&2; exit 2; }
            SCOPE="$2"
            shift 2
            ;;
        --mode)
            [ "$#" -ge 2 ] || { echo "Missing value for --mode" >&2; exit 2; }
            MODE="$2"
            shift 2
            ;;
        --report)
            [ "$#" -ge 2 ] || { echo "Missing value for --report" >&2; exit 2; }
            REPORT_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "${SCOPE}" in target|global|all) ;; *) echo "Invalid scope: ${SCOPE}" >&2; exit 2 ;; esac
case "${MODE}" in default|expert|all) ;; *) echo "Invalid mode: ${MODE}" >&2; exit 2 ;; esac
if [ -n "${REPORT_PATH}" ] && { [ "${SCOPE}" = "all" ] || [ "${MODE}" = "all" ]; }; then
    echo "--report requires one explicit scope and mode" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for compatibility evidence" >&2
    exit 2
fi

assert_file() {
    if [ ! -f "$1" ]; then
        echo "Missing file: $1" >&2
        return 1
    fi
}

assert_absent() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        echo "Unexpected managed path: $1" >&2
        return 1
    fi
}

snapshot_tree() {
    local root="$1"
    local output="$2"
    local path rel checksum target

    : > "${output}"
    while IFS= read -r path; do
        rel="${path#${root}/}"
        if [ -L "${path}" ]; then
            target="$(readlink "${path}")"
            printf 'L\t%s\t%s\n' "${rel}" "${target}" >> "${output}"
        elif [ -f "${path}" ]; then
            checksum="$(cksum < "${path}" | awk '{print $1 ":" $2}')"
            printf 'F\t%s\t%s\n' "${rel}" "${checksum}" >> "${output}"
        elif [ -d "${path}" ]; then
            printf 'D\t%s\n' "${rel}" >> "${output}"
        fi
    done < <(find "${root}" -mindepth 1 -print | LC_ALL=C sort)
}

verify_skill_surface() {
    local destination="$1"
    local mode="$2"
    local allow_user_skill="$3"
    local namespace workflow published_workflow primitive published_primitive removed installed_count expected_count
    namespace="$(jq -r '.namespace // empty' "${SKILL_CATALOG}")"
    [ "${namespace}" = "harness" ] || { echo "Unexpected skill namespace: ${namespace}" >&2; return 1; }

    while IFS= read -r workflow; do
        published_workflow="${namespace}-${workflow}"
        assert_file "${destination}/${published_workflow}/SKILL.md" || return 1
        grep -qx "name: ${published_workflow}" "${destination}/${published_workflow}/SKILL.md" || return 1
    done < <(jq -r '.public | keys[]' "${SKILL_CATALOG}")

    if [ "${mode}" = "expert" ]; then
        while IFS= read -r primitive; do
            published_primitive="${namespace}-${primitive}"
            assert_file "${destination}/${published_primitive}/SKILL.md" || return 1
            grep -qx "name: ${published_primitive}" "${destination}/${published_primitive}/SKILL.md" || return 1
        done < <(jq -r '.internal[]' "${SKILL_CATALOG}")
    else
        while IFS= read -r primitive; do
            assert_absent "${destination}/${primitive}" || return 1
            assert_absent "${destination}/${namespace}-${primitive}" || return 1
        done < <(jq -r '.internal[]' "${SKILL_CATALOG}")
    fi

    while IFS= read -r removed; do
        assert_absent "${destination}/${removed}" || return 1
        assert_absent "${destination}/${namespace}-${removed}" || return 1
    done < <(jq -r '.removed[]' "${SKILL_CATALOG}")

    expected_count="$(jq -r '.public | length' "${SKILL_CATALOG}")"
    if [ "${mode}" = "expert" ]; then
        expected_count=$((expected_count + $(jq -r '.internal | length' "${SKILL_CATALOG}")))
    fi
    if [ "${allow_user_skill}" = "true" ]; then
        expected_count=$((expected_count + 1))
        assert_file "${destination}/user-owned/SKILL.md" || return 1
    fi
    installed_count="$(find "${destination}" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l | tr -d ' ')"
    if [ "${installed_count}" -ne "${expected_count}" ]; then
        echo "Unexpected skill count in ${destination}: got ${installed_count}, expected ${expected_count}" >&2
        return 1
    fi
}

install_once() {
    local scope="$1"
    local mode="$2"
    local cell_home="$3"
    local target="$4"
    local log_path="$5"
    local args=()

    if [ "${scope}" = "target" ]; then
        args=(--target "${target}")
    else
        args=(--global)
    fi
    if [ "${mode}" = "expert" ]; then
        args+=(--expert)
    fi

    # Keep the installer's transaction journal outside the snapshotted home, so
    # idempotency is asserted over the installed surface rather than over install history.
    HOME="${cell_home}" HARNESS_STATE_DIR="${cell_home}.state" \
        "${HARNESS_ROOT}/install.sh" "${args[@]}" >> "${log_path}" 2>&1
}

verify_target_contracts() {
    local target="$1"
    local mode="$2"
    local runtime path allow_user

    for runtime in agents claude codex gemini; do
        path="${target}/.${runtime}/skills"
        allow_user="false"
        [ "${runtime}" = "codex" ] && allow_user="true"
        verify_skill_surface "${path}" "${mode}" "${allow_user}" || return 1
    done

    for path in \
        "${target}/.gemini/rules" \
        "${target}/.claude/rules" \
        "${target}/.codex/rules" \
        "${target}/.cursor/rules" \
        "${target}/.agents/rules"; do
        [ -d "${path}" ] || { echo "Missing runtime rules directory: ${path}" >&2; return 1; }
    done
    assert_file "${target}/AGENTS.md" || return 1
    [ -L "${target}/CLAUDE.md" ] || { echo "Missing CLAUDE.md link" >&2; return 1; }
    [ -L "${target}/GEMINI.md" ] || { echo "Missing GEMINI.md link" >&2; return 1; }
}

verify_global_contracts() {
    local cell_home="$1"
    local mode="$2"
    local runtime path allow_user

    for runtime in agents claude codex gemini; do
        case "${runtime}" in
            gemini) path="${cell_home}/.gemini/antigravity/skills" ;;
            *) path="${cell_home}/.${runtime}/skills" ;;
        esac
        allow_user="false"
        [ "${runtime}" = "codex" ] && allow_user="true"
        verify_skill_surface "${path}" "${mode}" "${allow_user}" || return 1
    done

    for path in harness agh agent-harness; do
        if [ ! -L "${cell_home}/.local/bin/${path}" ]; then
            echo "Missing global CLI link: ${path}" >&2
            return 1
        fi
    done
}

write_report() {
    local path="$1"
    local scope="$2"
    local mode="$3"
    local status="$4"
    local contracts

    [ -n "${path}" ] || return 0
    mkdir -p "$(dirname "${path}")"
    if [ "${scope}" = "target" ]; then
        contracts='["agents","claude","codex","cursor","gemini"]'
    else
        contracts='["agents","claude","cli","codex","gemini"]'
    fi
    jq -n \
        --arg os "$(uname -s)" \
        --arg scope "${scope}" \
        --arg mode "${mode}" \
        --arg status "${status}" \
        --argjson verifiedContracts "${contracts}" \
        '{schemaVersion: 1, os: $os, scope: $scope, mode: $mode, status: $status, installerRuns: 2, idempotent: ($status == "passed"), userContentPreserved: ($status == "passed"), verifiedContracts: $verifiedContracts}' \
        > "${path}"
}

run_cell() {
    local scope="$1"
    local mode="$2"
    local report_path="$3"
    local cell_dir cell_home target log_path before after result

    cell_dir="$(mktemp -d)" || return 1
    cell_home="${cell_dir}/home"
    target="${cell_dir}/target"
    log_path="${cell_dir}/install.log"
    before="${cell_dir}/before.manifest"
    after="${cell_dir}/after.manifest"
    mkdir -p "${cell_home}" "${target}"

    if [ "${scope}" = "target" ]; then
        mkdir -p "${target}/.codex/skills/user-owned"
        printf '%s\n' "user-owned" > "${target}/.codex/skills/user-owned/SKILL.md"
    else
        mkdir -p "${cell_home}/.codex/skills/user-owned"
        printf '%s\n' "user-owned" > "${cell_home}/.codex/skills/user-owned/SKILL.md"
    fi

    result=0
    install_once "${scope}" "${mode}" "${cell_home}" "${target}" "${log_path}" || result=1
    if [ "${result}" -eq 0 ]; then
        if [ "${scope}" = "target" ]; then
            verify_target_contracts "${target}" "${mode}" || result=1
            snapshot_tree "${target}" "${before}" || result=1
        else
            verify_global_contracts "${cell_home}" "${mode}" || result=1
            snapshot_tree "${cell_home}" "${before}" || result=1
        fi
    fi

    [ "${result}" -ne 0 ] || install_once "${scope}" "${mode}" "${cell_home}" "${target}" "${log_path}" || result=1
    if [ "${result}" -eq 0 ]; then
        if [ "${scope}" = "target" ]; then
            verify_target_contracts "${target}" "${mode}" || result=1
            snapshot_tree "${target}" "${after}" || result=1
        else
            verify_global_contracts "${cell_home}" "${mode}" || result=1
            snapshot_tree "${cell_home}" "${after}" || result=1
        fi
    fi
    if [ "${result}" -eq 0 ] && ! cmp -s "${before}" "${after}"; then
        echo "Installation is not idempotent for ${scope}/${mode}" >&2
        diff -u "${before}" "${after}" >&2 || true
        result=1
    fi

    if [ "${result}" -eq 0 ]; then
        if write_report "${report_path}" "${scope}" "${mode}" "passed"; then
            echo "[PASS] ${scope}/${mode}"
        else
            echo "Unable to write compatibility evidence: ${report_path}" >&2
            result=1
        fi
    fi
    if [ "${result}" -ne 0 ]; then
        if ! write_report "${report_path}" "${scope}" "${mode}" "failed"; then
            echo "Unable to write failed compatibility evidence: ${report_path}" >&2
        fi
        echo "[FAIL] ${scope}/${mode}" >&2
        [ ! -s "${log_path}" ] || sed -n '1,200p' "${log_path}" >&2
    fi
    rm -rf "${cell_dir}"
    return "${result}"
}

scopes="${SCOPE}"
modes="${MODE}"
[ "${SCOPE}" = "all" ] && scopes="target global"
[ "${MODE}" = "all" ] && modes="default expert"

overall=0
for scope in ${scopes}; do
    for mode in ${modes}; do
        cell_report=""
        if [ "${scope}" = "${SCOPE}" ] && [ "${mode}" = "${MODE}" ]; then
            cell_report="${REPORT_PATH}"
        fi
        run_cell "${scope}" "${mode}" "${cell_report}" || overall=1
    done
done

exit "${overall}"
