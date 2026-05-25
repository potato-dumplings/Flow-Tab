# Appearance Typography

## 目标

FlowTab 的生产 UI 字体必须通过统一 token 或命名例外进入。禁止新增裸字号入口，避免字号、weight、design 在 SwiftUI 和 AppKit 两套实现里漂移。

Settings 的 card / page / control primitives 是第一阶段视觉基准源；Settings 现有偏离值不自动合法化。

## FlowTypography

在 `FlowTab/Infrastructure/Appearance/FlowTypography.swift` 建立唯一字体真源。

要求：

- 新增文件必须显式加入 `FlowTab.xcodeproj` 的 FlowTab target sources；本项目不是文件系统同步 source group。
- 内部只维护一份 `Spec(size, weight, design)` 表。
- `Spec` initializer 必须是 `private`。
- 第一阶段不公开 `spec(_:)`。
- `swiftUI(_:)` 和 `appKit(_:)` 都从同一份 spec 派生。
- `Weight` / `Design` 使用 FlowTypography 自己的 enum，再映射到 SwiftUI / AppKit。
- `Design` 使用 `.standard`、`.rounded`、`.monospaced`；文档中的 default system design 对应代码里的 `.standard`。
- AppKit rounded 必须通过 descriptor design 派生，并 fallback 到 standard system font。
- 测量也必须使用命名 font API，不得为了测量重新开放 spec 或自行构造裸 font。

## Canonical Tokens

| Token                          | Spec                    | Intended Use                  |
| ------------------------------ | ----------------------- | ----------------------------- |
| `pageTitle`                    | `22 semibold standard`  | 页面标题                      |
| `pageSubtitle`                 | `12 regular standard`   | 页面副标题                    |
| `cardTitle`                    | `15 semibold standard`  | card / section 标题           |
| `cardSubtitle`                 | `11 regular standard`   | card subtitle、弱说明         |
| `formLabel`                    | `13 regular standard`   | 表单 row label                |
| `formLabelEmphasized`          | `13 medium standard`    | 强调 row/list label           |
| `controlText`                  | `13 regular standard`   | select/dropdown/input 文本    |
| `controlTextEmphasized`        | `13 medium standard`    | compact button 等强调控件文本 |
| `body`                         | `12 regular standard`   | 正文、说明、detail value      |
| `bodyEmphasized`               | `12 medium standard`    | segmented、状态文本           |
| `bodyStrong`                   | `12 semibold standard`  | 按钮、强状态文本              |
| `micro`                        | `10 medium standard`    | 小 badge、小计数              |
| `microEmphasized`              | `10 semibold standard`  | 强调小 badge                  |
| `display`                      | `28 semibold rounded`   | 初始/特殊 display 标题        |
| `metadataMonospaced`           | `11 regular monospaced` | 日志、路径、窗口元信息        |
| `metadataMonospacedEmphasized` | `11 medium monospaced`  | 强调元信息                    |
| `bodyMonospaced`               | `12 regular monospaced` | 表单数值或诊断正文            |

多个 token 可以指向同一个 spec。同值不等于同职责，是否共用 token 看职责，不看数字。

## Settings 迁移规则

第一阶段只接入核心 primitives：

- `FlowSettingsCardView`
- `AppKitSettingsPage`
- `FlowSettingsComponentStyles`
- 基础 control/style helper

迁移必须保持现有视觉：

- `makeBodyLabel()` 当前默认 `11`，映射到 `.cardSubtitle`。
- 原来显式 `12` 的调用点逐个判断，映射到 `.body`、`.bodyEmphasized` 或其他准确 token。
- segmented 必须使用 `.bodyEmphasized = 12 medium`。
- 普通 action button 使用 `.bodyStrong = 12 semibold`；compact action / compact control text 使用 `.controlTextEmphasized = 13 medium`。
- `makeBodyLabel(fontSize:)`、`makeStatusLabel(fontSize:)` 这类 helper 不得继续接收裸 `fontSize`，改为接收 token。

`AppVisibilityManagerView` 等 Settings 子页面中的 `23 / 14 / 12.5 / 10.5 / 9.5` 不自动成为基准；要么迁移到 token，要么命名为例外，要么登记 legacy。

## 命名例外

### 文字角色例外

文字角色例外必须返回 `Font` / `NSFont`，不能只暴露 size。

示例：

- `FlowSwitcherTypography.searchInputSwiftUI`
- `FlowSwitcherTypography.searchInputAppKit`
- `FlowSwitcherTypography.highlightedTitleSwiftUI`
- `FlowSwitcherTypography.highlightedTitleAppKit`

Switcher highlighted title 的宽度测量必须使用 `FlowSwitcherTypography.highlightedTitleAppKit`，不得自行构造测量字体。

### Runtime Preview 例外

`TerminalPreviewTypography` 靠近 `TerminalWindowPreviewProvider` 放置，属于 runtime preview 的命名例外，不进入普通全局 typography token。

