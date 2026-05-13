# Option+Tab 性能设计

## 目的

这份文档定义 Option+Tab 的目标产品体验和目标技术方案。文档从干净基线出发，只描述应该如何设计和验收，不依赖任何临时实现、实验补丁或本地状态。

核心目标：

- 按下 Option+Tab 后，应用层要快速出现。
- 如果自动进入窗口层设置为 `0.1s`，窗口层应在接近该时间点出现，而不是明显滞后。
- 选中的应用有大量窗口时，不应为了进入窗口层而扫描所有应用的 AX，也不应提前截取所有窗口截图。
- 首屏窗口数量应由当前屏幕和面板尺寸决定，超出部分分页展示。
- 截图只服务于当前可见窗口页，不能让不可见窗口拖慢首屏。
- 窗口层进入后，本次 session 的窗口顺序应冻结；截图调度基于这个固定顺序切出当前页。

## 范围

包含：

- 全局 Option+Tab 应用切换。
- 应用层启动耗时。
- 从应用层自动进入选中应用窗口层。
- 选中应用窗口列表的顺序。
- 大量窗口下的首屏分页。
- 当前页窗口截图预热。
- 后台全量 runtime snapshot 的调度策略。
- 日志、测试和压测验收。

不包含：

- Control+Tab 应用内窗口切换。
- 与 Option+Tab 启动无关的搜索排序。
- 选中窗口后的激活细节。
- 除分页控件和首屏窗口数量外的视觉重设计。

## 产品要求

### 应用层

应用层是用户按下 Option+Tab 后的第一反馈。

要求：

- 从 hotkey press 到应用层可见，p95 应小于等于 `100ms`。
- 正常 warm 状态下目标值为 p95 小于等于 `60ms`。
- 应用层启动不得依赖全量 AX 窗口扫描。
- 应用层启动不得依赖窗口截图。
- 应用顺序应稳定，优先反映系统 frontmost / MRU 顺序。

### 窗口层

窗口层展示当前选中应用的窗口。

要求：

- 如果 `autoEnterDelay = 0.1s`，并且选中应用窗口数据在 deadline 前已准备好，则窗口层应在 `110ms` p95 内出现。
- 如果选中应用窗口数据晚于 deadline 返回，则数据应用后应立即进入窗口层。
- 异步窗口数据返回后，不得重置原始 auto-enter deadline。
- 窗口层应使用“选中应用范围内”的窗口数据，不应等待全量 all-app AX snapshot。

### 大量窗口

如果选中应用有很多窗口：

- 首屏只展示当前屏幕尺寸可容纳的窗口数量。
- 可见数量由面板宽度、窗口卡片宽度、间距和分页控件预留空间计算。
- 超出可见数量时显示左右分页箭头或等价分页提示。
- 首次只请求当前页窗口截图。
- 非当前页截图只能在空闲时、低优先级、有上限地后台预热。
- 当前页已拿到的截图在本次面板 session 结束前应保持可用；后台预热不能让当前页从真实截图抖回 fallback。

对于 16 寸、宽度约 `1728px` 的屏幕，首屏目标大约是 `10` 个窗口。更大的屏幕可以更多，更小的屏幕可以更少。

## 总体架构

Option+Tab 应拆成三条互相独立的 runtime 路径：

1. 轻量应用快照。
2. 选中应用窗口快照。
3. 后台全量 runtime 快照。

这三条路径的耗时预算不同，不能绑在同一个关键路径里。

### 轻量应用快照

目的：

- 快速构建应用层。

允许做的事：

- 读取 running applications。
- 读取 bundle、app identity、名称、图标等轻量信息。
- 读取轻量 MRU / app rank。
- 构建 app-cycle session，窗口列表先延迟。

不允许做的事：

- 全量 AX 扫描。
- 为所有应用做完整窗口匹配。
- 窗口截图。
- 因为窗口数据缺失而阻塞应用层展示。

建议归属：

- `FlowTab/Infrastructure/Runtime`：轻量 app snapshot provider。
- `FlowTab/Features/Switcher`：session 启动和面板展示编排。

### 选中应用窗口快照

目的：

- 当窗口层需要展示时，只读取当前选中应用的窗口。

允许做的事：

- 根据 selected app ID 找到对应 running app / pid。
- 读取一次 CG window list。
- 过滤出属于 selected app pid 的窗口。
- 构建 selected app 的 window entries。
- 必要时只对 selected app 做 AX 补充，并且必须有严格预算。

