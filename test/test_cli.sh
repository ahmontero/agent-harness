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
    expected_name="harness-$(basename "$(dirname "${skill}")")"
    if grep -q "^---" "${skill}" && grep -qx "name: ${expected_name}" "${skill}" && grep -q "^description:" "${skill}"; then
        echo "  [PASS] $(basename "$(dirname "${skill}")")"
    else
        echo "  [FAIL] Missing namespaced frontmatter in ${skill}; expected ${expected_name}"
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
if [ "$(jq -r '.namespace // empty' "${SKILL_CATALOG}")" != "harness" ]; then
    echo "  [FAIL] Skill catalog must publish through the harness namespace"
    exit 1
fi
if [ "$(jq -r '.public | keys | sort | join(" ")' "${SKILL_CATALOG}")" != "fix implement investigate orchestrate" ]; then
    echo "  [FAIL] Public skill catalog must expose exactly fix, implement, investigate, and orchestrate"
    exit 1
fi
if [ "$(jq -r '.runtimes.orchestrate | join(" ")' "${SKILL_CATALOG}")" != "claude" ]; then
    echo "  [FAIL] orchestrate must be gated to the claude runtime"
    exit 1
fi
while IFS= read -r gated_workflow; do
    if ! jq -e --arg workflow "${gated_workflow}" '.public | has($workflow)' "${SKILL_CATALOG}" >/dev/null; then
        echo "  [FAIL] runtimes names a workflow absent from public: ${gated_workflow}"
        exit 1
    fi
done < <(jq -r '.runtimes // {} | keys[]' "${SKILL_CATALOG}")
if jq -e '(.public | has("ship")) or (.internal | index("ship") != null)' "${SKILL_CATALOG}" >/dev/null || \
   [ "$(jq -r '.removed | index("ship") != null' "${SKILL_CATALOG}")" != "true" ]; then
    echo "  [FAIL] ship must be removed rather than public or internal"
    exit 1
fi
for workflow in implement fix investigate orchestrate; do
    workflow_file="${HARNESS_ROOT}/core/skills/${workflow}/SKILL.md"
    if [ ! -f "${workflow_file}" ]; then
        echo "  [FAIL] Missing composite workflow: ${workflow}"
        exit 1
    fi
    if ! grep -qx "name: harness-${workflow}" "${workflow_file}"; then
        echo "  [FAIL] Composite workflow '${workflow}' is missing namespaced frontmatter"
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
TMP_TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_TEST_DIR}"' EXIT

CONTEXT_JSON=$("${HARNESS_ROOT}/bin/harness" context --json)
if echo "${CONTEXT_JSON}" | grep -q "branch"; then
    echo "  [PASS] harness context --json produced valid JSON."
else
    echo "  [FAIL] harness context --json output invalid: ${CONTEXT_JSON}"
    exit 1
fi

CONTEXT_IMPLEMENTER=$(echo "${CONTEXT_JSON}" | jq -r '.orchestrateModels.implementer')
CONTEXT_REVIEWER=$(echo "${CONTEXT_JSON}" | jq -r '.orchestrateModels.reviewer')
if [ -z "${CONTEXT_IMPLEMENTER}" ] || [ "${CONTEXT_IMPLEMENTER}" = "null" ] || \
   [ -z "${CONTEXT_REVIEWER}" ] || [ "${CONTEXT_REVIEWER}" = "null" ] || \
   [ "${CONTEXT_IMPLEMENTER}" = "${CONTEXT_REVIEWER}" ]; then
    echo "  [FAIL] harness context --json must expose distinct orchestrate models: ${CONTEXT_JSON}"
    exit 1
fi
echo "  [PASS] harness context --json exposes per-role orchestrate models."

CONTEXT_DEFAULT_DIR="${TMP_TEST_DIR}/context-defaults"
mkdir -p "${CONTEXT_DEFAULT_DIR}"
git -C "${CONTEXT_DEFAULT_DIR}" init -q
cat > "${CONTEXT_DEFAULT_DIR}/harness.config.json" <<'CONTEXT_CONFIG_EOF'
{
  "project": { "name": "context-defaults", "defaultProfile": "plain" },
  "profiles": { "plain": { "displayName": "Plain" } }
}
CONTEXT_CONFIG_EOF
DEFAULT_CONTEXT_JSON=$(cd "${CONTEXT_DEFAULT_DIR}" && STACK_PROFILE=plain "${HARNESS_ROOT}/bin/harness" context --json)
if [ "$(echo "${DEFAULT_CONTEXT_JSON}" | jq -r '.orchestrateModels.implementer')" != "sonnet" ] || \
   [ "$(echo "${DEFAULT_CONTEXT_JSON}" | jq -r '.orchestrateModels.reviewer')" != "opus" ]; then
    echo "  [FAIL] A profile without an orchestrate block must fall back to sonnet and opus: ${DEFAULT_CONTEXT_JSON}"
    exit 1
fi
echo "  [PASS] Orchestrate model defaults apply to a profile with no orchestrate block."

echo ""
echo "=== 5. Testing Static Landmine Scanner ==="
"${HARNESS_ROOT}/bin/harness" scan --rules "${HARNESS_ROOT}/core/templates/landmines-template.json" --all >/dev/null
echo "  [PASS] harness scan executed successfully."

