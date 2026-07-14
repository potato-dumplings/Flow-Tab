# Performance Pressure Workflow

Use this reference when deciding whether a change requires pressure testing, which pressure path to run, and what evidence must be reported.

Pressure testing is required when the risk concerns sustained CPU, RSS growth, latency, throughput, or scale behavior. For hot paths and scale-sensitive code, pressure testing is a validation layer alongside unit, behavior, and UI validation.

## Contents

- [Required Outcome](#required-outcome)
- [Requiredness Resolution Order](#requiredness-resolution-order)
- [Hard Triggers](#hard-triggers)
- [Known-Hot And Scoring Triggers](#known-hot-and-scoring-triggers)
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

## Requiredness Resolution Order

Resolve Pressure Requiredness in this order:

1. Hard trigger: any hard-trigger category makes pressure validation required.
2. Known-hot trigger: when no hard trigger applies, a path listed as a known hot area plus at least one scoring condition makes pressure validation required.
3. Scoring trigger: when neither prior trigger applies, at least two scoring conditions make pressure validation required.
4. Otherwise mark Pressure `not relevant` and state which trigger conditions were absent.

Stop at the first matching rule.

## Hard Triggers

Run pressure validation before completion if the change touches any of these categories:

- Search matching, tokenization, indexing, candidate selection, ranking, caching, debounce, scheduling, or result-publication paths used by the switcher.
- Home, Logs, Settings, or switcher page-lifecycle and repeated-presentation paths covered by the tab-switch pressure scenario.
- Runtime snapshot, window mapping, grouping, deduplication, active-Space recovery, fullscreen/off-Space activation, or other paths covered by the runtime-topology pressure scenario.
- Ownership or cadence changes to long-lived screen-capture polling, accessibility scans, preview pipelines, observers, timers, repeated `Task` chains, or runtime caches.
- A path with an explicit performance acceptance criterion, a known prior performance regression, or a required pressure scenario recorded in the stable product contract.

## Known-Hot And Scoring Triggers

When no hard trigger applies, score these conditions:

1. The code runs on every key press, tab switch, search refresh, panel refresh, or active-Space change.
2. The cost can grow with the number of apps, windows, search results, previews, or Spaces.
3. The change alters caching, object lifetime, asynchronous scheduling, or repeated runtime polling.
4. The change increases UI-tree complexity, layout work, cross-process calls, or preview generation.

One condition plus a path already listed as a known hot area in `docs/DEVELOPMENT.md` satisfies the known-hot trigger. Two or more conditions satisfy the scoring trigger.

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

- `SwitcherSearchCoordinator` matching, tokenization, caching, candidate selection, or ranking changes.
- Search debounce, asynchronous scheduling, result-rebuild cadence, or state-publication changes.
- Any code that can materially affect search-path CPU, memory, or throughput.

Minimum validation:

- For the process-level committed-index CPU/RSS path, run separate `realistic` and `stress` attempts with `./scripts/perf/search-committed-index-pressure.sh 0.5 --scenario <realistic|stress> --scenario-duration-seconds 30 --build-root <project-local-build-root> --output-dir <attempt-directory>`.
- Use a dataset of at least `10,000` windows, such as `400 apps x 25 windows`.
- Sample `%CPU` and `RSS` every `0.5s`.
- Run each scenario for at least `30s`.
- Cover both `realistic` and `stress` input rhythms.
- Report `avg/p95/max` and throughput.
- Use a distinct, not-yet-existing output directory. The wrapper preserves `process-samples.csv`, `summary.txt`, aggregate logs, `status.json`, and a unique `attempts/flowtabtests/` child output root for the build and every test batch. Every test batch must retain its own `.xcresult` and child `status.json`.

### Runtime Topology Pressure

Use this for:

- Multi-app workflow startup changes.
- Runtime snapshot, window mapping, grouping, deduplication, or active-Space recovery changes.
- Cross-Space or fullscreen search-and-activate flows.
- Repeated preview, activation, or topology-aware panel behavior changes.

Minimum validation:

- Create an immutable private fixed-app identity manifest with `./scripts/testing/create-ui-app-identity-manifest.sh --app-path <fixed-app> --output-file <project-local-private-manifest>`, then run the representative Noisy Option+Tab path with `./scripts/perf/runtime-topology-pressure.sh 0.5 --ui-app-identity-manifest <project-local-private-manifest> --build-root <project-local-build-root> --output-dir <attempt-directory>`.
- Use a real or fixture-driven multi-app topology so the result includes actual topology evidence.
- Include at least one cross-Space or fullscreen target when the affected path requires it.
- Repeat panel opening, search, selection, and activation across a sustained interaction window.
- Record CPU and RSS behavior during the repeated interaction window and compare it with the nearest known baseline.
- Use a distinct, not-yet-existing output directory. The wrapper preserves `flowtab-samples.csv`, `summary.txt`, aggregate logs, the top-level `status.json`, and the UI wrapper's `.xcresult`, stage logs, and child `status.json` under `attempts/ui-tests/run/`.

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
- Reject a Pressure Requiredness decision that bypasses the hard, known-hot, and scoring resolution order.
- Reject unexplained sustained CPU regression.
- Reject an RSS curve that continues growing after warm-up without an explanation.
- Reject toy-scale pressure results when the production risk is scale-sensitive.
- Reject validation that relies only on unit, behavior, or UI correctness when the change directly affects sustained-load behavior.
