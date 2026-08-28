#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-qa.sh
# Universal QA, Test Suite Runner & TDD Orchestrator
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/git.sh"

ACTIVE_PROFILE=$(get_active_profile)
REPO_DIR="$(get_target_repo "${ACTIVE_PROFILE}")"
ensure_git_repo "${REPO_DIR}"

ACTION="${1:-test}"
shift || true

cd "${REPO_DIR}"

case "${ACTION}" in
    test)
        TEST_CMD="$(get_profile_value "qa.testCommand" "")"
        if [ -z "${TEST_CMD}" ]; then
            RUNNER="$(get_profile_value "qa.testRunner" "pytest")"
            case "${RUNNER}" in
                pytest) TEST_CMD="pytest" ;;
                django) TEST_CMD="python manage.py test" ;;
                jest)   TEST_CMD="npm test --" ;;
                vitest) TEST_CMD="npx vitest run" ;;
                cargo)  TEST_CMD="cargo test" ;;
                go)     TEST_CMD="go test ./..." ;;
                *)      TEST_CMD="pytest" ;;
            esac
        fi
        log_info "Running test suite: ${BOLD}${TEST_CMD} $*${RESET}..."
        eval "${TEST_CMD} $*"
        ;;
    tdd)
        TEST_PATH="${1:-}"
        shift || true
        TDD_CMD="$(get_profile_value "qa.tddCommand" "")"
        if [ -z "${TDD_CMD}" ]; then
            TDD_CMD="pytest {path}"
        fi
        CMD="${TDD_CMD//\{path\}/${TEST_PATH}}"
        log_info "Running TDD cycle: ${BOLD}${CMD} $*${RESET}..."
        eval "${CMD} $*"
        ;;
    lint)
        LINT_CMD="$(get_profile_value "qa.lintCommand" "ruff check . 2>/dev/null || npm run lint 2>/dev/null || echo 'No linter configured'")"
        log_info "Running linter: ${BOLD}${LINT_CMD}${RESET}..."
        eval "${LINT_CMD}"
        ;;
    types)
        TYPE_CMD="$(get_profile_value "qa.typeCheckCommand" "mypy . 2>/dev/null || npm run typecheck 2>/dev/null || echo 'No type checker configured'")"
        log_info "Running type checker: ${BOLD}${TYPE_CMD}${RESET}..."
        eval "${TYPE_CMD}"
        ;;
    scan)
        "${SCRIPT_DIR}/stack-scan.sh" "$@"
        ;;
    all)
        log_info "Running full QA suite (Scan -> Lint -> Types -> Tests)..."
        FAILED_GATES=()

        run_gate() {
            local gate_name="$1"
            shift
            if "$@"; then
                log_success "QA gate passed: ${gate_name}"
            else
                log_error "QA gate failed: ${gate_name}"
                FAILED_GATES+=("${gate_name}")
            fi
        }

        run_gate "scan" "${SCRIPT_DIR}/stack-scan.sh" --diff
        run_gate "lint" "${SCRIPT_DIR}/stack-qa.sh" lint
        run_gate "types" "${SCRIPT_DIR}/stack-qa.sh" types
        run_gate "tests" "${SCRIPT_DIR}/stack-qa.sh" test

        if [ ${#FAILED_GATES[@]} -gt 0 ]; then
            log_error "QA failed. Required gates: ${FAILED_GATES[*]}"
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
