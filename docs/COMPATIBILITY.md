# Verified Compatibility

[![Compatibility Evidence](https://github.com/ahmontero/agent-harness/actions/workflows/compatibility.yml/badge.svg)](https://github.com/ahmontero/agent-harness/actions/workflows/compatibility.yml)

The compatibility workflow turns the installation claims in the README into a repeatable black-box contract. Every pull request and push to `main` runs eight independent cells:

| Dimension | Values |
| :--- | :--- |
| Operating system | Ubuntu latest, macOS latest |
| Installation scope | Target repository, isolated global home |
| Skill surface | Default, expert |
| Installer executions per cell | Two |

Each cell uploads a versioned JSON evidence artifact. A matrix failure identifies the exact operating system, installation scope, and skill-surface mode that violated the contract.

## Verified Contracts

### Target-repository installation

The runner verifies the surface each runtime is declared to receive, which is not the same surface everywhere: a workflow may be gated to one runtime in the skill catalog. It verifies:

- `.gemini/skills`, `.claude/skills`, `.codex/skills`, and `.agents/skills` expose the surface declared for that runtime;
- a workflow gated to one runtime in the catalog reaches only that runtime, and is absent everywhere else;
- runtime rule directories exist for Gemini, Claude, Codex, Cursor, and `.agents`;
- `AGENTS.md` and its `CLAUDE.md` and `GEMINI.md` links are present;
- default mode exposes exactly the three public workflows;
- expert mode additionally exposes every supported internal primitive;
- removed skills remain absent; and
- an unmanaged user-owned skill survives both installer executions.

### Global installation

The runner uses a temporary `HOME` and verifies:

- Gemini Antigravity, Claude Code, Codex, and `.agents` receive the expected skill surface;
- the `harness`, `agh`, and `agent-harness` CLI links are installed under the isolated home;
- default and expert visibility rules match the catalog;
- removed skills remain absent; and
- unmanaged user content is preserved.

### Idempotence

Every cell snapshots directory entries, symlink targets, and portable `cksum` values after the first installation. It executes the same installation again and requires the second snapshot to be byte-for-byte identical.

## Evidence Schema

Artifacts use this stable, machine-readable shape:

```json
{
  "schemaVersion": 2,
  "os": "Linux",
  "scope": "target",
  "mode": "default",
  "status": "passed",
  "installerRuns": 2,
  "idempotent": true,
  "userContentPreserved": true,
  "runtimeGating": true,
  "verifiedContracts": ["agents", "claude", "codex", "cursor", "gemini"]
}
```

`schemaVersion` moved from `1` to `2` when `runtimeGating` was added. A consumer pinned to version 1 should expect the field to be absent there.

Failed assertions return a non-zero status and, when a report path is supplied, record `status: "failed"` instead of emitting a false success.

## Reproduce Locally

Run the complete four-cell matrix for the current operating system:

```bash
bash test/e2e/test_install_matrix.sh
```

Run one cell and retain its JSON evidence:

```bash
bash test/e2e/test_install_matrix.sh \
  --scope target \
  --mode default \
  --report compatibility-target-default.json
```

The test requires Bash, Git, `jq`, and standard POSIX userland tools already required by the project.

## Evidence Boundary

This matrix verifies the filesystem and CLI installation contracts owned by `agent-harness`. It does not launch or evaluate proprietary agent runtimes, prove editor UI behavior, access package registries, or claim Windows support. Those capabilities require separate evidence and must not be inferred from this workflow.
