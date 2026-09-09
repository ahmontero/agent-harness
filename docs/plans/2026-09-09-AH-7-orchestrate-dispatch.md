# AH-7 Orchestrate Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `/harness-orchestrate`, a fourth public workflow that dispatches one implementer subagent and one reviewer subagent per Implementation Plan item, selects a model per role from profile configuration, and is installed only into Claude Code.

**Architecture:** A new skill document carries the whole workflow protocol; no new CLI subcommand is added. `core/skills/catalog.json` gains a `runtimes` map that `install.sh` consults so a public workflow can be restricted to one runtime, and `harness context --json` grows an `orchestrateModels` object resolved from the active profile. The compatibility matrix stops assuming an identical surface in every runtime and starts asserting the declared surface per runtime.

**Tech Stack:** Bash 3.2-compatible shell, `jq`, Git, Markdown skill documents. No new dependencies.

**Spec:** `specs/delta-AH-7-orchestrate-dispatch.md`

## Global Constraints

- Required gates fail closed. A command must never print success after suppressing a required failure (`rules/floor.md`).
- Behavior changes start RED. Add a deterministic failing test before modifying production behavior.
- Shell must work on the Bash versions shipped by supported macOS and Linux runners. No `mapfile`, no `declare -A`, no GNU-only flags.
- Every shell change must pass `shellcheck -S warning` via `npm run lint`.
- Commit messages follow `<type>(AH-7): <imperative description>`. No AI attribution trailers.
- Installation stays idempotent, and no user-owned skill is ever removed.
- The AH-3 receipt schema, the AH-4 ledger format, and the AH-4 ledger kinds are unchanged.
- Full local gate: `env -u STACK_PROFILE npm test && npm run lint && ./setup --verify`.

## File Structure

| File | Responsibility |
| :--- | :--- |
| `core/skills/orchestrate/SKILL.md` | Create. The entire workflow protocol: entry gates, dispatch loop, brief format, structured return, bounded loop, anti-rationalization, state anchor. |
| `core/skills/catalog.json` | Modify. Adds `public.orchestrate` and the sibling `runtimes` map. |
| `install.sh` | Modify. Threads a runtime label into `install_skill_surface` and filters public workflow installation by it. |
| `core/scripts/stack-context.sh` | Modify. Emits `orchestrateModels` in JSON and text output. |
| `schema.json` | Modify. Describes `profiles.<profile>.orchestrate.models`. |
| `harness.config.json` | Modify. Declares this repository's own role-to-model choices. |
| `test/test_cli.sh` | Modify. Catalog contract, per-runtime installation counts, expert filtering, context output. |
| `test/e2e/test_install_matrix.sh` | Modify. Runtime-aware surface verification and evidence. |
| `README.md`, `docs/COMPATIBILITY.md`, `docs/ARCHITECTURE.md`, `docs/PROVENANCE.md`, `CHANGELOG.md`, `package.json` | Modify. Documentation and release metadata. |

---

### Task 1: The orchestrate skill and its runtime gating

This task is atomic on purpose. Adding `orchestrate` to `public` without the installer filter turns every per-runtime count assertion red, so the skill document, the catalog entry, and the installer filter land together.

**Files:**
- Create: `core/skills/orchestrate/SKILL.md`
- Modify: `core/skills/catalog.json`
- Modify: `install.sh:242-266` (`install_skill_surface`), `install.sh:155-200` (`require_skill_catalog`), `install.sh:339-341`, `install.sh:388-390`
- Test: `test/test_cli.sh:31-49` (catalog contract), `test/test_cli.sh:165-196` (default surface), `test/test_cli.sh:199-215` (expert surface)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `install_skill_surface <destination> <runtime>` where `<runtime>` is one of `agents`, `claude`, `codex`, `gemini`; `workflow_allowed_for_runtime <workflow> <runtime>` returning 0 when permitted; the catalog key `.runtimes` mapping a public workflow name to an array of runtime labels, where an absent key means every runtime.

- [ ] **Step 1: Write the failing catalog contract test**

In `test/test_cli.sh`, replace the public-surface assertion at line 42 and add the runtime assertion after it:

```bash
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
```

In the same group, change the workflow section loop so it covers the new workflow:

