#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/surface.sh
# Installed skill surface identity and drift reasoning
# ==============================================================================
#
# Shared by the installer, `harness sync`, and `harness doctor`. It is one file on
# purpose: the installer decides what a surface should contain, and the drift check
# decides whether it still does. If those two answers came from two implementations
# they would eventually disagree, and a surface would be reported current because the
# checker forgot a rule the installer applies.
#
# Requires lib/utils.sh (for get_harness_root) and jq.

set -eo pipefail

SURFACE_MANIFEST_NAME=".agent-harness-surface.json"
SURFACE_MANIFEST_SCHEMA=1
SURFACE_DIGEST_LENGTH=12

# Set by surface_evaluate and read by its callers -- install.sh, stack-sync.sh, and
# stack-doctor.sh. ShellCheck analyses this file on its own and cannot see those readers.
# shellcheck disable=SC2034 # consumed by the scripts that source this library
SURFACE_STATE=""
# shellcheck disable=SC2034 # consumed by the scripts that source this library
SURFACE_REASONS=()

surface_catalog_path() {
    printf '%s/core/skills/catalog.json' "$(get_harness_root)"
}

surface_namespace() {
    jq -r '.namespace // empty' "$(surface_catalog_path)"
}

surface_harness_version() {
    local manifest
    manifest="$(get_harness_root)/package.json"
    if [ ! -f "${manifest}" ]; then
        log_error "Cannot determine the agent-harness version: ${manifest} is missing."
        return 1
    fi
    jq -r '.version' "${manifest}"
}

surface_workflow_allowed() {
    local workflow="$1"
    local runtime="$2"
    jq -e --arg workflow "${workflow}" --arg runtime "${runtime}" \
        'if (.runtimes // {}) | has($workflow) then (.runtimes[$workflow] | index($runtime)) != null else true end' \
        "$(surface_catalog_path)" >/dev/null
}

# Reads "<relative path>\t<absolute path>" lines, already sorted by relative path, and
# hashes the concatenation of each path followed by its content. Prefixing the path is
# what makes a rename register: content republished under a new name signs differently.
surface_digest_stream() {
    local relative absolute
    while IFS=$'\t' read -r relative absolute; do
        printf '%s\n' "${relative}"
        cat "${absolute}"
    done | git hash-object --stdin | cut -c "1-${SURFACE_DIGEST_LENGTH}"
}

# LC_ALL=C on every sort in this file. The two digests below must agree byte for byte on
# both CI runners, and a locale-dependent collation would make one bundle sign two ways
# depending on where it was installed -- the AH-9 lesson about tooling that differs
# between GNU and BSD, applied before it can bite.
surface_source_digest() {
    local workflow="$1"
    local root primitive
    root="$(get_harness_root)/core/skills"
    {
        printf 'SKILL.md\t%s/%s/SKILL.md\n' "${root}" "${workflow}"
        while IFS= read -r primitive; do
            printf 'references/%s.md\t%s/%s/SKILL.md\n' "${primitive}" "${root}" "${primitive}"
        done < <(jq -r --arg workflow "${workflow}" '.public[$workflow][]' "$(surface_catalog_path)")
    } | LC_ALL=C sort -t"$(printf '\t')" -k1,1 | surface_digest_stream
}

