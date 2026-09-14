---
name: harness-commit
description: Builds and validates Conventional Commit messages prefixed with the active issue key.
argument-hint: "build <type> \"<message>\" | check [commit_hash] | --install-hook"
---

# /harness-commit: Conventional Commit Builder

Formats commit messages according to Conventional Commits standards with issue keys extracted from the active branch:

```bash
harness commit build feat "add JWT authentication middleware"
# Output: feat(PROJ-123): add JWT authentication middleware
```

`harness commit --install-hook` installs a `commit-msg` hook that applies the same rules
`harness commit check` applies, before the commit exists — rather than at `harness ship`,
by which point the only remedy is rewriting history. It refuses a `commit-msg` hook it did
not write unless `--force` is given, and backs that one up first.

A merge, a revert, and a `fixup!`/`squash!` subject pass untouched: those messages are
written by git or rewritten by the rebase they exist for, and are not the project's to
conform. Comment lines are stripped before judging, so a trailer quoted in git's own
template is not read as a trailer the commit carries.
