#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-completion.sh
# Autocompletion installer for Zsh & Bash
# ==============================================================================
#
# The command list lives here once and is rendered into both shells. README.md has
# advertised "Shell Autocompletion (Zsh & Bash)" since the command existed while only the
# Zsh file was ever written, and the Zsh list had already drifted behind the dispatcher.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

# "<command>:<description>" in the order `harness --help` lists them.
HARNESS_COMMANDS=(
    "doctor:Diagnose and self-heal environment health, symlinks, hooks and configs"
    "context:Extract fast workspace signals (<1s) for LLMs"
    "config:Report the resolved configuration and validate its structure"
    "spec:Manage Living Delta Specs"
    "qa:Run test suites, TDD loops, linters, types"
    "scan:Run the static landmine scanner"
    "worktree:Create, seed, list and remove git worktrees"
    "branch:Manage git branches"
    "commit:Build or check a conventional commit message"
    "debt:Harvest technical debt markers"
    "receipt:Record and read private local workflow receipts"
    "ledger:Keep a durable append-only record of a workflow run"
    "ship:Run pre-flight checks, push the branch and open a Pull Request"
    "sync:Report or repair drift in installed skill surfaces"
    "completion:Install shell autocompletion"
    "init:Initialize the harness in a repository"
    "version:Report the installed version, checkout and revision"
    "upgrade:Update the checkout and re-sync every managed surface"
)

command_names() {
    local entry
    for entry in "${HARNESS_COMMANDS[@]}"; do
        printf '%s ' "${entry%%:*}"
    done
}

install_zsh() {
    local zsh_dir="${HOME}/.zsh/completion"
    local entry
    mkdir -p "${zsh_dir}"
    {
        printf '#compdef harness agh agent-harness\n\n'
        printf '_harness() {\n'
        printf '    local -a commands\n'
        printf '    commands=(\n'
        for entry in "${HARNESS_COMMANDS[@]}"; do
            printf "        '%s'\n" "${entry}"
        done
        printf '    )\n'
        printf '    _describe '"'"'command'"'"' commands\n'
        printf '}\n'
        printf '_harness "$@"\n'
    } > "${zsh_dir}/_harness"
    ln -sf "${zsh_dir}/_harness" "${zsh_dir}/_agh"
    ln -sf "${zsh_dir}/_harness" "${zsh_dir}/_agent-harness"
    log_success "Zsh completion written to ${zsh_dir}/_harness"
    log_info "Ensure ${zsh_dir} is on your fpath, then run 'compinit'."
}

install_bash() {
    local bash_dir="${HOME}/.local/share/bash-completion/completions"
    mkdir -p "${bash_dir}"
    {
        printf '# agent-harness bash completion\n'
        printf '_harness_complete() {\n'
        printf '    local current commands candidate\n'
        printf '    current="${COMP_WORDS[COMP_CWORD]}"\n'
        printf '    commands="%s"\n' "$(command_names)"
        # A read loop rather than mapfile: mapfile is bash 4, and macOS still ships 3.2,
        # so a generated completion using it would be a syntax error in the default shell
        # of the platform half of this project's CI runs on.
        printf '    if [ "${COMP_CWORD}" -eq 1 ]; then\n'
        printf '        COMPREPLY=()\n'
        printf '        while IFS= read -r candidate; do\n'
        printf '            COMPREPLY+=("${candidate}")\n'
        printf '        done < <(compgen -W "${commands}" -- "${current}")\n'
        printf '    fi\n'
        printf '}\n'
        printf 'complete -F _harness_complete harness agh agent-harness\n'
    } > "${bash_dir}/harness"
    log_success "Bash completion written to ${bash_dir}/harness"
    log_info "Add 'source ${bash_dir}/harness' to your ~/.bashrc, or install bash-completion to load it automatically."
}

case "${1:-}" in
    install)
        install_zsh
        install_bash
        ;;
    *)
        echo "Usage: harness completion install"
        ;;
esac
