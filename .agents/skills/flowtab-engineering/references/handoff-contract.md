# FlowTab Handoff Contract

Use this reference when the response closes or transfers implementation, review, diagnosis, architecture, remediation, or change-delivery work in FlowTab.

## Universal Contract

- Lead with the conclusion, completed work, or actionable recommendation.
- State material assumptions, unresolved uncertainty, affected files or modules, and ownership boundaries.
- Name rollback, fallback, or failure handling when it materially affects delivery risk.
- Report the result of the applicable engineering workflow; keep workflow policy in its owning reference.
- Include optional next actions only after the current deliverable is complete.

## Validation Status

Report runtime layers separately:

- Unit: `passed`, `failed`, `blocked`, `not relevant`, or `not run`.
- Behavior: `passed`, `failed`, `blocked`, `not relevant`, or `not run`.
- UI: `passed`, `failed`, `blocked`, `not relevant`, or `not run`.
- Pressure: `passed`, `failed`, `blocked`, `not relevant`, or `not run`.

Give a reason for `blocked`, `not relevant`, and `not run`. Add a separate Process/Tooling section for skill checks, path resolution, protocol contracts, wrapper interfaces, package validation, or other non-runtime proof.

Audit artifacts must use the exact machine enum and typed result supplied by the active protocol Registry. Translate that result into the human-facing status above only in the final handoff.

## Full Handoff

Use the full handoff for user-visible features, production bugfixes, architecture or migration work, permissions, runtime topology, hot paths, and any task with blocked required validation.

### Bugfix

- Pre-change failing signal.
- Independent regression Oracle and any contamination/background used only to recreate the failure.
- Evidence supporting the root cause.
- Production change and affected ownership boundary.
- Pre-change and post-change validation by runtime layer.
- Required layer or pressure work that remains blocked or unproven.
- Stable coverage-contract or audit-projection publication performed by the applicable workflow.

### Feature

- User-visible behavior and shared rule.
- Owning module and dependency direction.
- Representative scenario family and selected minimum test set.
- Unique evidence supplied by each required runtime layer.
- Known gaps, blockers, and pressure status.
- Stable coverage-contract or audit-projection publication performed by the applicable workflow.

### Architecture Or Migration

- Target design and material assumptions.
- Ownership and dependency direction.
- Migration stages and exact affected boundaries.
- Fallback or rollback boundary.
- Runtime and process/tooling validation plan.

### Review Or Diagnosis

- Finding or observed gap.
- Supporting evidence and impact.
- Affected ownership boundary and product scenario when relevant.
- Smallest corrective action, remaining uncertainty, or blocker.

### Remediation

- Current blocker and owning layer or environment.
- Facts already proven and facts still unproven.
- Minimum recovery action.
- Validation that resumes after recovery.

## Compact Handoff

Use the compact handoff for documentation-only, skill-only, mechanical, or other changes with no runtime behavior impact:

- State what changed and where.
- State the runtime layers as `not relevant` with the scoped reason.
- Report required Process/Tooling validation and its results.
- State any process command that was attempted but blocked.
