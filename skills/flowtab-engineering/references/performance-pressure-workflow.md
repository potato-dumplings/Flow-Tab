# Performance Pressure Workflow

Use this reference when deciding whether a change requires pressure testing, which pressure path to run, and what evidence must be reported.

Pressure testing is required when the risk concerns sustained CPU, RSS growth, latency, throughput, or scale behavior. For hot paths and scale-sensitive code, pressure testing is a validation layer alongside unit, behavior, and UI validation.

## Contents

- [Required Outcome](#required-outcome)
- [When Pressure Testing Is Required](#when-pressure-testing-is-required)
- [Fast Trigger Heuristic](#fast-trigger-heuristic)
- [Choose the Right Pressure Scenario](#choose-the-right-pressure-scenario)
- [Reporting Standard](#reporting-standard)
- [Rejection Criteria](#rejection-criteria)

## Required Outcome

- Identify whether the change touches a pressure-sensitive path before calling the task complete.
- Run the relevant pressure scenario when the change can affect sustained load, repeated interaction cost, or scale-sensitive behavior.
- Report the scenario, duration, sampling method, and baseline comparison.
- Preserve each pressure attempt's raw samples, aggregate summary, runner logs, child-wrapper output roots, and top-level status in its own evidence directory.
- Keep audit build roots, evidence directories, and private manifests inside the current project under the Git-ignored `./.build-local/` tree.
- Persist each location as `{resource_boundary: repository_root, relative_path_intent: <relative-path>}` and resolve it against the current repository root at the resource-owning boundary immediately before invocation.
- Use the nearest same-machine baseline from `docs/DEVELOPMENT.md`, `docs/TEST_COVERAGE_CHECKLIST.md`, or a previous named `.build-local` result when available.
- If no comparable baseline exists, record the run as a new local baseline and state that it is not a regression comparison.
- Treat unexplained CPU regressions or warm-state RSS growth as blockers.

## When Pressure Testing Is Required

Run pressure validation before submission if the change touches any of these categories:

- High-frequency interaction paths that run on repeated input or navigation.
  Examples: search keystrokes, panel-result movement, tab switching, repeated panel presentation, and active-Space interruption handling.
- Costs that grow with app count, window count, result count, or preview count.
  Examples: search indexing, candidate filtering, ranking, runtime snapshot assembly, window deduplication, and preview-list generation.
- Long-lived resources or repeated asynchronous work.
  Examples: caches, debounce windows, background `Task` chains, timers, observers, preview pipelines, screen-capture polling, and accessibility scans.
- Heavy SwiftUI or AppKit surfaces that are shown repeatedly or kept alive.
  Examples: Home, Logs, Settings, switcher-panel content, search-result lists, and preview surfaces.
- Runtime-topology paths that coordinate real apps, windows, Spaces, fullscreen transitions, or cross-Space activation.
  Examples: multi-app workflow startup, Space-aware search activation, fullscreen target activation, and off-Space snapshot recovery.

## Fast Trigger Heuristic

Pressure testing is required when two or more of the following are true:

1. The code runs on every key press, tab switch, search refresh, panel refresh, or active-Space change.
2. The cost can grow with the number of apps, windows, search results, previews, or Spaces.
3. The change alters caching, object lifetime, asynchronous scheduling, or repeated runtime polling.
4. The change increases UI-tree complexity, layout work, cross-process calls, or preview generation.

If one condition is true and the path is already listed as a known hot area in `docs/DEVELOPMENT.md`, pressure testing is still required.

## Choose the Right Pressure Scenario

### Tab-Switch Stress

Use this for:

- Left-side tab-switching changes in Home, Logs, or Settings.
- Page-lifecycle changes such as `onAppear`, `onDisappear`, `@StateObject`, keep-alive, or restoration behavior.
- Changes to heavy page composition or Logs presentation.

Minimum validation:

- Run `./scripts/perf/tab-switch-stress.sh 20 20 0.5 --build-root <project-local-build-root-20ms> --output-dir <attempt-20ms-directory>`.
- Prefer adding the lower-frequency comparison run `./scripts/perf/tab-switch-stress.sh 20 50 0.5 --build-root <project-local-build-root-50ms> --output-dir <attempt-50ms-directory>`.
- Use a distinct, not-yet-existing attempt directory for every run. The script atomically creates the leaf and preserves `samples.csv`, `summary.txt`, `build.log`, `app.log`, and `status.json`.
- Continue to support non-audit calls that use positional arguments only; they receive a unique output directory under `./.build-local/tab-switch-stress/`.
- Record CPU and RSS `avg/p95/max`. Keep the pressure result non-green when the pressure process exits nonzero, sampling fails, samples are missing, or evidence cannot be written.

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

Every required pressure run must report:

- The pressure scenario used.
- Why the scenario matches the changed code path.
- Duration, sample cadence, and dataset or topology size.
- CPU and RSS `avg/p95/max`, including throughput when relevant.
- A comparison with the previous same-machine baseline or nearest known-good run when comparable data exists.
- The project-local evidence-directory intent, including retained samples, summary, aggregate logs, child-wrapper output roots, and top-level `status.json`; use a redacted archive token in audit reports and retain the resolved local paths in the private manifest.
- Whether the result is a regression comparison or a newly recorded local baseline.
- Whether any observed regression is expected, explained, and accepted.

## Rejection Criteria

- Reject a change to a known hot path when pressure validation was skipped without a concrete reason.
- Reject unexplained sustained CPU regression.
- Reject an RSS curve that continues growing after warm-up without an explanation.
- Reject toy-scale pressure results when the production risk is scale-sensitive.
- Reject validation that relies only on unit, behavior, or UI correctness when the change directly affects sustained-load behavior.
