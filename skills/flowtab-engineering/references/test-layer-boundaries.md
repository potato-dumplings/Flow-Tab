# Test Layer Boundaries

Use this reference when deciding whether a scenario belongs in unit, behavior, or UI coverage.

These labels describe coverage layers, not a one-to-one naming scheme for Xcode targets. Pick the layer based on what evidence the test provides, then place it in the target that can express that evidence cleanly.

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

Current repo examples:

- `FlowTabCore/Tests/FlowTabCoreTests/GroupingTests.swift`
- `FlowTabCore/Tests/FlowTabCoreTests/PreferencesTests.swift`
- `FlowTabCore/Tests/FlowTabCoreTests/SwitcherSessionTests.swift`

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

Current repo examples:

- `FlowTabTests/FlowTabPriorityCoverageTests+PanelSessionBehavior.swift`
- `FlowTabTests/FlowTabPriorityCoverageTests+AppDelegateLifecycle.swift`
- `FlowTabTests/FlowTabTests+RuntimeInteraction.swift`

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

Current repo examples:

- `FlowTabUITests/FlowTabUITests+HomeAndLogs.swift`
- `FlowTabUITests/FlowTabUITests+Settings.swift`
- `FlowTabUITests/FlowTabUITests+SwitcherAndSearch.swift`
- `FlowTabUITests/FlowTabUITests+SpaceFixtureWorkflow.swift`

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

## Quick Selection Rules

1. If the scenario can be expressed as pure data, deterministic state, or reusable rule validation, write a unit test.
2. If the scenario needs app objects, notifications, persistence, runtime adapters, or controller coordination but can stay in-process, write a behavior test.
3. If the scenario must prove a visible route, an accessibility-facing result, or a real external-window workflow, write a UI test.
4. If more than one answer is true, place the shared rule at the lowest layer and keep higher layers thinner.

## Standard Product Scenarios

### 1. Three Apps in One Space, Search in the Panel, Activate the Target Window

Use this as the baseline product scenario for search coverage.

- User path: `Finder`, `Chrome`, and `Notes` are all running in the current desktop space. The user opens the switcher panel, searches for `doc`, selects the `Chrome` window titled `Docs`, and activates it.
- Unit coverage owns the search rule itself: query normalization, tokenization, app versus window scope matching, result ordering, and mapping the selected result back to the target app or window ID.
- Behavior coverage owns the in-process search flow: snapshot input enters `LiveSwitcherModel`, search mode rebuilds the index, search state updates, and applying the selected result moves the session to the correct target.
- UI coverage owns the user-visible journey: the panel shows the expected result, the user can select it, and focus actually switches to the `Docs` window.
- Example unit assertion: with three app entries already present, query `doc` ranks `Chrome / Docs` first in window scope and returns a stable window result ID.
- Example behavior assertion: after `enterSearchMode`, synchronizing query `doc`, and applying the selected result, the session selects `chrome-docs-window`.
- Example UI assertion: with three real fixture apps launched in one space, typing `doc` in the panel highlights `Docs`, and confirming the result brings the `Docs` window to the front.

### 2. Three Apps Across Spaces, Search in the Panel, Cross-Space Activate the Target

Use this when the product risk includes fullscreen windows, space transitions, or off-space targets.

- User path: `Finder` stays in the current desktop space, `Chrome` has a fullscreen window in another space, and `Notes` is in a third space. The user opens the switcher panel from the current space, searches for `mail`, selects the `Chrome` target, and FlowTab activates that window across spaces.
- Unit coverage owns the deterministic target resolution: given snapshot data that already contains off-space or fullscreen windows, search returns the correct candidate and selection resolves to the expected activation target.
- Behavior coverage owns the runtime orchestration: runtime snapshot data becomes searchable candidates, the selected result produces the right activation request, and any relevant active-space handling keeps or restores session state correctly.
- UI coverage owns the real system proof: the external app topology actually exists, the panel can surface the off-space result, and confirming it really switches the user into the target space and window.
- Example unit assertion: when `Chrome / Mail` exists in the window entries, query `mail` produces a `.window(appID: "chrome", windowID: "mail-window")` result.
- Example behavior assertion: applying the selected `Mail` result produces `RuntimeActivator` target `.window(appID: "chrome", windowID: "mail-window", ...)`.
- Example UI assertion: with three fixture apps distributed across spaces and one fullscreen window, confirming the `Mail` result from the panel changes spaces and makes the target window frontmost.

### 3. Three Apps Running, App-Managed Tab Titles Participate in Search

Use this when the product behavior depends on real window-title semantics rather than only bundle or app names.

- User path: `Chrome`, `Safari`, and `Notes` are running. A `Chrome` window contains app-managed tabs such as `Docs` and `PR`, with `PR` currently selected. The user opens the switcher panel, searches for `pr`, and activates that `Chrome` window by its current tab title.
- Unit coverage owns the title and search semantics: selected-tab title normalization, searchable title generation, token matching, and ranking for tab-derived window labels.
- Behavior coverage owns the app-level propagation: workflow or runtime title data enters the snapshot, the search index is rebuilt from that title, and selecting the result updates the session to the correct window.
- UI coverage owns the visible outcome: the panel exposes the tab-derived title that the user expects, searching `pr` returns that visible label, and confirming it activates the correct window.
- Example unit assertion: a configured window with raw title `Chrome Window 1` and selected tab `PR` normalizes into a searchable window title `PR`.
- Example behavior assertion: after snapshot ingestion and query `pr`, the first search result has primary text `PR` and points to the expected `Chrome` window ID.
- Example UI assertion: with a real fixture workflow that renders tab-backed titles, typing `pr` in the panel shows `PR` as the result label and activates the correct `Chrome` window after confirmation.