示例：

- `TerminalPreviewTypography.terminalFont(for:)`
- 内部封装 `fontSizeRange = 9...18`
- 动态 terminal font 创建只允许出现在这个命名实现内部

### 视觉尺寸例外

视觉尺寸例外不是文本设计 token，只能用于 SF Symbol、preview symbol、diagnostic marker 等视觉元素。

如果只服务 SwiftUI，API 名称和文档必须明确返回 `Font`。如果未来需要 AppKit，拆成 `...SwiftUI` / `...AppKit`，不要使用含混名称。

示例：

- `FlowSwitcherVisual.emptyStateIconSwiftUIFont`
- `FlowSwitcherVisual.previewFallbackSymbolSwiftUIFont`
- `FlowSwitcherVisual.overlayMarkerSwiftUIFont`

`overlayMarkerSwiftUIFont` 是 diagnostic visual font，不是普通设计 token，不得用于正文或控件文本。

## 禁止新增的字体入口

生产 UI 禁止新增：

- `.system(size:)`
- `systemFont(ofSize:)`
- `monospacedSystemFont(ofSize:)`
- `Font.custom(...)`
- `NSFont(name:size:)`
- `font.withSize(...)`

测试/诊断可视内容也必须迁移到 token、命名测试诊断例外，或登记 legacy。

## Audit

主 audit：

```bash
rg "\.system\(\s*size:|systemFont\(\s*ofSize:|monospacedSystemFont\(\s*ofSize:" FlowTab -n
```

旁路补充 audit：

```bash
rg "Font\.custom\(|NSFont\(name:\s*.*size:|\.withSize\(" FlowTab -n
```

第一阶段主 audit 和旁路补充 audit 的所有剩余命中必须落到三类之一：

- token / 命名例外内部实现
- 测试诊断命名例外
- legacy 清单

旁路补充 audit 的目标是除 `FlowTypography` / 命名例外内部实现外为零。第一阶段已有旁路命中只能暂时存在于命名例外内部或 legacy 清单中。

## Legacy 清单规则

legacy 只记录第一阶段 audit 基线。后续 UI 变更不能新增未登记裸入口；修改 legacy 文件时不得增加 legacy 数量，优先减少相关项。

legacy 可以按“同一文件 + 同一职责 + 同一目标 token/exception”分组，但每组必须覆盖 audit 的每一条剩余命中。

字段固定为：

| Field                       | Requirement                                               |
| --------------------------- | --------------------------------------------------------- |
| `file`                      | 文件路径                                                  |
| `current value`             | 当前裸字号或入口                                          |
| `target token or exception` | 目标 token / 命名例外                                     |
| `reason`                    | 第一阶段暂不迁移原因                                      |
| `removal condition`         | 移除条件                                                  |
| `audit locations`           | 优先列 audit 输出行号；只有行号不稳定时使用可复现定位模式 |

## First-Phase Legacy Baseline

This baseline covers current legacy primary audit and supplemental audit output. `FlowTypography` internal implementation hits are the canonical token source, not legacy. Entries may group hits by same file, responsibility, and target token or exception, but every legacy audit hit must be represented by an `audit locations` value.

