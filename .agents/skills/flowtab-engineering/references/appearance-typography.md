# Appearance Typography

> Status: active production contract
>
> Owner: `FlowTab/Infrastructure/Appearance`
>
> Code source of truth: `FlowTab/Infrastructure/Appearance/FlowTypography.swift`
>
> Migration backlog: [`APPEARANCE_TYPOGRAPHY_MIGRATION.md`](../../../../docs/APPEARANCE_TYPOGRAPHY_MIGRATION.md)

## Contents

- [Purpose And Scope](#purpose-and-scope)
- [Ownership And Source Of Truth](#ownership-and-source-of-truth)
- [Canonical Tokens](#canonical-tokens)
- [Token Usage Rules](#token-usage-rules)
- [Named Exceptions](#named-exceptions)
- [Prohibited Font Construction](#prohibited-font-construction)
- [Audit Contract](#audit-contract)
- [Allowlist Rules](#allowlist-rules)
- [Validation Routing](#validation-routing)

## Purpose And Scope

Route every production UI text font through a `FlowTypography` token or an audited named
exception. Apply the same rule to SwiftUI rendering, AppKit rendering and text measurement so
size, weight and design cannot drift between implementations.

SF Symbols, preview glyphs and diagnostic markers use named visual-font APIs. Dynamic runtime
fonts use a named runtime owner. Test-visible diagnostics use a named testing owner or an
explicit audit classification.

Select tokens by semantic role. Equal numeric specs do not make two roles interchangeable.

## Ownership And Source Of Truth

`FlowTypography.swift` owns the canonical `Spec(size, weight, design)` table and exposes:

- `FlowTypography.swiftUI(_:) -> Font`
- `FlowTypography.appKit(_:) -> NSFont`

Maintain one private spec table. Keep `Spec` construction private, map `Weight` and `Design`
inside `FlowTypography`, and derive both framework representations from the same spec.

Use `.standard`, `.rounded` and `.monospaced` as internal design values. Derive AppKit rounded
fonts through the descriptor design and fall back to the standard system font.

Update this document's token table in the same change whenever the code source of truth changes.
Add new Swift files explicitly to the FlowTab target sources because the Xcode project does not
use a file-system-synchronized source group.

## Canonical Tokens

| Token | Spec | Intended use |
| --- | --- | --- |
| `pageTitle` | `22 semibold standard` | Page title |
| `pageSubtitle` | `12 regular standard` | Page subtitle |
| `cardTitle` | `15 semibold standard` | Card or section title |
| `cardSubtitle` | `11 regular standard` | Card subtitle or weak explanation |
| `formLabel` | `13 regular standard` | Form row label |
| `formLabelEmphasized` | `13 medium standard` | Emphasized row or list label |
| `controlText` | `13 regular standard` | Select, dropdown or input text |
| `controlTextEmphasized` | `13 medium standard` | Emphasized compact control text |
| `body` | `12 regular standard` | Body, explanation or detail value |
| `bodyEmphasized` | `12 medium standard` | Segmented or status text |
| `bodyStrong` | `12 semibold standard` | Button or strong status text |
| `micro` | `10 medium standard` | Small badge or count |
| `microEmphasized` | `10 semibold standard` | Emphasized small badge |
| `display` | `28 semibold rounded` | Initial or special display title |
| `metadataMonospaced` | `11 regular monospaced` | Log, path or window metadata |
| `metadataMonospacedEmphasized` | `11 medium monospaced` | Emphasized metadata |
| `bodyMonospaced` | `12 regular monospaced` | Form value or diagnostic body |

## Token Usage Rules

- Choose the token from the rendered text's responsibility, not from the nearest numeric value.
- Keep ordinary action text on `.bodyStrong`; keep compact action/control text on
  `.controlTextEmphasized`.
- Keep segmented and status text on `.bodyEmphasized` when that is the role's intended weight.
- Pass `FlowTypography.Token` through shared helpers instead of passing a raw `fontSize`.
- Use the named `Font` or `NSFont` API for measurement; do not expose raw specs for measuring.
- Use the same named AppKit font for width measurement and AppKit rendering of one text role.

## Named Exceptions

Create a named exception when a complete semantic role cannot use a canonical token because it
depends on runtime font data, owns feature-specific text geometry or represents a visual metric.

Every exception must:

1. Live with the lowest responsible feature, runtime or testing owner.
2. Name the semantic role and framework in its API when the distinction matters.
3. Return `Font` or `NSFont`; do not expose only a size.
4. Own rendering and measurement for that role.
5. Appear in the typography audit allowlist as `named-exception` or `testing-diagnostic`.
6. Document its scope and removal condition in the migration backlog when it replaces legacy.

Keep visual-font APIs separate from text typography. A diagnostic marker or fallback icon font
cannot be reused for body or control text.

## Prohibited Font Construction

Outside `FlowTypography`, an audited named exception or a tracked legacy entry, do not add:

- `.system(size:)` or `Font.system(size:)`
- `systemFont(ofSize:)`
- `monospacedSystemFont(ofSize:)`
- other AppKit `*Font(ofSize:)` factories
- `Font.custom(...)`
- `NSFont(name:size:)`
- `NSFont(descriptor:size:)`
- `font.withSize(...)`

Apply this rule to production UI, visual-font metrics and test-visible diagnostics.

## Audit Contract

Run the canonical audit from the repository root:

```bash
python3 .agents/skills/flowtab-engineering/scripts/typography_audit.py \
  --repository-root .
```

The audit scans `FlowTab/**/*.swift`, detects single-line and multiline font constructors, masks
comments and string contents, and compares file-and-constructor counts against
[`typography-audit-allowlist.json`](typography-audit-allowlist.json).

Use scan mode only for diagnosis or allowlist maintenance:

```bash
python3 .agents/skills/flowtab-engineering/scripts/typography_audit.py \
  --repository-root . \
  --scan
```

An unexpected constructor, missing tracked constructor, count mismatch, invalid path intent or
invalid classification fails the audit.

## Allowlist Rules

The allowlist is the machine-readable current baseline. It stores repository-relative path
intents and resolves them against the explicit `repository_root` supplied to the audit script.

- Keep `canonical-source` entries limited to `FlowTypography` implementation details.
- Add `named-exception` only after the named owner exists and owns the complete role.
- Keep `testing-diagnostic` entries in testing-owned boundaries.
- Treat every `legacy` count as a non-increasing migration ceiling.
- Remove entries whose count reaches zero.
- Update the migration inventory whenever a target or ownership classification changes.
- Review the source diff and allowlist diff together; do not approve an unexplained count swap.

## Validation Routing

Choose required runtime layers through
[`risk-calibration.md`](risk-calibration.md)
and commands through
[`validation-command-cookbook.md`](validation-command-cookbook.md).

- Documentation, skill, detector or allowlist-only changes require Process/Tooling validation;
  Unit, Behavior, UI and Pressure are not relevant when runtime code is unchanged.
- Token additions or value-preserving migrations require the typography audit and the smallest
  build/test layer selected by risk calibration.
- Actual size, weight, design, text measurement, row height or preview-rendering changes are
  user-visible and require the affected UI path.
- Search, preview or other repeatedly rendered paths require Pressure when the performance
  workflow classifies the change as hot or scale-sensitive.
