# Evidence-Driven Synchronization Migration

Updated: 2026-07-30

## Goal

FlowTab must decide asynchronous completion, readiness, and success from observable
evidence. Machine speed, scheduler pressure, I/O latency, and animation load may
change completion latency, but must not change the functional result.

This ledger is the stable migration boundary. Each implementation slice owns one
synchronization contract and its representative production, test, fixture, or
tooling path. A slice updates its row and is committed independently with the
row ID in the commit subject.

## Repository Baseline

- Branch at audit start: `evidence-driven-sync-migration`
- Commit at audit start: `9668770830acdeaae87278502b3e04f66101a89b`
- Pre-existing worktree content: untracked `prompts.zip`
- Baseline ownership rule: `prompts.zip` remains unchanged and outside every
  migration commit.

## Audit Method

The baseline combined source search with call-path review across `FlowTab`,
`FlowTabCore`, `FlowTabSpaceFixture`, `FlowTabTests`, `FlowTabUITests`, and
repository validation/release scripts.

The initial search found:

- 37 direct `sleep`, `asyncAfter`, `Timer`, or `RunLoop` occurrences in
  production, TestingSupport, and the Space fixture.
- 13 direct sleep or RunLoop occurrences in `FlowTabTests`.
- 103 direct RunLoop occurrences in `FlowTabUITests`.
- 12 shell/JXA sleep or delay occurrences in scripts.
- 52 literal XCTest watchdog arguments in `FlowTabTests` and 554 in
  `FlowTabUITests`.
- No timing or waiting candidate in `FlowTabCore/Sources` or
  `FlowTabCore/Tests`.

The review also traced elapsed-time decisions that do not contain a wait call,
including AX scan budgets, observer warm-up/throttling, retry `notBefore`
values, input suppression windows, projection generations, process identity
stability, and expiration rules. Instrumentation timestamps and ordering
timestamps that never gate progress or success are outside this ledger.

## Classification And Status

Time classifications:

- **Evidence migration**: a fixed duration currently substitutes for completion,
  readiness, or success evidence.
- **Conditional observation**: the platform exposes no usable callback or
  notification; an immediate predicate/readback check, named cancellable
  cadence, and diagnostic watchdog are allowed.
- **Domain duration**: elapsed time is the product, fixture, animation,
  expiration, batching, or pressure protocol.
- **Watchdog**: time supplies only the terminal failure bound; success comes
  from an independent Oracle.

Statuses:

- `planned`: implementation or test migration remains.
- `verification-needed`: the time classification is allowed, but ownership,
  cancellation, naming, diagnostics, or deterministic coverage remains.
- `closed-retained`: the existing policy is already evidence-driven and its
  duration is an allowed domain rule or watchdog.
- `completed`: the migration and required validation for the row passed.
- `blocked`: required validation is unavailable and the evidence is recorded in
  the row.

Risk uses `H` for user-visible, runtime-identity, long-lived observer/task, or
hot-path changes; `M` for app/test orchestration; and `L` for isolated tooling
or policy naming. Validation abbreviations are Unit, Behavior, UI, Pressure,
and Process/Tooling.

## Migration Ledger

| ID | File and owner/symbol | Current time assumption and classification | Target evidence or retained policy; lifecycle owner | Risk and required validation | Status |
| --- | --- | --- | --- | --- | --- |
| SYNC-000 | `docs/EVIDENCE_DRIVEN_SYNCHRONIZATION_MIGRATION.md`; migration ledger baseline | The repository previously had no stable, reviewable closure ledger for time-based synchronization contracts. Process contract. | Preserve the startup Git baseline, semantic classification, dependency order, per-slice validation, and local commit trace in this document. The migration task owns updates through final closure. | L; Process/Tooling (`git diff --check`, ID/path/source-scope review). | completed by the baseline commit |
| SYNC-001 | `FlowTab/Infrastructure/Runtime/RuntimeAXRemoteWindowResolver.swift`; `windowScanResult(forPID:policy:)` | An 80–250ms wall-clock budget accepts a machine-dependent partial element-ID scan as usable output. Evidence migration. | Scan a deterministic policy-owned ID range and publish complete/unavailable evidence. Any watchdog must fail the scan with last scanned ID and observed windows rather than promote a partial result. The resolver call owns cancellation/termination. | H; Unit, Behavior, affected topology UI, runtime-topology Pressure. | blocked: implementation and Unit/Behavior/Process passed; UI/Pressure environment evidence is recorded below |
| SYNC-002 | `AppDelegate.installWorkspaceLifecycleObserver`, `RuntimeAppLaunchWindowEvidenceCoordinator`, `RuntimeProjectionService.signalAppLaunched`; app-launch convergence | A fixed 800ms delay was assumed to be enough for a launched app's windows to exist. Evidence migration. | Establish the exact app/PID AX observer before launch handling, use the launch repair as initial readback, and reconcile later AX transitions or a successful delayed observer installation. The AppDelegate-owned coordinator manages per-PID generation, exact appID/PID cancellation, monitor cleanup, and the named observer-install condition cadence. | H; Unit, Behavior, launch/topology UI, runtime-topology Pressure. | blocked: implementation and Unit/Behavior/Process passed; UI/Pressure environment evidence is recorded below |
| SYNC-003 | `RuntimeReconciliationCoordinator`, `RuntimeProjectionReconciliationDrainer`, `RuntimeProjectionService`, `RuntimeTransientRepairObservationDriver`; transient-empty repair observation | Delayed `notBefore` values `[0.1, 0.3, 0.8]` waited for AX data to become non-empty, while unrelated maintenance could advance the retry. Conditional observation. | Perform the repair readback immediately, resume from an exact AX/Space/lifecycle signal, and use a service-owned cancellable condition observer only while the payload remains incomplete. Request ID, attempt, and exact appID/PID reject stale evidence. The named `[0.1, 0.3, 0.8]` cadence repeats its last value; a 30-second watchdog terminates one uninterrupted incomplete-evidence session and reports the unmet condition plus last payload. | H; Unit, Behavior, topology UI, runtime-topology Pressure. | blocked: implementation and Unit/Behavior/Process passed; UI/Pressure environment evidence is recorded below |
| SYNC-004 | `FlowTab/Infrastructure/Runtime/RuntimeAXWindowChangeMonitor.swift`; observer install and `handleAXNotification` | Events during a 750ms warm-up are discarded and events inside a 160ms throttle window can lose the final state. Evidence migration. | Install observers, take an initial AX/window readback, and publish monotonically coalesced generations with a guaranteed trailing readback. The monitor owns observer removal; its delivery coordinator owns pending coalescing cancellation. | H; Unit, Behavior, Home/topology UI, runtime-topology Pressure. | completed |
| SYNC-005 | `FlowTab/Infrastructure/Runtime/RuntimeChromeWindowFocusBridge.swift`; `focusWindowScript` | Two fixed 50ms AppleScript delays are assumed to propagate Chrome window ordering before front-window readback. Conditional observation. | Issue the Chrome focus commands once and immediately return the exact front-window ID readback. Exact equality is the bridge acceptance Oracle; mismatch, empty/invalid output, and execution error remain explicit evidence for `RuntimeActivator`. SYNC-006 owns later activation convergence under one cancellable activation generation. | H; Unit, Behavior, exact-window UI, runtime-topology Pressure. | completed |
| SYNC-006 | `FlowTab/Infrastructure/Runtime/RuntimeActivator.swift`; `scheduleFocusRecovery` | Fixed 50ms/150ms retries probe whether the exact target became focused. Conditional observation. | Preserve exact AX/CG target readback as the sole success Oracle. Check immediately, consume usable focus/window notifications, and retain a named cancellable polling fallback plus diagnostic watchdog where macOS exposes no target-specific completion event. `RuntimeActivator` owns the task and activation generation. | H; Unit, Behavior, activation UI, runtime-topology Pressure. | completed |
| SYNC-007 | `FlowTab/Infrastructure/Runtime/RuntimeWindowPreviewProvider.swift`; ScreenCaptureKit callback bridges | One-second semaphore timeouts terminate callback waits; success already comes only from callback content. Watchdog. | Retain as a named bridge-watchdog policy. The synchronous bridge state owns late-callback rejection; tests must cover callback, error, timeout, and callback-after-timeout evidence. | M; Unit, Behavior, preview Pressure. | closed-retained |
| SYNC-008 | `FlowTab/Infrastructure/Runtime/RuntimeLogging.swift`; `scheduleFlushLocked` | A 50ms delay batches disk writes and does not establish write success. Domain duration. | Retain the named batching policy and cancellable `DispatchWorkItem`; explicit snapshot/read APIs flush synchronously before returning evidence. The diagnostics store owns the work item. | M; Unit, Behavior, log-write Pressure if changed. | closed-retained |
| SYNC-009 | `FlowTab/Features/Logs/RuntimeLogsSection.swift`; `RuntimeLogLinesViewModel` | The Logs surface polls once per second to discover appended or cleared lines. Evidence migration. | Publish append/flush/clear generations from the diagnostics owner, subscribe before the initial snapshot, and reload from the later generation. View-model start/stop owns the subscription and task. | M; Unit, Behavior, Logs UI, tab-switch Pressure. | completed |
| SYNC-010 | `RuntimeLogPrivacy.swift`, `RuntimeLogsSection`; diagnostic session expiration | The 15-minute session is an explicit expiration contract; the view advances a one-second loop to notice expiry. Domain duration. | Retain the expiration deadline, use the existing injected `now` readback for rules, and schedule one cancellable deadline wakeup through an injectable clock. Expiration succeeds only when clock readback reaches the stored deadline. | M; Unit, Behavior, Logs UI. | completed |
| SYNC-011 | `FlowTab/Features/Home/HomeLandingView.swift`, `HomePermissionObservationOwner`; Home permission observation | A perpetual one-second poll discovered TCC permission changes and treated each delayed wake as the opportunity to infer current state. Evidence migration plus conditional observation. | Use the shared permission coordinator from SYNC-012: install app-activation observation before immediate readbacks, publish only exact changed TCC evidence, and retain a named cancellable one-second fallback because TCC has no unified transition notification. Home active visibility owns start/stop and cache publication. | H; Unit, Behavior, Home permission UI, tab-switch Pressure. | completed |
| SYNC-012 | `FlowTab/Features/Settings/AppSettingsView.swift`; permission prompt observation | Forty 500ms attempts inferred post-prompt TCC convergence; the first condition check occurred after a sleep and cancellation was swallowed. Conditional observation plus watchdog. | Install the shared app-activation observer before an immediate readback, take an independent post-request readback, and use a named cancellable fallback cadence for TCC transitions without callbacks. The terminal watchdog reports target, generation, readbacks, elapsed time, bundle identity, and final evidence. Settings visibility owns both target observations. | H; Unit, Behavior, permission UI, tab-switch Pressure. | completed |
| SYNC-013 | `HomeLandingView.scheduleInitialAppSummariesRefresh`, `HomeInitialProjectionObservationOwner`; initial Home app-summary readiness | A fixed 900ms startup delay assumed the runtime app-switcher projection had committed before the Home readback. Evidence migration. | Install the exact service-object projection observer before the initial readback and maintenance request. Accept an initial complete projection, a later monotonic source generation, or a same-generation completeness transition. Home active visibility owns the observation generation, subscription, cancellation, and cleanup. | H; Unit, Behavior, Home UI, runtime-topology Pressure. | completed |
| SYNC-040 | `HomeLandingView.scheduleAppSummariesRefresh`, `HomeAppSummaryProjectionObservationOwner`; general Home app-summary refresh | A fixed 220ms post-signal delay assumed app-switcher projection commits had followed workspace and runtime refresh signals. Evidence migration. | Install the exact runtime-service observer before the baseline readback. Apply committed notification readbacks only for a newly available projection, a monotonic source generation, or same-generation completeness. App activation and permission changes request service-owned maintenance, followed by an independent request-return readback. Home active visibility owns the observation generation, subscription, cancellation, and initial-owner handoff. | H; Unit, Behavior, Home UI, runtime-topology Pressure. | completed |
| SYNC-041 | `HomeLandingView.requestSelectedAppRefresh`, `requestAppDetailProjection`, `HomeAppDetailProjectionObservationOwner`; selected/scoped Home detail | Fixed 120ms and 220ms post-selection or AX-signal delays assumed the requested current-app projection had committed. Evidence migration. | Install the exact runtime-service observer before the initial readback and selected/app-window/AX-destroy signal. Filter by exact appID and projection identity; apply an exact complete baseline immediately while retaining the trigger observation, then accept a newly available projection, monotonic source generation, or same-generation completeness transition. Independent request-return readback closes synchronous completion races. Home visibility and per-app request generations own subscriptions, cancellation, and stale-event rejection. | H; Unit, Behavior, selected-app Home UI, runtime-topology Pressure. | blocked: implementation, focused Unit/Behavior, full FlowTabTests, tab-switch Pressure, and Process passed; UI automation and full Priority order-isolation evidence are recorded below |
| SYNC-014 | `FlowTab/App/AppFoundation.swift`; `AppWindowCoordinator.scheduleAccessoryPolicyRestoration` | Up to 250 polls at 20ms infer that a status-item-opened regular window is active and visible. Conditional observation plus watchdog. | Register app/window observers before presentation, perform immediate visibility/activation readback, and complete on the matching window transition. A named cancellable condition observer is the fallback; watchdog diagnostics include app-active, visible, miniaturized, and activation-policy state. `AppWindowCoordinator` owns the task/observers. | H; Unit, Behavior, status-item UI. | completed; the expanded full Priority run's assigned SYNC-032/SYNC-033 order-isolation failure is recorded below |
| SYNC-015 | `SwitcherSearchCoordinator.scheduleRebuild`, `LiveSwitcherModel.scheduleSearchComputation` | 10–45ms delays debounce query work; result publication already requires revision and query/scope equality. Domain duration. | Retain as one named search scheduling policy with injectable scheduler/clock, cancellation, and revision Oracle. Remove duplicate scheduling ownership if both paths serve the same contract. | H hot path; Unit, Behavior, Search UI, realistic/stress Search Pressure. | completed; the expanded full Priority run's assigned SYNC-032/SYNC-033 order-isolation failure is recorded below |
| SYNC-016 | `AppDelegate.setupHotkeyMonitors`, `HotkeyRegistrationObservationOwner`, `HotkeySettingsCardAppKitView.updateTakeoverStatus`; Command+Tab registration status | A 250ms delay was treated as confirmation that Command+Tab takeover stayed inactive. Evidence migration. | Publish a monotonic registration generation with exact request ID, configurations, and takeover result after reconciliation and monitor setup. Settings observes before persistence/registration, closes synchronous delivery with readback, and renders only matching evidence. Settings active visibility owns observer cleanup and stale-generation rejection. | M; Unit, Behavior, Settings UI. | completed; the expanded full Priority run's assigned SYNC-032/SYNC-033 order-isolation failure is recorded below |
| SYNC-017 | `SwitcherPanelController+InputHandling.swift`, `ModifierReleaseObservationOwner`; modifier-release confirmation and replay suppression | Hardware release was inferred from repeated samples after fixed intervals. Conditional observation. | Install exact modifier/main-key transition observation before the initial hardware readback. Transition evidence triggers immediate readback; one named cancellable fallback sample closes missed-event and stale-readback gaps. Selection confirmation requires two stable released-state readbacks; SYNC-018 replay suppression closes from one exact released-state readback. The panel controller owns observation tokens, fallback work, and generation cancellation. | H; Unit, Behavior, switcher UI, interaction Pressure. | completed; the expanded full Priority run's assigned SYNC-032/SYNC-033 order-isolation failure is recorded below |
| SYNC-018 | `OptionTabHotkeyMonitor`, `AppDelegate.setupHotkeyMonitors`, `SwitcherHotkeyInputOwner`, `SwitcherPanelController+Hotkeys.swift`, `+SelectionLifecycle.swift`; tab throttle and post-finish ignore | 16ms and 20ms windows discard input assumed to be duplicate/replayed, so scheduling can change the selected result. Evidence migration. | Give each monitor a stable source UUID and monotonic sequence; register the exact route source and callback before explicitly starting Carbon observation. Accept each route/source/sequence identity once, reject duplicate, regressed, or replaced-source delivery, and preserve every distinct immediate event. Establish modifier/main-key observation before selection commit/end and close replay suppression only from an exact released-state readback. The controller owns input generations; AppDelegate owns monitor start/stop; the release owner owns observer/fallback cancellation. | H; Unit, Behavior, switcher UI, interaction Pressure. | completed; the expanded full Priority run's assigned SYNC-032/SYNC-033 order-isolation failure is recorded below |
| SYNC-019 | `InitialPanelVisibilityObservationOwner`, `SwitcherPanelController+InitialVisibilityRecovery.swift`; initial panel visibility | A grace duration decides whether occlusion is stale and later triggers failure. Evidence migration plus watchdog. | Install panel occlusion, become-key, and expose observers during controller initialization. Start the session observation before the first order-front action, and accept only an exact visible `PanelVisibilitySnapshot` from the initial readback, matching presentation action, window event, recovery readback, or terminal watchdog readback. The presentation session owns generation cancellation and one named watchdog that reports the last event and final snapshots. | H; Unit, Behavior, switcher UI, runtime-topology Pressure. | blocked: implementation, focused Unit/Behavior, deterministic Pressure, and Process passed; cross-slice pressure reproduced a 350ms watchdog cancellation at 372.550ms and full-suite panel-expose ordering failures; the latest SYNC-032D2 isolated and full reruns passed, while dedicated remediation remains required |
| SYNC-020 | `PanelVisibilityRecoveryObservationOwner`, `SwitcherPanelController+VisibilityRecovery.swift`; visibility recovery attempts and hard reorder | Fixed `[0, 50ms, 150ms, 300ms]` attempt waits and a fixed 10ms order-out/order-front gap assumed AppKit had committed window ordering. Evidence migration plus conditional observation. | Use the controller-lifetime occlusion/key/expose observers established by SYNC-019, an immediate exact readback, and an ordered state machine that must observe `panelPresented == false` before order-front and exact `userVisible == true` before success. The local AppKit SDK has no public order-on/off notification, so the presentation session owns one named cancellable 10ms condition-readback cadence, a four-attempt action policy, matching recovery/presentation generations, and a 1-second diagnostic watchdog. | H; Unit, Behavior, switcher UI, runtime-topology Pressure. | blocked: implementation and all-target Process build passed; the shared macOS XCTest service blocked Unit/Behavior/UI execution before test start, and runtime-topology launch identity remained unobserved |
| SYNC-021 | `ActiveSpaceTransitionObservationOwner`, `SwitcherPanelController+ActiveSpaceTransition.swift`; active-Space ignore and activation-suppression windows | 350ms/500ms windows assume which Space notifications belong to FlowTab's own presentation/migration. Evidence migration plus watchdog. | Establish the observation and exact runtime-service baseline before requesting topology refresh. Resolve only after the Space projection generation advances, then correlate current-Space identity, presentation generation, and exact panel visibility. Independent request-return and projection-notification readbacks close synchronous and missed-event races. The presentation session owns replacement, cancellation, activation suppression, and a one-second diagnostic watchdog. | H; Unit, Behavior, cross-Space UI, runtime-topology Pressure. | blocked: implementation, Unit/Behavior, deterministic Pressure, and Process passed; macOS LocalAuthentication blocked cross-Space UI and real-topology Pressure before test start |
| SYNC-022 | `TerminateInterruptionProtectionObservationOwner`, `SwitcherPanelController+TerminateInterruptionProtection.swift`, `+Hotkeys.swift`, `+InputHandling.swift`; terminate interruption protection | Five-second and 500ms uptime windows inferred that termination, projection refresh, and related AppKit presentation interruptions had finished. Evidence migration plus watchdog. | Establish an exact appID/PID/request-generation and projection baseline before sending the terminate request. Latch target completion only from matching workspace termination or terminated-process readback plus exact projection removal/replacement. Cancel the completion watchdog at that point, then retain an untimed presentation latch until active-Space, panel-visibility, or consumed interruption evidence is followed by a stable visible/active readback. The presentation session owns replacement and cancellation. | H; Unit, Behavior, termination UI, runtime-topology Pressure. | completed |
| SYNC-023 | `SwitcherPanelController+Hotkeys.swift`, `AppPreferences.swift`; delayed window-layer entry | The user-configured delay is the product contract. A secondary 350ms timer currently probes projection readiness. Domain duration plus evidence migration. | Retain the persisted auto-entry deadline under a named injectable scheduler. Enter only when both the user deadline and matching projection readiness are observed; remove the secondary readiness timer and react to projection generation events. The panel session owns timer cancellation. | H; Unit, Behavior, switcher UI, interaction Pressure. | completed |
| SYNC-024 | Composite visual-timing baseline | Semantic owner review found five independent animation or degraded-reveal contracts in the baseline row. Migration routing. | Preserve the baseline ID as the parent and close each lifecycle independently through SYNC-024A–SYNC-024E. | M aggregate; child rows define required validation. | completed: SYNC-024A–SYNC-024E closed independently |
| SYNC-024A | `TerminatePressFeedbackCompletionOwner`, `SwitcherPanelController.terminateSelectedApp`, `AppTileView`; terminate press feedback | An 80ms task sleep gated the terminate request while the rendered press animation used an unrelated 120ms duration. Domain duration plus scheduler-completion evidence. | Use one named 120ms press-feedback policy for the animation and an injectable completion scheduler. The panel controller owns one generation, cancellable token, request continuation, and late-callback rejection through session cancellation. | M; Unit, Behavior, termination UI, deterministic Pressure. | completed |
| SYNC-024B | `InitialWindowOnlyPreviewRevealObservationOwner`, `SwitcherPanelController.prepareInitialWindowOnlyPanelReveal`; initial preview reveal | A 250ms task sleep forced a degraded reveal when preview readiness had not arrived. Watchdog migration. | Use preview-batch completion plus pending-capture readback as the success Oracle. The named injectable watchdog performs a final readback and reports the last event plus unmet condition before degraded reveal; the presentation session owns cancellation and generation replacement. | M; Unit, Behavior, in-app switcher UI, deterministic Pressure. | completed |
| SYNC-024C | `SwitcherAppRemovalAnimationPolicy`, `SwitcherPanelOverlayView`; app-removal transition | A 140ms ease-out duration is a visual-only product contract for app sets up to 16 items. Domain duration. | Retain it as a named Switcher removal-animation policy. SwiftUI app-strip identity owns the animation; exact process termination and projection refresh remain the tile-removal Oracle. | L; Behavior/visual policy assertion, affected switcher UI, Process/Tooling. | completed |
| SYNC-024D | `HomeControlPressAnimationPolicy`, `FlowPageActionButton`; pressed-button transition | A 120ms ease-out duration is a visual-only Home button contract. Domain duration. | Retain it as a named injectable Home control-animation policy. SwiftUI view identity owns the animation; actions continue directly from input callbacks. | L; Behavior/visual policy assertion, affected Home UI, Process/Tooling. | completed |
| SYNC-024E | `SettingsAppVisibilityNavigationAnimationPolicy`, `AppSettingsView`, `AppVisibilityManagerView`; app-visibility navigation transition | A 180ms ease-in-out duration is a visual-only Settings navigation contract. Domain duration. | Retain it as a named injectable Settings navigation-animation policy. Settings view state owns the transition; the manager exposes contained AX children, and destination visibility remains the UI Oracle. | L; Behavior/visual policy assertion, affected Settings UI, Process/Tooling. | completed |
| SYNC-025 | `PanelPresentationDiagnosticProbeOwner`, `SwitcherPanelController+PresentationDiagnostics.swift`; frame-delay probe | A 16ms sleep sampled an assumed later display frame for diagnostics only. Domain measurement. | Retain 16ms only as a named frame-sample interval in an injectable diagnostic scheduler. A generation owner sequences next-main-turn and frame-sample callbacks, while presentation begin/end owns replacement and cancellation. Probe callbacks only emit measured diagnostics, so delayed delivery changes the recorded timestamp without affecting behavior. | L; Behavior diagnostic assertion, deterministic Pressure, Process/Tooling. | completed |
| SYNC-026 | Composite fixture-topology timing baseline | Semantic review separated the fullscreen chain, desktop refocus, and application AX suppression into independent observable contracts. Migration routing. | Preserve this parent ID as the routing boundary and close each lifecycle through SYNC-026A–SYNC-026C2. | H aggregate; child rows define required validation. | completed |
| SYNC-026A | `SpaceFixtureFullscreenTransitionOwner`, `AppKitSpaceFixtureWindow`, `SpaceFixtureWindowCoordinator`; ordered fullscreen transition chain | The workflow-configured initial delay intentionally stages fixture launch, while a fixed 1.4s gap assumed each preceding fullscreen animation had settled enough to start the next window. Domain duration plus evidence migration. | Retain the configured delay only before the first transition. Install the exact-window `didEnterFullScreen` observer before `toggleFullScreen`, then begin every later window directly from the preceding completion evidence. The coordinator-owned generation cancels scheduled work and exact-window observers on replacement; window close owns observer cleanup. | H fixture topology; Unit, Behavior, real multi-fullscreen UI, deterministic Pressure, Process/Tooling. | completed |
| SYNC-026B | `SpaceFixtureDesktopRefocusOwner`, `AppKitSpaceFixtureWindow`, `SpaceFixtureWindowCoordinator`; desktop-anchor refocus | A fixed 1.2s delay after the final fullscreen callback assumes AppKit is ready to activate and key the desktop anchor. Evidence migration with controlled condition polling. | Install exact-window and active-Space observers before activation, then read back application activity, exact plan/window identity, key/main/visible/minimized/active-Space/occlusion state, and the exact on-screen CG window. Because AppKit exposes no request-acceptance callback, use an immediate-condition-first, named 100ms retry owned by the coordinator generation. Completion comes only from the exact readback; a named 15s watchdog reports the final unmet conditions and last evidence. | H fixture topology; Unit, Behavior, desktop-preserving real fixture UI, runtime-topology Pressure. | completed |
| SYNC-026C | Composite application AX-suppression routing boundary | The producer-side projection acknowledgement and fixture-side suppression lifecycle belong to different process and resource owners. Migration routing. | Close producer publication through SYNC-026C1 and fixture suppression through SYNC-026C2. | H aggregate; child rows define required validation. | completed |
| SYNC-026C1 | `FlowTabUITestProjectionAcknowledgementOwner`, `FlowTabUITestBootstrapper`, `FlowTabTestLaunchOptions`; FlowTab TestingSupport projection acknowledgement | A fixture cannot infer when prelaunched FlowTab has committed the exact fixture process and window topology. Evidence migration. | Parse explicit test-only routes, install the runtime projection observer before initial readback, and publish a distributed acknowledgement only for a complete, clean projection matching bundle ID, positive PID, and exact window count. Include monotonic acknowledgement and source generations. The app TestingSupport bootstrap owns observation and termination cleanup. | H cross-process fixture evidence; Unit, Behavior, deterministic Pressure, Process/Tooling; end-to-end UI transport joins SYNC-026C2. | completed |
| SYNC-026C2 | `SpaceFixtureApplicationAXSuppressionOwner`, `SpaceFixtureWindowCoordinator`; fixture application AX suppression | Fixed 5s and post-fullscreen 8s delays assume workflow consumers have captured the application AX window list. Evidence migration. | Install the route observer before fixture window publication, then suppress only after the exact local topology stage, exact published application AX readback, and a matching acknowledgement for the fixture PID and window count. Preserve the route-less fixture flag through the local-topology plus exact-readback contract. Require exact zero readback, publish a monotonic suppression generation for every resolved owner, and report routed terminal evidence. The coordinator owns cancellation and cleanup. | H fixture topology; Unit, Behavior, AX-suppressed real fixture UI, runtime-topology Pressure. | completed |
| SYNC-027 | Composite fixture fault-latency baseline | Semantic owner review found two independent fault-injection contracts: delayed process termination and delayed exact-window close. Domain duration routing record. | Preserve the CLI compatibility boundary and route implementation, lifecycle, evidence, and validation through SYNC-027A and SYNC-027B. | M; child-slice validation. | completed: SYNC-027A and SYNC-027B closed independently |
| SYNC-027A | `SpaceFixtureAppDelegate`, `SpaceFixtureLaunchConfiguration`, `SpaceFixtureTerminationFaultOwner`; delayed process termination | `--terminate-delay-ms` intentionally keeps the fixture process alive after an application or SIGTERM request. The raw `asyncAfter` work had no cancellation owner and exposed no scheduled/applied evidence. Domain duration. | Retain the positive delay as `SpaceFixtureTerminationFaultPolicy`. A single AppDelegate-owned generation schedules through the injectable fixture scheduler, preserves the first request across duplicate sources, publishes exact scheduled/applied evidence with bundle ID and PID, and cancels the task and signal source at app termination. The optional notification route preserves existing launch configurations while enabling an observer to be established before the termination request. | M repeated async work; Unit, Behavior, representative termination UI, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-027B | `SpaceFixtureWindowCloseFaultOwner`, `SpaceFixtureWindowCoordinator`, `SpaceFixtureLaunchConfiguration`; delayed exact-window close | `--close-window-delay-ms` intentionally delays fixture window removal, while the former coordinator token exposed no scheduled/applied acknowledgement and fixture launch time could race the consumer's initial topology observation. Domain duration plus evidence-driven orchestration. | Retain the named fault duration behind an exact generation, bundle/PID, plan-index, and stable-window-number contract. Install the optional trigger observer before the initial readback and scheduled evidence; begin the delay from a matching trigger, then resolve only from AppKit visibility, exact CG-window, and coordinator-topology readback. Use an immediate first readback, named cancellable 50ms retry where WindowServer exposes no close-completion event, and a diagnostic 10s watchdog. The coordinator-owned fault owner cancels every observer and token. | M repeated async work; Unit, Behavior, representative window-removal UI, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-028 | Composite fixture workflow-readiness baseline | Semantic owner review separated per-process fixture readiness, multi-application readiness aggregation, and desktop-anchor orchestration. Migration routing. | Close coordinator-owned process readiness through SYNC-028A, route workflow-wide settling through SYNC-028B1, and close final desktop-anchor activation through SYNC-028B2. | H aggregate; child rows define required validation. | completed |
| SYNC-028A | `SpaceFixtureWorkflowReadinessOwner`, `SpaceFixtureWindowCoordinator`, `SpaceFixtureWindowContentView`, `launchSpaceFixtureWorkflow`; one fixture process readiness | The visible “Ready” state and shared single-process UI launcher previously advanced before fullscreen and desktop-refocus completion, then used a fixed settle duration to infer usable topology. Evidence migration. | Start a coordinator-owned readiness generation before window publication and emit exact configured, planned-window, fullscreen-completion, desktop-presentation, application-AX-exposure, and terminal-ready evidence. Update the visible state only from terminal evidence. The UI installs a unique observer before launch, captures the configured baseline, and accepts the later ready stage only for the same generation, bundle ID, PID, window plan, and fullscreen plan. Coordinator and XCTest-case lifecycles own cancellation and observer cleanup. | H fixture topology; Unit, Behavior, representative real fullscreen UI, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-028B | Composite multi-application workflow-readiness routing boundary | Semantic owner review separated readiness evidence emitted independently by every fixture process from the final desktop-anchor activation and Space readback. Migration routing. | Aggregate every configured fixture process through SYNC-028B1, then establish the final anchor through SYNC-028B2. | H aggregate; child rows define required validation. | completed |
| SYNC-028B1 | `SpaceFixtureWorkflowReadinessAggregateOwner`, `launchResolvedSpaceFixtureWorkflow`, `launchResolvedEdgeInputsWorkflow`; all-process readiness aggregation | A workflow-wide `settleTimeout` and fixed RunLoop advancement inferred when independently launched fixture processes and their Space topology were ready. Evidence migration plus watchdog. | Install a unique distributed observer for every workflow app before launching any process. Capture each exact configured baseline and accept its later ready evidence only for the configured workflow app ID, bundle ID, PID, observation generation, window plan, fullscreen plan, and titles. Complete after every app has terminal evidence. The workflow invocation owns all observers and aggregate-generation cancellation; one named watchdog reports every unmet app and last observation. | H multi-process fixture topology; Unit, Behavior, standard and edge multi-application UI, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-028B2 | `SpaceFixtureWorkflowDesktopAnchorObservationOwner`, `launchResolvedSpaceFixtureWorkflow`, `launchResolvedEdgeInputsWorkflow`; final desktop-anchor activation | After aggregate readiness, the launchers call `activate()` and use generic foreground state as the final desktop-anchor result. Evidence migration with exact readback. | Establish workspace observers and initial readback before activation. Resolve only when the exact readiness PID is active and frontmost, XCUI reports it foreground, the exact plan-identified XCUI window frame matches the PID-scoped topmost on-screen CG window, and that CG frame satisfies the desktop-Space non-fullscreen-size readback. The workflow invocation owns generation cancellation, observers, polling, and a diagnostic terminal watchdog. | H desktop/Space topology; Unit, Behavior, affected standard and edge UI, runtime-topology Pressure, Process/Tooling. | completed |
| SYNC-029 | `FlowTabUITestInitialPresentationObservationOwner`, `FlowTabUITestBootstrapper.presentInitialUIIfNeeded`; initial UI-test Search/switcher presentation | Twenty 150ms retries and two equal snapshots infer runtime projection stability before opening Search/switcher. Evidence migration. | Install exact projection observers before the baseline readback and readiness request. Resolve from an initially complete projection, a monotonic later generation, or a same-generation completeness transition; require the exact filtered projection/session item signature and a compatible post-presentation readback. A complete empty projection is authoritative no-content. The bootstrapper owns replacement, prepare, termination, resolution, observer, generation, task, and watchdog cleanup. | H test orchestration; Behavior, UI, runtime-topology/Search Pressure. | completed |
| SYNC-030 | Composite TestingSupport fault-injection timing boundary | Semantic owner review separated mock preview-capture latency from initial panel-occlusion staleness. Domain fixture duration routing. | Close preview-capture latency through SYNC-030A and panel-occlusion staleness through SYNC-030B. | M aggregate; child rows define required validation. | completed |
| SYNC-030A | `FlowTabUITestMockWindowPreviewLatencyOwner`, `FlowTabUITestBootstrapper.installMockWindowPreviewsIfNeeded`; mock preview I/O latency | A blocking thread sleep intentionally delays preview capture, has no cancellation owner, and exposes no TestingSupport completion evidence. Domain fixture duration. | Retain the compatible millisecond launch option as a bounded named latency policy. A TestingSupport generation owner performs a cancellable monotonic deadline wait and publishes exact owner/batch/request/outcome evidence. Preview result identity remains the success Oracle. Bootstrap preparation, replacement, termination, and deinitialization own cancellation. | M asynchronous preview path; Unit, Behavior, affected UI, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-030B | Initial panel-occlusion stale hook in `FlowTabUITestBootstrapper` | A task sleep intentionally holds stale occlusion state before releasing visibility, while generation equality informally rejects replacement. Domain fixture duration. | Retain the compatible millisecond launch option as a bounded named staleness policy; inject a cancellable scheduler, publish installed/released/cancelled evidence, and make bootstrap preparation, replacement, termination, and deinitialization own cleanup. The panel visibility/recovery state remains the success Oracle. | M presentation lifecycle; Unit, Behavior, affected UI, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-031 | `TabSwitchStressPolicy`, `TabSwitchStressRunner`, `TabSwitchStressEvidenceTransport`; tab-switch stress workload | Switch cadence and total duration define an exact planned pressure workload. The former wall-clock loop allowed slower scheduling to reduce the number of switches and swallowed task cancellation. Domain duration plus exact selection evidence. | Preserve the compatible launch inputs as a bounded named policy and derive `ceil(duration / cadence)` planned selections. Start with an immediate selection, count each planned target only after exact selected-tab readback, and complete after both the monotonic duration and workload evidence are satisfied. The runner owns one generation and cancellable wake; AppDelegate termination owns stop. UI establishes a unique distributed evidence route before launch. | M hot path; Unit/Behavior for runner, affected UI, deterministic and real tab-switch Pressure, Process/Tooling. | completed |
| SYNC-032 | Shared app-test asynchronous wait baseline | Semantic caller review found independent AppVisibility reload, AppDelegate delivery, Search publication, preview publication, panel presentation, termination-feedback, delayed-entry, and launch-bootstrap owners behind the two generic polling helpers. Migration routing. | Remove the generic helpers by closing each observable lifecycle through SYNC-032A–SYNC-032H. Retain a condition observer only if a caller has no callback, notification, task completion, scheduler, generation, or published state. | M aggregate; child rows define required validation. | completed: SYNC-032A–SYNC-032H closed and both generic polling helpers removed |
| SYNC-032A | `FlowTabTests+Support.waitUntil`; `AppVisibilityManagerModel.reload` tests | Two app-inventory tests polled wall-clock time and swallowed sleep cancellation while `@Published isLoading` already exposed task lifecycle. Evidence migration. | Subscribe before `reload()`, reject the initial idle value, and resolve only from the observed `loading → idle` transition. The test scope owns and releases the Combine subscription; XCTest timeout is the diagnostic failure bound. | L test synchronization; affected Unit/Behavior, Process/Tooling. | completed |
| SYNC-032B | AppDelegate notification-delivery routing boundary | Semantic caller review separated workspace lifecycle delivery from hotkey replacement delivery. Migration routing. | Close the independently emitted workspace and hotkey contracts through SYNC-032B1 and SYNC-032B2. | M aggregate; child rows define required validation. | completed: SYNC-032B1 and SYNC-032B2 closed independently |
| SYNC-032B1 | `FlowTabPriorityCoverageTests+AsyncSupport.waitUntil`; AppDelegate workspace launch and termination delivery tests | Workspace notifications are followed by generic polling of runtime-projection recording state. Evidence migration. | Establish exact app/PID recording callbacks before posting each workspace notification, then fulfill from the matching launch or termination signal and require the final recording readback. Test teardown owns callback removal. | M app lifecycle; affected Behavior, Process/Tooling. | completed |
| SYNC-032B2 | `AppDelegate.installHotkeyObserver`; AppDelegate hotkey-notification delivery tests | A hotkey-reload notification was followed by generic polling of replacement-monitor records. Its main-queue callback also deferred active-delegate validation into an unowned task, allowing later `shared` restoration to change which delegate accepted historical delivery. Evidence and lifecycle migration. | Establish the exact registration-evidence observer and generation baseline before posting. Handle the main-queue notification synchronously so the active delegate, sender, request ID, configurations, and takeover result are bound at receipt; require final evidence and exact monitor readback. AppDelegate owns observer removal at termination. | H long-lived observer lifecycle; affected Behavior, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-032C | `LiveSwitcherModel.handleApplicationTerminated`; Search preservation during projection refresh | Search scheduling and termination refresh publish model/layout completion, while the regression test polled derived state twice. Evidence migration. | Establish exact Search-result publication before mutating the query and again before terminating the app; independently observe the layout refresh, then require the final projection, scope, query, and result readback. Test scope owns callback cleanup. | M Search behavior; affected Unit/Behavior, deterministic Pressure, Process/Tooling. | completed; the expanded full run's launch-bootstrap order-isolation failure is assigned to SYNC-032H |
| SYNC-032D | Preview publication and reveal routing boundary | Semantic caller review found that model preview-batch publication and controller-owned initial panel reveal have independent event sources and lifecycles. Migration routing. | Close model publication through SYNC-032D1 and controller reveal through SYNC-032D2. | M aggregate; child rows define required validation. | completed: SYNC-032D1 and SYNC-032D2 closed independently |
| SYNC-032D1 | `FlowTabPriorityCoverageTests+WindowPreviewProviders`; `LiveSwitcherModel` preview batch publication | Terminal preview success and structured failure are inferred by polling snapshots and provider call counts after requesting capture. Evidence migration. | Install the model's preview-preparation callback before the first snapshot request. Fulfill once from exact image or failure/retry state, then independently read back the final snapshot, provider route, call count, and generation. Test scope owns callback cleanup. | M repeated preview work; affected Behavior, preview Pressure, Process/Tooling. | completed |
| SYNC-032D2 | `FlowTabPriorityCoverageTests+SwitcherInteractionRegressions`; initial window-only panel reveal | The regression polls panel alpha after asynchronous preview-batch completion even though the controller owns preview-ready evidence and reveal generation. Evidence migration. | Observe the controller's exact preview-ready resolution before presentation, then require matching observation/presentation generations, zero pending captures, panel alpha, and final image readback. Test scope owns observation cleanup. | M preview presentation; affected Behavior, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-032E | Search viewport and initial-presentation sizing routing boundary | Semantic caller review found that Search-result viewport scrolling and TestingSupport launch presentation have independent event sources and lifecycles. Migration routing. | Close Search state/scroll publication through SYNC-032E1 and initial launch sizing through SYNC-032E2. | M aggregate; child rows define required validation. | completed: SYNC-032E1 and SYNC-032E2 closed independently |
| SYNC-032E1 | `FlowTabPriorityCoverageTests+SessionAndPanelSearch`; Search activation and result viewport scrolling | Search activation result state and the SwiftUI scroll request were inferred by two generic condition polls even though activation publishes synchronously and the viewport exposes a completion callback plus monotonic scroll revision. Evidence migration. | Install the viewport callback before presentation. Require the immediate Search activation readback, then accept the first-focus and wrap events only when callback result ID, current scroll revision, selected index, and selected result all match the expected transition. Test scope owns callback restoration and presentation cleanup. | M Search viewport behavior; affected Unit/Behavior, deterministic Search Pressure, Process/Tooling. | completed |
| SYNC-032E2 | `FlowTabPriorityCoverageTests+SessionAndPanelSearch`; TestingSupport initial Search presentation sizing | The test polls Search-active state and panel height after launch bootstrap even though TestingSupport publishes exact initial-presentation resolution. Evidence migration. | Observe `.flowTabUITestInitialPresentationDidResolve` before bootstrap, require a matching controller object and Search-ready evidence, then read back active Search state, exact result count/layout measurements, and final panel size. Test scope owns notification cleanup and bootstrap cancellation. | M TestingSupport presentation; affected Behavior, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-032F | Shared `waitUntil` callers for terminate-shortcut entry | Tests poll pending termination after the named press-feedback completion scheduler already owns the transition. Evidence migration. | Inject the manual completion scheduler or establish the terminate-request callback before input, deliver completion explicitly, and verify the exact pending app/PID generation. | M termination behavior; affected Behavior, deterministic Pressure, Process/Tooling. | completed |
| SYNC-032G | Delayed and manual window-layer entry routing boundary | Semantic caller review found a user-configured deadline contract and an independently delivered projection-readiness contract behind the remaining generic polls. Migration routing. | Close the configured deadline through SYNC-032G1 and manual projection readiness through SYNC-032G2. | M aggregate; child rows define required validation. | completed: SYNC-032G1 and SYNC-032G2 closed independently |
| SYNC-032G1 | `FlowTabPriorityCoverageTests+DelayedWindowLayerEntry`; configured delayed window-layer entry | Tests poll the window-layer mode after a named, user-configured presentation deadline even though the delayed-entry scheduler owns delivery and exposes an exact pending lifecycle. Product time contract with deterministic delivery. | Inject `ManualDelayedWindowLayerEntryScheduler`, require the configured override or preference interval and pending owner readback before firing, then deliver the deadline explicitly and verify exact selected-app projection and mode synchronously. The presentation session owns cancellation. | M panel lifecycle; affected Behavior, deterministic owner Pressure, Process/Tooling. | completed |
| SYNC-032G2 | `FlowTabPriorityCoverageTests+ManualWindowLayerEntry`; manual window-layer projection readiness | A manual entry test polls first for projection maintenance and then for mode after invoking the explicit projection-update callback. Evidence migration. | Require the exact selected-app maintenance request immediately after input, publish the committed projection, invoke the matching update callback, and verify projection generation, selected windows, mode, and delayed-owner cancellation directly. | M panel lifecycle; affected Behavior, deterministic owner Pressure, Process/Tooling. | completed |
| SYNC-032H | `waitForLaunchBootstrapSearchAndSeededLogs`; AppDelegate UI-test bootstrap | A helper polls runtime log I/O and panel state together after launch. In suite order, a second exact pair of hotkey-monitor factory records can also arrive before that polling helper returns, while the isolated test remains green. Evidence and lifecycle migration. | Establish initial-presentation, log-change, and launch hotkey-registration evidence before launch; join the exact Search session, requested seeded-log count, and launch registration generation/readback. Identify and cancel or reject any hosted-app state from an earlier test generation. The test owns observations and one diagnostic XCTest timeout. | H hosted launch orchestration; affected Behavior, deterministic lifecycle Pressure, Process/Tooling. | completed |
| SYNC-033 | App tests with direct fixed waits; semantic review routing boundary | Raw RunLoop advances and sleeps represented independently owned SwiftUI/AppKit materialization, Settings bridge publication, notification nonblocking, AX background execution, and pressure-workload contracts. Migration routing. | Close each observable lifecycle through SYNC-033A–SYNC-033E. Earlier `PanelSessionBehavior` and `SwitcherInteractionRegressions` waits closed with their SYNC-032 owners. | M aggregate; child rows define required validation. | completed: SYNC-033A–SYNC-033E closed independently |
| SYNC-033A | `FlowTabTests+CompactActionButton`, `FlowTabTests+RuntimeLogsHostedControls`; initial hosted Logs control materialization | Two generic RunLoop condition loops wait for exact AppKit controls to appear below a SwiftUI host. Semantic review shows both representables materialize during the explicit host layout pass. | Perform the layout trigger once, then require immediate exact identifier/type hierarchy readback. Keep action-binding, style, and absence-of-native-popup assertions as independent Oracles. No observer or timer is needed when the synchronous readback is complete. | L test synchronization; affected Behavior, Process/Tooling. | completed |
| SYNC-033B | `FlowTabTests+EnglishLayout`, `FlowTabTests+PreferencesAndDiagnostics`; Settings presentation, permission, and system-appearance publication routing boundary | Generic RunLoop condition loops combine three independently owned state contracts. Migration routing. | Close system-theme readback, hosted presentation bridge publication, and permission evidence through SYNC-033B1–SYNC-033B3. | M aggregate; child rows define required validation. | completed: SYNC-033B1–SYNC-033B3 closed independently |
| SYNC-033B1 | `FlowTabTests+SystemThemeReadback`; app-scoped appearance-default contamination | A generic RunLoop loop waits for a distributed system-theme notification to return after the test has already established the expected effective appearance. Semantic review shows `SystemThemeState.refreshColorScheme()` performs the complete synchronous system-appearance readback. | Apply the app-scoped default, invoke the explicit refresh, and immediately require both `NSApp.effectiveAppearance` resolution and `SystemThemeState.colorScheme` to equal the baseline system scheme. Refresh again during test-owned restoration. | L test synchronization; affected Behavior, Process/Tooling. | completed |
| SYNC-033B2 | `SettingsPresentationObservationTestSupport`, `FlowTabTests+SettingsPresentationBridge`, `FlowTabTests+SettingsPresentationLayout`; hosted language and theme publication | RunLoop loops infer that SwiftUI published presentation state has rebuilt and updated the hosted AppKit Settings bridge. SwiftUI exposes no production render-completion callback for this representable boundary. | Wrap the unchanged Settings content with a test-owned SwiftUI transaction probe. Capture its initial context generation, install a cancellable callback before each trigger, and accept only a newer exact target context before checking localized-text or appearance topology. Keep the named XCTest watchdog as a failure bound with last-evidence diagnostics. Cold-host materialization uses direct layout readback when complete. | M Settings presentation behavior; affected Unit/Behavior, deterministic Pressure, Process/Tooling. | completed |
| SYNC-033B3 | `FlowTabTests+SettingsPermissionReadback`; permission request title publication | A RunLoop loop infers that the permission coordinator's exact post-request readback reached the hosted action button. | Capture a permission-readback generation and the denied title, then install both a cancellable granted-readback callback and exact `NSButton.title` KVO before click. Require the independent post-request readback, one request, and localized granted-state title. Keep a named XCTest watchdog as the failure bound with last-readback diagnostics. | M permission presentation behavior; affected Unit/Behavior, deterministic Pressure, Process/Tooling. | completed |
| SYNC-033C | `FlowTabPriorityCoverageTests+RuntimeProjectionNotificationPublication`; background notification publication while MainActor is unavailable | A 500ms blocking wait proves publishers return, then a raw 10ms RunLoop loop assumes cleanup eventually completes. Evidence migration plus watchdog. | Enter all publishers and register DispatchGroup completion before dispatch. Keep a named blocking watchdog solely as the nonblocking failure bound, then wait for exact publisher-return completion through XCTest to release MainActor and clean up. Test scope owns the group expectation and controller lifetime; failure reports completed notification names. | M runtime-notification delivery; affected Behavior, Process/Tooling. | completed |
| SYNC-033D | `FlowTabPriorityCoverageTests+RuntimeAXBackgroundResolution`; background remote AX resolution | A 250ms main-thread sleep is treated as proof that remote AX resolution can proceed without MainActor availability. Evidence migration plus watchdog. | Establish worker-start, resolver-invoked, and fetch-completed evidence before dispatch. Block MainActor only on a named resolver-invocation watchdog, then require exact off-main-thread readback and terminal worker completion. Test scope owns semaphores and override cleanup. | M AX runtime behavior; affected Behavior, runtime-topology Pressure, Process/Tooling. | completed |
| SYNC-033E | `FlowTabPriorityCoverageTests+RuntimeSnapshotPressure`; bounded AX collection workload | Per-item thread sleep simulates I/O latency and elapsed-time comparison is treated as concurrency success. Deterministic pressure workload migration. | Replace sleep with a named, test-owned blocking workload gate. Require the configured number of workers to enter concurrently, release work from explicit evidence, and verify bounded maximum concurrency plus ordered results independently of elapsed wall time. | M runtime hot path; affected Behavior, deterministic Pressure, Process/Tooling. | completed |
| SYNC-034 | `FlowTabUITests+Support.swift`, `+WorkflowWindowObservation.swift`, `+SpaceFixtureApp.swift`, `+ScrollingSupport.swift`, `+StatusItem.swift`, and fixture assertion helpers; shared UI condition loops | RunLoop cadence advances drive XCUI/CG/AX/process predicate observation. Conditional observation. | Centralize named UI observation cadence and watchdog diagnostics, check immediately, use `waitForExistence`/predicate expectations where possible, and keep exact CG/AX/window/process readback as the sole Oracle. XCTest case lifetime owns the wait. | H test infrastructure; affected UI suites, Process/Tooling. | in progress; SYNC-034A–SYNC-034S, SYNC-034U, and SYNC-034X completed, SYNC-034T, SYNC-034V–SYNC-034W, and SYNC-034Y–SYNC-034AA validation-blocked, with remaining owners split into later slices |
| SYNC-034A | `FlowTabUITests+WorkflowWindowObservation.waitForExactFrontmostSpaceFixtureWindow`; exact frontmost fixture-window observation | Optional AX and CG window numbers can both be absent and compare equal, allowing the condition loop to return without observing an exact window. Evidence-Oracle defect discovered by the SYNC-028B2 diagnostic run. | Reuse the generation-owned desktop-anchor observer and require the exact PID to be running, active, frontmost, and XCUI-foreground; join the exact title/identifier XCUI window to a present PID-scoped topmost CG window by valid matching frames and require desktop-Space readback. Install workspace observers before initial readback, treat XCUI attachment as an observed condition, retain only the named cancellable 100ms condition cadence where no exact attachment/window callback exists, and use the caller's named watchdog as a diagnostic failure bound. The helper invocation owns cancellation and cleanup. | H test Oracle; desktop-refocus UI, runtime-topology Pressure, Process/Tooling. | completed |
| SYNC-034B | `FlowTabUITests+ConditionObservation`, `waitForFrontmostBundleIdentifier`, status-item reopen and system-app MRU activation callers; exact frontmost application | A raw 100ms RunLoop loop begins after activation and infers that the expected application eventually became frontmost. | Start a generation-owned condition observer before activation. Register `NSWorkspace.didActivateApplicationNotification` before an initial `frontmostApplication` readback, accept only the exact bundle identifier, and use the caller timeout solely as a failure bound with last-readback diagnostics. Test scope cancels the notification token; stale, duplicate, replaced, and cancelled callbacks are rejected. | H shared UI observation; affected status-item/System MRU UI, deterministic owner Pressure, Process/Tooling. | completed |
| SYNC-034C | `FlowTabUITests+ConditionObservation`, `FlowTabUITests+SystemAppMRU.triggerAndWaitForWorkflowAppOrder`; exact switcher application order | A raw 100ms RunLoop loop returns on any complete fixture-application permutation, so a stale order can fail the caller before the expected order is published. | Install the exact-order observer before an explicit post-baseline runtime-log-confirmed switcher trigger. Check immediately, then use a test-owned main-RunLoop timer at the named XCUI readback cadence because the accessibility summary exposes no publication callback. Accept only the expected complete ordered identifiers. The helper owns timer cancellation; the caller timeout is solely a failure bound with the last summary/order readback. | H shared UI conditional observation; System MRU UI, deterministic owner Pressure, Process/Tooling. | completed |
| SYNC-034D | `FlowTabUITests+SystemAppMRU.terminateFlowTabUITestApplicationAndWait`; FlowTab process termination before MRU relaunch | A raw 100ms RunLoop loop polls `XCUIApplication.state` after termination. | Own the termination trigger and wait on XCTest's exact `.notRunning` application state. Treat the caller timeout only as a terminal failure bound and report the final application state. The helper invocation owns the wait. | M UI process lifecycle; System MRU UI, Process/Tooling. | completed |
| SYNC-034E | `FlowTabUITestConditionObservationOwner.observe`, `FlowTabUITests+StatusItem.waitForFlowTabStatusElement`; reentrant XCUI readback and status-item accessibility publication | Raw 100ms RunLoop loops repeatedly query the FlowTab application and SystemUIServer; quit-menu observation begins only after the menu-open action. The first migrated UI path proves that `XCUIElement.exists` can pump the RunLoop and reenter the shared owner, allowing an outer readback to fulfill an already-resolved generation again. | Revalidate the generation and unresolved state after every client readback and condition evaluation, discarding superseded outer work. Use the shared generation-owned scheduled readback because XCUI exposes no element-publication callback. Check immediately, establish the quit-item observer before the control-click trigger, and accept only the exact status or quit element's existence. The helper owns timer cancellation; the named watchdog is solely a failure bound with per-source last-readback diagnostics. | H shared UI observation; deterministic reentrancy and scheduler Pressure, status-item reopen/quit UI, Process/Tooling. | completed |
| SYNC-034F | `FlowTabUITests+SettingsCommandTabObservation.assertCommandTabTakeoverMarker`; cross-process Command+Tab takeover marker activation and restoration | A raw 100ms RunLoop loop begins after the action and polls the shared defaults marker with an unnamed cadence. Runtime logs establish production ordering but cannot prove that the marker is already visible to another process under I/O delay. | Establish the marker observer before the settings or quit trigger, require the inverse initial baseline, and check shared defaults immediately. Because cross-process defaults expose no reliable publication callback, use a named cancellable readback cadence until the exact expected Boolean is visible. Active-registration logs and `.notRunning` remain independent ordering evidence. The helper owns timer cancellation; the named watchdog is solely a failure bound with expected and last-observed values. | H system-shortcut UI lifecycle; affected Settings UI, existing shared-owner Pressure, Process/Tooling. | completed |
| SYNC-034G | `FlowTabUITests+HittableElementObservation`, `tapFirstHittable`, and `hasHittableElement`; exact actionable XCUI query candidate | Two shared helpers use raw 100ms RunLoop loops and wall-clock deadlines to discover the first existing, hittable query candidate. | Start a generation-owned scheduled query observer, perform an immediate readback, and accept only the first exact candidate whose `exists` and `isHittable` evidence is true. XCUI exposes no candidate-publication callback, so retain the shared named cancellable readback cadence. The helper invocation owns cancellation; its caller-supplied watchdog is solely a failure bound and reports candidate count, observed existing indices, first hittable index, source, and generation. | H shared UI interaction helper; deterministic owner tests, sidebar UI and repeated-path Pressure, Process/Tooling. | completed |
| SYNC-034H | `FlowTabUITests+ElementValueObservation`, `assertValue`, and `assertValuePrefix`; exact and prefix XCUI element-value publication | Two shared assertions use raw 100ms RunLoop loops and wall-clock deadlines to discover a matching accessibility value. | Start a generation-owned scheduled value observer before its immediate readback. Accept only an existing exact element whose string value satisfies the exact or prefix predicate. XCUI exposes no value-publication callback, so retain the shared named cancellable readback cadence. The helper invocation owns cancellation; its caller-supplied watchdog is solely a failure bound and reports identifier, existence, expected predicate, actual value, source, generation, and waiter result. | H shared UI assertion helper; deterministic owner tests, affected Settings UI, owner-lifecycle Pressure, Process/Tooling. | completed |
| SYNC-034I | `FlowTabUITestConditionObservationOwner`, `FlowTabUITestConditionReadbackScheduler`; shared scheduled XCUI readback serialization | The repeating 100ms Timer can fire while an XCUI readback is pumping the RunLoop. A slower readback therefore admits nested same-generation reads, stale XCUI elements, and machine-dependent assertion outcomes. Evidence-Oracle infrastructure defect. | Keep one cancellable one-shot Timer pending, rearm it only after its callback returns, and suppress a scheduled callback while the same generation is already reading. Preserve notification reentrancy for synchronous publication races. The condition owner owns generation rejection; the serial schedule owns its current Timer and cancellation. The named cadence only controls the next observation opportunity, while each condition/readback remains the sole success Oracle. | H shared UI observation infrastructure; deterministic scheduler/notification tests, 100 Timer and 500 generation Pressure, affected hittable/value/status-item UI, Process/Tooling. | completed |
| SYNC-034J | `FlowTabUITests+HomeWindowProjectionObservation`, `homeWindowRows`, `waitForHomeWindowRow`, `waitForHomeWindowTitle`, `assertHomeWindowTitle`, and `assertHomeWindowTitlesAbsent`; persistent Home window projection | Raw 100ms RunLoop loops and wall-clock deadlines infer that the selected app's window rows and titles have appeared or that another app's titles have disappeared. | Start a generation-owned projection observer before its immediate readback. Accept only a matching exact static title, a case-insensitive title match in a stable window-row label/value projection, or the readback absence of every prohibited title. XCUI exposes no Home-projection publication callback, so retain the shared serial named cadence. The helper owns cancellation; its caller watchdog is solely a failure bound and reports generation, source, exact visible static titles, row identifiers/labels/values, and waiter result. | H shared Home UI Oracle; deterministic owner tests, 100 lifecycle Pressure, exact activation and multi-app isolation UI, Process/Tooling. | completed |
| SYNC-034K | `FlowTabUITests+SwitcherWindowTitleObservation`, `waitForSwitcherWindowCards`; exact Switcher card title multiset | A raw 100ms RunLoop loop and wall-clock deadline infer that the window-card total and per-title counts have been published, including after a real window closes. | Start a generation-owned title-projection observer before its immediate readback. Bind the matching card query once per readback, derive total count and the complete title multiset from that element projection, and accept only exact equality with the expected multiplicities. XCUI exposes no card-projection callback, so retain the shared serial named cadence. The helper owns cancellation; its caller watchdog is solely a failure bound and reports expected/observed counts, generation, source, and waiter result. | H shared Switcher UI Oracle; deterministic duplicate-title tests, 100 lifecycle Pressure, physical Control+Tab and real window-set mutation UI, Process/Tooling. | completed |
| SYNC-034L | `FlowTabUITests+SwitcherWindowCardObservation`, `switcherWindowCardObservations`, `previewImageIdentifier`, and `assertSwitcherPreviewWindowCards`; exact Switcher card identity replacement | A raw 100ms RunLoop loop and wall-clock deadline infer that a selected app's complete card projection replaced the preceding app's anchors. | Start a generation-owned full-card projection observer and capture its baseline before the Down Arrow trigger. Gate resolution until that trigger returns, then accept only a post-trigger readback with the exact expected title multiset and card total, unique identifiers, absence of excluded titles, and complete disjointness from the preceding card identifiers. Preserve value, frame, and preview-image state in the same readback for downstream assertions and watchdog evidence. XCUI exposes no projection callback, so retain the shared serial named cadence. The helper owns cancellation; its caller watchdog is solely a failure bound with exact last-card diagnostics. | H shared Switcher identity Oracle; deterministic baseline/stale/excluded/multiplicity/identity-collision tests, 100 lifecycle Pressure, real multi-app card-isolation UI, Process/Tooling. | completed |
| SYNC-034M | `FlowTabUITests+LogsProjectionObservation`, `assertLogVisibility`, and obsolete `waitForLogs`; exact seeded Logs accessibility projection | Separate raw 200ms and fixed 1.2s RunLoop advances infer that log content or absence has settled; the marker helper has no remaining caller. | Remove the obsolete marker loop. Before tapping Logs, start a generation-owned observer with immediate baseline readback, then gate success until the trigger returns. Accept only the exact seeded-row identifier multiset and total, required tab/container existence, and prohibited-row absence. XCUI exposes no projection callback, so retain the shared serial named cadence. The helper owns cancellation; its watchdog is solely a failure bound with the acceptance gate and exact last projection. | H shared Logs UI Oracle; deterministic baseline/partial/prohibited/multiplicity tests, 100 lifecycle Pressure, runtime-log-level UI, Process/Tooling. | completed |
| SYNC-034N | `FlowTabUITests+RuntimeLogFileObservation`, `+RuntimeLogObservation`, `makeRuntimeLogFileSnapshot`, and `waitForRuntimeLogFiles`; cross-process runtime-log publication | Two used raw 200ms RunLoop loops begin after their triggers and infer that marker or regex evidence has flushed to disk; the required-plus-alternative overload has no caller. | Remove the unused overload. Resolve the Application Support log path at the UI-runner resource boundary. Start a cancellable vnode observation session and capture path, byte-count, file-identity, and event-generation baselines before the trigger. On wait, register for file events before immediate post-baseline content readback; retain a named serial 200ms readback cadence for coalesced, rotated, or unavailable vnode events. Accept only post-baseline file content satisfying the exact marker/regex contract. Baseline scope owns descriptors; each wait owns event/timer registration; watchdog expiry reports the unmet contract, event generations, content size, and bounded tail. | H shared cross-process UI Oracle; real vnode append, deterministic marker/regex tests, 100 lifecycle Pressure, affected mock-runtime UI, Process/Tooling. | completed |
| SYNC-034O | `FlowTabUITests+Support.waitForFocusedWorkflowWindow`; obsolete focused-window condition loop | A raw 100ms RunLoop loop remains in shared support even though semantic call-site review finds no caller. Obsolete test infrastructure. | Remove the unreferenced helper and close its ownerless observation lifecycle. Full-target compilation and zero symbol references are the closure evidence. | L obsolete UI-test helper; Process/Tooling. | completed |
| SYNC-034P | `FlowTabUITests+Support.assertStaticTextsAbsent`; obsolete static-text absence loop | A raw 100ms RunLoop loop remains in shared support even though semantic call-site review finds no caller. Obsolete test infrastructure. | Remove the unreferenced helper and close its ownerless observation lifecycle. Existing executable absence contracts use XCTest predicate expectations through `waitForNonExistence`. Full-target compilation and zero symbol references are the closure evidence. | L obsolete UI-test helper; Process/Tooling. | completed |
| SYNC-034Q | `FlowTabUITests+WorkflowWindowActivationObservation`, `waitForFrontmostWorkflowWindow`, and five Home/search activation callers; exact fixture-window activation | A raw 100ms RunLoop loop starts after the click or search confirmation and can accept a matching title or any matching app window as frontmost success. | Start a generation-owned observer before each trigger, capture the initial exact window readback, and gate resolution until the trigger returns. Combine workspace activation and target-process AX focused/main-window notifications with the shared named serial readback cadence. Accept only the expected bundle identifier plus exact topmost on-screen CGWindowID. The helper invocation owns all observer tokens, AX registrations, scheduled readback, cancellation, and watchdog diagnostics. | H exact window-identity UI Oracle; deterministic owner regression, 100 lifecycle Pressure, real multi-window fixture UI, Process/Tooling. | completed |
| SYNC-034R | `FlowTabUITests+ScrollingSupport.tapFirstHittableAfterScrolling` and Settings option-selection callers; exact dropdown option hittability | A raw 100ms RunLoop loop intertwines scroll actions with elapsed-time advancement and treats the deadline as the completion model. | Perform an immediate target/container readback, then use one named cancellable 100ms readback opportunity because XCUI exposes no option-frame or hittability callback. Derive one serial scroll event from exact target/container geometry, register the next readback only after that event returns, and accept only the exact first hittable candidate. The helper owns schedule cancellation; a named 30-second watchdog is solely a failure bound and reports the final geometry, step count, and delta. | H shared UI interaction Oracle; deterministic geometry/initial/slow-readback/watchdog tests, 100 lifecycle Pressure, Settings hotkey persistence UI, Process/Tooling. | completed |
| SYNC-034S | `FlowTabUITests+ScrollingSupport.tapElementAfterScrollingIntoView` and `selectHomeWorkflowApp`; exact Home app-row visibility | A raw 100ms RunLoop loop intertwines scroll actions with elapsed-time advancement and infers that an app row is actionable from elapsed time. | Read the exact target and its preferred or smallest horizontally containing fallback scroll container immediately. Accept only an existing, hittable target fully contained by the selected container, or the same exact target when no container exists. XCUI exposes no frame or hittability publication callback, so use the shared named serial cadence; derive one deterministic scroll event after each unresolved readback and register the next readback only after the event returns. The helper invocation owns scheduling, cancellation, and diagnostics; the caller watchdog is solely a terminal failure bound. | H shared UI interaction Oracle; deterministic selection/geometry/initial/slow-readback/watchdog tests, 100 lifecycle Pressure, real multi-app Home UI, Process/Tooling. | completed; affected UI execution is environment-blocked before the helper, with evidence recorded below |
| SYNC-034T | `FlowTabUITests+SpaceFixtureHomeActivation.selectHomeWorkflowApp`, `FlowTabUITestHomeAppSelectionObservationOwner`; exact selected-app Home projection | An outer wall-clock loop repeatedly performs 100ms title waits, limits each row action to two seconds, waits 1.5 seconds after a click, and clicks again when the expected projection has not appeared. Scheduling therefore controls action repetition and selection success. | Establish a selection generation and exact title-projection baseline before the row action. Accept an already matching baseline. Otherwise pause conditional XCUI polling while the SYNC-034S row owner scrolls and taps, perform an immediate trigger-return readback, then enable the shared named serial cadence only while the persistent exact title condition remains unmet. The selection invocation owns the deferred schedule, cancellation, monotonic watchdog budget, and final projection diagnostics. | H multi-owner Home UI orchestration; deterministic initial/trigger/delayed/watchdog tests, 100 generation Pressure, real multi-app Home isolation UI, Process/Tooling. | blocked: implementation and Process build passed; system authentication prevented XCTest initialization before all owner and affected UI tests |
| SYNC-034U | `FlowTabUITests+WorkflowWindowObservation.waitForTopmostWorkflowCGWindow`; obsolete topmost-window loop | A raw 100ms RunLoop loop remains in shared workflow support even though semantic call-site review finds no caller. Obsolete test infrastructure. | Remove the unreferenced helper and its ownerless polling lifecycle. Full-target compilation and zero symbol references are the closure evidence. | L obsolete UI-test helper; Process/Tooling. | completed |
| SYNC-034V | `FlowTabUITests+WorkflowWindowObservation.waitForExactFrontmostWorkflowCGWindow`; exact persistent fixture-window readback | A used raw 100ms RunLoop loop starts at each caller and infers that the expected fixture window is frontmost from elapsed observation opportunities. | Reuse the SYNC-034Q generation-owned observer. Register workspace activation plus target-process AX focused/main-window notifications and the named serial conditional-readback cadence before an immediate initial readback. Accept only the exact frontmost bundle identifier plus exact topmost on-screen CGWindowID. The helper invocation owns registrations, generation, schedule, cancellation, and watchdog final-readback diagnostics. | H exact window-identity UI Oracle; deterministic initial/event/delayed/cancel/watchdog tests, 100 lifecycle Pressure, affected global/in-app/search fixture UI, Process/Tooling. | blocked: implementation and complete UI-test target build passed; system authentication prevents XCTest initialization before owner and affected UI tests |
| SYNC-034W | `FlowTabUITests+WorkflowSpaceWindowObservation`, `waitForFrontmostWorkflowSpaceCGWindow`; exact frontmost fullscreen-Space fixture window | A used raw 100ms RunLoop loop starts after fixture setup and infers that the expected fullscreen sibling is frontmost from elapsed observation opportunities. Its CGWindowID is not known at this boundary. | Start a narrow generation-owned owner with workspace activation, target-process AX focused/main-window notifications, and the named serial conditional-readback cadence registered before the immediate readback. Accept only the exact frontmost bundle plus a topmost CG window whose title matches or whose titleless frame satisfies the established fullscreen-Space geometry contract, and return that exact window evidence. The helper invocation owns all registrations, schedule, generation, cancellation, and watchdog diagnostics. | H fullscreen-Space UI Oracle; deterministic initial/event/titleless-fullscreen/delayed/cancel/watchdog tests, 100 lifecycle Pressure, affected Option+Tab/Control+Tab/window-search fixture UI, Process/Tooling. | blocked: implementation and complete UI-test target build passed; system authentication prevents XCTest initialization before owner and affected UI tests |
| SYNC-034X | `FlowTabUITests+WorkflowWindowObservation.waitForActiveSpaceWorkflowCGWindow(windowNumber:title:app:timeout:)`; obsolete exact-ID active-Space loop | A raw 100ms RunLoop loop remains as an overload even though semantic call-site review finds no caller supplying `windowNumber`. Obsolete test infrastructure. | Remove the unreferenced overload and its ownerless polling lifecycle. Full-target compilation and zero symbol references are the closure evidence. | L obsolete UI-test helper; Process/Tooling. | completed |
| SYNC-034Y | `FlowTabUITests+WorkflowSpaceWindowObservation`, `waitForActiveSpaceWorkflowCGWindow(title:app:timeout:)`; active-Space topmost fullscreen fixture window | A used raw 100ms RunLoop loop begins after the FlowTab panel becomes ready and infers that the expected fixture fullscreen Space remains active. FlowTab may be the system-frontmost application at this boundary. | Reuse the generation-owned workflow-Space window owner with an explicit `activeSpace` scope. Register target-process AX focused/main-window events, workspace activation, and the named serial conditional-readback cadence before the immediate readback. Accept only a topmost target-process CG window whose title matches or whose titleless frame satisfies the established fullscreen-Space geometry contract; preserve the `frontmost` scope's exact bundle requirement for SYNC-034W. The helper invocation owns all observation inputs, generation, cancellation, and watchdog diagnostics. | H active-Space UI Oracle; deterministic scope/initial/event/titleless-fullscreen/delayed/cancel/watchdog tests, 100 lifecycle Pressure, affected Option+Tab/Control+Tab/window-search fixture UI, Process/Tooling. | blocked: implementation and complete UI-test target build passed; system authentication prevents XCTest initialization before owner and affected UI tests |
| SYNC-034Z | `FlowTabUITests+WorkflowSpaceWindowCollectionObservation`, `waitForWorkflowSpaceContainingCGWindow`; noisy active-Space fixture-window collection | A raw 100ms RunLoop loop starts after fixture launch or panel presentation and scans every target-process on-screen CG window until one matches the expected title or titleless fullscreen geometry. The matching fixture window may sit behind another sibling. | Start a generation-owned collection observer with workspace activation, target-process AX focused/main-window notifications, and the named serial conditional-readback cadence registered before the immediate full-collection readback. Accept any exact member matching the title or established titleless fullscreen-frame contract; preserve collection ordering only as diagnostic evidence. The helper invocation owns registrations, schedule, generation, cancellation, and watchdog final-collection diagnostics. | H multi-window active-Space UI Oracle; deterministic initial/non-topmost/event/titleless-fullscreen/delayed/cancel/watchdog tests, 100 lifecycle Pressure, affected noisy Option+Tab/Control+Tab/window-search fixture UI, Process/Tooling. | blocked: implementation and complete UI-test target build passed; system authentication prevents XCTest initialization before owner and affected UI tests |
| SYNC-034AA | `FlowTabUITests+Settings`, `FlowTabUITests+AverageLuminanceObservation`; Settings theme screenshot-luminance publication | Two raw 100ms RunLoop loops begin after selecting light or dark appearance and repeatedly sample the Settings screenshot until a threshold matches. | Start a generation-owned luminance observer before each theme selection and gate success until the action returns. Perform an immediate trigger readback, then retain the shared named serial XCUI cadence because screenshot pixels expose no publication callback. Accept only an existing exact Settings element whose sampled average luminance satisfies the requested threshold. The helper invocation owns generation, scheduling, cancellation, and watchdog final-readback diagnostics. | H visible Settings appearance Oracle; deterministic initial/trigger/delayed/cancel/watchdog tests, 100 lifecycle Pressure, affected theme/language Settings UI, Process/Tooling. | blocked: implementation, fixed-path app installation, and complete UI-test target build passed; XCTest automation initialization timed out before owner or affected UI test methods |
| SYNC-035 | Direct UI settle waits in Search, Settings, Home/Logs, MRU, Space fixture and switcher workflow tests; files enumerated in the UI audit scope below | Fixed 80ms–1.2s RunLoop advances occur between input/action and assertion, so assertion timing can change results. Evidence migration. | Remove each settle wait in favor of the affected visible element, log marker, fixture generation, process state, exact frontmost CG/AX window, or nonexistence Oracle. Observer/baseline setup precedes the action. | H; affected UI suites and matching Behavior coverage. | in progress; SYNC-035A, SYNC-035B, and the Logs projection settle path are completed, with remaining owners split into later slices |
| SYNC-035A | `FlowTabUITests+SystemAppMRU.dismissSwitcherAndWait`; switcher dismissal between repeated MRU triggers | A fixed 300ms RunLoop advance after Escape assumes the previous panel has disappeared before the next trigger. | Establish an XCTest nonexistence expectation for the exact switcher summary before Escape, then require that persistent UI state to become absent. The named dismissal watchdog is only a failure bound and reports the final switcher hierarchy. The helper invocation owns the expectation. | H repeated UI presentation; System MRU UI and repeated-path Pressure, Process/Tooling. | completed |
| SYNC-035B | `FlowTabUITests+Support.commitEditing`, `+ElementValueObservation.assertTriggerMakesValue`, and `testSettingsWindowBehaviorDelayAndTogglesPersistAcrossRelaunch`; delay-input commit | A fixed 200ms RunLoop advance after Tab assumes AppKit ended editing, normalized the value, and republished its accessibility value. | Start the generation-owned element-value observer before Tab, reject a matching baseline until the trigger returns, and accept only the exact normalized `1.23` accessibility readback. XCUI exposes no value-publication callback, so retain the shared serial named cadence. The helper invocation owns cancellation; its watchdog is solely a failure bound with acceptance state and last exact value. | H Settings UI commit Oracle; deterministic owner regression, affected Settings UI, Process/Tooling. | completed |
| SYNC-036 | All literal XCTest timeouts in `FlowTabTests` and `FlowTabUITests` | 606 literal durations are generally terminal bounds for an independent expectation or XCUI predicate, but policy ownership and diagnostic tiers are implicit. Watchdog. | Replace literals with named app-test and UI-test watchdog policies by operation class; preserve expectation/predicate success Oracles and include unmet condition plus last observation in custom waits. Test case/helper owner supplies cleanup. | M mechanical/test infra; Unit/Behavior/UI, Process/Tooling. | planned |
| SYNC-037 | `scripts/perf/tab-switch-stress.sh`, `search-committed-index-pressure.sh`, `runtime-topology-pressure.sh`, `lib/runtime-topology-target.sh` | Sampling duration/cadence and identity stability windows are pressure/safety protocols; process termination loops use unnamed 100ms cadence and attempt bounds. Domain duration/conditional observation/watchdog. | Retain measurement durations and sample cadence as named protocol inputs. Name process polling cadence/watchdogs, check state immediately, terminate from PID/start-identity/readback, and report the final `ps`/identity/status evidence. Traps own cancellation and cleanup. | M tooling/hot path; Pressure and Process/Tooling. | verification-needed |
| SYNC-038 | `scripts/release/release-install.sh`, `scripts/release/uninstall-flowtab.js` | A fixed one-second delay assumes FlowTab exited before replacement or deletion. Evidence migration. | Wait on exact process absence/identity readback immediately after quit/TERM, with a named watchdog and last PID/state diagnostic before mutating installed resources. The install/uninstall command owns cleanup. | M release tooling; Process/Tooling and release contract tests. | planned |
| SYNC-039 | `RuntimeWindowRecencyTracker`; semantic fallback age and generation age | A 300-second age is an explicit expiry rule for weak semantic identity; exact identity remains preferred. Domain duration. | Retain injected clock, maximum generation age, exact-window identity precedence, and deterministic expiry tests. Tracker owns records and pruning. | H identity semantics; Unit, Behavior, relevant UI only if implementation changes. | closed-retained |

## UI Fixed-Settle Audit Scope

SYNC-034 and SYNC-035 cover the direct RunLoop waits found in:

- `FlowTabUITests+HomeAndLogs.swift`
- `FlowTabUITests+ScrollingSupport.swift`
- `FlowTabUITests+Settings.swift`
- `FlowTabUITests+SettingsSearch.swift`
- `FlowTabUITests+SpaceFixtureApp.swift`
- `FlowTabUITests+SpaceFixtureEdgeInputsAssertions.swift`
- `FlowTabUITests+SpaceFixtureEdgeInputsWorkflow.swift`
- `FlowTabUITests+SpaceFixtureInAppWindowSwitcher.swift`
- `FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift`
- `FlowTabUITests+SpaceFixtureOptionTabNoisyRoundTrip.swift`
- `FlowTabUITests+SpaceFixtureOptionTabSpaceBacked.swift`
- `FlowTabUITests+SpaceFixtureRuntimeTruthEntrypoints.swift`
- `FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift`
- `FlowTabUITests+SpaceFixtureWorkflow.swift`
- `FlowTabUITests+StatusItem.swift`
- `FlowTabUITests+Support.swift`
- `FlowTabUITests+SwitcherAndSearch.swift`
- `FlowTabUITests+SwitcherInteractionRegressions.swift`
- `FlowTabUITests+SystemAppMRU.swift`
- `FlowTabUITests+WorkflowWindowObservation.swift`

Every call site will be closed as one of:

1. removed in favor of an event/notification/generation/process/window Oracle;
2. routed through the shared conditional observer because the platform exposes
   no usable event; or
3. retained as a named domain duration or terminal watchdog with explicit
   ownership and deterministic strategy.

## Dependency Order

1. Deterministic runtime evidence and shared generations: SYNC-001–SYNC-006.
2. App projection, permission, and view lifecycle consumers:
   SYNC-009–SYNC-013, the split Home contracts SYNC-040–SYNC-041, then
   SYNC-014.
3. Search, hotkey, panel, and window-layer orchestration:
   SYNC-015–SYNC-025.
4. Fixture and TestingSupport readiness: SYNC-026–SYNC-031.
5. App/UI test observation and watchdog infrastructure:
   SYNC-032–SYNC-036.
6. Pressure/release tooling: SYNC-037–SYNC-038.
7. Re-run the complete source audit and confirm all retained policies,
   including SYNC-007, SYNC-008, and SYNC-039.

Dependencies may force a later row to add its helper before an earlier consumer
is closed. Each commit still contains only one synchronization contract under
one lifecycle owner.

## Per-Slice Closure Record

When a row moves to `completed` or `blocked`, append these fields to the row or
an immediately following note:

- production/test design and independent Oracle;
- cancellation and cleanup owner;
- retained duration/watchdog policy and last-observation diagnostic;
- targeted validation commands and results by Unit, Behavior, UI, Pressure,
  and Process/Tooling;
- local commit SHA.

The final source audit must find no unclassified duration, wait, retry,
polling cadence, deadline, or timeout in the scoped paths.

### SYNC-001 Closure Record

- Design and Oracle: each named scan policy owns a deterministic element-ID
  range. The resolver publishes `complete(scanned:)` only after visiting the
  whole range, and publishes `unavailable` when the private resolver symbol
  cannot supply observations. Window absence remains authoritative only for a
  completed scan.
- Lifecycle: the synchronous resolver invocation owns the bounded traversal.
  This slice adds no observer, timer, retry, wait task, or production watchdog.
- Retained time policy: none in the production contract. Test semaphore
  deadlines are terminal failure watchdogs around event-driven
  suspend/resume evidence.
- Unit: three deterministic scan-policy, full-traversal, and
  suspend/resume tests passed in
  `.build-local/evidence-driven-sync/SYNC-001/flowtabtests-targeted-attempt-001`.
- Behavior: six inspector, absence-authority, remote-scan-decision, and
  off-Space window-binding tests passed across the targeted and expanded
  FlowTabTests attempts.
- UI and Pressure: the required Noisy Option+Tab real-topology scenario was
  attempted twice. Both attempts built fixtures, signed the runner, and
  produced valid result bundles, then macOS LocalAuthentication returned code
  `-4` (`System authentication is running`) before the test body. Evidence is
  preserved under
  `.build-local/evidence-driven-sync/SYNC-001/pressure-attempt-001` and
  `pressure-attempt-002`.
- Process/Tooling: `git diff --check` passed. The owner-scope source search
  found no elapsed clock cutoff or partial-scan completion path.
- Commit: `695f740` (`refactor(sync): migrate SYNC-001 remote AX scan`).

### SYNC-002 Closure Record

- Design and Oracle: `AppDelegate` installs the PID-scoped AX observation before
  forwarding the workspace launch event. The launch repair supplies the initial
  readback. Each later supported AX window transition supplies evidence for an
  `.axNotification` repair, while a delayed observer installation triggers an
  explicit post-install readback. Early consecutive AX transitions receive
  monotonic generations and use SYNC-004's standard trailing-readback batching.
  Observer callbacks are accepted only from the current context for the exact
  appID/PID.
- Lifecycle: `RuntimeAppLaunchWindowEvidenceCoordinator` owns observer-install
  generation and retry cancellation. Exact appID/PID termination removes one
  observer; stale termination for a reused PID is ignored. App termination
  cancels the PID retry, and AppDelegate termination cancels every retry and
  stops the monitor.
- Retained time policy: the platform exposes no readiness callback for a failed
  AX observer installation, so
  `runtimeAppLaunchObserverInstallRetryIntervalNanoseconds` retains a 250ms
  cancellable condition-observation cadence. Every attempt checks installation
  evidence directly; elapsed time never establishes success. Cancellation logs
  the last AX installation error.
- Unit and Behavior: ten immediate-install, delayed-install/readback,
  consecutive-event, cancellation, shutdown, superseded-generation, PID-reuse,
  AppDelegate-ordering, and projection-repair tests passed in
  `.build-local/evidence-driven-sync/SYNC-002/flowtabtests-targeted-attempt-005`.
  Six existing AX identity and runtime-drainer tests passed in
  `.build-local/evidence-driven-sync/SYNC-002/flowtabtests-expanded-attempt-006`.
- FlowTabCore: not relevant because the contract is owned by AppKit,
  ApplicationServices, AppDelegate, and the app runtime projection boundary.
- UI and Pressure: the real-fixture launch/termination scenario was attempted
  twice through `runtime-topology-pressure.sh`. Both attempts completed fixture
  preparation, fixed-App identity validation, runner signing, and result-bundle
  creation. macOS LocalAuthentication then returned code `-4`
  (`System authentication is running`) before the test body, so no target
  FlowTab process could be bound and no pressure samples could be attributed.
  Evidence is preserved under
  `.build-local/evidence-driven-sync/SYNC-002/pressure-attempt-001` and
  `pressure-attempt-002`; the latter was built from the final slice source
  state with private identity-manifest SHA-256
  `cf855c34361ee17c2309bedb385a0f1aca535e2dc68b02e7916bf07231a2f322`.
- Process/Tooling: `git diff --check` passed. The owner-scope source search
  found no app-launch convergence scheduler, 800ms delay, or delayed
  `.appLaunched` success path.
- Commit: `d267c49` (`refactor(sync): migrate SYNC-002 app launch readiness`).

### SYNC-003 Closure Record

- Design and Oracle: a dirty repair request is read back immediately. A
  non-empty repair result remains the sole success Oracle. An incomplete
  current-app window payload moves the request to `waitingForEvidence`; exact
  AX window, Space-topology, focus, launch, and lifecycle signals make it
  pending for an immediate readback. Unrelated app-switcher maintenance cannot
  advance it. Request ID and attempt reject stale or out-of-order callbacks,
  while exact appID/PID prevents a stale termination from cancelling a reused
  PID's request.
- Lifecycle: `RuntimeProjectionService` owns
  `RuntimeTransientRepairObservationDriver` on its maintenance queue. The
  driver owns both scheduled readbacks and the watchdog. Completion, matching
  evidence, request replacement, search-barrier promotion, exact app
  termination, and service deinitialization cancel the applicable work.
- Retained time policy: the platform does not expose a completion callback for
  an AX repair payload that is transiently empty. The named condition cadence
  is 100ms, 300ms, then 800ms repeated. It only requests another readback. A
  30-second watchdog is the terminal failure bound for one uninterrupted
  incomplete-evidence session; expiry cancels polling, preserves the stale
  projection state, and reports request ID, target, appID, attempt, the unmet
  non-empty-payload condition, the last transient-empty payload, and
  `lastObservedAt`.
- Unit and Behavior: fifteen immediate-readback, active condition-readback,
  event delivery, stale/out-of-order callback, cancellation, lifecycle,
  PID-reuse, priority, search-freshness, full-repair, cadence, and watchdog
  tests passed in
  `.build-local/evidence-driven-sync/SYNC-003/flowtabtests-targeted-attempt-010`.
  The complete `FlowTabPriorityCoverageTests` suite passed 526/526 in
  `.build-local/evidence-driven-sync/SYNC-003/flowtabtests-expanded-attempt-011`.
- FlowTabCore: not relevant because the contract is owned by the app runtime's
  AX/AppKit projection boundary and does not change the pure Core package.
- UI and Pressure: the final-source Noisy Option+Tab real-topology pressure
  attempt completed fixture preparation, fixed-App identity validation,
  current-source app installation, runner build/signing, and valid result
  bundle creation. macOS LocalAuthentication then returned code `-4`
  (`System authentication is running`) before the test body. No target FlowTab
  process could be bound and zero pressure samples were attributed. Evidence is
  preserved under
  `.build-local/evidence-driven-sync/SYNC-003/pressure-final-attempt-009`; its
  private fixed-App identity-manifest SHA-256 is
  `04c8a53b4b91212f5faa7b63c1883cacfcd6c1b19f8db3babd94d4e46d672ce4`.
- Process/Tooling: `git diff --check` and project-file `plutil -lint` passed.
  The owner-scope search found no `notBefore`, time-ready request selection,
  retry-exhaustion success/fallback, or legacy retry-policy symbol.
- Commit: `de5f778`
  (`refactor(sync): migrate SYNC-003 transient repair readiness`).

### SYNC-004 Closure Record

- Design and Oracle: `RuntimeAXWindowChangeMonitor` binds the PID generation
  and installs its observer before taking the initial `kAXWindows` readback.
  That readback compares every public switchable AX element with a distinct
  exact element in the existing live registry, while allowing the registry to
  contain remote AX windows that the public attribute omits. A matching
  baseline requires no repair. A changed or unavailable baseline and each
  observed AX transition request reconciliation; the consumer's projection
  and exact-window readback remain the sole success Oracles. Notification
  generations are monotonic per current appID/PID binding, and a quiet burst
  publishes one trailing evidence value with the latest generation and
  observed-transition count.
- Lifecycle: `RuntimeAXWindowChangeMonitor` owns AX observer registration,
  per-window notification registration, exact appID/PID bindings, and removal.
  `RuntimeAXWindowChangeDeliveryCoordinator` owns binding generations and one
  cancellable trailing task per PID. Unbind, monitor stop, PID reuse, task
  cancellation, and stale binding generations cancel or reject pending
  delivery.
- Retained time policy: `standardCoalesced` names a 160ms trailing batching
  cadence. Each new transition cancels and replaces the pending task, and an
  injected scheduler makes cancellation deterministic in tests. Scheduler
  delay changes only when the trailing readback is requested; completion and
  success remain defined by the resulting projection/window evidence.
- Unit and Behavior: the final 14-test focused set passed 14/14, covering exact
  initial identity, public-AX subset semantics, changed/unavailable readback,
  first-event capture, single and burst delivery, generation ordering,
  cancellation, stop, and PID rebinding in
  `.build-local/evidence-driven-sync/SYNC-004/flowtabtests-targeted-attempt-022`.
  The final complete `FlowTabPriorityCoverageTests` suite passed 540/540 in
  `.build-local/evidence-driven-sync/SYNC-004/flowtabtests-expanded-attempt-023`.
- FlowTabCore: not relevant because this synchronization contract belongs to
  the AppKit/ApplicationServices runtime projection boundary.
- UI: the real Home fixture mutation path
  `testRuntimeLifecycleRefreshesRealFixtureWindowSetMutation` passed 1/1 in
  23.305 seconds under
  `.build-local/evidence-driven-sync/SYNC-004/ui-home-mutation-attempt-017`.
  Permission validation reused the same prelaunched FlowTab process so every
  assertion remained bound to the tested app identity.
- Pressure: the canonical noisy-CG-sibling, cross-Space fullscreen Option+Tab
  workflow passed 1/1 in 49.844 seconds under
  `.build-local/evidence-driven-sync/SYNC-004/pressure-final-attempt-018`.
  The exact fixed-App identity contract matched across 70 checks and 5,047.861
  milliseconds, with 26 candidate observations and zero rejected transient
  identities. Resource sampling recorded CPU average/p95/max
  30.99/55.70/71.40 percent and RSS average/p95/max
  169.65/241.41/269.47 MiB. The private identity-manifest SHA-256 is
  `6d859fff6486a2b16b955d2e8739f5b9fce4a434a392d9a14a2064d635aeb800`.
- Process/Tooling: `git diff --check` and project-file `plutil -lint` passed.
  Owner-scope search found no warm-up timestamp, elapsed throttle, or
  zero-cadence delivery branch; the sole scheduled duration is the named,
  injected trailing batching policy.
- Commit: `8b593e8`
  (`refactor(sync): migrate SYNC-004 AX window evidence delivery`).

### SYNC-005 Closure Record

- Design and Oracle: the bridge issues the two existing Chrome window-index
  focus requests and `activate`, then immediately returns Chrome's exact
  front-window ID. The bridge accepts only equality with the requested Chrome
  window ID. A different ID, missing/invalid result, or AppleScript execution
  error remains explicit evidence for `RuntimeActivator`, whose existing exact
  AX/CG `verifyFocusAttempt` readback is the final activation Oracle. SYNC-006
  owns any later convergence for the activation request.
- Lifecycle: one synchronous bridge invocation owns one command/readback
  transaction. It allocates no observer, timer, retry, asynchronous task, or
  watchdog. `RuntimeActivator` owns the surrounding activation generation and
  its subsequent cancellation.
- Retained time policy: none in this bridge contract. Machine scheduling and
  Chrome event handling can change command completion latency; acceptance
  remains determined by the exact returned window ID.
- Unit and Behavior: the final nine-test focused set passed 9/9, covering
  generated AppleScript compilation and command/readback ordering, exact and
  mismatched IDs, execution failure, empty/invalid readback, browser
  applicability, and ambiguous/candidate identity rules in
  `.build-local/evidence-driven-sync/SYNC-005/flowtabtests-targeted-attempt-002`.
  The final complete `FlowTabPriorityCoverageTests` suite passed 542/542 in
  18.292 seconds under
  `.build-local/evidence-driven-sync/SYNC-005/flowtabtests-expanded-attempt-003`.
- FlowTabCore: not relevant because this contract belongs to the
  AppKit/AppleScript runtime activation boundary.
- UI and Pressure: the canonical noisy-CG-sibling, cross-Space fullscreen
  Option+Tab workflow passed 1/1 in 51.205 seconds under
  `.build-local/evidence-driven-sync/SYNC-005/pressure-attempt-006`. It
  validates the downstream exact-window activation/readback topology with the
  isolated Chrome-shaped fixture while leaving personal Chrome state
  untouched. The fixed-App identity contract matched across 72 checks and
  5,047.456 milliseconds, with 23 candidate observations and zero rejected
  transient identities. Resource sampling recorded CPU average/p95/max
  34.46/61.20/66.60 percent and RSS average/p95/max
  169.28/238.70/283.23 MiB. The private identity-manifest SHA-256 is
  `4af743703ca0a86772a81f728b4ed64f33a1c8672343b77894f1f4ed4040e1fc`.
  Attempt 005 independently reached exact AX focus verification, then its
  existing binding-transition log assertion missed the expected diagnostic;
  the clean retry closed the same path with the same source state.
- Process/Tooling: `git diff --check` and project-file `plutil -lint` passed.
  Owner-scope search found no bridge propagation duration or AppleScript
  `delay`; `NSAppleScript(source:)` compiled the generated script in the
  focused test.
- Commit: `dfc3389`
  (`refactor(sync): migrate SYNC-005 Chrome focus readback`).

### SYNC-006 Closure Record

- Design and Oracle: `RuntimeFocusRecoveryCoordinator` installs exact-PID app
  activation and termination observers plus active-Space and exact-app
  projection observers before the first activation request. It then performs
  an immediate readback. Every observed event requests another readback; only
  the named condition-polling fallback may reissue the existing recovery
  action. Success requires the exact requested AX/CG identity to be read back
  as focused, or as the frontmost valid CG window when AX focus evidence is
  unavailable. `RuntimeWindowFocusReadbackEvidence` carries the same atomic
  AX/CG observation from verification into projection reporting, so a second
  accessibility query cannot discard already-observed exact focus.
- Lifecycle: `RuntimeActivator` owns one coordinator and activation
  generation. The coordinator owns its observer registrations, scheduled poll,
  and watchdog. Supersession, exact-PID termination, explicit cancellation,
  successful readback, watchdog expiry, and deinitialization remove observers
  and cancel scheduled work. Stale generations and unrelated PID/appID events
  cannot advance the current request.
- Retained time policy: macOS exposes no target-window activation completion
  callback spanning AX, CG, Space changes, and browser focus. The named
  fallback cadence checks at 50ms, 150ms, then 500ms repeatedly; its scheduler
  is injected and cancellable, and elapsed time never establishes success. A
  five-second watchdog performs a final readback and then reports the unmet
  exact-target condition together with the last AX/CG observation.
- Unit and Behavior: the final focused set passed 15/15 in 0.365 seconds,
  covering initial-state completion, observer-before-action ordering, exact
  event delivery, unrelated/duplicate/out-of-order rejection, fallback
  cadence, cancellation, termination, supersession, watchdog diagnostics,
  slow scheduling, projection orchestration, and single-read exact-evidence
  propagation under
  `.build-local/evidence-driven-sync/SYNC-006/flowtabtests-focused-attempt-010`.
  The complete `FlowTabPriorityCoverageTests` suite passed 553/553 in 17.954
  seconds under
  `.build-local/evidence-driven-sync/SYNC-006/flowtabtests-priority-attempt-011`.
- FlowTabCore: not relevant because this contract belongs to the
  AppKit/ApplicationServices runtime activation and projection boundary.
- UI: the exact-window activation workflow passed 1/1 in 51.121 seconds under
  `.build-local/evidence-driven-sync/SYNC-006/ui-activation-attempt-013`.
  The installed fixed app was rebuilt from the final source state and validated
  against private identity-manifest SHA-256
  `65f73336adbba72ab1c9c8554952797e113bb85ef23ba377d5880d21550f49bc`.
- Pressure: the canonical noisy-CG-sibling, cross-Space fullscreen Option+Tab
  workflow passed 1/1 in 55.787 seconds under
  `.build-local/evidence-driven-sync/SYNC-006/runtime-topology-pressure-attempt-016`.
  The exact fixed-App identity contract matched across 79 checks and 5,009.848
  milliseconds, with 23 candidate observations and zero rejected transient
  identities. Resource sampling recorded CPU average/p95/max
  31.29/54.40/65.30 percent and RSS average/p95/max
  170.48/258.70/291.58 MiB.
- Process/Tooling: `git diff --check` and project-file `plutil -lint` passed.
  Owner-scope search found no legacy recovery-delay policy or retry-chain
  symbol. The retained poll cadence and watchdog are named, injected,
  cancellable policies whose tests advance by explicit scheduler delivery.
- Commit: `96daf6f`
  (`refactor(sync): migrate SYNC-006 activation convergence`).

### SYNC-009 Closure Record

- Design and Oracle: `RuntimeLogFileStore` publishes monotonic append, durable
  flush, and successful clear generations from its serialized storage queue.
  `RuntimeLogLinesViewModel` installs the observer before capturing its
  baseline generation and requesting the initial readback. Later generations
  are coalesced while a read is in flight; a read started for stale evidence
  cannot replace lines from a newer generation. The independently read and
  level-filtered persisted lines remain the only UI-content Oracle.
- Lifecycle: the diagnostics store owns observer registration and serialized
  removal. The view model owns one observation token, one coalesced reload
  task, and a view-lifecycle generation. Stop, disappearance, deinitialization,
  restart after a level change, and stale generations cancel or reject work.
  Clear keeps the established observer, applies only its returned clear
  generation, and verifies subsequent content through a new readback.
- Retained time policy: none. The former one-second refresh cadence was
  removed. XCTest and XCUI watchdogs terminate failed assertions; they never
  establish append, clear, or display success.
- Unit and Behavior: the final-source focused observation set passed 4/4 under
  `.build-local/evidence-driven-sync/SYNC-009/flowtabtests-targeted-attempt-023`.
  It covers observer-before-read ordering, an initially satisfied state,
  append/flush/clear generation ordering, clear readback, continued
  subscription after clear, cancellation, and stale, duplicate, out-of-order,
  and slow-read evidence. The complete `FlowTabTests` suite passed 252/252
  under
  `.build-local/evidence-driven-sync/SYNC-009/flowtabtests-full-attempt-021`;
  the complete `FlowTabPriorityCoverageTests` suite passed 553/553 under
  `.build-local/evidence-driven-sync/SYNC-009/flowtabtests-priority-attempt-022`.
- FlowTabCore: not relevant because this synchronization contract belongs to
  the app diagnostics storage and SwiftUI view-lifecycle boundary.
- UI: the visible Logs-page append path passed 1/1 in 11.696 seconds under
  `.build-local/evidence-driven-sync/SYNC-009/ui-live-log-attempt-014`.
  The test observes seeded persisted content, clears to the empty-state
  readback, emits a runtime log stimulus, and succeeds only when the exact new
  accessibility row appears while the page remains visible.
- Pressure: the canonical Logs-page lifecycle workload passed for 60 seconds
  at a 20ms switch cadence under
  `.build-local/evidence-driven-sync/SYNC-009/tab-switch-pressure-attempt-019-60s-20ms`.
  It completed 122 resource samples with CPU average/p95/max
  58.00/62.30/76.60 percent and RSS average/p95/max
  107.72/119.64/119.84 MiB. The last 30 seconds had a negative RSS slope; the
  last 20 seconds stabilized at 108.47 MiB with a 0.0091 MiB/sample slope.
  Same-machine parent-commit repetitions selected the same approximately
  90–121 MiB allocator high-water range, while current and parent CPU averages
  remained within 0.6 percentage points.
- Process/Tooling: the final app source built through the fixed-app installer
  and the pressure harness. `git diff --check` and project-file `plutil -lint`
  passed. Owner-scope search found no Logs-content polling interval or refresh
  sleep; the remaining diagnostic-session expiration wakeup belongs to
  SYNC-010.
- Commit: `d9bf79a`
  (`refactor(sync): migrate SYNC-009 runtime log observation`).

### SYNC-010 Closure Record

- Design and Oracle: `RuntimeDiagnosticSessionDeadlineCoordinator` replaces
  the one-second view loop with one scheduled next-state deadline. It reads an
  injected wall clock immediately when started and after every wake. A wake
  before the persisted expiration schedules the next exact display transition;
  only a clock value at or beyond the persisted expiration invokes session
  cleanup. Delayed scheduling can postpone the UI update, while the stored
  deadline and current clock readback continue to define diagnostic eligibility.
- Lifecycle: `RuntimeLogsSection` owns the coordinator as view state. The
  coordinator owns one cancellable token and one observation generation.
  Session restart, persisted-deadline replacement, user stop, view
  disappearance, deinitialization, and expiration cancel or invalidate the
  token. A stale or cancelled callback cannot clear a newer session.
- Retained time policy: `RuntimeDiagnosticSessionStore.duration` remains the
  15-minute product expiration contract. The named deadline policy retains a
  60-second displayed-minute unit solely to update the existing “about N
  minutes” text at exact value transitions. Neither duration establishes
  success. The injected clock supplies the expiration readback; the injected
  scheduler controls only when that readback occurs.
- Unit and Behavior: the focused deadline/store set passed 7/7 under
  `.build-local/evidence-driven-sync/SYNC-010/flowtabtests-targeted-attempt-002`,
  covering exact countdown transitions, an initially expired state, an early
  wake, a delayed wake, persistence cleanup, cancellation, supersession, and
  stale-callback rejection. Two hosted Logs-view integration tests passed 2/2
  under
  `.build-local/evidence-driven-sync/SYNC-010/flowtabtests-view-attempt-003`.
  The final complete `FlowTabTests` suite passed 258/258 under
  `.build-local/evidence-driven-sync/SYNC-010/flowtabtests-full-attempt-006`;
  the complete `FlowTabPriorityCoverageTests` suite passed 553/553 under
  `.build-local/evidence-driven-sync/SYNC-010/flowtabtests-priority-attempt-007`.
- FlowTabCore: not relevant because this product-duration contract belongs to
  app preferences and the SwiftUI Logs-page lifecycle.
- UI: the real Logs-page workflow passed 1/1 in 35.886 seconds under
  `.build-local/evidence-driven-sync/SYNC-010/ui-diagnostic-session-attempt-002`.
  It independently verifies seeded persisted content and filtering before
  enabling diagnostics, then requires the active-session status to appear,
  requires it to disappear after user cancellation, clears the logs, and
  verifies the cleared state survives relaunch.
- Pressure: 2,000 rapid deadline replacements retained exactly one available
  token; stopping and invoking every stale callback in reverse order produced
  no expiration under
  `.build-local/evidence-driven-sync/SYNC-010/flowtabtests-pressure-attempt-004`.
  The canonical 20-second Logs-page lifecycle workload at a 20ms switch cadence
  also passed under
  `.build-local/evidence-driven-sync/SYNC-010/tab-switch-pressure-attempt-005`.
  Its 42 samples recorded CPU average/p95/max 55.83/62.80/68.30 percent and RSS
  average/p95/max 98.08/117.02/117.17 MiB. The final 20-sample RSS slope was
  -1.014 MiB/sample, matching the same-machine SYNC-009 baseline range without
  warm-state growth.
- Process/Tooling: `git diff --check` and project-file `plutil -lint` passed.
  Owner-scope search found no one-second expiration loop. The only sleep in the
  contract is inside the injected, cancellable deadline scheduler; its result
  is always revalidated by the clock.
- Commit: `6b7a6d2`
  (`refactor(sync): migrate SYNC-010 diagnostic session deadline`).

### SYNC-012 Closure Record

- Design and Oracle: `RuntimePermissionObservationCoordinator` installs its
  app-activation observer before taking the initial TCC readback. A Settings
  permission action starts that observation before issuing the system request,
  then takes an independent request-return readback. App activation and the
  fallback cadence only trigger further readbacks; a `true` accessibility or
  screen-capture readback is the sole success Oracle. Scheduling delay can
  postpone the visible update without changing the permission result.
- Lifecycle: `AppSettingsView` owns one coordinator as view state. Each target
  has an observation generation, fallback token, and watchdog token; both
  targets share one generation-guarded activation subscription. Supersession,
  Settings deactivation, view disappearance, success, watchdog expiration,
  cancellation, and coordinator deinitialization cancel or invalidate every
  owned resource. Cancelled and out-of-order callbacks cannot update a newer
  observation.
- Retained time policy: TCC provides no unified permission-transition
  notification, so the named 500ms fallback cadence is retained as controlled
  condition polling. It follows the immediate readback, is cancellable, and is
  owned by the observation coordinator. The 20-second request watchdog is only
  a terminal failure bound; its final readback can still succeed after delayed
  scheduling, while failure diagnostics include the unmet target, generation,
  readback count, elapsed time, final evidence, bundle identifier, and bundle
  path. Existing Settings navigation animation remains a presentation
  duration.
- Unit and Behavior: the final focused permission set passed 11/11 under
  `.build-local/evidence-driven-sync/SYNC-012/flowtabtests-targeted-attempt-005`.
  It covers observer-before-readback ordering, an initially satisfied state,
  activation and fallback evidence, independent request readback, cancellation,
  supersession, stale callbacks, both owned-state transitions, delayed
  scheduling, watchdog diagnostics, dynamic fixture readback, and 2,000 rapid
  replacements. The complete `FlowTabTests` suite passed 266/266 under
  `.build-local/evidence-driven-sync/SYNC-012/flowtabtests-full-attempt-006`;
  the complete `FlowTabPriorityCoverageTests` suite passed 553/553 under
  `.build-local/evidence-driven-sync/SYNC-012/flowtabtests-priority-attempt-007`.
- FlowTabCore: not relevant because the permission request, TCC readback,
  Settings lifecycle, and test-fixture boundary all belong to the app target.
- UI: the real Settings permission workflow passed 1/1 under
  `.build-local/evidence-driven-sync/SYNC-012/ui-permission-observation-attempt-003`.
  It starts with two denied statuses, triggers both permission actions, changes
  an external atomic TCC fixture, and requires both exact granted statuses plus
  both `fallbackReadback` evidence logs. Three existing permission action,
  Simplified Chinese status, and English granted-label regressions passed 3/3
  under
  `.build-local/evidence-driven-sync/SYNC-012/ui-settings-permission-regression-attempt-004`.
- Pressure: 2,000 rapid replacements retained exactly one activation
  subscription and one fallback/watchdog pair; cancellation followed by every
  stale callback produced no additional evidence in the focused set. The
  canonical 20-second tab-switch workload at a 20ms cadence passed under
  `.build-local/evidence-driven-sync/SYNC-012/tab-switch-pressure-20ms-attempt-010`.
  Its 41 samples recorded CPU average/p95/max 61.06/66.30/118.30 percent and RSS
  average/p95/max 115.00/140.98/141.08 MB; the final 20-sample RSS slope was
  -0.438 MB/sample. The 50ms comparison passed under
  `.build-local/evidence-driven-sync/SYNC-012/tab-switch-pressure-50ms-attempt-011`
  with CPU 59.55/65.90/85.80 percent, RSS 103.21/128.64/129.16 MB, and a
  -0.686 MB/sample final slope. An exact parent-commit comparison at `6b7a6d2`
  passed under
  `.build-local/evidence-driven-sync/SYNC-012/tab-switch-parent-6b7a6d2-20ms-attempt-012`
  with CPU 60.53/73.50/83.30 percent, RSS 105.78/134.12/135.88 MB, and a
  -0.074 MB/sample final slope. The current and parent CPU averages differ by
  0.53 percentage points, and every warm-state RSS slope is negative.
- Process/Tooling: project-file `plutil -lint`, `git diff --check`, and complete
  app/UI builds passed. Owner-scope search found the legacy Settings
  `PermissionPolling` types, task registry, fixed-attempt loop, and swallowed
  cancellation removed. The remaining sleep is inside the injected,
  cancellable fallback scheduler, and every wake is revalidated by a TCC
  readback. The dynamic UI fixture accepts path intent and resolves an absolute,
  standardized file URL at the TestingSupport resource boundary.
- Commit: `d18d1b5`
  (`refactor(sync): migrate SYNC-012 permission observation`).

### SYNC-011 Closure Record

- Design and Oracle: `HomePermissionObservationOwner` reuses the shared
  `RuntimePermissionObservationCoordinator`. It installs the single
  app-activation subscription before taking immediate accessibility and
  screen-capture readbacks. Initial readback, app activation, and fallback
  delivery only request another readback; an exact changed TCC value is the
  sole state-transition Oracle. `HomeLandingView` publishes that evidence to
  its banner, sidebar permission status, runtime-summary refresh, AX-window
  monitor ownership, and static Home cache.
- Lifecycle: Home active visibility starts the owner and inactive visibility,
  disappearance, and teardown stop it. The owner manages one observation
  generation per target, two cancellable fallback tokens, and one shared
  activation subscription. Duplicate starts preserve one owned set.
  Cancellation and generation checks reject delayed, duplicate, and stale
  callbacks. The Home view retains its existing runtime projection and exact
  window-identity ownership boundaries.
- Retained time policy: TCC exposes no unified permission-transition callback,
  so `HomePermissionObservationOwner.fallbackReadbackInterval` retains a
  one-second conditional-readback cadence. The coordinator checks both targets
  immediately, owns and cancels the scheduled work, and uses every wake only
  to obtain a fresh TCC value. Home's long-lived observation mode has no
  completion watchdog because it represents current state for the duration of
  visible ownership.
- Unit and Behavior: the final focused set passed 3/3 in 0.043 seconds under
  `.build-local/evidence-driven-sync/SYNC-011/flowtabtests-targeted-attempt-003`.
  It covers observer-before-initial-readback ordering, initial evidence, app
  activation, a 60-second delayed fallback delivered through an injected
  clock/scheduler, visibility cancellation, stale callbacks, duplicate start,
  and 2,000 rapid start/stop cycles. The complete `FlowTabTests` class passed
  269/269 under
  `.build-local/evidence-driven-sync/SYNC-011/flowtabtests-class-attempt-005`;
  the complete `FlowTabPriorityCoverageTests` class passed 553/553 under
  `.build-local/evidence-driven-sync/SYNC-011/flowtabtests-priority-attempt-007`.
  A combined-class attempt retained at
  `.build-local/evidence-driven-sync/SYNC-011/flowtabtests-full-attempt-004`
  passed all 269 `FlowTabTests` and exposed one existing startup-stability
  assertion under cross-class scheduling. The exact assertion passed 1/1
  under
  `.build-local/evidence-driven-sync/SYNC-011/priority-flake-attempt-006`
  before the full Priority class passed cleanly.
- FlowTabCore: not relevant because permission readback, Home visibility, and
  SwiftUI state publication belong to the app target.
- UI: the dynamic Home permission workflow passed 1/1 in 8.431 seconds under
  `.build-local/evidence-driven-sync/SYNC-011/ui-home-permission-observation-attempt-011`.
  It starts with two denied values, observes the visible permission action,
  atomically changes the external TCC fixture, then requires that action to
  disappear and both exact `fallbackReadback` evidence logs to arrive. Four
  existing granted, unavailable-AX, app-directory, and permission-sidebar
  regressions passed 4/4 under
  `.build-local/evidence-driven-sync/SYNC-011/ui-home-permission-regressions-attempt-012`.
- Pressure: the owner-level 2,000-cycle test retained one activation
  subscription and two fallback tokens with no stale publication. The
  canonical 20-second tab-switch workload at 20ms cadence passed with 42
  samples under
  `.build-local/evidence-driven-sync/SYNC-011/tab-switch-pressure-20ms-attempt-013`.
  CPU average/p95/max was 63.73/70.10/90.30 percent and RSS was
  105.10/119.56/120.06 MB. The final 20-sample RSS slope was
  0.013 MB/sample across a 110.16-110.41 MB plateau. The 50ms comparison passed
  with 42 samples under
  `.build-local/evidence-driven-sync/SYNC-011/tab-switch-pressure-50ms-attempt-014`;
  CPU was 63.11/70.00/87.10 percent, RSS was 112.79/125.91/125.94 MB, and the
  final 20-sample slope was 0.050 MB/sample across a 116.31-117.47 MB plateau.
  Against the same-machine SYNC-012 parent baselines, CPU averages increased
  by 2.67 and 3.56 percentage points from the two immediate TCC readbacks per
  Home activation, while RSS p95/max decreased at both cadences and both
  current runs reached stable allocator ranges without continuing growth.
- Process/Tooling: the final app and UI-test targets built through their
  canonical scripts. Project-file `plutil -lint`, `git diff --check`, and
  owner-scope synchronization search passed. `HomeLandingView` no longer owns
  a permission sleep loop, poll task, or raw interval literal. The retained
  cadence is named on the extracted 118-line owner, injected through the
  coordinator scheduler in deterministic tests, and cancelled at the Home
  visibility boundary.
- Commit: `e7b209a`
  (`refactor(sync): migrate SYNC-011 home permission observation`).

### SYNC-013 Closure Record

- Design and Oracle: `HomeInitialProjectionObservationOwner` installs a
  `.runtimeAppSwitcherProjectionDidUpdate` observer filtered to the exact
  runtime projection service object before taking its initial readback or
  requesting maintenance. An initial complete projection is accepted
  immediately. Missing or incomplete evidence triggers maintenance followed
  by an independent request-return readback, closing synchronous completion
  races. Later readbacks apply only when the projection becomes available, the
  source-generation vector advances monotonically, or the same generation
  changes from incomplete to complete. Duplicate, regressed, unrelated-object,
  and out-of-order observations cannot change Home state.
- Lifecycle: Home active visibility starts one observation generation.
  Inactive visibility, disappearance, completion, supersession, and owner
  deinitialization remove its notification token and invalidate stale
  generations. `HomeLandingView` applies accepted evidence to app summaries,
  loading state, selection, cache pruning, and the AX window monitor while
  preserving the existing projection service and exact window-identity
  boundaries.
- Retained time policy: this contract retains no duration. The 900ms startup
  delay was removed. Readiness succeeds only from a projection-backed,
  complete readback. The visible Home lifetime bounds the consumer
  observation; the runtime projection repair watchdog and its last-evidence
  diagnostics remain owned by the underlying SYNC-003 repair contract.
- Unit and Behavior: the final focused owner/lifecycle set passed 7/7 under
  `.build-local/evidence-driven-sync/SYNC-013/flowtabtests-final-attempt-015`.
  It covers initially satisfied evidence, observer-before-trigger ordering,
  synchronous request completion, exact-object filtering, monotonic
  generations, same-generation completeness, duplicate and regressed
  notifications, visibility cancellation, and late-event rejection. A
  combined-class run exposed a test-side pre-inactive readback baseline and
  the previously recorded AppDelegate startup-stability scheduling
  sensitivity; both exact tests passed 2/2 after the test Oracle was anchored
  after inactive-state completion under
  `.build-local/evidence-driven-sync/SYNC-013/flowtabtests-flake-check-attempt-006`.
  The complete `FlowTabTests` class passed 270/270 under
  `.build-local/evidence-driven-sync/SYNC-013/flowtabtests-class-attempt-007`;
  the final complete `FlowTabPriorityCoverageTests` class passed 558/558 under
  `.build-local/evidence-driven-sync/SYNC-013/flowtabtests-priority-attempt-016`.
- FlowTabCore: not relevant because Home visibility, SwiftUI state
  publication, and runtime projection consumption belong to the app target.
- UI: the initial Home app-order/zero-count path and the Home overview
  counts/stats/permission-sidebar path passed 2/2 in 23.646 seconds under
  `.build-local/evidence-driven-sync/SYNC-013/ui-home-initial-attempt-009`.
  Their success Oracles are the exact visible app rows, counts, statistics,
  and permission elements.
- Pressure: 2,000 rapid owner replacements passed in 0.007 seconds under
  `.build-local/evidence-driven-sync/SYNC-013/owner-pressure-attempt-013`.
  One exact-object notification produced one readback, an unrelated object
  produced none, and a post-stop notification produced none. Canonical noisy
  cross-Space/fullscreen topology runs passed with identical functional
  outcomes at both 20ms and 50ms sampling cadences under
  `.build-local/evidence-driven-sync/SYNC-013/runtime-topology-20ms-attempt-011`
  and
  `.build-local/evidence-driven-sync/SYNC-013/runtime-topology-50ms-attempt-012`.
  The fixed-app identity contract matched all 363 and 297 checks. CPU
  average/p95/max was 100.86/137.40/157.40 and 98.10/137.60/147.60 percent;
  RSS average/p95/max was 186.09/257.86/322.38 and
  180.61/247.77/299.58 MB. A first sandboxed attempt was interrupted by
  `filecoordinationd` and `CoreSimulatorService`; the canonical run completed
  outside that failed environment.
- Process/Tooling: the final app and UI-test targets built through their
  canonical scripts. Project-file `plutil -lint`, `git diff --check`, and
  owner-scope synchronization search passed. The legacy 900ms constant,
  startup sleep, and bootstrapper were removed. `HomeLandingView` is smaller
  than its pre-slice baseline, and the extracted owner remains below the
  source-file size guardrail.
- Commit: `cf6318e`
  (`refactor(sync): migrate SYNC-013 home initial readiness`).

### SYNC-040 Closure Record

- Design and Oracle: `HomeAppSummaryProjectionObservationOwner` installs a
  `.runtimeAppSwitcherProjectionDidUpdate` observer filtered to the exact
  runtime projection service object before taking its baseline readback.
  Committed notification readbacks apply only when the projection becomes
  available, the source-generation vector advances monotonically, or the same
  generation changes from incomplete to complete. Duplicate, regressed,
  unrelated-object, and out-of-order notifications remain observable
  diagnostics without changing Home state. App activation and changed
  permission evidence request service-owned maintenance; an independent
  request-return readback closes synchronous completion races.
- Lifecycle: Home active visibility owns one long-lived observation generation.
  Inactive visibility, disappearance, supersession, and owner deinitialization
  remove the exact notification token and invalidate stale callbacks. The
  initial-readiness owner establishes the long-lived observer from inside its
  accepted completion callback, before releasing its own token, so projection
  commits cannot fall into a handoff gap. AppDelegate remains the workspace
  lifecycle owner and the runtime service remains the projection-commit owner;
  Home consumes their exact committed evidence.
- Retained time policy: the general app-summary contract retains no duration.
  Its 220ms post-signal sleep, refresh task, generic notification publisher,
  and duplicate workspace observers were removed. SYNC-041 subsequently
  removed the selected-app and app-scoped AX refresh delays. Runtime repair
  termination and final-evidence diagnostics remain owned by SYNC-003.
- Unit and Behavior: the final focused owner, lifecycle-handoff, and projection
  reader set passed 10/10 under
  `.build-local/evidence-driven-sync/SYNC-040/flowtabtests-targeted-attempt-003`.
  Coverage includes the observer-before-trigger ordering, initially available
  state, synchronous request completion, exact-object filtering, 64 duplicate
  notifications, monotonic generation acceptance, same-generation
  completeness, regressed evidence, background delivery on the main actor,
  inactive cancellation, and 2,000 rapid restarts with one live subscription.
  The complete `FlowTabTests` class passed 269/269 under
  `.build-local/evidence-driven-sync/SYNC-040/flowtabtests-class-attempt-004`;
  the complete `FlowTabPriorityCoverageTests` class passed 563/563 under
  `.build-local/evidence-driven-sync/SYNC-040/flowtabtests-priority-attempt-005`.
- FlowTabCore: not relevant because Home visibility, service-object
  observation, SwiftUI state publication, and projection maintenance requests
  belong to the app target.
- UI: the new launch-order workflow passed 1/1 in 28.111 seconds under
  `.build-local/evidence-driven-sync/SYNC-040/ui-home-summary-attempt-007`.
  FlowTab stays running while three real fixture apps launch later; the Oracle
  requires every exact app-identity row and window count. The existing
  fixture-first Home workflow passed 1/1 in 29.391 seconds under
  `.build-local/evidence-driven-sync/SYNC-040/ui-home-existing-attempt-008`.
  The first new-path attempt retained at
  `.build-local/evidence-driven-sync/SYNC-040/ui-home-summary-attempt-006`
  showed the permission probe terminating the prelaunched app before the
  assertion. Moving permission validation ahead of fixture launch preserved
  the intended process topology, after which the same product assertion
  passed.
- Pressure: the owner-level 2,000-restart test retained one exact-object
  subscription and published no post-stop evidence. Canonical noisy
  cross-Space/fullscreen topology runs passed with identical four-window
  selection and activation outcomes at 50ms and 20ms sample cadences under
  `.build-local/evidence-driven-sync/SYNC-040/runtime-topology-pressure-050ms-attempt-010`
  and
  `.build-local/evidence-driven-sync/SYNC-040/runtime-topology-pressure-020ms-attempt-011`.
  The 50ms run completed its UI scenario in 53.016 seconds with 280 matched
  identity samples; CPU average/p95/max was 99.59/137.00/153.80 percent and
  RSS average/p95/max was 179.19/270.22/296.94 MB. The 20ms run completed in
  51.484 seconds with 333 matched identity samples; CPU was
  96.61/138.90/148.20 percent and RSS was 166.63/264.72/268.09 MB. Both are
  comparable to the nearest same-machine SYNC-013 topology baselines and show
  the higher sampling pressure changing elapsed work and sample density while
  preserving the functional Oracle.
- Process/Tooling: the app and UI-test targets built through the canonical
  scripts. Project-file `plutil -lint`, `git diff --check`, owner-scope
  synchronization search, and source-size checks passed. The legacy general
  220ms sleep path, generic projection publisher, and dead general-refresh
  reader/policy symbols are absent. `HomeLandingView` decreased from its
  pre-slice line count, and the extracted owner and focused test file remain
  below the source-file size guardrail.
- Commit: `fa8ef7e`
  (`refactor(sync): migrate SYNC-040 home summary updates`).

### SYNC-041 Closure Record

- Design and Oracle: `HomeAppDetailProjectionObservationOwner` installs a
  `.runtimeCurrentAppWindowProjectionDidUpdate` observer filtered to the exact
  runtime projection service object before taking the initial readback and
  before issuing the selected-app, app-window-change, or AX-window-destroyed
  signal. Notification routing additionally requires the exact appID, and a
  readback is accepted only when its summary, candidate, and context identities
  all match that appID. An exact baseline can update Home immediately, while
  the request remains observed until later evidence becomes available, advances
  the source-generation vector monotonically, or changes the same generation
  from incomplete to complete. An independent request-return readback closes a
  synchronous service-completion race. Duplicate, regressed, unrelated-object,
  wrong-app, and wrong-projection-identity evidence cannot change Home state.
- Lifecycle: one Home-owned observation generation exists per appID.
  Supersession cancels only that app, summary projection changes retain only
  still-presented appIDs, and Home inactivity or disappearance cancels all
  observations. The shared notification token is removed when the final
  per-app observation ends and again defensively at owner deinitialization.
  Background runtime commits are delivered on the main actor before SwiftUI
  state publication. The runtime service remains the projection-commit owner,
  and SYNC-003 remains the underlying transient-repair lifecycle/watchdog
  owner.
- Retained time policy: the Home detail consumer retains no duration. The
  120ms selected-app delay, 220ms app-scoped AX delay, and their task
  dictionaries were removed. Completion and UI application depend on exact
  projection readback; runtime repair's named condition cadence and terminal
  watchdog remain classified and owned by SYNC-003.
- Unit and Behavior: the final focused set passed 9/9 under
  `.build-local/evidence-driven-sync/SYNC-041/flowtabtests-targeted-attempt-005`.
  Coverage includes exact service/appID/projection identity, observer-before-
  trigger ordering, synchronous notification and request-return completion,
  complete initial state, newly available and monotonic generation evidence,
  same-generation completeness, 64 duplicate notifications, regression and
  later-incomplete rejection, cancellation, retained-app pruning, main-actor
  delivery, 2,000 rapid supersessions with one live subscription, and inactive
  Home cancellation. The complete `FlowTabTests` class passed 269/269 under
  `.build-local/evidence-driven-sync/SYNC-041/flowtabtests-full-attempt-003`.
  The complete `FlowTabPriorityCoverageTests` class executed 570 tests under
  attempts 002 and 003; all seven SYNC-041 tests passed, while the existing
  `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  observed one duplicate external hotkey reload in suite order. That test
  passed 1/1 in isolation under
  `.build-local/evidence-driven-sync/SYNC-041/priority-existing-failure-rerun-attempt-001`.
  The order-dependent asynchronous test isolation remains assigned to
  SYNC-032/SYNC-033, so the required full Priority layer remains non-green.
- FlowTabCore: not relevant because the contract is owned by the app target's
  Home visibility, Runtime projection notification, and SwiftUI publication
  boundaries.
- UI: the fixed-path signed app was rebuilt successfully from the final
  implementation, and its frozen identity manifest has SHA-256
  `ab689524119b7237d011d45f248ac7c1ff4f5c4b60a878c28e1df113257261f8`.
  Three canonical attempts of
  `testRuntimeLifecycleRefreshesRealFixtureWindowSetMutation` ended before the
  test body with `Timed out while enabling automation mode`, including two
  elevated attempts and one attempt after restarting `testmanagerd`. The
  result bundles and logs are preserved under
  `.build-local/evidence-driven-sync/SYNC-041/ui-runtime-window-mutation-attempt-001`,
  `-002`, and `-003`. They provide runner-environment evidence and no FlowTab
  product assertion, so the required selected-app Home UI layer remains
  blocked.
- Pressure: the owner-level 2,000-supersession test retained one exact-object
  subscription and rejected every stale callback. The fixed-identity real
  topology attempt under
  `.build-local/evidence-driven-sync/SYNC-041/runtime-topology-pressure-050ms-attempt-001`
  remained non-green because UI automation never launched a matching target:
  identity checks and samples were both zero. Independent canonical Home
  lifecycle pressure passed at both 50ms and 20ms switch cadences under
  `.build-local/evidence-driven-sync/SYNC-041/tab-switch-pressure-50ms-attempt-001`
  and
  `.build-local/evidence-driven-sync/SYNC-041/tab-switch-pressure-20ms-attempt-001`.
  The 50ms run completed 20 seconds with app exit status 0 and 43 samples;
  CPU average/p95/max was 65.90/73.30/88.60 percent and RSS was
  107.60/122.52/122.88 MB. The 20ms run also completed with app exit status 0
  and 42 samples; CPU was 68.85/75.40/104.70 percent and RSS was
  115.55/128.28/128.30 MB. Higher scheduling pressure changed resource use
  while preserving the terminal workload result.
- Process/Tooling: the app target and focused/full test targets built through
  canonical scripts. Project-file `plutil -lint`, `git diff --check`, scoped
  fixed-delay/symbol search, and source-size checks passed. The removed
  `HomeRuntimeRefreshReader`, selected/scoped refresh tasks, and 120ms/220ms
  Home detail sleeps are absent. `HomeLandingView` is shorter than its
  pre-slice baseline; the extracted owner and focused test files remain below
  the new-file size guardrail.
- Commit: `113f9bd`
  (`refactor(sync): migrate SYNC-041 home detail updates`).

### SYNC-014 Closure Record

- Design and Oracle: `TemporaryRegularActivationRestorationOwner` installs
  exact-object application and window observers before requesting presentation,
  then takes both an initial readback and an independent presentation-return
  readback. Completion requires the exact readback state: the application is
  active and the target window is visible. App activation/unhide and target
  window key, main, miniaturization, occlusion, and close notifications only
  trigger a fresh readback. Duplicate, unrelated-object, out-of-order, and stale
  generation notifications cannot complete a later activation request.
- Lifecycle: `AppWindowCoordinator` owns one restoration owner and monotonic
  generation. Every new window-opening request cancels the prior observation,
  fallback, and watchdog before installing the next owner. The owner removes
  all exact-object notification tokens and cancels scheduled work on success,
  terminal failure, explicit cancellation, supersession, and deinitialization.
  The AppKit Home window is resolved before the owner starts, preserving the
  observer-before-trigger boundary.
- Retained time policy: a named 20ms fallback cadence remains because AppKit
  does not publish one completion callback covering every relevant application
  activation and window visibility mutation. Each cadence first reads the
  condition immediately, requests presentation only while evidence remains
  incomplete, and completes only from a later exact readback. A named
  five-second watchdog performs a final readback and terminates failure with
  source, elapsed time, app-active, visible, miniaturized, and activation-policy
  evidence. Both policies use injectable scheduler and monotonic-clock
  boundaries; cancellation belongs to the restoration owner.
- Unit and Behavior: the final focused set passed 11/11 under
  `.build-local/evidence-driven-sync/SYNC-014/flowtabtests-targeted-attempt-002`
  (eight owner tests and three status-item orchestration tests). Coverage
  includes initial satisfaction, observer-before-presentation ordering,
  presentation-return completion, exact unrelated/out-of-order/duplicate
  evidence, cancellation, coordinator supersession, conditional fallback
  presentation, watchdog diagnostics, and slow scheduling changing elapsed time
  while preserving the result. The complete `FlowTabTests` class passed 277/277
  under
  `.build-local/evidence-driven-sync/SYNC-014/flowtabtests-unit-full-attempt-001`.
  The complete `FlowTabPriorityCoverageTests` class executed 570 tests under
  `.build-local/evidence-driven-sync/SYNC-014/flowtabtests-priority-full-attempt-001`;
  all three SYNC-014 status-item tests passed, while the existing
  `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  observed one duplicate external hotkey reload in suite order. That test
  passed 1/1 in isolation under
  `.build-local/evidence-driven-sync/SYNC-014/priority-existing-failure-rerun-attempt-001`.
  Its order-dependent asynchronous test isolation remains assigned to
  SYNC-032/SYNC-033, so the expanded full Priority layer remains non-green.
- FlowTabCore: not relevant because the synchronization owner, AppKit evidence
  adapters, and status-item orchestration are app-target responsibilities.
- UI: the fixed-path signed app was rebuilt successfully with executable
  SHA-256
  `a0a2046dbfecc168a5b5397a34d6f25b712f0cd132e6eefc547a08e5389c9376`.
  The canonical
  `testStatusItemReopensLastSelectedTabAfterWindowClose` path passed 1/1 in
  9.609 seconds under
  `.build-local/evidence-driven-sync/SYNC-014/ui-status-item-attempt-002`.
  It verified window closure, another normal Space app becoming frontmost,
  status-item reopening of the previously selected Logs tab, the regular-to-
  accessory activation evidence, and the final FlowTab foreground state. The
  first attempt exposed that this pre-existing log Oracle requested INFO
  logging after resetting preferences without starting a diagnostic session;
  the test launch now establishes that observation precondition explicitly.
- Pressure: the deterministic owner-level 2,000-supersession test passed in the
  focused run, retained exactly one live application/window observation set,
  and delivered no stale outcome. The slow-scheduler test exercised a 100x
  elapsed-time change with the same terminal stable evidence and presentation
  count.
- Process/Tooling: the app, app-test, and UI-test targets built through the
  canonical scripts. Project-file `plutil -lint`, `git diff --check`, scoped
  synchronization search, and source-size checks passed. The legacy polling
  task, 250-attempt counter, and direct success-after-sleep path are absent;
  the remaining sleep is encapsulated by the named cancellable fallback and
  watchdog scheduler.
- Commit: `d30626e`
  (`refactor(sync): migrate SYNC-014 status item activation`).

### SYNC-015 Closure Record

- Design and Oracle: `SwitcherSearchCoordinator` is now the synchronous,
  deterministic search state machine. `LiveSwitcherModel` owns the sole
  `SwitcherSearchSchedulingOwner`, which debounces and executes search work.
  Each request captures the exact query, scope, catalog, searchable index, and
  scheduling revision. A result is published only when the scheduling revision
  remains current and the model readback still matches the captured query,
  scope, and index generation. Scheduler latency can change delivery time
  without becoming a success condition.
- Lifecycle: the model owns one scheduling owner. The owner owns and cancels
  both the pending debounce token and computation token, increments a monotonic
  revision on every request and cancellation, and rejects stale or out-of-order
  delivery. Callback registration closes the synchronous-callback-before-token-
  assignment race for injected schedulers and executors. Token cancellation,
  supersession, explicit model cancellation, and owner deinitialization clean
  up pending work.
- Retained time policy: the initial 20ms debounce and adaptive
  14/25/35/45ms debounce intervals are a named performance policy. The policy,
  scheduler, and monotonic clock are injectable. Computation duration selects
  only the next debounce interval; completion and publication depend on
  revision plus exact model readback. The duplicated coordinator-owned 10ms
  delay and its work-item lifecycle were removed.
- Unit and Behavior: the final focused set passed 11/11 under
  `.build-local/evidence-driven-sync/SYNC-015/flowtabtests-targeted-attempt-004`
  (eight Unit paths and three Priority behavior paths). Coverage includes the
  latest revision, initial synchronous execution, cancellation, duplicate and
  out-of-order completion, synchronous scheduler/executor callbacks, a 100x
  scheduler-latency change with the same result, policy boundaries, and 2,000
  supersessions retaining one current request. The complete `FlowTabTests`
  class passed 283/283 under
  `.build-local/evidence-driven-sync/SYNC-015/flowtabtests-unit-full-attempt-001`.
  The complete `FlowTabPriorityCoverageTests` class executed 570 tests under
  `.build-local/evidence-driven-sync/SYNC-015/flowtabtests-priority-full-attempt-001`;
  all targeted SYNC-015 behavior paths passed, while
  `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  observed the previously recorded duplicate external hotkey reload in suite
  order. Its exact isolated rerun passed 1/1 under
  `.build-local/evidence-driven-sync/SYNC-015/priority-existing-failure-rerun-attempt-001`.
  The order-isolation work remains assigned to SYNC-032/SYNC-033.
- FlowTabCore: not relevant because search state, model publication, and the
  scheduling lifecycle are app-target responsibilities.
- UI: the canonical install script rebuilt and installed the fixed-path signed
  app. `testSearchPanelChineseQueryShowsChineseMockResult` and
  `testSearchPanelEntryAndResultActivation` passed 2/2 in 37.924 seconds under
  `.build-local/evidence-driven-sync/SYNC-015/ui-search-attempt-001`, verifying
  query input, Chinese result publication, exact result activation, and the
  affected visible search path.
- Pressure: realistic Search Pressure passed under
  `.build-local/evidence-driven-sync/SYNC-015/search-pressure-realistic-attempt-002`
  with the conformant `flowtab.search.realistic.v1` rhythm, 44.446 active
  seconds, 71 valid samples, zero cadence gaps, and four successful batches.
  Stress Search Pressure passed under
  `.build-local/evidence-driven-sync/SYNC-015/search-pressure-stress-attempt-001`
  with the conformant `flowtab.search.stress.v1` rhythm, 41.852 active seconds,
  67 valid samples, zero cadence gaps, and two successful batches. Every
  committed-index batch reported `resultState=committedGenerationResult` and
  `freshnessBarrierRequests=0`.
- Process/Tooling: the app and app-test targets built through the canonical
  FlowTabTests wrapper, and the UI target built through the canonical install
  script. Project-file `plutil -lint`, `git diff --check`, scoped stale-symbol
  search, and source-size checks passed. New production and test files remain
  within the 400-line guardrail, while the touched oversized
  `LiveSwitcherModel.swift` shrank by four lines.
- Commit: `76827b2`
  (`refactor(sync): migrate SYNC-015 search scheduling`).

### SYNC-016 Closure Record

- Design and Oracle: `AppDelegate` now publishes
  `HotkeyRegistrationEvidence` only after Command+Tab reconciliation and both
  hotkey monitors have been configured. Each evidence value carries a
  monotonic generation, exact request ID, both requested configurations, and
  the resulting takeover-active readback. `AppSettingsView` prepares its
  observer before persisting or requesting registration and performs an
  independent request-return readback to close synchronous delivery races.
  `HotkeySettingsCardAppKitView` renders pending, active, or inactive solely
  from matching registration evidence.
- Lifecycle: Settings active visibility owns one
  `HotkeyRegistrationObservationOwner`. Starting installs the notification
  token before the initial readback; inactivity and disappearance remove the
  token, clear pending evidence, and advance an observation generation that
  rejects already-queued delivery. The owner accepts only strictly increasing
  evidence generations. Exact request identity or exact configuration
  equality resolves a pending request, while duplicate, regressed,
  out-of-order, and unrelated evidence cannot change the rendered result.
- Retained time policy: the 250ms inactive-status delay, delayed work items,
  and generation tokens were removed. Registration completion is synchronous
  at the AppDelegate owner boundary and therefore needs no watchdog. The
  persisted Command+Tab restoration marker remains the compatibility and crash-
  restoration state owned by `CommandTabTakeoverController`; Settings no
  longer uses it as registration-success evidence.
- Unit and Behavior: the final focused set passed 11/11 under
  `.build-local/evidence-driven-sync/SYNC-016/flowtabtests-targeted-attempt-003`
  (seven Unit paths and four Priority behavior paths). Coverage includes
  observer-before-readback delivery, an already-satisfied exact initial
  request, exact request/configuration matching, duplicate and out-of-order
  rejection, explicit stop/cancellation, scheduler-yield latency equivalence,
  exact AppDelegate publication, and 2,000 monotonic evidence generations.
  After tightening cancellation coverage to reject an already-queued
  notification delivery, the final five owner tests passed 5/5 under
  `.build-local/evidence-driven-sync/SYNC-016/flowtabtests-owner-final-attempt-001`.
  The complete `FlowTabTests` class passed 288/288 under
  `.build-local/evidence-driven-sync/SYNC-016/flowtabtests-unit-full-attempt-001`.
  The complete `FlowTabPriorityCoverageTests` class executed 570 tests under
  `.build-local/evidence-driven-sync/SYNC-016/flowtabtests-priority-full-attempt-001`;
  all four SYNC-016 behavior paths passed, while
  `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  observed the previously recorded duplicate external hotkey reload in suite
  order. Its exact isolated rerun passed 1/1 under
  `.build-local/evidence-driven-sync/SYNC-016/flowtabtests-known-order-isolated-attempt-001`.
  The order-isolation work remains assigned to SYNC-032/SYNC-033.
- FlowTabCore: not relevant because registration, Settings visibility,
  AppKit rendering, and notification publication are app-target boundaries.
- UI: the canonical install script rebuilt and installed the fixed-path signed
  app. The first canonical run ended before the test body when macOS timed out
  enabling automation mode. The elevated second run exposed that the new UI
  assertion read one accessibility property immediately after element
  existence; the Oracle was corrected to wait for the identified status
  element whose label or value contains the active registration evidence.
  `testSettingsCommandTabTakeoverTriggersSwitcherAndRestoresSystemShortcut`
  then passed 1/1 in 40.599 seconds under
  `.build-local/evidence-driven-sync/SYNC-016/ui-settings-command-tab-attempt-003`.
  It verified exact active-registration logging, marker compatibility, visible
  active status, Command+Tab delivery, and system-shortcut restoration after
  exit.
- Pressure: the deterministic 2,000-generation owner test passed in the
  focused run. It preserved the latest matching registration result while
  rejecting every earlier generation. The latency-equivalence test inserted
  additional scheduler yields and produced the same terminal state, so
  scheduling pressure changed delivery time without changing the result.
- Process/Tooling: the app, app-test, and UI-test targets built through the
  canonical scripts. Project-file `plutil -lint`, `git diff --check`, scoped
  stale-delay/symbol search, and source-size checks passed. New production and
  test files remain below the 400-line guardrail; the touched
  `HotkeySettingsCard.swift` shrank from 572 to 519 lines. The startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `aa62c7d`
  (`refactor(sync): migrate SYNC-016 hotkey registration status`).

### SYNC-017 Closure Record

- Design and Oracle: `ModifierReleaseObservationOwner` installs an exact
  modifier/main-key transition observer before its initial hardware readback.
  Matching local/global AppKit events and Carbon hotkey callbacks trigger an
  immediate readback. Selection confirmation requires two stable released-state
  readbacks and a pressed readback resets stability. Session-end replay
  suppression, as closed by SYNC-018, requires one exact released-state
  readback. Both decisions therefore come from current hardware state, while
  duplicate, reordered, and stale transition delivery can only request another
  readback.
- Lifecycle: `SwitcherPanelController` owns one observation owner and one
  observation generation. Each start replaces the prior event token and
  fallback token. Session cancellation, panel dismissal, search transitions,
  replay-suppression completion, and controller release cancel the applicable
  observation; generation checks reject already-queued fallback work. The
  system event-source token removes both local and global event monitors when
  its owner releases it.
- Retained time policy: `ModifierReleaseConfirmationPolicy.sampleInterval`
  remains a named 25ms fallback-readback cadence for an AppKit/global-event
  delivery gap and stale hardware readback. Each readback schedules at most one
  cancellable fallback sample, and matching transition evidence requests the
  readback immediately. Completion remains independent of elapsed duration. A
  held modifier is a valid open-ended input condition, so lifecycle
  cancellation owns termination and a watchdog does not apply.
- Unit and Behavior: the final focused set passed 13/13 under
  `.build-local/evidence-driven-sync/SYNC-017/targeted-attempt-002`
  (seven owner Unit paths and six controller behavior paths). Coverage includes
  observer-before-initial-readback ordering, an initially satisfied condition,
  event-triggered completion, missed-event fallback, pressed-state stability
  reset, duplicate transitions, explicit cancellation, stale-generation
  rejection, synchronous scheduler completion, and 2,000 transition events.
  Two additional interruption and flags-changed behavior paths passed 2/2
  under `.build-local/evidence-driven-sync/SYNC-017/behavior-attempt-001`.
  The complete `FlowTabTests` class passed 295/295 under
  `.build-local/evidence-driven-sync/SYNC-017/full-unit-attempt-001`.
  The complete `FlowTabPriorityCoverageTests` class executed 570 tests under
  `.build-local/evidence-driven-sync/SYNC-017/full-priority-attempt-001`; every
  SYNC-017 path passed, while
  `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  reproduced the registered suite-order failure. Its exact isolated rerun
  passed 1/1 under
  `.build-local/evidence-driven-sync/SYNC-017/priority-known-failure-isolated-001`.
  The order-isolation work remains assigned to SYNC-032/SYNC-033.
- FlowTabCore: not relevant because modifier observation, Carbon/AppKit event
  routing, hardware flag readback, and panel-session ownership are app-target
  boundaries.
- UI: the canonical install script rebuilt and installed the fixed-path signed
  app.
  `testSettingsHotkeySelectionsPersistAcrossRelaunch` passed 1/1 in 55.079
  seconds through the canonical UI wrapper, exercising persisted modifier/main
  key configuration, real hotkey delivery, modifier-release confirmation, and
  relaunch readback. Its result bundle is
  `.build-local/ui-tests/results/FlowTabUITests.xcresult`.
- Pressure: the deterministic 2,000-transition owner test passed in the
  focused run with a stable terminal result and a single live fallback token.
  Manual scheduler tests delayed and reordered fallback delivery while
  preserving the same hardware-state result. Scheduling pressure therefore
  changes observation latency while preserving selection and replay results.
- Process/Tooling: the app and app-test targets built through the canonical
  FlowTabTests wrapper, and the UI target built through the canonical install
  script. Project-file `plutil -lint`, `git diff --check`, scoped stale-delay
  search, and source-size checks passed. Both new production files and the new
  test file remain below the 400-line guardrail;
  `SwitcherPanelController+InputHandling.swift` shrank from 789 to 496 lines.
  The startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `7abc326`
  (`refactor(sync): migrate SYNC-017 modifier release observation`).

### SYNC-018 Closure Record

- Design and Oracle: every `OptionTabHotkeyMonitor` owns a stable
  `HotkeyInputSourceID` and emits one monotonic sequence for each resolved
  Carbon press or release. `SwitcherHotkeyInputOwner` accepts an exact
  route/source/sequence identity once, rejects duplicate and regressed
  sequences, and rejects queued delivery from a replaced or unregistered
  source. Each accepted receipt records the global input generation, source
  registration generation, and current presentation-session generation.
  Distinct immediately adjacent input events therefore advance independently.
  Selection finish and cancellation establish replay-release observation before
  committing or ending the session. Replay suppression closes only when the
  exact modifier and main-key readback is released, either from the initial
  readback or a later transition/readback.
- Lifecycle: AppDelegate creates monitors inactive, registers their exact source
  with the controller, installs the callback, retains the monitor, and then
  explicitly starts Carbon observation. Re-registration stops the prior
  monitor and advances the route registration generation before the replacement
  can emit; old-source delivery is rejected. AppDelegate termination owns
  monitor stop and Carbon unregistration. `SwitcherPanelController` owns the
  input owner for its lifetime. `ModifierReleaseObservationOwner` owns the
  replay event token, at most one fallback token, replacement generation,
  cancellation, and local/global monitor cleanup.
- Retained time policy: the 16ms tab-advance throttle and 20ms post-finish
  ignore duration were removed. The named 25ms modifier-release fallback
  cadence from SYNC-017 remains solely for a missed AppKit/Carbon transition;
  it immediately reads the same hardware condition and elapsed time cannot
  make it succeed. A held input is a valid open-ended condition, so release
  evidence or lifecycle cancellation terminates the observation and no
  watchdog applies.
- Unit and Behavior: the final focused set passed 14/14 under
  `.build-local/evidence-driven-sync/SYNC-018/targeted-attempt-002`
  (four owner Unit paths and ten monitor/AppDelegate/controller behavior paths).
  Coverage includes exact-once identity acceptance, duplicate and out-of-order
  rejection, source replacement/unregistration, explicit monitor start
  idempotence and stop cleanup, AppDelegate start/stop ownership, distinct
  immediate presses, replay while held, initial and transition release
  readback, fallback cancellation, and the next press after release. The
  complete `FlowTabTests` class passed 299/299 under
  `.build-local/evidence-driven-sync/SYNC-018/full-unit-attempt-002`.
  The complete `FlowTabPriorityCoverageTests` class executed 572 tests under
  `.build-local/evidence-driven-sync/SYNC-018/full-priority-attempt-002`; every
  SYNC-018 path passed, while
  `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  observed the registered duplicate factory-record suite-order state. Its exact
  isolated rerun passed 1/1 under
  `.build-local/evidence-driven-sync/SYNC-018/priority-known-failure-isolated-attempt-001`.
  The order-isolation work remains assigned to SYNC-032/SYNC-033.
- FlowTabCore: not relevant because Carbon input routing, AppDelegate lifecycle,
  panel-session identity, hardware release readback, and TestingSupport command
  delivery are app-target boundaries.
- UI: the canonical install script rebuilt and installed the fixed-path Apple
  Development-signed app. Two final-source attempts ended before the test body
  when macOS timed out enabling automation mode. After restarting
  `testmanagerd`, one attempt entered setup and lost the service connection
  before a product assertion. The following canonical elevated run with
  unrelated Space-fixture preparation skipped passed
  `testSettingsMainHotkeyRepresentativeMatrixTriggersSwitcher` 1/1 in 93.773
  seconds. It exercised three persisted main-hotkey configurations across
  relaunch and real key delivery into the switcher.
- Pressure: the deterministic 2,000-event owner test accepted every distinct
  identity exactly once and rejected a duplicate delivery for every sequence.
  The final-source three-iteration
  `testTabSwitchStressCPUAndMemory` UI workload passed 1/1 in 32.869 seconds;
  its average monotonic iteration was 3.120 seconds, average CPU time was
  0.074 seconds, and average peak physical memory was 15,872.427 KiB.
  Immediate-event and manual release-scheduler tests preserve the same
  selection/replay result across scheduling order, so scheduling pressure
  changes completion latency while preserving the Oracle.
- Process/Tooling: the app, app-test, and UI-test targets built through the
  canonical wrappers. Project-file `plutil -lint`, `git diff --check`, scoped
  stale-symbol/duration search, and source-size checks passed. Both new files
  remain below the 400-line guardrail; touched monitor/controller files remain
  below 800 lines with a single responsibility. The startup `prompts.zip`
  remains unchanged and outside the slice.
- Commit: `44b0802`
  (`refactor(sync): migrate SYNC-018 hotkey input identity`).

### SYNC-019 Closure Record

- Design and Oracle: `SwitcherPanelController` installs panel occlusion,
  become-key, and expose observers during initialization. A presentation starts
  `InitialPanelVisibilityObservationOwner` before the first
  `makeKeyAndOrderFront`/`orderFrontRegardless` action. The owner performs an
  immediate readback and accepts completion only when the exact current
  `PanelVisibilitySnapshot.userVisible` condition is true. Matching
  presentation-action, occlusion, become-key, expose, soft-recovery, and
  watchdog readbacks can provide that evidence. Every observation carries both
  the initial-visibility generation and presentation-session generation;
  duplicate, regressed, superseded, and wrong-session delivery cannot complete
  the current session.
- Lifecycle: the panel controller owns the AppKit observer tokens from
  initialization through deinitialization. The presentation session owns one
  initial-visibility observation generation, one injected scheduler token, and
  the existing soft-recovery task. Visibility completion cancels the watchdog
  and any active recovery task. Session end, cancellation, replacement, and
  generation invalidation cancel pending work; token deinitialization
  defensively cancels its task. Hidden occlusion evidence is deferred only
  while that exact observation remains active.
- Retained time policy: `initialPresentationVisibilityWatchdogInterval` is a
  named 350ms terminal failure bound with an injectable scheduler. It never
  establishes success. When it fires, a final readback can still complete a
  panel that became visible under slow scheduling. An unmet final readback
  records the last event source/snapshot and final watchdog snapshot before
  routing the existing recoverable-interruption policy. Visibility recovery
  attempt timing and hard-reorder sequencing remain assigned to SYNC-020.
- Unit and Behavior: the focused owner and controller set passed 10/10 across
  `.build-local/evidence-driven-sync/SYNC-019/targeted-attempt-002` and
  `.build-local/evidence-driven-sync/SYNC-019/targeted-attempt-003`. It covers
  initially satisfied state, observer-before-trigger delivery, exact matching
  generations, duplicate and stale evidence, event-driven completion,
  cancellation, final-watchdog completion under delayed scheduling, watchdog
  failure diagnostics, session cancellation, and 200 rapid open/close cycles.
  The complete `FlowTabTests` class passed 305/305 under
  `.build-local/evidence-driven-sync/SYNC-019/full-unit-attempt-001`; the final
  2,000-replacement pressure test added afterward passed 1/1 under the
  owner-pressure result below. A combined rerun retained under
  `.build-local/evidence-driven-sync/SYNC-019/full-unit-attempt-002` stalled in
  the shared XCTest service before any test-case output after the UI automation
  failures and was interrupted. The complete
  `FlowTabPriorityCoverageTests` class executed 574 tests under
  `.build-local/evidence-driven-sync/SYNC-019/full-priority-attempt-001`; every
  SYNC-019 path passed, while
  `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  reproduced the registered duplicate factory-record suite-order state. Its
  exact isolated rerun passed 1/1 under
  `.build-local/evidence-driven-sync/SYNC-019/priority-known-failure-isolated-attempt-001`.
  The order-isolation work remains assigned to SYNC-032/SYNC-033.
- FlowTabCore: not relevant because AppKit window notifications, overlay
  readback, panel presentation, and session watchdog ownership belong to the
  app target.
- UI: the canonical install script rebuilt and installed the fixed-path Apple
  Development-signed app. Two canonical switcher attempts, including a
  restarted `testmanagerd` and elevated full-host rerun, timed out while macOS
  enabled automation mode before entering the test body. Evidence is retained
  under
  `.build-local/evidence-driven-sync/SYNC-019/ui-switcher-attempt-001` and
  `.build-local/evidence-driven-sync/SYNC-019/ui-switcher-attempt-002`; neither
  produced a product assertion.
- Pressure: the 200-cycle controller open/close test passed in the focused run
  without a stale recovery execution. A deterministic 2,000-replacement owner
  workload passed in 0.005 seconds under
  `.build-local/evidence-driven-sync/SYNC-019/owner-pressure-attempt-001`,
  retaining exactly one current watchdog and publishing no callback after
  cancellation. The canonical 50ms runtime-topology attempt built the real
  fixture variants and signed runner, then reached
  `target_launch_identity_failed` because the UI runner never launched the
  frozen-identity FlowTab app; it recorded zero samples and no product result
  under
  `.build-local/evidence-driven-sync/SYNC-019/runtime-topology-pressure-050ms-attempt-001`.
  Switcher UI and runtime-topology Pressure remain environment-blocked.
- Process/Tooling: the app, app-test, fixture, and UI-test targets built through
  canonical wrappers. Project-file lint, diff checks, scoped stale-symbol
  search, source-size checks, and exact staged-content review are recorded
  before commit. New production and test files remain below 400 lines; touched
  controller files remain below 800 lines with focused responsibilities. The
  startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `a0b746b`
  (`refactor(sync): migrate SYNC-019 initial panel visibility`).

### SYNC-020 Closure Record

- Design and Oracle: `PanelVisibilityRecoveryObservationOwner` replaces the
  fixed retry-delay loop with one explicit state machine. It first performs an
  exact `PanelVisibilitySnapshot` readback. A hard attempt issues order-out and
  must then observe `panelPresented == false` before it can issue order-front;
  completion requires an exact current `userVisible == true` readback. The
  owner consumes the controller-lifetime occlusion, become-key, and expose
  notifications installed by SYNC-019. Recovery and presentation generations
  reject stale callbacks. A visible notification received while order-out is
  still pending is retained as diagnostic evidence and cannot skip the
  required order-out/order-front transition.
- Lifecycle: `SwitcherPanelController` owns one recovery observation owner.
  The owner is installed before the first recovery action and retains at most
  one condition-readback token and one watchdog token. Replacement,
  presentation-session end, selection cancellation, successful readback,
  watchdog termination, and owner release cancel pending work. Order-out
  induced resign-active, resign-key, and hidden-occlusion callbacks are routed
  back into the active owner instead of creating a competing recovery
  generation.
- Retained time policy: AppKit in the local macOS 14.5 SDK exposes no public
  `NSWindow` order-on/order-off notification. The named
  `interruptionConditionReadbackInterval` is therefore retained at 10ms as a
  cancellable condition-observation cadence. It performs an immediate check
  before scheduling and elapsed duration never establishes success. The
  four-attempt maximum is an action-count policy rather than a duration.
  `interruptionPresentationRecoveryWatchdogInterval` is a named one-second
  terminal failure bound; its final readback can still complete recovery, and
  failure reports both the preceding evidence and final snapshot.
- Unit and Behavior: five deterministic owner tests and four controller
  behavior tests compile in the final source. Their independent Oracles cover
  initially satisfied state, order-out readback before order-front, rejection
  of a reordered visible notification, matching and stale generations,
  event-driven completion, delayed condition scheduling with an unchanged
  result, cancellation/replacement, watchdog final-readback success, watchdog
  failure diagnostics, active-Space recovery, and occlusion recovery. The
  canonical final build passed for all app, app-test, fixture, and UI-test
  targets under
  `.build-local/evidence-driven-sync/SYNC-020/build-for-testing-attempt-003`.
  Final execution under
  `.build-local/evidence-driven-sync/SYNC-020/owner-targeted-attempt-006`
  produced a result bundle but no suite-start or test-start event after a
  `testmanagerd` restart; the stalled invocation was terminated and recorded
  with xcodebuild exit 75 and log-pipeline exit 130. Unit and Behavior remain
  environment-blocked.
- FlowTabCore: not relevant because AppKit window ordering, panel snapshots,
  presentation generations, and recovery lifecycle belong to the app target.
- UI: the canonical install script rebuilt and installed the final-source
  Apple Development-signed app. The elevated canonical switcher run built and
  signed its UI runner, entered `test-without-building`, and then produced no
  test-start event. Its result bundle and status are retained under
  `.build-local/evidence-driven-sync/SYNC-020/ui-switcher-attempt-002`;
  no product assertion ran.
- Pressure: the deterministic 2,000-replacement owner test compiles and asserts
  one live condition-readback token, one watchdog token, and zero callbacks
  after cancellation. Its execution shares the Unit infrastructure blocker.
  The final-source canonical 500ms runtime-topology run reused the real Space
  fixture variants and a frozen identity manifest for the newly installed app.
  The runner reached `test-without-building`, but no matching FlowTab launch
  was observed: `identity_check_count=0`, `sample_count=0`, and no launch
  receipt was produced. Evidence is retained under
  `.build-local/evidence-driven-sync/SYNC-020/runtime-topology-pressure-500ms-attempt-003`.
- Process/Tooling: the canonical wrappers compiled all six targets and
  installed the signed UI app. Project-file lint, `git diff --check`, scoped
  stale-delay/symbol search, source-size checks, and exact staged-content
  review are recorded before commit. The three new production files and two
  new test files remain below 400 lines; the extracted presentation controller
  responsibility also reduces
  `SwitcherPanelController+Presentation.swift`. The startup `prompts.zip`
  remains unchanged and outside the slice.
- Validation correction: the rapid open/close pressure case now observes the
  initial-visibility watchdog token, recovery scheduler tokens, recovery
  generation, and the last direct recovery diagnostic across 200
  presentation lifecycles. It fires every retained manual callback after
  cancellation and verifies that recovery and watchdog state remain stable.
  This replaces the asynchronous persisted-log timing Oracle, which classified
  SYNC-020's intentional synchronous soft recovery action as stale and could
  retain only a suffix of the generated records. The corrected case passed in
  0.169 seconds under
  `.build-local/evidence-driven-sync/SYNC-021/initial-visibility-pressure-corrected-attempt-011`.
- Commit: `206afdffa78e3bc1e193033fe03e1f06b69be0e3`
  (`refactor(sync): migrate SYNC-020 panel visibility recovery`).
- Validation-correction commit:
  `b7a1b2263598dfbd5f18797501dfdc0f4e0eb549`
  (`test(sync): correct SYNC-020 cancellation pressure oracle`).

### SYNC-021 Closure Record

- Design and Oracle: `ActiveSpaceTransitionObservationOwner` captures the
  runtime Space projection generation, ordered display/current-Space
  identities, presentation generation, and exact panel visibility before
  `signalSpaceTopologyChanged()`. An independent request-return readback and
  exact-runtime-service projection notifications provide later evidence.
  Resolution requires a Space generation strictly newer than the baseline.
  A same-Space visible result closes activation suppression without recovery;
  a changed current Space or hidden panel follows the existing modifier,
  search, termination-protection, and visibility-recovery rules. Duplicate,
  stale, out-of-order, replaced-observation, and wrong-presentation evidence
  cannot resolve the active observation.
- Lifecycle: one panel controller owns the projection observer, transition
  owner, and explicit activation-suppression identity. Starting a replacement
  cancels the preceding watchdog. Projection resolution, session end,
  cancellation, recovery completion, recovery watchdog, and controller
  release clear their matching work. The runtime projection notification is
  filtered to the controller's exact service object.
- Retained time policy: `topologyReadbackWatchdogInterval` is a named
  one-second terminal failure bound with an injectable scheduler. It performs
  one final exact readback: an advanced generation can still resolve, while an
  unmet condition reports the baseline, last evidence source/readback, and
  final readback. Elapsed time never establishes transition success. A visible
  final panel safely ends suppression; a hidden final panel enters the existing
  conservative recovery path.
- Unit and Behavior: five deterministic owner tests and seven controller
  behavior tests cover observer-before-request ordering, synchronous
  request-return evidence, stale/duplicate/out-of-order rejection, stable
  current-Space notification handling, exact Space identity change, modifier
  release cancellation, termination protection, final-watchdog readback,
  lifecycle cancellation, and slow scheduling with an unchanged result. The
  final complete canonical `FlowTabTests` run passed 893/893 in 41.381 seconds
  under
  `.build-local/evidence-driven-sync/SYNC-021/full-flowtabtests-final-attempt-018`.
- FlowTabCore: not relevant because workspace notifications, AppKit panel
  visibility, presentation sessions, and runtime projection service ownership
  belong to the app target.
- UI: the canonical install wrapper built, Apple Development-signed, validated,
  and installed the final app at `/Users/lk/Applications/Flow Tab UITest.app`.
  The final-source four-scenario run covered persisted hotkeys, main-hotkey
  presentation, in-app window presentation, and a fullscreen cross-Space
  workflow. Fixture preparation and runner signing passed, then the UI runner
  stopped before every test body with LocalAuthentication code `-4`
  (`System authentication is running`). The valid result bundle and
  machine-readable status are retained under
  `.build-local/evidence-driven-sync/SYNC-021/ui-final-source-attempt-019`.
- Pressure: the 2,000-replacement deterministic owner workload passed within
  the complete FlowTabTests run. It retains one current watchdog, cancels every
  replaced token, fires delayed callbacks after cancellation, and publishes no
  stale completion. The final-source real-topology run froze the installed app
  identity at SHA-256
  `78228fa980e358edd28a6a97efff6c0c3ee23b397c4bdeaf2ca8d44f25185264`,
  rebuilt and signed the runner, and then met the same LocalAuthentication
  failure before the app launch. Its status is
  `target_launch_identity_failed`, with valid result bundle,
  `identity_check_count=0`, and `sample_count=0`, under
  `.build-local/evidence-driven-sync/SYNC-021/runtime-topology-pressure-final-attempt-021`.
- Process/Tooling: the final all-six-target canonical build passed under
  `.build-local/evidence-driven-sync/SYNC-021/build-for-testing-final-attempt-017`.
  Project-file lint, `git diff --check`, scoped stale-symbol/duration search,
  source-size checks, and exact staged-content review are recorded before
  commit. Both new production files and both new test files remain below 400
  lines. The touched oversized panel-session test file shrinks by 151 lines as
  the focused SYNC-021 behavior coverage moves to its own file. The startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `17a0e8552fe31a64db60586cdb012a59c348c1a1`
  (`refactor(sync): migrate SYNC-021 active Space transition`).

### SYNC-022 Closure Record

- Design and Oracle: `TerminateInterruptionProtectionObservationOwner`
  replaces both uptime windows with a two-phase evidence contract. The
  controller captures projection generation, target presence, and panel
  visibility before issuing a terminate request, then commits the prepared
  observation with the accepted appID, PID, and request generation. Target
  completion requires exact projection absence or replacement together with
  either the matching workspace termination or a terminated-process readback
  whose projection evidence is newer than the baseline or removes a target
  known present at baseline. Same-bundle/different-PID, stale-generation,
  duplicate, out-of-order, and unavailable-identity observations cannot
  establish completion. Once target completion is latched, a later stale
  projection cannot revoke it.
- Presentation completion: target completion cancels its watchdog and enters
  an untimed presentation latch. Protection resolves only after the active
  Space transition or panel visibility publishes a stable readback, or after
  the owner consumes a related system interruption and reads the panel as
  user-visible with FlowTab active. Panel resign-key and app resign-active
  notifications can arrive in either order; each is recovered while the same
  observation remains active. The final real-fixture runs observed both
  notifications after the terminate request, restored the exact panel, and
  removed only the terminated fixture identity.
- Lifecycle: one panel controller owns the observation owner, exact process
  state reader, runtime-projection readbacks, and watchdog scheduler. A
  replacement request cancels the preceding token. Rejected requests cancel
  their prepared baseline. Target completion cancels the watchdog; successful
  presentation evidence, watchdog failure, presentation-session end,
  selection cancellation, and controller release clear all owned state.
  Presentation generation and exact runtime-service notification routing
  reject callbacks from replaced sessions.
- Retained time policy: the named
  `completionWatchdogInterval` remains five seconds solely as the terminal
  failure bound for target termination plus projection removal. Its wakeup
  performs a final exact readback that can still latch completion; elapsed
  time never establishes success. Failure reports the unmet
  `targetTerminationAndProjectionRemoval` condition, target identity,
  baseline, preceding evidence, and final process/projection/panel snapshot.
  The former 500ms post-refresh window is removed. Presentation completion has
  no duration and remains session-owned until evidence or cancellation.
- Unit and Behavior: the final-source targeted run passed 12/12 tests in
  0.483 seconds under
  `.build-local/evidence-driven-sync/SYNC-022/targeted-initial-readback-attempt-027`.
  Seven owner tests cover completion already satisfied by the first readback,
  observer-before-request ordering, exact identity and generation
  filtering, slow watchdog scheduling with an unchanged result, final
  watchdog readback and diagnostics, repeated/out-of-order presentation
  interruptions, and 2,000 replacement/cancellation cycles. Five controller
  tests cover observer-before-request ordering, workspace termination,
  projection removal, active-Space ordering, recovered panel/app activation,
  and failure diagnostics. The complete final-source canonical
  `FlowTabTests` run passed 902/902 in 69.157 seconds under
  `.build-local/evidence-driven-sync/SYNC-022/full-flowtabtests-initial-readback-attempt-028`.
- FlowTabCore: not relevant because terminate requests, workspace lifecycle,
  AppKit presentation events, and runtime projection ownership belong to the
  app target.
- UI: the persisted explicit/fallback quit-hotkey matrix passed in 60.821
  seconds under
  `.build-local/evidence-driven-sync/SYNC-022/ui-mock-hotkey-attempt-017`.
  The final-source real fixture path waited for the independent process-state
  and exact refreshed-element Oracles, kept the panel available through the
  termination interruption sequence, and passed in 25.854 seconds inside
  `.build-local/evidence-driven-sync/SYNC-022/runtime-topology-pressure-final-source-attempt-026`.
  Re-resolving the exact accessibility identifier after projection refresh
  prevents a pre-termination XCUI element binding from becoming the removal
  Oracle.
- Pressure: the deterministic owner workload replaces and cancels 2,000
  observations, fires retained callbacks after cancellation, and publishes no
  stale resolution. The final real-topology attempt froze the installed
  Apple Development-signed executable at SHA-256
  `48a426df29d7eb3fa59f340b85643e8252ceab0d774687bacd40c7cfbd9cf6cd`;
  its private manifest has SHA-256
  `0be5ebdc9ed84a6fc940de0c155d6426f83903569358f67d19c35ad556ad32d6`.
  Six sampled PID bindings matched the frozen identity across 5.131 seconds.
  The 500ms-sampled workload passed with CPU average/p95/max
  56.07/101.30/101.30 percent and RSS average/p95/max
  162.44/199.16/199.16 MB under
  `.build-local/evidence-driven-sync/SYNC-022/runtime-topology-pressure-final-source-attempt-026`.
- Process/Tooling: the final all-six-target canonical build passed under
  `.build-local/evidence-driven-sync/SYNC-022/build-for-testing-initial-readback-attempt-029`.
  Project-file lint, `git diff --check`, scoped stale-symbol/duration search,
  source-size checks, and exact staged-content review are recorded before
  commit. The five new production files and three new test files remain
  at or below 400 lines. The startup `prompts.zip` remains unchanged and
  outside the slice.
- Commit: `29645db31b29a4efab45d7543e2f3b13f69e5a83`
  (`refactor(sync): migrate SYNC-022 terminate interruption protection`).

### SYNC-023 Closure Record

- Design and Oracle: `DelayedWindowLayerEntryObservationOwner` implements one
  two-condition contract. The persisted monotonic deadline and an exact
  selected-app projection readback must both be satisfied before automatic
  entry. Readiness requires the same presentation generation and appID, at
  least two selected windows, a presented app layer, inactive Search, and
  `canAutoEnterWindowLayer`. A deadline wakeup only reads this state; every
  projection or layout event also compares the injected monotonic clock with
  the stored deadline, so delayed scheduler delivery changes completion
  latency while preserving the result.
- Observation ordering and evidence: the controller captures the initial
  projection generation and installs the owner before requesting selected-app
  projection maintenance. Initial readback, request-return readback,
  app-switcher projection publication, exact current-app projection
  publication, and subsequent session-layout readback close synchronous and
  missed-event races. Exact appID, observation generation, and presentation
  generation reject unrelated, duplicate, stale, and replaced evidence.
  Manual window-layer entry consumes the same exact projection publication
  directly.
- Lifecycle: the presentation controller owns one observation and one
  deadline token. Target replacement, Search activation, selection
  cancellation, session end, panel dismissal, controller release, and
  successful entry cancel or replace owned work. A preserved layout update
  keeps the original deadline only for the same app and presentation
  generation. Token cancellation and generation checks make retained
  callbacks inert.
- Retained time policy: `WindowLayerPreferencesStore` continues to own the
  user-selected 0–999.99-second auto-entry delay, rounded to hundredths with a
  0.75-second default. `DelayedWindowLayerEntryScheduler` schedules that one
  product deadline against system uptime. Once the deadline is satisfied, the
  presentation owner waits for exact projection evidence or lifecycle
  cancellation. Projection readiness and manual entry have no retry cadence
  or readiness timeout.
- Unit and Behavior: the final targeted run passed 14/14 tests in 0.279
  seconds under
  `.build-local/evidence-driven-sync/SYNC-023/targeted-attempt-006`.
  Owner tests cover initially ready state, deadline-first and
  projection-first ordering, delayed scheduler delivery, early wakeup
  rescheduling, exact app filtering, stale/duplicate/replaced evidence, and
  2,000 replacement/cancellation cycles. Controller tests cover
  observer-before-request ordering, synchronous request-return readback,
  configured-deadline cancellation, exact event entry, manual entry, and
  replacement. The complete canonical `FlowTabTests` run passed 913/913 in
  47.117 seconds under
  `.build-local/evidence-driven-sync/SYNC-023/full-flowtabtests-attempt-007`.
- FlowTabCore: not relevant because the persisted app preference, AppKit panel
  presentation, runtime projection events, and lifecycle owner belong to the
  app target.
- UI: the final signed-app visible path passed in 6.511 seconds under
  `.build-local/evidence-driven-sync/SYNC-023/ui-delayed-entry-attempt-008`.
  It observed the 300ms configured deadline, the exact five-window projection,
  and the prewarmed preview in the same window-layer transition. The dedicated
  repeated-presentation UI path completed 12/12 presentation, evidence-entry,
  confirmation, and cleanup cycles in 34.483 seconds under
  `.build-local/evidence-driven-sync/SYNC-023/ui-delayed-entry-pressure-attempt-010`.
- Pressure: the deterministic owner test replaces and cancels 2,000
  observations without stale completion. The final process-level run repeated
  the delayed-entry UI path 12 times and passed in 35.518 seconds under
  `.build-local/evidence-driven-sync/SYNC-023/delayed-entry-pressure-attempt-011`.
  Its Apple Development-signed executable SHA-256 is
  `4bce759ba9f24ea174f7a98fe1e2a69f3dd3d432f5b0cf9b9b61ef994abb326c`;
  the private manifest SHA-256 is
  `6382fb7724c1a0c3bee87063e4cb8cf8d6307414cf8f643c5a44f8ab7cb78868`.
  Forty-six 500ms samples matched the frozen identity. CPU average/p95/max was
  15.80/48.00/55.40 percent and RSS average/p95/max was
  116.39/130.88/135.91 MB. This is the local baseline for the dedicated
  delayed-entry interaction workload.
- Cross-slice pressure evidence: the first real-topology attempt completed
  three noisy cross-Space/fullscreen presentation phases, then SYNC-019's
  initial-visibility watchdog cancelled the fourth presentation after a
  372.550ms presentation exceeded its 350ms bound. The final readback recorded
  `userVisible=0`; the exact SYNC-023 observation had already been established
  and remained unrelated to the cancellation. Identity matching, 72 samples,
  and the valid failure result are retained under
  `.build-local/evidence-driven-sync/SYNC-023/runtime-topology-pressure-attempt-009`.
  The inventory assigns this reproducible scheduling-pressure result to the
  pending SYNC-019 remediation.
- Process/Tooling: the final canonical all-six-target build passed under
  `.build-local/evidence-driven-sync/SYNC-023/build-for-testing-attempt-012`.
  Project-file lint, `git diff --check`, scoped stale-symbol search, source-size
  checks, and exact staged-content review are recorded before commit. All six
  new production/test files and the affected UI test file remain below 400
  lines. The startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `6c3f3810a6a4090018b7587904417f10a4a55754`
  (`refactor(sync): migrate SYNC-023 delayed window-layer entry`).

### SYNC-024A Closure Record

- Design and Oracle: `TerminatePressFeedbackPolicy` gives the app-tile visual
  transition and terminate continuation one 120ms product duration.
  `TerminatePressFeedbackCompletionOwner` publishes an explicit scheduler
  completion carrying its generation and interval. The controller prepares
  visual state first, then sends the terminate request only from that matching
  completion. Termination success remains owned by SYNC-022's exact
  appID/PID/request/projection evidence.
- Lifecycle: the panel controller owns one completion owner and one scheduler
  token. Repeated input while a completion is pending is coalesced. Event
  monitor removal, selection/session end, and controller release cancel owned
  work; generation equality rejects retained callbacks after replacement or
  cancellation. Scheduler implementations may deliver synchronously without
  leaking a token or replaying completion.
- Retained time policy: the 120ms ease-out press feedback is an animation
  contract. The production scheduler waits for that named interval and reports
  completion; the interval no longer infers process termination, projection
  refresh, or request success. Delayed scheduler delivery changes request
  latency while preserving the selected app and resulting terminate request.
- Unit and Behavior: the final focused run passed 8/8 in 0.382 seconds under
  `.build-local/evidence-driven-sync/SYNC-024A/targeted-attempt-007`.
  Coverage includes one scheduled completion, duplicate delivery, replacement,
  cancellation, forced late callbacks, synchronous scheduler delivery,
  continuation-before-request ordering, interruption-protection preparation,
  shortcut routing, and request result readback.
- Expanded Behavior: the complete canonical run executed 918 tests under
  `.build-local/evidence-driven-sync/SYNC-024A/full-flowtabtests-attempt-003`.
  All SYNC-024A and termination paths passed. Two assertions in
  `testSwitcherInitialVisibilityObserverAcceptsWindowNotificationReadback`
  retained the SYNC-019 presenting state instead of consuming the panel-expose
  readback. Its exact isolated rerun passed 1/1 in 0.041 seconds under
  `.build-local/evidence-driven-sync/SYNC-024A/sync019-isolation-attempt-004`;
  the ledger assigns this full-suite order sensitivity to the pending SYNC-019
  remediation.
- FlowTabCore: not relevant because the visual policy, panel-session
  continuation, and AppKit/SwiftUI lifecycle belong to the app target.
- UI: the canonical install wrapper produced the fixed-path Apple
  Development-signed app. The two-case configured/fallback quit-hotkey matrix
  passed 1/1 in 76.070 seconds under
  `.build-local/evidence-driven-sync/SYNC-024A/ui-terminate-attempt-005`.
  Each case observed the exact selected app, matching mock terminate request,
  workspace-termination refresh, and selected-tile removal.
- Pressure: the deterministic 500-cycle owner workload alternated completion
  and cancellation, forcibly delivered every retained callback, published
  exactly the 250 live generations in monotonic order, and left no pending
  work. It is part of the focused result above.
- Process/Tooling: the canonical UI wrapper's all-six-target
  `build-for-testing`, signed fixed-app install, and targeted UI execution
  passed. Project-file lint, `git diff --check`, scoped stale-symbol search,
  source-size checks, and exact staged-content review are recorded before
  commit. Both new files remain below 400 lines; the touched controller remains
  below 800 lines with the completion owner extracted. The startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `f5bb3c29601866705ecf6b34afce29ef58976565`
  (`refactor(sync): migrate SYNC-024A terminate press completion`).

### SYNC-024B Closure Record

- Design and Oracle: the controller installs
  `onWindowOnlyPreviewPreparationChanged` during initialization, before any
  preview prewarm request. `InitialWindowOnlyPreviewRevealObservationOwner`
  then starts with the current presentation generation and an immediate
  pending-capture readback. Zero pending captures complete from
  `initial_readback`; later preview-batch callbacks complete only after their
  readback reports zero. A callback that arrived before owner startup is closed
  by the initial readback.
- Watchdog: `InitialWindowOnlyPreviewRevealPolicy` retains 250ms as the named
  degraded-reveal upper bound. Expiry performs a final pending-capture
  readback. A ready final snapshot publishes `watchdog_readback` evidence.
  An unready final snapshot publishes
  `InitialWindowOnlyPreviewRevealWatchdogFailure`, including the last event,
  final source, readiness flag, and pending count, before the controller
  reveals the panel in degraded mode. Watchdog expiry is never readiness or
  preview-capture success.
- Lifecycle: the presentation-session controller owns one observation owner
  and one cancellable watchdog token. Replacement increments the observation
  generation; every callback also matches the presentation generation.
  Presentation end cancels and invalidates pending work, restores panel alpha,
  and rejects retained callbacks. Synchronous scheduler delivery cancels the
  returned token without replaying completion.
- Unit and Behavior: the first targeted run exposed a test fixture that had
  neither a model session nor a presented-panel readback, so its call to the
  existing `endPresentationSession` guard correctly did not run. After
  establishing the intended presented-panel precondition, the final targeted
  run passed 11/11 in 0.628 seconds under
  `.build-local/evidence-driven-sync/SYNC-024B/targeted-attempt-005`.
  Coverage includes initial readiness, batch-event readiness, delayed
  watchdog delivery, duplicate delivery, replacement, cancellation, mismatched
  generations, synchronous delivery, final-ready readback, failure diagnostics,
  controller alpha transitions, and presentation-end cleanup.
- Expanded Behavior: the complete canonical FlowTabTests run passed 929/929 in
  63.478 seconds under
  `.build-local/evidence-driven-sync/SYNC-024B/full-flowtabtests-attempt-004`.
  The previously recorded SYNC-019 full-suite ordering failure did not recur;
  its earlier pressure and ordering evidence remains assigned to that dedicated
  remediation.
- FlowTabCore: not relevant because preview capture state, AppKit panel alpha,
  the presentation generation, and the watchdog owner all belong to the app
  target.
- UI: the canonical install wrapper produced the fixed-path Apple
  Development-signed app. The affected Control+Tab test passed 1/1 in 8.452
  seconds under
  `.build-local/evidence-driven-sync/SYNC-024B/ui-preview-attempt-003`.
  With an 80ms asynchronous preview workload, it observed the exact next-window
  selection, both preview images, the large window-preview canvas, and the
  `preview_batch_completed` readiness log.
- Pressure: the deterministic 500-cycle workload alternated cancellation and
  readiness completion, forcibly delivered every retained watchdog callback,
  published exactly the 250 live generations in monotonic order, and left no
  observation or failure pending. It is part of the targeted result above.
- Process/Tooling: the UI wrapper's all-six-target `build-for-testing`,
  fixed-app build/install/signature verification, targeted UI execution, and
  complete canonical app-test run passed. Project lint, stale-symbol search,
  source-size checks, `git diff --check`, and exact staged-content review are
  recorded before commit. The owner and both new test files remain below 400
  lines; the touched controller remains below 800 lines. The startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `845d353574cb99c384cee9eae543747d5bdfb7f8`
  (`refactor(sync): migrate SYNC-024B initial preview reveal`).

### SYNC-024C Closure Record

- Design and Oracle: `SwitcherAppRemovalAnimationPolicy` names the 140ms
  ease-out duration and the existing 16-app animation ceiling. The app strip
  resolves only an optional `Animation` from this immutable policy. Terminate
  request delivery, process state, workspace termination, runtime projection
  refresh, session membership, and tile identity never read the duration.
- Retained time policy and lifecycle: 140ms is a visual product contract for
  opacity/scale removal. SwiftUI app-strip identity owns and cancels its render
  transition as view identity changes or leaves the hierarchy. App sets above
  16 retain the existing no-animation path, preventing large-list render work.
  No callback, continuation, retry, success result, or model mutation is
  scheduled from this policy.
- Unit and Behavior: the focused canonical run passed 5/5 in 0.380 seconds
  under
  `.build-local/evidence-driven-sync/SYNC-024C/targeted-attempt-003`.
  Policy coverage verifies the named duration, inclusive 16-app boundary,
  invalid/large-count no-animation paths, and injected policy values. The
  behavior cases prove a sent terminate request retains the app, while matching
  workspace-termination evidence refreshes the projection and removes it.
- FlowTabCore: not relevant because the animation policy and SwiftUI app-strip
  rendering belong to the app target.
- UI: the fixed-path Apple Development-signed app and real Space Fixture test
  passed 1/1 in 28.010 seconds under
  `.build-local/evidence-driven-sync/SYNC-024C/ui-real-termination-attempt-002`.
  The fixture intentionally remained alive for 2.4 seconds after the quit
  request. Its exact tile remained present throughout that interval, then
  disappeared only after process termination and the matching runtime refresh.
- Pressure: not relevant because this slice adds one immutable constant lookup
  during app-strip rendering and owns no observer, timer, retry, callback, or
  repeated asynchronous work. The existing 16-app ceiling is covered at both
  sides of its boundary.
- Process/Tooling: canonical app-test and UI wrappers built all six targets.
  The UI workflow prepared and signed real fixture variants, installed and
  verified the fixed app signature, then executed the real-process topology.
  Project lint, stale-literal scan, source-size checks, `git diff --check`, and
  exact staged-content review are recorded before commit. Both new files remain
  below 400 lines, and the touched overlay remains below 800 lines. The startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `5a3e470c7e7d6cbd8bc6eb5788d657dfe0b7f203`
  (`refactor(sync): classify SYNC-024C app removal animation`).

### SYNC-024D Closure Record

- Design and Oracle: `HomeControlPressAnimationPolicy` names the 120ms
  ease-out duration and is injected into `FlowPageActionButton`. The SwiftUI
  `Button` continues to invoke its action closure directly from the input
  callback. The duration is read only while deriving the
  `configuration.isPressed` render animation; action delivery, preference
  mutation, navigation, and success state never read it.
- Retained time policy and lifecycle: 120ms is a visual product contract for
  pressed-gradient feedback. SwiftUI button identity owns and cancels the
  render transition as its pressed state or view identity changes. The policy
  owns no callback, continuation, timer, retry, observer, or success result.
- Unit and Behavior: the focused canonical run passed 2/2 in 0.002 seconds
  under
  `.build-local/evidence-driven-sync/SYNC-024D/targeted-attempt-001`.
  Coverage verifies the named default duration, injected policy propagation,
  and direct action-closure delivery independent of the visual duration.
- FlowTabCore: not relevant because the animation policy and SwiftUI button
  rendering belong to the app target.
- UI: the fixed-path Apple Development-signed app test passed 1/1 in 15.245
  seconds under
  `.build-local/evidence-driven-sync/SYNC-024D/ui-home-dismiss-attempt-001`.
  The affected Home action button accepted the real click, removed the
  permission banner from state evidence, and preserved the resulting
  preference across process termination and relaunch.
- Pressure: not relevant because this slice adds one immutable duration lookup
  during SwiftUI rendering and owns no observer, timer, retry, callback, or
  repeated asynchronous work.
- Process/Tooling: the canonical app-test wrapper passed, the fixed app rebuilt
  and verified its Apple Development signature, and the UI wrapper built all
  six targets before executing the affected path. Project lint,
  stale-literal scan, source-size checks, `git diff --check`, and exact
  staged-content review are recorded before commit. Both new files and the
  touched Home chrome file remain below 400 lines. The startup `prompts.zip`
  remains unchanged and outside the slice.
- Commit: `a0096673a73927dd02b1959f80b016f965f4a247`
  (`refactor(sync): classify SYNC-024D home press animation`).

### SYNC-024E Closure Record

- Design and Oracle: `SettingsAppVisibilityNavigationAnimationPolicy` names
  the 180ms ease-in-out duration and is injected into `AppSettingsView`.
  Manage and back input callbacks synchronously update
  `showsAppVisibilityManager`; the duration is read only while deriving the
  opacity animation. `AppVisibilityManagerView` explicitly contains its AX
  children so its manager and back identities form independently observable
  evidence. Navigation success is the requested destination's visible state.
- Retained time policy and lifecycle: 180ms is a visual product contract for
  the Settings/app-visibility opacity transition. Settings SwiftUI view
  identity owns and cancels the transition as state or view identity changes.
  The policy owns no callback, continuation, timer, retry, observer, success
  result, or delayed state mutation.
- Unit and Behavior: the focused canonical run passed 2/2 in 0.001 seconds
  under
  `.build-local/evidence-driven-sync/SYNC-024E/targeted-attempt-001`.
  Coverage verifies the named default duration and injected policy propagation
  into the Settings view.
- FlowTabCore: not relevant because the animation policy, navigation state,
  and SwiftUI rendering belong to the app target.
- UI: the first navigation run under
  `.build-local/evidence-driven-sync/SYNC-024E/ui-navigation-attempt-001`
  reached the manager but exposed only its root AX group, so the stable back
  identity was absent and the action was not attempted. After assigning AX
  child containment to the manager, the fixed-path Apple Development-signed
  navigation test passed 1/1 in 14.511 seconds under
  `.build-local/evidence-driven-sync/SYNC-024E/ui-navigation-attempt-002`.
  It observed the manager and back identities, clicked back, then observed
  manager removal and the Settings manage action's return. The existing
  pinyin-search manager regression also passed 1/1 in 13.510 seconds under
  `.build-local/evidence-driven-sync/SYNC-024E/ui-manager-regression-attempt-001`,
  retaining search-field and exact application-row visibility.
- Pressure: not relevant because this slice adds immutable duration lookup and
  AX containment during SwiftUI rendering and owns no observer, timer, retry,
  callback, or repeated asynchronous work.
- Process/Tooling: the canonical app-test wrapper passed, the fixed app rebuilt
  and verified its Apple Development signature, and the UI wrapper built all
  six targets before the final affected-path execution. Project lint,
  stale-literal scan, source-size checks, `git diff --check`, and exact
  staged-content review are recorded before commit. New files remain below
  400 lines. Touched Settings source and UI-test files remain below 800 lines
  with one Settings-view or Settings-test responsibility each. The startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `0e682598d51861495185b6bf2fdeed038504d4c7`
  (`refactor(sync): classify SYNC-024E settings navigation animation`).

### SYNC-025 Closure Record

- Design and Oracle: `PanelPresentationDiagnosticProbeOwner` replaces the
  anonymous task with a generation-scoped sequence. An injectable scheduler
  first publishes a next-main-turn probe, then schedules the named frame
  sample. Each callback records its actual monotonic timestamp in
  `PanelPresentationDiagnosticProbe`; neither callback provides a readiness or
  success result, and both only feed the existing diagnostic log.
- Retained time policy and lifecycle: 16ms is retained as
  `PanelPresentationDiagnosticPolicy.frameSampleInterval`, a diagnostic
  sampling contract for observing an approximately subsequent display frame.
  `SwitcherPanelController` owns the probe owner, and every presentation begin
  or invalidation cancels its current token and advances generation. Replaced,
  canceled, and late callbacks cannot publish into another presentation
  session.
- Unit and Behavior: the final focused canonical run passed 4/4 in 0.088
  seconds under
  `.build-local/evidence-driven-sync/SYNC-025/targeted-attempt-002`.
  Coverage verifies the named 16ms cadence, independently injected clock,
  actual callback timestamps, replacement, explicit cancellation, late
  callback rejection, and the representative global `show` path. Ending that
  presentation canceled the pending frame sample and preserved the last
  accepted probe.
- FlowTabCore: not relevant because the probe observes app-target panel
  presentation diagnostics and introduces no core-domain contract.
- UI: not relevant because the slice changes no rendered state, accessibility
  state, input result, recovery decision, or user-visible behavior. The
  representative AppKit presentation path is covered by the behavior test.
- Pressure: the deterministic 500-cycle workload alternated cancellation and
  deliberately delayed callback delivery. It published frame samples for
  exactly the 250 live generations in monotonic generation order, rejected
  every canceled callback, and left no pending work. The delayed clock values
  changed only probe timestamps.
- Process/Tooling: the canonical wrapper built all six targets and passed the
  focused tests. Project lint, stale anonymous-sleep scan, source-size checks,
  `git diff --check`, and exact staged-content review are recorded before
  commit. The new owner and test files remain below 400 lines. Existing
  visibility diagnostic value types moved from the oversized panel controller
  into its dedicated diagnostics file, leaving the controller below 800
  lines. The startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `b95e5998e8701c9ef6a84bb5e089c47165e1ae27`
  (`refactor(sync): classify SYNC-025 presentation diagnostic sampling`).

### SYNC-026A Closure Record

- Design and Oracle: `SpaceFixtureFullScreenObservation` installs an
  exact-`NSWindow` `didEnterFullScreen` observer before invoking
  `toggleFullScreen`. `SpaceFixtureFullscreenTransitionOwner` retains the
  configured launch delay only before the first window, then starts each later
  window directly from the preceding exact-window completion. Accepted
  evidence includes the owner generation, ordered sequence index, total count,
  and fixture window-plan index. Application AX publication and downstream
  fixture work begin only after accepted completion evidence.
- Retained time policy and lifecycle: `enterFullscreenDelayMilliseconds`
  remains a fixture scenario input that intentionally stages the first
  transition. After observer installation, an already-fullscreen readback
  completes synchronously without toggling the window. The coordinator owns
  its injected scheduler, transition generation, scheduled token, and current
  exact-window observation. Starting another launch cancels and invalidates all
  retained tokens. Each AppKit fixture window owns its single-shot notification
  token and removes it on completion, cancellation, close, or deinitialization.
  Duplicate, out-of-order, replaced, and canceled callbacks cannot advance
  another sequence.
- Unit and Behavior: the final focused canonical run passed 7/7 in 0.010
  seconds under
  `.build-local/evidence-driven-sync/SYNC-026A/targeted-attempt-004`.
  Coverage verifies configured first-delay scheduling, initial readback
  completion with synchronous callback delivery, first and subsequent event
  delivery, direct two-window chaining, duplicate late callback rejection,
  replacement, cancellation, retained canceled-callback delivery, downstream
  desktop/AX scheduling only after chain completion, and the representative
  coordinator paths.
- FlowTabCore: not relevant because the fixture scheduler, AppKit fullscreen
  notification, and topology orchestration belong to the dedicated fixture and
  app-test targets.
- UI: the canonical install wrapper rebuilt and verified the fixed-path Apple
  Development-signed app. The noisy Control+Tab real-topology test passed 1/1
  in 45.643 seconds under
  `.build-local/evidence-driven-sync/SYNC-026A/ui-attempt-003`. Its fixture
  created two separate fullscreen windows. Exact CG window identities and
  full-screen-sized frames observed both Spaces, and the workflow selected and
  activated each fullscreen sibling across Spaces before process cleanup.
- Pressure: the deterministic 500-cycle owner workload varied the configured
  initial delay on every cycle, alternated accepted completion and
  cancellation, forcibly delivered canceled callbacks, published exactly the
  250 live completion generations in monotonic order, and left no running
  transition. Scheduler timing changed only when the first transition began.
- Process/Tooling: the canonical app-test and UI wrappers built all six
  targets; fixture preparation, UI runner signing, fixed-app installation, and
  targeted execution passed. Project-file lint, stale 1.4-second spacing
  search, source-size checks, `git diff --check`, and exact staged-content
  review are recorded before commit. New production and test files remain
  below 400 lines, and touched coordinator/test files remain below 800 lines.
  The startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `e934fd2a5abc61bb0fdbd8d745e6d5993884ccf9`
  (`refactor(sync): migrate SYNC-026A fullscreen transition chain`).

### SYNC-026B Closure Record

- Design and Oracle: the final fullscreen completion now starts desktop-anchor
  recovery immediately. `SpaceFixtureDesktopRefocusOwner` installs
  exact-window and active-Space observers before activation, captures an
  initial readback, arms one generation-bound watchdog, invokes activation and
  `show(isKey: true)`, and captures a trigger-return readback. Accepted evidence
  must match the owner generation and planned desktop-anchor identity and must
  read back the application as active, the exact AppKit window as key, main,
  visible, unminimized, on the active Space, and occlusion-visible, plus that
  exact window number as an on-screen CG window owned by the fixture process.
  Application AX publication resumes only after that evidence resolves.
- Event gap, retry, and lifecycle: exact `NSWindow` key, main, occlusion, and
  deminiaturize notifications, application activation, and active-Space
  notifications all drive fresh readback. AppKit supplies no acceptance
  callback for activation/order-front requests, so a named 100ms retry first
  checks the full condition, repeats the request only while it remains unmet,
  and reads back again after the request. The coordinator-owned generation
  cancels its observer, retry, and watchdog on success, failure, replacement,
  or launch cancellation. Each AppKit fixture window also cancels its retained
  observation on close. Duplicate, stale-identity, replaced, canceled, and
  out-of-order callbacks cannot resolve another generation.
- Failure bound: the named 15s watchdog is terminal diagnostic policy only. Its
  final readback can still resolve success. A remaining failure records the
  generation, expected plan identity, last evidence source and snapshot, final
  snapshot, and every unmet exact condition.
- Unit and Behavior: the final focused canonical run passed 9/9 with zero
  failures in 0.016 seconds under
  `.build-local/evidence-driven-sync/SYNC-026B/targeted-attempt-007`.
  Coverage verifies observer-before-trigger ordering, initially satisfied
  state, synchronous trigger-return readback, independent key/main/CG
  conditions, exact identity and stale-generation rejection, retry after a
  rejected request, slow scheduling, terminal failure diagnostics,
  replacement/cancellation, and the representative coordinator path.
- FlowTabCore: not relevant because this contract belongs to the AppKit fixture
  topology and app-test targets and does not change a core-domain API.
- Pressure: the deterministic 500-cycle workload alternated successful
  observation and replacement/cancellation, forcibly delivered canceled
  event, retry, and watchdog work, accepted exactly the 250 live generations
  in monotonic order, produced no watchdog failures, and left no observation
  or scheduled work active. Delayed retry delivery changed only resolution
  time. The real two-window topology then exercised the final fullscreen
  completion, exact desktop-anchor refocus, and non-fullscreen CG readback;
  scheduling affected elapsed time while preserving the selected window and
  final Space result.
- UI: the required install wrapper rebuilt, signed, installed, and verified
  `/Users/lk/Applications/Flow Tab UITest.app`. The test resolves the fixture
  from the active Build Products boundary, removes prior fixture processes
  through observer plus process-state readback, and observes the exact
  frontmost PID, title/identifier XCUI window, matching CG window, and desktop
  frame through the SYNC-034A owner. The canonical wrapper passed
  `testSpaceFixtureRefocusesExactDesktopAnchorAfterFullscreenCompletion` 1/1
  with zero failures in 4.916 seconds under
  `.build-local/evidence-driven-sync/SYNC-034A/ui-attempt-002`.
- Oracle follow-up: the SYNC-028B2 diagnostic execution reached
  `testSpaceFixtureRefocusesExactDesktopAnchorAfterFullscreenCompletion`.
  Its shared `waitForExactFrontmostSpaceFixtureWindow` helper returned without
  a present exact window because absent AX and CG window numbers compared
  equal, and the test's independent nonnil assertion failed in 1.859 seconds
  under
  `.build-local/evidence-driven-sync/SYNC-028B2/ui-diagnostic-desktop-refocus-attempt-001`.
  SYNC-034A replaced that Oracle and its affected path now resolves only from
  present exact evidence.
- Process/Tooling: project-file lint, stale 1.2-second refocus-delay search,
  source-size checks, `git diff --check`, and exact staged-content review are
  recorded before commit. New production, test, and UI support files remain
  below 400 lines; the touched shared UI observation file remains below 800
  lines. Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `8c5554912551fe1b5f5edea0e4e85c0ad4e29a78`
  (`refactor(sync): migrate SYNC-026B desktop refocus`).

### SYNC-026C1 Closure Record

- Design and Oracle: FlowTab TestingSupport accepts explicit distributed
  acknowledgement routes containing a notification name, fixture bundle ID,
  and expected window count. It installs the app-switcher projection observer
  before its initial readback. A route publishes only when the committed
  projection is complete and clean and contains the exact bundle ID, a
  positive PID, and the expected window count. Published evidence includes
  monotonic observation and acknowledgement generations, exact PID and window
  count, and the complete runtime source-generation tuple. A distinct PID or
  source generation can publish fresh evidence while an identical notification
  is de-duplicated.
- Lifecycle: `FlowTabUITestProjectionAcknowledgementBootstrap` owns one
  route-specific observation owner for the application TestingSupport
  lifecycle. Reconfiguration cancels the prior observation before replacement.
  Application termination, explicit stop, owner cancellation, and empty routes
  remove the notification token and invalidate the active observation
  generation. Duplicate, canceled, replaced, and stale-generation callbacks
  cannot publish evidence.
- Retained time policy: none. This producer contract uses projection
  notifications plus immediate readback and introduces no sleep, polling
  cadence, timer, retry, deadline, or watchdog. The consumer-side terminal
  failure bound belongs to SYNC-026C2.
- Unit and Behavior: the final focused canonical run passed 6/6 with zero
  failures in 0.004 seconds under
  `.build-local/evidence-driven-sync/SYNC-026C1/targeted-attempt-004`.
  Coverage verifies route validation and de-duplication,
  observer-before-readback ordering, initially satisfied projection evidence,
  rejection of incomplete, dirty, wrong-bundle, and wrong-window-count
  snapshots, later matching notification delivery, distinct PID publication,
  duplicate suppression, cancellation, and stale-generation rejection. The
  projection adapter independently verifies the exact PID, window count,
  source generation, and clean-complete rule.
- FlowTabCore: not relevant because the contract is test-only orchestration at
  the FlowTab application/runtime-projection boundary and adds no core-domain
  API.
- UI: the producer route remains dormant until SYNC-026C2 supplies the
  per-fixture notification route and consumes its cross-process evidence.
  End-to-end distributed transport and visible topology validation therefore
  join that consumer slice.
- Pressure: the deterministic 500-cycle lifecycle workload alternated matching
  evidence and cancellation, forcibly delivered stale callbacks, published
  exactly the 250 live acknowledgement generations in monotonic order, and
  left no observer active. Delayed evidence delivery changed only when
  acknowledgement occurred.
- Process/Tooling: the canonical wrapper built all six targets and passed the
  focused tests. Project-file lint, source-size checks, `git diff --check`, and
  exact staged-content review are recorded before commit. New production and
  test files remain below 400 lines; touched shared files remain below 800
  lines. Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `ea0b73d19ea0c1d725938a3c97d44648c6100d61`
  (`refactor(sync): publish SYNC-026C1 projection acknowledgement`).

### SYNC-026C2 Closure Record

- Design and Oracle: each workflow fixture receives a unique pair of
  distributed-notification routes. The fixture installs its projection
  acknowledgement observer before publishing windows, then records the exact
  local topology stage after the no-fullscreen path, the final ordered
  fullscreen transition, or the exact desktop-refocus readback. Suppression
  begins only when the local stage is complete, both application AX attributes
  expose the exact locally published count, and FlowTab has acknowledged the
  same bundle ID, positive PID, and exact projected window count. Completion
  requires both application AX attributes to read back zero and publishes a
  monotonic suppression generation together with the accepted projection
  generation and source generation. The fixture completion evidence carries
  the exact zero readback for both application AX attributes. The independent
  UI Oracle matches the exact running bundle/PID and reads the fixture's XCUI
  window collection as empty. The route-less compatibility mode resolves from
  the same exact local topology, published-count, and zero-readback evidence;
  its local owner generation closes without cross-process publication.
- Lifecycle: `SpaceFixtureWindowCoordinator` owns one
  `SpaceFixtureApplicationAXSuppressionOwner`. Starting a fixture replaces and
  cancels the prior observer, readback retry, and watchdog generation.
  Coordinator cancellation and application termination remove every token.
  Duplicate, regressed, mismatched, canceled, replaced, and stale-generation
  acknowledgements cannot request suppression or publish completion. The UI
  workflow installs all completion observers before launching FlowTab or any
  fixture and removes them at workflow cleanup.
- Retained time policy: AppKit and cross-process AX readback provide no
  delivery callback, so an unmet local AX condition uses an
  immediate-condition-first, named 100ms retry cadence. The suppression owner
  owns and cancels that retry; time never establishes success. Its named 15s
  watchdog performs a final readback and reports every unmet condition plus
  the previous and final evidence. The UI's 20s bound is terminal failure only
  and reports the latest completion and independent AX readback.
- Unit and Behavior: the final focused canonical run passed 13/13 with zero
  failures in 0.015 seconds under
  `.build-local/evidence-driven-sync/SYNC-026C2/targeted-attempt-007`.
  Coverage verifies the exact SYNC-026C1 transport parser,
  observer-before-initial-readback ordering, synchronously delivered and
  initially satisfiable evidence, wrong/duplicate/out-of-order
  acknowledgements, delayed local publication, delayed zero readback,
  cancellation, replacement, stale callback rejection, route-less
  configuration compatibility, missing-acknowledgement watchdog diagnostics,
  no-fullscreen suppression, ordered multi-fullscreen completion,
  single-fullscreen completion, and exact desktop-refocus gating. Slower retry
  delivery changes completion latency while preserving the result.
- Full FlowTabTests: the final canonical wrapper rebuilt all six targets and
  passed 966/966 with zero failures in 43.669 seconds under
  `.build-local/evidence-driven-sync/SYNC-026C2/full-attempt-005`. Attempt 003
  reproduced the assigned SYNC-032/SYNC-033 order-isolation failure in
  `testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterWorkspaceTerminationRefresh`;
  the isolated diagnostic passed 1/1 in 0.242 seconds before the complete green
  rerun.
- FlowTabCore: not relevant because this contract belongs to the standalone
  fixture, application TestingSupport transport, and UI orchestration
  boundaries and adds no core-domain API.
- Pressure: the deterministic 500-generation lifecycle workload synchronously
  acknowledged each exact fixture identity, alternated immediate and delayed
  zero readback, published completion generations 1 through 500 exactly once,
  canceled every watchdog and retry, produced no failure, and left no active
  observation. The real-topology pressure run then passed the representative
  AX-suppressed cross-Space/fullscreen test 1/1 in 33.911 seconds under
  `.build-local/evidence-driven-sync/SYNC-026C2/runtime-topology-pressure-attempt-004`.
  Its frozen application identity contract matched across 44 checks and all 44
  CPU/RSS samples, with zero rejected transient identities. The default noisy
  Option+Tab scenario in attempt 002 completed C2 suppression and its first
  visible phase, then reproduced a missing fresh acknowledgement for a repeated
  Darwin trigger. That independent shared UI transport contract remains
  assigned to SYNC-034.
- UI: after the install wrapper prepared and verified the configured UI
  application, the representative AX-suppressed cross-Space/fullscreen test
  passed 1/1 with zero failures in 33.974 seconds under
  `.build-local/evidence-driven-sync/SYNC-026C2/ui-attempt-005`. The fixture's
  terminal notification carried the exact PID, acknowledgement/source
  generations, and zero counts for both application AX attributes. The UI
  independently matched that running bundle/PID, observed zero XCUI windows,
  and completed both visible cross-Space selection phases.
- Process/Tooling: `plutil -lint` passed for the Xcode project; the canonical
  wrappers compiled the new fixture, test, and UI sources in their intended
  targets. The UI wrapper now incrementally rebuilds every fixture variant from
  the current source boundary for each invocation; this replaced a stale
  July 28 variant that lacked the C2 routes, and `bash -n` validates the
  wrapper. Stale-symbol and literal review confirms removal of the fixed 5s
  and post-fullscreen 8s suppression policies. Source-size review keeps every
  new source below 400 lines, reduces the touched coordinator test file from
  763 to 556 lines, reduces the touched multi-app UI orchestration file from
  1130 to 1103 lines, and reduces the UI wrapper from 809 to 670 lines.
  `git diff --check` and exact staged-content review are recorded before
  commit. Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `4d3a6222de4c38034625f5a62ca4efc23fb67375`
  (`refactor(sync): migrate SYNC-026C2 AX suppression`).

### SYNC-027A Closure Record

- Design and Oracle: a positive `--terminate-delay-ms` value is represented by
  `SpaceFixtureTerminationFaultPolicy`. The AppDelegate routes both
  `applicationShouldTerminate` and SIGTERM through one
  `SpaceFixtureTerminationFaultOwner`, which accepts the first request and
  publishes exact scheduled and applied evidence containing a monotonic
  generation, request source, configured duration, bundle ID, and PID. The
  optional distributed-notification route keeps existing launch
  configurations compatible. The representative UI path independently
  verifies the exact running process and FlowTab projection removal after the
  applied evidence.
- Lifecycle: the AppDelegate owns the fault owner, its single scheduled token,
  and the SIGTERM dispatch source. Application termination cancels the active
  generation and token, releases the signal source, and restores the default
  signal disposition. Duplicate application and signal requests share the
  first accepted generation. Cancellation and replacement reject late
  callbacks, and applied evidence is published before the termination action.
- Retained time policy: the configured positive duration is the fixture's
  intentional termination-latency fault contract. Scheduling publishes only
  scheduled evidence; applied evidence, exact process state, and FlowTab
  projection readback establish progress and completion. The named fault owner
  manages cancellation, so machine or scheduler delay changes when the fault
  applies while preserving the resulting termination semantics.
- Unit and Behavior: the final focused canonical run passed 7/7 with zero
  failures in 0.007 seconds under
  `.build-local/evidence-driven-sync/SYNC-027A/targeted-attempt-003`.
  Coverage verifies strict evidence transport parsing, scheduled-to-applied
  transition order, mixed-source duplicate handling, cancellation, stale
  callback rejection, synchronous scheduler reentrancy, and launch
  configuration compatibility for both simple and workflow routes.
- Full FlowTabTests: the final canonical wrapper rebuilt all six targets and
  passed 972/972 with zero failures in 47.539 seconds under
  `.build-local/evidence-driven-sync/SYNC-027A/full-attempt-002`.
- FlowTabCore: not relevant because this fault policy belongs to the standalone
  fixture, app-test transport, and UI orchestration boundaries and adds no
  core-domain API.
- Pressure: the deterministic 500-generation lifecycle workload accepted each
  generation exactly once, published every scheduled and applied transition
  in order, executed every accepted action once, canceled every token, and
  left no active generation. Scheduler delivery timing changed only the
  transition latency.
- UI: after the install wrapper refreshed and verified the signed UI
  application, the representative real-fixture quit path passed 1/1 with zero
  failures in 25.245 seconds under
  `.build-local/evidence-driven-sync/SYNC-027A/ui-attempt-002`. The observer was
  installed before fixture launch and the termination trigger. Attempt 001
  established that the real FlowTab quit path reaches the fixture through
  SIGTERM; the final test therefore validates the exact signal source, duration,
  bundle ID, PID, and generation across scheduled and applied evidence before
  independently observing process exit and projection removal.
- Process/Tooling: `plutil -lint` passed for the Xcode project, the canonical
  wrappers compiled the new fixture, test, and UI sources in their intended
  targets, and stale raw AppDelegate `asyncAfter` and pending-reply state are
  absent. Each new source remains below 400 lines; touched shared sources retain
  a clear single responsibility. `git diff --check` and exact staged-content
  review are recorded before commit. Startup `prompts.zip` remains unchanged
  and outside the slice.
- Commit: `44cb4dc3b9676cbb9444b9041017757912dff570`
  (`refactor(sync): retain SYNC-027A termination fault policy`).

### SYNC-027B Closure Record

- Design and Oracle: `SpaceFixtureWindowCloseFaultPolicy` retains the configured
  fixture fault latency, while `SpaceFixtureWindowCloseFaultOwner` establishes
  an exact request generation, bundle ID, PID, target plan index, and stable
  AppKit window number. The optional distributed trigger observer is installed
  before the initial topology readback and scheduled evidence. A matching
  trigger begins the configured delay after the consumer has independently
  observed its baseline. The route-less launch contract remains compatible and
  begins the delay after fixture publication. Applied evidence is emitted only
  after the target is absent from the coordinator plan indices, the AppKit
  window is invisible, and the exact CG window is off-screen.
- Lifecycle: the window coordinator owns the fault owner. Each active generation
  owns its trigger observer, configured-delay token, readback-retry token, and
  watchdog token. Replacement and cancellation remove every owned resource and
  reject stale callbacks. Duplicate, out-of-order, wrong-generation,
  wrong-bundle/PID, and wrong-plan triggers cannot advance the state machine.
  The target window retains its last positive AppKit window number so post-close
  WindowServer readback preserves exact-window identity.
- Retained time policy: `--close-window-delay-ms` is the intentional latency of
  the fixture's window-removal fault. The owner performs an immediate
  post-action readback. WindowServer provides no public exact-window
  close-completion callback, so a named cancellable 50ms condition cadence
  repeats that readback. A named 10-second watchdog is only a terminal failure
  bound and reports the final unmet conditions plus the last and final exact
  topology evidence. Scheduler and compositor load therefore change completion
  time while the same readback establishes the result.
- Unit and Behavior: the final focused canonical run rebuilt all six targets and
  passed 12/12 with zero failures in 0.016 seconds under
  `.build-local/evidence-driven-sync/SYNC-027B/targeted-attempt-007`.
  Coverage verifies strict evidence and trigger transport parsing, both simple
  and workflow launch routes, matching-trigger gating, initial satisfaction,
  default route compatibility, cancellation and replacement, delayed CG
  convergence, watchdog diagnostics, synchronous scheduling, and coordinator
  integration.
- Full FlowTabTests: the canonical wrapper rebuilt all six targets and passed
  981/981 with zero failures in 46.348 seconds under
  `.build-local/evidence-driven-sync/SYNC-027B/full-attempt-001`.
- FlowTabCore: not relevant because this contract belongs to the standalone
  fixture, app-test transport, and UI orchestration boundaries and adds no core
  domain API.
- Pressure: the deterministic 500-generation lifecycle workload resolved every
  generation from exact topology evidence, rejected every replaced callback,
  canceled every owned observer and token, emitted one terminal transition per
  accepted request, and left no active request.
- UI: attempt 001 supplied concrete regression evidence for the former
  orchestration: under the observed build and automation load, the configured
  7.5-second delay removed window 2 before FlowTab captured the initial
  two-window projection, yielding `1w` at the baseline assertion. Attempt 002
  was stopped before test-body execution by macOS UI-runner authentication
  cancellation (`LocalAuthentication Code=-2`). The elevated canonical rerun
  then passed the representative real-fixture mutation path 1/1 with zero
  failures in 21.348 seconds under
  `.build-local/evidence-driven-sync/SYNC-027B/ui-attempt-003`. Its observer was
  installed before fixture launch; FlowTab independently displayed `2w` before
  the exact trigger, and the test then observed matching applied evidence,
  window-2 nonexistence, retained window 1, and FlowTab's `1w` readback.
- Process/Tooling: `plutil -lint` passed for the Xcode project, and canonical
  wrappers compiled the fixture, app-test, and UI-test sources in their intended
  targets. New production and test sources remain below 800 lines with a single
  window-close fault responsibility; the UI observation helper remains below
  400 lines. The obsolete coordinator token and scheduling symbol are absent.
  `git diff --check` and exact staged-content review are recorded before commit.
  Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `80254968b03675f233928159d55e03c80e98e2d1`
  (`refactor(sync): migrate SYNC-027B window close fault`).

### SYNC-028A Closure Record

- Design and Oracle: `SpaceFixtureWindowCoordinator` starts one
  `SpaceFixtureWorkflowReadinessOwner` generation before showing any window.
  The owner publishes a configured baseline followed by evidence for the exact
  planned-window indices, ordered fullscreen completion, exact desktop-anchor
  presentation, and exact zero application-AX exposure when suppression is
  configured. It publishes terminal ready evidence only when every configured
  condition is satisfied, then updates the visible workflow label and summary.
  The shared single-process UI launcher installs a unique distributed observer
  before fixture launch, captures the configured generation, and accepts only a
  later ready stage with the same bundle ID, PID, exact window plan, and exact
  fullscreen plan. The independent UI Oracle also matches that PID to the
  running application and reads back the visible Ready label, workflow summary,
  fullscreen marker, and FlowTab's three exact window titles.
- Lifecycle: the window coordinator owns readiness replacement, cancellation,
  and application-lifetime cleanup together with the fullscreen, desktop, and
  AX evidence producers. One application identity snapshot supplies readiness,
  AX suppression, and window-fault evidence for the launch. Generations reject
  canceled, replaced, duplicate, out-of-order, and stale transitions.
  `SpaceFixtureWorkflowReadinessObservationOwner` owns the distributed token;
  the XCTest invocation starts it before launch and removes it on every exit.
  The readiness owner clears its completed generation before publishing the
  terminal callback, preserving a synchronously installed replacement.
- Retained time policy: the configured pre-fullscreen delay remains the fixture
  staging contract classified by SYNC-026A and is driven by the fixture
  scheduler. Readiness itself introduces no sleep, retry, timer, or polling
  cadence. `SpaceFixtureWorkflowReadinessUITestPolicy` supplies a named 20-second
  terminal bound, extended only by an explicitly configured fullscreen staging
  duration. Success comes exclusively from exact evidence and visible
  readback. A failure reports all observed stages, their unmet conditions,
  identity and generations; the final visible-state watchdog also reports its
  last label and terminal evidence.
- Unit and Behavior: the final focused canonical run rebuilt all six targets and
  passed 17/17 with zero failures in 0.029 seconds under
  `.build-local/evidence-driven-sync/SYNC-028A/targeted-attempt-009`.
  Coverage verifies strict transport parsing, malformed ready rejection, every
  exact topology prerequisite, initially satisfied no-fullscreen and route-less
  AX paths, ordered multi-fullscreen and desktop-refocus integration, routed AX
  completion, duplicate and out-of-order rejection, cancellation, replacement,
  stale generation rejection, synchronous publication reentrancy, launch-route
  compatibility, and one shared application identity snapshot.
- Full FlowTabTests: the canonical wrapper rebuilt all six targets and passed
  986/986 with zero failures in 58.560 seconds under
  `.build-local/evidence-driven-sync/SYNC-028A/full-attempt-001`.
- FlowTabCore: not relevant because this contract belongs to the standalone
  fixture, app-test transport, and UI orchestration boundaries and adds no core
  domain API.
- Pressure: the deterministic 500-generation lifecycle workload replaced every
  prior owner, delivered every stale generation, completed only the final
  generation once, and left no active observation. The focused state-machine
  test also delivered prerequisites late and out of order; changed delivery
  timing altered completion latency while preserving the terminal result.
- UI: the install wrapper rebuilt and verified the signed UI application. The
  final UI wrapper then rebuilt the current fixture and runner and passed
  `testHomePageShowsRealSpaceFixtureWorkflowWindows` 1/1 with zero failures in
  21.570 seconds under
  `.build-local/evidence-driven-sync/SYNC-028A/ui-attempt-002`. The observer was
  installed before launch. With a configured five-second fullscreen staging
  delay, the fixture completed exact fullscreen and desktop-refocus evidence,
  published the matching Ready generation, and FlowTab independently exposed
  all three planned windows.
- Process/Tooling: `swiftc -parse` passed for every touched Swift source,
  `plutil -lint` passed for the Xcode project, and canonical wrappers compiled
  the fixture, app-test, and UI-test sources in their intended targets. The new
  readiness owner and UI observer remain below 400 lines; the evidence
  transport and focused test source remain between 400 and 800 lines with one
  clear responsibility. Touched shared sources remain below 800 lines.
  `git diff --check` and exact staged-content review are recorded before
  commit. Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `9a8363f9f6e78704aeecf644d5e2f16a8e907563`
  (`refactor(sync): migrate SYNC-028A fixture readiness`).

### SYNC-028B1 Closure Record

- Design and Oracle:
  `SpaceFixtureWorkflowReadinessAggregateObservationOwner` creates one unique
  distributed-notification route per configured workflow app and starts every
  observer before the first fixture process launches. Its pure aggregate owner
  records the exact configured baseline for each workflow app ID, then accepts
  a terminal ready snapshot only when bundle ID, PID, fixture observation
  generation, later transition generation, planned-window indices,
  fullscreen-window indices, and ordered titles match that baseline. Readiness
  evidence delivered before its configured notification is buffered and
  validated against the later baseline, closing cross-process notification
  reordering without relaxing identity. The aggregate completes once after
  every configured process supplies exact terminal evidence. Standard and edge
  launchers now proceed from that aggregate snapshot.
- Lifecycle: the workflow invocation owns all notification tokens, the
  aggregate generation, the XCTest expectation, and cleanup on every return.
  Starting a replacement first cancels all prior tokens and invalidates the
  prior generation. Cancellation and generation equality reject retained
  delivery; duplicate terminal evidence cannot over-fulfil the aggregate. The
  owner clears a completed generation before invoking its callback, preserving
  a synchronously installed replacement.
- Retained time policy: the serialized `settleTimeoutMs` key remains accepted
  for workflow configuration compatibility and now supplies a lower bound for
  the named `readinessWatchdog`. The default 20-second policy also accounts for
  configured fullscreen staging. Completion comes exclusively from the exact
  aggregate evidence. Watchdog expiry reports every unmet workflow app stage
  and the last parsed identity, generations, topology, titles, and readiness
  conditions.
- Unit and Behavior: the final focused canonical run rebuilt all six targets
  and passed 9/9 with zero failures in 0.027 seconds (0.032 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-028B1/targeted-attempt-002`.
  Coverage includes exact all-process completion, ready-before-configured
  notification reordering, incorrect static identity rejection, duplicate
  completion, unmet-condition diagnostics, cancellation, replacement, stale
  aggregate generations, synchronous callback replacement, and per-process
  readiness transport and state-machine behavior.
- Full FlowTabTests: the canonical wrapper passed 990/990 with zero failures in
  47.883 seconds (48.047 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-028B1/full-attempt-001`.
- FlowTabCore: not relevant because the aggregate consumes fixture test
  evidence and belongs to the app-test/UI-test orchestration boundary; it adds
  no core domain API.
- UI: the standard three-application workflow passed
  `testHomePageShowsMultipleRealSpaceFixtureWorkflowAppsAndWindowCounts` 1/1
  with zero failures in 27.290 seconds under
  `.build-local/evidence-driven-sync/SYNC-028B1/ui-attempt-001`. The edge
  workflow then passed
  `testSwitcherPanelPreviewKeepsIdenticalRealWorkflowWindowsDistinct` 1/1 with
  zero failures in 18.166 seconds under
  `.build-local/evidence-driven-sync/SYNC-028B1/ui-attempt-002`. Both executions
  installed all process observers before launching any fixture, aggregated the
  exact Finder/Chrome/Notes identities and topologies, and preserved the
  independently asserted Home counts or duplicate-window identities.
- Pressure: the deterministic 500-generation aggregate workload replaced every
  prior owner, delivered all stale generations, completed only the final
  generation, and left no active observation. The real three-process UI paths
  exercised independent process scheduling and fullscreen topology; delivery
  latency changed elapsed time while the exact aggregate result remained
  stable.
- Slice boundary: SYNC-028B2 owns the final desktop-anchor activation and exact
  foreground/Space/window readback after aggregate readiness.
- Process/Tooling: canonical app-test and UI wrappers compiled the fixture,
  app-test, and UI-test sources in their intended targets. `plutil -lint`,
  scoped obsolete-settle search, Swift parse checks, source-size checks,
  `git diff --check`, and exact staged-content review are recorded before
  commit. All three new sources remain below 400 lines. Startup `prompts.zip`
  remains unchanged and outside the slice.
- Commit: `025ef62938cc3b930b520722e66a7a6a929eba76`
  (`refactor(sync): migrate SYNC-028B1 workflow readiness`).

### SYNC-028B2 Closure Record

- Design and Oracle:
  `SpaceFixtureWorkflowDesktopAnchorObservationOwner` installs exact
  application-activation and active-Space observers before invoking
  `XCUIApplication.activate()`, then performs an initial readback and a
  trigger-return readback. A snapshot resolves only when the aggregate
  readiness PID still identifies a running, active fixture process; XCUI
  reports that process foreground; `NSWorkspace` reports the same bundle and
  PID frontmost; and the PID-scoped topmost on-screen CG window has a valid
  desktop-sized frame. The matching XCUI window must have the same frame
  within a two-point WindowServer/UI-session tolerance and contain one exact
  configured plan accessibility identifier. The plan index, title, and
  identifier therefore preserve workflow and window identity across standard
  and duplicate-title edge fixtures.
- Event gap and lifecycle: application activation and active-Space
  notifications each trigger a fresh complete readback. Initial and
  trigger-return readbacks close already-satisfied and synchronous transition
  gaps. The workflow invocation owns the observation owner, which owns its
  notification tokens, main-run-loop timer, XCTest expectation, and pure
  observation generation. Success, watchdog, replacement, cancellation, and
  deinitialization remove observers and invalidate polling. Generation
  equality rejects stale delivery; taking the active generation before the
  callback preserves synchronous replacement.
- Retained time policy: AppKit and XCUIApplication expose no exact
  activation-completion callback for this cross-process desktop/Space
  condition. The owner therefore retains the named 100ms
  `conditionPollInterval`, after the immediate readback, and cancels it with
  the workflow invocation. The named 15-second `watchdog` is a terminal
  failure bound. Its final readback may still resolve success; a failure
  reports every unmet condition plus distinct last and final process,
  frontmost, XCUI plan-window/frame, CG window/frame, and desktop-Space
  evidence.
- Diagnostic design evidence: UI attempts 001 and 002 showed that focused/main
  application AX attributes and the raw application AX window tree were
  unavailable to the UI runner while the exact process, frontmost application,
  and CG window were present. The final Oracle uses the XCUITest session's
  exact plan-identified window tree joined to the PID-scoped CG frame; UI
  attempts 003 through 006 then resolved immediately from that observable
  evidence, with the final two also requiring the observed accessibility label
  to match the configured title.
- Unit and Behavior: after the evidence/owner source split, the final focused
  canonical run rebuilt all six targets and passed 9/9 with zero failures in
  0.019 seconds (0.021 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-028B2/targeted-attempt-009`.
  Coverage includes initially satisfied state, exact process/frontmost/plan/
  XCUI/CG/desktop requirements, mismatched frames, cancellation, replacement,
  stale delivery, synchronous replacement, terminal diagnostics, slow
  conditional observation, and the existing desktop-refocus retry contract.
  The final staged-review supplement passed 2/2 with zero failures in 0.002
  seconds (0.003 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-028B2/targeted-attempt-010`,
  explicitly verifying duplicate post-completion delivery rejection and the
  retained last/final watchdog diagnostic.
- Full FlowTabTests: the canonical wrapper passed 996/996 with zero failures in
  49.814 seconds (49.988 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-028B2/full-attempt-001`.
- FlowTabCore: not relevant because the contract belongs to fixture UI-test
  orchestration and adds no core-domain API or runtime dependency.
- UI: the canonical install wrapper rebuilt and verified the fixed-path Apple
  Development-signed app before the final executions. The standard
  three-application workflow passed
  `testHomePageShowsMultipleRealSpaceFixtureWorkflowAppsAndWindowCounts` 1/1
  with zero failures in 27.368 seconds under
  `.build-local/evidence-driven-sync/SYNC-028B2/ui-attempt-005`. The
  duplicate-title edge workflow passed
  `testSwitcherPanelPreviewKeepsIdenticalRealWorkflowWindowsDistinct` 1/1
  with zero failures in 18.151 seconds under
  `.build-local/evidence-driven-sync/SYNC-028B2/ui-attempt-006`. Both paths
  activated the exact readiness PID and resolved the configured plan window on
  a desktop Space before continuing to their independent visible Oracles.
- Pressure: the deterministic lifecycle workload installed 500 replacement
  generations, delivered every stale generation, held the final generation
  across 50 incomplete condition readbacks, then resolved exactly once from
  final evidence and left no active owner. The two real multi-process UI paths
  exercised distinct workflow identities and scheduling; added observation
  latency changed completion time while preserving the exact result.
- Audit follow-up: the separate diagnostic run of the existing SYNC-026B UI
  path exposed the shared optional-window-identity defect registered as
  SYNC-034A. SYNC-028B2 uses a present XCUI plan window joined to a present CG
  window and its unit coverage rejects missing or mismatched identities.
- Process/Tooling: canonical wrappers compiled the evidence model, pure owner,
  UI lifecycle owner, and tests in both intended app-test targets.
  `plutil -lint`, Swift parse checks, source-size checks, scoped obsolete-wait
  review, `git diff --check`, and exact staged-content review are recorded
  before commit. All four new sources remain below 400 lines; the touched
  shared UI observation source remains below 800 lines. Startup `prompts.zip`
  remains unchanged and outside the slice.
- Commit: `397ab8c3f3d70537ff3619754d04181d2a38acba`
  (`refactor(sync): migrate SYNC-028B2 desktop anchor`).

### SYNC-034A Closure Record

- Defect and independent Oracle: the existing shared helper compared optional
  AX and CG window numbers directly, so two absent observations could return
  success. The independent nonnil assertion in the SYNC-026B real fixture UI
  reproduced the false positive in 1.859 seconds under
  `.build-local/evidence-driven-sync/SYNC-028B2/ui-diagnostic-desktop-refocus-attempt-001`.
  `SpaceFixtureWorkflowDesktopAnchorSnapshot.exactWindowIdentityMatches`
  now requires a present CG window number plus valid matching XCUI and CG
  frames; focused coverage rejects absent frames, missing CG identity, and
  mismatched frames before accepting exact evidence.
- Design and Oracle:
  `waitForExactFrontmostSpaceFixtureWindow` now delegates to
  `SpaceFixtureWorkflowDesktopAnchorObservationOwner`. Resolution requires the
  requested bundle and PID to be running, active, frontmost, and
  XCUI-foreground; the exact requested title and accessibility identifier must
  identify the XCUI window whose frame matches the present PID-scoped topmost
  on-screen CG window; and that window must have a desktop-Space frame. The
  snapshot reads `XCUIApplication.state` first and treats `.notRunning` as
  incomplete attachment evidence without querying the window tree. A later
  attachment therefore changes only completion time.
- Observation and lifecycle: the reused owner installs application-activation
  and active-Space observers before its initial readback. AppKit and
  XCUITest expose no exact callback for automation attachment plus the joined
  cross-process window condition, so the owner retains its named immediate-
  check-first 100ms condition poll. The helper invocation owns the owner and
  cancels observers, timer, expectation, generation, and pending delivery on
  success, failure, or return. The caller-owned named 25-second watchdog is a
  terminal failure bound whose final readback reports every unmet condition
  and the last/final process, XCUI, CG, frame, and Space evidence.
- Implementation cleanup: the private-symbol AX window-number bridge and its
  recursive identifier walk had no remaining owner after the exact
  plan-window/CG-frame join, so their source and project entries were removed.
  The shared UI observation source shrank while preserving its other AX and CG
  helpers.
- Unit and Behavior: the focused canonical wrapper rebuilt all six targets and
  passed 5/5 with zero failures in 0.004 seconds (0.005 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-034A/targeted-attempt-001`.
  Coverage includes absent and mismatched exact-window evidence, initially
  satisfied exact evidence, independent process/window/desktop conditions,
  cancellation, replacement, duplicate delivery rejection, and final watchdog
  diagnostics. The full canonical wrapper then passed 997/997 with zero
  failures in 49.190 seconds (49.345 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-034A/full-attempt-001`.
- FlowTabCore: not relevant because this contract belongs to fixture UI-test
  orchestration and changes no core-domain API or runtime dependency.
- UI: the first owner-backed run correctly rejected completion while the
  NSWorkspace-launched fixture was not yet attached to XCUITest, exposing the
  attachment-readiness query race. After attachment became explicit snapshot
  evidence, the desktop-refocus path passed 1/1 in 4.916 seconds under
  `.build-local/evidence-driven-sync/SYNC-034A/ui-attempt-002`. Expanded shared
  infrastructure regression passed the standard three-application workflow
  in 27.587 seconds and the duplicate-title edge workflow in 19.643 seconds,
  2/2 with zero failures in 47.229 seconds (47.231 seconds total), under
  `.build-local/evidence-driven-sync/SYNC-034A/ui-shared-regression-attempt-001`.
- Pressure: the reused owner retained the deterministic 500-generation
  replacement/cancellation workload, including 50 incomplete condition
  readbacks and forced stale delivery, and the SYNC-026B owner retained its
  independent 500-cycle retry/observer/watchdog workload. The three final real
  UI paths covered desktop refocus, independently scheduled multi-process
  readiness, and duplicate-title window identity without result drift.
- Process/Tooling: the canonical install, app-test, and UI wrappers rebuilt the
  intended six targets and verified signing before execution. Project-file
  lint, Swift parse checks, obsolete bridge/reference review, source-size
  checks, `git diff --check`, and exact staged-content review are recorded
  before commit. The new focused test remains below 400 lines; touched shared
  UI sources remain below 800 lines. Startup `prompts.zip` remains unchanged
  and outside the slice.
- Commit: `8092758e0e0fca7eb0d9a6345f504b9c50b900db`
  (`refactor(sync): migrate SYNC-034A exact window oracle`).

### SYNC-029 Closure Record

- Design and initial Oracle:
  `FlowTabUITestInitialPresentationObservationOwner` installs the exact
  runtime-service projection routes before its baseline readback and readiness
  request. Global presentation derives its item signature from the complete
  app-switcher projection after window-recency and app-visibility filtering.
  In-app presentation derives the focused app PID, app ID, and recency-ordered
  window IDs from the complete current-app projection. An initially complete
  nonempty projection can present immediately; an initially complete empty
  projection resolves as authoritative no-content. Later evidence must be a
  newly available projection, a component-wise monotonic generation, or a
  same-generation incomplete-to-complete transition. Regressed generations,
  duplicate candidates, and stale owner generations cannot present.
  `RuntimeReadModelGeneration` owns the shared component-wise monotonic
  comparison in Runtime infrastructure, so Home and TestingSupport consume one
  dependency-safe generation contract.
- Presentation readback: success requires the controller to report a presented
  session whose exact ordered item signature equals the accepted projection
  candidate. The post-action projection must preserve mode, PID, and item
  identity at the same or a component-wise monotonic later generation.
  Session-start maintenance may temporarily mark that later projection
  incomplete while preserving the accepted identity, so scheduling latency
  changes freshness convergence time without changing the presentation
  result. A changed PID or item signature cancels the presentation and waits
  for fresh evidence.
- Observation and lifecycle: the global route observes app-switcher projection
  commits; the in-app route observes both current-app and app-switcher
  projection commits. Each notification performs a full readback. One static
  bootstrap owner replaces and cancels the prior generation during app
  preparation, and AppDelegate termination cancels it before runtime service
  teardown. Resolution, no-content, watchdog failure, explicit cancellation,
  replacement, and deinitialization remove notification tokens; the owner
  cancels its watchdog and rejects every late generation.
- Retained time policy: the former presentation retry cadence and stable-
  snapshot count were removed. The named three-second `watchdog` remains only
  as a terminal failure bound. It performs one final readback that can still
  resolve success, then reports the unmet projection conditions and distinct
  last/final generation, completeness, PID, item, dirty-scope, presentation,
  Search, and post-readback evidence.
- Diagnostic correction: UI attempt 001 passed the real fixture path and
  exposed a mock Search failure where successful `startSession` maintenance
  advanced the projection before the immediate post-readback. The log recorded
  the exact unchanged six-app signature at a later temporarily incomplete
  generation. The final compatibility Oracle above removes that
  scheduler-dependent result while retaining exact identity checks.
- Unit and Behavior: the final focused canonical wrapper passed 8/8 with zero
  failures in 0.389 seconds (0.390 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-029/targeted-attempt-006`.
  Coverage includes initial complete and complete-empty states, observer-before-
  trigger ordering, same-generation completeness, later monotonic generation,
  regressed and stale generations, exact session mismatch, post-readback
  identity mismatch, duplicate candidate rejection, fresh retry, explicit
  cancellation, replacement, final-watchdog success, and last/final watchdog
  failure diagnostics. AppDelegate behavior verifies one later complete
  projection notification presents the exact two-app session and that
  complete-empty evidence performs no maintenance request.
- Full FlowTabTests: the canonical wrapper passed 1002/1002 with zero failures
  in 47.781 seconds (47.926 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-029/full-attempt-002`.
- FlowTabCore: not relevant because this owner exists only in the app
  `FLOWTAB_TESTING` boundary and adds no core-domain API or dependency.
- UI: the canonical install wrapper rebuilt and verified the fixed-path Apple
  Development-signed app for the final source state. The real fixture standard
  switcher path passed in 21.953 seconds and the mock window-Search launch path
  passed in 6.739 seconds, 2/2 with zero failures in 28.692 seconds (28.693
  seconds total), under
  `.build-local/evidence-driven-sync/SYNC-029/ui-attempt-003`. Their independent
  Oracles were the exact fixture app tile and exact mock Inbox window result.
- Pressure: the deterministic owner workload replaced 500 generations,
  force-delivered every cancelled watchdog and stale generation, then resolved
  the final generation exactly once. Its explicit-cancellation phase delivered
  a cancelled watchdog after a later ready snapshot and produced no callback.
  The post-presentation regression also advances to a later incomplete
  generation with the same identity and preserves the exact result.
- Process/Tooling: canonical wrappers compiled the four TestingSupport sources
  and three test sources in their intended targets. Project-file lint, Swift
  parse checks, scoped obsolete-wait review, source-size checks,
  `git diff --check`, and exact staged-content review are recorded before
  commit. Every new production source remains within the 400-line guardrail;
  the touched oversized AppDelegate lifecycle test source shrank. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `1c4dae662a0a9179b8edde21fb9ce8adc34e4385`
  (`refactor(sync): migrate SYNC-029 initial UI readiness`).

### SYNC-030A Closure Record

- Classification and policy:
  `--flowtab-ui-mock-window-preview-delay-ms` remains compatible and is
  classified as intentional mock I/O latency. The named
  `FlowTabUITestMockWindowPreviewLatencyPolicy` preserves the previous one-to-
  1,000 millisecond bounds. Elapsed time releases the injected capture work;
  it never establishes preview success.
- Owner and evidence:
  `FlowTabUITestMockWindowPreviewLatencyOwner` assigns exact owner and batch
  generations, request count, bounded policy, and `elapsed` or `cancelled`
  outcome to every wait. Its deadline waiter uses monotonic `DispatchTime`,
  registers each blocking capture, and signals all registered waiters on
  cancellation. Bootstrap preparation and replacement cancel the current
  owner; AppDelegate termination and owner deinitialization provide the final
  cleanup boundaries. Stopping also removes the installed model batch override.
  A cancelled batch returns no mock capture result.
- Independent Oracle: the existing preview pipeline accepts only its capture
  result, exact resolved window identity, current preview generation, cache
  application, and visible preview readback. TestingSupport now logs latency
  evidence independently. The representative UI test requires both exact
  preview-image identifiers and the `preview_batch_completed` state in addition
  to the injection marker.
- Unit and Behavior: the final focused canonical wrapper passed 5/5 with zero
  failures in 0.012 seconds (0.014 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-030A/targeted-attempt-003`.
  Coverage verifies policy bounds, exact elapsed evidence, an in-flight
  cancellation released by owner cancellation, the existing launch-option
  contract, Bootstrapper replacement/stop generation and override cleanup, and
  500 owner replacements retaining one final elapsed outcome.
  Attempt 001 stopped at compilation because two new test callbacks captured
  mutable arrays under `@Sendable`; the final tests store callback evidence
  behind an explicit lock.
- Expanded Behavior: the final complete canonical wrapper passed 1006/1006
  with zero failures in 48.409 seconds (48.565 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-030A/full-attempt-002`. Attempt 001
  reproduced the previously recorded suite-order duplicate hotkey-registration
  pair; its exact isolated rerun passed 1/1, and the final complete execution
  passed the same case in suite order.
- FlowTabCore: not relevant because the fault injection is confined to
  TestingSupport, the app-test target, and the UI-test path.
- UI: attempt 001 was blocked before the test body when macOS timed out while
  enabling automation mode. The canonical rerun passed
  `testControlTabFirstPhysicalGestureSelectsNextWindowWithVisiblePreview` 1/1
  with zero failures in 8.095 seconds under
  `.build-local/evidence-driven-sync/SYNC-030A/ui-attempt-003`. It observed the
  80ms elapsed marker, selected the exact secondary current-app window, exposed
  both exact preview images, and recorded preview-batch completion.
- Pressure: the deterministic 500-generation workload cancelled every prior
  owner, force-observed each stale owner as `cancelled`, and allowed only
  generation 500 to report `elapsed`. In-flight cancellation used explicit
  start and release evidence, so scheduler speed changed only completion time.
- Process/Tooling: project-file lint, Swift parse checks, scoped timing review,
  source-size checks, `git diff --check`, and exact staged-content review are
  recorded before commit. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Commit: `65a74c1b672aa62fc4a0ed7ca4ec1c7bc7eaa4fd`
  (`refactor(sync): migrate SYNC-030A preview latency`).

### SYNC-030B Closure Record

- Classification and policy:
  `--flowtab-ui-initial-panel-occlusion-stale-ms` remains compatible and is
  classified as an intentional TestingSupport staleness interval. The named
  `FlowTabUITestInitialPanelOcclusionStalenessPolicy` bounds the retained
  interval from one to 5,000 milliseconds. Elapsed time releases the injected
  stale state; exact panel readback and the existing recovery state establish
  the result.
- Owner and evidence:
  `FlowTabUITestInitialPanelOcclusionStalenessOwner` assigns monotonic owner and
  transition generations and publishes `installed`, `released`, or `cancelled`
  evidence with the bounded policy plus panel-availability, override-installed,
  and override-visible readback. The injected scheduler returns one cancellable
  release token. Replacement cancels the preceding generation before installing
  the next override, and a force-delivered stale callback is rejected by exact
  generation. Bootstrap preparation and explicit stop own synchronous cleanup;
  AppDelegate termination stops the owner, and owner deinitialization schedules
  token and injection cleanup on the main actor.
- Independent Oracle: the representative UI path requires exact installed and
  released evidence for the 260ms policy, the existing
  `presentationRecovery trigger=global_show action=complete` evidence, and the
  exact mock-browser switcher tile. The duration remains isolated from the
  panel-visibility and recovery success Oracle.
- Unit and Behavior: the final focused canonical wrapper passed 5/5 with zero
  failures in 0.108 seconds (0.109 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-030B/targeted-attempt-003`.
  Coverage verifies policy bounds, installed/released readback, explicit
  cancellation, replacement, force-delivered stale work, synchronous scheduler
  delivery, and deinitialization cleanup. Attempt 001 captured a compiler
  diagnostic for main-actor cleanup from `deinit`; the final implementation
  transfers the captured token and mutation into a main-actor cleanup task.
- Expanded Behavior: the complete canonical wrapper passed 1011/1011 with zero
  failures in 48.035 seconds (48.192 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-030B/full-attempt-001`.
- FlowTabCore: not relevant because this fault-injection policy and owner are
  confined to app TestingSupport, app tests, and the UI-test launch protocol.
- UI: the current signed test app installed successfully. The canonical
  `testSwitcherInitialPresentationStaleOcclusionDoesNotHardRecover` execution
  passed 1/1 with zero failures in 4.994 seconds (4.997 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-030B/ui-attempt-001`. It observed both
  exact staleness phases, completed presentation recovery, and found the exact
  visible switcher item.
- Pressure: the deterministic 500-generation replacement workload cancelled
  generations 1 through 499, force-delivered all of their callbacks, and
  accepted a release only for generation 500. Every scheduler token finished
  cancelled, so scheduling latency changes completion time while the exact
  generation determines the outcome.
- Process/Tooling: project-file lint, Swift parse checks, scoped timing review,
  source-size checks, `git diff --check`, and exact staged-content review are
  recorded before commit. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Commit: `e6ee592e35033f64b478b0a740e370e992e7a9ab`
  (`refactor(sync): migrate SYNC-030B occlusion staleness`).

### SYNC-031 Closure Record

- Classification and workload contract: the compatible
  `--flowtab-tab-stress-duration` and
  `--flowtab-tab-stress-interval-ms` inputs remain domain-duration pressure
  controls. `TabSwitchStressPolicy` bounds and converts them to monotonic
  nanoseconds, then derives an exact `ceil(duration / cadence)` selection
  workload. The first selection is immediate. Every later selection uses the
  named cadence, while completion requires both the requested duration and the
  complete planned workload.
- Owner and evidence: `TabSwitchStressRunner` owns one monotonic run
  generation, one transition generation, and at most one cancellable scheduler
  token. Each attempt records the requested target and reads back the exact
  selected tab. A matching readback advances the planned sequence; a mismatch
  retains the same target for a later attempt. Completion publishes the policy,
  attempts, confirmed switches, final requested/observed target, elapsed time,
  and both terminal conditions before requesting application termination.
  Explicit stop, AppDelegate termination, owner replacement, and
  deinitialization cancel the owned wake and reject stale callbacks.
- Independent Oracle: elapsed time releases cadence/deadline scheduling.
  Selection success comes from the exact `HomeTabState.selectedTab` readback.
  UI establishes a unique distributed-notification observer before launching
  the app, accepts the exact completed evidence, and then requires the process
  state to become `notRunning`. The stdout evidence route gives the pressure
  workflow the same exact workload and readback record.
- Unit and Behavior: the final focused canonical wrapper passed 10/10 with zero
  failures in 0.020 seconds (0.022 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-031/targeted-attempt-002`.
  Coverage verifies compatible input normalization, exact workload plus
  duration completion, immediate first selection, five-second delayed
  scheduling with the same target sequence and count, mismatched-readback
  retry, explicit cancellation, stale-generation rejection, synchronous
  scheduler delivery, deinitialization cleanup, and AppDelegate stop ownership.
- Expanded Behavior: the complete canonical wrapper passed 1020/1020 with zero
  failures in 48.257 seconds (48.440 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-031/full-attempt-001`.
- FlowTabCore: not relevant because this pressure workload is confined to the
  app TestingSupport boundary and its app/UI test targets.
- UI: the current Apple Development-signed test app installed successfully.
  The canonical `testTabSwitchStressCPUAndMemory` execution passed 1/1 with
  zero failures in 59.702 seconds (59.705 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-031/ui-attempt-001`. Each of its three
  measured launches established the observer before launch, accepted exactly
  125/125 readback-confirmed selections for the two-second/16ms policy, and
  observed exact process termination.
- Pressure: the deterministic 5,000-selection run preserved the exact cyclic
  sequence, count, five-second duration, one terminal result, and cancellation
  of every scheduler token. The 1,000-generation replacement run
  force-delivered every cancelled wake and allowed only generation 1,001 to
  complete. The real 20-second/20ms workload completed 1,000/1,000 exact
  selections in 87.399 seconds with 175 samples under
  `.build-local/evidence-driven-sync/SYNC-031/tab-switch-pressure-20ms-attempt-001`.
  The 20-second/50ms comparison completed 400/400 exact selections in 35.279
  seconds with 71 samples under
  `.build-local/evidence-driven-sync/SYNC-031/tab-switch-pressure-50ms-attempt-001`.
  Both recorded zero process/build failures and true duration/workload terminal
  evidence. The scheduling load changed completion latency while preserving
  the exact workload result.
- Process/Tooling: canonical app-test, install, UI, and pressure wrappers built
  the intended targets. Project-file lint, Swift parse checks, scoped timing
  review, source-size checks, `git diff --check`, and exact staged-content
  review are recorded before commit. Every new production and test source
  remains within the 400-line guardrail; the touched oversized switcher UI test
  source shrank. Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `3b4668a26ae3ab89f957b6a66aa5f6a07848269e`
  (`refactor(sync): migrate SYNC-031 tab stress`).

### SYNC-032A Closure Record

- Design and Oracle: both AppVisibility tests subscribe to the model's
  `@Published isLoading` stream before invoking `reload()`. The subscription
  first requires an observed loading value, then accepts the following idle
  value exactly once. The initial idle state therefore remains a baseline and
  cannot satisfy completion. Final assertions independently read the loaded
  app inventory, hidden count, selected app, and filtered Pinyin result.
- Lifecycle: each async test scope owns its Combine cancellable set. The
  one-shot publisher completes after the matching transition and test teardown
  releases the subscription. The five-second XCTest timeout is only a failure
  bound for a missing lifecycle transition.
- Unit and Behavior: the focused canonical wrapper passed 2/2 with zero
  failures in 0.531 seconds (0.533 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032A/targeted-attempt-002`.
  It covers the mock-runtime searchable inventory and a persisted hidden app
  absent from inventory.
- Expanded Behavior: removing the `FlowTabTests+Support.waitUntil` wall-clock
  loop affected the shared test target, so the complete canonical wrapper was
  run and passed 1020/1020 with zero failures in 46.723 seconds (46.870 seconds
  total) under
  `.build-local/evidence-driven-sync/SYNC-032A/full-attempt-003`.
  Diagnostic attempt 002 executed all 1020 tests and captured one transient
  duplicate hotkey-registration readback in the AppDelegate launch-bootstrap
  test before either extracted AppVisibility test ran. The exact failing test
  then passed 1/1 in
  `.build-local/evidence-driven-sync/SYNC-032A/bootstrap-rerun-001`; the
  preserved failure remains input to the planned AppDelegate delivery and
  launch-bootstrap slices.
- FlowTabCore, UI, and Pressure: not relevant because the slice changes only
  app-test synchronization around an existing published task lifecycle and
  does not change runtime behavior or a hot path.
- Process/Tooling: the canonical wrapper compiled all app, app-test, UI-test,
  fixture, and core targets. `plutil` project lint and Swift parse passed.
  Scoped timing review confirms that
  `FlowTabTests+Support` no longer contains a date deadline, task sleep, polling
  interval, or cancellation-swallowing wait. The focused new source is 72
  lines; the touched pre-existing oversized preferences source shrank from
  1,733 to 1,679 lines, and support shrank from 568 to 551 lines.
  `git diff --check` and exact staged-content review are recorded before commit.
  Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `83dc6d6adba43da1f3d4c5bf8ce7aa9c57718ed2`
  (`test(sync): migrate SYNC-032A app visibility reload`).

### SYNC-032B1 Closure Record

- Design and Oracle: the runtime-projection recording double exposes exact
  launch and termination callbacks. The test installs both callbacks before
  posting either workspace notification, accepts only the current appID/PID
  instance, and additionally requires the launch directory entry to carry that
  same identity. Callback expectations establish delivery; independent final
  arrays establish exact one-event readback. The existing coordinator assertion
  also proves that launch-window observation was prepared before the launch
  signal.
- Lifecycle: the test scope removes both recording callbacks in explicit
  teardown and in `defer`. It terminates the AppDelegate, posts launch and
  termination notifications again, and verifies that both recording arrays
  remain unchanged, proving workspace-observer cleanup.
- Retained time policy: the one-second XCTest expectation timeout is a terminal
  failure watchdog. Delivery succeeds only from the exact callback. The
  expectation descriptions identify the unmet transition and the following
  array assertions expose the final observed appID/PID evidence.
- Unit and Behavior: the final focused canonical wrapper passed 1/1 with zero
  failures in 0.038 seconds (0.039 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032B1/targeted-attempt-002`.
  The final complete canonical wrapper passed 1020/1020 with zero failures in
  47.899 seconds (48.046 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032B1/full-attempt-002`.
- FlowTabCore, UI, and Pressure: not relevant because this slice changes only
  app-test observation around existing synchronous workspace notification
  delivery and does not change runtime behavior, visible behavior, repeated
  asynchronous work, or a hot path.
- Process/Tooling: project-file lint, Swift parse, scoped timing review,
  `git diff --check`, and exact staged-content review are recorded before
  commit. The focused source is 169 lines. The touched pre-existing oversized
  AppDelegate test source shrank from 1,337 to 1,225 lines; the shared
  test-double source remains below its 800-line guardrail at 785 lines. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `65ef5cb4561d8a88a2a6fe0d07aee8a29b0d124d`
  (`test(sync): migrate SYNC-032B1 workspace delivery`).

### SYNC-032B2 Closure Record

- Pre-change evidence: complete FlowTabTests runs independently reproduced the
  launch-bootstrap assertion with the exact duplicate registration signatures
  `[FTAB, FTWN, FTAB, FTWN]` under
  `.build-local/evidence-driven-sync/SYNC-032A/full-attempt-002` and
  `.build-local/evidence-driven-sync/SYNC-032B2/full-attempt-001`. The hotkey
  observer received on the main queue but deferred its active-delegate check
  into an unowned `MainActor` task. Restoring `AppDelegate.shared` could
  therefore let an older delegate accept a historical notification through
  later global test hooks.
- Design and Oracle: the observer now enters the AppDelegate main-actor boundary
  directly from its declared main operation queue and handles the notification
  before delivery returns. It accepts only the delegate active at receipt,
  rejects self delivery and missing payloads, and applies the exact request.
  The test establishes a registration-evidence expectation before posting,
  filters by baseline-plus-one generation, request ID, and both configurations,
  then independently reads back registration evidence, the two exact monitor
  signatures and IDs, monitor starts, prior-monitor stops, and takeover result.
- Lifecycle and scheduling: AppDelegate owns the observer token from launch
  through termination and removes it synchronously. Notification delivery no
  longer creates asynchronous work that can outlive that token. A two-delegate
  regression changes `shared` only after delivery and yields the executor; the
  original receipt owner and exact generation remain unchanged. After both
  delegates terminate, a further notification leaves every generation and
  monitor record unchanged.
- Unit: not relevant because no pure domain rule or normalization changed; the
  contract is AppDelegate notification orchestration and is exercised at the
  Behavior layer.
- Behavior: the final focused canonical wrapper passed 2/2 with zero failures
  in 0.117 seconds (0.118 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032B2/targeted-attempt-005`.
  The final complete wrapper passed 1021/1021 with zero failures in 49.062
  seconds (49.232 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032B2/full-attempt-003`. The
  previously failing launch-bootstrap test passed in the same suite order.
- UI: not relevant because the normal Settings path already performs exact
  registration synchronously through `requestHotkeyReload`; this slice changes
  multi-delegate notification ownership and app-test observation without
  changing a visible control, persisted configuration, or single-delegate user
  journey.
- Pressure: the focused two-delegate lifecycle test alternated 500 exact
  notifications between active owners in 0.080 seconds. It verified 500
  per-delivery request-ID matches, exact per-owner generations, and 1,000
  replacement monitor records, then yielded scheduling and posted after both
  observer owners terminated without any additional evidence. This is a new
  deterministic
  local lifecycle baseline rather than a CPU/RSS regression comparison; the
  path has bounded work per infrequent configuration notification.
- FlowTabCore: not relevant because the observer and regression remain inside
  the app and app-test targets and add no core API or dependency.
- Process/Tooling: the canonical wrapper compiled all app and app-test sources.
  Project-file lint, Swift parse, scoped obsolete-wait review, source-size
  checks, `git diff --check`, and exact staged-content review are recorded
  before commit. The focused test source is 375 lines; production AppDelegate
  remains a single-responsibility 631-line source, and the touched pre-existing
  oversized lifecycle test shrank from 1,225 to 1,123 lines. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `06f26034464bc2529b920c2a33a70aaea12cbcbc`
  (`refactor(sync): migrate SYNC-032B2 hotkey delivery`).

### SYNC-032C Closure Record

- Design and Oracle: the termination-refresh regression now installs
  `onSearchStateChanged` before submitting the initial query and accepts only
  the active app scope, exact `bro` query, and exact `Browser` result. It then
  replaces that callback and installs `onSessionLayoutChanged` before changing
  the runtime projection or delivering the exact terminated app/PID. The
  second Search callback requires the refreshed app count and the same exact
  Search state. Both matching publications establish completion; independent
  final model readback confirms the committed projection, scope, query, and
  result.
- Lifecycle and retained time policy: the test scope clears both model
  callbacks in `defer`. One-shot guards reject repeated callback delivery.
  The one-second XCTest expectations are terminal failure watchdogs for the
  named missing Search or layout publication and never establish success.
  Both 10ms polling loops and their cancellation-swallowing sleeps were
  removed.
- Unit, Behavior, and Pressure: the focused canonical wrapper passed 3/3 with
  zero failures in 0.408 seconds (0.409 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032C/targeted-attempt-001`. The
  migrated termination-refresh Behavior test passed together with the
  scheduling owner's cancelled/out-of-order completion test and deterministic
  2,000-mutation latest-owner pressure test. Scheduler delay and superseded
  work cannot change the accepted revision or final result.
- Expanded Behavior: the complete canonical wrapper executed 1,021 tests and
  reported one independent suite-order failure in
  `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  after 49.513 seconds (49.681 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032C/full-attempt-001`. Its exact
  monitor signatures were `[FTAB, FTWN, FTAB, FTWN]`. The same test passed 1/1
  in 0.511 seconds under
  `.build-local/evidence-driven-sync/SYNC-032C/bootstrap-isolated-attempt-001`.
  The hosted-launch observation and lifecycle contract is assigned to
  SYNC-032H; the goal remains active.
- FlowTabCore and UI: not relevant because this slice changes only app-test
  observation of the existing model Search and projection callbacks. It adds
  no core-domain API, production behavior, visible control, or UI topology.
- Process/Tooling: the canonical wrapper compiled all six targets. Project-file
  lint, Swift parse, source-size review, and `git diff --check` passed. The
  focused source is 104 lines, and extracting the regression reduced the
  touched pre-existing oversized test source from 946 to 891 lines. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `a8469a684c5e7f504f598e78d9aeb3f00905674f`
  (`test(sync): migrate SYNC-032C termination search refresh`).

### SYNC-032H Closure Record

- Pre-change evidence: the complete Priority class reproduced the launch test's
  duplicate monitor signatures `[FTAB, FTWN, FTAB, FTWN]` with one failure
  among 585 tests under
  `.build-local/evidence-driven-sync/SYNC-032H/priority-source-diagnostic-attempt-002`.
  Permanent registration evidence identified generation 2 as
  `source=settings_view` with the same default configurations. Resetting
  stored preferences during UI-test bootstrap caused a hosted Settings view
  to request an already-applied registration, while the polling helper made
  total factory-record count a scheduling-sensitive success Oracle.
- Design and Oracle: `HotkeyRegistrationEvidence` now carries a stable source,
  including a shared `application_launch` value. The launch regression
  establishes three independent observers before
  `applicationDidFinishLaunching`: exact initial-presentation resolution for
  the target panel and active/pending Search, launch registration generation 1
  with both exact configurations, and a log clear followed by the requested
  append count. Completion joins those three signals. Final readbacks
  independently require Search session state, the exact two launch monitor
  signatures, registration generation/configuration/source, preference reset,
  seeded-log count and redaction, removal of the prelaunch log, and stress
  runner startup.
- Hosted Settings lifecycle: stored-value synchronization now performs an
  immediate registration-evidence readback and suppresses a reload when both
  registered configurations already match. Explicit user edits retain the
  existing unconditional persistence and reload path. The main-queue
  observation accepts evidence synchronously, so stopping the owner removes
  delivery and state without an unowned task. Matching-readback and stop
  regressions cover both paths.
- Lifecycle and retained time policy: the test scope owns both notification
  tokens, the runtime-log observation, and its thread-safe one-shot recorder;
  `defer` cancels or removes all of them and terminates the delegate. Initial
  presentation publishes its exact resolution before releasing its
  bootstrap-owned observation owner. The four-second XCTest timeout is a
  terminal failure watchdog for the three named missing signals; it never
  establishes success. The launch-specific 100ms polling cadence, deadline,
  and cancellation-swallowing sleep were removed.
- Unit and Behavior: the final focused canonical wrapper passed 6/6 with zero
  failures in 0.763 seconds (0.766 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032H/targeted-attempt-003`. It covers
  matching initial readback, synchronous stop cleanup, launch orchestration,
  initial-presentation readbacks, and both affected pressure contracts.
  The complete Priority class then passed 585/585 with zero failures in
  15.552 seconds (15.664 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032H/priority-final-attempt-001`,
  closing the original suite order. The complete canonical wrapper passed
  1022/1022 with zero failures in 49.010 seconds (49.170 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032H/full-attempt-001`.
- Pressure: the focused run retained the latest exact registration across
  2,000 generations and allowed only the final resolution across 500 replaced
  initial-presentation generations, including forced delivery of cancelled
  scheduler tokens. Scheduling changed completion latency while the accepted
  generation and final result remained exact. The complete 585-test Priority
  lifecycle run additionally exercised the hosted Settings/AppDelegate order
  that originally failed.
- FlowTabCore and UI: not relevant because this app/TestingSupport slice adds
  no core API and preserves the existing visible Settings controls,
  persistence format, explicit edit path, launch arguments, Search
  presentation, and fixture topology.
- Process/Tooling: the first sandboxed focused attempt did not enter testing
  because CoreSimulator XPC startup failed with xcodebuild exit 133 and no
  result bundle under
  `.build-local/evidence-driven-sync/SYNC-032H/targeted-attempt-001`; the
  canonical wrapper succeeded once granted normal Xcode service access.
  Project-file lint, Swift parse, scoped obsolete-helper/source-literal review,
  source-size checks, and `git diff --check` passed. The extracted launch test
  is 398 lines and its support recorder is 84 lines. The touched oversized
  lifecycle source shrank to 994 lines, the shared async support source shrank
  to 24 lines, and AppDelegate remains a single-responsibility 643-line
  source. Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `6c308e8c5fbc809283e341883725d59cce243378`
  (`refactor(sync): migrate SYNC-032H launch bootstrap`).

### SYNC-032D1 Closure Record

- Design and Oracle: both model-only regressions install
  `onWindowOnlyPreviewPreparationChanged` before the first snapshot request.
  The success path fulfills once only when both exact visible preview items
  contain images. The failure path fulfills once only when the special
  provider has one call and the model publishes
  `specialProviderUnavailable` with the exact next retry generation.
  Independent final readbacks verify visible item count/image state, special
  and generic provider call counts, failure reason, and retry generation.
- Lifecycle and retained time policy: each test clears its model callback in
  `defer`; a one-shot guard rejects duplicate batch delivery. The one-second
  XCTest expectation is a terminal failure watchdog whose description names
  the missing success or structured-failure publication. The former 50ms
  polling cadence, deadline, and cancellation-swallowing sleep were removed
  from both paths.
- Unit and Behavior: the final focused canonical wrapper passed 7/7 with zero
  failures in 0.696 seconds (0.700 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032D1/targeted-attempt-002`. The
  complete canonical wrapper passed 1022/1022 with zero failures in 48.498
  seconds (48.657 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032D1/full-attempt-001`.
- Pressure: the focused run covered a 1,000-window provider batch constrained
  to the visible page, explicit in-flight release, batch failure, structured
  provider failure, and 500 initial-reveal replacement/cancellation cycles.
  Every success remained tied to final image/failure state and the exact
  accepted owner generation.
- FlowTabCore and UI: not relevant because this slice changes app-test
  observation only. It preserves the preview resolver, capture scheduling,
  provider fallback behavior, visible panel behavior, core APIs, and fixture
  topology.
- Process/Tooling: focused attempt 001 stopped at compilation because the
  extracted file omitted its `FlowTabCore` import; no test ran. The import was
  restored before attempt 002. Project-file lint, Swift parse, scoped
  `waitUntil` review, source-size checks, `git diff --check`, and exact staged
  review passed. Extraction reduced the pre-existing 802-line preview-provider
  source to 657 lines; the new publication test source is 284 lines. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `3857a8576ac7cb805654f60a72113cc3fc74334f`
  (`test(sync): migrate SYNC-032D1 preview publication`).

### SYNC-032D2 Closure Record

- Design and Oracle: the reveal owner now retains the exact accepted
  `InitialWindowOnlyPreviewRevealEvidence` before invoking its ready callback
  and clears that readback when the next generation starts. The regression
  installs its preview-batch observer before presentation, preserves the
  controller's existing observer, and holds the capture batch behind an
  explicit gate. Releasing the gate must publish
  `previewBatchCompleted` for the exact observation and presentation
  generations. Success additionally requires zero pending and in-flight
  captures, completed owner/watchdog cleanup, panel alpha 1, the unchanged
  presentation generation, and one image for every exact final window row.
- Lifecycle and retained time policy: the test scope owns the batch gate,
  one-shot expectation, and callback wrapper. `defer` releases any blocked
  capture, restores the controller callback, and ends the presentation
  session. The one-second XCTest expectations are terminal failure watchdogs
  naming the missing batch-start or matching reveal evidence. The production
  250ms degraded-reveal watchdog remains the named SYNC-024B presentation
  policy and reports its final pending-capture readback; successful completion
  in this slice comes only from the matching preview-batch evidence. The
  former 80ms capture delay and generic 5ms polling cadence were removed.
- Unit and Behavior: the focused canonical wrapper passed 11/11 with zero
  failures in 0.214 seconds (0.216 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032D2/targeted-attempt-001`. It
  covers initial readback, batch completion, final watchdog readback,
  diagnostic watchdog failure, replacement, cancellation, synchronous
  watchdog delivery, controller reveal/degraded reveal, presentation-end
  cleanup, and the migrated regression. The first complete run executed
  1022 tests under
  `.build-local/evidence-driven-sync/SYNC-032D2/full-attempt-001`; both
  assertions belonged to
  `testSwitcherInitialVisibilityObserverAcceptsWindowNotificationReadback`,
  whose independent SYNC-019 owner remained in `presenting` after one
  `Task.yield()`. Its exact isolated rerun passed 1/1 in 0.037 seconds under
  `.build-local/evidence-driven-sync/SYNC-032D2/sync019-isolated-attempt-001`.
  The final complete canonical rerun passed 1022/1022 with zero failures in
  48.208 seconds (48.378 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032D2/full-attempt-002`.
- Pressure: the focused run exercised 500 preview-reveal
  replacement/cancellation generations and rejected stale watchdog work. The
  migrated regression also holds an arbitrarily slow capture at an explicit
  gate; release timing changes completion latency while the accepted
  generations, images, cleanup, and visible result remain exact.
- FlowTabCore and UI: not relevant because the retained evidence readback and
  regression belong to the app target and preserve the existing panel reveal,
  preview capture, core API, launch configuration, and fixture topology. The
  real visible path and degraded watchdog remain covered by the completed
  SYNC-024B UI slice.
- Process/Tooling: Swift parse, scoped `waitUntil`/fixed-delay review,
  source-size checks, `git diff --check`, and exact staged review passed. The
  production owner is 333 lines and the touched single-responsibility
  regression source is 610 lines. Startup `prompts.zip` remains unchanged and
  outside the slice.
- Commit: `be645c87c6972aa72c609a0ba9b01a64fabccec2`
  (`test(sync): migrate SYNC-032D2 preview reveal`).

### SYNC-032E1 Closure Record

- Design and Oracle: the Search viewport callback is installed before panel
  presentation and preserves any prior test observer. `enterSearchMode()`
  must immediately publish a non-empty result state, which is verified by
  direct readback. Before the first down-arrow and the final wrap action, the
  test records the exact next `searchResultScrollRevision` and first-result
  ID. Each transition resolves only from the real SwiftUI scroll callback
  while the model still reports that revision and ID. Waiting for the
  first-focus callback before issuing later inputs establishes a clean
  generation baseline; final readbacks require selected index zero and the
  exact first result.
- Lifecycle and retained time policy: the test scope owns two one-shot
  expectations and the callback wrapper. `defer` restores the prior callback
  and ends the presentation session. Each one-second XCTest timeout is a
  terminal failure watchdog naming the missing first-focus or exact wrap
  publication. The two generic 50ms condition-poll cadences and their
  two-second deadlines were removed; no product duration is introduced or
  changed.
- Unit and Behavior: the focused canonical wrapper passed 6/6 with zero
  failures in 0.646 seconds (0.648 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032E1/targeted-attempt-001`. It
  covers hosted SwiftUI viewport delivery, first/last result transitions,
  model-level wrap semantics, slow-scheduler invariance, cancelled and
  out-of-order completion rejection, and latest-owner pressure. The complete
  canonical wrapper passed 1022/1022 with zero failures in 49.952 seconds
  (50.110 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032E1/full-attempt-001`.
- Pressure: the focused run replaced 2,000 Search scheduling generations,
  force-fired 1,999 cancelled entries, and retained only the latest work. A
  separate manual-clock case changed scheduler/executor latency while
  preserving the exact final query, revision, result selection, and cleanup.
- FlowTabCore and UI: not relevant because this slice migrates app-test
  synchronization around existing model and SwiftUI evidence without
  changing Search behavior, core APIs, launch configuration, accessibility,
  or fixture topology. The hosted Behavior test executes the affected
  viewport task and exact visible scroll route.
- Process/Tooling: project-file lint, Swift parse, scoped remaining-`waitUntil`
  review, source-size checks, `git diff --check`, and exact staged review
  passed. Extraction reduced the pre-existing 1,251-line mixed session/Search
  source to 1,194 lines; the new focused viewport publication source is 167
  lines. Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `454c63574e270eba9a2b8b7cccfd40748fc71a27`
  (`test(sync): migrate SYNC-032E1 search scroll publication`).

### SYNC-032E2 Closure Record

- Design and Oracle: the regression installs
  `.flowTabUITestInitialPresentationDidResolve` for the exact panel controller
  before invoking launch bootstrap. It accepts only a positive observation
  generation resolved as `presented` from `initialReadback`, with global-mode
  baseline/candidate snapshots, the complete ordered app-ID set, a successful
  presentation attempt, Search active or pending, and a matching
  post-presentation readback. At notification delivery, independent controller
  readbacks require active Search, exact result count and selected app kind,
  current layout measurements, final panel height, and a released bootstrap
  owner. The same state is read back after expectation completion.
- Lifecycle and retained time policy: the test scope owns the notification
  token, launch option overrides, presentation session, and bootstrap
  observation cleanup; the temporary-preferences helper restores its keys.
  The one-second XCTest expectation is a terminal failure watchdog, and a
  rejected notification is retained for full evidence diagnostics. The
  TestingSupport owner's named three-second watchdog remains its terminal
  failure bound with final projection readback. The generic 50ms condition
  cadence and two-second polling deadline were removed; neither watchdog
  establishes success.
- Unit and Behavior: targeted attempt 001 executed all seven tests; the five
  owner/lifecycle tests and independent Search sizing test passed, while the
  migrated Oracle compared a stable Search UI ID (`app:<bundleID>`) with a raw
  bundle ID and correctly rejected the notification. The Oracle now matches
  `SwitcherSearchResultKind.app(appID:)`. The final focused canonical wrapper
  passed 7/7 with zero failures in 0.305 seconds (0.306 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032E2/targeted-attempt-002`. It
  covers initial satisfied state, observer-before-trigger delivery, fresh
  attempts, watchdog final readback, exact Search sizing, cancellation, and
  replacement. The complete canonical wrapper passed 1022/1022 with zero
  failures in 49.552 seconds (49.717 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032E2/full-attempt-001`.
- Pressure: the focused run replaced 500 initial-presentation generations,
  delivered every stale event against the active owner, force-fired cancelled
  watchdog work, and accepted only the final matching generation. Scheduling
  changes completion time while controller identity, item set, Search state,
  layout, and cleanup remain exact.
- FlowTabCore and UI: not relevant because this slice migrates app-test
  synchronization around existing TestingSupport evidence without changing
  core APIs, launch arguments, Search presentation behavior, accessibility,
  or fixture topology. The Behavior test hosts the real controller, SwiftUI
  content, bootstrap owner, and panel sizing path.
- Process/Tooling: project-file lint, Swift parse, scoped remaining-`waitUntil`
  review, source-size checks, `git diff --check`, and exact staged review
  passed. Extraction reduced the pre-existing mixed session/Search source
  from 1,194 to 1,142 lines; the new focused initial-Search presentation
  source is 192 lines. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Commit: `6f00bc18461643a8ccb023d0c71de66c506c4def`
  (`test(sync): migrate SYNC-032E2 initial search presentation`).

### SYNC-032F Closure Record

- Design and Oracle: both quit-shortcut regressions construct the controller
  with `ManualTerminatePressFeedbackScheduler` before starting the
  presentation. Key input must first leave
  `TerminatePressFeedbackCompletionOwner` pending at generation one, schedule
  the named policy interval, and publish no termination request. Explicitly
  firing that completion must synchronously clear the owner and publish a
  `PendingTerminateRequest` with exact selected app ID, PID 42100, and request
  generation one. Independent readbacks verify the termination animation,
  projection-maintenance sequence, unchanged pre-notification session, and
  exact post-workspace-notification layout and selected app.
- Lifecycle and retained time policy: the controller owns the completion
  owner/token and presentation-end cancellation. The second regression wraps
  and restores the controller's existing layout callback; both tests end the
  presentation in `defer`. The 120ms
  `TerminatePressFeedbackPolicy.completionInterval` remains the named,
  injected visual press-feedback contract. It determines when completion is
  delivered, while request success comes only from the exact scheduler
  completion and request readback. The one-second layout expectation is a
  terminal failure watchdog. Both generic 10ms condition cadences and
  one-second terminate-entry polling deadlines were removed.
- Unit and Behavior: the focused canonical wrapper passed 8/8 with zero
  failures in 0.138 seconds (0.141 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032F/targeted-attempt-001`. It
  covers both quit entry paths, scheduled completion identity, single
  delivery, replacement, cancellation, synchronous scheduler delivery, exact
  controller request publication, and lifecycle pressure. The complete
  canonical wrapper passed 1022/1022 with zero failures in 49.089 seconds
  (49.241 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032F/full-attempt-001`.
- Pressure: the focused owner workload delivered 500 generations, explicitly
  cancelled every even generation, force-fired cancelled work, and accepted
  exactly the 250 current odd generations in monotonic order. Duplicate fire
  was rejected and synchronous scheduler delivery cleaned its returned token,
  so scheduler latency changes completion time without changing request
  identity or result.
- FlowTabCore and UI: not relevant because this slice migrates app-test
  synchronization and shares existing scheduler test support without changing
  core APIs, hotkey configuration, animation duration, termination behavior,
  accessibility, launch options, or fixture topology. The Behavior tests
  exercise the real key-routing, visual-feedback owner, projection
  maintenance, workspace refresh, and panel layout paths.
- Process/Tooling: project-file lint, Swift parse, scoped stale-`waitUntil`
  review, source-size checks, `git diff --check`, and exact staged review
  passed. Extraction reduced the mixed session/Search source from 1,142 to
  1,027 lines and the completion-owner test source from 306 to 227 lines; the
  new focused quit-entry source is 294 lines and shared scheduler support is
  84 lines. Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `cf4890e2c57d4024add168e91698899e1f4adc4d`
  (`test(sync): migrate SYNC-032F terminate feedback entry`).

### SYNC-032G1 Closure Record

- Design and Oracle: the three configured auto-entry regressions now inject
  `ManualDelayedWindowLayerEntryScheduler` before presentation. Each path
  requires an app-layer session, one pending
  `DelayedWindowLayerEntryObservationOwner`, and the exact configured
  override or preference interval before deadline delivery. The complete
  selected-app projection is read back while the mode remains `.appCycle`;
  explicitly firing the owned deadline must then synchronously enter
  `.windowCycle` for the same app ID and clear the pending owner.
- Lifecycle and retained time policy: the presentation session owns the
  deadline token and cancels it on session end. The configurable
  `windowLayerPresentationDelay` remains a user-visible product contract.
  Scheduler latency determines when deadline evidence arrives; selected app
  identity, committed windows, and the resulting layer come from exact
  readbacks. The three one-second polling watchdogs and their 10ms cadences
  were removed.
- Unit and Behavior: after extracting the regressions into the focused owner
  source, the first compile identified a file-private assertion helper; the
  final test now reads the recording service directly. The final focused
  canonical wrapper passed 7/7 with zero failures in 0.159 seconds (0.160
  seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032G1/targeted-attempt-003`. It
  covers override and preference durations, initial complete projection,
  deadline delivery, session cancellation, and owner pressure. The complete
  canonical wrapper passed 1022/1022 with zero failures in 41.565 seconds
  (41.714 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032G1/full-attempt-002`.
- Pressure: the focused owner test replaced the deadline observation 2,000
  times, retained one current token, cancelled it, force-fired all stale
  scheduler work, and accepted no completion. The result therefore depends
  on current generation and final readback across arbitrary scheduler load.
- FlowTabCore and UI: not relevant because this slice migrates app-test
  synchronization around an existing injected product scheduler without
  changing core APIs, preference compatibility, window identity,
  accessibility, visual output, launch behavior, or fixture topology. The
  Behavior tests execute the real controller, projection service, and panel
  session path.
- Process/Tooling: Swift parse, scoped remaining-`waitUntil` review,
  source-size review, `git diff --check`, and exact diff review passed. The
  extraction reduced `PanelSessionBehavior.swift` from 2,394 to 2,240 lines;
  the focused delayed-entry source is 631 lines with one responsibility. Two
  remaining calls are assigned to SYNC-032G2. Startup `prompts.zip` remains
  unchanged and outside the slice.
- Commit: `a88bdde79a5e1be066282f4827d5bf1a04d8f3cc`
  (`test(sync): migrate SYNC-032G1 delayed entry deadline`).

### SYNC-032G2 Closure Record

- Design and Oracle: the manual-entry regression establishes the controller
  and injected `ManualDelayedWindowLayerEntryScheduler` before presentation,
  then records both projection and delayed-owner generation baselines.
  `.downArrow` must synchronously publish one exact selected-app maintenance
  request with the current PID, advance both generations once, and retain the
  app-layer session. A mismatched app event is rejected without another
  projection read. Publishing the complete matching projection and invoking
  the explicit update callback must advance the projection generation again,
  enter `.windowCycle` for the same app ID, expose the two exact window IDs,
  and cancel the pending delayed owner.
- Lifecycle and retained time policy: the presentation session owns the
  delayed-entry token and cancellation. The test's 30-second override proves
  that matching projection evidence completes manual entry independently of
  the later user-configured auto-entry deadline; the injected scheduler never
  advances. Both one-second polling watchdogs and 10ms polling cadences were
  removed.
- Unit and Behavior: the first focused attempt exposed an absolute generation
  assumption after session startup had already established generation one.
  Capturing baselines before input made the Oracle lifecycle-relative. The
  final focused canonical wrapper passed 6/6 with zero failures in 0.168
  seconds (0.169 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032G2/targeted-attempt-002`. It
  covers model replay, controller commit, mismatched and matching events,
  delayed-owner cancellation, and replacement pressure. The complete
  canonical wrapper passed 1022/1022 with zero failures in 41.957 seconds
  (42.110 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-032G2/full-attempt-001`.
- Pressure: the focused owner test replaced the observation 2,000 times,
  retained only the current generation, cancelled it, and rejected every
  force-fired stale deadline. The representative callback also proves that
  the explicit projection event cancels its still-pending 30-second token.
- FlowTabCore and UI: not relevant because this slice migrates app-test
  synchronization and source organization without changing core APIs,
  preferences, panel visuals, accessibility, launch behavior, or fixture
  topology. The Behavior tests execute the real model, projection service,
  controller input route, and panel-session owner.
- Process/Tooling: project-file lint, Swift parse, repository-wide app-test
  `waitUntil` absence, source-size review, `git diff --check`, and exact diff
  review passed. `PanelSessionBehavior.swift` shrank from 2,240 to 2,140
  lines; the new focused source is 210 lines. The generic async helper and its
  Xcode project reference were replaced by the focused regression. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Commit: `171cee6eceed016b72233d84e6c31e7ec94dbe0f`
  (`test(sync): migrate SYNC-032G2 manual entry evidence`).

### SYNC-033C Closure Record

- Design and Oracle: the test enters every background publisher and registers
  DispatchGroup completion on the main queue before dispatch. Each task records
  its exact notification name only after `NotificationCenter.post` returns.
  The named 500ms blocking watchdog remains solely as the proof boundary that
  background publication does not synchronously wait for MainActor delivery.
- Lifecycle and diagnostics: the DispatchGroup completion expectation is
  delivered through XCTest for deterministic cleanup after the blocking proof.
  This allows pending MainActor work to run. The test scope owns the group,
  expectation, completed-name evidence, and
  controller lifetime. Watchdog failure reports the sorted completed and
  expected notification names.
- Unit and Behavior: the final focused canonical wrapper passed 1/1 with zero
  failures in 0.022 seconds under
  `.build-local/evidence-driven-sync/SYNC-033C/targeted-attempt-002`. The
  complete canonical wrapper passed 1022/1022 with zero failures in 42.386
  seconds (42.549 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-033C/full-attempt-001`.
- UI and Pressure: not relevant because the slice changes only the test
  synchronization and diagnostics around the existing notification-delivery
  behavior; no runtime implementation, visible behavior, or repeated hot-path
  scheduling changes.
- Process/Tooling: Swift parse and scoped source-literal review passed. The
  first focused attempt passed 1/1 but exposed Swift 6 warnings for blocking and
  lock operations in an async context. The final synchronous MainActor test and
  lock-protected `@unchecked Sendable` evidence recorder compiled without those
  warnings. Final `git diff --check` and exact staged-content review are
  recorded before commit. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Commit: `4322115a746fb82a0930b7d6d066fb4d8470e27a`
  (`test(sync): migrate SYNC-033C notification publication`).

### SYNC-033D Closure Record

- Design and Oracle: the test establishes one-shot worker-start,
  resolver-invoked, and fetch-completed evidence before dispatching the
  background read. Once the worker has started, MainActor blocks only on the
  resolver-invocation watchdog. Success requires that exact signal, an
  off-main-thread resolver identity, and terminal fetch completion; no elapsed
  duration participates in the success Oracle.
- Lifecycle and diagnostics: the test scope owns both semaphores, the
  completion expectation, the locked evidence recorder, and all AX/permission
  override restoration. Named two-second watchdogs are terminal failure bounds.
  Every failure path reports the last worker-start, resolver-thread, and
  fetch-completion readback.
- Unit and Behavior: the final focused canonical wrapper passed 1/1 with zero
  failures in 0.003 seconds (0.004 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-033D/targeted-attempt-002`. The
  complete canonical wrapper passed 1022/1022 with zero failures in 49.480
  seconds (49.644 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-033D/full-attempt-001`.
- Pressure: 100 consecutive repetitions passed with zero failures in 0.101
  seconds (0.112 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-033D/pressure-attempt-001`. Each
  iteration independently required the exact background resolver and terminal
  completion evidence.
- UI: not relevant because this slice changes only app-test synchronization
  around the existing off-main AX resolver path and does not change visible
  behavior.
- FlowTabCore: not relevant because the slice changes no core-domain source or
  API.
- Process/Tooling: project-file lint, Swift parse, source-literal review, and
  source-size review passed. Focused attempt 001 passed 1/1 but exposed a Swift
  6 warning for capturing `NSRunningApplication` in a Sendable closure; the
  worker now performs that read in its own context and attempt 002 compiled
  without the warning. Extracting the test reduced the pre-existing oversized
  Runtime Space classification source from 1,169 to 1,116 lines; the focused
  source is 139 lines. Final `git diff --check` and exact staged-content review
  are recorded before commit. Startup `prompts.zip` remains unchanged and
  outside the slice.
- Commit: `a70b527363f21a3810b7db0ee410dbd3fc96ce07`
  (`test(sync): migrate SYNC-033D AX background resolution`).

### SYNC-033E Closure Record

- Design and Oracle: the test installs a condition-backed workload gate before
  starting collection. The first four workers must enter and remain blocked,
  proving the configured concurrency from exact in-flight evidence. Explicit
  release then permits all 28 tasks to finish. Success requires maximum
  in-flight count four, every exact index, zero remaining work, and the original
  ordered result; no sleep or elapsed-time threshold participates in the
  Oracle.
- Lifecycle and diagnostics: the test scope owns the gate, DispatchGroup,
  result recorder, release, and idempotent cancellation. A dedicated regression
  cancels a saturated gate and requires all blocked work to exit. Named
  two-second saturation and completion watchdogs are terminal failure bounds;
  failures report entered indices, current/maximum in-flight counts,
  release/cancellation state, and the final result readback.
- Unit and Behavior: the focused canonical wrapper passed 2/2 with zero
  failures in 0.002 seconds (0.003 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-033E/targeted-attempt-001`. The
  complete canonical wrapper passed 1023/1023 with zero failures in 48.699
  seconds (48.877 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-033E/full-attempt-001`.
- Pressure: 100 repetitions of both explicit-release and cancellation paths
  passed 200/200 with zero failures in 0.076 seconds (0.095 seconds total) under
  `.build-local/evidence-driven-sync/SYNC-033E/pressure-attempt-001`.
  Scheduling changed only when workers reached the gate; every iteration
  retained the exact concurrency bound, completion, and ordered-result Oracle.
- UI and FlowTabCore: not relevant because this slice changes only app-test
  workload synchronization around an unchanged runtime coordinator.
- Process/Tooling: Swift parse, scoped obsolete-sleep/elapsed-literal review,
  source-size review, and compiler-warning review passed. The focused source is
  217 lines with one pressure-workload responsibility. Final
  `git diff --check` and exact staged-content review are recorded before commit.
  Startup `prompts.zip` remains unchanged and outside the slice.
- Commit: `c76b13c9c24f515fe7be223cfbdb835d38bc54c5`
  (`test(sync): migrate SYNC-033E AX collection pressure`).

### SYNC-033A Closure Record

- Design and Oracle: both hosted Logs control tests now perform one explicit
  layout pass and immediately require the exact AppKit control type and
  accessibility identifier from the resulting hierarchy. The action-button
  test independently verifies localized titles, metrics, font, and
  appearance-derived style. The dropdown test independently verifies the
  bound log-level update, selected identifier, and absence of a native
  `NSPopUpButton`. The scoped paths retain no duration, observer, timer,
  retry, polling cadence, or timeout.
- Behavior targeted: 2/2 passed in 0.020/0.021 seconds through the canonical
  FlowTabTests runner at
  `.build-local/evidence-driven-sync/SYNC-033A/targeted-attempt-001`.
- Pressure: 100 repeated iterations of each path, 200/200 total, passed in
  1.956/1.987 seconds at
  `.build-local/evidence-driven-sync/SYNC-033A/pressure-attempt-001`.
- Behavior full: 1023/1023 passed in 49.004/49.157 seconds at
  `.build-local/evidence-driven-sync/SYNC-033A/full-attempt-001`.
- Process/Tooling: changed Swift files parse, the Xcode project plist is
  valid, changed-file compiler diagnostics contain no warnings, scoped
  literal search confirms the removed waits do not remain, and source-file
  sizes are 142 lines for `FlowTabTests+CompactActionButton`, 83 lines for
  `FlowTabTests+RuntimeLogsHostedControls`, and 1639 lines for the pre-existing
  oversized `FlowTabTests+PreferencesAndDiagnostics` after extracting the
  migrated test. Final `git diff --check` and exact staged-content review are
  recorded before commit. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Unit, UI, and FlowTabCore: not relevant because this slice changes only
  app-test synchronization around existing hosted controls.
- Commit: `b07c75cb7f2adf6b70df3b543d46a621f5fa62f2`
  (`test(sync): migrate SYNC-033A hosted Logs controls`).

### SYNC-033B1 Closure Record

- Design and Oracle: after applying the app-scoped
  `AppleInterfaceStyle` value, the test explicitly invokes
  `SystemThemeState.refreshColorScheme()` and immediately requires both the
  current `NSApp.effectiveAppearance` resolution and the state-owned
  `colorScheme` to match the captured system baseline. Cleanup restores the
  app appearance and defaults before another explicit refresh. The scoped
  path retains no observer, duration, retry, polling cadence, or watchdog.
- Behavior targeted: 1/1 passed in 0.002/0.003 seconds through the canonical
  FlowTabTests runner at
  `.build-local/evidence-driven-sync/SYNC-033B1/targeted-attempt-001`.
- Pressure: 200/200 repeated direct-readback iterations passed in
  0.187/0.207 seconds at
  `.build-local/evidence-driven-sync/SYNC-033B1/pressure-attempt-001`.
- Behavior full: 1023/1023 passed in 42.003/42.159 seconds at
  `.build-local/evidence-driven-sync/SYNC-033B1/full-attempt-001`.
- Process/Tooling: changed Swift files parse, the Xcode project plist is
  valid, changed-file compiler diagnostics contain no warnings, scoped
  literal search confirms the extracted path contains no time logic, and
  source-file sizes are 65 lines for `FlowTabTests+SystemThemeReadback` and
  1597 lines for the pre-existing oversized
  `FlowTabTests+PreferencesAndDiagnostics` after extraction. Final
  `git diff --check` and exact staged-content review are recorded before
  commit. Startup `prompts.zip` remains unchanged and outside the slice.
- Unit, UI, and FlowTabCore: not relevant because this slice changes only one
  app behavior test around an existing synchronous state readback.
- Commit: `3d09a602ed242809944ba4439e2e726af0c82a4c`
  (`test(sync): migrate SYNC-033B1 system theme readback`).

### SYNC-033B2 Closure Record

- Design and Oracle: the unchanged Settings content is wrapped only in the
  app-test target with a zero-size SwiftUI transaction probe. The recorder
  assigns monotonic context generations. Each hot language, explicit-theme,
  or follow-system test captures an initial generation and exact initial
  context/view readback, installs a cancellable callback, then performs the
  trigger. A callback is accepted only for a newer matching context; final
  success independently requires one exact AppKit Settings container plus
  localized text, target appearance, dark card topology, container rebuild
  identity, or layout frames as appropriate. Cold-dark materialization uses
  the probe's initial context and immediate hierarchy readback. The probe,
  recorder, callback, and cancellation token are test-owned and leave
  production modules unchanged.
- Timeout policy: `SettingsPresentationObservationPolicy.watchdogTimeout`
  is the named one-second XCTest failure bound. Expiry reports the baseline
  generation and last observed context evidence. Observer cancellation runs
  through `defer`; matching completion, duplicate callbacks, and test
  cancellation cannot leave a registered handler. The migrated paths retain
  no sleep, timer, RunLoop advancement, retry, or polling cadence.
- Unit and Behavior targeted: the recorder generation/cancellation test plus
  five hosted presentation paths passed 6/6 in 3.465/3.467 seconds through
  the canonical FlowTabTests runner at
  `.build-local/evidence-driven-sync/SYNC-033B2/targeted-attempt-003`.
  Attempt 001 stopped at compilation because the extracted files lacked
  explicit `FlowTabCore` imports; the imports were added before attempts 002
  and 003 passed.
- Pressure: 20 repeated iterations of all six paths, 120/120 total, passed
  in 66.177/66.200 seconds at
  `.build-local/evidence-driven-sync/SYNC-033B2/pressure-attempt-001`.
- Behavior full: 1024/1024 passed in 43.035/43.192 seconds at
  `.build-local/evidence-driven-sync/SYNC-033B2/full-attempt-001`.
- Process/Tooling: changed Swift files parse, the Xcode project plist is
  valid, the scoped time-literal search is clean, and compiler diagnostics
  contain no warnings for the new or extracted Settings presentation files.
  New files are 182, 294, 205, and 294 lines; the extraction reduces
  `FlowTabTests+EnglishLayout` from 913 to 726 lines and the pre-existing
  oversized `FlowTabTests+PreferencesAndDiagnostics` from 1597 to 1462
  lines. Final `git diff --check` and exact staged-content review are
  recorded before commit. Startup `prompts.zip` remains unchanged and outside
  the slice.
- UI and FlowTabCore: not relevant because this slice changes app-test
  synchronization and test-file organization around existing Settings
  presentation behavior.
- Commit: `c87d1483fad7505e70375e4beb771de17157e4ea`
  (`test(sync): migrate SYNC-033B2 Settings presentation evidence`).

### SYNC-033B3 Closure Record

- Design and Oracle: hosted Settings layout first establishes an exact denied
  permission readback generation and localized request-title baseline. The
  test then installs a generation-filtered granted-readback callback and an
  exact `NSButton.title` KVO observation before clicking. The request stub
  changes the trusted readback while deliberately returning a different
  request result, so success requires the coordinator's independent
  post-request readback, one request, a newer granted generation, and the
  localized manage title.
- Lifecycle and timeout policy: the test scope owns the hosted view,
  permission recorder, callback token, and KVO token. `defer` cancels the
  recorder callback, invalidates KVO, restores every permission override,
  restores presentation language, and restores the app-language default.
  `SettingsPermissionReadbackPolicy.watchdogTimeout` is the named one-second
  XCTest failure bound; diagnostics retain the baseline generation, last
  permission readback, and last observed title. The migrated path contains no
  sleep, RunLoop advancement, timer, retry, or condition polling.
- Unit and Behavior targeted: the recorder generation/cancellation test and
  hosted permission path passed 2/2 in 0.353/0.354 seconds through the
  canonical FlowTabTests runner at
  `.build-local/evidence-driven-sync/SYNC-033B3/targeted-attempt-004`.
  Attempt 002 stopped before build when sandboxed Xcode/CoreSimulator services
  terminated. The attempt-003 compiler scan exposed a Swift 6 captured-state
  warning in KVO delivery; moving title evidence into a MainActor-owned
  recorder removed the warning before attempt 004.
- Pressure: 100 repeated iterations of both paths, 200/200 total, passed in
  17.326/17.350 seconds at
  `.build-local/evidence-driven-sync/SYNC-033B3/pressure-attempt-003`.
- Behavior full: 1025/1025 passed in 42.412/42.578 seconds at
  `.build-local/evidence-driven-sync/SYNC-033B3/full-attempt-003`.
- Process/Tooling: changed Swift files parse, the Xcode project plist is
  valid, compiler diagnostics contain no warnings for the new permission
  readback file, and scoped searches confirm the two extracted Settings files
  contain no raw RunLoop or sleep synchronization. The new file is 275 lines;
  extraction reduces the pre-existing oversized
  `FlowTabTests+PreferencesAndDiagnostics` from 1462 to 1379 lines. Final
  `git diff --check` and exact staged-content review are recorded before
  commit. Startup `prompts.zip` remains unchanged and outside the slice.
- UI and FlowTabCore: not relevant because this slice changes app-test
  synchronization around the existing permission observation and Settings
  presentation path.
- Commit: `413038061ae0e6eaa8808405e4dc75676bfa8b4e`
  (`test(sync): migrate SYNC-033B3 permission readback`).

### SYNC-034B Closure Record

- Design and Oracle: a generation-owned UI condition observer registers
  `NSWorkspace.didActivateApplicationNotification` before its initial exact
  `frontmostApplication.bundleIdentifier` readback. Status-item reopen and
  system-app MRU activation establish the observer before their trigger.
  Resolution cancels the notification token; replacement, cancellation,
  stale generation, duplicate delivery, and watchdog termination retain
  explicit ownership. A watchdog expiry records one final readback for
  diagnostics and remains a terminal failure. The status-item path also
  performs an independent exact foreground readback after its visible and
  runtime-log evidence.
- UI owner and Pressure: UI-target tests cover an initially satisfied
  readback, exact activation-notification delivery, an unmatched event,
  500 iterations of replacement/cancellation/stale/duplicate delivery, and a
  watchdog whose final readback becomes satisfied only after expiry. All 4/4
  passed in 0.990/0.992 seconds at
  `.build-local/evidence-driven-sync/SYNC-034B/owner-targeted-attempt-005`.
- UI affected paths: status-item reopen passed 1/1 in 15.235/15.238 seconds
  at `.build-local/evidence-driven-sync/SYNC-034B/status-item-attempt-001`.
  The real eight-application System MRU topology, FlowTab process relaunch,
  and ten switcher reopen iterations passed 1/1 in 43.948/43.951 seconds at
  `.build-local/evidence-driven-sync/SYNC-034B/system-mru-attempt-002`.
- Automation recovery evidence: after local Automation Mode authentication,
  the identity probe passed 1/1 in 1.570 seconds at
  `.build-local/evidence-driven-sync/SYNC-034B/automation-probe-attempt-001`.
  Earlier attempts retain the LocalAuthentication and Automation Mode timeout
  diagnostics that preceded authentication. The first System MRU attempt
  also records the custom-build-root fixture-path fallback; the passing run
  uses the wrapper's canonical default build root and a fresh evidence output
  root.
- Process/Tooling: the changed Swift files parse, the Xcode project plist is
  valid, `git diff --check` passes, the two new files are 277 and 149 lines,
  the removed raw helper has no remaining references, and UI compilation has
  no diagnostics for the new files. The fixed-path app exists at
  `{user-home}/Applications/Flow Tab UITest.app`; it and
  `/Applications/Flow Tab.app` have the same
  `io.github.potato-dumplings.flowtab` Apple Development designated
  requirement and Team identifier.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only UI-test observation infrastructure and its two existing UI call
  paths.
- Commit: `74afd40ea55345a74f70918606af9a44d1bb6a85`
  (`test(sync): migrate SYNC-034B frontmost activation`).

### SYNC-034C Closure Record

- Design and Oracle: the shared condition owner now distinguishes notification
  and scheduled readbacks. A System MRU order observer is installed before
  each explicit switcher trigger, performs an immediate accessibility-summary
  readback, then uses a main-RunLoop timer at
  `FlowTabUITestConditionObservationPolicy.xcuiReadbackCadence` only because
  the XCUI summary exposes no publication callback. Success requires the
  complete fixture identifiers in their exact expected order. Trigger
  delivery and panel presentation remain independently confirmed by the
  existing runtime-log acknowledgement.
- Lifecycle and timeout policy: the helper owns the timer token and cancels it
  on success, replacement, explicit cancellation, watchdog expiry, or
  deinitialization. The caller-supplied timeout is only a failure bound; one
  final readback records summary presence, raw application value, parsed
  order, generation, source, and waiter result.
- UI owner and Pressure: exact-order parsing, initial readback, notification
  delivery, scheduled readback, watchdog diagnostics, 500 stale/duplicate/
  cancellation iterations, and 100 real Timer lifecycle iterations passed
  7/7 in 3.647/3.649 seconds at
  `.build-local/evidence-driven-sync/SYNC-034C/owner-targeted-attempt-003`.
- UI affected path: the real eight-application System MRU topology, FlowTab
  process relaunch, explicit initial/relaunch triggers, and ten switcher
  reopen iterations passed 1/1 in 43.644/43.647 seconds at
  `.build-local/evidence-driven-sync/SYNC-034C/system-mru-attempt-003`.
  Attempt 001 exposed that two callers still passed identifier-set order
  where the new contract requires the exact expected order. Attempt 002
  retained `diagnosticsSummary=<missing>` after launch activation dismissed
  an otherwise resolved initial presentation. The final path installs its
  observer before an explicit acknowledged trigger and is independent of
  launch-presentation timing.
- Process/Tooling: changed Swift files parse, the Xcode project plist is
  valid, compiler diagnostics contain no warnings for the changed files, and
  `git diff --check` passes. The shared observer, observer tests, and System
  MRU files are 306, 245, and 225 lines. Final exact staged-content review is
  recorded before commit. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only UI-test conditional observation and its existing real-topology path.
- Commit: `9838f69b36a5fa812878ec6446126590f659e490`
  (`test(sync): migrate SYNC-034C app order observation`).

### SYNC-034D Closure Record

- Design and Oracle: the System MRU helper now owns both the FlowTab
  termination trigger and XCTest's exact `.notRunning` application-state
  wait. Already-terminated state is accepted by the initial state readback;
  later termination completes only from the process-state transition. The
  caller timeout is solely a terminal bound and failure reports the last
  `XCUIApplication.state`.
- UI affected path: the real eight-application System MRU topology reached
  `Not Running` before its FlowTab relaunch, then preserved the expected
  rebuilt order across ten switcher reopens. The test passed 1/1 in
  37.372/37.375 seconds at
  `.build-local/evidence-driven-sync/SYNC-034D/system-mru-attempt-001`.
- Process/Tooling: the changed Swift file parses, the Xcode project plist is
  valid, compiler diagnostics contain no warning for the changed file, the
  old deadline/RunLoop process loop has no remaining reference in
  `FlowTabUITests+SystemAppMRU`, and `git diff --check` passes. Final exact
  staged-content review is recorded before commit. Startup `prompts.zip`
  remains unchanged and outside the slice.
- Unit, Behavior, FlowTabCore, and Pressure: not relevant because this slice
  delegates one UI-test process-state wait to XCTest and creates no reusable
  state rule, observer, timer, or repeated asynchronous worker.
- Commit: `f53afd3aa00fa895dbcef98ede4d626a8cbc9c16`
  (`test(sync): migrate SYNC-034D process termination`).

### SYNC-034E Closure Record

- Design and Oracle: the shared condition owner now revalidates its generation
  and unresolved state after both client-controlled readback and condition
  evaluation. If either operation pumps the RunLoop and a nested callback
  resolves or replaces the generation, the superseded outer work is
  discarded before evidence publication or expectation fulfillment. The
  status-item caller checks the FlowTab application and SystemUIServer
  immediately, then accepts only existence of the exact status or quit
  accessibility element.
- Lifecycle and timeout policy: the status-element helper owns the shared
  scheduled-readback owner and always cancels it on return. Because XCUI
  exposes no element-publication callback, it uses the named
  `xcuiReadbackCadence`. The quit-element observer is established before the
  control-click trigger; an already-present initial readback skips the
  trigger. `elementWatchdog` is solely a failure bound and reports the latest
  per-source existence evidence.
- Deterministic owner and Pressure: the explicit reentrant-readback
  regression, initial/event/scheduled/watchdog paths, exact-order rule, 500
  stale/duplicate/cancellation iterations, and 100 real Timer lifecycle
  iterations passed 8/8 in 2.178/2.180 seconds at
  `.build-local/evidence-driven-sync/SYNC-034E/owner-regression-attempt-001`.
- UI affected paths: status-item restoration from Finder and secondary-click
  quit-menu publication passed 2/2 in 32.748/32.750 seconds, with 33.354
  seconds total test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034E/affected-ui-attempt-002`.
  Attempt 001 retained the original
  `multiple calls made to XCTestExpectation fulfill` API violation from a
  reentrant status-item readback; the quit path independently passed in that
  run.
- Process/Tooling: the canonical UI app installation succeeded, changed Swift
  files parse, the Xcode project plist is valid, compiler diagnostics contain
  no warning for the changed files, the status-item raw deadline/RunLoop loops
  have no remaining reference, and `git diff --check` passes. The condition
  owner, owner tests, and status-item helper are 318, 281, and 140 lines.
  The touched oversized Home/Logs file decreases by one line. Final exact
  staged-content review is recorded before commit. Startup `prompts.zip`
  remains unchanged and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  UI-test observation infrastructure and its existing UI call paths.
- Commit: `442de518dff8a35b4fa9318b39d365ee53a34cbf`
  (`test(sync): migrate SYNC-034E status observation`).

### SYNC-034F Closure Record

- Design and Oracle: the test creates each marker owner before its settings or
  quit trigger, installs the scheduled readback, and requires the inverse
  initial marker baseline. Success comes only from the exact expected Boolean
  becoming visible in the shared defaults suite. The active-registration log
  and XCTest `.notRunning` state remain independent evidence that production
  reached the ordered activation and restoration boundaries.
- Lifecycle and timeout policy: cross-process defaults expose no reliable
  publication callback, so each helper invocation uses the named 100ms marker
  readback cadence. It owns and cancels the Timer on initial resolution,
  scheduled resolution, watchdog failure, or return. The named five-second
  watchdog is solely a terminal failure bound and reports expected, baseline,
  last value, source, and generation. I/O delay can extend observation time
  without changing the Boolean success Oracle. The existing test scope owns
  its termination fallback and cleanup launch.
- UI affected path: real Command+Tab configuration, system-shortcut takeover,
  switcher trigger, process termination, marker restoration, and cleanup
  passed 1/1 in 40.435/40.438 seconds, with 41.835 seconds total test
  operation time, at
  `.build-local/evidence-driven-sync/SYNC-034F/settings-command-tab-attempt-002`.
  Attempt 001 demonstrated the nominal single-readback path; subsequent
  semantic review identified that ordered runtime logs do not guarantee
  cross-process defaults visibility under I/O delay, leading to the
  preinstalled conditional owner in the passing closure run.
- Pressure: the unchanged shared owner retains the SYNC-034E coverage of 500
  stale/duplicate/cancellation iterations and 100 real Timer lifecycle
  iterations. This affected path additionally exercised two real marker
  owners across activation and restoration.
- Process/Tooling: both changed Swift files parse, the new source is present
  exactly once in the UI target, the Xcode project plist is valid, compiler
  diagnostics contain no warning for the changed files, the marker helper's
  raw deadline/RunLoop loop has no remaining reference, and
  `git diff --check` passes. The new owner/test file is 205 lines; extraction
  reduces Settings from 876 to 775 lines. Final exact staged-content review is
  recorded before commit. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Unit, Behavior, and FlowTabCore: not relevant because production marker
  ordering and restoration logic are unchanged; this slice migrates their UI
  observation contract.
- Commit: `483ff018f5f877b62ab82e5ec05adc23aabe0b57`
  (`test(sync): migrate SYNC-034F takeover marker`).

### SYNC-034G Closure Record

- Design and Oracle: `tapFirstHittable` and `hasHittableElement` now create a
  generation-owned query observer. It installs its scheduled readback before
  the immediate check and resolves only with the first indexed XCUI candidate
  whose `exists` and `isHittable` readbacks are both true. Tapping occurs only
  after that exact evidence resolves; Boolean probing uses the same evidence
  without an action.
- Lifecycle and timeout policy: XCUI exposes no candidate-publication callback,
  so the owner reuses the named 100ms XCUI readback cadence. Each helper
  invocation owns and cancels its Timer on initial resolution, scheduled
  resolution, watchdog failure, or return. The caller-supplied timeout remains
  only a terminal failure bound. A failure reports candidate count, observed
  existing indices, first hittable index, source, generation, and waiter result.
  Scheduling delay can extend observation without changing the exact
  candidate Oracle.
- Deterministic regression: initial exact-candidate resolution, a preinstalled
  scheduled readback, automatic cancellation, and watchdog final evidence
  passed 2/2 in 0.988/0.989 seconds, with 0.991 seconds total test operation
  time, at
  `.build-local/evidence-driven-sync/SYNC-034G/owner-regression-attempt-003`.
  Attempt 001 recorded the sandbox-denied SwiftPM temporary-file evidence and
  was rerun outside the sandbox through the canonical wrapper. Attempt 002
  exposed and led to the explicit escaping-closure capture fix before the
  passing run.
- UI and Pressure: a fresh real Home/Logs/Settings sidebar path passed 1/1 in
  9.935/9.936 seconds, with 9.938 seconds total test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034G/affected-ui-attempt-001`.
  Five consecutive repetitions then passed 5/5 in 45.338/45.340 seconds, with
  45.342 seconds total test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034G/sidebar-pressure-attempt-002`.
  This covers 15 real query-owner lifecycles and complements the unchanged
  shared owner's 100 Timer and 500 generation pressure iterations.
- Pressure diagnostic evidence: the first ten-iteration attempt completed
  iterations 1–8 before the XCUI application-assistance connection was lost
  during iteration 9; iteration 10 inherited a UI-testing authorization
  failure. No FlowTab or runner crash report was generated. The exited runner
  left xcodebuild waiting on result finalization, so the resolved single
  xcodebuild process was terminated after more than one minute and the
  partial result bundle and wrapper status were retained at
  `.build-local/evidence-driven-sync/SYNC-034G/sidebar-pressure-attempt-001`.
  The fresh 1/1 and final 5/5 runs establish that the failure was scoped to the
  exhausted XCUI session.
- Process/Tooling: the changed Swift files parse and compile, the new source is
  present exactly once in the UI target, the Xcode project plist is valid,
  passing logs contain no changed-file compiler warning, the two migrated raw
  deadline/RunLoop loops have no remaining definition, and `git diff --check`
  passes. The extracted owner file is 147 lines, Support decreases from 1,203
  to 1,174 lines, and the regression file remains within the 400-line
  guardrail at 395 lines. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  UI-test interaction infrastructure and its existing UI paths.
- Commit: `65bbc1e7ad96c9a5f45e4bcccf2c4b2eb57b99cc`
  (`test(sync): migrate SYNC-034G hittable queries`).

### SYNC-034H Closure Record

- Design and Oracle: `assertValue` and `assertValuePrefix` now create a
  generation-owned value observer. It installs its scheduled readback before
  the immediate check and resolves only when the exact XCUI element exists and
  its string value satisfies the exact or prefix predicate. An already
  satisfied value resolves from the initial readback. A later persistent value
  remains observable even when its publication preceded helper entry.
- Lifecycle and timeout policy: XCUI exposes no value-publication callback, so
  the owner reuses the named 100ms XCUI readback cadence. Each helper invocation
  owns the Timer and cancels it on initial resolution, scheduled resolution,
  watchdog failure, or return. The caller-supplied timeout remains solely a
  terminal failure bound. Its final readback reports identifier, existence,
  expected predicate, actual value, source, generation, and waiter result.
  Scheduling and accessibility-publication delay can extend observation without
  changing the value predicate Oracle.
- Deterministic regression: initial exact-value evidence, preinstalled
  scheduled prefix readback, automatic cancellation, and watchdog final
  evidence passed 2/2 in 0.629/0.629 seconds, with 0.630 seconds total test
  operation time, at
  `.build-local/evidence-driven-sync/SYNC-034H/owner-regression-attempt-001`.
- UI affected paths: the real Settings hotkey popup exercised an exact-value
  transition and the window-behavior path exercised prefix publication before
  and after a process relaunch. Both passed 2/2 in 25.189/25.190 seconds, with
  individual durations of 10.106 and 15.083 seconds and 26.852 seconds total
  test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034H/affected-ui-attempt-001`.
- Pressure: 50 iterations of each deterministic path exercised 100 owner
  lifecycles, including immediate resolution, scheduled resolution,
  cancellation, and watchdog final evidence. All 100/100 passed in
  19.857/19.872 seconds, with 20.680 seconds total test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034H/owner-pressure-attempt-001`.
  This complements the unchanged shared owner's 100 Timer and 500 generation
  pressure coverage.
- Process/Tooling: the changed Swift files parse and compile, the two new
  sources are present exactly once in the UI target, the Xcode project plist is
  valid, and all three canonical-wrapper status files report completed with
  zero final/build/signing/test exit codes and present result bundles. Compiler
  logs contain no warnings for changed files; the initial build reports three
  existing warnings in unrelated Space-fixture workflow files. Scoped search
  confirms the two raw value deadline/RunLoop loops have no remaining
  definition, and `git diff --check` passes. The new owner and regression files
  are 128 and 114 lines; extraction reduces Support from 1,174 to 1,152 lines.
  Startup `prompts.zip` remains unchanged and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes only
  UI-test assertion infrastructure and its existing Settings UI paths.
- Commit: `1c1656ba686b56f831c3265ac6fc1b0d0478d703`
  (`test(sync): migrate SYNC-034H element values`).

### SYNC-034I Closure Record

- Discovery evidence: a Home projection diagnostic prototype exercised a
  multi-row XCUI readback that exceeded the shared 100ms cadence. The exact
  window activation path passed in 28.402 seconds, then the multi-app title
  path accumulated nested accessibility reads and failed while resolving an
  unrelated AppKit `ThemeWidgetControlViewService.xpc` bundle identifier.
  The 2-test run retained 1 pass and 1 unexpected failure in
  67.997/68.000 seconds at
  `.build-local/evidence-driven-sync/SYNC-034I/affected-ui-attempt-001`.
  This established same-generation Timer reentrancy as a shared scheduler
  defect before the Home contract proceeds in its own slice.
- Design and Oracle: the scheduler now maintains one pending one-shot Timer and
  rearms it only after the scheduled readback callback returns. The condition
  owner suppresses a scheduled callback while the same generation is already
  reading. Notification callbacks remain eligible during an active readback,
  preserving the synchronous-publication race closure proven by the existing
  reentrant-notification regression. Initial, notification, scheduled, and
  watchdog readbacks retain their existing condition predicates; elapsed time
  never resolves a condition.
- Lifecycle and retained cadence: the serial schedule owns exactly one current
  cancellation token. Success, replacement, explicit cancellation, watchdog
  termination, and deinitialization invalidate that token and prevent rearm.
  The named 100ms XCUI cadence remains a conditional-observation policy that
  selects the next readback opportunity after prior work completes. Scheduler
  pressure can therefore extend completion time without introducing concurrent
  XCUI reads or changing the result.
- Deterministic scheduler and Timer Pressure: scheduled reentrancy suppression,
  single pending one-shot behavior, cancellation after rearm, notification
  reentrancy compatibility, named scheduled resolution, and 100 real Timer
  lifecycles passed 5/5 in 2.264/2.265 seconds, with 2.944 seconds total test
  operation time, at
  `.build-local/evidence-driven-sync/SYNC-034I/scheduler-regression-attempt-002`.
- Generation Pressure: 500 replacement/cancellation/stale/duplicate callback
  iterations passed 1/1 in 0.443/0.443 seconds, with 1.214 seconds total test
  operation time, at
  `.build-local/evidence-driven-sync/SYNC-034I/generation-pressure-attempt-001`.
- UI affected paths: real Settings prefix-value publication, Home/Logs/Settings
  sidebar hittable queries, and status-item quit-menu publication and process
  exit passed 3/3 in 56.083/56.085 seconds. Individual durations were 20.157,
  9.338, and 26.588 seconds; total test operation time was 56.783 seconds at
  `.build-local/evidence-driven-sync/SYNC-034I/affected-ui-attempt-002`.
- Process/Tooling: all changed Swift files parse and compile, both new sources
  are present exactly once in the UI target, the Xcode project plist is valid,
  passing wrapper status files report completed with zero final/build/signing/
  test exit codes and present result bundles, and `git diff --check` passes.
  Compiler logs contain no changed-file warning; three existing warnings remain
  in unrelated Space-fixture workflow files. The condition owner, extracted
  scheduler, and scheduler regressions are 316, 99, and 106 lines. Scoped
  review confirms the scheduler uses a nonrepeating Timer and rearms only after
  callback return. Startup `prompts.zip` remains unchanged and outside the
  slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes only
  shared UI-test observation scheduling and its existing UI callers.
- Commit: `c6be9c9c9aee8708481976cd6a450b8ef1abbee9`
  (`test(sync): migrate SYNC-034I serial readbacks`).

### SYNC-034J Closure Record

- Design and Oracle: one generation-owned owner now reads the persistent Home
  projection for a row containing a title, a visible title, or the absence of
  every prohibited title. Success comes only from an exact static-text
  existence readback or the case-insensitive label/value projection of rows
  whose identifiers begin with `flowtab.home.window.`. An exact static title
  short-circuits row enumeration; row evidence remains available for custom
  accessibility layouts and exact CG-window identifiers.
- Lifecycle and retained cadence: the helper starts the owner before its
  immediate readback and owns cancellation through success, watchdog expiry,
  and scope exit. Home projection is persistent and XCUI exposes no reliable
  publication callback, so the shared serial 100ms cadence remains the named
  conditional-observation policy. The watchdog is solely a failure bound and
  reports its unmet expectation, generation, source, exact static titles,
  row identifiers/labels/values, and waiter result.
- Deterministic regression and Pressure: initial matching-row evidence,
  delayed static-title evidence, initial and delayed prohibited-title absence,
  cancellation, stale callbacks, and 100 owner lifecycles passed 2/2 in
  0.473/0.474 seconds, with 1.937 seconds total test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034J/owner-regression-attempt-002`.
  Attempt 001 was stopped before compilation by the restricted sandbox's
  SwiftPM temporary-file denial; the canonical wrapper then passed outside
  that boundary.
- UI affected paths: after installing the current stable signed app through
  the canonical script, the real multi-app fixture paths for activating the
  exact selected Home window and showing only the selected application's
  resolved titles passed 2/2 in 63.485/63.490 seconds. Individual durations
  were 30.127 and 33.358 seconds; total test operation time was 64.170 seconds
  at
  `.build-local/evidence-driven-sync/SYNC-034J/affected-ui-attempt-001`.
  This reproduces the slow multi-row workload that exposed SYNC-034I without
  the nested XCUI/AppKit failure.
- Process/Tooling: both passing wrapper status files report `completed`, zero
  final/build/signing/test exit codes, and present result bundles. The changed
  Swift files parse and compile, both new sources occur exactly once in the UI
  target, the project plist is valid, and `git diff --check` passes. Compiler
  logs contain no changed-file warning; three existing warnings remain in
  unrelated Space-fixture workflow files. The owner and regression files are
  307 and 178 lines, while extraction reduces the already oversized shared
  Support file by 101 lines. Startup `prompts.zip` remains unchanged and
  outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes only
  shared UI-test Home projection infrastructure and its existing UI paths.
- Commit: `ed81aabb1c3e38159797d11f6922cce1cbe0ce6e`
  (`test(sync): migrate SYNC-034J Home projection`).

### SYNC-034K Closure Record

- Design and Oracle: one generation-owned owner observes the exact Switcher
  window-card total and title multiset, preserving duplicate-title
  multiplicity. Each readback binds the card query to one indexed element
  projection and derives both total and complete title counts from that
  projection. Success requires exact equality with the expected card count and
  title counts; elapsed time cannot satisfy or reject a candidate projection.
- Lifecycle and retained cadence: the helper installs the serial scheduled
  observer before its immediate readback and owns cancellation through success,
  watchdog expiry, and scope exit. XCUI exposes no card-projection callback, so
  the named 100ms cadence remains a conditional-observation policy. The caller
  watchdog is solely a failure bound and reports expected and observed counts,
  generation, source, and waiter result.
- Deterministic regression and Pressure: duplicate-title rejection and later
  exact resolution, initial and delayed success, cancellation, stale callbacks,
  and 100 owner lifecycles passed 2/2 in 0.596/0.597 seconds, with 1.374 seconds
  total test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034K/owner-regression-attempt-002`.
- UI affected paths: after installing the current stable signed app through
  the canonical script, the physical Control+Tab window-preview path and the
  real fixture path that closes one window while the Switcher remains open
  passed 2/2 in 34.761/34.765 seconds. Individual durations were 7.484 and
  27.277 seconds; total test operation time was 35.436 seconds at
  `.build-local/evidence-driven-sync/SYNC-034K/affected-ui-attempt-002`.
  The latter retained two-card evidence until the independent fixture close
  and runtime reconciliation published the exact one-card title projection.
- Process/Tooling: both final wrapper status files report `completed`, zero
  final/fixture/build/signing/test exit codes, and present result bundles.
  Both new Swift files parse and compile, both sources occur exactly once in
  the UI target, the project plist is valid, and `git diff --check` passes.
  Final compiler logs contain no warnings. The owner and regression files are
  153 and 139 lines, and extraction reduces the already oversized shared
  Support file by another 42 lines. Startup `prompts.zip` remains unchanged
  and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes only
  shared UI-test Switcher title-projection infrastructure and its existing UI
  paths.
- Commit: `f5d9dbb8369635a7742187bd347213d8b0991d51`
  (`test(sync): migrate SYNC-034K Switcher titles`).

### SYNC-034L Closure Record

- Design and Oracle: one generation-owned owner binds the Switcher card query
  once per readback, deduplicates exact accessibility identifiers, and preserves
  each card's title, value, frame, and preview-image state. Success requires the
  exact title multiset and card count, one unique identifier per card, absence
  of every excluded title, and a card identifier set disjoint from the
  preceding application's anchors. Elapsed time cannot promote a candidate
  projection.
- Lifecycle and retained cadence: the helper installs the serial scheduled
  observer and records its initial baseline before sending Down Arrow.
  Resolution stays gated while XCUI dispatches that trigger and is enabled only
  after the trigger returns, so even a matching baseline cannot prove the
  operation succeeded. The helper owns cancellation through success, watchdog
  expiry, and scope exit. XCUI exposes no card-projection callback, so the
  shared named 100ms cadence remains a conditional-observation policy. The
  caller watchdog is solely a failure bound and reports the acceptance gate,
  expected contract, exact last card projection, generation, source, and
  waiter result.
- Deterministic regression and Pressure: matching-baseline rejection before
  trigger completion, stale identifier rejection, excluded title rejection,
  reused-identifier rejection, duplicate-title multiplicity, initial and
  scheduled resolution, cancellation, stale callbacks, watchdog final readback,
  and 100 owner lifecycles passed 2/2 in 0.475/0.476 seconds. Total test
  operation time was 1.667 seconds at
  `.build-local/evidence-driven-sync/SYNC-034L/owner-regression-attempt-003`.
- UI affected path: after installing the current stable Apple
  Development-signed app through the canonical script, the real three-fixture
  multi-app card-isolation workflow passed 1/1 in 65.572/65.575 seconds, with
  66.212 seconds total test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034L/affected-ui-attempt-002`.
  For every fixture, the owner recorded its baseline before Down Arrow and then
  accepted only the explicitly selected app's exact two-card projection with
  unique identifiers disjoint from the preceding fixture's anchors.
- Process/Tooling: both wrapper status files report `completed`, zero final,
  fixture, signing, build, and test exit codes where applicable, and present
  result bundles. All changed Swift files parse and compile, both new sources
  occur exactly once in the UI target, the project plist is valid, and
  `git diff --check` passes. The changed files emit no compiler warnings; the
  build retained two warnings in unchanged future migration paths. The owner
  and regression files are 227 and 286 lines, and extraction reduces the
  already oversized shared Support file by 44 lines to 965. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes only
  shared UI-test Switcher card-identity infrastructure and its existing UI
  path.
- Commit: `b5e3302588a9d56ad12b49edae0c90029ae1cd10`
  (`test(sync): migrate SYNC-034L Switcher cards`).

### SYNC-034M Closure Record

- Design and Oracle: one generation-owned owner reads the Logs tab content,
  lines container, and complete seeded-row accessibility projection. Success
  requires both containers, the exact visible identifier multiset and row
  total, and absence of every prohibited identifier. Elapsed time cannot make
  a partial, duplicated, or prohibited projection succeed. The obsolete,
  uncalled marker loop has been removed.
- Lifecycle and retained cadence: the helper starts the observer and performs
  its immediate baseline readback before tapping Logs. Resolution remains
  gated until that trigger returns, so an already matching baseline cannot
  prove the operation completed. The helper owns cancellation through success,
  watchdog expiry, and scope exit. XCUI exposes no accessibility-projection
  callback, so the shared serial named 100ms cadence remains a conditional
  observation policy. The caller watchdog is solely a failure bound and reports
  the acceptance gate, expected contract, exact last identifier counts,
  generation, source, and waiter result.
- Deterministic regression and Pressure: matching-baseline rejection before
  trigger completion, partial/prohibited/duplicate projection rejection,
  initial and scheduled resolution, cancellation, stale callbacks, watchdog
  final readback, and 100 owner lifecycles passed 2/2 in 0.686/0.690 seconds.
  Total test operation time was 6.730 seconds at
  `.build-local/evidence-driven-sync/SYNC-034M/owner-regression-attempt-001`.
- UI affected path: after installing the current stable Apple
  Development-signed app through the canonical script, the DEBUG, INFO, WARN,
  and ERROR launch scenarios passed 1/1 in 24.372/24.374 seconds, with 25.848
  seconds total test operation time, at
  `.build-local/evidence-driven-sync/SYNC-034M/affected-ui-attempt-001`. Each
  scenario accepted only its exact seeded-row identifier multiset after the
  Logs-tab trigger.
- Process/Tooling: both wrapper status files report `completed`, zero final,
  signing, build, and test exit codes, and present result bundles. Both new
  Swift sources parse and compile, occur exactly once in the UI target, the
  project plist is valid, and `git diff --check` passes. The changed files emit
  no compiler warnings; the build retains three warnings in unchanged future
  migration paths. The owner and regression files are 235 and 205 lines, and
  extraction reduces the already oversized shared Support file by 83 lines to
  882. Startup `prompts.zip` remains unchanged and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes only
  shared UI-test Logs projection infrastructure and its existing UI path.
- Commit: `e2a81f52783595306a552b890401bb4633b45cc2`
  (`test(sync): migrate SYNC-034M Logs projection`).

### SYNC-034N Closure Record

- Design and Oracle: `FlowTabUITestRuntimeLogObservationBaseline` resolves the
  Application Support log path at the UI-runner resource boundary and captures
  byte count, file number or creation date, and vnode event generation before
  the trigger. Every wait registers its file-event callback before an immediate
  post-baseline readback. Rotation, replacement, and truncation restart the
  affected file at byte zero. Success requires the post-baseline bytes to
  satisfy the complete marker set or compiled regular expression; elapsed time
  cannot establish publication. The uncalled required-plus-alternative helper
  has been removed, and callers that intentionally inspect the whole persisted
  store now use an explicit all-content readback.
- Lifecycle and retained cadence: the baseline owns directory and file vnode
  sources and closes their descriptors on cancellation or deinitialization.
  Each wait owns one event registration and one shared serial scheduled
  readback registration through success, watchdog expiry, or scope exit.
  Cross-process writes, log creation, and rotation expose no complete reliable
  callback contract, so the named 200ms cadence remains a fallback for
  coalesced or unavailable vnode delivery. The caller watchdog is solely a
  failure bound and reports the missing contract, baseline/current event
  generations, character count, and a bounded content tail.
- Deterministic regression and Pressure: a real temporary log-file append
  resolved from vnode notification evidence; truncation and atomic replacement
  reset the byte offset; marker and regex contracts resolved only from matching
  content; and initial/scheduled resolution, cancellation, stale callbacks,
  watchdog final diagnostics, and 100 owner lifecycles passed 4/4 in
  1.671/1.673 seconds. Total test operation time was 12.669 seconds at
  `.build-local/evidence-driven-sync/SYNC-034N/owner-regression-attempt-004`.
- UI affected paths: the real stale-occlusion mock-runtime path exercised
  cross-process all-marker publication and passed 1/1 in 4.334/4.337 seconds,
  with 5.031 seconds total operation time, at
  `.build-local/evidence-driven-sync/SYNC-034N/affected-ui-attempt-001`.
  The focused mock-runtime trigger path exercised exact-notification-name regex
  publication and passed 1/1 in 2.714/2.716 seconds, with 4.058 seconds total
  operation time, at
  `.build-local/evidence-driven-sync/SYNC-034N/affected-regex-ui-attempt-003`.
- Superseded diagnostics: the broader Settings caller attempt stopped at its
  existing non-hittable `z` dropdown option before reaching either regex wait;
  its result bundle remains at
  `.build-local/evidence-driven-sync/SYNC-034N/affected-regex-ui-attempt-001`
  for the remaining scrolling/hittability owner. The first focused regex
  attempt successfully observed the target log and then failed an additional
  switcher-card projection assertion outside this contract; the final focused
  path validates only the runtime-log publication contract.
- Process/Tooling: the three final wrapper status files report `completed`,
  zero final, signing, build, and test exit codes, and present result bundles.
  Nine changed Swift files parse and compile, each of the three new sources
  occurs exactly once in the UI target, the project plist is valid, and
  `git diff --check` passes. No legacy dictionary snapshot type or empty
  snapshot all-content read remains. The earlier full build retains two
  warnings in unchanged future migration paths; the touched
  `SpaceFixtureInAppWindowSwitcher` warning is closed. The extracted source,
  owner, and regression files are 382, 278, and 393 lines, and extraction
  reduces the already oversized shared Support file by 125 lines to 757. Its
  remaining 200ms `commitEditing` settle belongs to the later direct-UI owner.
  Startup `prompts.zip` remains unchanged and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes only
  shared UI-test cross-process runtime-log observation infrastructure and its
  existing UI callers.
- Commit: `336c50afdee2345ff79c94e552b23332e392881e`
  (`test(sync): migrate SYNC-034N runtime log observation`).

### SYNC-034O Closure Record

- Design and Oracle: semantic call-site review found
  `waitForFocusedWorkflowWindow` only at its declaration. Removing the helper
  closes its ownerless deadline and raw 100ms RunLoop cadence. The executable
  synchronization surface now omits this unused contract.
- Lifecycle and retained time policy: the removed helper owned no external
  observer or resource. This path now allocates no timer, retry, watchdog, or
  polling cadence.
- Validation: Process/Tooling passed. Semantic `rg` reports zero remaining
  `waitForFocusedWorkflowWindow` references; `swiftc -parse` passes for the
  722-line shared support file; `plutil -lint` passes for the Xcode project;
  and `git diff --check` passes. The canonical UI wrapper's
  `process-attempt-001` completed signing and full-target build-for-testing
  with zero exit codes and `** TEST BUILD SUCCEEDED **`. Its selected
  one-test execution was blocked before any test body by XCTest automation
  mode initialization (`Timed out while enabling automation mode`, exit 65);
  the result bundle is present. The build reports the two unchanged warnings
  for unused `searchInput` and mutable `runtimeLogSnapshot`.
- Unit, Behavior, UI, FlowTabCore, and Pressure: not relevant because this
  slice removes unreachable UI-test support without changing an executable
  test or application runtime path.
- Commit: `57681626afe97e17005bb1ad598af8a6c746a742`
  (`test(sync): remove SYNC-034O obsolete focus wait`).

### SYNC-034P Closure Record

- Design and Oracle: semantic call-site review found
  `assertStaticTextsAbsent` only at its declaration. Removing the helper closes
  its ownerless deadline and raw 100ms RunLoop cadence. Executable element
  absence contracts continue to use `waitForNonExistence`, whose success
  Oracle is the exact XCTest `exists == false` predicate.
- Lifecycle and retained time policy: the removed helper owned no external
  observer or resource. This path now allocates no timer, retry, watchdog, or
  polling cadence.
- Validation: Process/Tooling passed. Semantic `rg` reports zero remaining
  `assertStaticTextsAbsent` references; `swiftc -parse` passes for the
  705-line shared support file; `plutil -lint` passes for the Xcode project;
  and `git diff --check` passes. The canonical UI wrapper's
  `process-attempt-001` completed with all fixture-skipped signing,
  build-for-testing, logging, and test-without-building exit codes zero; the
  result bundle is present. Full-target compilation passed and its selected
  deterministic test passed 1/1 in 0.674 seconds (0.676 seconds suite time).
  The build reports the two unchanged warnings for unused `searchInput` and
  mutable `runtimeLogSnapshot`.
- Unit, Behavior, UI, FlowTabCore, and Pressure: not relevant because this
  slice removes unreachable UI-test support without changing an executable
  test or application runtime path.
- Commit: `44d7063f062bca398ed3ddde59d0d25be905d42f`
  (`test(sync): remove SYNC-034P obsolete absence wait`).

### SYNC-034Q Closure Record

- Design and Oracle: all five Home and Switcher-search activation paths start
  `FlowTabUITestWorkflowWindowActivationObservationOwner` before their click
  or confirmation trigger. Registration precedes the initial readback, and
  an acceptance gate remains closed through the trigger. Workspace activation
  and target-process AX focused/main-window notifications cause immediate
  readback. Success requires the exact target bundle identifier and the
  expected topmost on-screen `CGWindowID`; CG, AX, and XCUI titles remain
  diagnostic evidence.
- Lifecycle and retained cadence: the helper invocation owns its generation,
  workspace observer token, AX observer, run-loop source, notification
  registrations, serial scheduled readback, expectation, and watchdog. Every
  completion, expiry, cancellation, and scope exit removes those resources.
  `FlowTabUITestConditionObservationPolicy.xcuiReadbackCadence` remains the
  named 100ms fallback because CGWindowList exposes no exact-window
  publication callback and AX events can be unavailable or coalesced. The
  caller timeout is solely a terminal failure bound; expiry reports the
  acceptance gate and last exact bundle, window number, frame, and title
  readback.
- UI-test infrastructure regression and Pressure:
  `owner-regression-attempt-002` passed 5/5 tests in 1.114 seconds
  (1.116 seconds suite time). Coverage includes observer-before-readback
  ordering, a matching initial state held behind the trigger gate, wrong
  bundle and wrong window rejection, exact event resolution after five
  delayed scheduled readbacks, 100 cancel/restart/duplicate-event iterations,
  and watchdog final-readback diagnostics. All canonical wrapper exit codes
  are zero and the result bundle is present.
- Affected UI: the freshly installed signed UI-test app and rebuilt real
  three-application fixture topology passed
  `testHomePageClickingRealWorkflowWindowActivatesExactFixtureWindow` 1/1 in
  29.383 seconds (29.386 seconds suite time), with 30.109 seconds total test
  operation time, at `affected-ui-attempt-001`. Fixture generation, logging,
  signing, build-for-testing, and test-without-building exit codes are zero;
  the result bundle is present.
- Process/Tooling: all eight changed Swift files parse; the Xcode project plist
  is valid; the removed helper has zero references; all five executable
  callers use `triggerAndWaitForFrontmostWorkflowWindow`; the implementation
  and test files are 362 and 293 lines; and `git diff --check` passes. The
  final owner and affected UI builds have no warnings. The initial full owner
  build retained the existing unused `searchInput` and mutable
  `runtimeLogSnapshot` warnings.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only the UI-test Oracle and its real fixture activation callers.
- Commit: `01c3786f6fe9d15b859fc79645d3bf599aeaa1d2`
  (`test(sync): migrate SYNC-034Q exact window activation`).

### SYNC-034R Closure Record

- Design and Oracle: `tapFirstHittableAfterScrolling` performs an immediate
  readback of the exact option query and its owning scroll container. A
  generation-owned schedule then reads the same candidate projection before
  each optional scroll action. Target/container geometry determines one named
  directional scroll delta, and the next readback is registered only after
  XCUI returns from that action. Success requires the exact first candidate
  whose `exists` and `isHittable` evidence is true.
- Lifecycle and retained time policy: the helper invocation owns the
  condition owner, one pending one-shot timer, scroll-step evidence,
  cancellation, and cleanup. XCUI exposes no option-frame or hittability
  publication callback, so
  `FlowTabUITestConditionObservationPolicy.xcuiReadbackCadence` remains the
  named 100ms conditional-readback cadence. The Settings option-selection
  owner supplies a named 30-second watchdog solely as a terminal failure
  bound. Expiry reports the readback source, candidate indices, first target
  frame, container frame, step count, and last scroll delta.
- UI-test infrastructure regression and Pressure: the final split source
  passed 5/5 tests in 1.256 seconds under
  `.build-local/evidence-driven-sync/SYNC-034R/owner-regression-attempt-009`.
  Coverage includes an already-hittable initial state with no scroll,
  deterministic below/above/unknown geometry, exact resolution after five
  delayed readbacks, 100 cancel/restart/stale-callback iterations, and
  watchdog final-readback diagnostics.
- Affected UI: the canonical wrapper passed
  `testSettingsHotkeySelectionsPersistAcrossRelaunch` 1/1 in 93.136 seconds
  under
  `.build-local/evidence-driven-sync/SYNC-034R/affected-ui-attempt-008`.
  The real Settings topology observed `x`, `y`, and `z` become hittable after
  serial scroll events, clicked only after that evidence, and verified all
  five hotkey values after relaunch. The subsequent source split moved the
  unchanged owner declarations into their single-responsibility file; the
  final UI target and owner suite compile that split successfully. Attempts
  009–012 then terminated at `app.launch()` because macOS left the signed
  fixed-path app in `Running Background`; all four failures occurred before
  the Settings page or scrolling helper, and their independent result bundles
  are retained with the passing affected-path evidence.
- Process/Tooling: the final UI-test target builds through the canonical
  wrapper. The Xcode project plist is valid, `git diff --check` passes, and
  the observation, support, and regression files are 266, 198, and 265 lines.
  The migrated helper contains no raw fixed RunLoop advance. The remaining
  raw loop in `tapElementAfterScrollingIntoView` is a separate owner and
  remains assigned to the next SYNC-034 slice. Startup `prompts.zip` remains
  unchanged and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only one UI-test interaction Oracle and its representative real Settings
  path.
- Commit: `16382e8be956c752351807640891e015ef2bc37f`
  (`test(sync): migrate SYNC-034R dropdown scrolling`).

### SYNC-034S Closure Record

- Design and Oracle: `tapElementAfterScrollingIntoView` performs an immediate
  readback of the exact app row, its preferred scroll container, and available
  fallbacks. Existing preferred-container ownership has precedence; otherwise
  the smallest usable fallback whose horizontal frame contains the target
  midpoint is selected. Success requires the exact target to exist, be
  hittable, and be fully contained by that container. When no container
  exists, exact target existence and hittability are sufficient. Geometry
  determines one serial scroll action after an unresolved readback; the next
  readback is registered only after XCUI returns from that action. The caller
  verifies the resulting selected-app Home title projection independently.
- Lifecycle and retained time policy: the helper invocation owns the
  condition generation, one pending one-shot timer, scroll-step evidence,
  cancellation, and cleanup. XCUI exposes no frame or hittability publication
  callback, so
  `FlowTabUITestConditionObservationPolicy.xcuiReadbackCadence` remains the
  named 100ms conditional-readback cadence. The caller timeout is solely a
  terminal failure bound. Expiry performs a final exact readback and reports
  target existence, hittability, frame, selected container source and frame,
  full-visibility evidence, scroll count, and last delta.
- UI-test infrastructure regression and Pressure: the canonical wrapper
  passed 13/13 tests in 2.886 seconds under
  `.build-local/evidence-driven-sync/SYNC-034S/owner-regression-attempt-001`.
  Coverage joins the shared serial scheduler and SYNC-034R regressions with
  six focused cases: initially satisfied evidence, preferred and smallest
  fallback selection, deterministic above/below/invalid/occluded geometry,
  five delayed readbacks followed by exact resolution, 100
  cancel/restart/stale-callback iterations, and watchdog final-readback
  diagnostics.
- Affected UI: the canonical wrapper rebuilt the real fixture variants and UI
  target under
  `.build-local/evidence-driven-sync/SYNC-034S/affected-ui-attempt-001`.
  Fixture generation, signing, and build-for-testing all returned zero and
  produced a result bundle. UI execution stopped at
  `FlowTabUITests+SpaceFixtureApp.swift:120` because the first
  `com.example.fixture.finder` fixture remained `Running Background` for the
  full foreground-activation watchdog. The test did not reach the Home page
  or this helper; the wrapper recorded
  `stage=xcodebuild_test-without-building_failed` and exit 65. This persistent
  macOS GUI-activation environment blocker leaves the Goal active for a later
  environment-confirmed affected-path run.
- Process/Tooling: the UI-test target builds through the canonical wrapper.
  The Xcode project plist is valid, `git diff --check` passes, and the shared
  scheduler is reused by both scrolling owners. The migrated helper contains
  no raw fixed RunLoop advance. New and touched focused sources remain below
  the 400-line guardrail. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only one UI-test interaction Oracle and its representative multi-app Home
  path.
- Commit: `ac3bb50fd4dec7265ae355edb90ccdaa8c328778`
  (`test(sync): migrate SYNC-034S scrolling visibility`).

### SYNC-034T Closure Record

- Design and Oracle: `selectHomeWorkflowApp` establishes a Home-selection
  generation and reads the exact expected title projection before touching the
  app row. A matching initial projection closes an already-selected state.
  Otherwise the owner gates projection acceptance while the SYNC-034S owner
  derives exact row/container visibility and performs one tap. After the tap
  returns, an immediate `.triggerReadback` closes synchronous SwiftUI
  publication races. A persistent expected-title match is the sole selection
  success Oracle; the caller's unique-title precondition and subsequent full
  title/absence assertions remain independent isolation evidence.
- Lifecycle and retained time policy: the selection invocation owns the
  deferred readback registration, projection generation, row-action owner,
  cancellation, and cleanup. XCUI exposes no window-projection publication
  callback. The shared named 100ms serial readback cadence is activated only
  after an unresolved trigger-return readback and is cancelled on resolution,
  watchdog expiry, restart, or owner teardown. A monotonic watchdog budget
  bounds the complete row-action and projection contract; expiry performs a
  final exact readback and reports phase, acceptance gate, expected title,
  visible static titles, and exact row identifiers/labels/values.
- UI-test infrastructure regression and Pressure: six focused tests cover an
  already matching initial projection, trigger-return publication, delayed
  scheduled publication, duplicate delivery, 100 cancel/restart/stale
  generations, watchdog final-readback diagnostics, and deterministic
  monotonic-budget exhaustion. Two existing Home projection tests and three
  shared condition-owner tests were selected as regressions. The canonical
  wrapper compiled the entire UI-test target without warnings in
  `.build-local/evidence-driven-sync/SYNC-034T/owner-regression-attempt-001`
  and `owner-regression-attempt-002`.
- Environment blocker: both owner attempts completed signing and
  build-for-testing with exit zero and produced independent result bundles.
  XCTest then failed before entering any test method with
  `LocalAuthentication Code=-4`, `System authentication is running`. A
  privileged read-only process check confirmed active `coreauthd` and
  `coreautha` processes. No owner, Pressure, or affected multi-app Home test
  executed, so those required validation layers remain open and the Goal
  remains active.
- Process/Tooling: the Xcode project plist is valid, the migrated selection
  helper contains no raw `Date` deadline or fixed RunLoop advance, and new and
  touched focused sources remain below the 400-line guardrail. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only UI-test selection orchestration and its test-owned observation
  infrastructure.
- Commit: `4ea39c42683aea779b3866a6a0f1d38a3d758075`
  (`test(sync): migrate SYNC-034T Home app selection`).

### SYNC-034U Closure Record

- Design and Oracle: semantic call-site review found no invocation of
  `waitForTopmostWorkflowCGWindow`. Removing the helper closes an ownerless
  frontmost-bundle, CG-window, XCTest-title, and AX-title polling loop without
  changing any executable UI path.
- Lifecycle and retained time policy: the removed helper owned neither an
  observer nor a cancellable schedule. Its wall-clock deadline and raw 100ms
  RunLoop cadence are removed. No duration remains for this contract.
- Validation: zero repository references remain for the symbol. The canonical
  UI wrapper's build-for-testing action compiles the complete UI-test target
  under
  `.build-local/evidence-driven-sync/SYNC-034U/process-build-attempt-001`.
  The build retains the pre-existing unused mutable `runtimeLogSnapshot`
  warning in `FlowTabUITests+SpaceFixtureRuntimeTruthEntrypoints.swift`;
  Unit, Behavior, UI execution, Pressure, and FlowTabCore are not relevant
  because no caller or executable behavior exists. The Xcode project plist is
  unchanged, `git diff --check` passes, and the touched pre-existing support
  file is reduced by 38 lines. Startup `prompts.zip` remains unchanged and
  outside the slice.
- Commit: `d3d8d55a04eb5a856a574c9d144ffdef1a9b936a`
  (`test(sync): remove SYNC-034U obsolete topmost wait`).

### SYNC-034V Closure Record

- Design and Oracle: `waitForExactFrontmostWorkflowCGWindow` now reuses the
  SYNC-034Q generation-owned activation observer. Workspace activation and
  target-process AX focused/main-window event sources are registered before
  the immediate initial readback. Success requires the exact expected
  frontmost bundle identifier and exact topmost on-screen CGWindowID. This
  persistent condition accepts an already-satisfied initial state, while all
  fourteen executable call sites retain their independent title, frame,
  topology, and workflow assertions.
- Lifecycle and retained time policy: each helper invocation owns the
  workspace token, AX observer registrations, one pending serial readback,
  generation rejection, cancellation, and cleanup. CGWindow/Space publication
  exposes no complete notification, so the shared named 100ms serial cadence
  remains a conditional readback opportunity. The caller timeout is solely a
  terminal failure bound; expiry performs a final readback and reports source,
  generation, frontmost bundle, topmost CG window number/title/frame, active
  title, and expected-title observability.
- UI-test infrastructure regression and Pressure: the shared owner has six
  focused tests covering observer registration before readback, exact initial
  state, post-baseline event resolution, exact bundle/window identity, five
  delayed observations, 100 cancel/restart/stale-generation iterations, and
  watchdog final-readback diagnostics. The canonical wrapper compiled these
  tests and the complete UI-test target successfully under
  `.build-local/evidence-driven-sync/SYNC-034V/process-build-attempt-001`.
- Environment blocker: the current read-only process observation confirms
  active `SecurityAgent`, `coreauthd`, and `coreautha`. The two preceding
  canonical test attempts failed during XCTest initialization with
  `LocalAuthentication Code=-4`, `System authentication is running`, before
  entering any test method. Owner, Pressure, and affected global/in-app/search
  fixture UI execution remain open, and the Goal remains active.
- Process/Tooling: the canonical build status reports `stage=completed`,
  final exit zero, signing exit zero, and build-for-testing exit zero. The
  build retains the existing unused `searchInput` warning in
  `FlowTabUITests+SpaceFixtureEdgeInputsWorkflow.swift`. The migrated helper
  contains no raw deadline or fixed RunLoop advance; the four remaining raw
  loops in the same support file are independently owned later slices.
  Observation implementation and regression files are 374 and 331 lines;
  the pre-existing support file is 708 lines with one workflow-window
  observation responsibility. The Xcode project is unchanged,
  `git diff --check` passes, and startup `prompts.zip` remains unchanged and
  outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only a UI-test exact-window Oracle and reuses test-owned observation
  infrastructure.
- Commit: `6e1441a8ae82106ab56b2dc107fce9a462b7b0aa`
  (`test(sync): migrate SYNC-034V exact CG window wait`).

### SYNC-034W Closure Record

- Design and Oracle: the three executable
  `waitForFrontmostWorkflowSpaceCGWindow` call sites now create a narrow
  generation-owned owner before their first readback. Success requires the
  exact target bundle to be frontmost and its topmost on-screen CG window to
  match the expected fixture title or the established titleless
  fullscreen-Space frame contract. The owner returns that exact
  `WorkflowCGWindowObservation`, preserving downstream window identity,
  topology, and fixture assertions in the Option+Tab, Control+Tab, and window
  search workflows.
- Lifecycle and retained time policy: each helper invocation owns the
  workspace activation token, target-process AX focused/main-window
  registrations, one pending serial readback, generation rejection,
  cancellation, and cleanup. CGWindow/Space publication exposes no complete
  notification, so the shared named 100ms cadence remains a conditional
  readback opportunity. The caller timeout is solely a terminal failure
  bound; expiry performs a final readback and reports generation, source,
  expected bundle/title, frontmost bundle, and the final topmost window
  number/title/frame.
- UI-test infrastructure regression and Pressure: six focused tests cover
  registration before an already-satisfied initial readback, rejection of a
  mismatched frontmost bundle and window title, titleless fullscreen-frame
  evidence, resolution after five delayed scheduled readbacks, 100
  cancel/restart/stale-generation iterations, duplicate notification
  delivery, and watchdog final-readback diagnostics. Both the owner and tests
  compile in the complete UI-test target.
- Environment blocker: active `SecurityAgent`, `coreauthd`, and `coreautha`
  still match the environment that produced
  `LocalAuthentication Code=-4`, `System authentication is running`, before
  any XCTest method in the preceding canonical attempts. Owner, Pressure, and
  affected Option+Tab/Control+Tab/window-search fixture UI execution remain
  open, and the Goal remains active.
- Process/Tooling: the final canonical build at
  `.build-local/evidence-driven-sync/SYNC-034W/process-build-attempt-002`
  reports `stage=completed`, with zero final, signing, and build-for-testing
  exit codes. The build retains the existing unused `runtimeLogSnapshot` and
  `searchInput` warnings in independently owned future migration paths. The
  project plist is valid, all new project references are unique,
  `git diff --check` passes, and the focused owner and regression files are
  131 and 275 lines. Extraction reduces the pre-existing workflow-window
  support file from 708 to 699 lines. Its three remaining raw loops are
  independently owned later slices. Startup `prompts.zip` remains unchanged
  and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only one UI-test fullscreen-Space Oracle and test-owned observation
  infrastructure.
- Commit: `3eeaea6bea7288a46ea2eea8f6b25e354a5207d6`
  (`test(sync): migrate SYNC-034W frontmost Space window`).

### SYNC-034X Closure Record

- Design and Oracle: semantic call-site review found no invocation of the
  `waitForActiveSpaceWorkflowCGWindow` overload whose first label is
  `windowNumber`. All three executable calls use the separately owned
  title/fullscreen-Space overload. Removing the unused overload closes its
  ownerless topmost-window loop without changing an executable UI path.
- Lifecycle and retained time policy: the removed overload owned no observer
  or cancellable schedule. Its wall-clock deadline and raw 100ms RunLoop
  cadence are removed, leaving no duration for this contract.
- Validation: the overload pattern has zero Swift references. The canonical
  UI wrapper's build-for-testing action compiles and signs the complete
  UI-test target under
  `.build-local/evidence-driven-sync/SYNC-034X/process-build-attempt-001`,
  with zero final, signing, and build exit codes. The build retains the
  existing unused `runtimeLogSnapshot` warning in a future migration path.
  Swift parsing and `git diff --check` pass, and the pre-existing
  workflow-window support file is reduced from 699 to 667 lines. Unit,
  Behavior, UI execution, Pressure, and FlowTabCore are not relevant because
  the removed overload has no caller. Startup `prompts.zip` remains unchanged
  and outside the slice.
- Commit: `911cfa9216aaba12962002526849977d22a3eab1`
  (`test(sync): remove SYNC-034X obsolete active-Space wait`).

### SYNC-034Y Closure Record

- Design and Oracle: all three executable
  `waitForActiveSpaceWorkflowCGWindow(title:app:timeout:)` calls now reuse the
  workflow-Space window owner with an explicit `activeSpace` scope. They run
  after the FlowTab panel is ready, so the scope accepts FlowTab as the
  system-frontmost application and succeeds only when the target fixture's
  topmost on-screen CG window matches the expected title or established
  titleless fullscreen-frame contract. The `frontmost` scope continues to
  require the exact target bundle for SYNC-034W.
- Lifecycle and retained time policy: each helper invocation installs
  workspace activation and target-process AX focused/main-window event sources
  before the immediate readback. It owns one pending serial readback,
  generation rejection, cancellation, and cleanup. CGWindow/Space publication
  exposes no complete notification, so the shared named 100ms cadence remains
  a conditional readback opportunity. The caller timeout is solely a terminal
  failure bound; expiry performs a final readback and reports scope, expected
  title, generation, source, frontmost bundle, and final topmost window
  number/title/frame.
- UI-test infrastructure regression and Pressure: the shared owner now has
  seven focused tests. A new initial-state case proves that `activeSpace`
  accepts exact target-window evidence while FlowTab is frontmost. Existing
  coverage preserves frontmost-bundle rejection, title and titleless
  fullscreen matching, observer-before-readback ordering, five delayed
  readbacks, duplicate delivery, 100 cancel/restart/stale-generation
  iterations, and watchdog final-readback diagnostics. The complete UI-test
  target compiles all seven tests.
- Environment blocker: the active system-authentication environment matches
  the preceding `LocalAuthentication Code=-4`,
  `System authentication is running` failures that occurred before any XCTest
  method. Owner, Pressure, and affected Option+Tab/Control+Tab/window-search UI
  execution remain open, and the Goal remains active.
- Process/Tooling: the canonical build at
  `.build-local/evidence-driven-sync/SYNC-034Y/process-build-attempt-001`
  reports `stage=completed`, with zero final, signing, and build-for-testing
  exit codes. The build retains the existing unused `runtimeLogSnapshot` and
  `searchInput` warnings in independent future slices. Swift parsing and
  `git diff --check` pass. The shared owner and regression files are 188 and
  310 lines, and this extraction reduces the pre-existing workflow-window
  support file from 667 to 658 lines. Its sole remaining raw loop is the
  separately owned multi-window Space-containing contract. Startup
  `prompts.zip` remains unchanged and outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only one UI-test active-Space Oracle and test-owned observation
  infrastructure.
- Commit: `8ef8de839b7bb59f9c2509caa3fed372449948f6`
  (`test(sync): migrate SYNC-034Y active-Space window`).

### SYNC-034Z Closure Record

- Design and Oracle: all five executable
  `waitForWorkflowSpaceContainingCGWindow(title:app:timeout:)` calls now use a
  generation-owned full-window-collection observer. These paths deliberately
  launch noisy sibling windows, so success comes from any target-process
  on-screen CG window whose title matches the expected value or whose
  titleless frame satisfies the established fullscreen-Space geometry
  contract. Window ordering remains diagnostic evidence and a matching
  non-topmost sibling resolves immediately.
- Lifecycle and retained time policy: each helper invocation installs
  workspace activation and target-process AX focused/main-window event sources
  before the immediate full-collection readback. It owns one pending serial
  readback, generation rejection, cancellation, and cleanup. CGWindow/Space
  publication exposes no complete notification, so the shared named 100ms
  cadence remains a conditional readback opportunity. The caller timeout is
  solely a terminal failure bound; expiry performs a final readback and reports
  every observed on-screen window number, title, and frame.
- UI-test infrastructure regression and Pressure: five focused tests cover an
  initially matching non-topmost sibling with observer-before-readback
  ordering, five delayed readbacks followed by event resolution, titleless
  fullscreen matching, 100 cancel/restart/stale-generation iterations with
  duplicate events, and watchdog final-collection readback. The complete
  UI-test target compiles all five tests and the five affected noisy
  Option+Tab, Control+Tab, and window-search call paths.
- Environment blocker: the active system-authentication environment matches
  the preceding `LocalAuthentication Code=-4`,
  `System authentication is running` failures that occurred before any XCTest
  method. The final read-only process check still finds `SecurityAgent`,
  `coreautha`, and both `coreauthd` processes. Owner, Pressure, and affected
  real-topology UI execution remain open, and the Goal remains active.
- Process/Tooling: the canonical build at
  `.build-local/evidence-driven-sync/SYNC-034Z/process-build-attempt-004`
  reports `stage=completed`, with zero final, signing, and build-for-testing
  exit codes. The first full compile records the existing unused
  `runtimeLogSnapshot` and `searchInput` warnings for independent future
  slices; the final incremental compile adds no diagnostic. A restricted
  attempt 003 stopped during SwiftPM manifest loading when sandboxed temporary
  file creation was denied, before source compilation. Swift parsing, project
  plist validation, and `git diff --check` pass. The project references are
  unique. The focused owner and regression files are 111 and 226 lines, and
  the workflow-window support file is reduced from 658 to 651 lines with no
  raw time-driven loop remaining. Startup `prompts.zip` remains unchanged and
  outside the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only one UI-test noisy-window collection Oracle and test-owned observation
  infrastructure.
- Commit: `9f9fec8f7c1e39327a473c0dd195da9d4bc00ad4`
  (`test(sync): migrate SYNC-034Z Space window collection`).

### SYNC-034AA Closure Record

- Design and Oracle: both screenshot-luminance assertions in
  `testSettingsAppearanceThemeAndLanguageUpdateVisibleUI` now establish a
  generation-owned observer before selecting light or dark appearance.
  Evidence remains gated while the action runs. The action-return readback or
  a later scheduled readback succeeds only when the exact Settings content
  element exists and its sampled average sRGB luminance satisfies the named
  light or relative-dark threshold. The existing exact theme-control value
  assertions remain independent Oracles.
- Lifecycle and retained time policy: each helper invocation owns its
  observation generation, one serial scheduled readback, trigger gate,
  cancellation, and cleanup. It performs an immediate `.triggerReadback`.
  Screenshot pixels expose no publication callback, so the shared named 100ms
  XCUI cadence remains a conditional observation opportunity. The five-second
  caller watchdog is solely a terminal failure bound and reports acceptance
  state, element identifier/existence, expected threshold, final luminance,
  generation, source, and waiter result.
- UI-test infrastructure regression and Pressure: five focused tests cover a
  matching initial readback, rejection before trigger completion followed by
  immediate trigger readback, five delayed scheduled readbacks, 100
  cancel/restart/stale-generation iterations with duplicate delivery, and
  watchdog final-readback diagnostics. The complete UI-test target compiles all
  five tests and the affected real Settings path.
- UI environment blocker: fixed-path app installation succeeds with the local
  Apple Development identity. The owner attempt at
  `.build-local/evidence-driven-sync/SYNC-034AA/owner-attempt-001`
  prepares fixtures and signs the runner, then exits 65 before every test
  method with `Timed out while enabling automation mode`; its result bundle is
  present. The post-attempt process readback finds `coreautha` active again.
  Owner, Pressure, and affected Settings UI execution remain open, and the Goal
  remains active.
- Process/Tooling: the canonical build at
  `.build-local/evidence-driven-sync/SYNC-034AA/process-build-attempt-001`
  reports `stage=completed`, with zero final, signing, and build-for-testing
  exit codes. Its only source warnings are the existing unused `searchInput`
  and mutable `runtimeLogSnapshot` candidates in independent future slices.
  Swift parsing, project plist validation, unique project-reference checks,
  zero raw `Date`/RunLoop loops in `FlowTabUITests+Settings`, and
  `git diff --check` pass. The owner and regression files are 196 and 213
  lines; the Settings file remains within its existing single-responsibility
  guardrail at 786 lines. Startup `prompts.zip` remains unchanged and outside
  the slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only one UI-test screenshot appearance Oracle and test-owned observation
  infrastructure.
- Commit: pending local slice commit.

### SYNC-035A Closure Record

- Design and Oracle: the System MRU path establishes an XCTest predicate
  expectation for nonexistence of the exact switcher summary before sending
  Escape. Dismissal succeeds only when that persistent accessibility element
  is absent, including an initially absent readback. The next trigger begins
  only after this evidence is observed.
- Lifecycle and timeout policy: each helper invocation owns its expectation.
  `FlowTabUITestSystemAppMRUPolicy.switcherDismissalWatchdog` is solely a
  terminal failure bound; expiry reports the final switcher accessibility
  hierarchy through `switcherDebugSummary`.
- UI affected path and Pressure: the real eight-application System MRU
  topology completed ten consecutive Escape dismissal and switcher reopen
  iterations, while preserving the exact expected application order. The
  test passed 1/1 in 42.311/42.313 seconds, with 43.655 seconds total test
  operation time, at
  `.build-local/evidence-driven-sync/SYNC-035A/system-mru-attempt-001`.
- Process/Tooling: the changed Swift file parses, the Xcode project plist is
  valid, compiler diagnostics contain no warning for the changed file, the
  fixed 300ms RunLoop advance has no remaining reference in
  `FlowTabUITests+SystemAppMRU`, the file is 264 lines, and
  `git diff --check` passes. Final exact staged-content review is recorded
  before commit. Startup `prompts.zip` remains unchanged and outside the
  slice.
- Unit, Behavior, and FlowTabCore: not relevant because this slice changes
  only one UI-test presentation lifecycle and its existing real-topology
  path.
- Commit: `9e84dbe7675f0d9c070c3b074ecbe9c58c779dbf`
  (`test(sync): migrate SYNC-035A switcher dismissal`).

### SYNC-035B Closure Record

- Design and Oracle: `assertTriggerMakesValue` starts the existing
  generation-owned element-value observer before sending Tab. Its acceptance
  gate remains closed through the trigger, so an already matching baseline
  cannot prove commit completion. Success requires the delay field to exist
  and publish the exact normalized accessibility value `1.23`; the relaunch
  readback independently proves persistence.
- Lifecycle and retained cadence: the helper invocation owns the serial
  scheduled observation and cancels it on success, watchdog expiry, or scope
  exit. XCUI exposes no text-field value publication callback, so the shared
  named 100ms readback cadence remains a conditional observation policy. The
  five-second caller watchdog is solely a failure bound and reports identifier,
  existence, acceptance state, expected predicate, actual value, generation,
  source, and waiter result.
- Deterministic regression: matching baseline rejection before trigger
  completion, scheduled post-trigger resolution, initial exact-value
  resolution, prefix resolution, cancellation, and watchdog final evidence
  passed 3/3 in 1.145/1.150 seconds. Total test operation time was 7.360
  seconds at
  `.build-local/evidence-driven-sync/SYNC-035B/owner-regression-attempt-002`.
- UI affected path: the real Settings path entered `1.2345`, observed exact
  post-Tab normalization to `1.23`, toggled both adjacent preferences, and
  verified all three persisted values after relaunch. It passed 1/1 in
  21.712/21.716 seconds, with 22.441 seconds total operation time, at
  `.build-local/evidence-driven-sync/SYNC-035B/affected-ui-attempt-001`.
- Process/Tooling: both final wrapper status files report `completed`, zero
  final, signing, build, and test exit codes, and present result bundles. Four
  changed Swift files parse and compile, the fixed 200ms helper and its sole
  caller are removed, the project plist is valid, and `git diff --check`
  passes. The build retains two warnings in unchanged future migration paths.
  The owner and regression files are 162 and 152 lines; the Settings test file
  remains within the 800-line single-responsibility guardrail at 779 lines,
  and Support shrinks to 753. Startup `prompts.zip` remains unchanged and
  outside the slice.
- Unit, Behavior, FlowTabCore, and Pressure: not relevant because this slice
  changes one UI-test commit Oracle, reuses the pressure-validated shared
  serial scheduler, and does not change application runtime behavior.
- Commit: `881cca7be035f367bf8f72cae23bf32d37c70ed1`
  (`test(sync): migrate SYNC-035B settings commit`).
