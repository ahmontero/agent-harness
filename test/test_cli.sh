#!/usr/bin/env bash
# ==============================================================================
# agent-harness: test/test_cli.sh
# Automated Test Suite for Agent Harness
# ==============================================================================

set -eo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${TEST_DIR}/.." && pwd)"

echo "=== 1. Testing Shell Scripts Syntax ==="
find "${HARNESS_ROOT}/bin" "${HARNESS_ROOT}/core/scripts" "${HARNESS_ROOT}" -maxdepth 2 -type f \( -name "*.sh" -o -name "harness" -o -name "setup" \) | while read -r script; do
    bash -n "${script}"
    echo "  [PASS] ${script}"
done

echo ""
echo "=== 2. Testing Skills YAML Frontmatter ==="
find "${HARNESS_ROOT}/core/skills" -name "SKILL.md" | while read -r skill; do
    if grep -q "^---" "${skill}" && grep -q "^name:" "${skill}" && grep -q "^description:" "${skill}"; then
        echo "  [PASS] $(basename "$(dirname "${skill}")")"
    else
        echo "  [FAIL] Missing valid frontmatter in ${skill}"
        exit 1
    fi
done

echo ""
echo "=== 2b. Testing Composite Workflow Contracts ==="
SKILL_CATALOG="${HARNESS_ROOT}/core/skills/catalog.json"
if [ ! -f "${SKILL_CATALOG}" ]; then
    echo "  [FAIL] Missing canonical skill catalog"
    exit 1
fi
if [ "$(jq -r '.public | keys | sort | join(" ")' "${SKILL_CATALOG}")" != "fix implement investigate" ]; then
    echo "  [FAIL] Public skill catalog must expose exactly fix, implement, and investigate"
    exit 1
fi
if jq -e '(.public | has("ship")) or (.internal | index("ship") != null)' "${SKILL_CATALOG}" >/dev/null || \
   [ "$(jq -r '.removed | index("ship") != null' "${SKILL_CATALOG}")" != "true" ]; then
    echo "  [FAIL] ship must be removed rather than public or internal"
    exit 1
fi
for workflow in implement fix investigate; do
    workflow_file="${HARNESS_ROOT}/core/skills/${workflow}/SKILL.md"
    if [ ! -f "${workflow_file}" ]; then
        echo "  [FAIL] Missing composite workflow: ${workflow}"
        exit 1
    fi
    for contract_section in "## Workflow Contract" "## Phases" "## Safety Boundary" "## State Anchor"; do
        if ! grep -Fq "${contract_section}" "${workflow_file}"; then
            echo "  [FAIL] Workflow '${workflow}' is missing contract section: ${contract_section}"
            exit 1
        fi
    done
    for receipt_contract in "harness receipt start ${workflow}" "harness receipt phase" "harness receipt finish"; do
        if ! grep -Fq "${receipt_contract}" "${workflow_file}"; then
            echo "  [FAIL] Workflow '${workflow}' is missing receipt integration: ${receipt_contract}"
            exit 1
        fi
    done
done

for primitive in tdd qa review simplify; do
    reference="references/${primitive}.md"
    if ! grep -Fq "${reference}" "${HARNESS_ROOT}/core/skills/implement/SKILL.md"; then
        echo "  [FAIL] implement does not load required private protocol: ${reference}"
        exit 1
    fi
done
for primitive in bug tdd qa review; do
    reference="references/${primitive}.md"
    if ! grep -Fq "${reference}" "${HARNESS_ROOT}/core/skills/fix/SKILL.md"; then
        echo "  [FAIL] fix does not load required private protocol: ${reference}"
        exit 1
    fi
done
if ! grep -Fqi "read-only" "${HARNESS_ROOT}/core/skills/investigate/SKILL.md" || \
   ! grep -Fq "STOP" "${HARNESS_ROOT}/core/skills/investigate/SKILL.md"; then
    echo "  [FAIL] investigate does not enforce its read-only STOP boundary"
    exit 1
fi
echo "  [PASS] composite workflows expose the required contracts and primitives."

echo ""
echo "=== 3. Testing CLI Dispatcher Output ==="
"${HARNESS_ROOT}/bin/harness" --help >/dev/null
echo "  [PASS] harness --help executed successfully."
"${HARNESS_ROOT}/bin/agh" --help >/dev/null
echo "  [PASS] agh --help executed successfully."
"${HARNESS_ROOT}/bin/agent-harness" --help >/dev/null
echo "  [PASS] agent-harness --help executed successfully."