不允许做的事：

- 扫描无关应用的 AX。
- 等待后台全量 runtime snapshot。
- 在窗口 metadata 之前先做截图。
- 仅靠重复 title 做窗口身份和排序。

建议归属：

- `FlowTab/Infrastructure/Runtime`：selected-app scoped runtime provider。
- `FlowTab/Features/Switcher`：请求调度、generation 校验、session apply。

### 后台全量 Runtime 快照

目的：

- 刷新完整 app/window 状态，供搜索、后续交互和一致性修正使用。

规则：

- 不得阻塞应用层展示。
- 不得阻塞 selected-app 窗口层进入。
- 应在应用层可见、selected-app 关键路径不再 pending 后再启动。
- 优先级应低于 hotkey、selected-app window snapshot、auto-enter。
- session 结束或新 generation 出现时应可取消。
- apply 时应尽量保持当前 selected app / selected window 不跳变。

建议归属：

- `FlowTab/Infrastructure/Runtime`：完整 runtime snapshot provider。
- `FlowTab/Features/Switcher`：后台调度和安全 apply。

## 链路设计

### 初次按下 Option+Tab

```text
Hotkey press
  -> 读取轻量 app snapshot
  -> 构建 app-cycle session，窗口延迟
  -> 展示应用层
  -> 如果 auto-enter 可能需要窗口，调度 selected-app window snapshot
  -> 等关键路径结束后，再调度后台 full runtime snapshot
```

### 自动进入窗口层

```text
面板打开或 selected app 变化
  -> 记录本次输入对应的 auto-enter deadline
  -> 如果 selected app 已有窗口，按 deadline 调度 timer
  -> 如果 selected app 没有窗口，请求 selected-app window snapshot
  -> selected-app windows 返回后：
       - 只有 session generation 和 selected app 仍匹配才 apply
       - 保留原始 auto-enter deadline
       - deadline 已过则立即进入窗口层
       - deadline 未到则只等待剩余时间
```

### 截图预热

```text
窗口 metadata 已准备好
  -> 按 selected app 的窗口排序规则生成本次 session 的固定窗口序列
  -> 根据布局计算当前页 visible slots
  -> 从固定序列切出当前页窗口
  -> 只为当前页窗口请求 preview
  -> cache hit 立即显示
  -> cache miss 进入有上限的 current-page capture batch
  -> 同一个 batch 共享一次 SCShareableContent 查询
  -> batch 结果提交后再展示当前页窗口卡片
  -> 当前页全部完成后，非当前页截图才可进入空闲阶段
```

## 窗口排序

selected app 的窗口排序建议优先级：

1. 当前可靠的 onscreen / frontmost window。
2. onscreen 窗口的 CG z-order。
3. FlowTab 自己记录的 recent window order，但只在 window identity 可靠时使用。
4. offscreen / other-space 窗口。
5. minimized / hidden 窗口，如果产品决定展示它们。

规则：

- 重复 title 不能作为唯一身份。
- 有 CG window ID 时优先使用 CG window ID。
- AX 可以补充 title、role、tab 信息，但不能导致全量 all-app AX 扫描。
- fullscreen sibling / desktop sibling artifact 应通过拓扑规则过滤，不能通过某个 app 的特殊 title hack 处理。
- 进入窗口层后，本次 session 应使用同一个排序结果做分页和截图调度；后台 snapshot 返回只能安全合并，不得让当前页顺序抖动或已显示图片回退。

## 首屏窗口数量与分页

首屏窗口数量应由纯布局规则计算。

输入：

- 面板内容宽度。
- 窗口卡片目标宽度。
- 卡片间距。
- 分页箭头或分页提示预留空间。
- 最小和最大 slot cap。

建议规则：

```text
availableWidth = panelWidth - horizontalPadding - paginationReserve
rawSlots = floor((availableWidth + itemSpacing) / (previewItemWidth + itemSpacing))
visibleSlots = clamp(rawSlots, min: 6, max: 16)
```

具体常量应放在一个共享 layout configuration 中，避免 model、view、test 各写一份数字。

行为：

- `windows.count <= visibleSlots`：展示全部窗口，不显示分页箭头。
- `windows.count > visibleSlots`：只展示当前页，并显示分页提示。
- 首次 preview capture request 数量必须小于等于 `visibleSlots`。
- 首次 preview capture 的对象必须是固定窗口序列中当前页的前 `visibleSlots` 个对象，而不是全量窗口集合。

