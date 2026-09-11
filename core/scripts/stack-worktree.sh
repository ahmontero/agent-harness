#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-worktree.sh
# Git Worktree Workspace Isolation Manager
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/issues.sh"

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

ACTION="${1:-list}"
shift || true

cd "${REPO_DIR}"

case "${ACTION}" in
    create)
        parse_create_arguments "$@"
        TYPE="${CREATE_TYPE:-feat}"
        RAW_KEY="${CREATE_KEY}"
        SLUG="${CREATE_SLUG}"
        BASE="${CREATE_BASE:-$(get_trunk_branch "${REPO_DIR}")}"

        if [ -z "${RAW_KEY}" ] || [ -z "${SLUG}" ]; then
            log_error "Usage: harness worktree create <type> <issue_key> <slug> [--base <branch>]"
            exit 1
        fi

        ISSUE_KEY="$(normalize_issue_key "${RAW_KEY}")"
        BRANCH_NAME="${TYPE}/${ISSUE_KEY}-${SLUG}"
        PARENT_DIR="$(dirname "${REPO_DIR}")"
        REPO_NAME="$(basename "${REPO_DIR}")"
        WORKTREE_DIR="${PARENT_DIR}/${REPO_NAME}-${ISSUE_KEY}"

        log_info "Creating worktree for ${BOLD}${BRANCH_NAME}${RESET} in ${WORKTREE_DIR}..."
        git worktree add -b "${BRANCH_NAME}" "${WORKTREE_DIR}" "${BASE}"
        log_success "Worktree created: ${WORKTREE_DIR}"
        ;;
    list)
        git worktree list
        ;;
    remove)
        # `harness worktree remove wt-AH` used to interpolate the key into grep as a
        # pattern and pass --force to every match. In the reproduction that removed two
        # worktrees and destroyed an unsaved file, with no prompt and nothing to recover
        # it from. A worktree is where work lives; matching it is an exact question.
        KEY=""
        FORCE=false
        DRY_RUN=false
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --force) FORCE=true; shift ;;
                --dry-run) DRY_RUN=true; shift ;;
                -h|--help)
                    echo "Usage: harness worktree remove <issue_key|path> [--force] [--dry-run]"
                    exit 0
                    ;;
                -*)
                    log_error "Unknown worktree remove option: $1"
                    exit 1
                    ;;
                *)
                    if [ -n "${KEY}" ]; then
                        log_error "worktree remove takes one key or path, not two: '${KEY}' and '$1'."
                        exit 1
                    fi
                    KEY="$1"
                    shift
                    ;;
            esac
        done

        if [ -z "${KEY}" ]; then
            log_error "Usage: harness worktree remove <issue_key|path> [--force] [--dry-run]"
            exit 1
        fi

        WT_PATHS=()
        WT_BRANCHES=()
        wt_current_path=""
        wt_current_branch=""
        flush_worktree_record() {
            [ -n "${wt_current_path}" ] || return 0
            WT_PATHS+=("${wt_current_path}")
            WT_BRANCHES+=("${wt_current_branch}")
            wt_current_path=""
            wt_current_branch=""
        }
        while IFS= read -r porcelain_line; do
            case "${porcelain_line}" in
                "worktree "*)
                    flush_worktree_record
                    wt_current_path="${porcelain_line#worktree }"
                    ;;
                "branch refs/heads/"*)
                    wt_current_branch="${porcelain_line#branch refs/heads/}"
                    ;;
            esac
        done < <(git worktree list --porcelain)
        flush_worktree_record

        # The first record is the main worktree, which is never a removal candidate.
        MAIN_WORKTREE="${WT_PATHS[0]:-${REPO_DIR}}"

        # An exact question: the worktree's own path, its directory name, or the issue
        # segment of its branch. A branch of feat/AH-1-alpha answers to AH-1; a path of
        # wt-AH-1 does not answer to wt-AH.
        worktree_matches_key() {
            local path="$1"
            local branch="$2"
            local key="$3"
            local last_segment
            [ "${path}" = "${key}" ] && return 0
            [ "$(basename "${path}")" = "${key}" ] && return 0
            if [ -n "${branch}" ]; then
                last_segment="${branch##*/}"
                [ "${last_segment}" = "${key}" ] && return 0
                case "${last_segment}" in
                    "${key}-"*) return 0 ;;
                esac
            fi
            return 1
        }

        MATCHED_PATHS=()
        MATCHED_BRANCHES=()
        wt_index=0
        while [ "${wt_index}" -lt ${#WT_PATHS[@]} ]; do
            candidate_path="${WT_PATHS[${wt_index}]}"
            candidate_branch="${WT_BRANCHES[${wt_index}]}"
            if [ "${candidate_path}" != "${MAIN_WORKTREE}" ] && \
               worktree_matches_key "${candidate_path}" "${candidate_branch}" "${KEY}"; then
                MATCHED_PATHS+=("${candidate_path}")
                MATCHED_BRANCHES+=("${candidate_branch}")
            fi
            wt_index=$((wt_index + 1))
        done

        if [ ${#MATCHED_PATHS[@]} -eq 0 ]; then
            log_error "'${KEY}' matches no worktree."
            log_info "Known worktrees:"
            git worktree list | sed 's/^/  /'
            exit 1
        fi

        if [ ${#MATCHED_PATHS[@]} -gt 1 ]; then
            log_error "'${KEY}' matches more than one worktree; nothing was removed."
            wt_index=0
            while [ "${wt_index}" -lt ${#MATCHED_PATHS[@]} ]; do
                printf '  %s (%s)\n' "${MATCHED_PATHS[${wt_index}]}" "${MATCHED_BRANCHES[${wt_index}]:-detached}"
                wt_index=$((wt_index + 1))
            done
            log_info "Pass the exact path of the one you mean."
            exit 1
        fi

        TARGET_PATH="${MATCHED_PATHS[0]}"
        TARGET_BRANCH="${MATCHED_BRANCHES[0]:-detached}"

        if [ "${DRY_RUN}" = true ]; then
            log_info "Would remove worktree: ${TARGET_PATH} (${TARGET_BRANCH}). Nothing was changed."
            exit 0
        fi

        if [ -n "$(git -C "${TARGET_PATH}" status --porcelain 2>/dev/null)" ] && [ "${FORCE}" != true ]; then
            log_error "${TARGET_PATH} has uncommitted changes; nothing was removed."
            git -C "${TARGET_PATH}" status --short | sed 's/^/  /'
            log_info "Commit or stash them, or re-run with --force to discard them."
            exit 1
        fi

        log_info "Removing worktree ${TARGET_PATH} (${TARGET_BRANCH})..."
        if [ "${FORCE}" = true ]; then
            git worktree remove --force "${TARGET_PATH}"
        else
            git worktree remove "${TARGET_PATH}"
        fi
        log_success "Removed worktree at ${TARGET_PATH}"
        ;;
    *)
        echo "Usage: harness worktree <create|list|remove> [args...]"
        exit 1
        ;;
esac
