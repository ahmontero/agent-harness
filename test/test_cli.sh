#!/usr/bin/env bash
# ==============================================================================
# agent-harness: test/test_cli.sh
# Automated Test Suite for Agent Harness
# ==============================================================================

set -eo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
# Named here rather than in group 20 because the surface-content assertions in group 6
# must exclude it: it is an installation record, not a published skill.
SURFACE_MANIFEST=".agent-harness-surface.json"

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
if find "${EXPERT_TARGET_DIR}/.codex/skills" -mindepth 1 -maxdepth 1 ! -name 'harness-*' ! -name "${SURFACE_MANIFEST}" -print -quit | grep -q . || \
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

# The README badge states a version to every reader of the front page. It drifted behind
# package.json the moment a release bumped one and not the other, so the claim is checked.
HARNESS_VERSION="$(jq -r '.version' "${HARNESS_ROOT}/package.json")"
if ! grep -qF "badge/version-${HARNESS_VERSION}-blue.svg" "${HARNESS_ROOT}/README.md"; then
    echo "  [FAIL] README version badge does not state package.json's version (${HARNESS_VERSION})"
    exit 1
fi
if ! grep -qF "## [${HARNESS_VERSION}]" "${HARNESS_ROOT}/CHANGELOG.md"; then
    echo "  [FAIL] CHANGELOG.md has no entry for the released version ${HARNESS_VERSION}"
    exit 1
fi
echo "  [PASS] the README badge and CHANGELOG agree with package.json on the version."

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
    .schemaVersion == 3 and
    .scope == "target" and
    .mode == "default" and
    .status == "passed" and
    .runtimeGating == true and
    .surfaceManifest == true and
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
echo "=== 20. Testing Skill Surface Manifest ==="
# A copied bundle has no recorded identity, so nothing downstream can ask whether it is
# current. The manifest is that identity, and these assertions are what stop it from
# drifting into decoration: it must name the runtime it was installed for, the mode it was
# installed in, the version it came from, and a digest per bundle.
HARNESS_VERSION="$(jq -r '.version' "${HARNESS_ROOT}/package.json")"

MANIFEST_TARGET="${TMP_TEST_DIR}/manifest-target"
mkdir -p "${MANIFEST_TARGET}"
git -C "${MANIFEST_TARGET}" init -q
"${HARNESS_ROOT}/install.sh" --target "${MANIFEST_TARGET}" >/dev/null

for runtime_pair in "gemini:.gemini" "claude:.claude" "codex:.codex" "agents:.agents"; do
    runtime_label="${runtime_pair%%:*}"
    runtime_dir="${MANIFEST_TARGET}/${runtime_pair#*:}/skills"
    manifest="${runtime_dir}/${SURFACE_MANIFEST}"
    if [ ! -f "${manifest}" ] || ! jq empty "${manifest}" >/dev/null 2>&1; then
        echo "  [FAIL] Curated installation wrote no valid surface manifest in ${runtime_dir}"
        exit 1
    fi
    if [ "$(jq -r '.schemaVersion' "${manifest}")" != "1" ] || \
       [ "$(jq -r '.namespace' "${manifest}")" != "harness" ] || \
       [ "$(jq -r '.harnessVersion' "${manifest}")" != "${HARNESS_VERSION}" ] || \
       [ "$(jq -r '.mode' "${manifest}")" != "curated" ] || \
       [ "$(jq -r '.runtime' "${manifest}")" != "${runtime_label}" ]; then
        echo "  [FAIL] Surface manifest does not identify its own installation in ${runtime_dir}"
        exit 1
    fi

    # The recorded skills must be exactly the workflows this runtime is allowed to receive.
    # Recording a gated workflow the runtime never got would report drift forever.
    expected_skills=""
    while IFS= read -r workflow; do
        if jq -e --arg w "${workflow}" --arg r "${runtime_label}" \
            'if (.runtimes // {}) | has($w) then (.runtimes[$w] | index($r)) != null else true end' \
            "${SKILL_CATALOG}" >/dev/null; then
            expected_skills="${expected_skills}harness-${workflow}
"
        fi
    done < <(jq -r '.public | keys[]' "${SKILL_CATALOG}")
    expected_skills="$(printf '%s' "${expected_skills}" | sort)"
    recorded_skills="$(jq -r '.skills[].name' "${manifest}" | sort)"
    if [ "${recorded_skills}" != "${expected_skills}" ]; then
        echo "  [FAIL] Surface manifest in ${runtime_dir} records the wrong skill set"
        exit 1
    fi
    if [ "$(jq -r '[.skills[] | select(.kind != "bundle")] | length' "${manifest}")" -ne 0 ] || \
       [ "$(jq -r '[.skills[] | select(.digest | test("^[0-9a-f]{12}$") | not)] | length' "${manifest}")" -ne 0 ]; then
        echo "  [FAIL] Curated manifest in ${runtime_dir} did not record every workflow as a 12-hex bundle digest"
        exit 1
    fi
done

# Expert primitives are symlinks into the source tree. They cannot drift, and recording
# them as bundles with a digest would invent a comparison that means nothing.
EXPERT_MANIFEST_TARGET="${TMP_TEST_DIR}/manifest-expert"
mkdir -p "${EXPERT_MANIFEST_TARGET}"
git -C "${EXPERT_MANIFEST_TARGET}" init -q
"${HARNESS_ROOT}/install.sh" --target "${EXPERT_MANIFEST_TARGET}" --expert >/dev/null
EXPERT_MANIFEST="${EXPERT_MANIFEST_TARGET}/.codex/skills/${SURFACE_MANIFEST}"
EXPECTED_PRIMITIVES="$(jq -r '.internal | length' "${SKILL_CATALOG}")"
if [ "$(jq -r '.mode' "${EXPERT_MANIFEST}")" != "expert" ] || \
   [ "$(jq -r '[.skills[] | select(.kind == "symlink")] | length' "${EXPERT_MANIFEST}")" -ne "${EXPECTED_PRIMITIVES}" ] || \
   [ "$(jq -r '[.skills[] | select(.kind == "symlink" and has("digest"))] | length' "${EXPERT_MANIFEST}")" -ne 0 ]; then
    echo "  [FAIL] Expert manifest did not record its primitives as digest-free symlinks"
    exit 1
fi

# A digest that ignores content is useless, and one that ignores paths cannot tell a
# renamed reference from the original. The sandbox below changes only the reference's
# *name*, keeping its bytes identical, which is the case a content-only digest misses.
DIGEST_SANDBOX="${TMP_TEST_DIR}/digest-sandbox"
rm -rf "${DIGEST_SANDBOX}"
mkdir -p "${DIGEST_SANDBOX}"
cp -R "${HARNESS_ROOT}/bin" "${HARNESS_ROOT}/core" "${HARNESS_ROOT}/install.sh" \
      "${HARNESS_ROOT}/setup" "${HARNESS_ROOT}/package.json" "${DIGEST_SANDBOX}/"
DIGEST_TARGET="${TMP_TEST_DIR}/digest-target"
mkdir -p "${DIGEST_TARGET}"
git -C "${DIGEST_TARGET}" init -q
"${DIGEST_SANDBOX}/install.sh" --target "${DIGEST_TARGET}" >/dev/null
DIGEST_MANIFEST="${DIGEST_TARGET}/.codex/skills/${SURFACE_MANIFEST}"
DIGEST_BEFORE="$(jq -r '.skills[] | select(.name == "harness-fix") | .digest' "${DIGEST_MANIFEST}")"

printf '\n<!-- content change -->\n' >> "${DIGEST_SANDBOX}/core/skills/bug/SKILL.md"
"${DIGEST_SANDBOX}/install.sh" --target "${DIGEST_TARGET}" >/dev/null
DIGEST_AFTER_CONTENT="$(jq -r '.skills[] | select(.name == "harness-fix") | .digest' "${DIGEST_MANIFEST}")"
if [ "${DIGEST_BEFORE}" = "${DIGEST_AFTER_CONTENT}" ]; then
    echo "  [FAIL] Bundle digest did not change when a reference protocol changed"
    exit 1
fi

# Byte-identical content published under a different reference name must sign differently.
cp -R "${DIGEST_SANDBOX}/core/skills/bug" "${DIGEST_SANDBOX}/core/skills/bug-renamed"
jq '(.internal) += ["bug-renamed"] | (.public.fix) = ((.public.fix | map(select(. != "bug"))) + ["bug-renamed"])' \
    "${DIGEST_SANDBOX}/core/skills/catalog.json" > "${DIGEST_SANDBOX}/core/skills/catalog.json.tmp"
mv "${DIGEST_SANDBOX}/core/skills/catalog.json.tmp" "${DIGEST_SANDBOX}/core/skills/catalog.json"
"${DIGEST_SANDBOX}/install.sh" --target "${DIGEST_TARGET}" >/dev/null
DIGEST_AFTER_RENAME="$(jq -r '.skills[] | select(.name == "harness-fix") | .digest' "${DIGEST_MANIFEST}")"
if [ "${DIGEST_AFTER_RENAME}" = "${DIGEST_AFTER_CONTENT}" ]; then
    echo "  [FAIL] Bundle digest ignored a reference rename that preserved content"
    exit 1
fi

# A rolled-back install must leave no manifest claiming a surface that is not there.
ROLLBACK_MANIFEST_TARGET="${TMP_TEST_DIR}/manifest-rollback"
ROLLBACK_STATE_DIR="${TMP_TEST_DIR}/manifest-rollback-state"
mkdir -p "${ROLLBACK_MANIFEST_TARGET}" "${ROLLBACK_STATE_DIR}"
git -C "${ROLLBACK_MANIFEST_TARGET}" init -q
HARNESS_STATE_DIR="${ROLLBACK_STATE_DIR}" HARNESS_ENABLE_FAILURE_INJECTION=true HARNESS_TEST_FAIL_AFTER=12 \
    "${HARNESS_ROOT}/install.sh" --target "${ROLLBACK_MANIFEST_TARGET}" >/dev/null 2>&1 || true
if find "${ROLLBACK_MANIFEST_TARGET}" -name "${SURFACE_MANIFEST}" -print -quit | grep -q .; then
    echo "  [FAIL] A rolled-back installation left a surface manifest behind"
    exit 1
fi
echo "  [PASS] surface manifests record runtime, mode, version, and path-sensitive digests."

echo ""
echo "=== 21. Testing Surface Drift Detection ==="
# Drift has to be answerable without a network and without reinstalling, or nobody will ask.
# --check is the read-only half: it reports, it never repairs, and it exits non-zero when
# any surface is stale so CI can consume it.
DRIFT_TARGET="${TMP_TEST_DIR}/drift-target"
mkdir -p "${DRIFT_TARGET}"
git -C "${DRIFT_TARGET}" init -q
"${HARNESS_ROOT}/install.sh" --target "${DRIFT_TARGET}" >/dev/null

run_drift_check() {
    DRIFT_STATUS=0
    DRIFT_OUTPUT="$("${HARNESS_ROOT}/bin/harness" sync --check --target "${DRIFT_TARGET}" 2>&1)" || DRIFT_STATUS=$?
}

run_drift_check
if [ "${DRIFT_STATUS}" -ne 0 ] || printf '%s' "${DRIFT_OUTPUT}" | grep -qi "drifted"; then
    echo "  [FAIL] sync --check reported drift immediately after a clean installation"
    exit 1
fi

# A gated workflow absent from a runtime that must not receive it is correct, not drift.
# Reporting it would make every codex, gemini, and agents surface permanently stale.
if [ -e "${DRIFT_TARGET}/.codex/skills/harness-orchestrate" ]; then
    echo "  [FAIL] the drift fixture is wrong: orchestrate must not be installed for codex"
    exit 1
fi

# --check must not touch anything it inspects.
DRIFT_FINGERPRINT_BEFORE="$(find "${DRIFT_TARGET}" -type f -exec git hash-object {} \; | sort | git hash-object --stdin)"
run_drift_check
DRIFT_FINGERPRINT_AFTER="$(find "${DRIFT_TARGET}" -type f -exec git hash-object {} \; | sort | git hash-object --stdin)"
if [ "${DRIFT_FINGERPRINT_BEFORE}" != "${DRIFT_FINGERPRINT_AFTER}" ]; then
    echo "  [FAIL] sync --check mutated the surface it inspected"
    exit 1
fi

# An edited bundle is the case that matters: the file still exists and still looks right.
printf '\nlocally edited\n' >> "${DRIFT_TARGET}/.claude/skills/harness-implement/SKILL.md"
run_drift_check
if [ "${DRIFT_STATUS}" -eq 0 ] || ! printf '%s' "${DRIFT_OUTPUT}" | grep -q "harness-implement"; then
    echo "  [FAIL] sync --check did not report an edited bundle as drifted"
    exit 1
fi
rm -rf "${DRIFT_TARGET}/.claude/skills/harness-implement"
cp -R "${DRIFT_TARGET}/.codex/skills/harness-implement" "${DRIFT_TARGET}/.claude/skills/harness-implement"

# A workflow that should be present and is gone.
rm -rf "${DRIFT_TARGET}/.agents/skills/harness-fix"
run_drift_check
if [ "${DRIFT_STATUS}" -eq 0 ] || ! printf '%s' "${DRIFT_OUTPUT}" | grep -q "harness-fix"; then
    echo "  [FAIL] sync --check did not report a missing workflow as drifted"
    exit 1
fi
cp -R "${DRIFT_TARGET}/.codex/skills/harness-fix" "${DRIFT_TARGET}/.agents/skills/harness-fix"

# Every installation that predates this delta is in exactly this state. It must read as
# drifted with a stated reason, not as an error and not as clean.
rm -f "${DRIFT_TARGET}/.gemini/skills/${SURFACE_MANIFEST}"
run_drift_check
if [ "${DRIFT_STATUS}" -eq 0 ] || ! printf '%s' "${DRIFT_OUTPUT}" | grep -q "no recorded version"; then
    echo "  [FAIL] sync --check did not report a manifest-less surface as drifted with a reason"
    exit 1
fi

# A version bump alone is drift: the bundles may be byte-identical today, but the surface
# no longer records which release produced them.
STALE_TARGET="${TMP_TEST_DIR}/drift-stale"
mkdir -p "${STALE_TARGET}"
git -C "${STALE_TARGET}" init -q
"${HARNESS_ROOT}/install.sh" --target "${STALE_TARGET}" >/dev/null
STALE_MANIFEST="${STALE_TARGET}/.codex/skills/${SURFACE_MANIFEST}"
jq '.harnessVersion = "0.0.1-old"' "${STALE_MANIFEST}" > "${STALE_MANIFEST}.tmp"
mv "${STALE_MANIFEST}.tmp" "${STALE_MANIFEST}"
STALE_STATUS=0
STALE_OUTPUT="$("${HARNESS_ROOT}/bin/harness" sync --check --target "${STALE_TARGET}" 2>&1)" || STALE_STATUS=$?
if [ "${STALE_STATUS}" -eq 0 ] || ! printf '%s' "${STALE_OUTPUT}" | grep -q "0.0.1-old"; then
    echo "  [FAIL] sync --check did not report an older recorded version as drifted"
    exit 1
fi
echo "  [PASS] sync --check reports drift with reasons, spares gated absences, and mutates nothing."

echo ""
echo "=== 22. Testing Surface Synchronization ==="
# The only command that could ever update an installed surface used to reach the global
# half and silently downgrade an expert installation on the way. These assertions pin both.
SYNC_TARGET_DIR="${TMP_TEST_DIR}/sync-target"
mkdir -p "${SYNC_TARGET_DIR}"
git -C "${SYNC_TARGET_DIR}" init -q
"${HARNESS_ROOT}/install.sh" --target "${SYNC_TARGET_DIR}" >/dev/null

surface_fingerprint() {
    find "$1" -type f -exec git hash-object {} \; | LC_ALL=C sort | git hash-object --stdin
}

SYNC_PRISTINE="$(surface_fingerprint "${SYNC_TARGET_DIR}/.claude/skills")"
printf '\nlocally edited\n' >> "${SYNC_TARGET_DIR}/.claude/skills/harness-implement/SKILL.md"
if [ "$(surface_fingerprint "${SYNC_TARGET_DIR}/.claude/skills")" = "${SYNC_PRISTINE}" ]; then
    echo "  [FAIL] the sync fixture did not actually dirty the surface"
    exit 1
fi
"${HARNESS_ROOT}/bin/harness" sync --target "${SYNC_TARGET_DIR}" >/dev/null
if [ "$(surface_fingerprint "${SYNC_TARGET_DIR}/.claude/skills")" != "${SYNC_PRISTINE}" ]; then
    echo "  [FAIL] sync did not restore a drifted surface to byte-identical content"
    exit 1
fi
if ! "${HARNESS_ROOT}/bin/harness" sync --check --target "${SYNC_TARGET_DIR}" >/dev/null 2>&1; then
    echo "  [FAIL] a synchronized surface still reports drift"
    exit 1
fi

# An expert surface must survive a sync that was given no mode. This is the regression
# that motivated the manifest: today's sync removes every managed primitive and reinstalls
# none, turning a 19-skill expert surface into a 4-skill curated one without saying so.
SYNC_EXPERT_DIR="${TMP_TEST_DIR}/sync-expert"
mkdir -p "${SYNC_EXPERT_DIR}"
git -C "${SYNC_EXPERT_DIR}" init -q
"${HARNESS_ROOT}/install.sh" --target "${SYNC_EXPERT_DIR}" --expert >/dev/null
EXPERT_BEFORE="$(find "${SYNC_EXPERT_DIR}/.codex/skills" -mindepth 1 -maxdepth 1 -type l | wc -l | tr -d ' ')"
"${HARNESS_ROOT}/bin/harness" sync --target "${SYNC_EXPERT_DIR}" >/dev/null
EXPERT_AFTER="$(find "${SYNC_EXPERT_DIR}/.codex/skills" -mindepth 1 -maxdepth 1 -type l | wc -l | tr -d ' ')"
if [ "${EXPERT_BEFORE}" -eq 0 ] || [ "${EXPERT_AFTER}" -ne "${EXPERT_BEFORE}" ] || \
   [ "$(jq -r '.mode' "${SYNC_EXPERT_DIR}/.codex/skills/${SURFACE_MANIFEST}")" != "expert" ]; then
    echo "  [FAIL] sync downgraded an expert surface to curated"
    exit 1
fi

# Repair, never initialize: a repository with no managed surface is left untouched.
SYNC_VIRGIN_DIR="${TMP_TEST_DIR}/sync-virgin"
mkdir -p "${SYNC_VIRGIN_DIR}"
git -C "${SYNC_VIRGIN_DIR}" init -q
"${HARNESS_ROOT}/bin/harness" sync --target "${SYNC_VIRGIN_DIR}" >/dev/null 2>&1 || true
if [ -e "${SYNC_VIRGIN_DIR}/.claude" ] || [ -e "${SYNC_VIRGIN_DIR}/AGENTS.md" ]; then
    echo "  [FAIL] sync initialized a repository that had no managed surface"
    exit 1
fi