echo ""
echo "=== 4. Testing Context Extraction ==="
CONTEXT_JSON=$("${HARNESS_ROOT}/bin/harness" context --json)
if echo "${CONTEXT_JSON}" | grep -q "branch"; then
    echo "  [PASS] harness context --json produced valid JSON."
else
    echo "  [FAIL] harness context --json output invalid: ${CONTEXT_JSON}"
    exit 1
fi

echo ""
echo "=== 5. Testing Static Landmine Scanner ==="
"${HARNESS_ROOT}/bin/harness" scan --rules "${HARNESS_ROOT}/core/templates/landmines-template.json" --all >/dev/null
echo "  [PASS] harness scan executed successfully."

echo ""
echo "=== 6. Testing Recipe Presets Initialization ==="
TMP_TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_TEST_DIR}"' EXIT

RECIPES=("python-fastapi" "typescript-fullstack" "go-microservices")
for recipe in "${RECIPES[@]}"; do
    TARGET_DIR="${TMP_TEST_DIR}/${recipe}-test"
    mkdir -p "${TARGET_DIR}"
    git -C "${TARGET_DIR}" init -q
    
    # Test installation with recipe
    "${HARNESS_ROOT}/install.sh" --target "${TARGET_DIR}" --recipe "${recipe}" >/dev/null
    
    # Assertions
    if [ -f "${TARGET_DIR}/stack.config.json" ] && [ -f "${TARGET_DIR}/rules/floor.md" ] && [ -f "${TARGET_DIR}/rules/landmines.md" ]; then
        echo "  [PASS] Recipe '${recipe}' initialized cleanly with floor and landmines."
    else
        echo "  [FAIL] Recipe '${recipe}' failed initialization in ${TARGET_DIR}"
        exit 1
    fi
    while IFS= read -r doc_link; do
        if [ -n "${doc_link}" ] && [ ! -f "${TARGET_DIR}/${doc_link}" ]; then
            echo "  [FAIL] Recipe '${recipe}' installed a scanner rule with missing documentation: ${doc_link}"
            exit 1
        fi
    done < <(jq -r '.[].docLink // empty' "${TARGET_DIR}/rules/landmines.json" | sort -u)
done

DEFAULT_TARGET_DIR="${TMP_TEST_DIR}/default-init-test"
mkdir -p "${DEFAULT_TARGET_DIR}"
git -C "${DEFAULT_TARGET_DIR}" init -q
"${HARNESS_ROOT}/install.sh" --target "${DEFAULT_TARGET_DIR}" >/dev/null
for required_file in stack.config.json rules/floor.md rules/landmines.md rules/landmines.json; do
    if [ ! -s "${DEFAULT_TARGET_DIR}/${required_file}" ]; then
        echo "  [FAIL] Default initialization omitted required file: ${required_file}"
        exit 1
    fi
done
while IFS= read -r doc_link; do
    if [ -n "${doc_link}" ] && [ ! -f "${DEFAULT_TARGET_DIR}/${doc_link}" ]; then
        echo "  [FAIL] Default initialization installed a dangling documentation link: ${doc_link}"
        exit 1
    fi
done < <(jq -r '.[].docLink // empty' "${DEFAULT_TARGET_DIR}/rules/landmines.json" | sort -u)
echo "  [PASS] Default initialization includes its complete quality floor."
for runtime_dir in .agents/skills .claude/skills .codex/skills .gemini/skills; do
    installed_count=$(find "${DEFAULT_TARGET_DIR}/${runtime_dir}" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l | tr -d ' ')
    if [ "${installed_count}" -ne 3 ]; then
        echo "  [FAIL] Curated installation exposed ${installed_count} skills in ${runtime_dir}; expected 3"
        exit 1
    fi
    for workflow in implement fix investigate; do
        if [ ! -f "${DEFAULT_TARGET_DIR}/${runtime_dir}/${workflow}/SKILL.md" ]; then
            echo "  [FAIL] Default initialization did not expose '${workflow}' in ${runtime_dir}"
            exit 1
        fi
        while IFS= read -r primitive; do
            if [ ! -f "${DEFAULT_TARGET_DIR}/${runtime_dir}/${workflow}/references/${primitive}.md" ]; then
                echo "  [FAIL] Workflow '${workflow}' omitted private protocol '${primitive}' in ${runtime_dir}"
                exit 1
            fi
        done < <(jq -r --arg workflow "${workflow}" '.public[$workflow][]' "${SKILL_CATALOG}")
    done
    if [ -e "${DEFAULT_TARGET_DIR}/${runtime_dir}/tdd" ] || [ -e "${DEFAULT_TARGET_DIR}/${runtime_dir}/ship" ]; then
        echo "  [FAIL] Curated installation exposed an internal or removed skill in ${runtime_dir}"
        exit 1
    fi