```bash
for workflow in implement fix investigate orchestrate; do
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash test/test_cli.sh`
Expected: FAIL at group `2b` with `Public skill catalog must expose exactly fix, implement, investigate, and orchestrate`.

- [ ] **Step 3: Write the skill document**

Create `core/skills/orchestrate/SKILL.md` with exactly this content:

```markdown
---
name: harness-orchestrate
description: Executes an approved delta spec's implementation plan by dispatching one implementer and one reviewer subagent per item, with a separate model per role.
argument-hint: "[Path to an approved delta spec]"
---

# /harness-orchestrate: Dispatched Delivery Workflow

Use this workflow to execute an Implementation Plan that already exists in an approved delta spec. If the requirement has no spec yet, use `/harness-implement`. If the requested outcome is analysis only, use `/harness-investigate`.

This workflow requires subagent dispatch and is installed only into Claude Code. It has no degraded single-context mode: without dispatch, the correct answer is `/harness-implement`, which delivers the same engineering gates inside one context.

## Workflow Contract

- The argument is the path to a delta spec whose section 3 carries a numbered Implementation Plan. Without one, stop and name `/harness-implement`.
- Run `harness spec verify <spec-path>` as the entry gate. A non-zero status ends the run before any dispatch.
- Verify that subagent dispatch is available before the first item. When it is not, abort with a diagnostic and name `/harness-implement`.
- Open the run with `RUN_ID="$(harness receipt start orchestrate --issue <issue-token>)"` and `harness ledger start "$RUN_ID"`. Omit `--issue` when no safe issue token exists.
- Dispatch strictly one item at a time, in plan order. Two subagents are never in flight at once, because they would race on one working tree.
- Close the run with `harness receipt finish "$RUN_ID" completed`, or `failed`, `blocked`, or `cancelled` when appropriate.

### The orchestrator does not implement

You dispatch, you record, you adjudicate. You do not write production code, you do not write tests, and you do not apply the fixes yourself. If you find yourself editing a source file, you have abandoned the role that makes this workflow worth running.

### One writer for the ledger

You are the only caller of `harness ledger append`. Subagents report to you and you record the outcome. The ledger stays a single-voice record of what you decided, and concurrent writes are impossible by construction.

## Roles and Models

| Role | Default model | Reads | Never sees |
| :--- | :--- | :--- | :--- |
| implementer | `sonnet` | The spec, the item, the repository | The reviewer's findings from another item |
| reviewer | `opus` | The diff, the item, `rules/floor.md` | The implementer's reasoning or narrative |

Resolve the configured models with `harness context --json` and read its `orchestrateModels` object. A profile overrides the defaults through `profiles.<profile>.orchestrate.models`.

Configuration selects which model fills a role. It can never collapse the two roles into one dispatch: the reviewer is always a separate dispatch with a fresh context.

## Phases

1. **Admit** — Run `harness context`, read the delta spec, and run `harness spec verify <spec-path>`. Enumerate the numbered plan items and state how many there are. Record the run with `harness receipt start` and `harness ledger start`.
2. **Dispatch the implementer** — Send the brief below for item N. Require the RED-GREEN-REFACTOR protocol from `references/tdd.md` and require `harness qa test` before the return. Record the outcome with `harness ledger append "$RUN_ID" phase "item <N> implemented — <summary>"`.
3. **Dispatch the reviewer** — Send a separate dispatch with the diff from `git diff`, the item text, and `rules/floor.md`. Require findings classified Critical, Important, or Minor using `references/review.md`. Record the counts in the ledger.
4. **Resolve the item** — Run the Bounded Review Loop below until it exits, then move to item N+1. Repeat phases 2 to 4 until the plan is exhausted.
5. **Close** — Run `harness qa all` once and report its real status. Run `harness ledger rulings "$RUN_ID"` and reproduce every line, exhaustively and in recorded order. Finish the receipt.

## The Brief

A subagent inherits the repository, so the brief is short and has exactly seven fields:

- `RUN_ID` — the run identifier, for your records, not for the subagent to write with
- `SPEC` — the delta spec path, to be read from disk
- `ITEM` — the plan item number and its verbatim text
- `FILES` — the paths this item is permitted to touch
- `ACCEPTANCE` — the observable behavior that proves the item is done
- `TEST` — `harness qa test`
- `PROHIBITIONS` — no commit, no push, no pull request, no change to any external system, no work on another item

## The Return

Every subagent returns one line in this shape:

`ITEM <N> | STATUS pass|blocked | TESTS <command> <result> | FILES <list> | NOTES <one to three lines>`

A malformed return is re-dispatched exactly once with the shape restated. A second malformed return marks the item `blocked` and ends the run.

## Bounded Review Loop

The loop is per item and it never runs unbounded.

- **Minor findings never enter the loop.** Record each with `harness ledger append "$RUN_ID" deferred "<one-liner>"` and report them at hand-off.
- **Critical and Important findings enter the loop.** One round is one implementer dispatch plus one reviewer dispatch scoped to the amended code. After each round, record `harness ledger append "$RUN_ID" phase "item <N> round <R>/3 (<X> addressed, <Y> open)"`.
- **Three rounds is the cap.** Do not open a fourth. A loop that survives three rounds has a structural problem that another round will not solve.
- **At the cap, adjudicate every open finding individually.** Either park it with `harness ledger append "$RUN_ID" parked "<finding> — Ruling: <why the code stands>"`, or classify it as load-bearing.
- **A load-bearing finding at the cap ends the workflow as blocked.** Record `harness ledger append "$RUN_ID" ruling "<finding> — blocked: <what the user must decide>"`, call `harness receipt finish "$RUN_ID" blocked`, and hand the decision to the user.

## 🛑 Anti-Rationalization Gate (Banned LLM Excuses)

| Agent Rationalization (Excuse) | Mandatory Rule / Rebuttal |
| :--- | :--- |
| *"This item is small, I will just implement it myself."* | **BANNED.** The orchestrator never implements. A fresh context per item and a reviewer who did not write the code are the entire product of this workflow. |
| *"These two items are independent, I will dispatch both."* | **BANNED.** Dispatch is serial. Two subagents share one working tree, and that is a race, not a speedup. |
| *"I will review this item myself to save a dispatch."* | **BANNED.** A reviewer who saw the implementation reasoning is not a reviewer. Dispatch separately or do not claim review. |
| *"The subagent's return was close enough."* | **BANNED.** Re-dispatch once with the shape restated. A second malformed return blocks the item. |
| *"Dispatch is unavailable, I will run the plan inline."* | **BANNED.** That is `/harness-implement`. Name it and stop. |

## Safety Boundary

- Do not run this workflow without an approved delta spec that passes `harness spec verify`.
- Do not edit production code, tests, or configuration yourself.
- Do not dispatch more than one subagent at a time.
- Do not commit, push, open a pull request, or change external systems unless the user explicitly asks.
- Do not report completion while a load-bearing finding is open. Finish the receipt as `blocked`.
- Do not absorb work that no plan item covers; record it as debt and continue.

## State Anchor

Report progress on every turn as:

`[ORCHESTRATE: Item X/Y — <role dispatched> | Gate: <evidence or pending> | Next: <next action>]`

Inside the bounded review loop:

`[ORCHESTRATE: Item X/Y — review | Round <R>/3 | Open: <C> Critical, <I> Important | Next: <next action>]`

Completion requires:

`[ORCHESTRATE: COMPLETE | Items: <Y> | QA: PASS | Rulings: <N> | Publish: NOT REQUESTED|COMPLETE]`

A load-bearing finding at the cap ends the run as:

`[ORCHESTRATE: BLOCKED | Item: <X>/<Y> | Load-bearing findings: <N> | Rulings: <N>]`
```