# A published name occupied by something the installer may not replace is a failed run,
# not a warning followed by success.
SYNC_BLOCKED_DIR="${TMP_TEST_DIR}/sync-blocked"
mkdir -p "${SYNC_BLOCKED_DIR}"
git -C "${SYNC_BLOCKED_DIR}" init -q
"${HARNESS_ROOT}/install.sh" --target "${SYNC_BLOCKED_DIR}" >/dev/null
rm -rf "${SYNC_BLOCKED_DIR}/.codex/skills/harness-fix"
mkdir -p "${SYNC_BLOCKED_DIR}/.codex/skills/harness-fix"
echo "mine" > "${SYNC_BLOCKED_DIR}/.codex/skills/harness-fix/SKILL.md"
if "${HARNESS_ROOT}/bin/harness" sync --target "${SYNC_BLOCKED_DIR}" >/dev/null 2>&1; then
    echo "  [FAIL] sync reported success while a published skill name was unavailable"
    exit 1
fi
if [ "$(cat "${SYNC_BLOCKED_DIR}/.codex/skills/harness-fix/SKILL.md")" != "mine" ]; then
    echo "  [FAIL] sync replaced a skill path it does not manage"
    exit 1
fi

# One sync is one transaction, undone the same way any installation is.
SYNC_ROLLBACK_DIR="${TMP_TEST_DIR}/sync-rollback"
SYNC_ROLLBACK_STATE="${TMP_TEST_DIR}/sync-rollback-state"
mkdir -p "${SYNC_ROLLBACK_DIR}" "${SYNC_ROLLBACK_STATE}"
git -C "${SYNC_ROLLBACK_DIR}" init -q
"${HARNESS_ROOT}/install.sh" --target "${SYNC_ROLLBACK_DIR}" >/dev/null
printf '\nlocally edited\n' >> "${SYNC_ROLLBACK_DIR}/.claude/skills/harness-implement/SKILL.md"
SYNC_DIRTY="$(surface_fingerprint "${SYNC_ROLLBACK_DIR}/.claude/skills")"
HARNESS_STATE_DIR="${SYNC_ROLLBACK_STATE}" "${HARNESS_ROOT}/bin/harness" sync --target "${SYNC_ROLLBACK_DIR}" >/dev/null
HARNESS_STATE_DIR="${SYNC_ROLLBACK_STATE}" "${HARNESS_ROOT}/setup" --rollback >/dev/null
if [ "$(surface_fingerprint "${SYNC_ROLLBACK_DIR}/.claude/skills")" != "${SYNC_DIRTY}" ]; then
    echo "  [FAIL] rolling back a sync did not restore the previous surface"
    exit 1
fi
echo "  [PASS] sync repairs, preserves expert mode, never initializes, fails closed, and rolls back."

echo ""
echo "=== 23. Testing Doctor Surface Reporting ==="
# Drift is staleness, not breakage, so it is a warning: doctor must still exit 0. What it
# must never do is stay silent, or claim a check ran when it could not.
DOCTOR_DIR="${TMP_TEST_DIR}/doctor-target"
mkdir -p "${DOCTOR_DIR}"
git -C "${DOCTOR_DIR}" init -q
"${HARNESS_ROOT}/install.sh" --target "${DOCTOR_DIR}" >/dev/null
printf '\nlocally edited\n' >> "${DOCTOR_DIR}/.claude/skills/harness-implement/SKILL.md"

# HOME is isolated for the whole group. `doctor --fix` repairs both the scopes doctor
# reports on, and the global one is derived from $HOME: without this, running the test
# suite rewrote the developer's own global skill surfaces. The suite may not reach outside
# its temporary directory, and a test that repairs surfaces has to be held to that hardest.
DOCTOR_HOME="${TMP_TEST_DIR}/doctor-home"
mkdir -p "${DOCTOR_HOME}"
doctor_in_dir() {
    (cd "${DOCTOR_DIR}" && env HOME="${DOCTOR_HOME}" "${HARNESS_ROOT}/bin/harness" doctor "$@" 2>&1)
}

# A drifted global surface inside the isolated home, so the two-scope repair is asserted
# rather than merely assumed from an empty $HOME.
env HOME="${DOCTOR_HOME}" "${HARNESS_ROOT}/install.sh" --global >/dev/null
printf '\nlocally edited\n' >> "${DOCTOR_HOME}/.claude/skills/harness-implement/SKILL.md"

DOCTOR_STATUS=0
DOCTOR_OUTPUT="$(doctor_in_dir)" || DOCTOR_STATUS=$?
if [ "${DOCTOR_STATUS}" -ne 0 ]; then
    echo "  [FAIL] doctor treated surface drift as an error instead of a warning"
    exit 1
fi
if ! printf '%s' "${DOCTOR_OUTPUT}" | grep -q "drifted" || \
   ! printf '%s' "${DOCTOR_OUTPUT}" | grep -q "harness-implement"; then
    echo "  [FAIL] doctor did not report the drifted surface and its reason"
    exit 1
fi

DOCTOR_FIX_STATUS=0
doctor_in_dir --fix >/dev/null || DOCTOR_FIX_STATUS=$?
if [ "${DOCTOR_FIX_STATUS}" -ne 0 ] || \
   ! "${HARNESS_ROOT}/bin/harness" sync --check --target "${DOCTOR_DIR}" >/dev/null 2>&1; then
    echo "  [FAIL] doctor --fix did not repair the drifted surface"
    exit 1
fi
if ! env HOME="${DOCTOR_HOME}" "${HARNESS_ROOT}/bin/harness" sync --check --global >/dev/null 2>&1; then
    echo "  [FAIL] doctor --fix did not repair the global surface it reported as drifted"
    exit 1
fi

# A check that could not run must never read as a check that passed.
DOCTOR_STUB="${TMP_TEST_DIR}/doctor-stub"
mkdir -p "${DOCTOR_STUB}"
cat > "${DOCTOR_STUB}/jq" <<'STUB_EOF'
#!/usr/bin/env bash
exit 1
STUB_EOF
chmod +x "${DOCTOR_STUB}/jq"
DOCTOR_NOJQ="$(cd "${DOCTOR_DIR}" && env HOME="${DOCTOR_HOME}" PATH="${DOCTOR_STUB}:${PATH}" "${HARNESS_ROOT}/bin/harness" doctor 2>&1)" || true
if ! printf '%s' "${DOCTOR_NOJQ}" | grep -qi "unavailable" || \
   printf '%s' "${DOCTOR_NOJQ}" | grep -q "current  "; then
    echo "  [FAIL] doctor reported a surface state without a working jq"
    exit 1
fi
echo "  [PASS] doctor warns on drift, repairs with --fix, and reports an unrunnable check as unavailable."

echo ""
echo "=== 24. Testing Commit Scope Derivation ==="
# A version number in a branch name is not an issue key. Reading one out of
# chore/release-2.4.1 records chore(release-2): ..., a scope that points at no issue and
# that no reader can trace back to one.
COMMIT_DIR="${TMP_TEST_DIR}/commit-scope"
mkdir -p "${COMMIT_DIR}"
git -C "${COMMIT_DIR}" init -q
git -C "${COMMIT_DIR}" config user.email "tests@agent-harness.local"
git -C "${COMMIT_DIR}" config user.name "Agent Harness Tests"
echo "fixture" > "${COMMIT_DIR}/fixture.txt"
git -C "${COMMIT_DIR}" add fixture.txt
git -C "${COMMIT_DIR}" commit -qm "commit scope fixture"
# Keeps the builder inside the fixture: with no local config it resolves the example
# profile's targetRepoPath and would commit into whatever happens to live there.
cat > "${COMMIT_DIR}/harness.config.json" <<'COMMIT_CONFIG_EOF'
{
  "project": { "name": "commit-scope-fixture", "defaultProfile": "fixture" },
  "profiles": { "fixture": { "displayName": "Commit scope fixture" } }
}
COMMIT_CONFIG_EOF

# commit_subject <branch> <type> <message> -> prints the recorded commit subject
commit_subject() {
    local branch="$1" type="$2" message="$3"
    git -C "${COMMIT_DIR}" checkout -q -B "${branch}"
    printf '%s\n' "${branch}" > "${COMMIT_DIR}/fixture.txt"
    git -C "${COMMIT_DIR}" add fixture.txt
    (cd "${COMMIT_DIR}" && "${HARNESS_ROOT}/bin/harness" commit build "${type}" "${message}" >/dev/null 2>&1)
    git -C "${COMMIT_DIR}" log -1 --pretty=%s
}

COMMIT_RELEASE_SUBJECT="$(commit_subject "chore/release-2.4.1" chore "release 2.4.1")"
if [ "${COMMIT_RELEASE_SUBJECT}" != "chore: release 2.4.1" ]; then
    echo "  [FAIL] commit build read an issue key out of a release version: ${COMMIT_RELEASE_SUBJECT}"
    exit 1
fi

COMMIT_BUMP_SUBJECT="$(commit_subject "fix/bump-node-22-1" fix "bump node to 22.1")"
if [ "${COMMIT_BUMP_SUBJECT}" != "fix: bump node to 22.1" ]; then
    echo "  [FAIL] commit build read an issue key out of a version bump: ${COMMIT_BUMP_SUBJECT}"
    exit 1
fi

COMMIT_TASK_SUBJECT="$(commit_subject "task/AH-11-slug" feat "keep the real key")"
if [ "${COMMIT_TASK_SUBJECT}" != "feat(AH-11): keep the real key" ]; then
    echo "  [FAIL] commit build dropped the issue key of a task branch: ${COMMIT_TASK_SUBJECT}"
    exit 1
fi

COMMIT_COMPAT_SUBJECT="$(commit_subject "fix/COMPAT-1-slug" fix "keep a single-digit key")"
if [ "${COMMIT_COMPAT_SUBJECT}" != "fix(COMPAT-1): keep a single-digit key" ]; then
    echo "  [FAIL] commit build dropped a single-digit issue key: ${COMMIT_COMPAT_SUBJECT}"
    exit 1
fi
echo "  [PASS] commit build scopes real issue keys and leaves version-like branches unscoped."

echo "=== 25. Testing Configuration Resolution ==="

# A repository with no configuration must resolve to the built-in defaults. The shipped
# config.example.json is documentation; while it acted as a fallback every unconfigured
# repository silently adopted its "backend" profile and its pytest/ruff/mypy commands.
CONFIG_BARE="${TMP_TEST_DIR}/config-bare"
mkdir -p "${CONFIG_BARE}"
git -C "${CONFIG_BARE}" init -q
BARE_VALIDATE="$(cd "${CONFIG_BARE}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" config validate 2>&1 || true)"
if ! printf '%s' "${BARE_VALIDATE}" | grep -q "Configuration file: none"; then
    echo "  [FAIL] config validate did not report an absent configuration as none: ${BARE_VALIDATE}"
    exit 1
fi
if printf '%s' "${BARE_VALIDATE}" | grep -q "config.example.json"; then
    echo "  [FAIL] config.example.json is still acting as a configuration fallback"
    exit 1
fi
BARE_PROFILE="$(cd "${CONFIG_BARE}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" context --json | jq -r '.profile')"
if [ "${BARE_PROFILE}" != "default" ]; then
    echo "  [FAIL] An unconfigured repository resolved to profile '${BARE_PROFILE}' instead of default"
    exit 1
fi
if ! (cd "${CONFIG_BARE}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" config validate >/dev/null 2>&1); then
    echo "  [FAIL] config validate failed on a repository with no configuration"
    exit 1
fi
echo "  [PASS] An unconfigured repository resolves to the built-in defaults."

# jq's // treats false as empty, so a configured false was replaced by the caller's
# default and nothing could be switched off by configuration.
CONFIG_FALSE="${TMP_TEST_DIR}/config-false"
mkdir -p "${CONFIG_FALSE}"
git -C "${CONFIG_FALSE}" init -q
cat > "${CONFIG_FALSE}/harness.config.json" <<'FALSE_CONFIG_EOF'
{
  "project": { "defaultProfile": "p" },
  "profiles": { "p": { "displayName": "P", "qa": { "testCommand": false } } }
}
FALSE_CONFIG_EOF
FALSE_VALUE="$(cd "${CONFIG_FALSE}" && STACK_PROFILE=p bash -c '
    source "'"${HARNESS_ROOT}"'/core/scripts/lib/utils.sh"
    source "'"${HARNESS_ROOT}"'/core/scripts/lib/config.sh"
    get_profile_value "qa.testCommand" "true"
')"
if [ "${FALSE_VALUE}" != "false" ]; then
    echo "  [FAIL] A configured false was reported as '${FALSE_VALUE}' instead of false"
    exit 1
fi
MISSING_VALUE="$(cd "${CONFIG_FALSE}" && STACK_PROFILE=p bash -c '
    source "'"${HARNESS_ROOT}"'/core/scripts/lib/utils.sh"
    source "'"${HARNESS_ROOT}"'/core/scripts/lib/config.sh"
    get_profile_value "qa.absentKey" "fallback"
')"
if [ "${MISSING_VALUE}" != "fallback" ]; then
    echo "  [FAIL] An absent key did not fall back to its default: '${MISSING_VALUE}'"
    exit 1
fi
echo "  [PASS] A configured false is distinguished from an absent key."

# Configuration values reached eval, so a configuration file could execute commands.
CONFIG_EVAL="${TMP_TEST_DIR}/config-eval"
EVAL_WITNESS="${TMP_TEST_DIR}/eval-witness"
mkdir -p "${CONFIG_EVAL}"
git -C "${CONFIG_EVAL}" init -q
cat > "${CONFIG_EVAL}/harness.config.json" <<EVAL_CONFIG_EOF
{
  "project": { "defaultProfile": "p" },
  "profiles": { "p": { "targetRepoPath": "\$(touch ${EVAL_WITNESS})", "rules": { "scanner": "\$(touch ${EVAL_WITNESS})" } } }
}
EVAL_CONFIG_EOF
(cd "${CONFIG_EVAL}" && STACK_PROFILE=p "${HARNESS_ROOT}/bin/harness" context >/dev/null 2>&1) || true
(cd "${CONFIG_EVAL}" && STACK_PROFILE=p "${HARNESS_ROOT}/bin/harness" scan --all >/dev/null 2>&1) || true
if [ -e "${EVAL_WITNESS}" ]; then
    echo "  [FAIL] A configuration value was evaluated as a shell command"
    exit 1
fi
echo "  [PASS] Configuration values are expanded, never evaluated."

# Structural validation, and an honest account of what it does not cover.
config_validate_in() {
    local directory="$1"
    (cd "${directory}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" config validate 2>&1)
}
config_validate_status() {
    local directory="$1"
    local status=0
    (cd "${directory}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" config validate >/dev/null 2>&1) || status=$?
    printf '%s' "${status}"
}

CONFIG_BROKEN="${TMP_TEST_DIR}/config-broken"
mkdir -p "${CONFIG_BROKEN}"
git -C "${CONFIG_BROKEN}" init -q
printf '{ "project": ' > "${CONFIG_BROKEN}/harness.config.json"
if [ "$(config_validate_status "${CONFIG_BROKEN}")" = "0" ]; then
    echo "  [FAIL] config validate accepted a file that is not valid JSON"
    exit 1
fi
BROKEN_OUTPUT="$(config_validate_in "${CONFIG_BROKEN}" || true)"
if ! printf '%s' "${BROKEN_OUTPUT}" | grep -q "not valid JSON"; then
    echo "  [FAIL] config validate did not name invalid JSON as the problem"
    exit 1
fi

CONFIG_SHAPE="${TMP_TEST_DIR}/config-shape"
mkdir -p "${CONFIG_SHAPE}"
git -C "${CONFIG_SHAPE}" init -q
cat > "${CONFIG_SHAPE}/harness.config.json" <<'SHAPE_CONFIG_EOF'
{
  "project": { "defaultProfile": "absent" },
  "profiles": { "p": { "qa": { "testCommand": ["not", "a", "string"] }, "unknownKey": 1 } }
}
SHAPE_CONFIG_EOF
SHAPE_OUTPUT="$(config_validate_in "${CONFIG_SHAPE}" || true)"
if [ "$(config_validate_status "${CONFIG_SHAPE}")" = "0" ]; then
    echo "  [FAIL] config validate accepted a configuration with type and reference errors"
    exit 1
fi
for expected in "qa.testCommand" "defaultProfile" "unknownKey"; do
    if ! printf '%s' "${SHAPE_OUTPUT}" | grep -q "${expected}"; then
        echo "  [FAIL] config validate did not report ${expected}: ${SHAPE_OUTPUT}"
        exit 1
    fi
done
if ! printf '%s' "${SHAPE_OUTPUT}" | grep -q "Not checked"; then
    echo "  [FAIL] config validate did not state which checks it could not perform"
    exit 1
fi
echo "  [PASS] config validate reports structural problems and names what it did not check."

echo ""
echo "=== 26. Testing Gate Refusals ==="

# The unconfigured lint and type defaults ended in `|| echo 'No linter configured'`, so a
# repository with neither tool passed both gates and `qa all` printed "All required QA
# gates passed" having checked nothing.
gates_repo() {
    local directory="$1"
    local qa_block="$2"
    mkdir -p "${directory}"
    git -C "${directory}" init -q
    git -C "${directory}" config user.email "tests@agent-harness.local"
    git -C "${directory}" config user.name "Agent Harness Tests"
    printf '[]\n' > "${directory}/rules.json"
    cat > "${directory}/harness.config.json" <<GATES_CONFIG_EOF
{
  "project": { "name": "gates", "defaultProfile": "p" },
  "profiles": { "p": { "qa": ${qa_block}, "rules": { "scanner": "./rules.json" } } }
}
GATES_CONFIG_EOF
    git -C "${directory}" add -A
    git -C "${directory}" commit -qm "fixture"
}

GATES_UNSET="${TMP_TEST_DIR}/gates-unset"
gates_repo "${GATES_UNSET}" '{ "testCommand": "true" }'

for gate in lint types; do
    GATE_STATUS=0
    GATE_OUTPUT="$(cd "${GATES_UNSET}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" qa "${gate}" 2>&1)" || GATE_STATUS=$?
    if [ "${GATE_STATUS}" -eq 0 ]; then
        echo "  [FAIL] qa ${gate} exited 0 with no checker configured"
        exit 1
    fi
    if ! printf '%s' "${GATE_OUTPUT}" | grep -q "could not run"; then
        echo "  [FAIL] qa ${gate} did not report that the gate could not run: ${GATE_OUTPUT}"
        exit 1
    fi
    case "${gate}" in
        lint) expected_key="qa.lintCommand" ;;
        types) expected_key="qa.typeCheckCommand" ;;
    esac
    if ! printf '%s' "${GATE_OUTPUT}" | grep -q "${expected_key}"; then
        echo "  [FAIL] qa ${gate} did not name ${expected_key} as the key to set: ${GATE_OUTPUT}"
        exit 1
    fi
done
echo "  [PASS] An unconfigured lint or type gate refuses instead of passing."

ALL_STATUS=0
ALL_OUTPUT="$(cd "${GATES_UNSET}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" qa all 2>&1)" || ALL_STATUS=$?
if [ "${ALL_STATUS}" -eq 0 ]; then
    echo "  [FAIL] qa all exited 0 while two gates could not run"
    exit 1
