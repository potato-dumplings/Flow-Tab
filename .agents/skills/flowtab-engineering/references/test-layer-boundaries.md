# Test Layer Boundaries

Use this reference when deciding whether a scenario belongs in unit, behavior, or UI coverage.

These labels describe coverage layers, not a one-to-one naming scheme for Xcode targets. Pick the layer based on what evidence the test provides, then place it in the target that can express that evidence cleanly.

## Contents

- [Layer Model Versus Test Targets](#layer-model-versus-test-targets)
- [Unit Tests](#unit-tests)
- [Behavior Tests](#behavior-tests)
- [UI Tests](#ui-tests)
- [Cross-Layer Rules](#cross-layer-rules)
- [Test Oracle Integrity](#test-oracle-integrity)
- [Scenario Fan-Out](#scenario-fan-out)
- [Quick Selection Rules](#quick-selection-rules)

## Layer Model Versus Test Targets

- `FlowTabCore/Tests/FlowTabCoreTests` is the default home for pure `FlowTabCore` unit tests.
- `FlowTabTests` can hold both app-scoped unit tests and behavior tests.
- `FlowTabUITests` holds XCUI-driven UI coverage, including real fixture-app workflows.
- The target name does not change the layer responsibility. A deterministic test inside `FlowTabTests` is still a unit test, and a fixture-driven case inside `FlowTabUITests` is still UI coverage.

## Unit Tests

Unit tests answer: "Is the shared rule correct?"

They are responsible for:

- Pure input/output logic.
- Deterministic state transitions and state machines.
- Normalization, grouping, ranking, filtering, and selection rules.
- Session rules, preference mapping, and reusable helpers.
- App-specific deterministic logic that cannot move to `FlowTabCore` yet but still does not need app runtime or XCUI.

They are not responsible for:

- Proving that a user can see or trigger the behavior in the UI.
- Verifying window or panel presentation, navigation, focus, or accessibility identifiers.
- Exercising real app launch, permission prompts, XCUI interaction, or cross-process coordination.
- Re-checking the same end-to-end journey that a behavior or UI test already owns.

Signals that a test is unit-level:

- It does not need `XCUIApplication`.
- It can avoid app launch, external fixtures, and long async waiting.
- Assertions focus on returned values, derived state, or deterministic side effects.

## Behavior Tests

Behavior tests answer: "Is the app wiring and orchestration using the rule correctly in-process?"

They are responsible for:

- App-level coordination across models, controllers, stores, services, and runtime adapters.
- Launch arguments, persistence, notification handling, logging behavior, permissions interpretation, and hotkey lifecycle.
- In-process integration seams that stay stable with overrides, fakes, or test doubles.
- Feature flows where the important assertion is orchestration or state propagation rather than visible UI rendering.

They are not responsible for:

- Exhaustively covering pure rule permutations that already belong in unit tests.
- Proving the final user-visible route through real XCUI interaction when a UI assertion is what matters.
- Pixel layout, tab selection visuals, button hittability, or other UI-surface details.

Signals that a test is behavior-level:

- It usually lives in `FlowTabTests`.
- It may instantiate `AppKit` or feature coordinators, but it stays in-process.
- It often uses overrides, fakes, seeded stores, or notifications instead of clicks in a live UI.
- Assertions focus on orchestration, state handoff, persistence, logging output, or integration decisions.

## UI Tests

UI tests answer: "Can the user observe and complete the intended path?"

They are responsible for:

- User-visible navigation and interaction flows.
- Screen-level assertions such as visible content, control routing, focus, and accessibility-identified outcomes.
- Search entry, selection, settings changes, logs interactions, permission reminders, and other journeys whose success must be proven from the outside.
- Real fixture-app workflows when the evidence depends on external windows, spaces, fullscreen state, or other cross-process topology.

They are not responsible for:

- Repeating every rule permutation already covered below the UI layer.
- Owning every internal branch or persistence detail that a behavior test can prove more cheaply.
- Acting as the only regression layer for shared logic that should be stable in unit or behavior tests.

Signals that a test is UI-level:

- It uses `XCUIApplication`, XCUI queries, or real fixture apps.
- Assertions are phrased in terms of what the user can see, tap, type, or trigger.
- It may need launch arguments or `FlowTabSpaceFixture`, but its pass condition is still user-visible behavior.

## Cross-Layer Rules

- Each required layer must contribute unique evidence.
- Unit tests should own the shared rule.
- Behavior tests should own in-process orchestration and integration.
- UI tests should own the visible user path.
- Do not copy the same branch-by-branch assertion into all three layers.
- When a feature introduces a new rule, prove the rule once at unit level, prove the flow once at behavior level, and prove the critical user journey once at UI level.
- When a bug is user-visible, keep or add a higher-layer regression after reproducing the lowest practical failing signal.
- If a feature seems impossible to cover at unit level, first look for the deterministic rule or data transformation that should be extracted. Do not skip the layer just because the current design hides the seam.
- `FlowTab/TestingSupport` only provides scaffolding. Tests that use it are still unit, behavior, or UI depending on the evidence they produce.
- `FlowTabSpaceFixture` extends UI evidence for real window topology. It does not replace the normal unit and behavior chain.

## Test Oracle Integrity

Before adding or recommending a test, identify the oracle first: the product contract, business rule, official API result, stable fixture state, explicit input, or independent specification that defines the expected result.

Assertions must compare the process and result against that oracle. Do not derive expected values from the bug's old implementation path, the proposed fix, a legacy storage field, a stale cache, or a value inserted only to trigger the failure.

Regression tests may include stale data, legacy fields, cached entries, incorrect configuration, or other contamination when they model a real failure environment. Label those values as contamination or background; they must not define the expected result.

Bad:

- Because the old price calculator read `legacyDiscountPercent`, set it to `50` and assert the final price is not the 50% discounted price.

Better:

- Given an order total of `200` and the rule "subtract 20 when total is at least 100", assert the payable amount is `180`.
- If `legacyDiscountPercent = 50` is included, treat it only as contamination. The expected value still comes from the order total and coupon rule.

## Scenario Fan-Out

The scenario named by the user, a bug report, or a failing test is the seed scenario. Before selecting tests, expand it across the product axes that could change the outcome:

- State variants: empty, single, multiple, selected, unselected, enabled, disabled, default, customized, stale, or missing data.
- Input variants: exact, partial, case-changed, normalized, ambiguous, duplicate, invalid, or boundary-value input.
- Runtime topology: current app, other app, current space, off-space, fullscreen, minimized, hidden, duplicate titles, missing windows, or fixture-backed real windows.
- Lifecycle and persistence: first launch, relaunch, preference reload, runtime refresh, delayed update, interrupted flow, or restored session.
- Permission and fallback paths: Accessibility denied, screen recording denied, unsupported runtime data, private bridge fallback, unavailable fixture, or degraded-but-safe output.
- Scale and pressure: many apps, many windows, repeated switching, repeated search edits, long-lived observers, cache churn, or preview-heavy rendering.

Do not turn every axis into UI automation. Use the cheapest responsible layer for breadth:

- Unit tests should cover the rule matrix and edge variants that can be expressed as data.
- Behavior tests should cover representative orchestration, persistence, runtime adapter, and lifecycle variants.
- UI tests should cover the critical visible journey and real-topology proof that lower layers cannot prove.
- Pressure checks should cover sustained load or scale-sensitive variants when the changed path can regress under repetition.

After fan-out, produce a concise scenario plan before editing test files:

- Required: the smallest scenarios needed to satisfy the relevant layers from `risk-calibration.md`.
- Optional: useful variants that are not included by default because they duplicate evidence, are expensive, or are lower risk.
- Not adding: variants intentionally left out, with the reason they do not change the current risk judgment.

Add the selected set autonomously when it remains inside the authorized product scope. New test files, new test methods in existing files and other additive test declarations do not require clarification. When evidence shows that an existing test function or existing file-scope test semantics must change, use the project-local test-semantic guard, state the exact conflict and ask the smallest product-semantics question needed to proceed. Treat a product-scope expansion as normal requirement clarification through the owning workflow.

When a relevant variant is intentionally not automated or is blocked, record it in the task validation plan or active Campaign through the owning workflow. A single happy path is enough only when the fan-out shows the remaining axes are genuinely not relevant to the changed behavior.

## Quick Selection Rules

1. If the scenario can be expressed as pure data, deterministic state, or reusable rule validation, write a unit test.
2. If the scenario needs app objects, notifications, persistence, runtime adapters, or controller coordination but can stay in-process, write a behavior test.
3. If the scenario must prove a visible route, an accessibility-facing result, or a real external-window workflow, write a UI test.
4. If more than one answer is true, place the shared rule at the lowest layer and keep higher layers thinner.
