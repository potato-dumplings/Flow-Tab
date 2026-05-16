# Runtime Logging

本页定义 FlowTab 生产运行时日志的级别口径。新增或调整日志时，优先复用 `RuntimeLog` 和 `RuntimeLogCategory`，不要在生产代码里直接调用 `RuntimeDiagnostics.shared.log(...)`，除非是在日志基础设施本身或测试启动数据里写入原始记录。

## 级别规则

- `debug`：高频诊断、候选项、逐窗口/逐输入细节、耗时拆解、布局测量、内部探测路径和成功细节。
- `info`：正常生命周期、用户偏好生效、成功注册/恢复、以及预期内 fallback 策略选择。
- `warning`：权限缺失、能力降级、超时、缓存异常、搜索无结果诊断等可恢复但需要关注的状态。
- `error`：最终请求操作失败，例如热键注册失败、Command+Tab 接管或恢复失败、activation recovery 耗尽、launch-at-login 写入失败、预览批量获取失败。

内部路线失败不自动等于 `error`。例如 activation 可以先尝试 CG，再尝试 AX、public recovery 或 Chrome internal；单条路线不可用应保持 `debug`，只有所有可用恢复路径耗尽后才记录 `error`。

## 分类规则

`RuntimeLogCategory` 里标记为 verbose-only 的分类，在关闭 verbose diagnostics 时会压制 `debug/info`，但仍保留 `warning/error`。这适用于 `Activation`、`AX`、`AXMatch`、`HotKey`、`InputTrace`、`Preview`、`Search*`、`Session`、`Snapshot`、`SwitcherLayout` 等容易在热路径中刷屏的分类。

`Permission`、`App`、`UITest` 不按 noisy 分类压制。权限缺失通常用 `warning`，偏好或应用状态生效通常用 `info`。

## 放置原则

- 可复用生产日志入口放在 `FlowTab/Infrastructure/Runtime/RuntimeLogging.swift`。
- 运行时拓扑、权限、activation、preview、snapshot 等诊断日志应留在 runtime infrastructure 或对应的 feature coordinator，不要散落到纯 UI 渲染代码。
- 临时排障日志必须在交付前移除；需要长期保留的日志应按本页级别重新判断。