done
echo "  [PASS] Default initialization exposes composite workflows to supported runtimes."

EXPERT_TARGET_DIR="${TMP_TEST_DIR}/expert-init-test"
mkdir -p "${EXPERT_TARGET_DIR}"
git -C "${EXPERT_TARGET_DIR}" init -q
"${HARNESS_ROOT}/install.sh" --target "${EXPERT_TARGET_DIR}" --expert >/dev/null
while IFS= read -r skill; do
    if [ ! -f "${EXPERT_TARGET_DIR}/.codex/skills/${skill}/SKILL.md" ]; then
        echo "  [FAIL] Expert installation omitted skill: ${skill}"
        exit 1
    fi
done < <(jq -r '(.public | keys[]), .internal[]' "${SKILL_CATALOG}")
if [ -e "${EXPERT_TARGET_DIR}/.codex/skills/ship" ]; then
    echo "  [FAIL] Expert installation restored the removed ship skill"
    exit 1
fi
echo "  [PASS] Expert initialization exposes workflows and supported primitives."

mkdir -p "${EXPERT_TARGET_DIR}/.codex/skills/user-owned"
echo "user-owned" > "${EXPERT_TARGET_DIR}/.codex/skills/user-owned/SKILL.md"
ln -s "${HARNESS_ROOT}/core/skills/ship" "${EXPERT_TARGET_DIR}/.codex/skills/ship"
"${HARNESS_ROOT}/install.sh" --target "${EXPERT_TARGET_DIR}" >/dev/null
"${HARNESS_ROOT}/install.sh" --target "${EXPERT_TARGET_DIR}" >/dev/null
if [ -e "${EXPERT_TARGET_DIR}/.codex/skills/tdd" ] || \
   [ -L "${EXPERT_TARGET_DIR}/.codex/skills/ship" ] || \
   [ ! -f "${EXPERT_TARGET_DIR}/.codex/skills/user-owned/SKILL.md" ]; then
    echo "  [FAIL] Curated migration did not safely remove managed primitives or preserve user skills"
    exit 1
fi
if [ "$(find "${EXPERT_TARGET_DIR}/.codex/skills" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l | tr -d ' ')" -ne 4 ]; then
    echo "  [FAIL] Curated migration is not idempotent"
    exit 1
fi
echo "  [PASS] Curated migration is safe and idempotent."

echo ""
echo "=== 7. Testing Fail-Closed QA Aggregation ==="

run_qa_failure_case() {
    local failing_gate="$1"
    local qa_dir="${TMP_TEST_DIR}/qa-${failing_gate}"
    local lint_cmd="echo lint >> gate.log; true"
    local types_cmd="echo types >> gate.log; true"
    local test_cmd="echo test >> gate.log; true"

    mkdir -p "${qa_dir}"
    git -C "${qa_dir}" init -q
    git -C "${qa_dir}" config user.email "tests@agent-harness.local"
    git -C "${qa_dir}" config user.name "Agent Harness Tests"

    cat > "${qa_dir}/rules.json" <<'RULES_EOF'
[
  {
    "id": "TEST-001",
    "name": "Forbidden marker",
    "pattern": "FORBIDDEN_MARKER",
    "fileExtensions": [".txt"],
    "level": "error",
    "message": "Remove the forbidden marker."
  }
]
RULES_EOF
    echo "clean" > "${qa_dir}/tracked.txt"
    git -C "${qa_dir}" add tracked.txt rules.json
    git -C "${qa_dir}" commit -qm "test fixture"

    case "${failing_gate}" in
        scan) echo "FORBIDDEN_MARKER" > "${qa_dir}/tracked.txt" ;;
        lint) lint_cmd="echo lint >> gate.log; false" ;;
        types) types_cmd="echo types >> gate.log; false" ;;
        test) test_cmd="echo test >> gate.log; false" ;;
    esac

    cat > "${qa_dir}/stack.config.json" <<CONFIG_EOF
{
  "project": {"defaultProfile": "backend"},
  "profiles": {
    "backend": {
      "qa": {
        "lintCommand": "${lint_cmd}",
        "typeCheckCommand": "${types_cmd}",
        "testCommand": "${test_cmd}"
      },
      "rules": {"scanner": "./rules.json"}
    }
  }
}
CONFIG_EOF

    if (cd "${qa_dir}" && "${HARNESS_ROOT}/bin/harness" qa all >/dev/null 2>&1); then
        echo "  [FAIL] qa all returned success when ${failing_gate} failed"
        exit 1
    fi

    for gate in lint types test; do
        if ! grep -qx "${gate}" "${qa_dir}/gate.log"; then
            echo "  [FAIL] qa all stopped before running ${gate} after ${failing_gate} failed"
            exit 1
        fi
    done
    echo "  [PASS] qa all propagated ${failing_gate} failure and completed every gate."
}

