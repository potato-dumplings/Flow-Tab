# Engineering Specialty Rules

Use this reference when a change touches concurrency, permissions, logging, dependencies, or runtime ownership. These rules complement `module-boundaries.md`; they do not replace the feature or bugfix workflow.

## Concurrency And Lifetime

- Keep AppKit, SwiftUI, window, panel, and observable UI state mutations on the main actor.
- Own long-lived `Task`, timer, observer, notification, and polling lifetimes from the object that starts them.
- Cancel repeated async work when the owning session, panel, app lifecycle object, or view model ends.
- Avoid detached tasks unless the work is intentionally independent from UI/session lifetime and has explicit cancellation or completion handling.
- Treat task lifetime, observer lifetime, and polling cadence changes as pressure-sensitive when they can repeat during search, panel presentation, tab switching, runtime snapshotting, or preview generation.

## Permissions And Code Identity

- Keep permission interpretation in app/runtime infrastructure or behavior tests; do not hide it in UI-only code.
- Use `ui-automation-prerequisites.md` before diagnosing Accessibility or Screen & System Audio Recording failures.
- Do not add production branches that exist only to satisfy UI tests. Put launch-time test hooks and overrides in `FlowTab/TestingSupport`.
- When fixed-path UI automation behaves differently from normal app launch, check bundle path and code identity before changing production permission logic.

## Runtime Activation Boundaries

- For full-screen, cross-Space, Chrome-like noisy, or otherwise ambiguous window activation, FlowTab must keep its own target-window evidence: title, CGWindowID, frame, Space evidence, CG/AX reconciliation, activation route, and post-attempt verification that the selected CGWindowID becomes onscreen.
- Do not use direct Space switching as a product fix, test pass condition, fixture workaround, or architecture proposal. This includes `ManagedDisplaySetCurrentSpace`, managed display Spaces APIs, `CopyManagedDisplaySpaces`, and other private routes that set the current Space instead of activating the selected window.
- Do not use an app's Window menu or tab/window menu selection as a product fix, test pass condition, fixture workaround, or architecture proposal. Menu routing is app-specific and does not prove FlowTab can identify and activate the concrete user-selected window.
- If a change touches activation or runtime topology, reject designs whose success signal is only "app became frontmost", "Space changed", or "menu item was selected"; the success signal must remain the selected window's concrete activation evidence.

## Logging

- Prefer existing stable logs and observability points before adding new logging.
- Temporary diagnosis logs must be removed from production files before handoff.
- Reusable production logging belongs in infrastructure or a dedicated logging helper, not scattered across feature UI.
- Log enough context to diagnose permissions, runtime topology, activation, and search state transitions, but avoid logging high-frequency per-item details unless gated or sampled.

## Dependencies

- Do not add external dependencies without a clear ownership boundary and validation plan.
- Keep `FlowTabCore` free of AppKit, SwiftUI, ApplicationServices, ScreenCaptureKit, and test-only dependencies.
- Prefer local helpers already present in the owning module over introducing a new abstraction.
- When dependency direction is unclear, classify the code by responsibility first, then verify that dependency direction still points from app to core.
