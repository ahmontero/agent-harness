#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/lib/qa.sh
# QA gate resolution and readiness
# ==============================================================================
#
# One answer to "what does this gate resolve to, and can it run", shared by stack-qa.sh,
# which runs the gates, and stack-doctor.sh, which reports whether they could run.
#
# It is one file for the same reason lib/specs.sh and lib/surface.sh are: two commands
# answering the same question from two implementations eventually disagree, and here the
# disagreement would be doctor calling an environment healthy that qa all then refuses --
# which is the exact defect doctor's gate section was added to close. Resolution is subtler
# than it looks: the test gate accepts a runner name as well as a command, and a gate set to
# false is a recorded decision rather than an absence. Either rule restated slightly
# differently in a second place is a fresh divergence.
#
# Requires lib/config.sh for get_profile_value.

set -eo pipefail

# The gates that resolve to a configured command, in the order both commands report them.
# The scan gate is not among them: it resolves to the scanner rather than to a project
# command, and qa all validates its mode separately.
# shellcheck disable=SC2034 # consumed by the scripts that source this library
QA_COMMAND_GATES=(lint types tests)

# The configuration key a gate reads. Every message that tells someone what to set names it
# from here, so the key a refusal quotes is the key the resolution actually consulted.
qa_gate_config_key() {
    case "$1" in
        lint)  printf 'qa.lintCommand' ;;
        types) printf 'qa.typeCheckCommand' ;;
        tests) printf 'qa.testCommand' ;;
    esac
}

# The test command may also be expressed as a runner name, which is the older and more
# common form in a recipe's configuration.
qa_resolve_test_command() {
    local configured runner
    configured="$(get_profile_value "qa.testCommand" "")"
    if [ -n "${configured}" ]; then
        printf '%s\n' "${configured}"
        return
    fi
    runner="$(get_profile_value "qa.testRunner" "")"
    case "${runner}" in
        pytest) printf '%s\n' "pytest" ;;
        django) printf '%s\n' "python manage.py test" ;;
        jest)   printf '%s\n' "npm test --" ;;
        vitest) printf '%s\n' "npx vitest run" ;;
        cargo)  printf '%s\n' "cargo test" ;;
        go)     printf '%s\n' "go test ./..." ;;
        false|none) printf '%s\n' "false" ;;
        *) printf '%s\n' "" ;;
    esac
}

# The command a gate resolves to: a shell string, "false" or "none" where the project has
# recorded it has no such gate, and empty where nothing is configured.
qa_gate_command() {
    case "$1" in
        lint)  get_profile_value "qa.lintCommand" "" ;;
        types) get_profile_value "qa.typeCheckCommand" "" ;;
        tests) qa_resolve_test_command ;;
    esac
}

# runnable, declared-absent, or unrunnable. The three states qa all's exit codes already
# distinguish, named so doctor can report the same verdict without running anything.
qa_gate_state() {
    case "$(qa_gate_command "$1")" in
        "")         printf 'unrunnable' ;;
        false|none) printf 'declared-absent' ;;
        *)          printf 'runnable' ;;
    esac
}