for gate in scan lint types test; do
    run_qa_failure_case "${gate}"
done

echo ""
echo "=== 8. Testing Delta Spec Verification ==="
SPEC_TEST_DIR="${TMP_TEST_DIR}/spec-verification"
mkdir -p "${SPEC_TEST_DIR}/specs"
git -C "${SPEC_TEST_DIR}" init -q

cat > "${SPEC_TEST_DIR}/specs/delta-valid.md" <<'SPEC_EOF'
# Delta Spec: TEST-1 — valid
## 1. Intent & Context
This change makes a deterministic behavior explicit.
## 2. Requirements & Domain Floor Invariants
- [x] The observable behavior is covered by an automated test.
## 3. Implementation Plan
1. Add the regression test.
## 4. Verification & QA
- Automated test: `bash test/test_cli.sh`
SPEC_EOF

cat > "${SPEC_TEST_DIR}/specs/delta-incomplete.md" <<'SPEC_EOF'
# Delta Spec: TEST-2 — incomplete
## 1. Intent & Context
Missing required sections must be rejected.
SPEC_EOF

cat > "${SPEC_TEST_DIR}/specs/delta-placeholder.md" <<'SPEC_EOF'
# Delta Spec: TEST-3 — placeholder
## 1. Intent & Context
[Brief summary]
## 2. Requirements & Domain Floor Invariants
- [ ] Requirement 1: ...
## 3. Implementation Plan
1. [ ] Implement core logic
## 4. Verification & QA
- Expected outcome: ...
SPEC_EOF

cat > "${SPEC_TEST_DIR}/specs/delta-fake-headings.md" <<'SPEC_EOF'
# Delta Spec: TEST-4 — fake-headings
## 1. Intent & Context
This prose mentions ## 2. Requirements & Domain Floor Invariants without defining the section.
It also mentions ## 3. Implementation Plan and ## 4. Verification & QA inline.
SPEC_EOF

if ! (cd "${SPEC_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" spec verify specs/delta-valid.md >/dev/null); then
    echo "  [FAIL] spec verify rejected a complete spec"
    exit 1
fi

for invalid_spec in specs/delta-incomplete.md specs/delta-placeholder.md specs/delta-fake-headings.md specs/missing.md; do
    if (cd "${SPEC_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" spec verify "${invalid_spec}" >/dev/null 2>&1); then
        echo "  [FAIL] spec verify accepted invalid input: ${invalid_spec}"
        exit 1
    fi
done
echo "  [PASS] spec verify accepts complete specs and rejects invalid inputs."

if ! (cd "${SPEC_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" spec archive payments specs/delta-valid.md >/dev/null); then
    echo "  [FAIL] spec archive rejected a verified spec"
    exit 1
fi
if [ ! -f "${SPEC_TEST_DIR}/specs/archive/payments/delta-valid.md" ] || [ -e "${SPEC_TEST_DIR}/specs/delta-valid.md" ]; then
    echo "  [FAIL] spec archive did not move the verified spec into the module archive"
    exit 1
fi
if (cd "${SPEC_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" spec archive ../unsafe specs/archive/payments/delta-valid.md >/dev/null 2>&1); then
    echo "  [FAIL] spec archive accepted an unsafe module name"
    exit 1
fi
cp "${SPEC_TEST_DIR}/specs/archive/payments/delta-valid.md" "${SPEC_TEST_DIR}/outside-spec.md"
if (cd "${SPEC_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" spec archive payments outside-spec.md >/dev/null 2>&1); then
    echo "  [FAIL] spec archive accepted a spec outside the specs directory"
    exit 1
