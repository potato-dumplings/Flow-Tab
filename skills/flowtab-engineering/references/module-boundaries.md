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

## Placement Rules

- Move logic to `FlowTabCore` when it can be expressed without `AppKit`, `SwiftUI`, accessibility APIs, screen capture APIs, or test-only hooks.
- Keep application startup, dependency wiring, root composition, and app lifecycle concerns in `FlowTab/App`.
- Keep feature UI and feature-local interaction logic in `FlowTab/Features`.
- Keep runtime snapshots, logging services, workspace integration, and platform bridges in `FlowTab/Infrastructure`.
- Keep mock-only code, launch flags, and testing adapters in `FlowTab/TestingSupport`.

## Dependency Rules

- Let `FlowTab` depend on `FlowTabCore`, not the reverse.
- Do not add `AppKit`, `SwiftUI`, `ApplicationServices`, or `ScreenCaptureKit` dependencies to `FlowTabCore`.
- Do not place production business logic inside `TestingSupport`.
- Do not duplicate core algorithms in `FlowTab` when they belong in `FlowTabCore`.

## Organization Rules

- Keep test-only code, scaffolding, and temporary diagnostics out of production feature files.
- Split oversized files by responsibility instead of adding unrelated code to existing large entry or controller files.
- Apply explicit file-size guardrails. New source files should usually stay within 400 lines. Files between 400 and 800 lines must still have a clear single responsibility. Files over 800 lines are oversized and should be split instead of expanded.
- When touching an already oversized file, prefer extraction over accumulation. Do not keep adding unrelated responsibilities to entry, panel, controller, coordinator, bridge, or runtime files.
- When the same property, spacing value, or behavior configuration is used in more than two places, extract it into a shared constant instead of repeating literals. Example: shared edge spacing used by Home, Settings, and Logs.
- Place detailed project documentation under `docs/`. Keep repo root limited to repository entry documents such as `README*`, `AGENTS.md`, and top-level build or configuration files.
- Keep view code out of infrastructure files unless the code is truly a shared infrastructure-facing UI component and not feature UI.

## Architecture Heuristics

- If the code is deterministic and reusable across UI surfaces, prefer `FlowTabCore`.
- If the code exists to talk to the OS or the app runtime, prefer `Infrastructure`.
- If the code exists only to support tests, prefer `TestingSupport`.
- If the code exists to render or coordinate a concrete feature, prefer `Features`.

## Invalid Moves

- Adding a reverse dependency from `FlowTabCore` back to app code.
- Solving file placement problems by copying logic into multiple modules.
- Hiding test scaffolding inside production files for convenience.
- Fixing a boundary problem with an exception instead of refactoring the abstraction.