## 截图策略

截图昂贵，且受 Screen Recording 权限和系统负载影响。产品上应优先避免“错图”，其次再追求“快图”。

规则：

- 不得把某个窗口截图复用到另一个窗口。
- preview cache key 至少应包含 app ID、pid、CG window ID；如果可用，还应包含 bounds/title/version 等变化信号。
- 截图未准备好时，窗口卡片应显示明确的 fallback：app icon、窗口标题、loading 状态。
- 只要 selected-app window metadata 准备好，就可以开始当前页截图预热。
- capture 并发数需要压测决定，不应拍脑袋。建议初始值为 `min(visibleSlots, 4)`，只有在压测证明 p95 改善且 UI 不变卡时再提高。
- 当前页 cache miss 应合并成一个 capture batch；batch 内共享一次 `SCShareableContent` 查询，再按受控并发执行每个窗口截图。
- 当前页冷截图结果应按 batch 发布；batch 未提交前不要展示 fallback 窗口卡片，避免单卡或整页“翻面”。
- 当前页 batch 即使全部失败，也必须提交完成状态并展示 fallback，不能让窗口层永久空白。
- 当前页截图未完成前，不请求非当前页截图。
- 当前页截图结果应被 session 内保活。即使 preview cache 发生驱逐，当前页卡片也应优先使用 session-pinned 图片，直到面板关闭或 session generation 失效。
- 面板关闭、session 取消或 generation 变化后，应丢弃 session-pinned 图片和未开始的非当前页预热。

验收：

- cache hit 的当前页截图应在窗口层首帧出现。
- cold capture 必须记录 first-image 和 all-visible-image 耗时。
- cold capture 不得阻塞应用层。
- cold capture 不应阻塞窗口 metadata 展示，但 UI 必须让 loading fallback 和真实截图有明确区别。
- 当前页截图一旦显示，在同一 session 内不得因为后台非当前页截图、cache 驱逐或 full snapshot 合并而回退为 fallback。

## 调度优先级

从高到低：

1. Hotkey callback 和应用层展示。
2. selected-app window snapshot。
3. auto-enter deadline 处理。
4. 当前页 preview capture。
5. 后台 full runtime snapshot。
6. 非当前页 preview capture。

后台 full runtime snapshot 不应在 selected-app window refresh pending 时立即启动。可以引入一个小延迟，例如 `150ms`，用于避开关键路径资源竞争。

所有异步任务都应有 generation token：

- stale selected-app snapshot result 要丢弃。
- stale preview result 要丢弃。
- stale full snapshot result 要么丢弃，要么只做安全合并。

## 日志设计

Option+Tab 性能链路日志默认应为 `DEBUG` 级别。

必要 DEBUG 事件：

- `optionTabPress`：hotkey 时间戳、方向。
- `appSnapshot`：running app 数量、selected app 数量、耗时。
- `appLayerPresented`：从 hotkey 到可见总耗时、session 构建耗时、panel 展示耗时。
- `selectedAppWindowSnapshot`：app ID、pid 数、窗口数、CG 耗时、可选 AX 耗时、apply 耗时、总耗时。
- `autoEnter`：配置 delay、原始 deadline、剩余 delay、实际进入时间、overshoot。
- `previewVisiblePage`：visible slots、窗口总数、page index、cache hits、capture requests。
- `previewCapture`：first image 耗时、all visible image 耗时、成功/失败数量。
- `backgroundFullSnapshot`：调度延迟、开始时间、总耗时、是否和关键路径重叠。

SLA 违背用 `WARN`：

- 应用层超过 `100ms`。
- selected-app 窗口数据已可用后，auto-enter 超出配置 delay 超过 `10ms`。
- selected-app window snapshot 超过 `100ms`。
- 后台 full snapshot 在 selected-app 关键路径 pending 时启动。

正常使用时，不应在 `INFO` 级别输出大量 per-window topology dump。拓扑细节应放在 DEBUG 或专门诊断工具里。

## 测试计划

### Unit Tests

证明纯规则：

- 小屏、16 寸、大屏下的 visible slot 计算。
- 分页 page slicing 和箭头显示规则。
- auto-enter deadline 计算：数据早于 deadline、晚于 deadline 两种情况。
- preview request 数量被限制在 visible slots 内。
- preview cache key 的命中与失效。
- 重复 title、CG z-order、offscreen、stale recency 下的窗口排序。

### Behavior Tests

证明进程内编排：

