#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-qa.sh
# Universal QA, Test Suite Runner & TDD Orchestrator
# ==============================================================================
#
# Gate status codes, shared by the individual gates and the `all` aggregation:
#   0  the gate ran and passed
#   1  the gate ran and failed (or any other non-zero status from the checker)
#   2  the gate could not run: nothing is configured for it
#   3  the gate was skipped because the configuration declares this project has none
#
# 2 exists because "could not run" is not a pass. The previous defaults ended in
# `|| echo 'No linter configured'`, so a repository with neither ruff nor npm passed both
# the lint and the type gate and `qa all` reported "All required QA gates passed" having
# checked nothing, which is exactly what rules/floor.md invariant 1 forbids.
#
# 3 exists so the refusal is satisfiable. A project with genuinely no linter records that
# as a decision -- `"lintCommand": false` -- rather than living with a gate it can never
# pass. It is also why a configured false has to survive a configuration lookup at all.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"

GATE_UNRUNNABLE=2
GATE_DECLARED_ABSENT=3

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

ACTION="${1:-test}"
shift || true

cd "${REPO_DIR}"

# Resolves one configured command and runs it, or refuses. Extra arguments are appended,
# which is what lets `harness qa test tests/unit -k name` forward to the configured runner.
run_configured_gate() {
    local label="$1"
    local key="$2"
    local command_line="$3"
    shift 3

    case "${command_line}" in
        "")
            log_error "QA gate '${label}' could not run: nothing is configured for it."
            log_info "Set profiles.${ACTIVE_PROFILE}.${key} to the command this project uses, or to false to record that it has none."
            return "${GATE_UNRUNNABLE}"
            ;;
        false|none)
            log_warn "QA gate '${label}' skipped: the configuration declares this project has none (${key}: false)."
            return "${GATE_DECLARED_ABSENT}"
            ;;
    esac

    log_info "Running ${label}: ${BOLD}${command_line} $*${RESET}..."
    eval "${command_line} $*"
}

# The test command may also be expressed as a runner name, which is the older and more
# common form in a recipe's configuration.
resolve_test_command() {
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

gate_test() {
    run_configured_gate "test suite" "qa.testCommand" "$(resolve_test_command)" "$@"
}

gate_lint() {
    run_configured_gate "lint" "qa.lintCommand" "$(get_profile_value "qa.lintCommand" "")"
}

gate_types() {
    run_configured_gate "types" "qa.typeCheckCommand" "$(get_profile_value "qa.typeCheckCommand" "")"
}

# A gate invoked on its own reports a declared-absent checker as success: nothing is
# wrong with a project that has recorded it has no linter.
exit_for_single_gate() {
    local status="$1"
    [ "${status}" -eq "${GATE_DECLARED_ABSENT}" ] && exit 0
    exit "${status}"
}

case "${ACTION}" in
    test)
        STATUS=0
        gate_test "$@" || STATUS=$?
        exit_for_single_gate "${STATUS}"
        ;;
    tdd)
        TEST_PATH="${1:-}"
        shift || true
        TDD_CMD="$(get_profile_value "qa.tddCommand" "")"
        if [ -z "${TDD_CMD}" ]; then
            log_error "QA gate 'tdd' could not run: nothing is configured for it."
            log_info "Set profiles.${ACTIVE_PROFILE}.qa.tddCommand to the command this project uses, with {path} where the test path belongs."
            exit "${GATE_UNRUNNABLE}"
        fi
        CMD="${TDD_CMD//\{path\}/${TEST_PATH}}"
        log_info "Running TDD cycle: ${BOLD}${CMD} $*${RESET}..."
        eval "${CMD} $*"
        ;;
    lint)
        STATUS=0
        gate_lint || STATUS=$?
        exit_for_single_gate "${STATUS}"
        ;;
    types)
        STATUS=0
        gate_types || STATUS=$?
        exit_for_single_gate "${STATUS}"
        ;;
    scan)
        "${SCRIPT_DIR}/stack-scan.sh" "$@"
        ;;
    all)
        log_info "Running full QA suite (Scan -> Lint -> Types -> Tests)..."
        FAILED_GATES=()
        UNRUNNABLE_GATES=()
        DECLARED_GATES=()

        record_gate() {
            local gate_name="$1"
            local status="$2"
            case "${status}" in
                0) log_success "QA gate passed: ${gate_name}" ;;
                "${GATE_UNRUNNABLE}") UNRUNNABLE_GATES+=("${gate_name}") ;;
                "${GATE_DECLARED_ABSENT}") DECLARED_GATES+=("${gate_name}") ;;
                *)
                    log_error "QA gate failed: ${gate_name}"
                    FAILED_GATES+=("${gate_name}")
                    ;;
            esac
        }

        run_gate() {
            local gate_name="$1"
            shift
            local status=0
            "$@" || status=$?
            record_gate "${gate_name}" "${status}"
        }

        # --branch, not --diff. The aggregate suite is what runs before a branch is
        # published, and at that moment the working tree is clean: --diff read an empty set
        # and reported a passing scan over a branch whose commits were never inspected.
        run_gate "scan" "${SCRIPT_DIR}/stack-scan.sh" --branch
        run_gate "lint" gate_lint
        run_gate "types" gate_types
        run_gate "tests" gate_test

        if [ ${#DECLARED_GATES[@]} -gt 0 ]; then
            log_warn "QA gates declared absent by configuration: ${DECLARED_GATES[*]}"
        fi
        if [ ${#UNRUNNABLE_GATES[@]} -gt 0 ]; then
            log_error "QA gates could not run: ${UNRUNNABLE_GATES[*]}"
        fi
        if [ ${#FAILED_GATES[@]} -gt 0 ]; then
            log_error "QA gates failed: ${FAILED_GATES[*]}"
        fi
        if [ ${#UNRUNNABLE_GATES[@]} -gt 0 ] || [ ${#FAILED_GATES[@]} -gt 0 ]; then
            log_error "QA did not pass. A gate that could not run is not a gate that passed."
            exit 1
        fi
        log_success "All required QA gates passed."
        ;;
    *)
        log_error "Unknown QA action: ${ACTION}"
        echo "Usage: harness qa <test|tdd|lint|types|scan|all> [args...]"
        exit 1
        ;;
esac
