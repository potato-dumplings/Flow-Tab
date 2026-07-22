# Risk Calibration

Use this reference before deciding how much process, coverage, and reporting a FlowTab change needs. The goal is to keep the repository strict where behavior can regress, while avoiding heavyweight ceremony for changes that do not touch runtime behavior.

## Contents

- [Required Outcome](#required-outcome)
- [Risk Classes](#risk-classes)
- [Layer Not-Relevant Rules](#layer-not-relevant-rules)
- [Process And Tooling Validation](#process-and-tooling-validation)
- [Fast Decision Table](#fast-decision-table)

## Required Outcome

- Classify the change by user-visible and runtime risk before choosing validation.
- Keep unit, behavior, UI, and pressure validation mandatory when the change can affect those layers.
- Mark a layer `not relevant` only with a concrete reason tied to the change scope.
- Do not use risk calibration to skip tests because they are slow, flaky, or inconvenient. Use blocker reporting for that.

## Risk Classes

### Documentation Or Skill-Only

Use this class for changes limited to `docs/`, `README*`, `AGENTS.md`, `.agents/skills/`, comments, or explanatory text that does not alter source, build settings, runtime scripts, fixtures, launch arguments, or runtime configuration.

Minimum validation:

- Inspect the edited files.
- Check links, referenced paths, metadata, and applicable process contracts.
- Run the relevant Process/Tooling validation for Skill, prompt, command, package, or protocol changes.

Reporting:

- Runtime validation: unit, behavior, UI, and pressure are `not relevant: documentation, Skill, or prompt-only change`.
- Process/Tooling validation: report every required structural, path, protocol, command-interface, package, or eval check and its result.

### Mechanical Refactor Or File Movement

Use this class when behavior should not change, but source files, module placement, names, access control, or dependencies change.

Minimum validation:

- Run the smallest build or test target that proves the moved code still compiles in its new boundary.
- Run directly affected unit or behavior tests when logic is recompiled or dependencies changed.
- Run UI tests only if user-visible UI, accessibility identifiers, launch behavior, permissions, or real app workflow wiring changed.
- Run pressure validation only if the refactor touches a pressure-sensitive path from `performance-pressure-workflow.md`.

Reporting:

- State why behavior is expected to be unchanged and which compile/test command proved the boundary.

### User-Visible Feature Or Feature Extension

Use this class when users can observe new behavior, a changed interaction path, changed settings behavior, changed runtime output, or changed panel/home/logs/switcher behavior.

Minimum validation:

- Unit coverage when a deterministic rule, state transition or normalization changes.
- Behavior coverage when app orchestration, persistence, permissions, runtime adaptation or integration changes.
- UI coverage for the visible user path.
- Pressure validation when `performance-pressure-workflow.md` triggers.

Reporting:

- State the visible behavior, the shared rule, where it lives, and what unique evidence each layer provides.

### Bugfix Or Regression

Use this class for broken behavior, regressions, flakes, crashes, permission failures, compile failures, and user-reported defects.

Minimum validation:

- Establish a pre-change failing signal from tests, logs, crash output, compiler or static analyzer output, deterministic configuration mismatch, permission/code-identity evidence, or another stable observation.
- Add or keep regression coverage at the lowest layer that can express the failure.
- Add higher-layer coverage when the failure was user-visible or crossed app/runtime boundaries.
- Run pressure validation when the defect or fix touches a hot or scale-sensitive path.

Reporting:

- State the pre-change signal, supporting evidence, production change, post-change validation by layer, and any blocked layer with the reason.

### Hot Path Or Scale-Sensitive Change

Use this class in addition to the above when the change touches repeated input, search, panel refresh, runtime sampling, caches, observers, timers, async task lifetimes, preview generation, or heavy UI shown repeatedly.

Minimum validation:

- Run the matching pressure scenario from `performance-pressure-workflow.md`.
- Compare against the nearest same-machine baseline when available.
- If no baseline exists, record the run as the new local baseline and say that it is not a regression comparison.

## Layer Not-Relevant Rules

A test layer can be marked `not relevant` only when the reason is specific:

- Unit is not relevant when no deterministic rule, state transition, normalization, or pure logic changed.
- Behavior is not relevant when no app orchestration, persistence, launch, permission, runtime adapter, logging, or in-process integration changed.
- UI is not relevant when no visible UI, accessibility-facing result, user journey, fixture workflow, launch path, or permission prompt changed.
- Pressure is not relevant when the change does not touch hot paths, scale-sensitive costs, repeated async work, long-lived resources, or heavy repeated UI.

Do not mark a layer not relevant merely because the current code lacks a seam. For feature work, a missing unit seam is usually a design signal; either extract the deterministic rule or state why the behavior truly has no rule-level surface.

## Process And Tooling Validation

Process/Tooling is a reporting dimension alongside the runtime layers. It is required when a change affects engineering instructions, repository paths, build or test command documentation, wrappers, instruction contracts, Skill metadata, bundled resources, packaging, or audit Skill inputs.

Choose the checks owned by the changed boundary:

- Skill structure: frontmatter, description length, folder/name agreement, `agents/openai.yaml`, direct reference links, bundled resources and generated Schema freshness.
- Repository integration: AGENTS and Skill entry paths, path-intent resolution, stale-path scans, and referenced file existence.
- Command contracts: syntax, `--help`, wrapper argument ownership, and project-local build/evidence roots.
- Audit Skill inputs: active stage references, handoff paths, artifact paths and command interfaces.
- Delivery hygiene: `git diff --check` and review of the final changed-file set.

Report Process/Tooling as `passed`, `failed`, `blocked`, or `not run`, with the command or concrete reason. A runtime layer marked `not relevant` does not reduce the required Process/Tooling checks.

## Fast Decision Table

| Change type | Unit | Behavior | UI | Pressure | Process/Tooling |
| --- | --- | --- | --- | --- | --- |
| Docs, Skill, or prompt text only | Not relevant | Not relevant | Not relevant | Not relevant | Required |
| Pure `FlowTabCore` rule | Required | As needed for app wiring | Not relevant unless visible path changed | If scale-sensitive | As changed |
| App orchestration change | As needed for rules | Required | If user-visible | If hot path | As changed |
| Visible panel/home/logs/settings change | Required when a rule exists | Required when wiring changes | Required | If repeated or heavy | As changed |
| Bugfix with user-visible impact | Lowest failing layer | Required if orchestration is involved | Required for the visible regression; report blocked when its evidence path is unavailable | If hot path | As changed |
| Permission, signing, or fixture workflow | As needed for helpers | Required for interpretation/wiring | Required when user-facing or cross-process | Usually not relevant unless repeated workflow cost changed | Required |
