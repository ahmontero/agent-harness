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
- Record each phase with `harness receipt phase "$RUN_ID" <token> <status>`. The five tokens this workflow owns are `admit`, `dispatch`, `review`, `resolve`, and `close`; the receipt rejects any other. The receipt is a closed schema, so anything that needs words belongs in the ledger instead.
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
