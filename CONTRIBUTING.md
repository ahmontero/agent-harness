# Contributing to agent-harness

Thank you for your interest in improving `agent-harness`!

## Development & Verification
Before submitting a Pull Request:
1. Ensure all shell scripts pass syntax checks:
   ```bash
   ./setup --verify
   ```
2. Run the test suite:
   ```bash
   npm test
   # or
   bash test/test_cli.sh
   ```
3. Ensure all skills in `core/skills/**/SKILL.md` contain valid YAML frontmatter.