fi
if printf '%s' "${ALL_OUTPUT}" | grep -q "All required QA gates passed"; then
    echo "  [FAIL] qa all printed success while two gates could not run"
    exit 1
fi
if ! printf '%s' "${ALL_OUTPUT}" | grep -q "could not run: lint types"; then
    echo "  [FAIL] qa all did not name the gates that could not run: ${ALL_OUTPUT}"
    exit 1
fi
echo "  [PASS] qa all separates a gate that could not run from a gate that failed."

# A project with no linter may record that as a decision. It is the reason a configured
# false has to survive a lookup at all: the alternative is a gate nobody can satisfy.
GATES_DECLARED="${TMP_TEST_DIR}/gates-declared"
gates_repo "${GATES_DECLARED}" '{ "testCommand": "true", "lintCommand": false, "typeCheckCommand": false }'
DECLARED_STATUS=0
DECLARED_OUTPUT="$(cd "${GATES_DECLARED}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" qa all 2>&1)" || DECLARED_STATUS=$?
if [ "${DECLARED_STATUS}" -ne 0 ]; then
    echo "  [FAIL] qa all failed on a repository that declared it has no linter: ${DECLARED_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${DECLARED_OUTPUT}" | grep -q "declared" ; then
    echo "  [FAIL] qa all did not report the declared-absent gates: ${DECLARED_OUTPUT}"
    exit 1
fi
echo "  [PASS] A gate declared absent is reported as declared, not as passed."

# Without a usable jq the rule loop was skipped entirely and the scan printed
# "passed with 0 errors" -- the fail-open shape AH-9 left as an open question.
GATES_STUB="${TMP_TEST_DIR}/gates-stub"
mkdir -p "${GATES_STUB}"
cat > "${GATES_STUB}/jq" <<'JQ_STUB_EOF'
#!/usr/bin/env bash
exit 1
JQ_STUB_EOF
chmod +x "${GATES_STUB}/jq"
SCAN_NOJQ_STATUS=0
SCAN_NOJQ_OUTPUT="$(cd "${GATES_UNSET}" && PATH="${GATES_STUB}:${PATH}" "${HARNESS_ROOT}/bin/harness" scan --all 2>&1)" || SCAN_NOJQ_STATUS=$?
if [ "${SCAN_NOJQ_STATUS}" -eq 0 ]; then
    echo "  [FAIL] scan exited 0 without a usable jq: ${SCAN_NOJQ_OUTPUT}"
    exit 1
fi
if printf '%s' "${SCAN_NOJQ_OUTPUT}" | grep -q "passed with 0 errors"; then
    echo "  [FAIL] scan reported a passing scan without a usable jq"
    exit 1
fi
echo "  [PASS] The scanner refuses to report a result it could not compute."

# A failed push degraded to a warning and the pull request was opened anyway, for a
# branch that was never pushed.
SHIP_REPO="${TMP_TEST_DIR}/ship-repo"
gates_repo "${SHIP_REPO}" '{ "testCommand": "true", "lintCommand": "true", "typeCheckCommand": "true" }'
SHIP_STUB="${TMP_TEST_DIR}/ship-stub"
SHIP_WITNESS="${TMP_TEST_DIR}/ship-witness"
mkdir -p "${SHIP_STUB}"
cat > "${SHIP_STUB}/gh" <<SHIP_STUB_EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${SHIP_WITNESS}"
SHIP_STUB_EOF
chmod +x "${SHIP_STUB}/gh"
SHIP_STATUS=0
SHIP_OUTPUT="$(cd "${SHIP_REPO}" && PATH="${SHIP_STUB}:${PATH}" env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" ship 2>&1)" || SHIP_STATUS=$?
if [ "${SHIP_STATUS}" -eq 0 ]; then
    echo "  [FAIL] ship exited 0 although the branch could not be pushed: ${SHIP_OUTPUT}"
    exit 1
fi
if [ -e "${SHIP_WITNESS}" ]; then
    echo "  [FAIL] ship opened a pull request for a branch it had not pushed: $(cat "${SHIP_WITNESS}")"
    exit 1
fi
echo "  [PASS] ship stops at a failed push instead of opening a pull request."

# A subcommand named `check` that can only warn cannot be used as a gate.
COMMIT_CHECK_REPO="${TMP_TEST_DIR}/commit-check"
gates_repo "${COMMIT_CHECK_REPO}" '{ "testCommand": "true" }'
git -C "${COMMIT_CHECK_REPO}" commit -q --allow-empty -m "not a conventional message"
CHECK_STATUS=0
(cd "${COMMIT_CHECK_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" commit check >/dev/null 2>&1) || CHECK_STATUS=$?
if [ "${CHECK_STATUS}" -eq 0 ]; then
    echo "  [FAIL] commit check exited 0 on a message that does not conform"
    exit 1
fi
git -C "${COMMIT_CHECK_REPO}" commit -q --allow-empty -m "fix(AH-11): conform to the standard"
if ! (cd "${COMMIT_CHECK_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" commit check >/dev/null 2>&1); then
    echo "  [FAIL] commit check rejected a conforming message"
    exit 1
fi
echo "  [PASS] commit check fails on a non-conforming message."

echo ""
echo "=== 27. Testing Signal Truthfulness ==="

# context recursed into specs/archive/ while spec status did not, so the two disagreed:
# twelve "active" delta specs in a repository whose active count was zero.
SIGNAL_REPO="${TMP_TEST_DIR}/signals"
mkdir -p "${SIGNAL_REPO}/specs/archive/done"
git -C "${SIGNAL_REPO}" init -q
cat > "${SIGNAL_REPO}/harness.config.json" <<'SIGNAL_CONFIG_EOF'
{
  "project": { "name": "signals", "defaultProfile": "p" },
  "profiles": { "p": { "displayName": "Signals" } }
}
SIGNAL_CONFIG_EOF
printf '# Delta Spec: X\n' > "${SIGNAL_REPO}/specs/delta-AH-1-active.md"
printf '# Delta Spec: Y\n' > "${SIGNAL_REPO}/specs/archive/done/delta-AH-0-archived.md"
printf '# Delta Spec: Z\n' > "${SIGNAL_REPO}/specs/archive/done/delta-AH-2-archived.md"