surface_installed_digest() {
    local bundle="$1"
    local reference
    [ -f "${bundle}/SKILL.md" ] || return 1
    {
        printf 'SKILL.md\t%s/SKILL.md\n' "${bundle}"
        if [ -d "${bundle}/references" ]; then
            for reference in "${bundle}"/references/*.md; do
                [ -f "${reference}" ] || continue
                printf 'references/%s\t%s\n' "$(basename "${reference}")" "${reference}"
            done
        fi
    } | LC_ALL=C sort -t"$(printf '\t')" -k1,1 | surface_digest_stream
}

# The published names a runtime should carry in a given mode, as "<name>\t<kind>" lines.
surface_expected_entries() {
    local runtime="$1"
    local mode="$2"
    local namespace catalog workflow primitive
    catalog="$(surface_catalog_path)"
    namespace="$(surface_namespace)"
    while IFS= read -r workflow; do
        if surface_workflow_allowed "${workflow}" "${runtime}"; then
            printf '%s-%s\tbundle\n' "${namespace}" "${workflow}"
        fi
    done < <(jq -r '.public | keys[]' "${catalog}")
    if [ "${mode}" = "expert" ]; then
        while IFS= read -r primitive; do
            printf '%s-%s\tsymlink\n' "${namespace}" "${primitive}"
        done < <(jq -r '.internal[]' "${catalog}")
    fi
}

surface_has_managed_content() {
    local directory="$1"
    [ -d "${directory}" ] || return 1
    find "${directory}" -mindepth 2 -maxdepth 2 -name ".agent-harness-managed" -print -quit 2>/dev/null | grep -q .
}

# Sets SURFACE_STATE to absent, unmanaged, current, or drifted, and fills SURFACE_REASONS.
# "unmanaged" means a directory agent-harness has never installed into; it is reported so
# that a mistyped --target is visible, and it is never repaired.
# shellcheck disable=SC2034 # SURFACE_STATE is read by the scripts that source this library
surface_evaluate() {
    local directory="$1"
    local manifest="${directory}/${SURFACE_MANIFEST_NAME}"
    local recorded_runtime recorded_mode recorded_version current_version
    local expected_names recorded_names name kind digest recorded_digest installed_digest source_digest

    SURFACE_STATE=""
    SURFACE_REASONS=()

    if [ ! -d "${directory}" ]; then
        SURFACE_STATE="absent"
        return 0
    fi
    if [ ! -f "${manifest}" ]; then
        if surface_has_managed_content "${directory}"; then
            SURFACE_STATE="drifted"
            SURFACE_REASONS+=("no recorded version: installed before surface manifests existed")
        else
            SURFACE_STATE="unmanaged"
        fi
        return 0
    fi
    if ! jq empty "${manifest}" >/dev/null 2>&1 || \
       [ "$(jq -r '.schemaVersion' "${manifest}")" != "${SURFACE_MANIFEST_SCHEMA}" ]; then
        SURFACE_STATE="drifted"
        SURFACE_REASONS+=("no recorded version: the manifest is unreadable or uses an unrecognized schema")
        return 0
    fi

    recorded_runtime="$(jq -r '.runtime' "${manifest}")"
    recorded_mode="$(jq -r '.mode' "${manifest}")"
    recorded_version="$(jq -r '.harnessVersion' "${manifest}")"
    current_version="$(surface_harness_version)"

    if [ "${recorded_version}" != "${current_version}" ]; then
        SURFACE_REASONS+=("recorded version ${recorded_version}, current ${current_version}")
    fi

    expected_names="$(surface_expected_entries "${recorded_runtime}" "${recorded_mode}" | LC_ALL=C sort)"
    recorded_names="$(jq -r '.skills[] | "\(.name)\t\(.kind)"' "${manifest}" | LC_ALL=C sort)"
    if [ "${expected_names}" != "${recorded_names}" ]; then
        while IFS=$'\t' read -r name kind; do
            [ -n "${name}" ] || continue
            printf '%s\n' "${recorded_names}" | grep -qxF "${name}	${kind}" || \
                SURFACE_REASONS+=("${name}: the catalog publishes it for this runtime and the surface does not carry it")
        done <<< "${expected_names}"
        while IFS=$'\t' read -r name kind; do
            [ -n "${name}" ] || continue
            printf '%s\n' "${expected_names}" | grep -qxF "${name}	${kind}" || \
                SURFACE_REASONS+=("${name}: recorded here but no longer published for this runtime")
        done <<< "${recorded_names}"
    fi

    while IFS=$'\t' read -r name kind recorded_digest; do
        [ -n "${name}" ] || continue
        if [ "${kind}" = "symlink" ]; then
            [ -L "${directory}/${name}" ] || \
                SURFACE_REASONS+=("${name}: recorded as a symlink and is not one")
            continue
        fi
        if [ ! -d "${directory}/${name}" ]; then
            SURFACE_REASONS+=("${name}: missing from the surface")
            continue
        fi
        installed_digest="$(surface_installed_digest "${directory}/${name}" || true)"
        source_digest="$(surface_source_digest "${name#"$(surface_namespace)"-}" 2>/dev/null || true)"
        if [ -n "${source_digest}" ] && [ "${installed_digest}" != "${source_digest}" ]; then
            if [ "${installed_digest}" != "${recorded_digest}" ]; then
                SURFACE_REASONS+=("${name}: the installed copy was edited after installation")
            else
                SURFACE_REASONS+=("${name}: the source has changed since installation")
            fi
        fi
    done < <(jq -r '.skills[] | "\(.name)\t\(.kind)\t\(.digest // "")"' "${manifest}")

    if [ ${#SURFACE_REASONS[@]} -eq 0 ]; then
        SURFACE_STATE="current"
    else
        SURFACE_STATE="drifted"
    fi
}

# The surfaces each scope owns, as "<directory>\t<runtime>" lines. Both the installer and
# the sync path read them from here so a surface can never be installed into one place and
# looked for in another.
surface_global_list() {
    printf '%s/.gemini/antigravity/skills\tgemini\n' "${HOME}"
    printf '%s/.gemini/config/skills\tgemini\n' "${HOME}"
    printf '%s/.claude/skills\tclaude\n' "${HOME}"
    printf '%s/.codex/skills\tcodex\n' "${HOME}"
    printf '%s/.agents/skills\tagents\n' "${HOME}"
}

surface_repo_list() {
    local target="$1"
    printf '%s/.gemini/skills\tgemini\n' "${target}"
    printf '%s/.claude/skills\tclaude\n' "${target}"
    printf '%s/.codex/skills\tcodex\n' "${target}"
    printf '%s/.agents/skills\tagents\n' "${target}"
}

# The mode a scope was installed in. Expert wins: a scope with any expert surface is an
# expert installation, and repairing it as curated is the silent downgrade this delta
# exists to stop. A scope with no manifest at all has no recorded mode and returns nothing,
# leaving the choice to the caller rather than guessing here.
surface_scope_mode() {
    local directory mode found=""
    while IFS=$'\t' read -r directory _; do
        [ -f "${directory}/${SURFACE_MANIFEST_NAME}" ] || continue
        mode="$(jq -r '.mode // empty' "${directory}/${SURFACE_MANIFEST_NAME}" 2>/dev/null || true)"
        [ -n "${mode}" ] || continue
        found="${mode}"
        [ "${mode}" = "expert" ] && { printf 'expert'; return 0; }
    done
    [ -z "${found}" ] || printf '%s' "${found}"
}
