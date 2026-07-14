# Module Boundaries

Use this reference when deciding where code should live or when a change feels like it crosses layers.

## Boundary Summary

- `FlowTabCore`
  Hold pure models, grouping logic, session state, preference normalization, and other reusable logic that can stay free of app-framework and OS-integration dependencies.
- `FlowTab`
  Hold app entry, UI composition, feature orchestration, runtime integration, and platform-facing behavior.
- `FlowTab/Features`
  Hold feature-specific user-facing behavior and feature-local coordination.
- `FlowTab/Infrastructure`
  Hold OS integration, runtime bridges, logging infrastructure, and shared platform-facing services.
- `FlowTab/TestingSupport`
  Hold test bootstrap, mock injection, visibility helpers, and other testing-only support.
- Test targets
  Hold test code only. Do not move test logic back into production modules.

## Current Ownership Map

- `FlowTab/App`
  App entry, `AppDelegate`, dependency wiring, app lifecycle, root windows, top-level launch behavior.
- `FlowTab/Features/Home`
  Home page UI, app/window lists, user-facing home interactions, home-specific coordination.
- `FlowTab/Features/Logs`
  Logs page UI, log presentation, log clearing UI behavior, logs-specific state.
- `FlowTab/Features/Settings`
  Settings UI, preference controls, permission reminders surfaced through settings.
- `FlowTab/Features/Switcher`
  Switcher panel UI, panel controller, presentation behavior, search interaction routing, selection and activation UI flow.
- `FlowTab/Features/SharedUI`
  Shared feature-facing UI components that are not tied to one page and do not own runtime integration.
- `FlowTab/Infrastructure/Runtime`
  Runtime snapshots, window/app discovery, activation, accessibility and screen-capture integration, topology and preview providers.
- `FlowTab/Infrastructure/Preferences`
  App preference storage, preference adapters, app-scoped preference infrastructure.
- `FlowTab/Infrastructure/Appearance`
  Shared appearance, colors, typography, and platform-facing styling helpers.
- `FlowTab/Infrastructure/Support`
  Cross-feature support helpers that are app-level or platform-facing, but not pure enough for `FlowTabCore`.
- `FlowTab/TestingSupport`
  Launch arguments, test-only dependency injection, mock visibility helpers, and fixtures used by tests.
- `FlowTabSpaceFixture`
  Fixture app behavior used to create real window and space topology for UI automation.

## Placement Rules

- Classify every production file by architecture role and feature ownership before choosing a directory.
- Let directories reflect architecture role and business module, not the history of which large file the code was extracted from.
- Move logic to `FlowTabCore` when it can be expressed without `AppKit`, `SwiftUI`, accessibility APIs, screen capture APIs, or test-only hooks.
- Keep application startup, dependency wiring, root composition, and app lifecycle concerns in `FlowTab/App`, and treat that directory as the app shell rather than a general landing zone for extracted files.
- Keep feature UI and feature-local interaction logic in `FlowTab/Features`.
- Keep runtime snapshots, logging services, workspace integration, and platform bridges in `FlowTab/Infrastructure`.
- Keep mock-only code, launch flags, and testing adapters in `FlowTab/TestingSupport`.

## Dependency Rules

- Let `FlowTab` depend on `FlowTabCore`, not the reverse.
- Do not add `AppKit`, `SwiftUI`, `ApplicationServices`, or `ScreenCaptureKit` dependencies to `FlowTabCore`.
- Do not place production business logic inside `TestingSupport`.
- Do not duplicate core algorithms in `FlowTab` when they belong in `FlowTabCore`.
- Use `engineering-specialty-rules.md` when placement depends on concurrency lifetime, permissions, logging, or dependency ownership.

## Organization Rules

- Keep test-only code, scaffolding, and temporary diagnostics out of production feature files.
- Split oversized files by responsibility instead of adding unrelated code to existing large entry or controller files.
- Apply explicit file-size guardrails. New source files should usually stay within 400 lines. Files between 400 and 800 lines must still have a clear single responsibility. Files over 800 lines are oversized and should be split instead of expanded.
- When touching an already oversized file, prefer extraction over accumulation. Do not keep adding unrelated responsibilities to entry, panel, controller, coordinator, bridge, or runtime files.
- When the same property, spacing value, or behavior configuration is used in more than two places, extract it into a shared constant instead of repeating literals. Example: shared edge spacing used by Home, Settings, and Logs.
- Place detailed project documentation under `docs/`. Keep repo root limited to repository entry documents such as `README*`, `AGENTS.md`, and top-level build or configuration files.
- Keep view code out of infrastructure files unless the code is truly a shared infrastructure-facing UI component and not feature UI.

## Architecture Heuristics

- Ask why the file exists before asking which framework it uses. Place it by primary responsibility, then verify the dependency direction still holds.
- If the code is deterministic and reusable across UI surfaces, prefer `FlowTabCore`.
- If the code exists to talk to the OS or the app runtime, prefer `Infrastructure`.
- If the code exists only to support tests, prefer `TestingSupport`.
- If the code exists to render or coordinate a concrete feature, prefer `Features`.

## Invalid Moves

- Adding a reverse dependency from `FlowTabCore` back to app code.
- Solving file placement problems by copying logic into multiple modules.
- Hiding test scaffolding inside production files for convenience.
- Fixing a boundary problem with an exception instead of refactoring the abstraction.
