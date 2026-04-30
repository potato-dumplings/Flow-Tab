# Test Coverage Matrix

Updated: 2026-04-30

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
| Settings: appearance | Strong: theme/language preference resolution and app strings | Partial: app content can build with persisted preferences | Strong: toggles and theme/language persistence are UI-tested; `testSettingsAppearanceThemeAndLanguageUpdateVisibleUI` proves visible theme luminance and English copy refresh after changing Settings | Not relevant | No major known UI/E2E gap; keep behavior coverage at construction/orchestration level when appearance wiring changes. |
| Settings: window behavior | Strong: auto-enter delay normalization, window behavior preference defaults | Strong: delayed auto-enter uses configured delay and switcher behavior toggles are covered below the UI layer | Strong: Settings values persist across relaunch, and `testSettingsWindowBehaviorHideMinimizedAppsAffectsSwitcherAppLayer` proves the hide-minimized setting changes switcher app-layer output | Not relevant for the hide-minimized UI coverage; run pressure only when changing switcher timing, filtering cost, or repeated runtime paths | Auto-enter timing and restore-minimized variants remain behavior-tested; add representative UI cases only if those user paths regress or become higher risk. |
| Settings: search | Strong: search preference normalization and search matching rules | Strong: search coordinator, query editing, scope routing, result application | Strong: search disabled blocks launch-time auto-search; default scope control persists and switches; default window and restored app scopes now open matching results through the user path | Strong for search pressure scenarios | No major known Settings search UI/E2E gap; keep new search settings changes tied to visible runtime behavior, not only control persistence. |
| Settings: permission controls | Strong: permission copy/state helpers and launch override parsing | Strong: prompt gating and launch behavior | Strong for banner visibility, Settings routing, reminder persistence, and disabled in-app controls | Not relevant | External System Settings outcomes are intentionally not asserted; only app-owned entry points are automated. |
| Home app and window list | Strong: runtime snapshot assembly, filtering helpers, and Home window activation target resolution | Strong: runtime snapshot/provider behavior and Home activation dispatch with scoped contexts | Strong: mock Home selection, real multi-app Home counts, per-app window isolation, and real Home window-row activation are automated | Strong: real fixture workflow covers multi-app counts, window list isolation, fullscreen-only handling, and exact window activation | No major known Home workflow gap; keep new Home runtime behavior tied to fixture UI proof where system topology matters. |
| Logs and diagnostics | Strong: log level ordering, preference normalization, diagnostics filtering | Strong: runtime log write/read/since/clear behavior and noisy-category filtering | Strong for seeded logs, level visibility, clear behavior; Partial for open-directory button | Not relevant | Finder/open-directory side effect is intentionally not asserted; only the visible entry point is automated. |
| Switcher standard panel flow | Strong: `SwitcherSession` navigation and commit rules | Strong: panel controller routing, global hotkey flow, interruptions, occlusion, active-space handling | Strong for mock panel entry/exit; Partial for real fixture app strip, preview isolation, and duplicate-title preview anchors | Partial: tab-switch stress covers repeated switching | More real multi-app switcher scenarios should move from mock runtime to fixture workflow where system topology matters. |
| Search panel and result activation | Strong: matching, tokenization, pinyin, cursor editing, ranking-related behavior | Strong: search coordinator, search-mode routing, selected-result application | Strong for mock app search; Strong for real workflow app-scope, window-scope activation, duplicate-title, identical-window, and edge-title paths | Strong: search performance and pressure baselines exist | No major known search UI/E2E gap for stable fixture inputs; keep lifecycle refresh and system shortcut paths tracked separately. |
| Terminate selected app | Partial: key configuration is unit-tested | Strong: terminate flow keeps app until exit, polling timeout, workspace termination refresh, panel quit shortcut routing | Partial: Settings UI changes explicit `Option + Z` and fallback `Option + W` quit shortcuts, then removes a selected mock app after simulated terminate refresh | Not relevant | UI automation proves configured shortcut-to-refresh routes with mock runtime; real process termination remains behavior-tested. |
| Runtime snapshot, AX/CG mapping, and window records | Strong for deterministic helper rules where extracted | Strong: assembly, filtering, CG/AX binding, sticky binding, title fallback, ambiguous matching, private bridge fallback | Partial: real fixture workflow proves selected Home/Switcher/search runtime paths plus duplicate-title, identical-window, and edge-title AX inputs | Partial: real multi-app fixture topology is partly connected | Full multi-app workflow coverage is still incremental; running app/window lifecycle refresh remains a separate real-topology gap. |
| Runtime activation and recovery | Partial: deterministic target/fallback helpers | Strong: app activation, window activation, minimized restore, missing-window fallback, recovery retries | Strong: real app-scope search activation, real window-scope search activation, real edge-title search activation, and real Home window-row activation are covered | Partial when real fixture workflows are used | Representative real activation paths are covered; real process termination remains behavior-tested rather than fixture-process UI-tested. |
| Window previews and icons | Strong: preview sizing, cache, title-bar style, icon cache | Strong: preview cache reuse and provider behavior | Partial: switcher preview isolation and duplicate same-title window anchors exist in real workflow UI | Not relevant unless preview generation changes cost | Pixel-level preview correctness is not broadly asserted; current UI proof relies on accessibility anchors and isolation. |
| App launch, lifecycle, and status item | Partial: launch-option parsing, content construction, permission override parsing | Strong: AppDelegate launch/teardown, observer cleanup, stress runner startup, status-item open behavior | Strong for launch smoke/performance and tab navigation; Partial for status-item workflows | Partial: launch performance is measured | Status-item behavior is mostly behavior-tested, not driven through a full UI menu workflow. |
| Space fixture workflow infrastructure | Strong: fixture configuration parsing and window planning | Strong: fixture window coordinator and resolved workflow logic | Strong for fixture app UI; Partial for FlowTab real multi-app consumption | Strong where real workflow tests are selected | A unified multi-app launcher and broader FlowTab real workflow suite are still pending. |
| Performance and pressure gates | Strong for search pressure helper scenarios | Partial: app stress runner startup is covered | Strong for UI tab-switch stress measurement | Strong for search external sampling and tab-switch UI metrics | Keep baselines current when search, repeated switching, preview capture, or runtime sampling changes. |

## Current High-Value Gaps

1. `P2` Command-Tab takeover still lacks stable system-level UI automation.
2. `P2` Terminate selected app still lacks a full real-process UI shortcut workflow.

## Maintenance Rules

- Update this file when adding a feature, fixing a user-visible bug, or changing the meaning of an existing test.
- Keep detailed per-test scenario text in the layer-specific coverage documents; keep this file focused on cross-layer coverage and gaps.
- Do not mark UI/E2E as `Strong` when the test only proves a setting value persisted. Mark it `Partial` until the changed setting is proven through the resulting user-visible behavior.
- Do not use this matrix to skip required FlowTab layers. Use `skills/flowtab-engineering/references/risk-calibration.md` for layer relevance decisions.