| file | current value | target token or exception | reason | removal condition | audit locations |
| --- | --- | --- | --- | --- | --- |
| `FlowTab/App/ContentView.swift` | `28 semibold rounded`, `13 regular` | `.display`, `.body` | Initial placeholder view predates `FlowTypography`. | Replace placeholder text fonts with `FlowTypography.swiftUI`. | `28`, `39` |
| `FlowTab/App/HomeRootView.swift` | `20 semibold`, `17 medium`, `15 medium` | sidebar brand/visual metrics, `.cardTitle` | Sidebar brand and icon sizing need a named sidebar typography/visual pass. | Add sidebar typography/visual exception or map text to canonical tokens. | `143`, `198`, `202` |
| `FlowTab/TestingSupport/FlowTabUITestBootstrapper.swift` | `13 semibold` | named testing diagnostic exception | Testing bootstrap visible diagnostics need a testing-specific token or exception. | Introduce testing diagnostic typography or migrate to `FlowTypography`. | `173` |
| `FlowTab/Features/Logs/AppLogsView.swift` | `22 semibold`, `12 regular` | `.pageTitle`, `.pageSubtitle` | Logs page header predates `FlowTypography`. | Replace with `FlowTypography.swiftUI`. | `36`, `38` |
| `FlowTab/Features/Logs/RuntimeLogsSection.swift` | `12 regular`, `11 monospaced` | `.body`, `.metadataMonospaced` | Logs controls and lines predate shared typography. | Replace labels with `.body` and log/path text with `.metadataMonospaced`. | `148`, `152`, `169`, `206`, `214` |
| `FlowTab/Features/SharedUI/HomeChrome.swift` | `15 semibold`, `11 medium`, `11 regular`, `12 semibold` | `.cardTitle`, `.cardSubtitle`, `.bodyStrong` | Shared page chrome predates shared typography. | Replace shared chrome fonts with `FlowTypography` tokens. | `73`, `81`, `91`, `191` |
| `FlowTab/Features/Home/HomeLayerRowView.swift` | `13 medium`, `10 semibold`, `11 monospaced`, `11 medium monospaced` | `.formLabelEmphasized`, `.microEmphasized`, `.metadataMonospaced`, `.metadataMonospacedEmphasized` | Home list rows predate shared typography. | Replace row title, badge, and metadata fonts with tokens. | `48`, `54`, `73`, `99` |
| `FlowTab/Features/Home/HomeWindowRowButton.swift` | `13 medium`, `11 regular`, `12 medium` | `.formLabelEmphasized`, `.cardSubtitle`, `.bodyEmphasized` | Home window row AppKit labels predate shared typography. | Replace row labels with `FlowTypography.appKit`. | `175`, `176`, `177` |
| `FlowTab/Features/Home/HomeLandingView.swift` | `22 semibold`, `13 regular`, `13 semibold`, `12 medium` | `.pageTitle`, `.controlText`, `.controlTextEmphasized`, `.bodyEmphasized` | Home landing header and actions predate shared typography. | Replace with `FlowTypography` tokens while preserving current visual weights. | `154`, `161`, `206`, `210` |
| `FlowTab/Features/Home/HomeOverviewComponents.swift` | `10.5 medium`, `17 semibold`, `12 semibold`, `12 medium`, `11 medium` | `.micro`, Home stat value exception, `.bodyStrong`, `.bodyEmphasized`, `.cardSubtitle` | Home stats include non-canonical legacy sizes that need product review before changing. | Map canonical values to tokens and decide whether stat value becomes a named Home exception or a canonical token. | `273`, `279`, `420`, `428`, `437` |
| `FlowTab/Features/Settings/AppVisibilityManagerView.swift` | `12`, `22`, `23`, `20`, `14`, `12.5`, `10.5`, `9.5`, `11`, `13` mixed SwiftUI/AppKit fonts | canonical tokens or App Visibility-specific exceptions | App Visibility manager is a Settings subpage with known non-baseline values. | Classify each role, then migrate to canonical tokens or explicit App Visibility exceptions. | `91`, `93`, `105`, `110`, `147`, `217`, `290`, `293`, `303`, `346`, `358`, `362`, `374`, `376`, `406`, `410`, `417`, `423`, `579` |
| `FlowTab/Features/Switcher/SwitcherPanelSearchBridge.swift` | `20 regular` | `FlowSwitcherTypography.searchInputAppKit` | Search input is a Switcher text-role exception. | Move AppKit search text font into `FlowSwitcherTypography`. | `278` |
| `FlowTab/Features/Switcher/SwitcherPanelSearchViews.swift` | `20`, `16`, `14`, `13`, `12`, `11`, `10`, `24` mixed text and symbol fonts | `FlowSwitcherTypography`, `FlowSwitcherVisual`, canonical tokens | Switcher search has text roles, visual symbol metrics, and measurement fonts that must be named together. | Add Switcher typography/visual APIs and replace search view call sites. | `104`, `110`, `115`, `126`, `167`, `179`, `201`, `206`, `233`, `268`, `271`, `295`, `305`, `357`, `368`, `376` |
| `FlowTab/Features/Switcher/SwitcherPanelPreviewViews.swift` | `13`, `12`, `52`, `18`, dynamic fallback font size | canonical tokens, `FlowSwitcherVisual`, icon fallback exception | Preview cards mix text fonts with symbol and icon fallback visuals. | Tokenize text and move symbol/fallback glyph fonts into named visual/icon exceptions. | `82`, `138`, `176`, `231`, `286` |
| `FlowTab/Features/Switcher/SwitcherPanelOverlayView.swift` | `4` | `FlowSwitcherVisual.overlayMarkerSwiftUIFont` | Overlay marker is diagnostic visual font, not text typography. | Move marker font creation into the named visual exception. | `106` |
| `FlowTab/Infrastructure/Runtime/TerminalWindowPreviewProvider.swift` | dynamic terminal font size | `TerminalPreviewTypography.terminalFont(for:)` | Terminal preview rendering uses runtime font data and remains outside normal UI tokens. | Move dynamic terminal font creation and range clamp into `TerminalPreviewTypography`. | primary `500`; supplemental `497` |

## Validation

- 文档阶段：unit / behavior / UI / pressure 均不相关。
- 新增 `FlowTypography` 且不替换视觉值：build + audit。
- Settings primitives 接入且视觉值不变：build + audit + Settings 重点页面截图或人工检查。
- 替换现有 UI 且视觉值不变：build + audit + 重点页面检查。
- 改实际字号、布局测量、Switcher 搜索行高或 preview 渲染：升级为用户可见变更，跑对应 UI 路径。
- 搜索/preview 等反复渲染路径发生实质变化时，再评估 pressure。
