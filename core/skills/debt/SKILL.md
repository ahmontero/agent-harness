---
name: debt
description: Scans and harvests technical debt and pragmatism markers (# pragmatism:, # defer:) across the codebase.
argument-hint: "[--json] [--path <path>]"
---

# /debt: Technical Debt Harvester

Scans repository for `# pragmatism:` and `# defer:` comments to generate actionable debt audits.

```bash
harness debt
harness debt --json
```
