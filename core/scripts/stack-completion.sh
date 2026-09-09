#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-completion.sh
# Autocompletion installer for Zsh & Bash
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

install_zsh() {
    local zsh_dir="${HOME}/.zsh/completion"
    mkdir -p "${zsh_dir}"
    cat > "${zsh_dir}/_harness" << 'ZSH_EOF'
#compdef harness agh agent-harness forge

_harness() {
    local -a commands
    commands=(
        'doctor:Diagnose and self-heal environment health and configs'
        'context:Extract fast workspace signals (<1s) for LLMs'
        'spec:Manage Living Delta Specs'
        'qa:Run test suites, TDD loops, linters, types'
        'scan:Run static landmine scanner'
        'worktree:Manage git worktrees'
        'branch:Manage git branches'
        'commit:Build conventional commit message'
        'debt:Harvest technical debt markers'
        'receipt:Record private local workflow lifecycle events'
        'ledger:Keep a durable append-only record of a workflow run'
        'ship:Run pre-flight checks and open Pull Request'
        'sync:Re-synchronize skills and rules across harnesses'
        'init:Initialize harness in repository'
    )
    _describe 'command' commands
}
_harness "$@"
ZSH_EOF
    ln -sf "${zsh_dir}/_harness" "${zsh_dir}/_agh"
    ln -sf "${zsh_dir}/_harness" "${zsh_dir}/_agent-harness"
    log_success "Zsh autocompletions written to ${zsh_dir}/_harness"
}

if [ "$1" = "install" ]; then
    install_zsh
else
    echo "Usage: harness completion install"
fi
