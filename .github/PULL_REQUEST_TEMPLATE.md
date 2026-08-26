## 📝 Description

Briefly describe the change and its rationale:
- What problem does this solve?
- What changes were made to the core scripts, skills, or recipes?

---

## 🎯 Type of Change

- [ ] 🐛 Bug fix (non-breaking change fixing an issue)
- [ ] ✨ New feature (non-breaking change adding functionality)
- [ ] 🍳 New recipe (`recipes/<name>/`)
- [ ] 🧠 Skill improvement (`core/skills/<name>/`)
- [ ] 📚 Documentation update

---

## ✅ Pre-Flight Verification Checklist

Before requesting review, ensure all checks pass:

- [ ] Run syntax & skill frontmatter verification:
  ```bash
  ./setup --verify
  ```
- [ ] Run full automated test suite:
  ```bash
  bash test/test_cli.sh
  ```
- [ ] All new shell scripts have `chmod +x` executable permissions.
- [ ] If modifying a skill, YAML frontmatter contains `name` and `description`.
- [ ] If adding a recipe, it contains `stack.config.json`, `rules/floor.md`, and `rules/landmines.md`.
