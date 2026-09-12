# Delta Spec: AH-28 — security-baseline

## 1. Intent & Context
- **Issue / Ticket:** AH-28
- **Module:** security
- **Summary:** The default landmine ruleset detects one of five textbook secrets. Measured against a file carrying `API_KEY = "AKIA…"`, `password = "…"`, `GITHUB_TOKEN = "ghp_…"`, a `postgres://` DSN carrying its credentials inline, and an inline PEM block, only the lowercase `api_key` assignment was reported. This delta gives the scanner a security baseline it always applies, which a project's own rules file extends rather than replaces.
- **Target Module / Layer:** `core/scripts/stack-scan.sh`, `core/templates/security-baseline.json` (new), `schema.json`, `README.md`, `test/test_cli.sh`.

### Why a baseline and not a better template

The scanner resolves exactly one rule file: `--rules`, else `profiles.<p>.rules.scanner`, else the built-in template (`stack-scan.sh:156-185`). `harness init` copies that template into the project as `rules/landmines.json`. Improving the template therefore reaches new projects only — every repository that has already run `init` keeps its four-rule copy indefinitely, and choosing a recipe substitutes a different and equally partial set. A baseline the scanner always applies is the only shape that reaches the installed base, and it keeps one copy of the security rules rather than the five that AH-26 has just finished deleting for the same reason.

### Why `grep -I` belongs to this delta

Every rule shipped today carries `fileExtensions`, so no rule has ever been applied to a binary file. Baseline rules cannot: secrets live in `.yaml`, `.tf`, `.json` and `.env` as readily as in `.py`. With the restriction gone, a binary that matches makes `grep -En` print `Binary file <path> matches` with no line number, which reaches `line_is_suppressed` and produces `sed: invalid command code B` and `[: … integer expression expected` in the middle of a scan, a finding with no line, and — the part that matters — a finding that `harness-ignore:` cannot suppress, because there is no line to annotate. The only remaining escape is `--no-verify`, which retires the whole gate. This delta is what makes that reachable, so it is what closes it.

## 2. Requirements & Domain Floor Invariants
- [x] R1: The scanner applies a built-in security baseline in addition to the resolved rule file, and reports which baseline it used alongside the rule file it used.
- [x] R2: A project rule whose `id` matches a baseline rule replaces it. That is the per-rule escape hatch, and it is the only way a project can weaken a baseline rule without disabling the baseline.
- [x] R3: `profiles.<p>.rules.securityBaseline: false` disables the baseline entirely, following the `qa.lintCommand: false` idiom for declaring something deliberately absent. `schema.json` describes it.
- [x] R4: A rule may set `ignoreCase: true`; the scanner passes `-i` to grep for that rule only. Provider-token rules stay case-sensitive, because `AKIA`, `ghp_` and `AIza` are literal.
- [x] R5: The baseline detects, at minimum: a case-insensitive credential assignment, GitHub / AWS / OpenAI / Slack / Google provider tokens, credentials embedded in a URL or DSN, and a PEM private-key block by content.
- [x] R6: The baseline does not fire on an interpolated or placeholder value — `"${DB_PASSWORD}"`, `"{{ vault_token }}"`, `"<your-key>"`, `"%s"` — because a gate that cries wolf is answered with `--no-verify`.
- [x] R7: The scanner skips binary files (`grep -I`), so no finding can be raised that per-line suppression cannot address.
- [x] R8: This repository passes its own baseline with no suppressions and no path exclusions. Its fixtures are assembled from arguments — `printf '%s = "%s"\n' "api_key" "…"` — so the suite writes the secret-shaped content its tests need while carrying none itself. That is better than the per-line suppression this spec first proposed: a suppressed fixture is still a secret in the file, and it is the move AH-20 made for the debt marker.
- [x] Invariant: Must not violate `rules/floor.md`. In particular invariant 1 — a scan that could not read its baseline is not a passing scan — and invariant 3 — the README's description of the rule format must match the fields the scanner reads.

### Non-goals
- Rewriting the four existing template rules. `SEC-001`, `SEC-002`, `PERF-001` and `SEC-003` stay as they are; the baseline is additive.
- Touching the three recipes' rule files. With a baseline that always applies, their partial secret rules are no longer the only thing standing between a recipe project and a leaked credential.
- Scanner performance. The rule-by-file loop is a known gap, measured at 12.3s for 1000 files and 4 rules, and this delta adds rules to it. It is recorded as debt, not fixed here.

## 3. Implementation Plan
1. [x] RED — assert the five-secret file is detected in full, that an interpolated value and a placeholder are not, and that a binary file raises nothing.
2. [x] Add `core/templates/security-baseline.json` with the rules R5 requires, each carrying `ignoreCase` where R4 calls for it.
3. [x] Teach `stack-scan.sh` to load the baseline, merge it under R2's id-precedence, honour R3, and report both sources.
4. [x] Add `ignoreCase` to the rule contract: the scan loop, the rule validator, and the README's format section.
5. [x] Add `-I` to both grep invocations in the scan loop, with the binary case covered by R1's test.
6. [x] Describe `rules.securityBaseline` in `schema.json` and the baseline in `README.md`.
7. [x] Make this repository pass its own baseline — assembling its three inline fixtures rather than suppressing them — then run `harness qa all`.

## 4. Verification & QA
- **Automated Test Command:** `bash test/test_cli.sh`
- **Expected Outcome:** A new test group asserting R1 through R8 passes; the existing scanner groups (5, 17, 19, 31, 33, 34) stay green; `harness qa all` exits 0 over this repository with the baseline applied to it.
