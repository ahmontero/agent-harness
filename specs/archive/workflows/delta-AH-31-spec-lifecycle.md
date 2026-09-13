# Delta Spec: AH-31 — spec-lifecycle

## 1. Intent & Context
- **Issue / Ticket:** AH-31
- **Module:** workflows
- **Summary:** `harness spec archive` exists, works, and is tested, and nothing an agent reads mentions it. No workflow calls it, the `spec` primitive's own `argument-hint` omits it, and the README never names it. A delivered spec therefore stays active forever, and `harness context` — the first command every workflow runs — reports work in flight that shipped weeks ago.
- **Target Module / Layer:** `core/skills/spec/SKILL.md`, `core/skills/{implement,orchestrate}/SKILL.md`, `core/scripts/stack-pr.sh`, `README.md`, `test/test_cli.sh`.

### This already happened once, and left a scar in the suite

`test/test_cli.sh` contains an assertion that `specs/delta-AH-11-truthful-core-hardening.md` is not present, with the comment "A delivered spec left active makes harness context overstate what is in flight." That is a test hardcoded to one filename because one spec was forgotten. It cannot catch the next one, because the next one will have a different name. The defect it guards is the missing step, not the file.

### The step is not merely uncalled, it is undiscoverable

`bin/harness` advertises `spec archive` in its help. Nothing else does. The `spec` primitive bundled into `/harness-implement` and `/harness-orchestrate` documents `status`, `create` and `verify`, and its frontmatter hint lists exactly those three. An agent working from the bundle has no way to learn the command exists, which is why three consecutive deltas in this repository were archived by hand rather than by protocol.

### Why `ship` warns and does not refuse

A protocol instruction is a hope; this repository's own floor says claims must be executable. `harness ship` is the last point before work is published, and an active spec for the branch being shipped is worth naming there. It warns rather than refuses, for the reason `ship` already gives about untracked files: a project may legitimately carry one spec across several pull requests, and refusing would retire the command rather than catch the mistake.

## 2. Requirements & Domain Floor Invariants
- [ ] R1: The `spec` primitive documents `harness spec archive`, including in its `argument-hint`, and states when a spec is archived: at hand-off, once the workflow has produced a reviewed and verified tree.
- [ ] R2: `/harness-implement` phase 7 and `/harness-orchestrate` phase 5 archive the delta spec they worked from.
- [ ] R3: `harness ship` reports any active delta spec before publishing, naming the paths, and publishes anyway. It never refuses on one.
- [ ] R4: The README describes the full lifecycle, archive included, where it already describes specs.
- [ ] R5: A test asserts the protocols require archiving and that the primitive documents the command, so the step cannot go missing again by being forgotten rather than by being wrong.
- [ ] R6: The existing AH-11 assertion is left exactly as it is. It guards a specific historical file and this delta does not make it redundant.
- [ ] Invariant: Must not violate `rules/floor.md`. Invariant 3 in particular — `harness spec archive` is advertised by the dispatcher and reachable by no documented path, which is a claim the project makes and does not honour.

### Non-goals
- Refusing to ship on an active spec. Stated above and deliberate.
- Archiving automatically from `ship` or from any command. Which module a spec belongs to is a judgment the spec records and a human can correct; a command that moved files on its own would be doing the one thing this project refuses to do quietly.
- Changing `harness spec archive` itself. It resolves the module from the spec, refuses an occupied destination, and refuses a path outside `specs/`. The gap is that nobody is told to call it.

## 3. Implementation Plan
1. [ ] RED — assert that the `spec` primitive documents `archive` and lists it in its hint, that `implement` and `orchestrate` require it at hand-off, and that `ship` reports an active spec without refusing.
2. [ ] Document `archive` in `core/skills/spec/SKILL.md`, in its `argument-hint`, and say when it is called.
3. [ ] Add the archive step to `/harness-implement` phase 7 and `/harness-orchestrate` phase 5.
4. [ ] Report active delta specs in `harness ship`, next to the untracked-files warning it already emits.
5. [ ] Describe the lifecycle in `README.md`.
6. [ ] Run `harness qa all`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** The new assertions pass; group 39's ship guards stay green, which is what proves the warning did not become a refusal — that group already asserts what `ship` refuses and what it merely reports. `harness qa all` exits 0.