- [ ] **Step 4: Add the catalog entry and the runtimes map**

In `core/skills/catalog.json`, add the workflow to `public` and the sibling map after it:

```json
    "orchestrate": [
      "spec",
      "tdd",
      "qa",
      "review"
    ]
```

```json
  "runtimes": {
    "orchestrate": ["claude"]
  },
```

Place `runtimes` between `public` and `internal`. Leave `schemaVersion` at `1`: the key is additive, optional, and the catalog has no consumer outside this repository.

- [ ] **Step 5: Run the test to verify the catalog contract passes and the installer now fails**

Run: `bash test/test_cli.sh`
Expected: group `2b` passes; group `6` now fails with `Curated installation exposed 4 skills in .agents/skills; expected 3`. That failure is the RED for the installer filter.

- [ ] **Step 6: Add the runtime filter to the installer**

In `install.sh`, add this helper directly above `install_workflow_bundle`:

```bash
workflow_allowed_for_runtime() {
    local workflow="$1"
    local runtime="$2"

    jq -e --arg workflow "${workflow}" --arg runtime "${runtime}" \
        'if (.runtimes // {}) | has($workflow) then (.runtimes[$workflow] | index($runtime)) != null else true end' \
        "${SKILL_CATALOG}" >/dev/null
}
```

