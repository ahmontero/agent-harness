# Delta Spec: AH-20 — debt-marker-anchoring

## 1. Intent & Context
- **Issue / Ticket:** AH-20
- **Module:** debt
- **Summary:** `harness debt` reports sixteen technical debt markers in this repository and there are none. Every one is the harness describing or testing its own feature: seven in documentation, five in test fixtures that write the marker into a temporary repository, two in archived specs, and two in a help string and a source comment that name the marker. `harness context` therefore tells every agent that enters this repository that it carries sixteen debt items, which is the same class of untrue signal as the rest of this series, inverted: it does not hide a problem, it invents sixteen. The cause is that a debt marker is matched as a substring anywhere in a line, while a debt marker is a *comment*. Requiring the comment token to begin a comment — at the start of a line or after whitespace — removes fourteen of the sixteen and leaves trailing markers on a code line working, which is the form the marker is most often written in.
- **Target Module / Layer:** `core/scripts/lib/debt.sh`, `bin/harness`, `core/skills/debt/SKILL.md`, `test/test_cli.sh`, `README.md`, `CHANGELOG.md`, `package.json`.

## 2. Requirements & Domain Floor Invariants
- [x] Requirement 1: A marker is recognized when its comment token starts a line, follows only indentation, or follows whitespace on a code line. All three are how a debt marker is actually written.
- [x] Requirement 2: A marker quoted inside prose or a string literal — preceded by a backtick, a quote, or a parenthesis — is not a debt marker and is not reported.
- [x] Requirement 3: The two remaining places where this repository names the markers in running text are rewritten so the text quotes them, which is both better typography and no longer a false positive. They are not suppressed and no path is excluded: configuration to hide a wrong answer is worse than the wrong answer.
- [x] Requirement 4: A test asserts that the files which describe and test the feature — `README.md`, `AGENTS.md`, `core/skills/debt/SKILL.md`, `test/test_cli.sh` — yield no findings, so this cannot regress while remaining true if real debt is recorded elsewhere.
- [x] Invariant: Must not violate `rules/floor.md`. `harness context` must not state a count it cannot justify.

## 3. Implementation Plan
1. [x] Add failing coverage to `test/test_cli.sh` for the three forms that must match, the three that must not, and the dogfooding assertion.
2. [x] Anchor the pattern in `core/scripts/lib/debt.sh` to the start of a comment.
3. [x] Quote the markers in the `bin/harness` help string and the `core/skills/debt/SKILL.md` description.
4. [x] Run `harness qa all` and the full suite.

## 4. Verification & QA
- **Automated Test Command:** `env -u STACK_PROFILE npm test`
- **Expected Outcome:** Green suite with zero regressions, including the new assertions in group 41, and `harness context` reporting zero technical debt markers in a repository that has none.