echo ""
echo "=== 6. Testing Recipe Presets Initialization ==="
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
for runtime in agents claude codex gemini; do
    runtime_dir=".${runtime}/skills"
    expected_count=0
    while IFS= read -r workflow; do
        published_workflow="harness-${workflow}"
        if jq -e --arg workflow "${workflow}" --arg runtime "${runtime}" \
            'if (.runtimes // {}) | has($workflow) then (.runtimes[$workflow] | index($runtime)) != null else true end' \
            "${SKILL_CATALOG}" >/dev/null; then
            expected_count=$((expected_count + 1))
            if [ ! -f "${DEFAULT_TARGET_DIR}/${runtime_dir}/${published_workflow}/SKILL.md" ]; then
                echo "  [FAIL] Default initialization did not expose '${published_workflow}' in ${runtime_dir}"
                exit 1
            fi
            if ! grep -qx "name: ${published_workflow}" "${DEFAULT_TARGET_DIR}/${runtime_dir}/${published_workflow}/SKILL.md"; then
                echo "  [FAIL] Installed workflow metadata does not match '${published_workflow}' in ${runtime_dir}"
                exit 1
            fi
            while IFS= read -r primitive; do
                if [ ! -f "${DEFAULT_TARGET_DIR}/${runtime_dir}/${published_workflow}/references/${primitive}.md" ]; then
                    echo "  [FAIL] Workflow '${workflow}' omitted private protocol '${primitive}' in ${runtime_dir}"
                    exit 1
                fi
            done < <(jq -r --arg workflow "${workflow}" '.public[$workflow][]' "${SKILL_CATALOG}")
        elif [ -e "${DEFAULT_TARGET_DIR}/${runtime_dir}/${published_workflow}" ]; then
            echo "  [FAIL] Gated workflow '${published_workflow}' leaked into ${runtime_dir}"
            exit 1
        fi
    done < <(jq -r '.public | keys[]' "${SKILL_CATALOG}")

    installed_count=$(find "${DEFAULT_TARGET_DIR}/${runtime_dir}" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l | tr -d ' ')
    if [ "${installed_count}" -ne "${expected_count}" ]; then
        echo "  [FAIL] Curated installation exposed ${installed_count} skills in ${runtime_dir}; expected ${expected_count}"
        exit 1
    fi
    if [ -e "${DEFAULT_TARGET_DIR}/${runtime_dir}/implement" ] || \
       [ -e "${DEFAULT_TARGET_DIR}/${runtime_dir}/tdd" ] || \
       [ -e "${DEFAULT_TARGET_DIR}/${runtime_dir}/ship" ] || \
       [ -e "${DEFAULT_TARGET_DIR}/${runtime_dir}/harness-tdd" ] || \
       [ -e "${DEFAULT_TARGET_DIR}/${runtime_dir}/harness-ship" ]; then
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
    published_skill="harness-${skill}"
    if jq -e --arg workflow "${skill}" \
        'if (.runtimes // {}) | has($workflow) then (.runtimes[$workflow] | index("codex")) != null else true end' \
        "${SKILL_CATALOG}" >/dev/null; then
        if [ ! -f "${EXPERT_TARGET_DIR}/.codex/skills/${published_skill}/SKILL.md" ]; then
            echo "  [FAIL] Expert installation omitted skill: ${published_skill}"
            exit 1
        fi
        if ! grep -qx "name: ${published_skill}" "${EXPERT_TARGET_DIR}/.codex/skills/${published_skill}/SKILL.md"; then
            echo "  [FAIL] Expert skill metadata does not match: ${published_skill}"
            exit 1
        fi
    elif [ -e "${EXPERT_TARGET_DIR}/.codex/skills/${published_skill}" ]; then
        echo "  [FAIL] Gated workflow leaked into expert codex surface: ${published_skill}"
        exit 1
    fi
done < <(jq -r '(.public | keys[]), .internal[]' "${SKILL_CATALOG}")
if find "${EXPERT_TARGET_DIR}/.codex/skills" -mindepth 1 -maxdepth 1 ! -name 'harness-*' -print -quit | grep -q . || \
   [ -e "${EXPERT_TARGET_DIR}/.codex/skills/harness-ship" ]; then
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
   [ -e "${EXPERT_TARGET_DIR}/.codex/skills/harness-tdd" ] || \
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

FAILED_CLEANUP_TARGET="${TMP_TEST_DIR}/failed-cleanup-test"
FAILED_CLEANUP_BIN="${TMP_TEST_DIR}/failed-cleanup-bin"
mkdir -p "${FAILED_CLEANUP_TARGET}/.codex/skills" "${FAILED_CLEANUP_BIN}"
ln -s "${HARNESS_ROOT}/core/skills/tdd" "${FAILED_CLEANUP_TARGET}/.codex/skills/tdd"
cat > "${FAILED_CLEANUP_BIN}/unlink" <<'FAILED_UNLINK_EOF'
#!/usr/bin/env bash
exit 1
FAILED_UNLINK_EOF
chmod +x "${FAILED_CLEANUP_BIN}/unlink"
if PATH="${FAILED_CLEANUP_BIN}:${PATH}" "${HARNESS_ROOT}/install.sh" --target "${FAILED_CLEANUP_TARGET}" >/dev/null 2>&1; then
    echo "  [FAIL] Installer reported success after managed skill cleanup failed"
    exit 1
fi
echo "  [PASS] Managed skill cleanup fails closed."

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

