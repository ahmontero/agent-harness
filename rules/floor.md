# Agent Harness Quality Floor

These invariants apply to every change in this repository.

1. **Required gates fail closed.** Scan, lint, type-check, and test failures must produce a non-zero aggregate status. A command must never print success after suppressing a required failure.
2. **Behavior changes start RED.** Add a deterministic failing test before modifying production behavior, then verify RED, GREEN, and regression coverage.
3. **Claims are executable.** Documented commands, validation messages, and advertised guarantees must correspond to implemented and tested behavior. Placeholders may not pass verification.
4. **Shell behavior is portable.** Runtime scripts must work with the Bash versions available on supported macOS and Linux runners and must avoid unannounced platform-specific utilities.
5. **Agent side effects are explicit.** Read-only investigation must not edit files, publish branches, or open pull requests. External publication requires an explicit user request.
6. **Changes stay scoped.** Do not combine unrelated refactors with an active feature or fix. Record follow-up work separately.

Before completion, run:

```bash
harness scan --diff
bash test/test_cli.sh
```
