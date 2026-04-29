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
| Hotkey configuration normalization | Strong: main hotkey, quit key fallback, in-app hotkey conflict fallback, derived Carbon fields | Strong: AppDelegate reload, monitor recreation, callback routing, conflict skip | Partial: Settings changes one main shortcut and verifies one real trigger path | Not relevant | Missing systematic setting-to-effective-hotkey E2E coverage for every configurable main key/modifier, quit key, and in-app key path. |
| Global hotkey monitor lifecycle | Partial: configuration-derived fields are unit-tested | Strong: Carbon event parsing, press/release callback routing, registration fallback, unregister-on-stop | Partial: one Settings UI test triggers `Option + Space` after changing settings | Not relevant | Real UI automation does not exhaustively prove each registered shortcut fires after user changes it. |
| In-app window hotkey | Strong: preference resolution and conflict avoidance | Strong: AppDelegate registration/conflict handling and focused-window session release-to-commit | Partial: Settings disables controls without Accessibility permission; no full changed-shortcut trigger path | Not relevant | Missing UI/E2E path: change in-app shortcut in Settings, press that shortcut, verify focused-window session starts and commits. |
| Command-Tab takeover | Not relevant for most pure logic beyond helper resolution | Strong: takeover success/failure, abnormal-exit recovery, restore-on-terminate | Gap: no stable system-level Command-Tab takeover E2E automation | Not relevant | System shortcut takeover remains behavior-tested, not proven through a full real keyboard takeover UI workflow. |
| Settings: appearance | Strong: theme/language preference resolution and app strings | Partial: app content can build with persisted preferences | Partial: toggles and theme/language persistence are UI-tested | Not relevant | Visible theme/language effect is not directly asserted after changing Settings. |
| Settings: window behavior | Strong: auto-enter delay normalization, window behavior preference defaults | Strong: delayed auto-enter uses configured delay and switcher behavior toggles are covered below the UI layer | Partial: Settings values persist across relaunch | Partial if changes affect switcher timing paths | Missing Settings-to-runtime E2E proof that changed delay/toggles alter actual switcher behavior from the user path. |
| Settings: search | Strong: search preference normalization and search matching rules | Strong: search coordinator, query editing, scope routing, result application | Partial: search disabled blocks launch-time auto-search; default scope control persists and switches | Strong for search pressure scenarios | Default scope UI coverage should prove the setting changes actual search-result scope, not only persisted control state. |
| Settings: permission controls | Strong: permission copy/state helpers and launch override parsing | Strong: prompt gating and launch behavior | Strong for banner visibility, Settings routing, reminder persistence, and disabled in-app controls | Not relevant | External System Settings outcomes are intentionally not asserted; only app-owned entry points are automated. |
| Home app and window list | Partial: runtime snapshot assembly and filtering helpers | Strong: runtime snapshot/provider behavior and activation helpers | Strong for mock Home selection; Partial for real multi-app workflow Home coverage | Partial: real fixture workflow covers multi-app counts and window list isolation | Missing real E2E proof that clicking a Home window row activates the intended fixture window. |
| Logs and diagnostics | Strong: log level ordering, preference normalization, diagnostics filtering | Strong: runtime log write/read/since/clear behavior and noisy-category filtering | Strong for seeded logs, level visibility, clear behavior; Partial for open-directory button | Not relevant | Finder/open-directory side effect is intentionally not asserted; only the visible entry point is automated. |
| Switcher standard panel flow | Strong: `SwitcherSession` navigation and commit rules | Strong: panel controller routing, global hotkey flow, interruptions, occlusion, active-space handling | Strong for mock panel entry/exit; Partial for real fixture app strip and preview isolation | Partial: tab-switch stress covers repeated switching | More real multi-app switcher scenarios should move from mock runtime to fixture workflow where system topology matters. |
| Search panel and result activation | Strong: matching, tokenization, pinyin, cursor editing, ranking-related behavior | Strong: search coordinator, search-mode routing, selected-result application | Strong for mock app search; Strong for real workflow window-scope activation paths already connected | Strong: search performance and pressure baselines exist | Remaining real workflow gaps include app-scope search activation, duplicate titles, identical windows, non-ASCII titles, and long-title AX paths. |
| Terminate selected app | Partial: key configuration is unit-tested | Strong: terminate flow keeps app until exit, polling timeout, workspace termination refresh, panel quit shortcut routing | Gap: no full UI/E2E quit-shortcut user path | Not relevant | Add UI/E2E only if this becomes a critical user regression path; behavior coverage currently carries the risk. |
| Runtime snapshot, AX/CG mapping, and window records | Strong for deterministic helper rules where extracted | Strong: assembly, filtering, CG/AX binding, sticky binding, title fallback, ambiguous matching, private bridge fallback | Partial: real fixture workflow proves selected Home/Switcher/search runtime paths | Partial: real multi-app fixture topology is partly connected | Full multi-app workflow coverage is still incremental; complex duplicate and pathological title/window cases remain below E2E. |
| Runtime activation and recovery | Partial: deterministic target/fallback helpers | Strong: app activation, window activation, minimized restore, missing-window fallback, recovery retries | Partial: real window-scope search activation is covered; Home row activation is not | Partial when real fixture workflows are used | Need more real end-to-end activation assertions outside the search flow. |
| Window previews and icons | Strong: preview sizing, cache, title-bar style, icon cache | Strong: preview cache reuse and provider behavior | Partial: switcher preview isolation exists in real workflow UI | Not relevant unless preview generation changes cost | Pixel-level preview correctness is not broadly asserted; current UI proof relies on accessibility anchors and isolation. |
| App launch, lifecycle, and status item | Partial: launch-option parsing, content construction, permission override parsing | Strong: AppDelegate launch/teardown, observer cleanup, stress runner startup, status-item open behavior | Strong for launch smoke/performance and tab navigation; Partial for status-item workflows | Partial: launch performance is measured | Status-item behavior is mostly behavior-tested, not driven through a full UI menu workflow. |
| Space fixture workflow infrastructure | Strong: fixture configuration parsing and window planning | Strong: fixture window coordinator and resolved workflow logic | Strong for fixture app UI; Partial for FlowTab real multi-app consumption | Strong where real workflow tests are selected | A unified multi-app launcher and broader FlowTab real workflow suite are still pending. |
| Performance and pressure gates | Strong for search pressure helper scenarios | Partial: app stress runner startup is covered | Strong for UI tab-switch stress measurement | Strong for search external sampling and tab-switch UI metrics | Keep baselines current when search, repeated switching, preview capture, or runtime sampling changes. |