- Option+Tab 使用轻量 app snapshot 展示应用层，不等待 full AX。
- selected app 初始无窗口时，会触发 selected-app scoped window snapshot。
- selected-app snapshot stale 或 selected app 已变化时不会 apply。
- selected-app 窗口数据返回后，auto-enter 保留原始 deadline。
- selected-app 关键路径 pending 时，background full snapshot 被延后。
- preview capture 请求数量只等于当前 visible page。
- current-page runtime preview miss 合并为单个 batch，提交后再展示当前页。
- batch preview capture 对同一页共享一次 shareable-content 查询模式。
- full snapshot apply 时尽量保持当前选择不跳变。

### UI Tests

证明用户可见行为：

- Option+Tab 能打开应用层并显示 app entries。
- selected app 有大量窗口时，窗口层只显示首屏窗口并显示分页控件。
- 翻页会切换可见窗口，不会一次请求所有窗口截图。
- loading fallback 和真实截图视觉上可区分。
- 有 Screen Recording 权限时，当前页截图加载到正确窗口卡片上。

UI 自动化应优先使用 fixture 或 mock topology。真实 Chrome 可用于人工探索，但自动化测试不应依赖开发者本机 Chrome 状态。

### Pressure Tests

该路径是 hot path 且对 app/window/preview 数量敏感，因此必须有压测。

必测场景：

- `600` 个 running apps，窗口延迟加载：应用层启动 p95。
- selected app 有 `100` 个窗口：selected-app snapshot p95 和 auto-enter overshoot。
- selected app 有 `1000` 个窗口：selected-app snapshot p95 和 preview request count。
- 连续 Option+Tab open/close 至少 `60` 次。
- 在 `0`、`1`、`10`、`100+` 窗口的应用之间反复移动 selection。
- visible slots 为 `6`、`10`、`16` 时的 preview 压测。

报告指标：

- app-layer presentation 的 p50、p95、max。
- selected-app window snapshot 的 p50、p95、max。
- auto-enter overshoot p95。
- preview cache hit 数、capture request 数、first-image p95、all-visible p95。
- background full snapshot 是否和关键路径重叠。

## 验收标准

实现满足以下条件时，才算达到合格产品状态：

- app-layer presentation 在 app-scale 压测下 p95 小于等于 `100ms`。
- selected-app window snapshot 在 `1000` 个 selected-app windows 下 p95 小于等于 `100ms`，且不扫描无关应用 AX。
- `autoEnterDelay = 0.1s` 时，如果 selected-app metadata 在 deadline 前可用，窗口层进入 p95 小于等于 `110ms`。
- 首次 preview request 数量不超过 visible slots。
- 16 寸屏幕首屏约展示 `10` 个窗口，窗口更多时显示分页。
- background full snapshot 不阻塞 app-layer presentation，也不阻塞 selected-app auto-enter。
- DEBUG 日志足够解释 Option+Tab 全链路耗时，不需要把普通性能诊断提升到 INFO。

## 实施阶段

1. 可观测性。
   - 增加 DEBUG 级链路耗时。
   - 增加 WARN 级 SLA 违背日志。
   - 避免把临时调查日志放进长期生产路径。

2. 拆出应用层轻量启动。
   - 增加 lightweight app snapshot。
   - 应用层展示不依赖 AX。

3. 增加 selected-app scoped window discovery。
   - 只读取 selected app 的窗口。
   - 保留 auto-enter 原始 deadline。

4. 增加首屏分页和截图限流。
   - 抽出 visible slots 和 page slicing 纯规则。
   - 只请求当前页截图。

5. 延后 full runtime snapshot。
   - 关键路径完成后再启动。
   - 支持 cancel 和 generation-safe apply。

6. 补齐测试和压测。
   - Unit 覆盖纯规则。
   - Behavior 覆盖编排。
   - UI 覆盖可见分页和截图正确性。
   - Pressure 覆盖 latency 和 scale。

## 失败与降级

当 runtime 能力不可用时：

- Accessibility denied：应用层仍应打开；selected-app windows 可以降级为 CG-only metadata。
- Screen Recording denied：窗口卡片显示 title/icon fallback，跳过截图并记录诊断。
- CG window ID 缺失：只能使用 session 内临时身份，不得跨 session 缓存截图。
- Full snapshot timeout：保留当前 lightweight / selected-app session，以后台低优先级稍后重试。

用户不应该看到“错窗口截图”。在截图不确定时，明确的 loading fallback 优于错误 preview。