fi
echo "  [PASS] spec archive moves verified specs and rejects unsafe destinations."

echo ""
echo "=== 9. Testing Repository Dogfooding Rules ==="
for rule_doc in rules/floor.md rules/landmines.md; do
    if [ ! -s "${HARNESS_ROOT}/${rule_doc}" ]; then
        echo "  [FAIL] Missing canonical repository rule: ${rule_doc}"
        exit 1
    fi
done
while IFS= read -r doc_link; do
    if [ -n "${doc_link}" ] && [ ! -f "${HARNESS_ROOT}/${doc_link}" ]; then
        echo "  [FAIL] Scanner rule references missing documentation: ${doc_link}"
        exit 1
    fi
done < <(jq -r '.[].docLink // empty' "${HARNESS_ROOT}/rules/landmines.json" | sort -u)
if [ ! -f "${HARNESS_ROOT}/harness.config.json" ]; then
    echo "  [FAIL] Repository must define local QA commands instead of using config.example.json"
    exit 1
fi
if [ "$(jq -r '.profiles.harness.qa.testCommand' "${HARNESS_ROOT}/harness.config.json")" != "env -u STACK_PROFILE npm test" ] || \
   [ "$(jq -r '.profiles.harness.qa.lintCommand' "${HARNESS_ROOT}/harness.config.json")" != "./setup --verify" ]; then
    echo "  [FAIL] Repository QA configuration does not target its canonical verification commands"
    exit 1
fi
echo "  [PASS] repository provides its canonical floor and landmine documentation."

echo ""
echo "=== 10. Testing Public Workflow Documentation ==="
for documented_contract in \
    "## 🚦 Three Engineering Workflows" \
    "## 🧠 Internal Engineering Protocols" \
    "./setup --global --expert" \
    '`/implement`' \
    '`/fix`' \
    '`/investigate`'; do
    if ! grep -Fq "${documented_contract}" "${HARNESS_ROOT}/README.md"; then
        echo "  [FAIL] README is missing public contract: ${documented_contract}"
        exit 1
    fi
done
if grep -Fq "The 19 Standard Agent Skills" "${HARNESS_ROOT}/README.md" || \
   grep -Fq '<code>/ship' "${HARNESS_ROOT}/README.md"; then
    echo "  [FAIL] README still exposes the legacy skill surface or removed ship workflow"
    exit 1
fi
if ! grep -Fq "harness receipt start" "${HARNESS_ROOT}/README.md" || \
   ! "${HARNESS_ROOT}/bin/harness" --help | grep -Fq "receipt"; then
    echo "  [FAIL] Receipt lifecycle is missing from the public CLI documentation"
    exit 1
fi
if grep -Fq "Install globally with zero dependencies" "${HARNESS_ROOT}/README.md" || \
   grep -Fq "### 1. Zero External Dependencies" "${HARNESS_ROOT}/docs/ARCHITECTURE.md"; then
    echo "  [FAIL] Documentation claims zero external dependencies despite requiring system tooling"
    exit 1
fi
echo "  [PASS] README presents the workflow surface and accurate dependency model."

echo ""
echo "=== 11. Testing Compatibility Evidence Contract ==="
COMPAT_RUNNER="${HARNESS_ROOT}/test/e2e/test_install_matrix.sh"
COMPAT_REPORT="${TMP_TEST_DIR}/compatibility-target-default.json"
if [ ! -x "${COMPAT_RUNNER}" ]; then
    echo "  [FAIL] Missing executable compatibility runner: test/e2e/test_install_matrix.sh"
    exit 1
fi
"${COMPAT_RUNNER}" --scope target --mode default --report "${COMPAT_REPORT}" >/dev/null
if ! jq -e '
    .schemaVersion == 1 and
    .scope == "target" and
    .mode == "default" and
    .status == "passed" and
    (.os | type == "string" and length > 0) and
    (.verifiedContracts | sort == ["agents", "claude", "codex", "cursor", "gemini"])
' "${COMPAT_REPORT}" >/dev/null; then
    echo "  [FAIL] Compatibility runner did not emit the required evidence schema"
    exit 1
