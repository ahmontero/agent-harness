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
    "uninstall:Remove the surfaces, CLI symlinks and hook agent-harness installed"
    "version:Report the installed version, checkout and revision"
    "upgrade:Update the checkout and re-sync every managed surface"
)

# What each command actually takes. Completion offered the top-level names and stopped, so
# the second word -- which is where every one of these commands does something -- was never
# completed at all. "<command>:<space-separated words>".
HARNESS_SUBCOMMANDS=(
    "doctor:--fix --check-auth --json"
    "context:--json"
    "config:validate --json"
    "spec:status create verify archive --json --module"
    "qa:test tdd scan lint types all --json"
    "scan:--staged --diff --branch --all --base --json --rules --install-hook --force"
    "worktree:create list seed remove --base --seed --force --dry-run"
    "branch:create check list --base"
    "commit:build check --branch --base --message-file --install-hook --force"
    "debt:--json --all --path"
    "receipt:start phase finish list show prune --issue --keep --json"
    "ledger:start append show rulings signature failure"
    "ship:--yes --dry-run --draft --body-file"
    "sync:--check --target --global --expert"
    "init:--recipe --with-hook"
    "uninstall:--global --target --dry-run --yes"
    "completion:install"
    "upgrade:--check"
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
        printf '    local -a subcommands\n'
        printf '    if (( CURRENT == 2 )); then\n'
        printf '        _describe '"'"'command'"'"' commands\n'
        printf '        return\n'
        printf '    fi\n'
        printf '    case "${words[2]}" in\n'
        for entry in "${HARNESS_SUBCOMMANDS[@]}"; do
            printf '        %s) subcommands=(%s) ;;\n' "${entry%%:*}" "${entry#*:}"
        done
        printf '    esac\n'
        printf '    (( ${#subcommands} )) && _describe '"'"'subcommand'"'"' subcommands\n'
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
        printf '    local subcommands=""\n'
        printf '    case "${COMP_WORDS[1]}" in\n'
        local entry
        for entry in "${HARNESS_SUBCOMMANDS[@]}"; do
            printf '        %s) subcommands="%s" ;;\n' "${entry%%:*}" "${entry#*:}"
        done
        printf '    esac\n'
        printf '    COMPREPLY=()\n'
        printf '    if [ "${COMP_CWORD}" -eq 1 ]; then\n'
        printf '        while IFS= read -r candidate; do\n'
        printf '            COMPREPLY+=("${candidate}")\n'
        printf '        done < <(compgen -W "${commands}" -- "${current}")\n'
        printf '    elif [ -n "${subcommands}" ]; then\n'
        printf '        while IFS= read -r candidate; do\n'
        printf '            COMPREPLY+=("${candidate}")\n'
        printf '        done < <(compgen -W "${subcommands}" -- "${current}")\n'
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
    -h|--help)
        echo "Usage: harness completion install"
        ;;
    *)
        # This printed the usage text and exited 0, so `harness completion isntall` reported
        # success having written no completion at all. Every other command in the CLI
        # refuses a subcommand it does not have.
        log_error "Unknown completion action: ${1:-<none>}"
        echo "Usage: harness completion install" >&2
        exit 1
        ;;
esac
