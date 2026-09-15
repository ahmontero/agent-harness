#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/git.sh
# Git Automation, Trunk Resolution & Worktree Helpers
# ==============================================================================

set -eo pipefail

# The marker that makes "our hook" a decidable question, shared by the installer in
# stack-scan.sh and the diagnostic in stack-doctor.sh so the two cannot disagree about
# which hooks agent-harness is allowed to touch.
# shellcheck disable=SC2034 # consumed by the scripts that source this library
HARNESS_PRE_COMMIT_MARKER="# agent-harness-pre-commit-hook-v1"
# The message validator's hook answers the same question the scanner's does: is this ours to
# replace. Without a marker of its own an installer cannot tell an idempotent re-run from
# destroying a hook the project depends on.
# shellcheck disable=SC2034 # consumed by the scripts that source this library
HARNESS_COMMIT_MSG_MARKER="# agent-harness-commit-msg-hook-v1"

# Resolves the hooks directory git will actually read, which is not ${repo}/.git/hooks in
# a linked worktree, where .git is a file.
resolve_hooks_dir() {
    local repo_dir="${1:-$(pwd)}"
    local hooks_dir
    hooks_dir="$(git -C "${repo_dir}" rev-parse --git-path hooks 2>/dev/null)" || return 1
    [[ "${hooks_dir}" = /* ]] || hooks_dir="${repo_dir}/${hooks_dir}"
    printf '%s\n' "${hooks_dir}"
}

# Writes one managed hook: <marker> on line 2, then the body, installed atomically. The
# checkout that installed it is written in and the bare name kept as a fallback, because a
# GUI Git client does not inherit a login shell and `harness` alone is not on its PATH.
#
# Both managed hooks go through here. The refusal, the backup and the atomic rename were
# written once for the scanner's hook, and a second copy for the message validator's is
# exactly the divergence this library exists to prevent.
install_managed_hook() {
    local repo_dir="$1"
    local hook_name="$2"
    local marker="$3"
    local invocation="$4"
    # The line a human pastes into a hook of their own is not the line this file executes:
    # the body resolves ${HARNESS_CLI} and exits through exec, and neither belongs in
    # somebody else's script. Conflating the two printed the hook's own body as advice.
    local manual_line="$5"
    local force="$6"
    local hooks_dir hook_path backup temporary harness_cli

    hooks_dir="$(resolve_hooks_dir "${repo_dir}")" || return 1
    hook_path="${hooks_dir}/${hook_name}"
    backup="${hook_path}.harness-backup"
    mkdir -p "${hooks_dir}"

    if [ -e "${hook_path}" ] && ! grep -qxF "${marker}" "${hook_path}" 2>/dev/null; then
        if [ "${force}" != true ]; then
            # stdout is this function's return channel -- the caller reads the hook path from
            # it through a command substitution. Advice written there is swallowed by that
            # capture and never reaches anyone, so every human line here goes to stderr.
            log_error "A ${hook_name} hook that agent-harness did not write already exists: ${hook_path}"
            log_info "Add this line to it instead, or re-run with --force to back it up and replace it:" >&2
            printf '  %s\n' "${manual_line}" >&2
            return 1
        fi
        if [ -e "${backup}" ]; then
            log_error "Refusing to overwrite an existing backup: ${backup}"
            return 1
        fi
        cp -p "${hook_path}" "${backup}"
        log_warn "Backed up the previous ${hook_name} hook to ${backup}."
    fi

    harness_cli="$(get_harness_root)/bin/harness"
    temporary="$(mktemp "${hooks_dir}/${hook_name}.harness.XXXXXX")"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' "${marker}"
        printf 'HARNESS_CLI="%s"\n' "${harness_cli}"
        printf '[ -x "${HARNESS_CLI}" ] || HARNESS_CLI="harness"\n'
        printf '%s\n' "${invocation}"
    } > "${temporary}"
    chmod 755 "${temporary}"
    mv "${temporary}" "${hook_path}"
    printf '%s\n' "${hook_path}"
}

ensure_git_repo() {
    local repo_dir="${1:-$(pwd)}"
    if [ ! -d "${repo_dir}/.git" ] && ! git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "'${repo_dir}' is not a git repository."
        exit 1
    fi
}

# get_repo_root lives in lib/utils.sh: lib/config.sh needs it and is sourced before this
# file everywhere, and without this file at all by stack-config.sh and install.sh.

get_current_branch() {
    local repo_dir="${1:-$(pwd)}"
    git -C "${repo_dir}" branch --show-current 2>/dev/null || echo "HEAD"
}

get_trunk_branch() {
    local repo_dir="${1:-$(pwd)}"
    local configured_trunk
    configured_trunk="$(get_profile_value "git.trunkBranch" "")"

    if [ -n "${configured_trunk}" ]; then
        echo "${configured_trunk}"
        return
    fi

    # Auto-detect main vs master
    if git -C "${repo_dir}" show-ref --verify --quiet refs/heads/main 2>/dev/null || \
       git -C "${repo_dir}" show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
        echo "main"
    elif git -C "${repo_dir}" show-ref --verify --quiet refs/heads/master 2>/dev/null || \
         git -C "${repo_dir}" show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
        echo "master"
    else
        echo "main"
    fi
}

is_working_tree_dirty() {
    local repo_dir="${1:-$(pwd)}"
    if [ -n "$(git -C "${repo_dir}" status --porcelain 2>/dev/null)" ]; then
        return 0 # Dirty
    else
        return 1 # Clean
    fi
}

# Parses the shared "<type> <issue_key> <slug>" creation form, with --base as a flag rather
# than a fourth positional argument. Both `harness branch create` and
# `harness worktree create` advertised --base and read the base positionally, so the flag
# reached git as a revision and printed git's usage text instead of creating anything. The
# fourth positional argument still works, so no existing invocation changes meaning.
parse_create_arguments() {
    CREATE_TYPE=""
    CREATE_KEY=""
    CREATE_SLUG=""
    CREATE_BASE=""
    local positional=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --base)
                if [ -z "${2:-}" ]; then
                    log_error "--base requires a branch name."
                    return 1
                fi
                CREATE_BASE="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                return 1
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    # shellcheck disable=SC2034 # read by the caller after this function returns
    CREATE_TYPE="${positional[0]:-}"
    # shellcheck disable=SC2034 # read by the caller after this function returns
    CREATE_KEY="${positional[1]:-}"
    # shellcheck disable=SC2034 # read by the caller after this function returns
    CREATE_SLUG="${positional[2]:-}"
    [ -n "${CREATE_BASE}" ] || CREATE_BASE="${positional[3]:-}"
}
