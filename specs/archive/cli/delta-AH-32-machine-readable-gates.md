# Delta Spec: AH-32 — machine-readable-gates

## 1. Intent & Context
- **Issue / Ticket:** AH-32
- **Module:** cli
- **Summary:** `harness context`, `harness debt` and `harness spec status` answer in JSON. The two commands an agent most needs to act on — the scanner and the QA aggregate — answer only in ANSI-coloured prose, so an agent that wants to know which rule fired on which line, or which gate failed, parses log lines. This delta gives both a `--json` form.
- **Target Module / Layer:** `core/scripts/stack-scan.sh`, `core/scripts/stack-qa.sh`, `README.md`, `test/test_cli.sh`.

### The two commands have different problems

`stack-scan.sh` emits from 44 places and `log_info` and `log_success` write to **stdout** — only `log_warn` and `log_error` go to stderr. A JSON mode that does not move them produces a document no consumer can parse, which is exactly the defect `harness context` already closed and records in a comment: "an agent parsing JSON got prose".

`stack-qa.sh` has a different problem, not a larger one. Its gates run the project's own commands through `eval`, so the output on stdout belongs to `pytest`, `npm test` or whatever is configured. That output is not this project's to suppress, and it cannot share a stream with a JSON document.

### One mechanism for both

Both are solved by moving the process's stdout aside once, at the top, rather than by guarding 44 call sites or redefining the logging functions:

```sh
exec 3>&1 1>&2     # everything written as "stdout" now goes to stderr; fd 3 is the real one
...
printf '%s\n' "${document}" >&3
```

It cannot miss a call site, it carries the `eval`'d gate output with it, and it leaves one place to read. Guarding each site would eventually miss one, and a JSON mode that is correct in 43 places and prose in the 44th is worse than none.

## 2. Requirements & Domain Floor Invariants
- [ ] R1: `harness scan --json` emits one JSON document on stdout and nothing else. Every human line the scan would print goes to stderr, so a human watching still sees it.
- [ ] R2: The scan document carries each finding as `rule`, `name`, `level`, `file`, `line`, `text` and `message`, plus the mode, the rule sources, and the error and warning counts. A path-pattern finding has no line and reports `null` rather than inventing one.
- [ ] R3: `harness qa all --json` emits one JSON document on stdout naming every gate and its status, and the gates' own output goes to stderr. The four statuses are the four the aggregate already distinguishes by exit code: `passed`, `failed`, `unrunnable` and `declared-absent`.
- [ ] R4: A scan that could not run stays distinguishable from a clean one. `findings: []` with a `status` of `unrunnable` and exit `2` must never read as a pass.
- [ ] R5: A mistyped option is refused, not degraded. `harness scan --jsonn` must not scan and answer in prose — the defect `harness context` closed and whose comment explains it.
- [ ] R6: Exit statuses are unchanged in both commands. `--json` changes the shape of the answer, never the verdict.
- [ ] R7: The README documents both forms where it documents the commands.
- [ ] Invariant: Must not violate `rules/floor.md`. Invariant 1 in particular — a gate that could not run must remain reportable as such in the machine form, which is the whole reason R4 is stated separately.

### Non-goals
- `--json` on the individual gates (`harness qa test`, `lint`, `types`). They run one command and return its status; the aggregate is what has a shape worth serialising.
- Changing any human output. The prose stays byte-for-byte what it is; `--json` only decides which stream it lands on.
- A stable schema promise. The document is described in the README and asserted by tests; it is not yet versioned, and this spec does not claim it is.

## 3. Implementation Plan
1. [ ] RED — assert both commands emit a document `jq` accepts with nothing else on stdout, that a mistyped option is refused, that an unrunnable scan is distinguishable from a clean one, and that exit statuses do not move.
2. [ ] Add `--json` to `stack-scan.sh`: the fd swap, finding collection in `report_finding`, and the document.
3. [ ] Add `--json` to `stack-qa.sh all`: the fd swap, gate status collection, and the document.
4. [ ] Document both in `README.md`.
5. [ ] Run `harness qa all`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** The new assertions pass; scanner groups 5, 17, 19, 31, 33, 34, 43 and 44 and the QA group 7 stay green, which is what proves R6 — they already assert the exit statuses and the human output this delta must not move.
