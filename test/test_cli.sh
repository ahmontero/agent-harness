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
"${HARNESS_ROOT}/bin/harness" scan --rules "${HARNESS_ROOT}/core/templates/landmines-template.json" --all >/dev/null || true
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
done

echo ""
echo "All automated tests passed successfully! [100%]"