An absent `runtimes` entry yields `true`, so the three existing workflows keep reaching every destination without a catalog entry of their own.

Change the signature and the workflow loop of `install_skill_surface`:

```bash
install_skill_surface() {
    local destination="$1"
    local runtime="$2"
    transaction_ensure_directory "${destination}"
    require_skill_catalog
```

```bash
    while IFS= read -r workflow; do
        if workflow_allowed_for_runtime "${workflow}" "${runtime}"; then
            install_workflow_bundle "${destination}" "${workflow}"
        fi
    done < <(jq -r '.public | keys[]' "${SKILL_CATALOG}")
```

Leave the cleanup loop above it untouched. Removal stays unconditional while installation is filtered, so a stale copy in a now-disallowed destination disappears on the next installation with no migration step.

- [ ] **Step 7: Pass the runtime label at both call sites**

Replace the target loop at `install.sh:339-341`:

```bash
    install_skill_surface "${gemini_skills}" gemini
    install_skill_surface "${claude_skills}" claude
    install_skill_surface "${codex_skills}" codex
    install_skill_surface "${agents_skills}" agents
```

Replace the global loop at `install.sh:388-390`:

```bash
    install_skill_surface "${gemini_skills}" gemini
    install_skill_surface "${gemini_config_skills}" gemini
    install_skill_surface "${claude_skills}" claude
    install_skill_surface "${codex_skills}" codex
    install_skill_surface "${agents_skills}" agents
```

Delete the now-unused `skills_destination` local declarations that fed those loops.

- [ ] **Step 8: Validate the runtimes map in require_skill_catalog**

Append to `require_skill_catalog`, before its closing brace:

```bash
    local gated_workflow gated_runtime
    while IFS= read -r gated_workflow; do
        if ! jq -e --arg workflow "${gated_workflow}" '.public | has($workflow)' "${SKILL_CATALOG}" >/dev/null; then
            log_error "Catalog gates a workflow that is not public: ${gated_workflow}"
            return 1
        fi
    done < <(jq -r '(.runtimes // {}) | keys[]' "${SKILL_CATALOG}")

    while IFS= read -r gated_runtime; do
        case "${gated_runtime}" in
            agents|claude|codex|gemini) ;;
            *)
                log_error "Unknown runtime label in catalog: ${gated_runtime}"
                return 1
                ;;
        esac
    done < <(jq -r '(.runtimes // {}) | to_entries[] | .value[]' "${SKILL_CATALOG}")
```

- [ ] **Step 9: Make the default-surface assertions runtime-aware**

In `test/test_cli.sh`, replace the whole `for runtime_dir in .agents/skills .claude/skills .codex/skills .gemini/skills; do` block with this. It derives the expectation from the catalog instead of hardcoding three, and it asserts the absence of a gated workflow in every runtime that must not receive it:

```bash
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
```

This is the assertion that proves the gating claim: `.claude/skills` expects four, the other three expect three, and a leak is named explicitly rather than inferred from a count.

- [ ] **Step 10: Filter the expert-surface assertion by runtime**

The expert group verifies `(.public | keys[]), .internal[]` against `${EXPERT_TARGET_DIR}/.codex/skills`, which would now demand `harness-orchestrate` in a runtime that must not have it. Replace that `while` loop with:

```bash
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
```

Note that the internal primitives are never gated: expert mode still symlinks every one of them into all four destinations. Only public workflows carry a `runtimes` entry, and the expression above returns `true` for anything absent from the map.

The later migration assertion in the same group expects four entries in `${EXPERT_TARGET_DIR}/.codex/skills` after re-running the default installation. That number is unchanged: three permitted workflows plus the user-owned skill.

- [ ] **Step 11: Run the full suite to verify green**

Run: `env -u STACK_PROFILE npm test && npm run lint`
Expected: PASS. Then confirm the gating by hand:

