# Performance Pressure Workflow

Use this reference when deciding whether a change requires pressure testing, which pressure path to run, and what evidence must be reported.

Pressure testing is required when the risk is about sustained CPU, RSS growth, latency, throughput, or scale behavior. It does not replace unit, behavior, or UI validation. It is a separate validation layer for hot paths and scale-sensitive code.

## Contents

- [Required Outcome](#required-outcome)
- [When Pressure Testing Is Required](#when-pressure-testing-is-required)
- [Fast Trigger Heuristic](#fast-trigger-heuristic)
- [Choose the Right Pressure Scenario](#choose-the-right-pressure-scenario)
- [Reporting Standard](#reporting-standard)
- [Rejection Criteria](#rejection-criteria)

## Required Outcome

- Identify whether the change touches a pressure-sensitive path before calling the task done.
- Run the relevant pressure scenario when the change can affect sustained load, repeated interaction cost, or scale-sensitive behavior.
- Report the scenario, duration, sampling method, and baseline comparison.
- Use the nearest same-machine baseline from `docs/DEVELOPMENT.md`, `docs/TEST_COVERAGE_CHECKLIST.md`, or a previous named `.build-local` result when available.
- If no comparable baseline exists, record the run as a new local baseline and state that it is not a regression comparison.
- Treat unexplained CPU regressions or warm-state RSS growth as blockers, not as optional follow-up.

## When Pressure Testing Is Required

Run pressure validation before submission if the change touches any of these categories:

- High-frequency interaction paths that run on repeated input or navigation.
  Examples: search keystrokes, panel result movement, tab switching, repeated panel presentation, active-space interruption handling.
- Costs that grow with app count, window count, result count, or preview count.
  Examples: search indexing, candidate filtering, ranking, runtime snapshot assembly, window dedupe, preview list generation.
- Long-lived resources or repeated async work.
  Examples: caches, debounce windows, background `Task` chains, timers, observers, preview pipelines, screen-capture polling, accessibility scans.
- Heavy SwiftUI or AppKit surfaces that are shown repeatedly or kept alive.
  Examples: Home, Logs, Settings, switcher panel content, search result lists, preview surfaces.
- Runtime-topology paths that coordinate real apps, windows, spaces, fullscreen transitions, or cross-space activation.
  Examples: multi-app workflow startup, space-aware search activation, fullscreen target activation, off-space snapshot recovery.

## Fast Trigger Heuristic

Pressure testing is required when two or more of the following are true:

1. The code runs on every key press, tab switch, search refresh, panel refresh, or active-space change.
2. The cost can grow with the number of apps, windows, search results, previews, or spaces.
3. The change alters caching, object lifetime, async scheduling, or repeated runtime polling.
4. The change increases UI tree complexity, layout work, cross-process calls, or preview generation.

If one answer is true and the path is already a known hot area in `docs/DEVELOPMENT.md`, still treat pressure testing as required.

## Choose the Right Pressure Scenario

### Tab-Switch Stress

Use this for:

- Left-side tab switching changes in Home, Logs, or Settings.
- Page lifecycle changes such as `onAppear`, `onDisappear`, `@StateObject`, keep-alive, or restoration behavior.
- Changes to heavy page composition or logs presentation.

Minimum validation:

- Run `./scripts/perf/tab-switch-stress.sh 20 20 0.5`
- Prefer adding the lower-frequency comparison run `./scripts/perf/tab-switch-stress.sh 20 50 0.5`
- Record `CPU avg/peak` and `RSS avg/peak`

### Search Pressure

Use this for:

- `SwitcherSearchCoordinator` matching, tokenization, caches, candidate selection, or ranking changes.
- Search debounce, async scheduling, result rebuild cadence, or state publication changes.
- Any code that can materially affect search-path CPU, memory, or throughput.

Minimum validation:

- Use a dataset of at least `10,000` windows such as `400 apps x 25 windows`
- Sample `%CPU` and `RSS` every `0.5s`
- Run each scenario for at least `30s`
- Cover both `realistic` and `stress` input rhythms
- Report `avg / p95 / max` and throughput

### Runtime Topology Pressure

Use this for:

- Multi-app workflow startup changes.
- Runtime snapshot, window mapping, grouping, dedupe, or active-space recovery changes.
- Cross-space or fullscreen search-and-activate flows.
- Changes to repeated preview, activation, or topology-aware panel behavior.

Minimum validation:

- Use real or fixture-driven multi-app topology, not only mock snapshots
- Include at least one cross-space or fullscreen target when that path is affected
- Exercise repeated panel open, search, selection, and activation rather than a single happy-path click
- Record CPU and RSS behavior for the repeated interaction window and compare against the last known baseline

## Reporting Standard

Every required pressure run should report:

- Which pressure scenario was used
- Why that scenario matches the changed code path
- Duration, sampling cadence, and dataset or topology size
- CPU and RSS summary, plus throughput when relevant
- Comparison against the prior same-machine baseline or the most recent known good run, when available
- Whether the result is a regression comparison or a newly recorded local baseline
- Whether any observed regression is expected, explained, and accepted

## Rejection Criteria

- Reject completions that change known hot paths and skip pressure validation without a concrete reason.
- Reject unexplained sustained CPU regressions.
- Reject RSS curves that continue climbing after warm-up without explanation.
- Reject pressure results that use toy-scale data when the production risk is scale-sensitive.
- Reject relying on unit, behavior, or UI correctness alone when the change clearly affects sustained-load behavior.