fi
BLOCKED_REPORT_PARENT="${TMP_TEST_DIR}/compatibility-report-parent"
printf '%s\n' "not-a-directory" > "${BLOCKED_REPORT_PARENT}"
if "${COMPAT_RUNNER}" --scope target --mode default --report "${BLOCKED_REPORT_PARENT}/result.json" >/dev/null 2>&1; then
    echo "  [FAIL] Compatibility runner reported success after evidence output failed"
    exit 1
fi
if "${COMPAT_RUNNER}" --scope unsupported --mode default >/dev/null 2>&1 || \
   "${COMPAT_RUNNER}" --scope target --mode unsupported >/dev/null 2>&1 || \
   "${COMPAT_RUNNER}" --report "${TMP_TEST_DIR}/ambiguous.json" >/dev/null 2>&1; then
    echo "  [FAIL] Compatibility runner accepted an invalid or ambiguous matrix request"
    exit 1
fi
for evidence_file in docs/COMPATIBILITY.md .github/workflows/compatibility.yml; do
    if [ ! -s "${HARNESS_ROOT}/${evidence_file}" ]; then
        echo "  [FAIL] Missing compatibility evidence asset: ${evidence_file}"
        exit 1
    fi
done
for matrix_contract in \
    "os: [ubuntu-latest, macos-latest]" \
    "scope: [target, global]" \
    "mode: [default, expert]"; do
    if ! grep -Fq "${matrix_contract}" "${HARNESS_ROOT}/.github/workflows/compatibility.yml"; then
        echo "  [FAIL] Compatibility workflow is missing matrix contract: ${matrix_contract}"
        exit 1
    fi
done
if ! grep -Fq "docs/COMPATIBILITY.md" "${HARNESS_ROOT}/README.md"; then
    echo "  [FAIL] README does not link to the compatibility evidence contract"
    exit 1
fi
echo "  [PASS] compatibility runner exposes a machine-readable evidence contract."

echo ""
echo "=== 12. Testing Local Execution Receipts ==="
RECEIPT_TEST_DIR="${TMP_TEST_DIR}/receipt-test"
mkdir -p "${RECEIPT_TEST_DIR}"
git -C "${RECEIPT_TEST_DIR}" init -q
git -C "${RECEIPT_TEST_DIR}" config user.email "tests@agent-harness.local"
git -C "${RECEIPT_TEST_DIR}" config user.name "Agent Harness Tests"
echo "fixture" > "${RECEIPT_TEST_DIR}/fixture.txt"
git -C "${RECEIPT_TEST_DIR}" add fixture.txt
git -C "${RECEIPT_TEST_DIR}" commit -qm "receipt fixture"

RUN_ID="$(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start implement --issue AH-3)"
if ! [[ "${RUN_ID}" =~ ^implement-[A-Za-z0-9._-]+$ ]]; then
    echo "  [FAIL] receipt start did not return a safe run ID: ${RUN_ID}"
    exit 1
fi
RECEIPT_FILE="${RECEIPT_TEST_DIR}/.git/agent-harness/runs/${RUN_ID}.jsonl"
if [ ! -f "${RECEIPT_FILE}" ] || [ -e "${RECEIPT_TEST_DIR}/.harness" ]; then
    echo "  [FAIL] receipt was not stored exclusively under Git metadata"
    exit 1
fi

(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase "${RUN_ID}" tdd started >/dev/null)
(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase "${RUN_ID}" tdd passed >/dev/null)
(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt finish "${RUN_ID}" completed >/dev/null)

if ! jq -s -e '
    length == 4 and
    .[0].schemaVersion == 1 and
    .[0].workflow == "implement" and
    .[0].event == "workflow_started" and
    .[0].issue == "AH-3" and
    .[1].event == "phase" and .[1].phase == "tdd" and .[1].status == "started" and
    .[2].status == "passed" and
    .[3].event == "workflow_finished" and .[3].outcome == "completed" and
    ([.[] | keys[]] | map(test("prompt|code|secret|evidence|path"; "i")) | any | not)
' "${RECEIPT_FILE}" >/dev/null; then
    echo "  [FAIL] receipt lifecycle did not produce the closed privacy-safe schema"
    exit 1
fi

if (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase "${RUN_ID}" qa passed >/dev/null 2>&1) || \
   (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt finish "${RUN_ID}" completed >/dev/null 2>&1); then
    echo "  [FAIL] receipt accepted an event after its terminal event"
    exit 1
fi

