# Test Coverage Matrix

Updated: 2026-04-29

## Purpose

This document gives a product-scenario view of FlowTab test coverage. It complements the existing layer-focused documents:

- [UNIT_AND_BEHAVIOR_TEST_COVERAGE.md](UNIT_AND_BEHAVIOR_TEST_COVERAGE.md)
- [UI_AUTOMATION_TEST_COVERAGE.md](UI_AUTOMATION_TEST_COVERAGE.md)
- [TEST_COVERAGE_CHECKLIST.md](TEST_COVERAGE_CHECKLIST.md)
- [SPACE_FIXTURE_APP_WORKFLOW.md](SPACE_FIXTURE_APP_WORKFLOW.md)

Use this matrix when deciding whether a feature has enough automated evidence across unit, behavior/integration, and UI/end-to-end layers.

## Status Legend

- `Strong`: the layer has direct automated coverage for the scenario.
- `Partial`: the layer has related automated coverage, but it does not prove the full user-visible or runtime outcome.
- `Not relevant`: the layer does not naturally apply to this scenario.
- `Gap`: the scenario still needs coverage in this layer.

## Coverage Matrix

| Product scenario | Unit coverage | Behavior / integration coverage | UI / E2E automation | Pressure / real topology | Main remaining gap |
| --- | --- | --- | --- | --- | --- |
| Core grouping and switcher session state | Strong: grouping, selection, window-layer entry, commit, remembered-window, edge guards | Partial: higher-level session orchestration is covered through `LiveSwitcherModel` and panel behavior | Partial: switcher UI paths exercise selected session outcomes | Not relevant unless a change touches hot paths | No major known gap for pure session rules; keep new rules at unit level first. |
| Hotkey configuration normalization | Strong: main hotkey, quit key fallback, in-app conflict fallback, notification payload, derived Carbon fields, and supported key/modifier matrix axes | Strong: AppDelegate reload, monitor recreation, callback routing, conflict skip | Partial: Settings UI small matrix covers option/control/command main triggers, explicit/fallback quit, and explicit/fallback In-App triggers | Not relevant | UI/E2E intentionally uses a representative matrix rather than exhaustive every-key combinations; Command-Tab takeover remains separate. |
| Global hotkey monitor lifecycle | Partial: configuration-derived fields are unit-tested | Strong: Carbon event parsing, press/release callback routing, registration fallback, unregister-on-stop | Partial: Settings UI triggers representative main shortcuts: `Option + Space`, Control + Grave, and `Command + B` | Not relevant | Full lifecycle cleanup and registration fallback remain behavior-level assertions rather than repeated through UI automation. |
| In-app window hotkey | Strong: preference resolution and conflict avoidance | Strong: AppDelegate registration/conflict handling and focused-window session release-to-commit | Partial: Settings UI triggers explicit `Option + B` and conflict-fallback `Control + B` focused-current-app sessions | Not relevant | Real focused-app topology remains separate; UI coverage proves the configurable shortcut path with mock-current-app evidence. |
| Command-Tab takeover | Not relevant for most pure logic beyond helper resolution | Strong: takeover success/failure, abnormal-exit recovery, restore-on-terminate | Gap: no stable system-level Command-Tab takeover E2E automation | Not relevant | System shortcut takeover remains behavior-tested, not proven through a full real keyboard takeover UI workflow. |
| Settings: appearance | Strong: theme/language preference resolution and app strings | Partial: app content can build with persisted preferences | Partial: toggles and theme/language persistence are UI-tested | Not relevant | Visible theme/language effect is not directly asserted after changing Settings. |
| Settings: window behavior | Strong: auto-enter delay normalization, window behavior preference defaults | Strong: delayed auto-enter uses configured delay and switcher behavior toggles are covered below the UI layer | Strong: Settings values persist across relaunch, and `testSettingsWindowBehaviorHideMinimizedAppsAffectsSwitcherAppLayer` proves the hide-minimized setting changes switcher app-layer output | Not relevant for the hide-minimized UI coverage; run pressure only when changing switcher timing, filtering cost, or repeated runtime paths | Auto-enter timing and restore-minimized variants remain behavior-tested; add representative UI cases only if those user paths regress or become higher risk. |
| Settings: search | Strong: search preference normalization and search matching rules | Strong: search coordinator, query editing, scope routing, result application | Partial: search disabled blocks launch-time auto-search; default scope control persists and switches | Strong for search pressure scenarios | Default scope UI coverage should prove the setting changes actual search-result scope, not only persisted control state. |
| Settings: permission controls | Strong: permission copy/state helpers and launch override parsing | Strong: prompt gating and launch behavior | Strong for banner visibility, Settings routing, reminder persistence, and disabled in-app controls | Not relevant | External System Settings outcomes are intentionally not asserted; only app-owned entry points are automated. |
| Home app and window list | Partial: runtime snapshot assembly and filtering helpers | Strong: runtime snapshot/provider behavior and activation helpers | Strong for mock Home selection; Partial for real multi-app workflow Home coverage | Partial: real fixture workflow covers multi-app counts and window list isolation | Missing real E2E proof that clicking a Home window row activates the intended fixture window. |
| Logs and diagnostics | Strong: log level ordering, preference normalization, diagnostics filtering | Strong: runtime log write/read/since/clear behavior and noisy-category filtering | Strong for seeded logs, level visibility, clear behavior; Partial for open-directory button | Not relevant | Finder/open-directory side effect is intentionally not asserted; only the visible entry point is automated. |
| Switcher standard panel flow | Strong: `SwitcherSession` navigation and commit rules | Strong: panel controller routing, global hotkey flow, interruptions, occlusion, active-space handling | Strong for mock panel entry/exit; Partial for real fixture app strip and preview isolation | Partial: tab-switch stress covers repeated switching | More real multi-app switcher scenarios should move from mock runtime to fixture workflow where system topology matters. |
| Search panel and result activation | Strong: matching, tokenization, pinyin, cursor editing, ranking-related behavior | Strong: search coordinator, search-mode routing, selected-result application | Strong for mock app search; Strong for real workflow window-scope activation paths already connected | Strong: search performance and pressure baselines exist | Remaining real workflow gaps include app-scope search activation, duplicate titles, identical windows, non-ASCII titles, and long-title AX paths. |
| Terminate selected app | Partial: key configuration is unit-tested | Strong: terminate flow keeps app until exit, polling timeout, workspace termination refresh, panel quit shortcut routing | Partial: Settings UI changes explicit `Option + Z` and fallback `Option + W` quit shortcuts, then removes a selected mock app after simulated terminate refresh | Not relevant | UI automation proves configured shortcut-to-refresh routes with mock runtime; real process termination remains behavior-tested. |
| Runtime snapshot, AX/CG mapping, and window records | Strong for deterministic helper rules where extracted | Strong: assembly, filtering, CG/AX binding, sticky binding, title fallback, ambiguous matching, private bridge fallback | Partial: real fixture workflow proves selected Home/Switcher/search runtime paths | Partial: real multi-app fixture topology is partly connected | Full multi-app workflow coverage is still incremental; complex duplicate and pathological title/window cases remain below E2E. |
| Runtime activation and recovery | Partial: deterministic target/fallback helpers | Strong: app activation, window activation, minimized restore, missing-window fallback, recovery retries | Partial: real window-scope search activation is covered; Home row activation is not | Partial when real fixture workflows are used | Need more real end-to-end activation assertions outside the search flow. |
| Window previews and icons | Strong: preview sizing, cache, title-bar style, icon cache | Strong: preview cache reuse and provider behavior | Partial: switcher preview isolation exists in real workflow UI | Not relevant unless preview generation changes cost | Pixel-level preview correctness is not broadly asserted; current UI proof relies on accessibility anchors and isolation. |
| App launch, lifecycle, and status item | Partial: launch-option parsing, content construction, permission override parsing | Strong: AppDelegate launch/teardown, observer cleanup, stress runner startup, status-item open behavior | Strong for launch smoke/performance and tab navigation; Partial for status-item workflows | Partial: launch performance is measured | Status-item behavior is mostly behavior-tested, not driven through a full UI menu workflow. |
| Space fixture workflow infrastructure | Strong: fixture configuration parsing and window planning | Strong: fixture window coordinator and resolved workflow logic | Strong for fixture app UI; Partial for FlowTab real multi-app consumption | Strong where real workflow tests are selected | A unified multi-app launcher and broader FlowTab real workflow suite are still pending. |
| Performance and pressure gates | Strong for search pressure helper scenarios | Partial: app stress runner startup is covered | Strong for UI tab-switch stress measurement | Strong for search external sampling and tab-switch UI metrics | Keep baselines current when search, repeated switching, preview capture, or runtime sampling changes. |

## Current High-Value Gaps

1. `P0` Settings search default scope E2E: change default scope to `window`, open search from the user path, and assert window results are shown by default.
2. `P1` Appearance E2E: change theme or language and assert visible UI output changes after the setting is applied.
3. `P1` Real workflow activation: click a Home window row backed by a fixture app and assert the exact fixture window becomes frontmost.
4. `P1` Real workflow app search: search for a real fixture app in app scope and assert the target fixture app becomes frontmost.
5. `P2` Real workflow edge cases: duplicate titles, visually identical windows, non-ASCII titles, punctuation, whitespace, and long titles through the AX/runtime path.

## Maintenance Rules

- Update this file when adding a feature, fixing a user-visible bug, or changing the meaning of an existing test.
- Keep detailed per-test scenario text in the layer-specific coverage documents; keep this file focused on cross-layer coverage and gaps.
- Do not mark UI/E2E as `Strong` when the test only proves a setting value persisted. Mark it `Partial` until the changed setting is proven through the resulting user-visible behavior.
- Do not use this matrix to skip required FlowTab layers. Use `skills/flowtab-engineering/references/risk-calibration.md` for layer relevance decisions.
