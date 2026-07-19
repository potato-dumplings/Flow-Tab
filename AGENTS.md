# FlowTabApp Project Instructions

## Local Skill

- Use the project-local skill `flowtab-engineering` at `.agents/skills/flowtab-engineering/SKILL.md` for feature work, bug fixes, refactors, test-coverage decisions, logging-placement decisions, module-boundary decisions, implementation guidance, architecture proposals, change summaries, remediation, and handoff responses in this repository.
- Use the project-local skill `flowtab-test-audit` at `.agents/skills/flowtab-test-audit/SKILL.md` together with `flowtab-engineering` for repository-wide test-asset baselines, dependency-slice audits, full closure and audit recovery.
- For test-audit work, follow the stage routing in `.agents/skills/flowtab-test-audit/SKILL.md`, load only the selected stage reference and treat historical prompt archives as design inputs.
- For `flowtab-engineering` work, read the relevant reference file before editing:
  - `references/feature-workflow.md`
  - `references/bugfix-workflow.md`
  - `references/module-boundaries.md`
  - `references/risk-calibration.md`
  - `references/validation-command-cookbook.md`
  - `references/flowtabtests-workflow.md`

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
- For documentation, Skill, prompt, or other no-runtime-behavior changes, report Unit, Behavior, UI, and Pressure as `not relevant` with the scoped reason, and run the applicable Process/Tooling validation.
- Run `FlowTabTests` only through `.agents/skills/flowtab-engineering/references/flowtabtests-workflow.md`. Do not add signing bypasses or alternate app-test commands to get past certificate failures; report the missing or invalid local signing setup as the blocker.