```bash
rm -rf /tmp/ah7 && mkdir -p /tmp/ah7 && git -C /tmp/ah7 init -q && ./install.sh --target /tmp/ah7 >/dev/null
ls /tmp/ah7/.claude/skills /tmp/ah7/.codex/skills
```

Expected: `harness-orchestrate` appears under `.claude/skills` and under no other runtime.

- [ ] **Step 12: Verify the unconditional cleanup path**

Run:

```bash
mkdir -p /tmp/ah7/.codex/skills/harness-orchestrate
printf '%s\n' 'agent-harness-skill-bundle-v1' > /tmp/ah7/.codex/skills/harness-orchestrate/.agent-harness-managed
./install.sh --target /tmp/ah7 >/dev/null
[ -e /tmp/ah7/.codex/skills/harness-orchestrate ] && echo "LEAK" || echo "CLEANED"
```

Expected: `CLEANED`. This is the property that makes the change migration-free.

- [ ] **Step 13: Commit**

```bash
git add core/skills/orchestrate/SKILL.md core/skills/catalog.json install.sh test/test_cli.sh
git commit -m "feat(AH-7): add orchestrate workflow gated to the claude runtime"
```

---

### Task 2: Per-role model configuration

**Files:**
- Modify: `schema.json` (profile properties, alongside `ci` and `qa`)
- Modify: `harness.config.json` (`profiles.harness`)
- Modify: `core/scripts/stack-context.sh:35-38` (value resolution), `:53-66` (JSON output), `:68-78` (text output)
- Test: `test/test_cli.sh:104-112` (group 4)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `harness context --json` emits `.orchestrateModels.implementer` and `.orchestrateModels.reviewer`, both strings, never empty. Defaults are `sonnet` and `opus`. The skill written in Task 1 reads exactly these two paths.

- [ ] **Step 1: Write the failing test**

Append to group 4 of `test/test_cli.sh`, after the existing `branch` assertion:

```bash
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
```

`TMP_TEST_DIR` already exists in this suite; reuse it rather than creating another temporary root.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash test/test_cli.sh`
Expected: FAIL at group 4 with `harness context --json must expose distinct orchestrate models`, because the key does not exist and both values read as `null`.

- [ ] **Step 3: Resolve the values in the context script**

In `core/scripts/stack-context.sh`, add after the `ISSUE_PROVIDER` assignment:

```bash
ORCHESTRATE_IMPLEMENTER="$(get_profile_value "orchestrate.models.implementer" "sonnet")"
ORCHESTRATE_REVIEWER="$(get_profile_value "orchestrate.models.reviewer" "opus")"
```

`get_profile_value` already resolves dotted paths through `jq`, so no helper is needed.

- [ ] **Step 4: Emit the values**

In the JSON branch, insert before the `"activeDeltaSpecs"` line:

```bash
  "orchestrateModels": {
    "implementer": "${ORCHESTRATE_IMPLEMENTER}",
    "reviewer": "${ORCHESTRATE_REVIEWER}"
  },
```

In the text branch, insert before the `Active Delta Specs:` line:

```bash
Orchestrate Models:   implementer=${ORCHESTRATE_IMPLEMENTER} reviewer=${ORCHESTRATE_REVIEWER}
```

- [ ] **Step 5: Describe the block in the schema**

In `schema.json`, add to `properties.profiles.additionalProperties.properties`, next to `ci`:

```json
"orchestrate": {
  "type": "object",
  "description": "Subagent orchestration settings for /harness-orchestrate (Claude Code only)",
  "properties": {
    "models": {
      "type": "object",
      "description": "Model identifier per dispatched role",
      "properties": {
        "implementer": {
          "type": "string",
          "description": "Model for the implementer dispatch"
        },
        "reviewer": {
          "type": "string",
          "description": "Model for the reviewer dispatch"
        }
      }
    }
  }
}
```

Values are free-form strings and deliberately not an enumeration: model identifiers age faster than this repository releases, and a stale enum would reject a valid configuration.

- [ ] **Step 6: Declare this repository's own choices**

In `harness.config.json`, add to `profiles.harness` after the `ci` block:

```json
      "orchestrate": {
        "models": {
          "implementer": "sonnet",
          "reviewer": "opus"
        }
      },
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `env -u STACK_PROFILE npm test && npm run lint`
Expected: PASS, including `shellcheck -S warning` on the modified script.

