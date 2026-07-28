# Evidence-Driven Synchronization Migration

Updated: 2026-07-28

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
| SYNC-011 | `FlowTab/Features/Home/HomeLandingView.swift`; permission watcher | A perpetual one-second poll discovers TCC permission changes even though app activation is already observed. Evidence migration. | Subscribe before initial permission readback and refresh on app-activation/lifecycle evidence. If a platform permission transition has no notification, share the controlled permission observer from SYNC-012. View appearance owns start/stop. | M; Unit, Behavior, Home permission UI. | planned |
| SYNC-012 | `FlowTab/Features/Settings/AppSettingsView.swift`; permission prompt observation | Forty 500ms attempts inferred post-prompt TCC convergence; the first condition check occurred after a sleep and cancellation was swallowed. Conditional observation plus watchdog. | Install the shared app-activation observer before an immediate readback, take an independent post-request readback, and use a named cancellable fallback cadence for TCC transitions without callbacks. The terminal watchdog reports target, generation, readbacks, elapsed time, bundle identity, and final evidence. Settings visibility owns both target observations. | H; Unit, Behavior, permission UI, tab-switch Pressure. | completed |
| SYNC-013 | `FlowTab/Features/Home/HomeLandingView.swift`, `HomeRuntimeProjectionService.swift`; initial and scoped Home refresh | Fixed 900ms startup and 120/220ms post-signal delays assume runtime projection commits have arrived. Evidence migration. | Subscribe before requesting maintenance, capture source generation, perform initial readback, and apply only a matching later app-switcher/current-app projection generation or completeness transition. Home visibility and per-app request generations own cancellation. | H; Unit, Behavior, Home UI, runtime-topology Pressure. | planned |
| SYNC-014 | `FlowTab/App/AppFoundation.swift`; `AppWindowCoordinator.scheduleAccessoryPolicyRestoration` | Up to 250 polls at 20ms infer that a status-item-opened regular window is active and visible. Conditional observation plus watchdog. | Register app/window observers before presentation, perform immediate visibility/activation readback, and complete on the matching window transition. A named cancellable condition observer is the fallback; watchdog diagnostics include app-active, visible, miniaturized, and activation-policy state. `AppWindowCoordinator` owns the task/observers. | H; Unit, Behavior, status-item UI. | planned |
| SYNC-015 | `SwitcherSearchCoordinator.scheduleRebuild`, `LiveSwitcherModel.scheduleSearchComputation` | 10–45ms delays debounce query work; result publication already requires revision and query/scope equality. Domain duration. | Retain as one named search scheduling policy with injectable scheduler/clock, cancellation, and revision Oracle. Remove duplicate scheduling ownership if both paths serve the same contract. | H hot path; Unit, Behavior, Search UI, realistic/stress Search Pressure. | verification-needed |
| SYNC-016 | `FlowTab/Features/Settings/HotkeySettingsCard.swift`; `updateTakeoverStatus` | A 250ms delay is treated as confirmation that Command+Tab takeover stayed inactive. Evidence migration. | Publish registration result/marker generation from the hotkey owner and render status from that readback. The card observes before requesting registration and owns subscription cleanup. | M; Unit, Behavior, Settings UI. | planned |
| SYNC-017 | `SwitcherPanelController+InputHandling.swift`; modifier-release confirmation and replay suppression | Hardware release is inferred from repeated samples after fixed intervals. Conditional observation. | Consume flags/key transition events first, immediately read hardware state, and retain named cancellable sampling only for missed global events. Stable released-state samples remain the condition Oracle; session and confirmation generations own cancellation. | H; Unit, Behavior, switcher UI, interaction Pressure. | planned |
| SYNC-018 | `SwitcherPanelController+Hotkeys.swift`, `+SelectionLifecycle.swift`; tab throttle and post-finish ignore | 16ms and 20ms windows discard input assumed to be duplicate/replayed, so scheduling can change the selected result. Evidence migration. | Deduplicate by concrete event identity and session/input generation, and suppress replay until observed modifier/main-key release. The active presentation session owns the state. | H; Unit, Behavior, switcher UI, interaction Pressure. | planned |
| SYNC-019 | `SwitcherPanelController+InitialVisibilityRecovery.swift`; initial visibility grace/deadline | A grace duration decides whether occlusion is stale and later triggers failure. Evidence migration plus watchdog. | Establish the panel occlusion/key/order observer before presentation, use initial readback and later presentation generation to prove visibility, and retain one named terminal watchdog that reports the last visibility snapshot. The presentation session owns it. | H; Unit, Behavior, switcher UI, runtime-topology Pressure. | planned |
| SYNC-020 | `SwitcherPanelController+Presentation.swift`; visibility recovery attempts and hard reorder | Fixed attempt delays and a fixed order-out/order-front gap assume AppKit has committed window ordering. Evidence migration/conditional observation. | Attempt from observed hidden/occluded evidence, await matching key/occlusion/order transitions, and verify `isPanelVisibleToUser` after each action. Use next-main-turn or named cancellable condition observation only where AppKit has no callback; terminal failure includes the last `PanelVisibilitySnapshot`. | H; Unit, Behavior, switcher UI, runtime-topology Pressure. | planned |
| SYNC-021 | `SwitcherPanelController+Presentation.swift`, `+InputHandling.swift`; active-Space ignore and activation-suppression windows | 350ms/500ms windows assume which Space notifications belong to FlowTab's own presentation/migration. Evidence migration. | Correlate Space topology projection generation, active presentation generation, panel visibility readback, and the triggering workspace notification. End suppression on the matching observed transition. | H; Unit, Behavior, cross-Space UI, runtime-topology Pressure. | planned |
| SYNC-022 | `SwitcherPanelController+Presentation.swift`, `+InputHandling.swift`; terminate interruption protection | Five-second and 500ms windows infer that termination and post-refresh work remain in flight. Evidence migration plus watchdog. | Track an explicit termination request generation from request acceptance through matching PID termination/projection removal. Protection ends on that evidence; a named watchdog only terminates stale state and logs the last process/projection observation. | H; Unit, Behavior, termination UI, runtime-topology Pressure. | planned |
| SYNC-023 | `SwitcherPanelController+Hotkeys.swift`, `AppPreferences.swift`; delayed window-layer entry | The user-configured delay is the product contract. A secondary 350ms timer currently probes projection readiness. Domain duration plus evidence migration. | Retain the persisted auto-entry deadline under a named injectable scheduler. Enter only when both the user deadline and matching projection readiness are observed; remove the secondary readiness timer and react to projection generation events. The panel session owns timer cancellation. | H; Unit, Behavior, switcher UI, interaction Pressure. | planned |
| SYNC-024 | `SwitcherPanelController+Hotkeys.swift`, `SwitcherPanelPreviewViews.swift`, `SwitcherPanelOverlayView.swift`, `HomeChrome.swift`, Settings navigation; press/reveal/visual animation durations | Fixed durations express visual feedback or a bounded degraded reveal, including the 80ms terminate press, 120/140/180ms animations, and 250ms preview reveal bound. Domain duration/watchdog. | Centralize named animation/reveal policies. Actions that require animation completion use scheduler/completion evidence; preview readiness remains the preferred Oracle and the reveal watchdog records readiness state before degraded reveal. Session/view lifetime owns cancellation. | M; Unit where policy logic changes, Behavior, affected UI. | verification-needed |
| SYNC-025 | `SwitcherPanelController+PresentationDiagnostics.swift`; frame-delay probe | A 16ms sleep samples an assumed later display frame for diagnostics only. Domain measurement. | Drive the second probe from an actual display/update callback or explicitly named diagnostic scheduler; it must not affect behavior. The probe task is canceled with the presentation session. | L; Behavior diagnostic assertion, Process/Tooling. | planned |
| SYNC-026 | `FlowTabSpaceFixture/SpaceFixtureWindowCoordinator.swift`; fullscreen chain, desktop refocus, AX suppression | Fullscreen entry has a completion callback, while 1.2s/1.4s/5s/8s settle delays sequence later fixture state. Evidence migration. | Chain fullscreen/refocus/accessibility publication from window/fullscreen/key/occlusion readbacks and explicit transition acknowledgements. Retain only workflow-configured latency that is itself a fixture scenario. The coordinator owns cancellable scheduled actions/observers. | H fixture topology; Unit, Behavior, real fixture UI, runtime-topology Pressure. | planned |
| SYNC-027 | `SpaceFixtureAppDelegate`, `SpaceFixtureLaunchConfiguration`; terminate and close delay options | Configured terminate/close latency intentionally creates a slow-process or window-removal scenario. Domain duration. | Retain as named fixture fault policies with injectable scheduler, cancellation, and explicit “scheduled/applied” acknowledgement. App delegate/coordinator own pending work. | M; Unit, Behavior, representative fixture UI. | verification-needed |
| SYNC-028 | `SpaceFixtureWindowContentView`, `SpaceFixtureWindowCoordinator`; workflow readiness labels | “Ready” is published before asynchronous fullscreen/refocus/close topology transitions complete, forcing UI settle waits. Evidence migration. | Publish a monotonic fixture transition generation/stage only after exact planned windows and requested fullscreen/key/AX exposure states are read back. UI observers establish a baseline before launch/action and wait for a later matching stage. | H; Unit, Behavior, all affected real fixture UI, runtime-topology Pressure. | planned |
| SYNC-029 | `FlowTab/TestingSupport/FlowTabUITestBootstrapper.swift`; `presentInitialUIIfNeeded` | Twenty 150ms retries and two equal snapshots infer runtime projection stability before opening Search/switcher. Evidence migration. | Observe runtime projection commit notifications before bootstrap, capture baseline generation, perform initial readback, and open from a matching complete later generation. A shared UI-test watchdog reports the last session/projection signature. Bootstrapper owns observer/task cleanup. | H test orchestration; Behavior, UI, runtime-topology/Search Pressure. | planned |
| SYNC-030 | `FlowTabUITestBootstrapper.installMockWindowPreviewsIfNeeded`, initial stale occlusion hook | Thread sleep and millisecond launch options intentionally inject preview latency or stale visibility. Domain fixture duration. | Retain as named fault-injection policies, preferably backed by controllable gates/acknowledgements; ensure cancellation and completion markers are owned by TestingSupport and UI tests wait on the resulting Oracle. | M; Behavior, affected UI, Pressure when used. | verification-needed |
| SYNC-031 | `FlowTab/TestingSupport/FlowTabLaunchTesting.swift`; `TabSwitchStressRunner` | Switch cadence and total duration define the pressure workload. Domain duration. | Retain named protocol inputs, use a monotonic injectable clock/scheduler, propagate cancellation, and terminate only after the required workload/duration evidence. Runner task owns cancellation and cleanup. | M hot path; Unit/Behavior for runner, tab-switch Pressure, Process/Tooling. | verification-needed |
| SYNC-032 | `FlowTabTests/FlowTabTests+Support.swift`, `FlowTabPriorityCoverageTests+AsyncSupport.swift`; shared async waits | Generic polling is used even where production callbacks, notifications, generations, or task completion are available; cancellation is swallowed. Evidence migration/conditional observation. | Add expectation/notification/task-completion helpers that observe before triggering. Keep one named immediate-check condition observer only for predicates without an event source, with cancellation and last-observation diagnostics. | M; app Unit/Behavior, Process/Tooling. | planned |
| SYNC-033 | App tests with direct fixed waits: `FlowTabTests+CompactActionButton`, `+EnglishLayout`, `+PreferencesAndDiagnostics`, `FlowTabPriorityCoverageTests+PanelSessionBehavior`, `+RuntimeProjectionNotificationPublication`, `+RuntimeSpaceClassification`, `+SwitcherInteractionRegressions`; simulated latency in `+RuntimeSnapshotPressure` | Raw RunLoop advances and 60/80/250ms sleeps are used for settling or race setup; snapshot pressure sleep represents injected I/O latency. Evidence migration/domain pressure duration. | Replace settling with callbacks/state/generation expectations. Retain simulated latency only as a named injectable workload gate or pressure policy. Each test owns expectation cleanup and watchdog reporting. | M; affected Unit/Behavior and Pressure, Process/Tooling. | planned |
| SYNC-034 | `FlowTabUITests+Support.swift`, `+WorkflowWindowObservation.swift`, `+SpaceFixtureApp.swift`, `+ScrollingSupport.swift`, `+StatusItem.swift`, and fixture assertion helpers; shared UI condition loops | RunLoop cadence advances drive XCUI/CG/AX/process predicate observation. Conditional observation. | Centralize named UI observation cadence and watchdog diagnostics, check immediately, use `waitForExistence`/predicate expectations where possible, and keep exact CG/AX/window/process readback as the sole Oracle. XCTest case lifetime owns the wait. | H test infrastructure; affected UI suites, Process/Tooling. | planned |
| SYNC-035 | Direct UI settle waits in Search, Settings, Home/Logs, MRU, Space fixture and switcher workflow tests; files enumerated in the UI audit scope below | Fixed 80ms–1.2s RunLoop advances occur between input/action and assertion, so assertion timing can change results. Evidence migration. | Remove each settle wait in favor of the affected visible element, log marker, fixture generation, process state, exact frontmost CG/AX window, or nonexistence Oracle. Observer/baseline setup precedes the action. | H; affected UI suites and matching Behavior coverage. | planned |
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
   SYNC-009–SYNC-014.
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
- Commit: `refactor(sync): migrate SYNC-012 permission observation`; its exact
  SHA is appended by the next ledger update after the commit exists.
