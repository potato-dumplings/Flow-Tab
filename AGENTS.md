# FlowTabApp Project Instructions

## Local Skill

- Use the project-local skill `flowtab-engineering` at `skills/flowtab-engineering/SKILL.md` for any feature work, bug fix, refactor, test-coverage decision, logging-placement decision, or module-boundary decision in this repository.
- Use the project-local skill `flowtab-direct-delivery` at `skills/flowtab-direct-delivery/SKILL.md` for implementation guidance, architecture proposals, change summaries, and remediation or handoff responses in this repository.
- Read the relevant reference file from that skill before editing:
  - `references/feature-workflow.md`
  - `references/bugfix-workflow.md`
  - `references/module-boundaries.md`
  - `references/risk-calibration.md`
  - `references/validation-command-cookbook.md`

## Core Rules

- Write clean code.
- Add comments only for complex or non-obvious logic, and explain why.
- Avoid trivial comments.
- Do not introduce single-feature or single-scenario special cases.
- Keep test-only code, temporary debugging hooks, and temporary bug-investigation logs out of production files.
- When the same property or behavior is needed in more than two places, extract it into a shared constant instead of repeating literals.
- Apply file-size guardrails. New source files should usually stay within 400 lines. Files between 400 and 800 lines must still have a clear single responsibility. Files over 800 lines are oversized and should be split instead of expanded. When touching an already oversized file, prefer extraction and do not keep growing it without also reducing or isolating responsibilities.
- Place detailed project documentation under `docs/`. Keep repo root limited to entry documents such as `README*`, `AGENTS.md`, and top-level build or config files.
- Respect module boundaries across `FlowTabCore`, `FlowTab`, `FlowTab/TestingSupport`, and the test targets.

## Validation Rules

- For every user-visible feature extension or new feature, add or update unit, behavior, and UI tests unless `risk-calibration.md` makes a layer explicitly not relevant.
- Do not consider feature work complete until the required related unit, behavior, and UI tests pass. If a required layer is blocked, report the blocker instead of calling the work complete.
- For every bug fix, reproduce and diagnose the issue with stable tests, logs, crash output, compiler or static analyzer output, deterministic configuration or permission evidence, or another concrete signal before changing production logic.
- Keep regression coverage after every bug fix.
