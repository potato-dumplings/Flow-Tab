# Appearance Typography Migration

> Status: active migration backlog
>
> Canonical contract: [`appearance-typography.md`](../.agents/skills/flowtab-engineering/references/appearance-typography.md)
>
> Machine baseline: [`typography-audit-allowlist.json`](../.agents/skills/flowtab-engineering/references/typography-audit-allowlist.json)

## Contents

- [Purpose](#purpose)
- [Completed Foundation](#completed-foundation)
- [Planned Named APIs](#planned-named-apis)
- [Legacy Maintenance Rules](#legacy-maintenance-rules)
- [Current Legacy Inventory](#current-legacy-inventory)
- [Migration Workflow](#migration-workflow)
- [Validation](#validation)

## Purpose

This document owns the current typography migration backlog. It records planned named APIs,
legacy ownership and removal conditions. The active production rules, token table, audit
contract and validation routing remain in `appearance-typography.md`.

The machine baseline owns exact file-and-constructor counts. This document intentionally avoids
source line numbers so ordinary source movement does not invalidate the migration contract.

## Completed Foundation

- `FlowTab/Infrastructure/Appearance/FlowTypography.swift` owns the shared token table.
- `FlowTypography.swiftUI(_:)` and `FlowTypography.appKit(_:)` derive from one private spec.
- Core Settings page, card and control primitives consume `FlowTypography` tokens.
- `AppKitSettingsCardBaseView.makeBodyLabel(_:)` and `makeStatusLabel(_:)` accept semantic tokens.

## Planned Named APIs

These names are migration destinations. Introduce them only when migrating their complete role;
do not treat them as currently implemented APIs.

### Switcher Text Roles

- `FlowSwitcherTypography.searchInputSwiftUI`
- `FlowSwitcherTypography.searchInputAppKit`
- `FlowSwitcherTypography.highlightedTitleSwiftUI`
- `FlowSwitcherTypography.highlightedTitleAppKit`

Switcher highlighted-title measurement must use the same AppKit font returned by
`FlowSwitcherTypography.highlightedTitleAppKit`.

### Runtime Preview Typography

Place `TerminalPreviewTypography` beside `TerminalWindowPreviewProvider` and expose
`terminalFont(for:)`. Keep terminal font-name resolution, descriptor scaling, fallback creation
and the `9...18` display-size clamp inside that named owner.

### Switcher Visual Fonts

- `FlowSwitcherVisual.emptyStateIconSwiftUIFont`
- `FlowSwitcherVisual.previewFallbackSymbolSwiftUIFont`
- `FlowSwitcherVisual.overlayMarkerSwiftUIFont`

These APIs own SF Symbol, fallback glyph and diagnostic marker metrics. They do not define text
typography roles.

## Legacy Maintenance Rules

The allowlist classifies every detected constructor as one of:

- `canonical-source`: implementation inside `FlowTypography`.
- `named-exception`: an implemented, role-owned exception.
- `testing-diagnostic`: visible test or diagnostic typography with an explicit owner.
- `legacy`: a remaining migration item.

Apply these rules to every migration:

1. Keep each file-and-constructor count equal to or below its pre-change `legacy` count.
2. Remove the allowlist entry when the count reaches zero.
3. Reclassify an entry only after the named owner exists and owns the complete role.
4. Update the human inventory when ownership, target or removal conditions change.
5. Keep new production font construction inside `FlowTypography` or an audited named exception.

## Current Legacy Inventory

| File | Current role or value | Target | Removal condition |
| --- | --- | --- | --- |
| `FlowTab/App/ContentView.swift` | `28 semibold rounded`, `13 regular` | `.display`, `.body` | Replace placeholder fonts with `FlowTypography.swiftUI`. |
| `FlowTab/App/HomeRootView.swift` | `20 semibold`, `17 medium`, `15 medium` | Sidebar roles, `.cardTitle` | Name sidebar typography/visual roles and map canonical text. |
| `FlowTab/TestingSupport/FlowTabUITestBootstrapper.swift` | `13 semibold` diagnostic text | Testing diagnostic typography | Introduce the testing-owned font API or use an existing token. |
| `FlowTab/Features/Logs/AppLogsView.swift` | Page header | `.pageTitle`, `.pageSubtitle` | Replace the header fonts with tokens. |
| `FlowTab/Features/Logs/RuntimeLogsSection.swift` | Log controls and monospaced rows | `.body`, `.metadataMonospaced` | Replace every remaining raw log font. |
| `FlowTab/Features/SharedUI/HomeChrome.swift` | Shared card and action chrome | `.cardTitle`, `.cardSubtitle`, `.bodyStrong` | Route shared chrome through tokens. |
| `FlowTab/Features/Home/HomeLayerRowView.swift` | Row title, badge and metadata | Form, micro and metadata tokens | Replace the complete row typography role set. |
| `FlowTab/Features/Home/HomeWindowRowButton.swift` | AppKit row labels | Form, card and body tokens | Route all row labels through `FlowTypography.appKit`. |
| `FlowTab/Features/Home/HomeLandingView.swift` | Page title and action text | Page, control and body tokens | Replace all Home landing raw fonts while preserving intended values. |
| `FlowTab/Features/Home/HomeOverviewComponents.swift` | Stats and summary labels | Canonical tokens plus Home stat-value role | Classify the stat value and migrate the remaining canonical roles. |
| `FlowTab/Features/Settings/AppVisibilityManagerView.swift` | Mixed Settings subpage typography | Canonical tokens or App Visibility roles | Classify every role and eliminate raw constructors. |
| `FlowTab/Features/Switcher/SwitcherPanelSearchBridge.swift` | Search input | `FlowSwitcherTypography.searchInputAppKit` | Move AppKit search typography into the named owner. |
| `FlowTab/Features/Switcher/SwitcherPanelSearchViews.swift` | Search rows, highlighted title and symbols | Switcher typography/visual APIs and canonical tokens | Introduce the complete role APIs and use them for rendering and measurement. |
| `FlowTab/Features/Switcher/SwitcherPanelPreviewViews.swift` | Preview text, symbols and fallback glyphs | Canonical tokens and named visual roles | Separate text tokens from visual/icon metrics. |
| `FlowTab/Features/Switcher/SwitcherPanelOverlayView.swift` | Diagnostic overlay marker | `FlowSwitcherVisual.overlayMarkerSwiftUIFont` | Move the marker metric into the named visual owner. |
| `FlowTab/Infrastructure/Runtime/TerminalWindowPreviewProvider.swift` | Dynamic terminal font creation and scaling | `TerminalPreviewTypography.terminalFont(for:)` | Move every detected terminal font constructor into the named runtime owner. |

## Migration Workflow

1. Read the canonical contract and this backlog before editing a legacy path.
2. Run the typography audit and retain its pre-change result.
3. Select one complete semantic role or one shared owner; preserve visual values unless the task
   explicitly changes appearance.
4. Replace the raw constructors and reduce or reclassify the corresponding allowlist entries.
5. Run the typography audit again, then execute the risk-required validation layers.
6. Update this inventory when the target or removal condition changes.

Canonical audit command:

```bash
python3 .agents/skills/flowtab-engineering/scripts/typography_audit.py \
  --repository-root .
```

## Validation

Choose required runtime layers through
[`risk-calibration.md`](../.agents/skills/flowtab-engineering/references/risk-calibration.md)
and concrete commands through
[`validation-command-cookbook.md`](../.agents/skills/flowtab-engineering/references/validation-command-cookbook.md).
Always run the typography audit after changing production fonts, the detector or the allowlist.
