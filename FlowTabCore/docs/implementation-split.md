# FlowTab 分工实现（第 1 轮）

## 模块拆分

1. `FlowTabCore/Preferences`
- 负责主题、快捷键、最小化恢复、多窗口策略等配置定义。

2. `FlowTabCore/Grouping`
- 负责应用分组构建与分组索引映射。

3. `FlowTabCore/SwitcherSession`
- 负责核心状态机：
  - 应用层切换
  - 分组层导航（`↑` 进入，`←/→` 切组）
  - 窗口层切换（`↓` 进入，`Tab/Shift+Tab` 切窗口）
  - 释放主修饰键后的目标确认

4. `FlowTabCoreTests`
- 负责回归测试，覆盖当前需求中的关键行为路径。

## 当前已完成

1. 配置模型（默认值与枚举）已落地。
2. 分组构建与 group 索引定位已落地。
3. 三层切换状态机已落地，包含：
- 最小化窗口是否恢复（可选）
- `Command + Tab` 覆盖能力配置字段
- 多窗口策略（最近活跃 / 记住上次 / 自动进入窗口层）
- 主题模式（白天 / 黑夜 / 跟随系统，默认跟随系统）
4. 单元测试已覆盖关键行为。

## 下一轮实现

1. `SystemBridge`：接入 macOS 事件监听与窗口激活（公有 API 优先）。
2. `ShortcutEngine`：主热键与方向键事件流整合到 `SwitcherSession`。
3. `OverlayUI`：实现 macOS 简洁风切换面板（应用层/分组层/窗口层视觉一致）。
4. `Persistence`：保存主题、快捷键、窗口策略与分组配置。