mkdir -p "${SPEC_TEST_DIR}/specs/delta-not-a-file.md"
SPEC_STATUS_OUTPUT="$(cd "${SPEC_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" spec status 2>/dev/null)"
if printf '%s\n' "${SPEC_STATUS_OUTPUT}" | grep -q "specs/archive/"; then
    echo "  [FAIL] spec status listed an archived spec as active"
    exit 1
fi
if printf '%s\n' "${SPEC_STATUS_OUTPUT}" | grep -q "delta-not-a-file.md"; then
    echo "  [FAIL] spec status listed a directory as an active spec"
    exit 1
fi
if ! printf '%s\n' "${SPEC_STATUS_OUTPUT}" | grep -q "delta-incomplete.md"; then
    echo "  [FAIL] spec status did not list an active spec"
    exit 1
fi
rmdir "${SPEC_TEST_DIR}/specs/delta-not-a-file.md"
echo "  [PASS] spec status lists active specs and excludes archived specs and directories."

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
    "## 🚦 Engineering Workflows" \
    "## 🧠 Internal Engineering Protocols" \
    "./setup --global --expert" \
    '`/harness-implement`' \
    '`/harness-fix`' \
    '`/harness-investigate`' \
    '`/harness-orchestrate`'; do
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
    .schemaVersion == 2 and
    .scope == "target" and
    .mode == "default" and
    .status == "passed" and
    .runtimeGating == true and
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

ORCHESTRATE_RUN_ID="$(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start orchestrate --issue AH-7)"
(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase "${ORCHESTRATE_RUN_ID}" dispatch passed >/dev/null)
(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase "${ORCHESTRATE_RUN_ID}" review passed >/dev/null)
if (cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt phase "${ORCHESTRATE_RUN_ID}" tdd passed >/dev/null 2>&1); then
    echo "  [FAIL] receipt accepted an implement phase token for orchestrate"
    exit 1
fi
(cd "${RECEIPT_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt finish "${ORCHESTRATE_RUN_ID}" completed >/dev/null)
echo "  [PASS] orchestrate receipts accept their own phase tokens and reject foreign ones."

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
echo "=== 14. Testing Bounded Review Ledger ==="
LEDGER_TEST_DIR="${TMP_TEST_DIR}/ledger-test"
mkdir -p "${LEDGER_TEST_DIR}"
git -C "${LEDGER_TEST_DIR}" init -q
git -C "${LEDGER_TEST_DIR}" config user.email "tests@agent-harness.local"
git -C "${LEDGER_TEST_DIR}" config user.name "Agent Harness Tests"
echo "fixture" > "${LEDGER_TEST_DIR}/fixture.txt"
git -C "${LEDGER_TEST_DIR}" add fixture.txt
git -C "${LEDGER_TEST_DIR}" commit -qm "ledger fixture"

LEDGER_RUN_ID="$(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start implement --issue AH-4)"
(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger start "${LEDGER_RUN_ID}" >/dev/null)
LEDGER_FILE="${LEDGER_TEST_DIR}/.git/agent-harness/ledgers/${LEDGER_RUN_ID}.md"
if [ ! -f "${LEDGER_FILE}" ] || [ -e "${LEDGER_TEST_DIR}/.agent-harness" ]; then
    echo "  [FAIL] ledger was not stored exclusively under Git metadata"
    exit 1
fi
if [ "$(head -n 1 "${LEDGER_FILE}")" != "# Harness ledger — run: ${LEDGER_RUN_ID}" ]; then
    echo "  [FAIL] ledger does not carry its run identity on the first line"
    exit 1
fi

(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger start "${LEDGER_RUN_ID}" >/dev/null)
if [ "$(wc -l < "${LEDGER_FILE}" | tr -d ' ')" -ne 1 ]; then
    echo "  [FAIL] repeating ledger start was not idempotent"
    exit 1
fi

(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${LEDGER_RUN_ID}" phase "tdd passed" >/dev/null)
(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${LEDGER_RUN_ID}" ruling "first ruling" >/dev/null)
(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${LEDGER_RUN_ID}" deferred "a minor finding" >/dev/null)
(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${LEDGER_RUN_ID}" parked "second ruling" >/dev/null)
(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${LEDGER_RUN_ID}" complete "third ruling is not one" >/dev/null)

if ! grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z +phase +tdd passed$' "${LEDGER_FILE}"; then
    echo "  [FAIL] ledger append did not record a UTC-timestamped kinded line"
    exit 1
fi

LEDGER_SHOW="$(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger show "${LEDGER_RUN_ID}")"
if [ "$(printf '%s\n' "${LEDGER_SHOW}" | grep -c .)" -ne 6 ]; then
    echo "  [FAIL] ledger show did not print the header and every appended line"
    exit 1
fi

LEDGER_RULINGS="$(cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger rulings "${LEDGER_RUN_ID}")"
if [ "$(printf '%s\n' "${LEDGER_RULINGS}" | grep -c .)" -ne 2 ] || \
   printf '%s\n' "${LEDGER_RULINGS}" | grep -q "a minor finding" || \
   [ "$(printf '%s\n' "${LEDGER_RULINGS}" | grep -n "first ruling" | cut -d: -f1)" != "1" ] || \
   [ "$(printf '%s\n' "${LEDGER_RULINGS}" | grep -n "second ruling" | cut -d: -f1)" != "2" ]; then
    echo "  [FAIL] ledger rulings did not return only ruling and parked lines in recorded order"
    exit 1
fi

LEDGER_OVERSIZED="$(head -c 513 < /dev/zero | tr '\0' 'a')"
if (cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${LEDGER_RUN_ID}" note "unsupported kind" >/dev/null 2>&1) || \
   (cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${LEDGER_RUN_ID}" ruling "${LEDGER_OVERSIZED}" >/dev/null 2>&1) || \
   (cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger start "../escape" >/dev/null 2>&1) || \
   (cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger start "unsafe run id" >/dev/null 2>&1) || \
   (cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append missing ruling "no ledger here" >/dev/null 2>&1) || \
   (cd "${LEDGER_TEST_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger show missing >/dev/null 2>&1); then
    echo "  [FAIL] ledger accepted an unsupported kind, oversized text, unsafe run ID, or missing ledger"
    exit 1
fi

LINKED_LEDGER_DIR="${TMP_TEST_DIR}/ledger-linked"
git -C "${LEDGER_TEST_DIR}" worktree add -q -b ledger-linked "${LINKED_LEDGER_DIR}"
LINKED_LEDGER_RUN_ID="$(cd "${LINKED_LEDGER_DIR}" && "${HARNESS_ROOT}/bin/harness" receipt start investigate)"
(cd "${LINKED_LEDGER_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger start "${LINKED_LEDGER_RUN_ID}" >/dev/null)
if [ ! -f "${LEDGER_TEST_DIR}/.git/agent-harness/ledgers/${LINKED_LEDGER_RUN_ID}.md" ] || \
   [ -d "${LINKED_LEDGER_DIR}/.git/agent-harness" ]; then
    echo "  [FAIL] linked worktree did not use the repository's shared ledger store"
    exit 1
fi
echo "  [PASS] ledgers are private, validated, append-only, ruling-filtered, and worktree-shared."
echo ""
echo "=== 15. Testing Loop Stagnation Breaker ==="
STAGNATION_DIR="${TMP_TEST_DIR}/stagnation-test"
mkdir -p "${STAGNATION_DIR}"
git -C "${STAGNATION_DIR}" init -q
git -C "${STAGNATION_DIR}" config user.email "tests@agent-harness.local"
git -C "${STAGNATION_DIR}" config user.name "Agent Harness Tests"
echo "fixture" > "${STAGNATION_DIR}/fixture.txt"
git -C "${STAGNATION_DIR}" add fixture.txt
git -C "${STAGNATION_DIR}" commit -qm "stagnation fixture"

cat > "${STAGNATION_DIR}/harness.config.json" <<'STAGNATION_CONFIG_EOF'
{
  "project": { "name": "stagnation-fixture", "defaultProfile": "loose" },
  "profiles": {
    "loose": { "displayName": "Default threshold" },
    "patient": { "displayName": "Raised threshold", "loop": { "stagnationThreshold": 3 } },
    "impatient": { "displayName": "Rejected threshold", "loop": { "stagnationThreshold": 1 } },
    "bogus": { "displayName": "Non-integer threshold", "loop": { "stagnationThreshold": "soon" } }
  }
}
STAGNATION_CONFIG_EOF

# Two failures differing only in timestamp, absolute path, line and column, and long numeric ID.
STAGNATION_FAIL_A="$(printf 'FAIL test_widget at 2026-09-09T10:11:12Z\n  /Users/someone/repo/src/widget.py:42:7: AssertionError\n  request id 1234567890')"
STAGNATION_FAIL_B="$(printf 'FAIL test_widget at 2026-01-02T03:04:05Z\n  /home/other/checkout/src/widget.py:99:2: AssertionError\n  request id 9876543210')"
STAGNATION_FAIL_C='FAIL test_gadget: TypeError on None'

stagnation_signature() {
    printf '%s' "$1" | (cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger signature)
}

# Signs from inside <dir>, so the caller controls which repository the normalizer resolves.
stagnation_signature_in() {
    printf '%s' "$2" | (cd "$1" && "${HARNESS_ROOT}/bin/harness" ledger signature)
}

# stagnation_failure <profile> <run_id> <text> [label] -> prints "<exit code> <stdout>"
stagnation_failure() {
    local profile="$1" run_id="$2" text="$3" out code
    set +e
    if [ "$#" -ge 4 ]; then
        out="$(printf '%s' "${text}" | (cd "${STAGNATION_DIR}" && STACK_PROFILE="${profile}" "${HARNESS_ROOT}/bin/harness" ledger failure "${run_id}" "$4" 2>/dev/null))"
    else
        out="$(printf '%s' "${text}" | (cd "${STAGNATION_DIR}" && STACK_PROFILE="${profile}" "${HARNESS_ROOT}/bin/harness" ledger failure "${run_id}" 2>/dev/null))"
    fi
    code=$?
    set -e
    printf '%s %s' "${code}" "${out}"
}

stagnation_open_run() {
    local run_id
    run_id="$(cd "${STAGNATION_DIR}" && STACK_PROFILE="$1" "${HARNESS_ROOT}/bin/harness" receipt start implement --issue AH-8)"
    (cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger start "${run_id}" >/dev/null)
    printf '%s' "${run_id}"
}

SIG_A="$(stagnation_signature "${STAGNATION_FAIL_A}")"
if ! printf '%s' "${SIG_A}" | grep -Eq '^[0-9a-f]{12}$'; then
    echo "  [FAIL] ledger signature did not print a 12-character lowercase hex digest"
    exit 1
fi
if [ "${SIG_A}" != "$(stagnation_signature "${STAGNATION_FAIL_A}")" ]; then
    echo "  [FAIL] ledger signature was not deterministic for one input"
    exit 1
fi

# The normalization ruleset is asserted independently: the expected normalized form is
# written by hand here, so a drifting pipeline changes the digest and fails this case on
# either CI runner rather than agreeing with itself.
STAGNATION_EXPECTED_NORMAL='FAIL test_widget at <timestamp> <path>/widget.py:<line>: AssertionError request id <id>'
STAGNATION_EXPECTED_SIG="$(printf '%s' "${STAGNATION_EXPECTED_NORMAL}" | git hash-object --stdin | cut -c1-12)"
if [ "${SIG_A}" != "${STAGNATION_EXPECTED_SIG}" ]; then
    echo "  [FAIL] signature does not match the documented normalization of the fixed corpus"
    exit 1
fi

if [ "${SIG_A}" != "$(stagnation_signature "${STAGNATION_FAIL_B}")" ]; then
    echo "  [FAIL] signature did not scrub timestamps, absolute paths, line numbers, and long IDs"
    exit 1
fi
if [ "${SIG_A}" = "$(stagnation_signature "${STAGNATION_FAIL_C}")" ]; then
    echo "  [FAIL] signature collapsed two materially different failures"
    exit 1
fi

if (printf '' | (cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger signature) >/dev/null 2>&1) || \
   (printf '   \n\t\n' | (cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger signature) >/dev/null 2>&1); then
    echo "  [FAIL] ledger signature accepted empty or whitespace-only input"
    exit 1
fi

# One failure in one file must sign identically regardless of which checkout produced the
# capture: this worktree, a colleague's clone, a CI runner's temp directory. A rule that
# gave the signing repository's own root a distinct token would break exactly this, and it
# is the reason no such rule exists. Neither root below contains a space, which is the
# documented limit of a whitespace-delimited path rule.
STAGNATION_OTHER_DIR="${TMP_TEST_DIR}/other-checkout"
mkdir -p "${STAGNATION_OTHER_DIR}"
git -C "${STAGNATION_OTHER_DIR}" init -q
git -C "${STAGNATION_OTHER_DIR}" config user.email "tests@agent-harness.local"
git -C "${STAGNATION_OTHER_DIR}" config user.name "Agent Harness Tests"
echo "fixture" > "${STAGNATION_OTHER_DIR}/fixture.txt"
git -C "${STAGNATION_OTHER_DIR}" add fixture.txt
git -C "${STAGNATION_OTHER_DIR}" commit -qm "second checkout fixture"
STAGNATION_HERE="$(printf 'FAIL test_total at 2026-09-09T21:04:11Z\n  %s/src/widget.py:118:9: AssertionError: 41 != 42\n  trace 1739284410' "${STAGNATION_OTHER_DIR}")"
STAGNATION_THERE="$(printf 'FAIL test_total at 2026-09-10T02:57:03Z\n  /tmp/ci-runner/checkout/src/widget.py:120:4: AssertionError: 41 != 42\n  trace 9902244188')"
if [ "$(stagnation_signature_in "${STAGNATION_OTHER_DIR}" "${STAGNATION_HERE}")" != \
     "$(stagnation_signature_in "${STAGNATION_OTHER_DIR}" "${STAGNATION_THERE}")" ]; then
    echo "  [FAIL] one failure signed two ways depending on which checkout captured it"
    exit 1
fi

STAGNATION_RUN="$(stagnation_open_run loose)"
STAGNATION_LEDGER="${STAGNATION_DIR}/.git/agent-harness/ledgers/${STAGNATION_RUN}.md"
if [ "$(stagnation_failure loose "${STAGNATION_RUN}" "${STAGNATION_FAIL_A}")" != "0 continue" ]; then
    echo "  [FAIL] the first failure of a run did not report continue on exit 0"
    exit 1
fi
if ! grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z +failure +sig:${SIG_A}$" "${STAGNATION_LEDGER}"; then
    echo "  [FAIL] ledger failure did not append a signature-only kinded line"
    exit 1
fi
if grep -q "AssertionError\|widget.py\|someone" "${STAGNATION_LEDGER}"; then
    echo "  [FAIL] verifier output leaked into the ledger"
    exit 1
fi

if [ "$(stagnation_failure loose "${STAGNATION_RUN}" "${STAGNATION_FAIL_C}" "round 2/3 — different failure")" != "0 continue" ]; then
    echo "  [FAIL] a differing failure did not report continue"
    exit 1
fi
if ! grep -Eq "failure +sig:$(stagnation_signature "${STAGNATION_FAIL_C}") — round 2/3 — different failure$" "${STAGNATION_LEDGER}"; then
    echo "  [FAIL] ledger failure did not record its optional label"
    exit 1
fi

# An intervening phase line must not reset the failure history.
STAGNATION_REPEAT_RUN="$(stagnation_open_run loose)"
if [ "$(stagnation_failure loose "${STAGNATION_REPEAT_RUN}" "${STAGNATION_FAIL_A}")" != "0 continue" ]; then
    echo "  [FAIL] the first failure of the repeat run did not report continue"
    exit 1
fi
(cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${STAGNATION_REPEAT_RUN}" phase "round 1/3 (0 addressed, 2 open)" >/dev/null)
if [ "$(stagnation_failure loose "${STAGNATION_REPEAT_RUN}" "${STAGNATION_FAIL_B}")" != "3 stagnant" ]; then
    echo "  [FAIL] two equivalent failures across a phase line did not report stagnant on exit 3"
    exit 1
fi

# A raised threshold must delay the decision by exactly one more equivalent failure.
STAGNATION_PATIENT_RUN="$(cd "${STAGNATION_DIR}" && STACK_PROFILE=patient "${HARNESS_ROOT}/bin/harness" receipt start implement --issue AH-8)"
(cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger start "${STAGNATION_PATIENT_RUN}" >/dev/null)
# Evaluated in sequence and up front: each call appends to the same ledger, so the
# assertion must not short-circuit past a call the next one depends on.
PATIENT_FIRST="$(stagnation_failure patient "${STAGNATION_PATIENT_RUN}" "${STAGNATION_FAIL_A}")"
PATIENT_SECOND="$(stagnation_failure patient "${STAGNATION_PATIENT_RUN}" "${STAGNATION_FAIL_B}")"
PATIENT_THIRD="$(stagnation_failure patient "${STAGNATION_PATIENT_RUN}" "${STAGNATION_FAIL_A}")"
if [ "${PATIENT_FIRST}" != "0 continue" ] || [ "${PATIENT_SECOND}" != "0 continue" ] || [ "${PATIENT_THIRD}" != "3 stagnant" ]; then
    echo "  [FAIL] profiles.<profile>.loop.stagnationThreshold did not raise the breaker threshold"
    exit 1
fi

STAGNATION_REJECT_RUN="$(stagnation_open_run loose)"
STAGNATION_LONG_LABEL="$(head -c 201 < /dev/zero | tr '\0' 'a')"
IMPATIENT_CODE="$(stagnation_failure impatient "${STAGNATION_REJECT_RUN}" "${STAGNATION_FAIL_A}" | cut -d' ' -f1)"
BOGUS_CODE="$(stagnation_failure bogus "${STAGNATION_REJECT_RUN}" "${STAGNATION_FAIL_A}" | cut -d' ' -f1)"
case "${IMPATIENT_CODE}:${BOGUS_CODE}" in
    0:*|*:0|3:*|*:3)
        echo "  [FAIL] a threshold below two or a non-integer threshold produced a decision instead of an error"
        exit 1
        ;;
esac
if (printf '%s' "${STAGNATION_FAIL_A}" | (cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger failure "${STAGNATION_REJECT_RUN}" "${STAGNATION_LONG_LABEL}") >/dev/null 2>&1) || \
   (printf '%s' "${STAGNATION_FAIL_A}" | (cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger failure "${STAGNATION_REJECT_RUN}" "$(printf 'two\nlines')") >/dev/null 2>&1) || \
   (printf '' | (cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger failure "${STAGNATION_REJECT_RUN}") >/dev/null 2>&1) || \
   (printf '%s' "${STAGNATION_FAIL_A}" | (cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger failure missing) >/dev/null 2>&1); then
    echo "  [FAIL] ledger failure accepted an oversized label, a multi-line label, empty input, or a missing ledger"
    exit 1
fi

(cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger append "${STAGNATION_RUN}" ruling "the only ruling" >/dev/null)
STAGNATION_RULINGS="$(cd "${STAGNATION_DIR}" && "${HARNESS_ROOT}/bin/harness" ledger rulings "${STAGNATION_RUN}")"
if [ "$(printf '%s\n' "${STAGNATION_RULINGS}" | grep -c .)" -ne 1 ] || \
   printf '%s\n' "${STAGNATION_RULINGS}" | grep -q "sig:"; then
    echo "  [FAIL] failure lines contaminated ledger rulings output"
    exit 1
fi
echo "  [PASS] failure signatures are normalized, deterministic, evidence-free, and breaker-bounded."


echo ""
echo "=== 16. Testing Fail-Closed Verification ==="
# A verification gate that prints a failure and exits 0 is the exact shape rules/floor.md
# invariant 1 forbids, so the sandbox is dirtied deliberately and the exit status is the
# assertion. The harness is copied rather than mutated in place: --verify walks its own
# checkout, so injecting a syntax error into the real tree would corrupt the suite running it.
VERIFY_SANDBOX_ROOT="${TMP_TEST_DIR}/verify"
mkdir -p "${VERIFY_SANDBOX_ROOT}"

new_verify_sandbox() {
    local sandbox="${VERIFY_SANDBOX_ROOT}/$1"
    rm -rf "${sandbox}"
    mkdir -p "${sandbox}"
    cp -R "${HARNESS_ROOT}/bin" "${HARNESS_ROOT}/core" "${HARNESS_ROOT}/install.sh" \
          "${HARNESS_ROOT}/setup" "${sandbox}/"
    printf '%s' "${sandbox}"
}

# Sets VERIFY_STATUS and VERIFY_OUTPUT. Both are globals rather than a printed status,
# because a command substitution would run the body in a subshell and discard the output.
run_verify() {
    local sandbox="$1"
    VERIFY_STATUS=0
    VERIFY_OUTPUT="$(bash "${sandbox}/setup" --verify 2>&1)" || VERIFY_STATUS=$?
}

VERIFY_CLEAN="$(new_verify_sandbox clean)"
run_verify "${VERIFY_CLEAN}"
VERIFY_CLEAN_STATUS="${VERIFY_STATUS}"
if [ "${VERIFY_CLEAN_STATUS}" -ne 0 ] || ! printf '%s' "${VERIFY_OUTPUT}" | grep -q "Verification completed successfully"; then
    echo "  [FAIL] setup --verify did not succeed on an unmodified checkout"
    exit 1
fi

VERIFY_SYNTAX="$(new_verify_sandbox syntax)"
printf '\nif [ unterminated\n' >> "${VERIFY_SYNTAX}/core/scripts/stack-debt.sh"
run_verify "${VERIFY_SYNTAX}"
VERIFY_SYNTAX_STATUS="${VERIFY_STATUS}"
if [ "${VERIFY_SYNTAX_STATUS}" -eq 0 ] || \
   ! printf '%s' "${VERIFY_OUTPUT}" | grep -q "stack-debt.sh" || \
   printf '%s' "${VERIFY_OUTPUT}" | grep -q "Verification completed successfully"; then
    echo "  [FAIL] setup --verify reported success over a shell syntax error"
    exit 1
fi

VERIFY_FRONTMATTER="$(new_verify_sandbox frontmatter)"
mkdir -p "${VERIFY_FRONTMATTER}/core/skills/malformed"
printf 'no frontmatter at all\n' > "${VERIFY_FRONTMATTER}/core/skills/malformed/SKILL.md"
run_verify "${VERIFY_FRONTMATTER}"
VERIFY_FRONTMATTER_STATUS="${VERIFY_STATUS}"
if [ "${VERIFY_FRONTMATTER_STATUS}" -eq 0 ] || \
   printf '%s' "${VERIFY_OUTPUT}" | grep -q "Verification completed successfully"; then
    echo "  [FAIL] setup --verify reported success over a skill missing its frontmatter"
    exit 1
fi

# One invocation must surface every problem; stopping at the first would make the gate
# a per-run bisection instead of a report.
VERIFY_BOTH="$(new_verify_sandbox both)"
printf '\nif [ unterminated\n' >> "${VERIFY_BOTH}/core/scripts/stack-debt.sh"
mkdir -p "${VERIFY_BOTH}/core/skills/malformed"
printf 'no frontmatter at all\n' > "${VERIFY_BOTH}/core/skills/malformed/SKILL.md"
run_verify "${VERIFY_BOTH}"
VERIFY_BOTH_STATUS="${VERIFY_STATUS}"
if [ "${VERIFY_BOTH_STATUS}" -eq 0 ] || \
   ! printf '%s' "${VERIFY_OUTPUT}" | grep -q "stack-debt.sh" || \
   ! printf '%s' "${VERIFY_OUTPUT}" | grep -q "malformed/SKILL.md"; then
    echo "  [FAIL] setup --verify did not report both a syntax error and a malformed skill in one run"
    exit 1
fi
echo "  [PASS] setup --verify fails closed on syntax errors and malformed skills."

echo ""
echo "=== 17. Testing Scanner Index Fidelity ==="
# The pre-commit hook runs --staged, so --staged must describe the commit. Reading the
# working tree instead makes the gate answer a question nobody asked: it clears a staged
# violation that was reverted on disk, and blocks a violation that is not being committed.
SCAN_RULES="${TMP_TEST_DIR}/scan-rules.json"
cat > "${SCAN_RULES}" <<'SCAN_RULES_EOF'
[
  {
    "id": "TEST-001",
    "name": "Forbidden marker",
    "pattern": "FORBIDDEN_MARKER",
    "fileExtensions": [".py"],
    "level": "error",
    "message": "Remove the forbidden marker."
  }
]
SCAN_RULES_EOF

SCAN_REPO="${TMP_TEST_DIR}/scan-index"
mkdir -p "${SCAN_REPO}"
git -C "${SCAN_REPO}" init -q
git -C "${SCAN_REPO}" config user.email harness@example.com
git -C "${SCAN_REPO}" config user.name "Harness Test"
printf 'print("clean")\n' > "${SCAN_REPO}/app.py"
git -C "${SCAN_REPO}" add app.py
git -C "${SCAN_REPO}" commit -qm "baseline"

# Sets SCAN_STATUS and SCAN_OUTPUT, for the same reason run_verify does.
run_scan() {
    local mode="$1"
    SCAN_STATUS=0
    SCAN_OUTPUT="$(cd "${SCAN_REPO}" && "${HARNESS_ROOT}/bin/harness" scan "${mode}" --rules "${SCAN_RULES}" 2>&1)" || SCAN_STATUS=$?
}

# Staged violation, reverted on disk. This is the bypass: git commit would record the
# marker, and a working-tree read sees a clean file.
printf 'print("clean")\nFORBIDDEN_MARKER = 1\n' > "${SCAN_REPO}/app.py"
git -C "${SCAN_REPO}" add app.py
printf 'print("clean")\n' > "${SCAN_REPO}/app.py"
run_scan --staged
if [ "${SCAN_STATUS}" -eq 0 ]; then
    echo "  [FAIL] scan --staged passed a violation that is staged for commit"
    exit 1
fi

# The mirror image: present on disk, absent from the index. --staged must clear it and
# --diff must not, because they answer different questions.
git -C "${SCAN_REPO}" reset -q --hard
printf 'print("clean")\nFORBIDDEN_MARKER = 1\n' > "${SCAN_REPO}/app.py"
run_scan --staged
if [ "${SCAN_STATUS}" -ne 0 ]; then
    echo "  [FAIL] scan --staged blocked a violation that is not staged for commit"
    exit 1
fi
run_scan --diff
if [ "${SCAN_STATUS}" -eq 0 ]; then
    echo "  [FAIL] scan --diff passed a working-tree violation"
    exit 1
fi

# A path staged as an addition and then deleted from disk is still in the commit.
git -C "${SCAN_REPO}" reset -q --hard
printf 'FORBIDDEN_MARKER = 1\n' > "${SCAN_REPO}/ghost.py"
git -C "${SCAN_REPO}" add ghost.py
rm "${SCAN_REPO}/ghost.py"
run_scan --staged
if [ "${SCAN_STATUS}" -eq 0 ]; then
    echo "  [FAIL] scan --staged skipped a staged addition that was deleted from disk"
    exit 1
fi

# Findings must cite the staged path and the line number inside the staged content,
# not whatever line the working-tree copy happens to have.
git -C "${SCAN_REPO}" reset -q --hard
rm -f "${SCAN_REPO}/ghost.py"
printf 'a = 1\nb = 2\nFORBIDDEN_MARKER = 3\n' > "${SCAN_REPO}/app.py"
git -C "${SCAN_REPO}" add app.py
printf 'a = 1\n' > "${SCAN_REPO}/app.py"
run_scan --staged
if ! printf '%s' "${SCAN_OUTPUT}" | grep -q "app.py" || \
   ! printf '%s' "${SCAN_OUTPUT}" | grep -qE '(^|[^0-9])3:FORBIDDEN_MARKER'; then
    echo "  [FAIL] scan --staged did not report the staged path and staged line number"
    exit 1
fi

# Materialized index content is scratch, not output. A private TMPDIR makes the leak
# assertion deterministic instead of a guess about the shared temporary directory.
SCAN_TMPDIR="${TMP_TEST_DIR}/scan-tmp"
rm -rf "${SCAN_TMPDIR}"
mkdir -p "${SCAN_TMPDIR}"
(cd "${SCAN_REPO}" && TMPDIR="${SCAN_TMPDIR}" "${HARNESS_ROOT}/bin/harness" scan --staged --rules "${SCAN_RULES}" >/dev/null 2>&1) || true
if [ -n "$(ls -A "${SCAN_TMPDIR}")" ]; then
    echo "  [FAIL] scan --staged left materialized index content behind"
    exit 1
fi
git -C "${SCAN_REPO}" reset -q --hard
echo "  [PASS] scan --staged reads the index, cites staged lines, and leaves no scratch."

echo ""
echo "=== 18. Testing Pre-Commit Hook Preservation ==="
# Overwriting a hook the user already relies on is silent data loss, and reporting success
# while doing it is the same fail-open shape as the gates above.
HOOK_REPO="${TMP_TEST_DIR}/hook-repo"
mkdir -p "${HOOK_REPO}"
git -C "${HOOK_REPO}" init -q
HOOK_PATH="${HOOK_REPO}/.git/hooks/pre-commit"
HOOK_BACKUP="${HOOK_REPO}/.git/hooks/pre-commit.harness-backup"
# No trailing newline: the assertions compare against "$(cat ...)", which strips one.
FOREIGN_HOOK=$'#!/bin/sh\necho "existing project hook"'

# Sets HOOK_STATUS and HOOK_OUTPUT, for the same reason run_verify does.
install_hook() {
    HOOK_STATUS=0
    HOOK_OUTPUT="$(cd "${HOOK_REPO}" && "${HARNESS_ROOT}/bin/harness" scan --install-hook "$@" 2>&1)" || HOOK_STATUS=$?
}

rm -f "${HOOK_PATH}" "${HOOK_BACKUP}"
install_hook
if [ "${HOOK_STATUS}" -ne 0 ] || [ ! -x "${HOOK_PATH}" ]; then
    echo "  [FAIL] --install-hook did not install into a repository without a pre-commit hook"
    exit 1
fi
HOOK_FIRST="$(cat "${HOOK_PATH}")"
install_hook
if [ "${HOOK_STATUS}" -ne 0 ] || [ "$(cat "${HOOK_PATH}")" != "${HOOK_FIRST}" ]; then
    echo "  [FAIL] --install-hook was not idempotent over its own hook"
    exit 1
fi

printf '%s' "${FOREIGN_HOOK}" > "${HOOK_PATH}"
chmod 755 "${HOOK_PATH}"
install_hook
if [ "${HOOK_STATUS}" -eq 0 ] || [ "$(cat "${HOOK_PATH}")" != "${FOREIGN_HOOK}" ]; then
    echo "  [FAIL] --install-hook overwrote or accepted a hook agent-harness did not write"
    exit 1
fi
if ! printf '%s' "${HOOK_OUTPUT}" | grep -q "harness scan --staged"; then
    echo "  [FAIL] --install-hook refused a foreign hook without printing the line to add manually"
    exit 1
fi

rm -f "${HOOK_BACKUP}"
install_hook --force
if [ "${HOOK_STATUS}" -ne 0 ] || [ ! -f "${HOOK_BACKUP}" ] || \
   [ "$(cat "${HOOK_BACKUP}")" != "${FOREIGN_HOOK}" ] || [ ! -x "${HOOK_BACKUP}" ] || \
   [ "$(cat "${HOOK_PATH}")" = "${FOREIGN_HOOK}" ]; then
    echo "  [FAIL] --install-hook --force did not back the foreign hook up before replacing it"
    exit 1
fi

# A second --force must not turn the backup into a copy of our own hook.
printf '%s' "${FOREIGN_HOOK}" > "${HOOK_PATH}"
install_hook --force
if [ "${HOOK_STATUS}" -eq 0 ] || [ "$(cat "${HOOK_BACKUP}")" != "${FOREIGN_HOOK}" ]; then
    echo "  [FAIL] --install-hook --force destroyed an existing backup"
    exit 1
fi
echo "  [PASS] --install-hook preserves foreign hooks, is idempotent, and backs up under --force."

echo ""
echo "=== 19. Testing Scanner Rule Validation ==="
# grep -E exits 2 on a pattern it cannot compile. With stderr suppressed that is
# indistinguishable from "no match", so an unusable rule reads as a clean file forever.
# The two fixtures below are deliberately different: BAD-002 is malformed for every grep,
# while BAD-001 is a PCRE lookahead that BSD grep rejects and GNU grep happily compiles.
# Asserting the *reason* for BAD-001, not just its ID, is what stops the guard from silently
# becoming a macOS-only check again -- which is how the first attempt passed here and failed
# on the Ubuntu runner.
BAD_RULES="${TMP_TEST_DIR}/bad-rules.json"
cat > "${BAD_RULES}" <<'BAD_RULES_EOF'
[
  {
    "id": "BAD-001",
    "name": "PCRE lookahead",
    "pattern": "\\.objects\\.all\\(\\)(?!\\.iterator)",
    "fileExtensions": [".py"],
    "level": "error",
    "message": "unreachable"
  },
  {
    "id": "BAD-002",
    "name": "Unbalanced group",
    "pattern": "(unclosed",
    "fileExtensions": [".py"],
    "level": "error",
    "message": "unreachable"
  }
]
BAD_RULES_EOF

RULE_STATUS=0
RULE_OUTPUT="$(cd "${SCAN_REPO}" && "${HARNESS_ROOT}/bin/harness" scan --all --rules "${BAD_RULES}" 2>&1)" || RULE_STATUS=$?
if [ "${RULE_STATUS}" -eq 0 ] || \
   ! printf '%s' "${RULE_OUTPUT}" | grep -q "BAD-002"; then
    echo "  [FAIL] scan accepted a rule pattern that grep -E cannot compile"
    exit 1
fi
if ! printf '%s' "${RULE_OUTPUT}" | grep -q "BAD-001.*PCRE construct"; then
    echo "  [FAIL] scan did not reject a PCRE lookahead on the grep-independent path"
    exit 1
fi

# A pattern that compiles and matches nothing is valid, not unusable.
QUIET_RULES="${TMP_TEST_DIR}/quiet-rules.json"
cat > "${QUIET_RULES}" <<'QUIET_RULES_EOF'
[
  {
    "id": "QUIET-001",
    "name": "Never present",
    "pattern": "THIS_STRING_IS_NOT_IN_THE_FIXTURE",
    "fileExtensions": [".py"],
    "level": "error",
    "message": "unreachable"
  }
]
QUIET_RULES_EOF
if ! (cd "${SCAN_REPO}" && "${HARNESS_ROOT}/bin/harness" scan --all --rules "${QUIET_RULES}" >/dev/null 2>&1); then
    echo "  [FAIL] scan rejected a valid pattern that simply matches nothing"
    exit 1
fi

# The shipped PERF-001 must actually fire, and must still spare the bounded forms its
# documentation says it spares.
PERF_REPO="${TMP_TEST_DIR}/perf-fixture"
mkdir -p "${PERF_REPO}"
git -C "${PERF_REPO}" init -q
printf 'rows = Model.objects.all()\n' > "${PERF_REPO}/unbounded.py"
printf 'a = Model.objects.all().iterator()\nb = Model.objects.all().values("id")\nc = Model.objects.all()[:10]\n' > "${PERF_REPO}/bounded.py"
git -C "${PERF_REPO}" add -A
for shipped_rules in "${HARNESS_ROOT}/rules/landmines.json" "${HARNESS_ROOT}/core/templates/landmines-template.json"; do
    PERF_OUTPUT="$(cd "${PERF_REPO}" && "${HARNESS_ROOT}/bin/harness" scan --all --rules "${shipped_rules}" 2>&1)" || true
    if ! printf '%s' "${PERF_OUTPUT}" | grep -q "PERF-001.*unbounded.py"; then
        echo "  [FAIL] PERF-001 in ${shipped_rules} did not flag an unbounded objects.all()"
        exit 1
    fi
    # Anchored on a non-alphanumeric boundary: a bare "bounded.py" is also a substring
    # of "unbounded.py", which would make this assertion pass for the wrong reason.
    if printf '%s' "${PERF_OUTPUT}" | grep -qE '(^|[^[:alnum:]])bounded\.py'; then
        echo "  [FAIL] PERF-001 in ${shipped_rules} flagged an iterator, values, or sliced query"
        exit 1
    fi
done
echo "  [PASS] unusable rule patterns abort the scan and PERF-001 discriminates correctly."
echo ""
echo "All automated tests passed successfully! [100%]"