SIGNAL_STATUS_COUNT="$(cd "${SIGNAL_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" spec status 2>/dev/null | grep -c 'delta-.*\.md' || true)"
SIGNAL_CONTEXT_COUNT="$(cd "${SIGNAL_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" context --json | jq -r '.activeDeltaSpecs')"
if [ "${SIGNAL_CONTEXT_COUNT}" != "1" ] || [ "${SIGNAL_STATUS_COUNT}" != "1" ]; then
    echo "  [FAIL] spec status reported ${SIGNAL_STATUS_COUNT} and context reported ${SIGNAL_CONTEXT_COUNT} active delta specs; both must be 1"
    exit 1
fi
echo "  [PASS] context and spec status agree on the active delta spec count."

# The debt count was computed by a ripgrep invocation with no fallback, so a machine
# without ripgrep reported zero markers -- indistinguishable from a repository that has none.
printf '# pragmatism: one\n# defer: two\n' > "${SIGNAL_REPO}/tracked.txt"
git -C "${SIGNAL_REPO}" add -A
git -C "${SIGNAL_REPO}" -c user.email=t@t -c user.name=t commit -qm fixture
DEBT_LISTED="$(cd "${SIGNAL_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" debt --json | jq -r 'length')"
DEBT_IN_CONTEXT="$(cd "${SIGNAL_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" context --json | jq -r '.technicalDebtMarkers')"
if [ "${DEBT_LISTED}" != "2" ] || [ "${DEBT_IN_CONTEXT}" != "2" ]; then
    echo "  [FAIL] debt reported ${DEBT_LISTED} markers and context reported ${DEBT_IN_CONTEXT}; both must be 2"
    exit 1
fi
echo "  [PASS] context and debt agree on the technical debt marker count."

# A scan that could not complete must not be reported as a count of zero.
if [ "$(id -u)" -ne 0 ]; then
    UNREADABLE_REPO="${TMP_TEST_DIR}/signals-unreadable"
    mkdir -p "${UNREADABLE_REPO}/locked"
    git -C "${UNREADABLE_REPO}" init -q
    printf '# pragmatism: hidden\n' > "${UNREADABLE_REPO}/locked/marker.txt"
    git -C "${UNREADABLE_REPO}" add -A
    git -C "${UNREADABLE_REPO}" -c user.email=t@t -c user.name=t commit -qm fixture
    chmod 000 "${UNREADABLE_REPO}/locked"
    UNREADABLE_CONTEXT="$(cd "${UNREADABLE_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" context --json 2>/dev/null | jq -r '.technicalDebtMarkers')"
    chmod 755 "${UNREADABLE_REPO}/locked"
    if [ "${UNREADABLE_CONTEXT}" = "0" ]; then
        echo "  [FAIL] context reported 0 debt markers for a scan that could not complete"
        exit 1
    fi
    if [ "${UNREADABLE_CONTEXT}" != "null" ]; then
        echo "  [FAIL] context reported '${UNREADABLE_CONTEXT}' instead of null for an incomplete scan"
        exit 1
    fi
    echo "  [PASS] An incomplete debt scan is reported as null, never as zero."
else
    echo "  [SKIP] Debt scan failure is not reproducible as root."
fi

# The JSON document was assembled by a heredoc, so a quote anywhere in a path or branch
# name produced a document no consumer could parse.
QUOTE_PARENT="${TMP_TEST_DIR}/quote-parent"
QUOTE_REPO="${QUOTE_PARENT}/re\"po"
mkdir -p "${QUOTE_REPO}"
git -C "${QUOTE_REPO}" init -q
if ! (cd "${QUOTE_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" context --json) | jq empty >/dev/null 2>&1; then
    echo "  [FAIL] context --json produced an unparseable document for a path containing a quote"
    exit 1
fi
echo "  [PASS] context --json is valid JSON for a path containing a quote."

# doctor claimed to diagnose symlinks, hooks, and configuration and checked none of them.
DOCTOR_CLAIMS_REPO="${TMP_TEST_DIR}/doctor-claims"
mkdir -p "${DOCTOR_CLAIMS_REPO}"
git -C "${DOCTOR_CLAIMS_REPO}" init -q
"${HARNESS_ROOT}/install.sh" --target "${DOCTOR_CLAIMS_REPO}" >/dev/null
DOCTOR_CLAIMS_HOME="${TMP_TEST_DIR}/doctor-claims-home"
mkdir -p "${DOCTOR_CLAIMS_HOME}"
DOCTOR_CLAIMS="$(cd "${DOCTOR_CLAIMS_REPO}" && env -u STACK_PROFILE HOME="${DOCTOR_CLAIMS_HOME}" "${HARNESS_ROOT}/bin/harness" doctor 2>&1 || true)"
for section in "CLI Installation" "Pre-Commit Hook" "Configuration"; do
    if ! printf '%s' "${DOCTOR_CLAIMS}" | grep -q "${section}"; then
        echo "  [FAIL] doctor does not report on ${section}: ${DOCTOR_CLAIMS}"
        exit 1
    fi
done
if ! printf '%s' "${DOCTOR_CLAIMS}" | grep -q "no agent-harness pre-commit hook"; then
    echo "  [FAIL] doctor did not report the absent pre-commit hook: ${DOCTOR_CLAIMS}"
    exit 1
fi

FOREIGN_HOOKS="$(git -C "${DOCTOR_CLAIMS_REPO}" rev-parse --git-path hooks)"
case "${FOREIGN_HOOKS}" in
    /*) ;;
    *) FOREIGN_HOOKS="${DOCTOR_CLAIMS_REPO}/${FOREIGN_HOOKS}" ;;
esac
mkdir -p "${FOREIGN_HOOKS}"
printf '#!/bin/sh\nexit 0\n' > "${FOREIGN_HOOKS}/pre-commit"
chmod +x "${FOREIGN_HOOKS}/pre-commit"
DOCTOR_FOREIGN="$(cd "${DOCTOR_CLAIMS_REPO}" && env -u STACK_PROFILE HOME="${DOCTOR_CLAIMS_HOME}" "${HARNESS_ROOT}/bin/harness" doctor 2>&1 || true)"
if ! printf '%s' "${DOCTOR_FOREIGN}" | grep -q "not written by agent-harness"; then
    echo "  [FAIL] doctor did not report a foreign pre-commit hook: ${DOCTOR_FOREIGN}"
    exit 1
fi

# A configuration doctor cannot validate is an error, not a silent pass.
printf '{ "project": ' > "${DOCTOR_CLAIMS_REPO}/harness.config.json"
DOCTOR_BADCONF_STATUS=0
(cd "${DOCTOR_CLAIMS_REPO}" && env -u STACK_PROFILE HOME="${DOCTOR_CLAIMS_HOME}" "${HARNESS_ROOT}/bin/harness" doctor >/dev/null 2>&1) || DOCTOR_BADCONF_STATUS=$?
if [ "${DOCTOR_BADCONF_STATUS}" -eq 0 ]; then
    echo "  [FAIL] doctor exited 0 with a configuration that is not valid JSON"
    exit 1
fi
echo "  [PASS] doctor checks the CLI installation, the pre-commit hook, and the configuration."

# --check-auth was advertised, parsed, and read by nothing.
DOCTOR_AUTH="$(cd "${SIGNAL_REPO}" && env -u STACK_PROFILE HOME="${DOCTOR_CLAIMS_HOME}" "${HARNESS_ROOT}/bin/harness" doctor --check-auth 2>&1 || true)"
if ! printf '%s' "${DOCTOR_AUTH}" | grep -q "Provider Authentication"; then
    echo "  [FAIL] doctor --check-auth reported nothing about provider authentication: ${DOCTOR_AUTH}"
    exit 1
fi
echo "  [PASS] doctor --check-auth reports provider authentication state."

# context was the only command reading repository facts that never asserted a repository
# exists. In a directory that is not one it answered branch "HEAD", dirty false, zero active
# specs and zero debt markers, and exited 0: five helpers each degrading reasonably on their
# own, composed into one confident document about a repository that is not there. It is also
# the first command every workflow runs, and the one whose numbers an agent cannot check.
CONTEXT_NOREPO="${TMP_TEST_DIR}/context-norepo"
mkdir -p "${CONTEXT_NOREPO}"
context_norepo() {
    CONTEXT_STATUS=0
    CONTEXT_OUTPUT="$( (cd "${CONTEXT_NOREPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" context "$@" 2>&1) )" || CONTEXT_STATUS=$?
}

for context_form in "text" "json"; do
    if [ "${context_form}" = "json" ]; then
        context_norepo --json
    else
        context_norepo
    fi
    if [ "${CONTEXT_STATUS}" -eq 0 ]; then
        echo "  [FAIL] context (${context_form}) exited 0 outside a repository: ${CONTEXT_OUTPUT}"
        exit 1
    fi
    if ! printf '%s' "${CONTEXT_OUTPUT}" | grep -q "not a git repository"; then
        echo "  [FAIL] context (${context_form}) did not say why it refused: ${CONTEXT_OUTPUT}"
        exit 1
    fi
    # Refusing is only half of it: none of the facts it used to invent may survive.
    for invented in '"branch"' '"dirty"' '"activeDeltaSpecs"' "Current Branch" "Working Tree"; do
        if printf '%s' "${CONTEXT_OUTPUT}" | grep -qF "${invented}"; then
            echo "  [FAIL] context (${context_form}) still reported ${invented} outside a repository: ${CONTEXT_OUTPUT}"
            exit 1
        fi
    done
done
echo "  [PASS] context refuses a directory that is not a repository instead of inventing one."

# --help is a claim about the CLI, not about a repository, so it still answers in one that
# does not exist yet -- which is exactly where someone asks what the command does.
context_norepo --help
if [ "${CONTEXT_STATUS}" -ne 0 ] || ! printf '%s' "${CONTEXT_OUTPUT}" | grep -q "Usage: harness context"; then
    echo "  [FAIL] context --help did not answer outside a repository (status ${CONTEXT_STATUS}): ${CONTEXT_OUTPUT}"
    exit 1
fi
echo "  [PASS] context --help answers without a repository."

echo ""
echo "=== 28. Testing Destructive Command Refusals ==="

# `worktree remove wt-AH` interpolated the key into grep as a pattern and removed every
# match with --force. In the reproduction it removed two worktrees and destroyed an
# unsaved file, with no prompt and no way to recover it.
WT_ROOT="${TMP_TEST_DIR}/worktrees"
WT_MAIN="${WT_ROOT}/wt"
mkdir -p "${WT_MAIN}"
git -C "${WT_MAIN}" init -q
git -C "${WT_MAIN}" config user.email "tests@agent-harness.local"
git -C "${WT_MAIN}" config user.name "Agent Harness Tests"
git -C "${WT_MAIN}" commit -q --allow-empty -m init

harness_wt() {
    (cd "${WT_MAIN}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" worktree "$@" 2>&1)
}
harness_wt_status() {
    local status=0
    (cd "${WT_MAIN}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" worktree "$@" >/dev/null 2>&1) || status=$?
    printf '%s' "${status}"
}
worktree_count() {
    git -C "${WT_MAIN}" worktree list | grep -c . || true
}

harness_wt create feat AH-1 alpha >/dev/null
harness_wt create feat AH-2 beta >/dev/null
if [ "$(worktree_count)" != "3" ]; then
    echo "  [FAIL] Fixture worktrees were not created"
    exit 1
fi

# The substring that used to match everything must now match nothing.
LOOSE_OUTPUT="$(harness_wt remove wt-AH || true)"
if [ "$(worktree_count)" != "3" ]; then
    echo "  [FAIL] A substring key removed worktrees: ${LOOSE_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${LOOSE_OUTPUT}" | grep -q "matches no worktree"; then
    echo "  [FAIL] A substring key did not report that it matches nothing: ${LOOSE_OUTPUT}"
    exit 1
fi
if [ "$(harness_wt_status remove wt-AH)" = "0" ]; then
    echo "  [FAIL] worktree remove exited 0 for a key that matches no worktree"
    exit 1
fi
echo "  [PASS] worktree remove matches an exact key, never a substring."

# --dry-run names the target and changes nothing.
DRY_OUTPUT="$(harness_wt remove AH-1 --dry-run)"
if [ "$(worktree_count)" != "3" ]; then
    echo "  [FAIL] --dry-run removed a worktree"
    exit 1
fi
if ! printf '%s' "${DRY_OUTPUT}" | grep -q "wt-AH-1"; then
    echo "  [FAIL] --dry-run did not name the worktree it would remove: ${DRY_OUTPUT}"
    exit 1
fi
echo "  [PASS] worktree remove --dry-run reports without mutating."

# Uncommitted work is never discarded without --force.
printf 'important\n' > "${WT_ROOT}/wt-AH-1/UNSAVED.txt"
DIRTY_OUTPUT="$(harness_wt remove AH-1 || true)"
if [ ! -f "${WT_ROOT}/wt-AH-1/UNSAVED.txt" ]; then
    echo "  [FAIL] worktree remove destroyed uncommitted work: ${DIRTY_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${DIRTY_OUTPUT}" | grep -q "uncommitted"; then
    echo "  [FAIL] worktree remove did not explain the refusal: ${DIRTY_OUTPUT}"
    exit 1
fi
if [ "$(harness_wt_status remove AH-1 --force)" != "0" ]; then
    echo "  [FAIL] worktree remove --force did not remove a dirty worktree"
    exit 1
fi
if [ "$(worktree_count)" != "2" ]; then
    echo "  [FAIL] worktree remove --force did not remove exactly one worktree"
    exit 1
fi
echo "  [PASS] worktree remove refuses uncommitted work unless forced."

# An ambiguous key is a refusal, not a guess about which of two to destroy.
# Created with git directly: `harness worktree create` derives the directory from the
# issue key, so two worktrees answering to one key can only be built by hand -- which is
# exactly the situation a branch-derived match has to refuse rather than guess at.
git -C "${WT_MAIN}" worktree add -q -b fix/AH-2-gamma "${WT_ROOT}/other-AH-2" HEAD
AMBIGUOUS_OUTPUT="$(harness_wt remove AH-2 || true)"
if printf '%s' "${AMBIGUOUS_OUTPUT}" | grep -q "Removed worktree"; then
    echo "  [FAIL] An ambiguous key removed a worktree: ${AMBIGUOUS_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${AMBIGUOUS_OUTPUT}" | grep -q "matches more than one worktree"; then
    echo "  [FAIL] An ambiguous key was not reported as ambiguous: ${AMBIGUOUS_OUTPUT}"
    exit 1
fi
if [ "$(worktree_count)" != "3" ]; then
    echo "  [FAIL] An ambiguous key changed the worktree list"
    exit 1
fi
echo "  [PASS] An ambiguous worktree key is refused."

# ./setup is advertised as a guided interactive installer and asked nothing, so running it
# from $HOME installed AGENTS.md, two symlinks, a config, rules, and four surfaces there.
GUIDED_HOME="${TMP_TEST_DIR}/guided-home"
GUIDED_CWD="${TMP_TEST_DIR}/guided-cwd"
mkdir -p "${GUIDED_HOME}" "${GUIDED_CWD}"
git -C "${GUIDED_CWD}" init -q
GUIDED_STATUS=0
GUIDED_OUTPUT="$(cd "${GUIDED_CWD}" && env HOME="${GUIDED_HOME}" "${HARNESS_ROOT}/setup" 2>&1 < /dev/null)" || GUIDED_STATUS=$?
if [ "${GUIDED_STATUS}" -eq 0 ]; then
    echo "  [FAIL] Guided setup installed without confirmation and without a terminal"
    exit 1
fi
if [ -f "${GUIDED_CWD}/AGENTS.md" ]; then
    echo "  [FAIL] Guided setup wrote into the current directory before being confirmed"
    exit 1
fi
for flag in "--yes" "--global" "--target"; do
    if ! printf '%s' "${GUIDED_OUTPUT}" | grep -q -- "${flag}"; then
        echo "  [FAIL] Guided setup did not name ${flag} as the explicit alternative: ${GUIDED_OUTPUT}"
        exit 1
    fi
done
echo "  [PASS] Guided setup refuses to install unconfirmed."

if ! (cd "${GUIDED_CWD}" && env HOME="${GUIDED_HOME}" "${HARNESS_ROOT}/setup" --yes >/dev/null 2>&1); then
    echo "  [FAIL] Guided setup --yes did not install"
    exit 1
fi
if [ ! -f "${GUIDED_CWD}/AGENTS.md" ]; then
    echo "  [FAIL] Guided setup --yes did not initialize the current directory"
    exit 1
fi
echo "  [PASS] Guided setup installs when it is explicitly confirmed."

# Every workflow the installed surface describes needs a repository.
GUIDED_NOGIT="${TMP_TEST_DIR}/guided-nogit"
mkdir -p "${GUIDED_NOGIT}"
NOGIT_STATUS=0
NOGIT_OUTPUT="$(cd "${GUIDED_NOGIT}" && env HOME="${GUIDED_HOME}" "${HARNESS_ROOT}/setup" --yes 2>&1)" || NOGIT_STATUS=$?
if [ "${NOGIT_STATUS}" -eq 0 ]; then
    echo "  [FAIL] Guided setup initialized a directory that is not a Git repository"
    exit 1
fi
if ! printf '%s' "${NOGIT_OUTPUT}" | grep -q "not a Git repository"; then
    echo "  [FAIL] Guided setup did not explain the refusal: ${NOGIT_OUTPUT}"
    exit 1
fi
TARGET_NOGIT="${TMP_TEST_DIR}/target-nogit"
mkdir -p "${TARGET_NOGIT}"
TARGET_NOGIT_OUTPUT="$("${HARNESS_ROOT}/install.sh" --target "${TARGET_NOGIT}" 2>&1)"
if ! printf '%s' "${TARGET_NOGIT_OUTPUT}" | grep -q "not a Git repository"; then
    echo "  [FAIL] An explicit --target did not warn about a directory that is not a Git repository"
    exit 1
fi
echo "  [PASS] A directory that is not a repository is refused when guided and reported when explicit."

# Every journal holds a full backup of every replaced file and nothing ever removed one.
PRUNE_STATE="${TMP_TEST_DIR}/prune-state"
PRUNE_HOME="${TMP_TEST_DIR}/prune-home"
mkdir -p "${PRUNE_STATE}" "${PRUNE_HOME}"
prune_run=0
while [ "${prune_run}" -lt 12 ]; do
    env HOME="${PRUNE_HOME}" HARNESS_STATE_DIR="${PRUNE_STATE}" \
        "${HARNESS_ROOT}/install.sh" --cli-only >/dev/null 2>&1
    prune_run=$((prune_run + 1))
done
PRUNE_COUNT="$(find "${PRUNE_STATE}/transactions" -mindepth 1 -maxdepth 1 -type d | grep -c . || true)"
if [ "${PRUNE_COUNT}" -gt 10 ]; then
    echo "  [FAIL] ${PRUNE_COUNT} transaction journals were retained; at most 10 are kept"
    exit 1
fi
if [ "${PRUNE_COUNT}" -lt 1 ]; then
    echo "  [FAIL] Journal pruning removed every journal, leaving nothing to roll back"
    exit 1
fi
if ! env HOME="${PRUNE_HOME}" HARNESS_STATE_DIR="${PRUNE_STATE}" \
        "${HARNESS_ROOT}/install.sh" --rollback >/dev/null 2>&1; then
    echo "  [FAIL] The most recent installation was no longer rollbackable after pruning"
    exit 1
fi
echo "  [PASS] Transaction journals are pruned and the latest stays rollbackable."

# `spec create` for a key and slug that already have a spec truncated it through the
# redirection that renders the template, replacing a spec someone had written with an empty
# one, and then reported "Created Delta Spec". A delta spec is the record of what a change
# is for; re-running the command that creates it is not a request to discard it.
#
# Both the template branch and the no-template fallback wrote with '>', so the refusal is
# asserted at the command, which is the one place that covers both.
SPEC_OVERWRITE_REPO="${TMP_TEST_DIR}/spec-overwrite"
mkdir -p "${SPEC_OVERWRITE_REPO}"
git -C "${SPEC_OVERWRITE_REPO}" init -q
git -C "${SPEC_OVERWRITE_REPO}" config user.email "tests@agent-harness.local"
git -C "${SPEC_OVERWRITE_REPO}" config user.name "Agent Harness Tests"
git -C "${SPEC_OVERWRITE_REPO}" commit -q --allow-empty -m init

harness_in_spec_overwrite() {
    (cd "${SPEC_OVERWRITE_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" "$@" 2>&1)
}

harness_in_spec_overwrite spec create AH-60 ordering >/dev/null
SPEC_OVERWRITE_FILE="${SPEC_OVERWRITE_REPO}/specs/delta-AH-60-ordering.md"
if [ ! -f "${SPEC_OVERWRITE_FILE}" ]; then
    echo "  [FAIL] spec create did not create the fixture spec"
    exit 1
fi
printf '\n## 5. Decision log\nThe queue was chosen over the cron job because ordering matters.\n' \
    >> "${SPEC_OVERWRITE_FILE}"
SPEC_OVERWRITE_BEFORE="$(git hash-object "${SPEC_OVERWRITE_FILE}")"

SPEC_OVERWRITE_STATUS=0
SPEC_OVERWRITE_OUTPUT="$(harness_in_spec_overwrite spec create AH-60 ordering)" || SPEC_OVERWRITE_STATUS=$?
if [ "${SPEC_OVERWRITE_STATUS}" -eq 0 ]; then
    echo "  [FAIL] spec create exited 0 for a spec that already exists"
    exit 1
fi
if [ "$(git hash-object "${SPEC_OVERWRITE_FILE}")" != "${SPEC_OVERWRITE_BEFORE}" ]; then
    echo "  [FAIL] spec create overwrote an existing delta spec: ${SPEC_OVERWRITE_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${SPEC_OVERWRITE_OUTPUT}" | grep -q "delta-AH-60-ordering.md"; then
    echo "  [FAIL] spec create did not name the spec it refused to replace: ${SPEC_OVERWRITE_OUTPUT}"
    exit 1
fi
if printf '%s' "${SPEC_OVERWRITE_OUTPUT}" | grep -q "Created Delta Spec"; then
    echo "  [FAIL] spec create reported creating a spec it did not create: ${SPEC_OVERWRITE_OUTPUT}"
    exit 1
fi

# The refusal is about this one spec, not about the command.
if ! harness_in_spec_overwrite spec create AH-60 batching >/dev/null; then
    echo "  [FAIL] spec create refused a spec that does not exist yet"
    exit 1
fi
if [ ! -f "${SPEC_OVERWRITE_REPO}/specs/delta-AH-60-batching.md" ]; then
    echo "  [FAIL] spec create did not create a spec whose path is free"
    exit 1
fi
echo "  [PASS] spec create refuses to replace an existing delta spec and preserves it."

echo ""
echo "=== 29. Testing Advertised Flags ==="

FLAGS_REPO="${TMP_TEST_DIR}/flags"
mkdir -p "${FLAGS_REPO}"
git -C "${FLAGS_REPO}" init -q
git -C "${FLAGS_REPO}" config user.email "tests@agent-harness.local"
git -C "${FLAGS_REPO}" config user.name "Agent Harness Tests"
cat > "${FLAGS_REPO}/harness.config.json" <<'FLAGS_CONFIG_EOF'
{
  "project": { "name": "flags", "defaultProfile": "p" },
  "profiles": { "p": { "displayName": "Flags", "git": { "trunkBranch": "trunk" } } }
}
FLAGS_CONFIG_EOF
git -C "${FLAGS_REPO}" add -A
git -C "${FLAGS_REPO}" commit -qm "fixture"
git -C "${FLAGS_REPO}" branch -M trunk
git -C "${FLAGS_REPO}" checkout -q -b other
git -C "${FLAGS_REPO}" commit -q --allow-empty -m "divergent"

harness_in_flags() {
    (cd "${FLAGS_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" "$@" 2>&1)
}

# --base was advertised by both commands and read from the fourth positional argument, so
# it reached git as a revision and printed git's usage text instead of creating a branch.
harness_in_flags branch create feat AH-50 from-trunk --base trunk >/dev/null
if [ "$(git -C "${FLAGS_REPO}" branch --show-current)" != "feat/AH-50-from-trunk" ]; then
    echo "  [FAIL] branch create --base did not create and check out the branch"
    exit 1
fi
if [ "$(git -C "${FLAGS_REPO}" rev-parse HEAD)" != "$(git -C "${FLAGS_REPO}" rev-parse trunk)" ]; then
    echo "  [FAIL] branch create --base did not branch from the named base"
    exit 1
fi
git -C "${FLAGS_REPO}" checkout -q other

harness_in_flags worktree create feat AH-51 wt-from-trunk --base trunk >/dev/null
FLAGS_WT="$(dirname "${FLAGS_REPO}")/$(basename "${FLAGS_REPO}")-AH-51"
if [ ! -d "${FLAGS_WT}" ]; then
    echo "  [FAIL] worktree create --base did not create the worktree"
    exit 1
fi
if [ "$(git -C "${FLAGS_WT}" rev-parse HEAD)" != "$(git -C "${FLAGS_REPO}" rev-parse trunk)" ]; then
    echo "  [FAIL] worktree create --base did not branch from the named base"
    exit 1
fi
echo "  [PASS] branch create and worktree create accept --base."

# --module was advertised and discarded. An active spec stays directly in specs/, which is
# what "active" means to both spec status and context, so the module is recorded inside the
# spec and read back by `spec archive` rather than changing where the file lives.
harness_in_flags spec create AH-52 modular --module catalogue >/dev/null
if [ ! -f "${FLAGS_REPO}/specs/delta-AH-52-modular.md" ]; then
    echo "  [FAIL] spec create --module did not create the spec: $(find "${FLAGS_REPO}/specs" -type f)"
    exit 1
fi
if ! grep -q "catalogue" "${FLAGS_REPO}/specs/delta-AH-52-modular.md"; then
    echo "  [FAIL] spec create --module did not record the module in the spec"
    exit 1
fi
if [ "$(cd "${FLAGS_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" spec status 2>/dev/null | grep -c 'delta-AH-52')" != "1" ]; then
    echo "  [FAIL] A spec created with --module is not reported as active"
    exit 1
fi
echo "  [PASS] spec create --module records the module and keeps the spec active."

# An issue key or slug that escapes specs/ reached sed and failed with a raw redirection error.
for bad in "a/b" ".." "../x"; do
    if harness_in_flags spec create AH-53 "${bad}" >/dev/null 2>&1; then
        echo "  [FAIL] spec create accepted an unsafe slug: ${bad}"
        exit 1
    fi
    UNSAFE_OUTPUT="$(harness_in_flags spec create AH-53 "${bad}" || true)"
    if ! printf '%s' "${UNSAFE_OUTPUT}" | grep -q "Unsafe"; then
        echo "  [FAIL] spec create did not name the slug as unsafe: ${bad} -> ${UNSAFE_OUTPUT}"
        exit 1
    fi
done
if harness_in_flags spec create "../etc" safe >/dev/null 2>&1; then
    echo "  [FAIL] spec create accepted an unsafe issue key"
    exit 1
fi
echo "  [PASS] spec create rejects an issue key or slug that escapes specs/."

# --all was advertised and dropped, so there was no way to reach an untracked marker.
printf '# pragmatism: untracked\n' > "${FLAGS_REPO}/loose.txt"
printf '// defer: slashes\n' > "${FLAGS_REPO}/tracked.ts"
git -C "${FLAGS_REPO}" add tracked.ts
git -C "${FLAGS_REPO}" commit -qm "tracked marker"
TRACKED_COUNT="$(harness_in_flags debt --json | jq -r 'length')"
ALL_COUNT="$(harness_in_flags debt --all --json | jq -r 'length')"
if [ "${TRACKED_COUNT}" != "1" ]; then
    echo "  [FAIL] debt reported ${TRACKED_COUNT} tracked markers; the // marker must count"
    exit 1
fi
if [ "${ALL_COUNT}" != "2" ]; then
    echo "  [FAIL] debt --all reported ${ALL_COUNT} markers; it must also see the untracked one"
    exit 1
fi
if ! harness_in_flags debt --json | jq -e '.[0] | has("file") and has("line") and has("text")' >/dev/null; then
    echo "  [FAIL] debt --json did not emit objects with file, line, and text"
    exit 1
fi
if ! harness_in_flags debt --path "${FLAGS_REPO}/tracked.ts" --json | jq -e 'length == 1' >/dev/null; then
    echo "  [FAIL] debt --path did not restrict the scan"
    exit 1
fi
# A colon in a path must not drop the finding: emitting fewer findings than the text
# listing shows is the same class of defect as reporting a count nothing computed.
mkdir -p "${FLAGS_REPO}/dir:with:colons"
printf '# defer: colon path\n' > "${FLAGS_REPO}/dir:with:colons/marker.py"
git -C "${FLAGS_REPO}" add -A
git -C "${FLAGS_REPO}" commit -qm "colon marker"
if ! harness_in_flags debt --json | jq -e '[.[] | select(.file | contains("dir:with:colons"))] | length == 1' >/dev/null; then
    echo "  [FAIL] debt --json dropped a finding whose path contains a colon: $(harness_in_flags debt --json)"
    exit 1
fi
echo "  [PASS] debt honours --all, --path, and emits a JSON array."

# `spec status [--json]` was advertised in the dispatcher help and the flag was dropped on
# the floor with every other argument, so the JSON form printed the human listing.
harness_in_flags spec create AH-55 second >/dev/null
STATUS_JSON="$(harness_in_flags spec status --json)"
if ! printf '%s' "${STATUS_JSON}" | jq empty >/dev/null 2>&1; then
    echo "  [FAIL] spec status --json did not emit JSON: ${STATUS_JSON}"
    exit 1
fi
if [ "$(printf '%s' "${STATUS_JSON}" | jq -r 'length')" != "2" ]; then
    echo "  [FAIL] spec status --json did not list both active specs: ${STATUS_JSON}"
    exit 1
fi
if ! printf '%s' "${STATUS_JSON}" | jq -e 'all(.[]; test("delta-.*[.]md$"))' >/dev/null; then
    echo "  [FAIL] spec status --json listed something that is not a delta spec: ${STATUS_JSON}"
    exit 1
fi
echo "  [PASS] spec status --json emits the active delta specs as JSON."

# README advertises autocompletion for Zsh and Bash; only the Zsh file was ever written.
COMPLETION_HOME="${TMP_TEST_DIR}/completion-home"
mkdir -p "${COMPLETION_HOME}"
env HOME="${COMPLETION_HOME}" "${HARNESS_ROOT}/bin/harness" completion install >/dev/null
if [ ! -f "${COMPLETION_HOME}/.zsh/completion/_harness" ]; then
    echo "  [FAIL] completion install wrote no Zsh completion"
    exit 1
fi
BASH_COMPLETION="${COMPLETION_HOME}/.local/share/bash-completion/completions/harness"
if [ ! -f "${BASH_COMPLETION}" ]; then
    echo "  [FAIL] completion install wrote no Bash completion"
    exit 1
fi
if ! bash -n "${BASH_COMPLETION}"; then
    echo "  [FAIL] The Bash completion is not valid Bash"
    exit 1
fi
for command_name in config receipt ledger sync; do
    if ! grep -q "${command_name}" "${BASH_COMPLETION}" || \
       ! grep -q "${command_name}" "${COMPLETION_HOME}/.zsh/completion/_harness"; then
        echo "  [FAIL] Completions do not offer '${command_name}'"
        exit 1
    fi
done
echo "  [PASS] completion install writes both a Zsh and a Bash completion."

# --profile with no value ran `shift 2` with one argument left, which under set -e exited 0
# having done nothing at all.
PROFILE_STATUS=0
PROFILE_OUTPUT="$(cd "${FLAGS_REPO}" && "${HARNESS_ROOT}/bin/harness" --profile 2>&1)" || PROFILE_STATUS=$?
if [ "${PROFILE_STATUS}" -eq 0 ]; then
    echo "  [FAIL] harness --profile with no value exited 0"
    exit 1
fi
if ! printf '%s' "${PROFILE_OUTPUT}" | grep -q "requires a profile name"; then
    echo "  [FAIL] harness --profile with no value did not name the missing argument: ${PROFILE_OUTPUT}"
    exit 1
fi
echo "  [PASS] harness --profile requires a value."

# An unknown recipe installed nothing and reported success.
RECIPE_TARGET="${TMP_TEST_DIR}/recipe-unknown"
mkdir -p "${RECIPE_TARGET}"
git -C "${RECIPE_TARGET}" init -q
RECIPE_STATUS=0
RECIPE_OUTPUT="$("${HARNESS_ROOT}/install.sh" --target "${RECIPE_TARGET}" --recipe pyton-fastapi 2>&1)" || RECIPE_STATUS=$?
if [ "${RECIPE_STATUS}" -eq 0 ]; then
    echo "  [FAIL] An unknown recipe installed successfully"
    exit 1
fi
if ! printf '%s' "${RECIPE_OUTPUT}" | grep -q "python-fastapi"; then
    echo "  [FAIL] An unknown recipe did not name the available recipes: ${RECIPE_OUTPUT}"
    exit 1
fi
if [ -f "${RECIPE_TARGET}/AGENTS.md" ]; then
    echo "  [FAIL] An unknown recipe left a partial installation behind"
    exit 1
fi
echo "  [PASS] An unknown recipe is refused and rolled back."

# A lowercase slug carrying a digit is not an issue key: feat/add-2fa-support committed as
# feat(add-2). The group above covers the version-like branches and the keys that must
# survive; this is the case it does not reach.
git -C "${FLAGS_REPO}" checkout -q -b feat/add-2fa-support
printf 'x\n' > "${FLAGS_REPO}/subject.txt"
git -C "${FLAGS_REPO}" add subject.txt
harness_in_flags commit build feat "support two-factor auth" >/dev/null
BUILT_MESSAGE="$(git -C "${FLAGS_REPO}" log -1 --pretty=%s)"
if [ "${BUILT_MESSAGE}" != "feat: support two-factor auth" ]; then
    echo "  [FAIL] commit build read an issue key out of a slug: ${BUILT_MESSAGE}"
    exit 1
fi
echo "  [PASS] commit build does not read an issue key out of a lowercase slug."

# commit build printed a success-shaped message and then surfaced git's own error.
EMPTY_INDEX_STATUS=0
EMPTY_INDEX_OUTPUT="$(harness_in_flags commit build feat "nothing is staged")" || EMPTY_INDEX_STATUS=$?
if [ "${EMPTY_INDEX_STATUS}" -eq 0 ]; then
    echo "  [FAIL] commit build committed with an empty index"
    exit 1
fi
if ! printf '%s' "${EMPTY_INDEX_OUTPUT}" | grep -q "Nothing is staged"; then
    echo "  [FAIL] commit build did not explain the empty index: ${EMPTY_INDEX_OUTPUT}"
    exit 1
fi
echo "  [PASS] commit build refuses an empty index."

# An option whose value was left off consumed the next argument -- which was not there --
# and `shift 2` failed under `set -e`. The command exited 1 having printed nothing at all,
# so `install.sh --target` with the path forgotten was indistinguishable from a crash. The
# scanner's own options have said what they require since they were written; these had not.
for missing_value_option in --target --recipe --sync-target --seed-target; do
    MISSING_STATUS=0
    MISSING_OUTPUT="$("${HARNESS_ROOT}/install.sh" "${missing_value_option}" 2>&1)" || MISSING_STATUS=$?
    if [ "${MISSING_STATUS}" -eq 0 ]; then
        echo "  [FAIL] install.sh ${missing_value_option} with no value exited 0"
        exit 1
    fi
    if ! printf '%s' "${MISSING_OUTPUT}" | grep -q -- "${missing_value_option} requires"; then
        echo "  [FAIL] install.sh ${missing_value_option} with no value said nothing: '${MISSING_OUTPUT}'"
        exit 1
    fi
done
SYNC_MISSING_STATUS=0
SYNC_MISSING_OUTPUT="$(harness_in_flags sync --target)" || SYNC_MISSING_STATUS=$?
if [ "${SYNC_MISSING_STATUS}" -eq 0 ]; then
    echo "  [FAIL] sync --target with no value exited 0"
    exit 1
fi
if ! printf '%s' "${SYNC_MISSING_OUTPUT}" | grep -q -- "--target requires"; then
    echo "  [FAIL] sync --target with no value said nothing: '${SYNC_MISSING_OUTPUT}'"
    exit 1
fi
echo "  [PASS] an option missing its value names what it requires instead of exiting silently."

echo ""
echo "=== 30. Testing Drift Of Unrecorded Surfaces ==="
# The drift check only ever compared the manifest against the catalog, so an entry that
# was in neither was invisible. In the audited installation fourteen obsolete skills --
# including `ship`, which the catalog marks removed -- were published into ~/.claude/skills
# from a second checkout while `harness sync --check` called the surface current. They were
# unreachable to repair too: remove_managed_skill only matched symlinks under the current
# HARNESS_ROOT, so no later run from any other checkout could clean them up.
UNRECORDED_TARGET="${TMP_TEST_DIR}/unrecorded-target"
mkdir -p "${UNRECORDED_TARGET}"
git -C "${UNRECORDED_TARGET}" init -q
"${HARNESS_ROOT}/install.sh" --target "${UNRECORDED_TARGET}" >/dev/null

UNRECORDED_SURFACE="${UNRECORDED_TARGET}/.claude/skills"
if ! "${HARNESS_ROOT}/bin/harness" sync --check --target "${UNRECORDED_TARGET}" >/dev/null 2>&1; then
    echo "  [FAIL] A freshly installed surface was already reported as drifted"
    exit 1
fi

# A bundle carrying the managed marker that no manifest records.
mkdir -p "${UNRECORDED_SURFACE}/harness-obsolete/references"
printf -- '---\nname: harness-obsolete\ndescription: gone\n---\n' > "${UNRECORDED_SURFACE}/harness-obsolete/SKILL.md"
printf 'agent-harness-skill-bundle-v1\n' > "${UNRECORDED_SURFACE}/harness-obsolete/.agent-harness-managed"

# A symlink into a checkout that is not this one, which is how the audited surface got its
# fourteen. The target must exist so the link is not merely broken.
FOREIGN_CHECKOUT="${TMP_TEST_DIR}/foreign-checkout"
mkdir -p "${FOREIGN_CHECKOUT}/core/skills/ship"
printf -- '---\nname: ship\ndescription: removed from the catalog\n---\n' > "${FOREIGN_CHECKOUT}/core/skills/ship/SKILL.md"
ln -s "${FOREIGN_CHECKOUT}/core/skills/ship" "${UNRECORDED_SURFACE}/ship"

UNRECORDED_REPORT="$("${HARNESS_ROOT}/bin/harness" sync --check --target "${UNRECORDED_TARGET}" 2>&1 || true)"
if "${HARNESS_ROOT}/bin/harness" sync --check --target "${UNRECORDED_TARGET}" >/dev/null 2>&1; then
    echo "  [FAIL] sync --check called a surface current while it published two unrecorded skills"
    exit 1
fi
for unrecorded in "harness-obsolete" "ship"; do
    if ! printf '%s' "${UNRECORDED_REPORT}" | grep -q "${unrecorded}"; then
        echo "  [FAIL] sync --check did not name the unrecorded skill '${unrecorded}': ${UNRECORDED_REPORT}"
        exit 1
    fi
done
echo "  [PASS] A managed skill no manifest records is reported as drift."

# An unmanaged directory is somebody else's, and must be left exactly where it is.
mkdir -p "${UNRECORDED_SURFACE}/somebody-elses-skill"
printf -- '---\nname: somebody-elses-skill\ndescription: not ours\n---\n' > "${UNRECORDED_SURFACE}/somebody-elses-skill/SKILL.md"

SYNC_REPAIR="$("${HARNESS_ROOT}/bin/harness" sync --target "${UNRECORDED_TARGET}" 2>&1)"
if [ -e "${UNRECORDED_SURFACE}/harness-obsolete" ] || [ -L "${UNRECORDED_SURFACE}/ship" ]; then
    echo "  [FAIL] sync left an unrecorded managed skill published: ${SYNC_REPAIR}"
    exit 1
fi
for removed in "harness-obsolete" "ship"; do
    if ! printf '%s' "${SYNC_REPAIR}" | grep -q "${removed}"; then
        echo "  [FAIL] sync removed '${removed}' without naming it: ${SYNC_REPAIR}"
        exit 1
    fi
done
if [ ! -f "${UNRECORDED_SURFACE}/somebody-elses-skill/SKILL.md" ]; then
    echo "  [FAIL] sync removed a skill agent-harness does not manage"
    exit 1
fi
if ! "${HARNESS_ROOT}/bin/harness" sync --check --target "${UNRECORDED_TARGET}" >/dev/null 2>&1; then
    echo "  [FAIL] The surface is still drifted after sync repaired it"
    exit 1
fi
echo "  [PASS] sync removes unrecorded managed skills by name and leaves unmanaged ones alone."

echo ""
echo "=== 31. Testing Scanner Paths And Suppression ==="
# The scanner could only ever match file *content*, so it could not express a forbidden
# filename -- which is the first thing a pre-commit gate is installed to stop. And with no
# escape hatch, one false positive left --no-verify as the only option, retiring the whole
# gate rather than one line.
PATHS_REPO="${TMP_TEST_DIR}/scanner-paths"
mkdir -p "${PATHS_REPO}"
git -C "${PATHS_REPO}" init -q
git -C "${PATHS_REPO}" config user.email "tests@agent-harness.local"
git -C "${PATHS_REPO}" config user.name "Agent Harness Tests"

scan_paths() {
    SCAN_PATHS_STATUS=0
    SCAN_PATHS_OUTPUT="$(cd "${PATHS_REPO}" && "${HARNESS_ROOT}/bin/harness" scan --all --rules "$1" 2>&1)" || SCAN_PATHS_STATUS=$?
}

PATH_RULES="${TMP_TEST_DIR}/path-rules.json"
cat > "${PATH_RULES}" <<'PATH_RULES_EOF'
[
  {
    "id": "PATH-001",
    "name": "Environment file",
    "pathPattern": "(^|/)\\.env([.][^/]+)?$",
    "excludePaths": ["*.example"],
    "level": "error",
    "message": "Environment files must not be committed."
  },
  {
    "id": "CONTENT-001",
    "name": "Forbidden content",
    "pattern": "FORBIDDEN_CONTENT",
    "level": "error",
    "message": "Remove the forbidden content."
  },
  {
    "id": "SCOPED-001",
    "name": "Scoped content",
    "pattern": "SCOPED_MARKER",
    "excludePaths": ["vendor/*", "*.generated.js"],
    "level": "error",
    "message": "Remove the scoped marker."
  }
]
PATH_RULES_EOF

printf 'SECRET=1\n' > "${PATHS_REPO}/.env"
printf 'SECRET=example\n' > "${PATHS_REPO}/.env.example"
git -C "${PATHS_REPO}" add -A -f
scan_paths "${PATH_RULES}"
if [ "${SCAN_PATHS_STATUS}" -eq 0 ]; then
    echo "  [FAIL] A pathPattern rule did not flag a committed .env: ${SCAN_PATHS_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${SCAN_PATHS_OUTPUT}" | grep -q "PATH-001"; then
    echo "  [FAIL] The pathPattern finding did not name its rule: ${SCAN_PATHS_OUTPUT}"
    exit 1
fi
if printf '%s' "${SCAN_PATHS_OUTPUT}" | grep -q "\.env\.example"; then
    echo "  [FAIL] excludePaths did not exempt .env.example: ${SCAN_PATHS_OUTPUT}"
    exit 1
fi
git -C "${PATHS_REPO}" rm -q --cached .env >/dev/null
rm -f "${PATHS_REPO}/.env"
echo "  [PASS] A pathPattern rule matches a forbidden filename and honours excludePaths."

# Suppression on the matching line and on the line above it.
printf 'ok = 1\nvalue = "FORBIDDEN_CONTENT"  # harness-ignore: CONTENT-001\n' > "${PATHS_REPO}/inline.py"
printf '# harness-ignore: CONTENT-001\nvalue = "FORBIDDEN_CONTENT"\n' > "${PATHS_REPO}/above.py"
git -C "${PATHS_REPO}" add -A
scan_paths "${PATH_RULES}"
if [ "${SCAN_PATHS_STATUS}" -ne 0 ]; then
    echo "  [FAIL] Suppressed findings still failed the scan: ${SCAN_PATHS_OUTPUT}"
    exit 1
fi
echo "  [PASS] harness-ignore suppresses a finding on its line and on the line below."

# Suppression is per rule: naming one rule must not silence another.
printf 'value = "FORBIDDEN_CONTENT"  # harness-ignore: PATH-001\n' > "${PATHS_REPO}/wrong-rule.py"
git -C "${PATHS_REPO}" add -A
scan_paths "${PATH_RULES}"
if [ "${SCAN_PATHS_STATUS}" -eq 0 ]; then
    echo "  [FAIL] A harness-ignore for one rule silenced another: ${SCAN_PATHS_OUTPUT}"
    exit 1
fi
rm -f "${PATHS_REPO}/wrong-rule.py"
git -C "${PATHS_REPO}" add -A
echo "  [PASS] harness-ignore names one rule and silences only that rule."

# excludePaths on a content rule.
mkdir -p "${PATHS_REPO}/vendor"
printf 'SCOPED_MARKER\n' > "${PATHS_REPO}/vendor/lib.js"
printf 'SCOPED_MARKER\n' > "${PATHS_REPO}/bundle.generated.js"
git -C "${PATHS_REPO}" add -A
scan_paths "${PATH_RULES}"
if [ "${SCAN_PATHS_STATUS}" -ne 0 ]; then
    echo "  [FAIL] excludePaths did not exempt a content-rule match: ${SCAN_PATHS_OUTPUT}"
    exit 1
fi
printf 'SCOPED_MARKER\n' > "${PATHS_REPO}/app.js"
git -C "${PATHS_REPO}" add -A
scan_paths "${PATH_RULES}"
if [ "${SCAN_PATHS_STATUS}" -eq 0 ]; then
    echo "  [FAIL] excludePaths exempted a path it does not cover: ${SCAN_PATHS_OUTPUT}"
    exit 1
fi
rm -f "${PATHS_REPO}/app.js"
git -C "${PATHS_REPO}" add -A
echo "  [PASS] excludePaths scopes a content rule without disabling it."

# A rule must say what it matches, exactly once.
for broken in '[{"id":"B1","name":"n","level":"error","message":"m"}]' \
              '[{"id":"B2","name":"n","pattern":"a","pathPattern":"b","level":"error","message":"m"}]'; do
    BROKEN_RULES="${TMP_TEST_DIR}/broken-rule.json"
    printf '%s\n' "${broken}" > "${BROKEN_RULES}"
    scan_paths "${BROKEN_RULES}"
    if [ "${SCAN_PATHS_STATUS}" -eq 0 ]; then
        echo "  [FAIL] The scanner accepted a rule that does not name exactly one matcher: ${broken}"
        exit 1
    fi
done
echo "  [PASS] A rule must carry exactly one of pattern or pathPattern."

# The shipped rules refuse secret material by path.
for shipped_rules in "${HARNESS_ROOT}/rules/landmines.json" "${HARNESS_ROOT}/core/templates/landmines-template.json"; do
    if ! jq -e '[.[] | select(.id == "SEC-003")] | length == 1' "${shipped_rules}" >/dev/null; then
        echo "  [FAIL] ${shipped_rules} does not ship SEC-003"
        exit 1
    fi
    for secret_path in ".env" ".env.production" "deploy/server.pem" "certs/private.key" "home/id_rsa"; do
        mkdir -p "${PATHS_REPO}/$(dirname "${secret_path}")"
        printf 'x\n' > "${PATHS_REPO}/${secret_path}"
        git -C "${PATHS_REPO}" add -A -f
        scan_paths "${shipped_rules}"
        if [ "${SCAN_PATHS_STATUS}" -eq 0 ]; then
            echo "  [FAIL] ${shipped_rules} did not refuse ${secret_path}: ${SCAN_PATHS_OUTPUT}"
            exit 1
        fi
        git -C "${PATHS_REPO}" rm -q --cached "${secret_path}" >/dev/null
        rm -f "${PATHS_REPO}/${secret_path}"
    done
    printf 'x\n' > "${PATHS_REPO}/.env.example"
    git -C "${PATHS_REPO}" add -A -f
    scan_paths "${shipped_rules}"
    if [ "${SCAN_PATHS_STATUS}" -ne 0 ]; then
        echo "  [FAIL] ${shipped_rules} refused .env.example: ${SCAN_PATHS_OUTPUT}"
        exit 1
    fi
done
echo "  [PASS] The shipped rules refuse environment files and key material by path."

# Every recipe declares a scanner and must ship the rules it declares.
for recipe_config in "${HARNESS_ROOT}"/recipes/*/stack.config.json; do
    recipe_dir="$(dirname "${recipe_config}")"
    declared="$(jq -r '.profiles | to_entries[0].value.rules.scanner // empty' "${recipe_config}")"
    if [ -z "${declared}" ]; then
        echo "  [FAIL] $(basename "${recipe_dir}") declares no scanner rules"
        exit 1
    fi
    recipe_rules="${recipe_dir}/${declared#./}"
    if [ ! -f "${recipe_rules}" ] || ! jq empty "${recipe_rules}" >/dev/null 2>&1; then
        echo "  [FAIL] $(basename "${recipe_dir}") declares ${declared} and does not ship it"
        exit 1
    fi
    if ! jq -e 'length > 0 and all(.[];
            has("id") and has("name") and has("level") and has("message") and
            (((has("pattern") | if . then 1 else 0 end) + (has("pathPattern") | if . then 1 else 0 end)) == 1))' \
        "${recipe_rules}" >/dev/null; then
        echo "  [FAIL] ${recipe_rules} contains a rule that is not well formed"
        exit 1
    fi
    scan_paths "${recipe_rules}"
    if [ "${SCAN_PATHS_STATUS}" -ne 0 ]; then
        echo "  [FAIL] ${recipe_rules} could not be run by the scanner: ${SCAN_PATHS_OUTPUT}"
        exit 1
    fi
done
echo "  [PASS] Every recipe ships the scanner rules its configuration declares."

echo ""
echo "=== 32. Testing Receipt Read Path ==="
# The receipt command has been write-only since AH-3: it produced an observability record
# that the user it was produced for could not read back, and nothing ever removed one.
RECEIPT_READ_REPO="${TMP_TEST_DIR}/receipt-read"
mkdir -p "${RECEIPT_READ_REPO}"
git -C "${RECEIPT_READ_REPO}" init -q
git -C "${RECEIPT_READ_REPO}" config user.email "tests@agent-harness.local"
git -C "${RECEIPT_READ_REPO}" config user.name "Agent Harness Tests"
git -C "${RECEIPT_READ_REPO}" commit -q --allow-empty -m init
git -C "${RECEIPT_READ_REPO}" checkout -q -b task/AH-60-read-path

receipt_in() {
    (cd "${RECEIPT_READ_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" receipt "$@")
}

OPEN_RUN="$(receipt_in start implement --issue AH-60)"
receipt_in phase "${OPEN_RUN}" understand passed
CLOSED_RUN="$(receipt_in start fix --issue AH-61)"
receipt_in phase "${CLOSED_RUN}" reproduce passed
receipt_in finish "${CLOSED_RUN}" completed

LIST_OUTPUT="$(receipt_in list)"
for expected in "${OPEN_RUN}" "${CLOSED_RUN}" "AH-60" "AH-61" "task/AH-60-read-path" "implement" "fix"; do
    if ! printf '%s' "${LIST_OUTPUT}" | grep -qF "${expected}"; then
        echo "  [FAIL] receipt list did not report '${expected}': ${LIST_OUTPUT}"
        exit 1
    fi
done
if ! printf '%s' "${LIST_OUTPUT}" | grep -F "${OPEN_RUN}" | grep -q "open"; then
    echo "  [FAIL] receipt list did not mark the unfinished run as open: ${LIST_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${LIST_OUTPUT}" | grep -F "${CLOSED_RUN}" | grep -q "completed"; then
    echo "  [FAIL] receipt list did not report the finished run's outcome: ${LIST_OUTPUT}"
    exit 1
fi
echo "  [PASS] receipt list reports every run, its issue, its branch, and whether it is open."

SHOW_OUTPUT="$(receipt_in show "${CLOSED_RUN}")"
for expected in "workflow_started" "reproduce" "workflow_finished" "completed"; do
    if ! printf '%s' "${SHOW_OUTPUT}" | grep -qF "${expected}"; then
        echo "  [FAIL] receipt show did not report '${expected}': ${SHOW_OUTPUT}"
        exit 1
    fi
done
if receipt_in show "no-such-run" >/dev/null 2>&1; then
    echo "  [FAIL] receipt show accepted a run that does not exist"
    exit 1
fi
echo "  [PASS] receipt show prints one run's events."

# An abandoned run is a finding, not litter, so pruning never touches a run that is open.
PRUNE_RUNS=""
prune_index=0
while [ "${prune_index}" -lt 4 ]; do
    extra_run="$(receipt_in start investigate)"
    receipt_in finish "${extra_run}" completed
    PRUNE_RUNS="${PRUNE_RUNS}${extra_run}
"
    prune_index=$((prune_index + 1))
done
SECOND_OPEN="$(receipt_in start investigate)"

PRUNE_OUTPUT="$(receipt_in prune --keep 2)"
if ! printf '%s' "${PRUNE_OUTPUT}" | grep -q "3"; then
    echo "  [FAIL] receipt prune did not report how many receipts it removed: ${PRUNE_OUTPUT}"
    exit 1
fi
REMAINING="$(receipt_in list)"
for still_open in "${OPEN_RUN}" "${SECOND_OPEN}"; do
    if ! printf '%s' "${REMAINING}" | grep -qF "${still_open}"; then
        echo "  [FAIL] receipt prune removed a run that is still open: ${still_open}"
        exit 1
    fi
done
TERMINAL_LEFT="$(printf '%s' "${REMAINING}" | grep -c "completed" || true)"
if [ "${TERMINAL_LEFT}" != "2" ]; then
    echo "  [FAIL] receipt prune left ${TERMINAL_LEFT} terminal receipts instead of 2: ${REMAINING}"
    exit 1
fi
echo "  [PASS] receipt prune keeps the newest terminal receipts and never prunes an open run."

echo ""
echo "=== 33. Testing Branch-Range Scanning ==="
# The scan gate inside `qa all` ran in --diff mode, which reads the working tree against
# HEAD. On a finished branch that set is empty, so a secret committed two commits earlier
# was reported as "No files to scan." and the aggregate suite printed that every gate
# passed -- the exact moment before `harness ship` pushes it.
RANGE_REPO="${TMP_TEST_DIR}/scan-range"
mkdir -p "${RANGE_REPO}"
git -C "${RANGE_REPO}" init -q
git -C "${RANGE_REPO}" config user.email "tests@agent-harness.local"
git -C "${RANGE_REPO}" config user.name "Agent Harness Tests"

write_range_config() {
    cat > "${RANGE_REPO}/harness.config.json" <<RANGE_CONFIG_EOF
{
  "project": { "defaultProfile": "range" },
  "profiles": {
    "range": {
      "git": { "trunkBranch": "$1" },
      "qa": { "testCommand": false, "lintCommand": false, "typeCheckCommand": false }
    }
  }
}
RANGE_CONFIG_EOF
}

write_range_config "main"
git -C "${RANGE_REPO}" add -A
git -C "${RANGE_REPO}" commit -q -m "init"
git -C "${RANGE_REPO}" branch -M main
git -C "${RANGE_REPO}" checkout -q -b feat/AH-13-leak
printf 'api_key = "ABCDEFGHIJKLMNOP0123"\n' > "${RANGE_REPO}/leak.py"
git -C "${RANGE_REPO}" add -A
git -C "${RANGE_REPO}" commit -q -m "add leak"

range_harness() {
    RANGE_STATUS=0
    RANGE_OUTPUT="$( (cd "${RANGE_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" "$@" 2>&1) )" || RANGE_STATUS=$?
}

range_harness qa all
if [ "${RANGE_STATUS}" -eq 0 ]; then
    echo "  [FAIL] qa all passed with a secret committed on the branch: ${RANGE_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${RANGE_OUTPUT}" | grep -q "SEC-001"; then
    echo "  [FAIL] the qa scan gate did not read the branch's committed change: ${RANGE_OUTPUT}"
    exit 1
fi
echo "  [PASS] qa all scans everything the branch changes, not only the working tree."

range_harness scan --branch
if [ "${RANGE_STATUS}" -ne 1 ]; then
    echo "  [FAIL] scan --branch did not fail on a committed finding (status ${RANGE_STATUS}): ${RANGE_OUTPUT}"
    exit 1
fi
range_harness scan --branch --base main
if [ "${RANGE_STATUS}" -ne 1 ]; then
    echo "  [FAIL] scan --branch --base did not fail on a committed finding (status ${RANGE_STATUS}): ${RANGE_OUTPUT}"
    exit 1
fi
echo "  [PASS] scan --branch reads the range, and --base names it explicitly."

# What the branch changes is committed work plus everything already on its way into a
# commit: a tracked file edited but not committed, and a new file staged. An untracked file
# is deliberately outside that set -- it will not be pushed, so flagging it would fail a
# branch for a scratch file it does not carry.
printf 'ok = 1\n' > "${RANGE_REPO}/edited.py"
git -C "${RANGE_REPO}" add -A
git -C "${RANGE_REPO}" commit -q -m "add a clean tracked file"
printf 'auth_token = "ZYXWVUTSRQPONMLK9876"\n' > "${RANGE_REPO}/edited.py"
printf 'secret_key = "MLKJIHGFEDCBA9876543"\n' > "${RANGE_REPO}/staged.py"
git -C "${RANGE_REPO}" add staged.py
printf 'bearer = "QQQQWWWWEEEERRRRTTTT"\n' > "${RANGE_REPO}/untracked.py"
range_harness scan --branch
for expected in "edited.py" "staged.py"; do
    if ! printf '%s' "${RANGE_OUTPUT}" | grep -q "${expected}"; then
        echo "  [FAIL] scan --branch did not read ${expected}: ${RANGE_OUTPUT}"
        exit 1
    fi
done
if printf '%s' "${RANGE_OUTPUT}" | grep -q "untracked.py"; then
    echo "  [FAIL] scan --branch flagged an untracked file the branch does not carry: ${RANGE_OUTPUT}"
    exit 1
fi
git -C "${RANGE_REPO}" rm -q --cached staged.py >/dev/null
rm -f "${RANGE_REPO}/staged.py" "${RANGE_REPO}/untracked.py"
git -C "${RANGE_REPO}" checkout -q -- edited.py
echo "  [PASS] scan --branch covers committed, edited, and staged work, and stops there."

# A range that cannot be resolved is a gate that could not run, which stack-qa.sh reports
# as such. Reporting it as a clean scan is the defect this group exists to keep closed.
range_harness scan --branch --base no/such/ref
if [ "${RANGE_STATUS}" -ne 2 ]; then
    echo "  [FAIL] an unresolvable base did not exit 2 (status ${RANGE_STATUS}): ${RANGE_OUTPUT}"
    exit 1
fi
write_range_config "no-such-trunk"
range_harness qa all
if [ "${RANGE_STATUS}" -eq 0 ]; then
    echo "  [FAIL] qa all passed while its scan gate could not resolve a range: ${RANGE_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${RANGE_OUTPUT}" | grep -q "could not run"; then
    echo "  [FAIL] qa all did not report the scan gate as unrunnable: ${RANGE_OUTPUT}"
    exit 1
fi
write_range_config "main"
echo "  [PASS] an unresolvable range reports a gate that could not run, never a clean scan."

# The review protocol named `harness scan --diff` as its static gate and the quality floor
# repeated it. --diff answers "what have I not committed yet", and review runs after the
# work is committed -- `harness ship` refuses to publish a branch with uncommitted tracked
# changes -- so the gate the protocol prescribed was structurally unable to read the code
# it was reviewing. It is the same fail-open `qa all` was moved off above: the aggregation
# was corrected there and the prose an agent actually follows was left naming the old mode.
#
# The two assertions below are the evidence and the rule. The evidence has to hold for the
# rule to mean anything, so it is checked rather than asserted in a comment.
range_harness scan --diff
if [ "${RANGE_STATUS}" -ne 0 ] || ! printf '%s' "${RANGE_OUTPUT}" | grep -q "the diff selection is empty"; then
    echo "  [FAIL] scan --diff did not read an empty set on a clean tree (status ${RANGE_STATUS}): ${RANGE_OUTPUT}"
    exit 1
fi
range_harness scan --branch
if [ "${RANGE_STATUS}" -ne 1 ]; then
    echo "  [FAIL] scan --branch did not read the finding the same clean tree carries: ${RANGE_OUTPUT}"
    exit 1
fi
echo "  [PASS] on a committed branch --diff reads nothing while --branch reads the change."

for gate_document in \
    "core/skills/review/SKILL.md" \
    "rules/floor.md" \
    "core/templates/AGENTS-template.md" \
    "AGENTS.md"; do
    if grep -Fq "scan --diff" "${HARNESS_ROOT}/${gate_document}"; then
        echo "  [FAIL] ${gate_document} prescribes scan --diff, which reads nothing at review time"
        exit 1
    fi
    if ! grep -Fq "scan --branch" "${HARNESS_ROOT}/${gate_document}"; then
        echo "  [FAIL] ${gate_document} gates on a scan without naming the mode that reads the branch"
        exit 1
    fi
done
echo "  [PASS] every protocol that gates on a scan names the mode that reads the branch."

echo ""
echo "=== 34. Testing Scanner Argument Refusals ==="
# `harness scan --al` scanned the empty staged set and exited 0, and a rules path that did
# not resolve was replaced by the built-in template. Both answered a question nobody asked
# and called the answer a pass.
REFUSAL_REPO="${TMP_TEST_DIR}/argument-refusals"
mkdir -p "${REFUSAL_REPO}"
git -C "${REFUSAL_REPO}" init -q
git -C "${REFUSAL_REPO}" config user.email "tests@agent-harness.local"
git -C "${REFUSAL_REPO}" config user.name "Agent Harness Tests"
printf 'api_key = "ABCDEFGHIJKLMNOP0123"\n' > "${REFUSAL_REPO}/leak.py"
git -C "${REFUSAL_REPO}" add -A
git -C "${REFUSAL_REPO}" commit -q -m "init"

assert_refuses() {
    local label="$1"
    shift
    local status=0 output
    output="$( (cd "${REFUSAL_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" "$@" 2>&1) )" || status=$?
    if [ "${status}" -eq 0 ]; then
        echo "  [FAIL] ${label} accepted '$2' instead of refusing it: ${output}"
        exit 1
    fi
    if ! printf '%s' "${output}" | grep -qF -- "$2"; then
        echo "  [FAIL] ${label} refused '$2' without naming it: ${output}"
        exit 1
    fi
}

assert_refuses "harness scan" scan --al
assert_refuses "harness context" context --jsonn
assert_refuses "harness doctor" doctor --fixx
echo "  [PASS] scan, context, and doctor refuse an option they do not define."

assert_refuses "harness scan" scan --force
echo "  [PASS] scan refuses --force without the --install-hook it modifies."

REFUSAL_STATUS=0
REFUSAL_OUTPUT="$( (cd "${REFUSAL_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" \
    scan --all --rules "${TMP_TEST_DIR}/no-such-rules.json" 2>&1) )" || REFUSAL_STATUS=$?
if [ "${REFUSAL_STATUS}" -ne 2 ]; then
    echo "  [FAIL] a --rules path that does not resolve did not abort (status ${REFUSAL_STATUS}): ${REFUSAL_OUTPUT}"
    exit 1
fi
cat > "${REFUSAL_REPO}/harness.config.json" <<'REFUSAL_CONFIG_EOF'
{
  "project": { "defaultProfile": "refusal" },
  "profiles": { "refusal": { "rules": { "scanner": "./rules/renamed-away.json" } } }
}
REFUSAL_CONFIG_EOF
REFUSAL_STATUS=0
REFUSAL_OUTPUT="$( (cd "${REFUSAL_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" scan --all 2>&1) )" || REFUSAL_STATUS=$?
if [ "${REFUSAL_STATUS}" -ne 2 ]; then
    echo "  [FAIL] a configured rules.scanner that does not resolve did not abort (status ${REFUSAL_STATUS}): ${REFUSAL_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${REFUSAL_OUTPUT}" | grep -q "renamed-away.json"; then
    echo "  [FAIL] the refusal did not name the rule file it could not read: ${REFUSAL_OUTPUT}"
    exit 1
fi
rm -f "${REFUSAL_REPO}/harness.config.json"
echo "  [PASS] rules that were requested and cannot be read abort instead of falling back."

echo ""
echo "=== 35. Testing Worktree Surface Continuity ==="
# `worktree create` reported that a directory existed and stopped there. Skill surfaces are
# installation artifacts rather than tracked files, so a project that keeps them out of Git
# got a worktree with no skills and no CLAUDE.md -- and references/worktree.md sends the
# agent into exactly that directory as phase 2 of harness-implement.
WT_ROOT="${TMP_TEST_DIR}/worktree-surface"
mkdir -p "${WT_ROOT}"
WT_REPO="${WT_ROOT}/project"
git init -q "${WT_REPO}"
git -C "${WT_REPO}" config user.email "tests@agent-harness.local"
git -C "${WT_REPO}" config user.name "Agent Harness Tests"
printf '# project\n' > "${WT_REPO}/README.md"
git -C "${WT_REPO}" add -A
git -C "${WT_REPO}" commit -q -m init
# The configuration harness init writes declares trunkBranch: main, so the fixture has to
# be on main. Without this the test passed wherever init.defaultBranch was already main and
# failed everywhere else with "fatal: invalid reference: main".
git -C "${WT_REPO}" branch -M main

HOME_FOR_WT="${WT_ROOT}/home"
mkdir -p "${HOME_FOR_WT}"
wt_install() {
    (cd "${WT_REPO}" && env -u STACK_PROFILE HOME="${HOME_FOR_WT}" \
        HARNESS_STATE_DIR="${WT_ROOT}/state" "${HARNESS_ROOT}/install.sh" "$@")
}
wt_harness() {
    WT_STATUS=0
    WT_OUTPUT="$( (cd "${WT_REPO}" && env -u STACK_PROFILE HOME="${HOME_FOR_WT}" \
        HARNESS_STATE_DIR="${WT_ROOT}/state" "${HARNESS_ROOT}/bin/harness" "$@" 2>&1) )" || WT_STATUS=$?
}

wt_install --target "${WT_REPO}" >/dev/null 2>&1

# init must record the surfaces it installed, and leave the symlinks committable: a tracked
# CLAUDE.md is what carries AGENTS.md into every worktree.
if [ ! -f "${WT_REPO}/.gitignore" ]; then
    echo "  [FAIL] harness init installed four skill surfaces and wrote no .gitignore entry for them"
    exit 1
fi
for ignored in ".claude/skills/" ".gemini/skills/" ".codex/skills/" ".agents/skills/"; do
    if ! grep -qxF "${ignored}" "${WT_REPO}/.gitignore"; then
        echo "  [FAIL] .gitignore does not record the installed surface ${ignored}: $(cat "${WT_REPO}/.gitignore")"
        exit 1
    fi
done
for kept in "CLAUDE.md" "GEMINI.md" "AGENTS.md"; do
    if grep -qxF "${kept}" "${WT_REPO}/.gitignore"; then
        echo "  [FAIL] .gitignore ignores ${kept}, which every worktree needs in order to read the floor"
        exit 1
    fi
done
GITIGNORE_BEFORE="$(cat "${WT_REPO}/.gitignore")"
wt_install --target "${WT_REPO}" >/dev/null 2>&1
if [ "$(cat "${WT_REPO}/.gitignore")" != "${GITIGNORE_BEFORE}" ]; then
    echo "  [FAIL] a second harness init duplicated its .gitignore block"
    exit 1
fi
echo "  [PASS] harness init records the installed surfaces in .gitignore, once, and keeps the symlinks committable."

git -C "${WT_REPO}" add -A
git -C "${WT_REPO}" commit -q -m "harness init"

# With the surfaces ignored, the new worktree carries none. The command must say so.
wt_harness worktree create feat AH-14 isolated
if [ "${WT_STATUS}" -ne 0 ]; then
    echo "  [FAIL] worktree create failed: ${WT_OUTPUT}"
    exit 1
fi
WT_PATH="${WT_ROOT}/project-AH-14"
if [ ! -d "${WT_PATH}" ]; then
    echo "  [FAIL] worktree create did not produce ${WT_PATH}: ${WT_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${WT_OUTPUT}" | grep -q "skills"; then
    echo "  [FAIL] worktree create did not report the surfaces the new worktree lacks: ${WT_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${WT_OUTPUT}" | grep -q "worktree seed"; then
    echo "  [FAIL] worktree create named no repair path for a worktree with no surface: ${WT_OUTPUT}"
    exit 1
fi
echo "  [PASS] worktree create names the surfaces the new worktree does not carry, and how to repair it."

# Seeding installs the surfaces and the symlinks, and nothing else.
wt_harness worktree seed "${WT_PATH}"
if [ "${WT_STATUS}" -ne 0 ]; then
    echo "  [FAIL] worktree seed failed: ${WT_OUTPUT}"
    exit 1
fi
for runtime_dir in .claude .gemini .codex .agents; do
    if [ ! -f "${WT_PATH}/${runtime_dir}/skills/harness-implement/SKILL.md" ]; then
        echo "  [FAIL] worktree seed did not install the ${runtime_dir} surface: ${WT_OUTPUT}"
        exit 1
    fi
done
if [ ! -L "${WT_PATH}/CLAUDE.md" ]; then
    echo "  [FAIL] worktree seed did not link CLAUDE.md to AGENTS.md: ${WT_OUTPUT}"
    exit 1
fi
if [ -n "$(git -C "${WT_PATH}" status --porcelain)" ]; then
    echo "  [FAIL] worktree seed left tracked changes behind: $(git -C "${WT_PATH}" status --porcelain)"
    exit 1
fi
echo "  [PASS] worktree seed installs the surfaces and the AGENTS.md symlinks, and touches nothing tracked."

# A project that tracks its surfaces already carries them in every worktree, and those
# bundles hold the managed marker -- installing over them would delete versioned files.
TRACKED_REPO="${WT_ROOT}/tracked"
git init -q "${TRACKED_REPO}"
git -C "${TRACKED_REPO}" config user.email "tests@agent-harness.local"
git -C "${TRACKED_REPO}" config user.name "Agent Harness Tests"
printf '# tracked\n' > "${TRACKED_REPO}/README.md"
git -C "${TRACKED_REPO}" add -A
git -C "${TRACKED_REPO}" commit -q -m init
git -C "${TRACKED_REPO}" branch -M main
(cd "${TRACKED_REPO}" && env -u STACK_PROFILE HOME="${HOME_FOR_WT}" \
    HARNESS_STATE_DIR="${WT_ROOT}/state" "${HARNESS_ROOT}/install.sh" --target "${TRACKED_REPO}") >/dev/null 2>&1
rm -f "${TRACKED_REPO}/.gitignore"
git -C "${TRACKED_REPO}" add -A -f
git -C "${TRACKED_REPO}" commit -q -m "track the surfaces"
TRACKED_STATUS=0
TRACKED_OUTPUT="$( (cd "${TRACKED_REPO}" && env -u STACK_PROFILE HOME="${HOME_FOR_WT}" \
    HARNESS_STATE_DIR="${WT_ROOT}/state" "${HARNESS_ROOT}/bin/harness" \
    worktree seed "${TRACKED_REPO}" 2>&1) )" || TRACKED_STATUS=$?
if [ "${TRACKED_STATUS}" -eq 0 ]; then
    echo "  [FAIL] worktree seed rewrote surfaces the project tracks in Git: ${TRACKED_OUTPUT}"
    exit 1
fi
if [ -n "$(git -C "${TRACKED_REPO}" status --porcelain)" ]; then
    echo "  [FAIL] the refused seed still modified tracked files: $(git -C "${TRACKED_REPO}" status --porcelain)"
    exit 1
fi
echo "  [PASS] worktree seed refuses a project whose surfaces are tracked, and changes nothing."

wt_harness worktree seed "${WT_ROOT}/not-a-worktree"
if [ "${WT_STATUS}" -eq 0 ]; then
    echo "  [FAIL] worktree seed accepted a path that is not a worktree of this repository: ${WT_OUTPUT}"
    exit 1
fi
echo "  [PASS] worktree seed refuses a path this repository does not own."

echo ""
echo "=== 36. Testing Workflow Trigger Coverage ==="
# Both workflows filtered pull_request to branches: [main], so a pull request targeting a
# release branch or sitting on top of another one ran no job at all -- and GitHub renders
# zero checks as an absence, not a failure. `gh pr checks` exits 0 on such a pull request
# with "no checks reported", so the absence read as a pass to tooling too.

# Prints the keys nested directly under one trigger in a workflow's `on:` block.
trigger_keys() {
    awk -v trigger="$2" '
        /^on:/ { in_on = 1; next }
        in_on && /^[^[:space:]]/ { in_on = 0 }
        in_on && $0 ~ "^[[:space:]]+" trigger ":" { in_trigger = 1; next }
        in_trigger && /^[[:space:]]{0,2}[^[:space:]]/ { in_trigger = 0 }
        in_trigger { print }
    ' "$1"
}

for workflow in ci compatibility; do
    workflow_file="${HARNESS_ROOT}/.github/workflows/${workflow}.yml"
    if [ ! -f "${workflow_file}" ]; then
        echo "  [FAIL] Missing workflow: ${workflow_file}"
        exit 1
    fi
    if trigger_keys "${workflow_file}" "pull_request" | grep -q "branches:"; then
        echo "  [FAIL] ${workflow}.yml filters pull_request by base branch, so a pull request targeting anything else runs no check at all"
        exit 1
    fi
    if ! trigger_keys "${workflow_file}" "push" | grep -q "branches:"; then
        echo "  [FAIL] ${workflow}.yml runs on every push to every branch; only pull requests need universal coverage"
        exit 1
    fi
done
echo "  [PASS] every pull request is verified whatever it targets, and push stays scoped to the trunk."

echo ""
echo "=== 37. Testing Surface Digest Contract ==="
# A digest is an identity claim: every surface manifest records one, and drift detection
# compares against it. A refactor that changed the hashed bytes would report every
# installed surface as drifted at once, so the contract is pinned rather than assumed.
DIGEST_ROOT="${TMP_TEST_DIR}/digest-contract"
mkdir -p "${DIGEST_ROOT}/home"
DIGEST_TARGET="${DIGEST_ROOT}/target"
git init -q "${DIGEST_TARGET}"
git -C "${DIGEST_TARGET}" config user.email "tests@agent-harness.local"
git -C "${DIGEST_TARGET}" config user.name "Agent Harness Tests"
git -C "${DIGEST_TARGET}" commit -q --allow-empty -m init
HOME="${DIGEST_ROOT}/home" HARNESS_STATE_DIR="${DIGEST_ROOT}/state" \
    "${HARNESS_ROOT}/install.sh" --target "${DIGEST_TARGET}" >/dev/null 2>&1

# Computed here from the documented rule -- each file's relative path, then its content,
# ordered by relative path -- with no reference to how surface.sh does it.
independent_digest() {
    local bundle="$1"
    local payload reference
    payload="$(mktemp)"
    {
        printf 'SKILL.md\n'
        cat "${bundle}/SKILL.md"
        for reference in "${bundle}"/references/*.md; do
            [ -f "${reference}" ] || continue
            printf 'references/%s\n' "$(basename "${reference}")"
            cat "${reference}"
        done
    } > "${payload}"
    git hash-object --stdin < "${payload}" | cut -c 1-12
    rm -f "${payload}"
}

DIGEST_SURFACE="${DIGEST_TARGET}/.claude/skills"
for workflow in implement fix investigate; do
    bundle="${DIGEST_SURFACE}/harness-${workflow}"
    expected="$(independent_digest "${bundle}")"
    source_digest="$( cd "${HARNESS_ROOT}" && bash -c '
        source core/scripts/lib/utils.sh
        source core/scripts/lib/surface.sh
        surface_source_digest "$1"' _ "${workflow}" )"
    installed_digest="$( cd "${HARNESS_ROOT}" && bash -c '
        source core/scripts/lib/utils.sh
        source core/scripts/lib/surface.sh
        surface_installed_digest "$1"' _ "${bundle}" )"

    if [ "${source_digest}" != "${installed_digest}" ]; then
        echo "  [FAIL] ${workflow}: source digest ${source_digest} and installed digest ${installed_digest} disagree, so a fresh install would report as drifted"
        exit 1
    fi
    if [ "${installed_digest}" != "${expected}" ]; then
        echo "  [FAIL] ${workflow}: digest ${installed_digest} does not match the documented rule (${expected}); the hashed bytes have changed"
        exit 1
    fi
    if [ "${#installed_digest}" -ne 12 ]; then
        echo "  [FAIL] ${workflow}: digest '${installed_digest}' is not 12 characters"
        exit 1
    fi
done
echo "  [PASS] source and installed digests agree and match the documented byte contract."

# Repeated calls must agree. The failure this group exists to keep closed was a race
# against child-process reaping, which is exactly what a repeated call exercises.
DIGEST_REPEATS="$( cd "${HARNESS_ROOT}" && bash -c '
    source core/scripts/lib/utils.sh
    source core/scripts/lib/surface.sh
    index=0
    while [ "${index}" -lt 12 ]; do
        surface_source_digest implement
        surface_installed_digest "$1"
        index=$((index + 1))
    done' _ "${DIGEST_SURFACE}/harness-implement" 2>&1 )"
if printf '%s' "${DIGEST_REPEATS}" | grep -qi "write error\|Interrupted"; then
    echo "  [FAIL] a digest computation reported an interrupted write: ${DIGEST_REPEATS}"
    exit 1
fi
# A freshly installed bundle signs identically to its source -- that is what makes a
# clean install report as current -- so all 24 lines must be the same digest.
if [ "$(printf '%s\n' "${DIGEST_REPEATS}" | grep -c .)" -ne 24 ]; then
    echo "  [FAIL] a digest computation produced no output, so one of the 24 calls failed: ${DIGEST_REPEATS}"
    exit 1
fi
if [ "$(printf '%s\n' "${DIGEST_REPEATS}" | sort -u | grep -c .)" -ne 1 ]; then
    echo "  [FAIL] repeated digest computations did not agree: ${DIGEST_REPEATS}"
    exit 1
fi
echo "  [PASS] repeated digest computations agree and report no interrupted write."

echo ""
echo "=== 38. Testing Init Project Detection ==="
# harness init copied a fixed template declaring every repository a Python "backend"
# running pytest, so the first command a new user ran -- harness qa all -- invoked pytest
# in a Node repository. The README already promised detection, so the claim existed and the
# code did not honour it.
INIT_ROOT="${TMP_TEST_DIR}/init-detection"
mkdir -p "${INIT_ROOT}/home"

# Builds a repository from the files named, initializes the harness in it, and leaves the
# generated configuration in INIT_CONFIG.
init_detect_repo() {
    local name="$1"
    shift
    INIT_REPO="${INIT_ROOT}/${name}"
    mkdir -p "${INIT_REPO}"
    git -C "${INIT_REPO}" init -q
    git -C "${INIT_REPO}" config user.email "tests@agent-harness.local"
    git -C "${INIT_REPO}" config user.name "Agent Harness Tests"
    local spec relative
    for spec in "$@"; do
        relative="${spec%%=*}"
        mkdir -p "${INIT_REPO}/$(dirname "${relative}")"
        printf '%s\n' "${spec#*=}" > "${INIT_REPO}/${relative}"
    done
    git -C "${INIT_REPO}" add -A
    git -C "${INIT_REPO}" commit -q -m init
    HOME="${INIT_ROOT}/home" HARNESS_STATE_DIR="${INIT_ROOT}/state" \
        "${HARNESS_ROOT}/install.sh" --target "${INIT_REPO}" >/dev/null 2>&1
    INIT_CONFIG="${INIT_REPO}/stack.config.json"
    if [ ! -f "${INIT_CONFIG}" ]; then
        echo "  [FAIL] harness init wrote no configuration in ${name}"
        exit 1
    fi
}

init_config_query() {
    jq -r "$1" "${INIT_CONFIG}"
}

# Whatever init writes must pass the repository's own validator.
assert_config_validates() {
    local status=0 output
    output="$( (cd "${INIT_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" config validate 2>&1) )" || status=$?
    if [ "${status}" -ne 0 ]; then
        echo "  [FAIL] the configuration init generated does not validate: ${output}"
        exit 1
    fi
}

# A Node project with its own test and lint scripts and a tsconfig.
init_detect_repo node \
    'package.json={"name":"app","scripts":{"test":"vitest run","lint":"eslint ."},"devDependencies":{"vitest":"^1.0.0"}}' \
    'tsconfig.json={}'
assert_config_validates
if [ "$(init_config_query '.project.defaultProfile')" != "node" ]; then
    echo "  [FAIL] a Node repository did not get the node profile: $(cat "${INIT_CONFIG}")"
    exit 1
fi
if [ "$(init_config_query '.profiles.node.qa.testCommand')" != "npm test" ]; then
    echo "  [FAIL] a Node repository with a test script did not get 'npm test': $(cat "${INIT_CONFIG}")"
    exit 1
fi
if [ "$(init_config_query '.profiles.node.qa.lintCommand')" != "npm run lint" ]; then
    echo "  [FAIL] a Node repository with a lint script did not get 'npm run lint': $(cat "${INIT_CONFIG}")"
    exit 1
fi
if [ "$(init_config_query '.profiles.node.qa.typeCheckCommand')" != "npx tsc --noEmit" ]; then
    echo "  [FAIL] a Node repository with a tsconfig did not get a type check: $(cat "${INIT_CONFIG}")"
    exit 1
fi
if init_config_query '.. | strings' | grep -q "pytest"; then
    echo "  [FAIL] a Node repository was told to run pytest: $(cat "${INIT_CONFIG}")"
    exit 1
fi
echo "  [PASS] a Node repository gets its own scripts, and no pytest."

# A Node project with no scripts at all evidences no command; an unset gate reports that it
# could not run, which is correct. A gate running the wrong tool is not.
init_detect_repo bare-node 'package.json={"name":"bare"}'
assert_config_validates
if [ "$(init_config_query '.profiles.node.qa.testCommand // "unset"')" != "unset" ]; then
    echo "  [FAIL] a Node repository with no test script was given a test command anyway: $(cat "${INIT_CONFIG}")"
    exit 1
fi
echo "  [PASS] a command with no evidence behind it is left unset."

# Go: the compiler type-checks, so 'no type checker' is a decision rather than a gap.
init_detect_repo go 'go.mod=module example.com/svc'
assert_config_validates
if [ "$(init_config_query '.profiles.go.qa.testCommand')" != "go test ./..." ]; then
    echo "  [FAIL] a Go repository did not get 'go test ./...': $(cat "${INIT_CONFIG}")"
    exit 1
fi
if [ "$(init_config_query '.profiles.go.qa.typeCheckCommand')" != "false" ]; then
    echo "  [FAIL] a Go repository did not record that it has no separate type checker: $(cat "${INIT_CONFIG}")"
    exit 1
fi
echo "  [PASS] a Go repository gets go test, and records that the compiler is its type checker."

# Django is not pytest, and manage.py is the evidence that distinguishes them.
init_detect_repo django 'manage.py=#!/usr/bin/env python' 'requirements.txt=django'
assert_config_validates
if [ "$(init_config_query '.profiles.python.qa.testCommand')" != "python manage.py test" ]; then
    echo "  [FAIL] a Django repository was not detected as one: $(cat "${INIT_CONFIG}")"
    exit 1
fi
echo "  [PASS] a Django repository gets manage.py test rather than pytest."

# Nothing recognizable: a profile with no commands, and no invented ones.
init_detect_repo plain 'README.md=# docs only'
assert_config_validates
if [ "$(init_config_query '.profiles | keys | length')" != "1" ]; then
    echo "  [FAIL] an unrecognizable repository got more than one profile: $(cat "${INIT_CONFIG}")"
    exit 1
fi
if [ "$(init_config_query '[.profiles[].qa // {} | keys[]] | length')" != "0" ]; then
    echo "  [FAIL] an unrecognizable repository was given commands anyway: $(cat "${INIT_CONFIG}")"
    exit 1
fi
echo "  [PASS] an unrecognizable repository gets no invented commands."

# Nothing init writes may assert a fact it did not read from the target.
for forbidden in "PROJ" "trunkBranch"; do
    if grep -qF "${forbidden}" "${INIT_CONFIG}"; then
        echo "  [FAIL] init asserted '${forbidden}', which it cannot know: $(cat "${INIT_CONFIG}")"
        exit 1
    fi
done
echo "  [PASS] init states no issue prefix and no trunk branch it did not read."

# The schema must accept the value stack-qa.sh documents for a gate a project has none of.
SCHEMA_REPO="${INIT_ROOT}/schema-false"
mkdir -p "${SCHEMA_REPO}"
git -C "${SCHEMA_REPO}" init -q
cat > "${SCHEMA_REPO}/harness.config.json" <<'SCHEMA_FALSE_EOF'
{
  "project": { "name": "x", "defaultProfile": "p" },
  "profiles": { "p": { "qa": { "testCommand": "go test ./...", "typeCheckCommand": false, "lintCommand": false } } }
}
SCHEMA_FALSE_EOF
SCHEMA_STATUS=0
SCHEMA_OUTPUT="$( (cd "${SCHEMA_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" config validate 2>&1) )" || SCHEMA_STATUS=$?
if [ "${SCHEMA_STATUS}" -ne 0 ]; then
    echo "  [FAIL] schema.json rejects the 'false' that stack-qa.sh documents and honours: ${SCHEMA_OUTPUT}"
    exit 1
fi
echo "  [PASS] config validate accepts the documented way to declare a gate absent."

# `harness init` passed $(pwd), so running it from a subdirectory installed a whole second
# harness inside that subdirectory -- its own AGENTS.md, CLAUDE.md and GEMINI.md symlinks,
# rules/, stack.config.json, a second .gitignore and four skill surfaces -- and said nothing
# about where any of it went. Initializing a repository means initializing its root.
INIT_SUBDIR_REPO="${TMP_TEST_DIR}/init-subdir"
mkdir -p "${INIT_SUBDIR_REPO}/src/deep"
git -C "${INIT_SUBDIR_REPO}" init -q
git -C "${INIT_SUBDIR_REPO}" config user.email "tests@agent-harness.local"
git -C "${INIT_SUBDIR_REPO}" config user.name "Agent Harness Tests"
printf 'print("x")\n' > "${INIT_SUBDIR_REPO}/src/deep/app.py"
git -C "${INIT_SUBDIR_REPO}" add -A
git -C "${INIT_SUBDIR_REPO}" commit -q -m init

INIT_SUBDIR_OUTPUT="$( (cd "${INIT_SUBDIR_REPO}/src/deep" \
    && env -u STACK_PROFILE HOME="${INIT_ROOT}/home" HARNESS_STATE_DIR="${INIT_ROOT}/state" \
       "${HARNESS_ROOT}/bin/harness" init 2>&1) )"

for stray in AGENTS.md CLAUDE.md GEMINI.md stack.config.json .gitignore rules .claude .gemini .codex .agents .cursor; do
    if [ -e "${INIT_SUBDIR_REPO}/src/deep/${stray}" ] || [ -L "${INIT_SUBDIR_REPO}/src/deep/${stray}" ]; then
        echo "  [FAIL] init from a subdirectory wrote ${stray} into it: ${INIT_SUBDIR_OUTPUT}"
        exit 1
    fi
done
for expected in AGENTS.md stack.config.json rules; do
    if [ ! -e "${INIT_SUBDIR_REPO}/${expected}" ]; then
        echo "  [FAIL] init from a subdirectory did not initialize the repository root: ${INIT_SUBDIR_OUTPUT}"
        exit 1
    fi
done
# Writing somewhere other than the working directory has to be said out loud.
if ! printf '%s' "${INIT_SUBDIR_OUTPUT}" | grep -qF "${INIT_SUBDIR_REPO}"; then
    echo "  [FAIL] init did not name the root it resolved to: ${INIT_SUBDIR_OUTPUT}"
    exit 1
fi
echo "  [PASS] init from a subdirectory initializes the repository root and names it."

echo ""
echo "=== 39. Testing Ship Guards ==="
# `harness ship` published whatever it was pointed at. On the trunk it pushed the trunk and
# opened a pull request from main into main; with uncommitted work it pushed a branch
# missing it and said nothing; and it asked for no confirmation before a push, which this
# project's own conventions forbid an agent from performing unasked.
SHIP_ROOT="${TMP_TEST_DIR}/ship-guards"
mkdir -p "${SHIP_ROOT}"
git init -q --bare "${SHIP_ROOT}/remote.git"
SHIP_REPO="${SHIP_ROOT}/work"
git init -q "${SHIP_REPO}"
git -C "${SHIP_REPO}" config user.email "tests@agent-harness.local"
git -C "${SHIP_REPO}" config user.name "Agent Harness Tests"
git -C "${SHIP_REPO}" remote add origin "${SHIP_ROOT}/remote.git"
cat > "${SHIP_REPO}/harness.config.json" <<'SHIP_CONFIG_EOF'
{
  "project": { "name": "ship", "defaultProfile": "ship" },
  "profiles": {
    "ship": {
      "git": { "trunkBranch": "main" },
      "qa": { "testCommand": false, "lintCommand": false, "typeCheckCommand": false },
      "ci": { "provider": "custom", "prCommand": "echo PULL-REQUEST-OPENED" }
    }
  }
}
SHIP_CONFIG_EOF
git -C "${SHIP_REPO}" add -A
git -C "${SHIP_REPO}" commit -q -m init
git -C "${SHIP_REPO}" branch -M main

ship() {
    SHIP_STATUS=0
    SHIP_OUTPUT="$( (cd "${SHIP_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" ship "$@" </dev/null 2>&1) )" || SHIP_STATUS=$?
}
remote_branches() {
    git -C "${SHIP_ROOT}/remote.git" for-each-ref --format='%(refname:short)' refs/heads
}

# On the trunk there is nothing to open a pull request about, and pushing it is publication.
ship --yes
if [ "${SHIP_STATUS}" -eq 0 ]; then
    echo "  [FAIL] ship published the trunk branch: ${SHIP_OUTPUT}"
    exit 1
fi
if [ -n "$(remote_branches)" ]; then
    echo "  [FAIL] ship pushed while refusing: $(remote_branches)"
    exit 1
fi
echo "  [PASS] ship refuses to publish the branch it is targeting, and pushes nothing."

git -C "${SHIP_REPO}" checkout -q -b feat/AH-18-demo

# A branch with no commits of its own has nothing to propose.
ship --yes
if [ "${SHIP_STATUS}" -eq 0 ]; then
    echo "  [FAIL] ship opened a pull request for a branch with no commits: ${SHIP_OUTPUT}"
    exit 1
fi
echo "  [PASS] ship refuses a branch with no commits ahead of its target."

printf 'shipped = 1\n' > "${SHIP_REPO}/feature.txt"
git -C "${SHIP_REPO}" add -A
git -C "${SHIP_REPO}" commit -q -m "add the feature"

# Uncommitted work would not be pushed, and the previous command said nothing about it.
printf 'shipped = 2\n' > "${SHIP_REPO}/feature.txt"
ship --yes
if [ "${SHIP_STATUS}" -eq 0 ]; then
    echo "  [FAIL] ship pushed a branch that is missing uncommitted work: ${SHIP_OUTPUT}"
    exit 1
fi
if [ -n "$(remote_branches)" ]; then
    echo "  [FAIL] ship pushed while refusing a dirty tree: $(remote_branches)"
    exit 1
fi
git -C "${SHIP_REPO}" checkout -q -- feature.txt
echo "  [PASS] ship refuses uncommitted changes to tracked files."

# An option is an option, not a branch name.
ship --no-such-flag
if [ "${SHIP_STATUS}" -eq 0 ] || ! printf '%s' "${SHIP_OUTPUT}" | grep -qF -- "--no-such-flag"; then
    echo "  [FAIL] ship accepted an unknown option as a target branch: ${SHIP_OUTPUT}"
    exit 1
fi
echo "  [PASS] ship refuses an option it does not define instead of targeting a branch named after it."

# Publication needs a confirmation, and there is no terminal here to ask on.
ship
if [ "${SHIP_STATUS}" -eq 0 ]; then
    echo "  [FAIL] ship published without a confirmation: ${SHIP_OUTPUT}"
    exit 1
fi
if [ -n "$(remote_branches)" ]; then
    echo "  [FAIL] ship pushed without confirmation: $(remote_branches)"
    exit 1
fi
echo "  [PASS] ship refuses to publish unasked when there is no terminal to confirm on."

# --dry-run reports the decision and changes nothing.
ship --dry-run --yes
if [ "${SHIP_STATUS}" -ne 0 ]; then
    echo "  [FAIL] a dry run failed: ${SHIP_OUTPUT}"
    exit 1
fi
if [ -n "$(remote_branches)" ]; then
    echo "  [FAIL] a dry run pushed: $(remote_branches)"
    exit 1
fi
if ! printf '%s' "${SHIP_OUTPUT}" | grep -q "feat/AH-18-demo"; then
    echo "  [FAIL] a dry run did not name the branch it would publish: ${SHIP_OUTPUT}"
    exit 1
fi
echo "  [PASS] --dry-run names what it would publish and mutates nothing."

# The confirmed path: QA, push, then the configured pull-request command.
ship --yes
if [ "${SHIP_STATUS}" -ne 0 ]; then
    echo "  [FAIL] a confirmed ship failed: ${SHIP_OUTPUT}"
    exit 1
fi
if ! remote_branches | grep -qx "feat/AH-18-demo"; then
    echo "  [FAIL] a confirmed ship did not push the branch: $(remote_branches)"
    exit 1
fi
if ! printf '%s' "${SHIP_OUTPUT}" | grep -q "PULL-REQUEST-OPENED"; then
    echo "  [FAIL] a confirmed ship did not run the configured pull request command: ${SHIP_OUTPUT}"
    exit 1
fi
echo "  [PASS] a confirmed ship runs QA, pushes, and opens the pull request."

# A run that pushed and opened nothing has not shipped, and must not report that it did.
git -C "${SHIP_REPO}" checkout -q -b feat/AH-18-nopr
printf 'more = 1\n' > "${SHIP_REPO}/second.txt"
git -C "${SHIP_REPO}" add -A
git -C "${SHIP_REPO}" commit -q -m "second"
python3 - "${SHIP_REPO}/harness.config.json" <<'STRIP_PR_EOF'
import json, sys
path = sys.argv[1]
config = json.load(open(path))
config["profiles"]["ship"]["ci"] = {"provider": "custom"}
json.dump(config, open(path, "w"), indent=2)
STRIP_PR_EOF
git -C "${SHIP_REPO}" add -A
git -C "${SHIP_REPO}" commit -q -m "drop the pr command"
ship --yes
if [ "${SHIP_STATUS}" -eq 0 ]; then
    echo "  [FAIL] ship reported success having opened no pull request: ${SHIP_OUTPUT}"
    exit 1
fi
if ! remote_branches | grep -qx "feat/AH-18-nopr"; then
    echo "  [FAIL] ship did not push before reporting that it opened nothing: $(remote_branches)"
    exit 1
fi
echo "  [PASS] a push with no pull request exits non-zero and says which half happened."

echo ""
echo "=== 40. Testing Version, Upgrade And Dogfooding ==="
# The whole drift model turns on which version is installed -- every surface manifest
# records one -- and there was no way to ask. Upgrading was equally undiscoverable.
VERSION_EXPECTED="$(jq -r '.version' "${HARNESS_ROOT}/package.json")"
VERSION_STATUS=0
VERSION_OUTPUT="$("${HARNESS_ROOT}/bin/harness" version 2>&1)" || VERSION_STATUS=$?
if [ "${VERSION_STATUS}" -ne 0 ]; then
    echo "  [FAIL] harness version exited ${VERSION_STATUS}: ${VERSION_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${VERSION_OUTPUT}" | grep -qF "${VERSION_EXPECTED}"; then
    echo "  [FAIL] harness version does not report package.json's version (${VERSION_EXPECTED}): ${VERSION_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${VERSION_OUTPUT}" | grep -qF "${HARNESS_ROOT}"; then
    echo "  [FAIL] harness version does not name the checkout it runs from: ${VERSION_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${VERSION_OUTPUT}" | grep -qF "$(git -C "${HARNESS_ROOT}" rev-parse --short HEAD)"; then
    echo "  [FAIL] harness version does not name the checkout's revision: ${VERSION_OUTPUT}"
    exit 1
fi
echo "  [PASS] harness version reports the version, the checkout, and its revision."

# Every command the dispatcher routes must be in the help. `completion` was dispatched and
# documented in the README while absent from --help, and nothing could notice.
HELP_OUTPUT="$("${HARNESS_ROOT}/bin/harness" --help 2>&1)"
DISPATCHED="$(awk '
    /^case "\$\{COMMAND\}" in$/ { inside = 1; next }
    inside && /^esac$/ { inside = 0 }
    inside && /^    [a-z|]+\)$/ { gsub(/[ )]/, ""); print }
' "${HARNESS_ROOT}/bin/harness" | tr '|' '\n')"
if [ -z "${DISPATCHED}" ]; then
    echo "  [FAIL] could not read the dispatcher's command list from bin/harness"
    exit 1
fi
while IFS= read -r command_name; do
    [ -n "${command_name}" ] || continue
    [ "${command_name}" = "*" ] && continue
    if ! printf '%s' "${HELP_OUTPUT}" | grep -qE "(^|[^a-z-])${command_name}([^a-z-]|$)"; then
        echo "  [FAIL] 'harness ${command_name}' is dispatched but absent from harness --help"
        exit 1
    fi
done <<< "${DISPATCHED}"
echo "  [PASS] every command the dispatcher routes is named in harness --help."

# A name offered by the completion must be a binary that exists.
if [ ! -e "${HARNESS_ROOT}/bin/forge" ]; then
    if grep -q "forge" "${HARNESS_ROOT}/bin/harness" || \
       grep -q "forge" "${HARNESS_ROOT}/core/scripts/stack-completion.sh"; then
        echo "  [FAIL] 'forge' is still advertised although bin/forge does not exist"
        exit 1
    fi
fi
echo "  [PASS] no binary name is advertised that does not exist."

# upgrade mutates a checkout, so it refuses rather than guesses.
UPGRADE_ROOT="${TMP_TEST_DIR}/upgrade"
mkdir -p "${UPGRADE_ROOT}"
UPGRADE_STATUS=0
UPGRADE_OUTPUT="$(HARNESS_TEST_CHECKOUT="${UPGRADE_ROOT}/not-a-clone" \
    "${HARNESS_ROOT}/bin/harness" upgrade 2>&1)" || UPGRADE_STATUS=$?
if [ "${UPGRADE_STATUS}" -eq 0 ]; then
    echo "  [FAIL] upgrade accepted a checkout that is not a Git clone: ${UPGRADE_OUTPUT}"
    exit 1
fi

DIRTY_CHECKOUT="${UPGRADE_ROOT}/dirty"
git init -q "${DIRTY_CHECKOUT}"
git -C "${DIRTY_CHECKOUT}" config user.email "tests@agent-harness.local"
git -C "${DIRTY_CHECKOUT}" config user.name "Agent Harness Tests"
printf 'x\n' > "${DIRTY_CHECKOUT}/tracked.txt"
git -C "${DIRTY_CHECKOUT}" add -A
git -C "${DIRTY_CHECKOUT}" commit -q -m init
printf 'edited\n' > "${DIRTY_CHECKOUT}/tracked.txt"
UPGRADE_STATUS=0
UPGRADE_OUTPUT="$(HARNESS_TEST_CHECKOUT="${DIRTY_CHECKOUT}" \
    "${HARNESS_ROOT}/bin/harness" upgrade 2>&1)" || UPGRADE_STATUS=$?
if [ "${UPGRADE_STATUS}" -eq 0 ]; then
    echo "  [FAIL] upgrade pulled over uncommitted changes: ${UPGRADE_OUTPUT}"
    exit 1
fi
if [ "$(cat "${DIRTY_CHECKOUT}/tracked.txt")" != "edited" ]; then
    echo "  [FAIL] the refused upgrade changed the working tree"
    exit 1
fi
echo "  [PASS] upgrade refuses a checkout that is not a clone, and one with uncommitted changes."

# Compared before and after rather than against a clean tree: the suite runs from a
# checkout that may legitimately carry work in progress.
UPGRADE_BEFORE="$(git -C "${HARNESS_ROOT}" status --porcelain)"
UPGRADE_HEAD_BEFORE="$(git -C "${HARNESS_ROOT}" rev-parse HEAD)"
UPGRADE_STATUS=0
UPGRADE_OUTPUT="$("${HARNESS_ROOT}/bin/harness" upgrade --check 2>&1)" || UPGRADE_STATUS=$?
if [ "${UPGRADE_STATUS}" -ne 0 ]; then
    echo "  [FAIL] upgrade --check is a report and must not refuse; it exited ${UPGRADE_STATUS}: ${UPGRADE_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${UPGRADE_OUTPUT}" | grep -qF "${VERSION_EXPECTED}"; then
    echo "  [FAIL] upgrade --check does not report the installed version: ${UPGRADE_OUTPUT}"
    exit 1
fi
if ! printf '%s' "${UPGRADE_OUTPUT}" | grep -qF "Nothing was changed"; then
    echo "  [FAIL] upgrade --check does not say that it changed nothing: ${UPGRADE_OUTPUT}"
    exit 1
fi
if [ "$(git -C "${HARNESS_ROOT}" status --porcelain)" != "${UPGRADE_BEFORE}" ] || \
   [ "$(git -C "${HARNESS_ROOT}" rev-parse HEAD)" != "${UPGRADE_HEAD_BEFORE}" ]; then
    echo "  [FAIL] upgrade --check changed the checkout"
    exit 1
fi
echo "  [PASS] upgrade --check reports the installed version and mutates nothing."

# The two commands this project asks every user to trust are the two it never ran on itself.
CI_WORKFLOW="${HARNESS_ROOT}/.github/workflows/ci.yml"
for dogfood in "harness scan --all" "harness config validate"; do
    if ! grep -qF "${dogfood}" "${CI_WORKFLOW}"; then
        echo "  [FAIL] CI does not run '${dogfood}' against this repository"
        exit 1
    fi
done
echo "  [PASS] CI runs this repository's own scanner and configuration validator."

# A delivered spec left active makes harness context overstate what is in flight.
if [ -f "${HARNESS_ROOT}/specs/delta-AH-11-truthful-core-hardening.md" ]; then
    echo "  [FAIL] the AH-11 delta spec was delivered in 7ea3705 and is still active"
    exit 1
fi
echo "  [PASS] no delivered delta spec is still listed as active."

echo ""
echo "=== 41. Testing Debt Marker Anchoring ==="
# harness debt reported sixteen markers in this repository and there were none: every one
# was the harness describing or testing its own feature. A debt marker is a comment, and it
# was being matched as a substring anywhere in a line.
DEBT_REPO="${TMP_TEST_DIR}/debt-anchoring"
mkdir -p "${DEBT_REPO}"
git -C "${DEBT_REPO}" init -q
git -C "${DEBT_REPO}" config user.email "tests@agent-harness.local"
git -C "${DEBT_REPO}" config user.name "Agent Harness Tests"

# The three forms a debt marker is actually written in. The comment token is passed as an
# argument rather than written inline, so this file does not itself carry a marker -- which
# is the very category of false positive this group exists to close.
{
    printf '%s pragmatism: at the start of a line\n' '#'
    printf 'value = 1\n'
    printf 'def inner():\n'
    printf '    %s defer: after indentation only\n' '#'
    printf '    return value\n'
    printf 'total = value + 1  %s pragmatism: trailing on a code line\n' '#'
} > "${DEBT_REPO}/code.py"

# The same text quoted in prose or inside a string literal is not a debt marker.
cat > "${DEBT_REPO}/guide.md" <<'DEBT_DOC_EOF'
Record debt with `# pragmatism:` or `// defer:` in a comment.
The '# defer:' form works in shell too.
DEBT_DOC_EOF
cat > "${DEBT_REPO}/fixture.sh" <<'DEBT_FIXTURE_EOF'
printf '# pragmatism: written into a temporary repository\n' > marker.txt
printf '// defer: and the slash form\n' >> marker.txt
DEBT_FIXTURE_EOF

git -C "${DEBT_REPO}" add -A
git -C "${DEBT_REPO}" commit -q -m init

DEBT_JSON="$( (cd "${DEBT_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" debt --json) )"
DEBT_FOUND="$(printf '%s' "${DEBT_JSON}" | jq -r 'length')"
if [ "${DEBT_FOUND}" != "3" ]; then
    echo "  [FAIL] expected the 3 real markers, found ${DEBT_FOUND}: ${DEBT_JSON}"
    exit 1
fi
for expected in "at the start of a line" "after indentation only" "trailing on a code line"; do
    if ! printf '%s' "${DEBT_JSON}" | jq -e --arg text "${expected}" 'any(.[]; .text | contains($text))' >/dev/null; then
        echo "  [FAIL] a real marker was missed (${expected}): ${DEBT_JSON}"
        exit 1
    fi
done
echo "  [PASS] a marker is found at the start of a line, after indentation, and trailing on a code line."

for quoted in "guide.md" "fixture.sh"; do
    if printf '%s' "${DEBT_JSON}" | jq -e --arg file "${quoted}" 'any(.[]; .file | contains($file))' >/dev/null; then
        echo "  [FAIL] a marker quoted in ${quoted} was reported as debt: ${DEBT_JSON}"
        exit 1
    fi
done
echo "  [PASS] a marker quoted in prose or inside a string literal is not debt."

# The count harness context reports comes from the same scan, so it moves with it.
DEBT_CONTEXT="$( (cd "${DEBT_REPO}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" context --json) )"
if [ "$(printf '%s' "${DEBT_CONTEXT}" | jq -r '.technicalDebtMarkers')" != "3" ]; then
    echo "  [FAIL] harness context reports a different count than harness debt: ${DEBT_CONTEXT}"
    exit 1
fi
echo "  [PASS] harness context reports the same count as harness debt."

# Dogfooding: the files that describe and test the feature must yield nothing. Stated per
# file rather than as a repository total, so it stays true when real debt is recorded.
SELF_DEBT="$( (cd "${HARNESS_ROOT}" && env -u STACK_PROFILE "${HARNESS_ROOT}/bin/harness" debt --json) )"
for describes_itself in "README.md" "AGENTS.md" "core/skills/debt/SKILL.md" "test/test_cli.sh" "bin/harness" "core/scripts/lib/debt.sh"; do
    if printf '%s' "${SELF_DEBT}" | jq -e --arg file "${describes_itself}" 'any(.[]; .file == $file)' >/dev/null; then
        echo "  [FAIL] ${describes_itself} describes or tests the debt feature and was reported as carrying debt"
        exit 1
    fi
done
echo "  [PASS] the files that describe and test the marker are not reported as carrying it."

echo ""
echo "All automated tests passed successfully! [100%]"
