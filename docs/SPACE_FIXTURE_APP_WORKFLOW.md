# Space Fixture App Workflow

## 背景

当前 FlowTab 的自动化测试主要覆盖两类能力：

- 通过 `--flowtab-ui-mock-runtime` 注入运行时快照，验证 UI 展示和交互逻辑。
- 通过 `handleActiveSpaceDidChangeForTesting()` 或发布 `NSWorkspace.activeSpaceDidChangeNotification`，验证收到空间变化信号后的恢复与取消策略。

这类自动化可以稳定覆盖 FlowTab 自己的逻辑判断，但不能证明 XCTest 已真实驱动 macOS 完成以下行为：

- 新建或进入真实 Space
- fullscreen Space 的生成与切换
- Mission Control 或系统手势动画过程
- 单应用多窗口跨 Space 的真实运行时拓扑

因此，如果要补充“更接近真实环境”的验证，需要单独引入一个测试专用的 fixture app。

## 目标

新增一个专用于本地真实环境回归的 fixture app，用它制造接近 Chrome 的单应用多窗口场景：

- 同一个应用同时存在多个窗口
- 其中一个窗口进入 fullscreen，生成独立 fullscreen Space
- 其他窗口仍停留在普通桌面
- FlowTab 对这些窗口执行真实的 runtime snapshot、分组、排序、space 识别和激活相关逻辑

## 非目标

该 fixture app 不用于替代现有 mock-runtime 自动化，也不应承担以下职责：

- 替代现有 unit、behavior、UI 主覆盖链路
- 作为稳定 CI 的唯一空间验证方案
- 直接证明所有 Mission Control 动画时序都稳定可自动化
- 把测试专用逻辑混入 FlowTab 生产代码路径

## 推荐方案

推荐新增一个独立的测试 app target，例如 `FlowTabSpaceFixture`，而不是复用 FlowTab 本体。

原因如下：

- FlowTab 自己的面板窗口具有跨 Space 和 fullscreen 辅助行为，不能很好模拟普通目标应用。
- 测试目标需要的是“像 Chrome 一样的单应用多窗口”，而不是“FlowTab 自己进入全屏”。
- 独立 fixture app 更容易稳定控制窗口数量、标题、布局和 fullscreen 行为。

## Fixture App 必备能力

该 app 至少应具备以下能力：

- 是普通 macOS app，而不是 `LSUIElement` 或 agent app。
- 支持单应用多窗口。
- 启动时可通过参数创建指定数量窗口。
- 每个窗口具备稳定、可预测的标题。
- 可指定某一个窗口在启动后自动进入 fullscreen。
- 可关闭系统自动 window tabbing，避免多个窗口被合并成标签页。
- 可设置窗口初始位置和尺寸，避免全部重叠。

## 建议启动参数

建议 fixture app 支持以下启动参数：

- `--window-count <N>`
- `--fullscreen-window-index <index>`
- `--window-title-prefix <prefix>`
- `--staggered-layout`
- `--enter-fullscreen-delay-ms <value>`

示例：

```text
FlowTabSpaceFixture --window-count 3 --fullscreen-window-index 3 --window-title-prefix "Fixture"
```

对应预期：

- 创建 3 个窗口
- 标题分别为 `Fixture 1`、`Fixture 2`、`Fixture 3`
- 第 3 个窗口进入 fullscreen
- 第 1、2 个窗口保留在普通桌面

## 为什么必须支持单应用多窗口

如果 fixture app 只有一个窗口，它只能证明“系统里出现了一个 fullscreen Space”，但不能有效覆盖我们更关心的真实场景：

- FlowTab 是否把多个窗口识别为同一个应用
- fullscreen 窗口和普通窗口是否会同时出现在运行时快照中
- 同一应用下的窗口列表是否能覆盖普通桌面窗口和 off-space 窗口
- 后续激活和切换逻辑是否能处理同 app 多窗口的 space 差异

因此，单窗口空壳 app 不足以代表 Chrome 这类真实目标应用。

## 测试流程

### 1. 构建 fixture app

先构建 `FlowTabSpaceFixture` target，确保测试环境中能拿到可启动的 app bundle。

### 2. 启动 fixture app

通过启动参数创建多窗口场景，并让指定窗口进入 fullscreen。

建议初始场景：

- 3 个窗口
- 第 3 个窗口 fullscreen
- 其余 2 个窗口留在普通桌面

### 3. 等待系统状态稳定

在 FlowTab 开始采样前，等待以下状态稳定：

- fixture app 所有窗口创建完成
- 指定窗口已进入 fullscreen
- macOS 已为该窗口建立 fullscreen Space
- 前台应用和活跃 Space 状态不再抖动

这一步应由测试驱动层显式等待，而不是依赖固定极短延时。

### 4. 启动或操作 FlowTab

在真实空间场景已经建立后，再启动或唤起 FlowTab，执行目标验证，例如：

- 首页窗口列表
- switcher 中的 app card 与 window card
- 同 app 多窗口展示
- fullscreen 或 off-space 窗口的恢复展示
- 激活指定窗口后的 space 切换与焦点行为

### 5. 执行断言

断言应聚焦在真实环境下仍然可稳定判断的结果：

- FlowTab 是否识别到 fixture app
- 是否识别到该 app 下的多个窗口
- fullscreen 窗口是否进入了可预期的展示或恢复路径
- 激活后是否发生预期的窗口聚焦或 space 切换

不应把系统动画帧级时序作为主断言目标。

### 6. 清理环境

测试结束后关闭 fixture app 和 FlowTab，确保不会污染下一条用例的空间状态。

## 测试分层建议

推荐把测试职责拆成两层：

- 主自动化层：继续使用现有 mock runtime 和信号模拟，覆盖稳定、可重复的业务逻辑。
- 真实环境补充层：使用 fixture app 制造多窗口 fullscreen Space 场景，做本地回归或低频集成验证。

这样做的原因是：

- 主自动化负责稳定性和覆盖面。
- 真实环境补充层负责发现 mock 路径无法证明的系统行为偏差。

## 风险与限制

该方案虽然比“直接让 FlowTab 自己全屏”更合理，但仍有以下限制：

- fullscreen 进入时机可能受系统动画、焦点和桌面设置影响。
- `activeSpaceDidChange` 的触发时序可能和 UI 自动化脚本不同步。
- 不同 macOS 版本和桌面设置可能导致行为差异。
- 这类测试更适合本地回归或低频集成运行，不适合作为唯一稳定 CI 依据。

## 与现有自动化的关系

这套方案是对现有自动化的补充，不是替换。

现有自动化继续负责：

- mock runtime 数据场景
- `activeSpaceDidChange` 后的控制器策略
- UI 可见性、交互、搜索、列表展示

fixture app 方案补充负责：

- 真实单应用多窗口场景
- 真实 fullscreen Space 生成
- 真实窗口拓扑对 FlowTab runtime 的影响

## 后续实施顺序

建议按以下顺序推进：

1. 新增 `FlowTabSpaceFixture` target，先只支持多窗口和稳定标题。
2. 再增加“指定窗口自动 fullscreen”能力。
3. 先做一条本地可重复的手工回归流程。
4. 在流程稳定后，再接入低频 UI 自动化或集成测试。
5. 最后再决定是否需要把该流程纳入常规测试脚本。

## 当前结论

如果要验证接近 Chrome 的真实空间场景，fixture app 必须支持单应用多窗口，且至少有一个窗口可以进入 fullscreen。仅创建单窗口空壳 app 不足以覆盖我们需要的场景。
