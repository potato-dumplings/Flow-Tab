---
name: flowtab-direct-delivery
description: "Direct answer and implementation handoff rules for FlowTab tasks. Use when writing implementation guidance, architecture proposals, bugfix explanations, change summaries, or remediation plans in this repository. Require concrete steps, affected modules or files, validation, rollback or failure handling when relevant, and avoid placeholder offers such as 'if you want, I can...'."
---

# FlowTab Direct Delivery

Apply this skill when explaining how to implement, change, fix, or summarize work in FlowTab. The answer should deliver the usable content first instead of offering to provide it later.

## Required Response Contract

1. Deliver substance before invitation.
   Give the recommendation, implementation path, and key details before offering optional follow-up help.

2. Do not replace the answer with a placeholder offer.
   Avoid lines that only say the next step could be provided later, such as "if you want, I can give a concrete plan" or "I can add implementation details next." These are only acceptable after the concrete answer is already present.

3. Make implementation guidance concrete.
   Only explain the implementation approach and execution order. First state how the change should be implemented, then state the sequence for carrying it out.

4. Prefer direct recommendations over meta commentary.
   If one path is clearly best, recommend it directly instead of narrating that a plan could be created.

5. Keep optional next steps genuinely optional.
   Offer follow-up actions only after the answer is complete, and only when there are multiple meaningful directions the user may want.

## Response Patterns

- For architecture or migration proposals, state the target design, migration stages, fallback path, and validation plan.
- For bugfix explanations, state the failing signal, root cause, production change, regression coverage, and any remaining risk.
- For implementation guidance, state where the code should live, what the API or data flow should look like, and how success should be verified.
- For change summaries or handoffs, state what changed, why it changed, where it changed, and how it was validated.

## Bad and Better

- Bad: "If you want, I can next provide a concrete no-private-API plan."
- Better: "Implement the no-private-API migration in three stages: first isolate the private calls behind one adapter, then replace each capability with a public-path strategy, then remove the adapter after regression coverage passes."