- [ ] **Step 8: Commit**

```bash
git add schema.json harness.config.json core/scripts/stack-context.sh test/test_cli.sh
git commit -m "feat(AH-7): expose per-role orchestrate models through harness context"
```

---

### Task 3: Runtime-aware compatibility matrix

**Files:**
- Modify: `test/e2e/test_install_matrix.sh:98-146` (`verify_skill_surface`), `:177`, `:205`, `:216-239` (`write_report`)
- Modify: `docs/COMPATIBILITY.md` (evidence schema block and verified contracts)

**Interfaces:**
- Consumes: the `.runtimes` catalog key from Task 1.
- Produces: `verify_skill_surface <destination> <mode> <allow_user_skill> <runtime>`; an evidence artifact carrying `schemaVersion: 2` and a boolean `runtimeGating` field.

- [ ] **Step 1: Write the failing assertion**

In `test/e2e/test_install_matrix.sh`, change the signature and the public-workflow loop of `verify_skill_surface`:

```bash
verify_skill_surface() {
    local destination="$1"
    local mode="$2"
    local allow_user_skill="$3"
    local runtime="$4"
    local namespace workflow published_workflow primitive published_primitive removed installed_count expected_count
    namespace="$(jq -r '.namespace // empty' "${SKILL_CATALOG}")"
    [ "${namespace}" = "harness" ] || { echo "Unexpected skill namespace: ${namespace}" >&2; return 1; }

    expected_count=0
    while IFS= read -r workflow; do
        published_workflow="${namespace}-${workflow}"
        if jq -e --arg workflow "${workflow}" --arg runtime "${runtime}" \
            'if (.runtimes // {}) | has($workflow) then (.runtimes[$workflow] | index($runtime)) != null else true end' \
            "${SKILL_CATALOG}" >/dev/null; then
            expected_count=$((expected_count + 1))
            assert_file "${destination}/${published_workflow}/SKILL.md" || return 1
            grep -qx "name: ${published_workflow}" "${destination}/${published_workflow}/SKILL.md" || return 1
        else
            assert_absent "${destination}/${published_workflow}" || return 1
        fi
    done < <(jq -r '.public | keys[]' "${SKILL_CATALOG}")
```

Then delete the `expected_count="$(jq -r '.public | length' "${SKILL_CATALOG}")"` line further down, keeping the `expert` and `allow_user_skill` increments that follow it:

```bash
    if [ "${mode}" = "expert" ]; then
        expected_count=$((expected_count + $(jq -r '.internal | length' "${SKILL_CATALOG}")))
    fi
```

Pass the runtime at both call sites. In `verify_target_contracts` at line 177 and in `verify_global_contracts` at line 205, the loop variable `runtime` is already in scope:

```bash
        verify_skill_surface "${path}" "${mode}" "${allow_user}" "${runtime}" || return 1
```

- [ ] **Step 2: Run the matrix, then prove the assertion has teeth**

Run: `bash test/e2e/test_install_matrix.sh --scope target --mode default`
Expected: PASS.

Widening the catalog would not test anything: the installer and the matrix read the same file, so any consistent edit stays consistent. Mutate the installer instead, so the two disagree:

```bash
sed -i.bak 's/if workflow_allowed_for_runtime "${workflow}" "${runtime}"; then/if true; then/' install.sh
bash test/e2e/test_install_matrix.sh --scope target --mode default; echo "exit=$?"
mv install.sh.bak install.sh
```

Expected: the mutated run FAILS with `Unexpected managed path` naming `harness-orchestrate` under a non-Claude destination, and a non-zero exit. A passing mutated run means the assertion is decorative and must be fixed before moving on. Restore `install.sh` with the `mv` above, and confirm `git status --short` is clean for that file.

- [ ] **Step 3: Record the gating assertion in the evidence artifact**

In `write_report`, add the field and bump the evidence schema:

```bash
    jq -n \
        --arg os "$(uname -s)" \
        --arg scope "${scope}" \
        --arg mode "${mode}" \
        --arg status "${status}" \
        --argjson verifiedContracts "${contracts}" \
        '{schemaVersion: 2, os: $os, scope: $scope, mode: $mode, status: $status, installerRuns: 2, idempotent: ($status == "passed"), userContentPreserved: ($status == "passed"), runtimeGating: ($status == "passed"), verifiedContracts: $verifiedContracts}' \
        > "${path}"
```