## Current High-Value Gaps

1. `P0` Settings hotkey E2E: after changing each supported main shortcut option, press the new shortcut and verify the switcher opens or advances as expected.
2. `P0` Settings hotkey E2E: after changing quit and in-app shortcuts, prove the new shortcuts affect the actual panel or focused-window session behavior.
3. `P0` Settings search default scope E2E: change default scope to `window`, open search from the user path, and assert window results are shown by default.
4. `P1` Settings window behavior E2E: change auto-enter delay or related toggles and verify the switcher behavior changes through the visible workflow.
5. `P1` Appearance E2E: change theme or language and assert visible UI output changes after the setting is applied.
6. `P1` Real workflow activation: click a Home window row backed by a fixture app and assert the exact fixture window becomes frontmost.
7. `P1` Real workflow app search: search for a real fixture app in app scope and assert the target fixture app becomes frontmost.
8. `P2` Real workflow edge cases: duplicate titles, visually identical windows, non-ASCII titles, punctuation, whitespace, and long titles through the AX/runtime path.

## Maintenance Rules

- Update this file when adding a feature, fixing a user-visible bug, or changing the meaning of an existing test.
- Keep detailed per-test scenario text in the layer-specific coverage documents; keep this file focused on cross-layer coverage and gaps.
- Do not mark UI/E2E as `Strong` when the test only proves a setting value persisted. Mark it `Partial` until the changed setting is proven through the resulting user-visible behavior.
- Do not use this matrix to skip required FlowTab layers. Use `skills/flowtab-engineering/references/risk-calibration.md` for layer relevance decisions.
