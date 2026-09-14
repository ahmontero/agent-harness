---
name: harness-doctor
description: Diagnoses and self-heals the engineering environment: CLI dependencies and symlinks, installed skill surfaces, the landmine pre-commit hook, the resolved configuration, and whether this project's QA gates can run.
argument-hint: "[--fix] [--check-auth]"
---

# /harness-doctor: Environment Health & Self-Healing

Diagnoses, in order: required and optional executables; which agent harnesses are active;
the target repository's `AGENTS.md`; whether each installed skill surface is still current;
whether the `~/.local/bin` CLI symlinks resolve to this checkout and are on `PATH`; whether
the repository's `pre-commit` hook is agent-harness's own, a foreign hook, or absent;
whether the resolved configuration passes `harness config validate`; and whether this
project's test, lint and type gates can run at all.

Drift and missing optional tooling are warnings and leave the exit status at `0`. A
configuration that does not validate, a broken CLI symlink, a missing required tool, or a
QA gate that cannot run is an error and exits non-zero. A gate the configuration declares
absent with `false` is a recorded decision, not a problem; doctor executes nothing and reads
the same resolution `harness qa all` runs, so the two cannot disagree about whether this
project can pass its own QA. A check that could not run is reported as unavailable, never
as clean.

```bash
# Diagnostic check
harness doctor

# Self-heal what can be repaired (AGENTS.md, drifted skill surfaces)
harness doctor --fix

# Also report whether the configured issue and CI provider CLIs are authenticated
harness doctor --check-auth
```