The bump to `2` is deliberate. `docs/COMPATIBILITY.md` publishes this shape as a stable contract, and adding a field changes it, so the version has to move with it.

- [ ] **Step 4: Update the compatibility document**

In `docs/COMPATIBILITY.md`, replace the evidence JSON block with the `schemaVersion: 2` shape including `runtimeGating`, and add one bullet to the target-repository contract list:

```markdown
- a workflow gated to one runtime in the catalog reaches only that runtime, and is absent everywhere else;
```

Change the opening sentence of the target-repository section so it no longer implies an identical surface everywhere: the runner verifies the declared surface per runtime, not the same surface in every runtime.

- [ ] **Step 5: Run the full matrix**

Run: `bash test/e2e/test_install_matrix.sh`
Expected: all four cells for this operating system pass, and both installer executions per cell stay byte-for-byte identical.

- [ ] **Step 6: Commit**

```bash
git add test/e2e/test_install_matrix.sh docs/COMPATIBILITY.md
git commit -m "test(AH-7): verify the declared skill surface per runtime"
```

---

### Task 4: Documentation and release metadata

**Files:**
- Modify: `README.md`, `docs/ARCHITECTURE.md`, `docs/PROVENANCE.md:19`, `CHANGELOG.md`, `package.json`

**Interfaces:**
- Consumes: the finished behavior from Tasks 1 to 3.
- Produces: no code interface.

- [ ] **Step 1: Document the workflow in the README**

Add `/harness-orchestrate` to the workflow list with its Claude Code restriction stated in the first sentence, and add a short runtime-support table:

```markdown
| Workflow | Antigravity | Claude Code | Codex | Cursor | `.agents` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `/harness-implement` | yes | yes | yes | yes | yes |
| `/harness-fix` | yes | yes | yes | yes | yes |
| `/harness-investigate` | yes | yes | yes | yes | yes |
| `/harness-orchestrate` | no | yes | no | no | no |
```

Say plainly why: the workflow requires subagent dispatch, and `/harness-implement` is the equivalent everywhere else.

- [ ] **Step 2: Correct the provenance row**

In `docs/PROVENANCE.md`, the `obra/superpowers` row currently ends with a sentence stating that subagent dispatch and per-role model selection were deliberately not adapted. Replace that sentence with one recording that AH-7 adapts them as `harness-orchestrate`, still citing `b36e082`, and add `orchestrate/SKILL.md` to the row's file list. Keep the existing statement that only the method is adapted and no template or script was copied.

- [ ] **Step 3: Describe the gating seam in the architecture document**

Add a short subsection covering the catalog's `runtimes` map, the rule that an absent entry means every runtime, and the property that cleanup stays unconditional while installation is filtered.

- [ ] **Step 4: Add the changelog entry and bump the version**

In `CHANGELOG.md`, add a `## [2.1.0]` section above `## [2.0.0]`, dated the day this work lands in `YYYY-MM-DD` form to match the existing entries, with `### Added` entries for the workflow, the catalog gating, and the per-role model configuration. Leave `## [Unreleased]` empty above it. Then set `"version": "2.1.0"` in `package.json`. A new public workflow with no breaking change is a minor bump.

- [ ] **Step 5: Verify no claim outruns the code**

Run: `harness scan --diff && env -u STACK_PROFILE npm test && npm run lint && ./setup --verify`
Expected: PASS. Re-read every sentence added in this task and confirm each names behavior that Tasks 1 to 3 actually implemented.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/ARCHITECTURE.md docs/PROVENANCE.md CHANGELOG.md package.json
git commit -m "docs(AH-7): document orchestrate and per-runtime skill gating"
```

---

## Final Verification

- [ ] `harness spec verify specs/delta-AH-7-orchestrate-dispatch.md`
- [ ] `env -u STACK_PROFILE npm test && npm run lint && ./setup --verify`
- [ ] `bash test/e2e/test_install_matrix.sh`
- [ ] `harness scan --diff`
- [ ] Tick every requirement checkbox in `specs/delta-AH-7-orchestrate-dispatch.md` sections 2 and 3 that the work actually satisfied, and leave unticked anything it did not.
- [ ] Two-axis review per `core/skills/review/SKILL.md`.