if (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start deploy >/dev/null 2>&1) || \
   (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start fix --issue "unsafe issue" >/dev/null 2>&1) || \
   (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase ../escape qa passed >/dev/null 2>&1) || \
   (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase missing qa unknown >/dev/null 2>&1) || \
   (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt finish missing successful >/dev/null 2>&1); then
    echo "  [FAIL] receipt accepted an unsupported or unsafe token"
    exit 1
fi

VALIDATION_RUN_ID="$(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start investigate)"
if (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase "${VALIDATION_RUN_ID}" secret_key passed >/dev/null 2>&1); then
    echo "  [FAIL] receipt accepted a non-allowlisted phase token"
    exit 1
fi
(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt finish "${VALIDATION_RUN_ID}" cancelled >/dev/null)

RACE_RUN_ID="$(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start fix)"
for i in 1 2; do
    (
        if (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt finish "${RACE_RUN_ID}" completed >/dev/null 2>&1); then
            echo success
        else
            echo rejected
        fi
    ) > "${TMP_TEST_DIR}/receipt-finish-${i}" &
done
wait
RACE_RECEIPT_FILE="${RECEIPT_TEST_DIR}/.git/agent-harness/runs/${RACE_RUN_ID}.jsonl"
if [ "$(grep -l '^success$' "${TMP_TEST_DIR}"/receipt-finish-* | wc -l | tr -d ' ')" -ne 1 ] || \
   [ "$(jq -s '[.[] | select(.event == "workflow_finished")] | length' "${RACE_RECEIPT_FILE}")" -ne 1 ]; then
    echo "  [FAIL] concurrent finish attempts produced multiple terminal events"
    exit 1
fi

RECEIPTS_TEST_STORE="${RECEIPT_TEST_DIR}/.git/agent-harness/runs"
cat > "${TMP_TEST_DIR}/outside-receipt.jsonl" <<'RECEIPT_EOF'
{"schemaVersion":1,"runId":"linked","timestamp":"2026-01-01T00:00:00Z","workflow":"implement","event":"workflow_started","issue":null,"profile":"test","branch":"main"}
RECEIPT_EOF
ln -s "${TMP_TEST_DIR}/outside-receipt.jsonl" "${RECEIPTS_TEST_STORE}/linked.jsonl"
cat > "${RECEIPTS_TEST_STORE}/tampered.jsonl" <<'RECEIPT_EOF'
{"schemaVersion":1,"runId":"different","timestamp":"2026-01-01T00:00:00Z","workflow":"implement","event":"workflow_started","issue":null,"profile":"test","branch":"main"}
RECEIPT_EOF
if (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase linked qa passed >/dev/null 2>&1) || \
   (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase tampered qa passed >/dev/null 2>&1); then
    echo "  [FAIL] receipt followed a symlink or accepted tampered run identity"
    exit 1
fi

for i in 1 2 3 4 5 6 7 8; do
    (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start fix > "${TMP_TEST_DIR}/receipt-id-${i}") &
done
wait
if [ "$(cat "${TMP_TEST_DIR}"/receipt-id-* | sort -u | wc -l | tr -d ' ')" -ne 8 ]; then
    echo "  [FAIL] concurrent receipt starts did not produce unique run IDs"
    exit 1
fi

LINKED_RECEIPT_DIR="${TMP_TEST_DIR}/receipt-linked"
git -C "${RECEIPT_TEST_DIR}" worktree add -q -b receipt-linked "${LINKED_RECEIPT_DIR}"
LINKED_RUN_ID="$(cd "${LINKED_RECEIPT_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start investigate)"
if [ ! -f "${RECEIPT_TEST_DIR}/.git/agent-harness/runs/${LINKED_RUN_ID}.jsonl" ] || \
   [ -d "${LINKED_RECEIPT_DIR}/.git/agent-harness" ]; then
    echo "  [FAIL] linked worktree did not use the repository's shared receipt store"
    exit 1
fi
echo "  [PASS] receipts are private, validated, terminal, concurrent-safe, and worktree-shared."

echo ""
echo "=== 13. Testing Remote Installer Bootstrap ==="
if ! bash "${HARNESS_ROOT}/test/test_remote_install.sh" >/dev/null; then
    echo "  [FAIL] install.sh cannot bootstrap a persistent installation from stdin"
    exit 1
fi
echo "  [PASS] stdin bootstrap installs globally from a persistent checkout."

echo ""
echo "All automated tests passed successfully! [100%]"
