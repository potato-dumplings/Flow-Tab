# Runtime AX/CG/Space Window Mapping

## 文档定位

这份文档是 FlowTab runtime 的地基图纸，不是逐条补丁清单。

它定义的是目标形态：

- runtime 长期维护底层状态，而不是长期维护一份大 `RuntimeSnapshot`。
- `RuntimeSnapshot`、Home summary、Switcher app/window 列表、search index 都是从底层状态投影出来的读模型。
- 热路径只能读已维护好的投影，不能排队等待 CG/AX/Space 采样。
- 全量 snapshot 是 repair/fallback，不是 `Option+Tab`、`Control+Tab`、Search 或 Home 的主流程。
- activation 可以用缓存选择目标，但必须用提交后的系统回读验证结果。

## 核心目标

1. `window-layer` 只展示可切换、可恢复、可稳定维护的窗口条目，不暴露死条目或短暂幻觉。
2. 构建阶段与维护阶段使用一致的 reconciliation 管线，启动期、后台维护期、交互期行为一致。
3. `Option+Tab` 首帧稳定读取 app 投影，不触发全量 AX/CG/Space 重采样。
4. `Control+Tab` 和当前 app window layer 只读取当前 app 投影，不依赖所有 app 的窗口已完成。
5. Search 读取持续维护且原子提交的 committed search index；进入 Search 时先做轻量 freshness validation，确认该 index 已覆盖最新 app lifecycle、CG、Space 与 AX dirty generation。若未覆盖，只有 bounded freshness barrier 成功提交新 generation 后才能进入最新结果态；barrier 未提交时只能返回 degraded/stale committed result 与 dirty/freshness metadata。Search 不读取 repair 中间态，也不把旧索引或部分索引伪装成最新完整结果。
6. Home 读取摘要投影，只刷新可见或选中的 app/window 详情。
7. 真实系统拓扑变化通过 dirty signal、局部 pullback、retry/backoff、projection rebuild 闭环吸收。

## 总体架构

目标 runtime 由四层组成：

1. **Source inputs**
   - `NSWorkspace` / running apps
   - `CGWindowList`
   - `AX` app/window tree
   - `CG -> Space` topology
   - activation 后的 focused-window readback

2. **RuntimeReadModelStore**
   - app directory
   - `RuntimeWindowRecord` 主表
   - Space topology state
   - freshness/confidence/dirty metadata
   - projection cache

3. **RuntimeMaintenanceScheduler**
   - dirty app / dirty window / dirty Space 队列
   - priority / coalescing / cancellation / retry / backoff
   - bounded sampling and repair

4. **Feature surfaces**
   - Switcher app cycle
   - Switcher current-app window cycle
   - Switcher search
   - Home summaries and selected rows
   - activation service

关键约束：

- `RuntimeReadModelStore` 是长期状态核心。
- `RuntimeSnapshotProvider` 是采集、reconciliation 和投影构建边界，不是所有 surface 的状态机中心。
- feature surface 只发 dirty signal 或读 projection，不自己扩张 topology reconciliation 状态机。
- projection 可丢弃、可重建、可带 freshness metadata；它不是长期真相。

## 为什么不能只做 RuntimeSnapshotCache

`RuntimeSnapshot` 是结果，不是地基。

如果把当前 `snapshot()` 的结果缓存起来，再命名为 `RuntimeSnapshotCache`，但底层仍然在 hot path 上调用同一条 snapshot/sampling queue，就只是换了名字。正确拆分是：

- 底层维护 `RuntimeWindowRecord`、app directory、Space topology、dirty/reconciliation 队列。
- projection store 从这些底层状态生成面向 surface 的读模型。
- hot path 读取 projection store，不进入 CG/AX/Space 采样队列。
- full snapshot 只作为 repair、fallback、diagnostic 或迁移期兼容入口。

## RuntimeReadModelStore

目标 store 维护以下长期状态。

### appDirectory

按 app identity 聚合运行中 app：

- `appID`
- bundle identifier / fallback pid id
- display name
- primary pid
- grouped pids
- launch state
- app-layer visibility state
- preference-derived app-layer eligibility
- last active rank / recency
- freshness metadata

约束：

- app-layer 偏好只依赖 app 层事实时，不应额外读取 AX window tree。
- 例如“隐藏某 app”是 app-layer 过滤；不需要为了判断这个 app 是否被用户隐藏而拉 AX。
- 只有偏好语义真的依赖窗口事实时，才读取 window projection 或触发 scoped repair。

### windowRecordsByCGWindowID

以 `CGWindowID` 为主键维护长期窗口身份。

`RuntimeWindowRecord` 至少包含：

- `cgWindowID`
- `stableWindowID`
- `ownerPID`
- `lastKnownCGTitle`
- `lastKnownCGFrame`
- `currentAXAttachment`
- `lastExactAXWindowID`
- `lastConfirmationSource`
- `lastExactConfirmedAt`
- `publicAXState`
- `spaceRecovery`
- `allowedActions`
- `bindingConfidence`
- `firstSeenAt`
- `lastSeenAt`
- `suspectDeletedAt`
- `needsReconciliation`
- `freshness`

其中 `currentAXAttachment` 是当前可用激活句柄；`lastExactAXWindowID` 和 `lastExactConfirmedAt` 是 sticky binding 的历史证据；`spaceRecovery` 是恢复路线证据；`publicAXState` 保存 minimized/focused/main 等公开 AX 状态。

约束：

- `CGWindowID` 是长期窗口身份主锚点。
- `AXWindowID` 只服务当前或短周期采样，不承担跨快照长期身份。
- `AXUIElement` 是提交时的激活句柄，不是持久主键。
- `spaceRecovery` 是 `RuntimeWindowRecord` 的字段，不是另一份并列真相。
- 旧的 sticky map、space recovery map、当前 AX 索引都应收敛为主表派生状态。

### derived indexes

这些索引从主表派生：

- `currentAXToCG: [AXWindowID: CGWindowID]`
- `currentCGToAX: [CGWindowID: AXWindowID]`
- `validCGWindowIDsByPID`
- `lastAXWindowIDsByPID`
- `recordsByPID`
- `recordsByAppID`
- `dirtyRecordsByPID`
- `searchableRecordIDs`

约束：

- 派生索引可以重建，不能和主表双写出第二份事实。
- 如果索引和主表冲突，以主表为准并重建索引。

### spaceTopology

Space topology 至少维护：

- `currentSpaceIDByDisplay`
- `spacesByID`
- `windowIDsBySpaceID`
- `spaceIDsByCGWindowID`
- `fullscreenWindowIDBySpaceID`
- `lastSignature`
- `lastValidatedAt`

目标状态不只保存某个窗口的临时 `spaceIDs` 查询结果，而是维护一份可 diff 的拓扑视图。它回答：

- 当前系统有哪些 Space。
- 每个 display 当前处于哪个 Space。
- 某个 `CGWindowID` 当前属于哪些 Space。
- 哪些 Space 或 fullscreen 归属发生了变化。
- 哪些 `CGWindowID` 受拓扑变化影响。

### projection cache

projection cache 是 read model，不是 source of truth：

- `appSwitcherProjection`
- `currentAppWindowProjection`
- `homeSummaryProjection`
- `homeAppWindowProjection`
- `committedSearchIndex`
- `stagingSearchIndex`
- `activationTargetProjection`

每份 projection 都必须带 freshness/confidence metadata：

- `generatedAt`
- `sourceGeneration`
- `dirtyAppIDs`
- `dirtyPIDs`
- `dirtyCGWindowIDs`
- `pendingRepairScopes`
- `isCompleteForScope`
- `coveredAppLifecycleGeneration`
- `coveredCGGeneration`
- `coveredSpaceGeneration`
- `coveredAXDirtyGeneration`
- `committedGeneration`

除 Search 以外，如果 projection 不完整，要明确暴露 pending/dirty，而不是假装完整。

Search 是更强约束：Search surface 只能读取 `committedSearchIndex`。`stagingSearchIndex` 只允许 runtime maintenance 写入和验证，不能被 Search 直接读取。pending/dirty 可以作为内部 barrier 或日志状态存在，但不能成为正常搜索结果的一部分。

## 角色划分

### CGWindowID

- 负责长期稳定窗口身份。
- 是 sticky binding 的主锚点。
- 适合回答“这个窗口长期是谁”。
- 是启动阶段和运行期 reconciliation 最先建立的记录。
- 不直接承担第三方窗口激活。

### AXWindowID 与 AXUIElement

- `AXWindowID` 是当前采样或 registry 下的短周期索引键。
- `AXUIElement` 是当前提交时优先使用的激活句柄。
- 适合回答“现在能不能用公开 AX 激活它”。
- 不适合独自承担跨重排、跨全屏、跨恢复的长期身份。

### public AX state

公开 AX state 包括：

- focused
- main
- minimized
- title
- frame
- role/subrole
- allowed actions

这些状态用于公开匹配、tie-breaker、window-layer exposure 和 activation 选择。但它们仍然附着到 `RuntimeWindowRecord.currentAXAttachment`，不能在 Switcher、Home、activation 各自保存一份局部判断。

### exact bridge

当前 exact bridge 使用 `_AXUIElementGetWindow` 形成 `AX -> CG` 精确映射。

约束：

- 公开信息能唯一匹配时，优先使用公开路径。
- 公开路径不能唯一匹配时，exact bridge 用来学习当前 `AX <-> CG`。
- exact bridge 不替代公开匹配，不替代 Space topology，不替代提交后的 readback。

### CG -> Space

`CG -> Space` 是独立于 `AX <-> CG exact binding` 的恢复证据。

它适合回答：

- 当前没有 AX attachment 时，窗口是否仍属于可识别 Space。
- fullscreen/off-space 窗口是否可以通过 Space recovery 找回。
- Space topology 变化后，哪些窗口需要局部 reconciliation。

它不等价于 sticky binding，但可以独立支撑提交恢复路径。

### private activation fallback

私有 `CGWindowID` 激活只能用于明确的用户提交路径：

1. 用户选择一个窗口。
2. 当前没有可靠 AX activation handle。
3. record 有明确 target `CGWindowID` 和恢复证据。
4. 执行私有 fallback。
5. 立刻回读 focused AX/CG。
6. 用 readback 重新写入 exact evidence。

被动采样、projection 构建、Home 刷新、Search index rebuild 不能做有副作用的激活探测。

## WindowRecord 状态机

窗口状态从 `RuntimeWindowRecord` 派生，而不是维护多套并列状态。

### exact

条件：

- 当前 AX attachment 与 `CGWindowID` 已唯一确认。
- confirmation source 可以是 public unique match、exact bridge 或 verified focus readback。

用途：

- 可进入 window layer。
- 可优先使用 AX 激活。
- 可刷新 sticky evidence。

### sticky

条件：

- 历史上曾经 exact。
- 当前 AX attachment 暂时缺席或不可确认。
- 没有硬删除信号。

用途：

- 保留长期身份。
- 等待 AX notification、Space topology change、active-space retry 或 scoped repair 恢复 exact。
- 不因为一次采样缺席立即删除。

### space-backed

条件：

- 当前没有 AX exact。
- 没有足够 sticky activation handle。
- 但 `CG -> Space` 已确认，且有提交恢复路径。

用途：

- 支撑 fullscreen/off-space/current-space 外窗口恢复。
- 可进入 window layer，但必须标注 `hasConfirmedActivationRoute`。
- 提交时优先走 Space recovery，再读回 AX/CG 验证。

### provisional CG-only

条件：

- 当前只有 CG 观测。
- 没有 AX exact。
- 没有 sticky evidence。
- 没有 Space recovery 或恢复路线未确认。

用途：

- 短期候选。
- 可参与后续 reconciliation。
- 不应进入主 window layer。

### deleted

条件：

- `pid terminated`。
- 已知 AX window destroyed 且没有保留 sticky/Space 恢复理由。
- AX、CG、Space 三层证据在 grace window 内持续缺席。
- Space recovery 超时且 CG/AX 也持续缺席。

约束：

- 删除接受强删除信号或连续缺席超时。
- 单次 AX 空结果不是删除证明。
- 单次 Space topology diff 不是删除证明，只能标脏并局部 pullback。

## Space Topology 策略

### 快速判定

Space 是否变化不能只靠全量 window snapshot。目标策略是维护轻量 topology signature：

- displays 集合
- current space per display
- space ids per display
- fullscreen space/window signature
- known window membership generation

当 signature 未变化时：

- 不需要重跑全量 Space reconciliation。
- 只对明确 dirty app/window 做局部 pullback。

当 signature 变化时：

- 生成 `RuntimeSpaceTopologyDiff`。
- 产出 `addedSpaceIDs`、`removedSpaceIDs`、`changedSpaceIDs`、`affectedCGWindowIDs`。
- 只标记受影响 app/window dirty。
- 对 current/recent/visible scopes 优先 pullback。

### normal 与 fullscreen 变化

normal -> fullscreen 通常表现为：

- 新 fullscreen Space 出现，或目标 window 移入 fullscreen Space。
- display current Space 变化。
- `fullscreenWindowIDBySpaceID` 变化。

fullscreen -> normal 通常表现为：

- fullscreen Space 移除，或目标 window 离开 fullscreen Space。
- removed/changed Space 影响原 fullscreen window。
- target `CGWindowID` 的 `spaceIDs` 变化。

目标 runtime 不需要每次都完整拉所有 AX tree 才知道这些变化。它应先通过 Space signature/diff 判断拓扑是否变了，再把受影响 `CGWindowID` 转成 app/pid scoped repair。

### 系统权威视图

目标形态需要接近系统权威的 Space/window 视图：

- display-level Space topology 来自 managed display Spaces。
- window membership 来自 `CGSCopySpacesForWindows` / `SLSCopySpacesForWindows`。
- CG window facts 来自 `CGWindowList`。
- AX 只作为 activation handle、public state、dirty/repair input。

如果生产环境只能先从当前 CG window list 推导 Space metadata，则必须把它标为迁移中实现，而不是最终权威模型。

## Reconciliation 管线

构建阶段、后台维护阶段、用户提交后的 readback 都进入同一条 reconciliation 管线。差别只在 scope、priority、触发原因和允许的副作用。

单个 app/pid 的 pipeline：

1. 读取 app directory，确认 app/pid scope。
2. 采集 scoped CG facts。
3. 必要时采集 scoped AX windows。
4. 必要时读取 scoped Space membership。
5. 对每个 valid `CGWindowID` 先 ensure `RuntimeWindowRecord`。
6. 用 public AX state 尝试唯一匹配。
7. public 唯一匹配成功时写入 exact evidence。
8. public 不能唯一时，必要且允许时调用 exact bridge。
9. exact bridge 成功时写入 exact evidence。
10. 对 unresolved CG 更新 sticky/space-backed/provisional 状态。
11. 对 unresolved AX 不做猜测性长期绑定。
12. 更新派生索引。
13. 更新 freshness/confidence/dirty metadata。
14. rebuild affected projections。

政策：

- 无法唯一确认时，不扩大猜测匹配。
- 一次快照重新变歧义，不等于历史 sticky binding 被证伪。
- `CG -> Space` 是独立证据层，不应因暂时没有 AX exact 就被忽略。
- scoped repair 只修受影响范围，不把每个入口都升级成全局 full snapshot。

## RuntimeMaintenanceScheduler

`RuntimeMaintenanceScheduler` 负责把各种事件收敛成有边界的维护任务。

### 输入事件

- app launched
- app terminated
- AX app/window changed
- AX window destroyed
- Space topology changed
- active Space changed
- Home visible app rows changed
- Home selected app changed
- Switcher opened
- Switcher entered current-app window cycle
- Switcher search activated
- activation target selected
- activation focused readback verified
- periodic stale repair tick

### dirty scopes

- `dirtyApp(appID, pid, reason)`
- `dirtyWindow(CGWindowID, reason)`
- `dirtySpaceTopology(reason)`
- `dirtyProjection(kind, reason)`
- `staleScope(scope, age)`

### priority

优先级从高到低：

1. activation readback target/readback `CGWindowID`
2. current focused app
3. Switcher selected app / current window-cycle app
4. Search active and dirty searchable windows
5. Home selected app
6. Home visible rows
7. recently active apps
8. AX/Space dirty apps
9. stale periodic repair
10. full repair fallback

### 调度规则

- 相同 app/pid dirty 合并。
- 相同 `CGWindowID` dirty 合并。
- 后来的高优先级 scoped repair 可以取消或越过低优先级 full repair。
- AX 空结果使用短间隔 retry，不立刻删除。
- 连续失败进入 backoff。
- 用户热路径不等待 maintenance queue drain。
- 每轮维护有 bounded batch，避免一次性扫完整个系统。

## Projection Contracts

### appSwitcherProjection

用途：

- `Option+Tab` 首帧 app cycle。

读取要求：

- 只读 projection store。
- 不进入 runtime maintenance/sampling queue 的同步等待。
- 不触发 CG/AX/Space 采样。
- 不等待 background full snapshot。

内容：

- app id
- display name
- group id
- app recency rank
- app-layer visibility eligibility
- coarse window availability/freshness
- selected app hint

约束：

- app cycle 不需要所有 app 的完整 window layer。
- 如果 window count 或 minimized facts 不新鲜，只能以 freshness 表达，不阻塞面板出现。

### currentAppWindowProjection

用途：

- `Control+Tab`
- `Option+Tab` 进入当前/选中 app window cycle

读取要求：

- 只读当前 app 或选中 app 的 maintained projection。
- 如果该 app dirty，面板先显示现有可信窗口，再异步触发 scoped repair。
- 不因为其他 app 未维护完成而阻塞。

内容：

- exact/sticky/space-backed 可展示窗口
- activation handle metadata
- Space recovery metadata
- public AX state
- freshness/confidence

### searchWindowProjection

用途：

- Switcher search 的 window 搜索。

读取要求：

- 只读取原子提交的 `committedSearchIndex`。
- Search 打开时先执行 freshness validation，对比 committed index 覆盖的 app lifecycle、CG signature、Space signature、AX dirty generation 与 runtime 当前 generation。
- 如果 committed index 已覆盖当前 generation，Search 立即读取并保持该 generation 内结果稳定。
- 如果 committed index 未覆盖当前 generation，必须先执行 bounded freshness barrier：只对 dirty/current/selected/recent/affected scopes 做 scoped repair，构建 `stagingSearchIndex`，验证通过后原子提交为新的 `committedSearchIndex`。
- bounded freshness barrier 被请求但尚未提交新 generation 时，Search 当前读到的只能是 last committed index，并且必须标记为 `degradedStaleCommittedResult` / stale committed read，携带 dirty/freshness metadata；不能把这个状态命名为 fresh、complete、latest 或 current-generation committed。
- Search 不读取 `stagingSearchIndex`，不读取 repair 中间态，不把旧 index 或部分 index 当作最新完整结果。
- search index 来自 `RuntimeWindowRecord` 主表和 app directory，不来自当前 session 的偶然完整程度。

内容：

- searchable app entries
- searchable window entries
- committed generation
- committed-at timestamp
- covered app lifecycle generation
- covered CG signature generation
- covered Space signature generation
- covered AX dirty generation
- completeness proof for the committed scope

约束：

- 两次搜索读取同一个 committed generation 时，结果必须稳定；后台 maintenance 不能把半成品增量暴露给正在搜索的用户。
- dirty/pending 是内部 barrier、日志或阻断状态，不是 Search 的正常结果状态。
- Search 激活可以提升相关 stale repair 优先级，但不能同步拉全量 AX tree 才开始搜索。
- 如果 freshness barrier 在预算内无法提交新 generation，Search 不能进入最新搜索结果态；当前行为可以返回 last committed index，但必须显式标记为 degraded/stale committed result 并携带 dirty/freshness metadata，不能命名、记录或展示为 fresh/complete/latest result。

### homeSummaryProjection

用途：

- Home app 列表。

读取要求：

- 读取 app summaries。
- 可见 rows 和 selected app 可触发较高优先级 scoped repair。
- Home 不应迫使 hotkey app cycle 等待全局窗口维护。

内容：

- app summary
- window count / visible count / minimized count
- freshness/confidence
- selected app detail projection

### activationTargetProjection

用途：

- 用户提交 app/window 后选择最合适激活路线。

读取要求：

- 可以读取 cached target route。
- 提交后必须 readback。
- readback 是写回 exact evidence 的入口。

内容：

- target `CGWindowID`
- preferred AX handle
- fallback AX route
- Space recovery route
- private CG fallback eligibility
- expected verification target

## Activation Contract

activation 是唯一允许有副作用恢复探测的路径。

窗口提交顺序：

1. 如果当前 exact AX handle 可用，优先 AX activation。
2. 如果 public AX recovery 可行，尝试 public recovery。
3. 如果 record 是 space-backed，先恢复目标 Space，再尝试 AX recovery。
4. 如果没有 AX handle 但 record 具备明确 `CGWindowID` 和 fallback eligibility，执行 private CG activation fallback。
5. 提交后读取 focused AX/CG。
6. 如果 readback target 与提交目标一致，写入 `.verifiedFocusReadback` exact evidence。
7. 如果 readback 不一致，标记 target/readback scopes dirty，并降级该 activation route confidence。

成功条件：

- 不能只看“命令执行成功”。
- 必须用 focused readback 或可等价证明确认目标窗口真的成为当前窗口。
- readback 不能解析到 registry 中既有 AX handle 时，也要能基于 pid + focused `CGWindowID` seed exact record。

## Snapshot 的新位置

旧 snapshot-shaped 入口在目标形态中只能作为：

- repair fallback
- migration compatibility
- diagnostic command
- cold start bootstrap 的最后兜底
- test fixture assembly helper

当前实现已删除 provider-facing `RuntimeSnapshotProvider.snapshot()` wrapper；runtime full repair 入口使用 `RuntimeFullRepairProjectionPayload` / `fullRepairProjectionPayload()`，不再构造 `RuntimeSnapshot` wrapper。

它不再是：

- `Option+Tab` 首帧主流程。
- `Control+Tab` 当前 app window 主流程。
- Search index 主来源。
- Home summary 主来源。
- 每个 topology dirty signal 的默认处理方式。

任何新的 `snapshot` cache 如果仍挂在同一条采样队列上，仍然会被后台 CG/AX/Space 工作拖住，所以不满足目标。

## Full Snapshot Repair Policy

允许 full snapshot 的场景：

- cold start 后没有任何可用 read model。
- projection generation 与底层主表不可恢复地冲突。
- coordinator 多次 scoped repair backoff 后仍不能收敛。
- 用户显式打开诊断/日志/修复入口。
- 测试或开发需要构造完整系统观测。

full snapshot 完成后：

- 不能直接替换所有长期状态。
- 必须拆成 app/window/space facts 后进入 reconciliation。
- 只能更新受影响 projections。
- 如果用户已经进入 window/search 状态，不能用过期 full snapshot 覆盖当前交互状态。

## AX Notification 策略

AX notification 不是绝对可靠的系统权威事件源，但很适合作为 dirty signal。

原则：

- 收到 AX app/window changed：标记对应 app dirty。
- 收到已知 AX window destroyed：定位关联 `CGWindowID`，清除 current attachment，保留 sticky evidence，标记 affected window dirty。
- 收到无法识别的 destroyed：退回 app dirty，不猜测删除哪个 record。
- AX 空列表：进入 transient retry，不直接清空窗口。
- AX notification 缺失：由 periodic stale repair 和 Space/CG diff 补漏。

不依赖 AX notification 保证：

- 所有窗口变化必达。
- 通知顺序完全可靠。
- destroyed 一定携带可识别 window element。
- AX tree 永远不会短暂为空。

## 删除与失效

### pid terminated

- 取消该 pid pending/in-flight requests。
- 清空该 pid 的 `RuntimeWindowRecord` 状态。
- 移除 AX live registry 条目。
- rebuild affected projections。

### known AX destroyed

- 清除 current AX attachment。
- 删除当前 `AX -> CG` / `CG -> AX` 派生索引。
- 保留历史 exact/sticky evidence。
- 标记 record needs reconciliation。
- 如果之后 CG/Space 也持续缺席，进入删除 grace。

### Space removed/changed

- invalidates matching `spaceRecovery` evidence。
- 标记 affected `CGWindowID` dirty。
- 不直接删除 record。

### continuous absence timeout

只有 AX、CG、Space 三层证据在 grace window 内持续缺席，才删除 record。

## Surface Ownership

### Switcher

Switcher 负责：

- 面板生命周期。
- app/window/search interaction state。
- 读取 runtime projections。
- 发送 selected/current/search dirty signal。
- 执行用户提交 activation。

Switcher 不负责：

- 自己维护 Space topology diff。
- 自己维护 AX retry/backoff。
- 自己维护 window identity 主表。
- 打开面板时同步跑 full snapshot。

### Home

Home 负责：

- 展示 app summaries。
- 展示 selected app 详情。
- 把 visible/selected scopes 反馈给 runtime scheduler。

Home 不负责：

- 为 Switcher 维护窗口真相。
- 自己扩张 AX/Space reconciliation 状态机。

### Runtime infrastructure

Runtime infrastructure 负责：

- source input adapters。
- `RuntimeReadModelStore`。
- `RuntimeMaintenanceScheduler`。
- reconciliation coordinator。
- projection builders。
- activation verification writeback。

## 当前实现迁移说明

当前代码已经有一部分目标地基：

- CG-first `RuntimeWindowRecord` 主表。
- `RuntimeSpaceTopologySnapshot` / `RuntimeSpaceTopologyDiff`。
- `RuntimeSpaceTopologyProviding`。
- `RuntimeReconciliationCoordinator`。
- app-local affected `CGWindowID` pullback。
- verified-focus target/readback 写回。
- public AX state 参与匹配。
- `RuntimeReadModelStore` Phase 1 P0 已作为 runtime-owned projection cache 边界落地：`RuntimeProjectionService` 持有 store，repair/maintenance 返回数据时会提交 app switcher、Home summary、current-app window projection；app lifecycle、AX/window dirty、Space topology 和 activation verified signals 会写入 generation/dirty/pending repair metadata。
- `RuntimeReadModelStore` 现在也维护 `RuntimeAppDirectoryState`：该 runtime-owned state 类型拥有 PID-keyed replace/upsert/remove、same appID scoped pruning 与 projection derivation 规则。full repair 与 current-app repair payload 会携带 `RuntimeAppDirectoryEntry` evidence，store 在提交 app-switcher/current-app projection 的同一事务里写入 app directory state，并在 `readAppDirectoryProjection()` 时从该主表派生 `RuntimeAppDirectoryProjection` 与 generation/freshness/dirty metadata。app directory 因此不再只是 repair-provider builder 的局部 grouping helper 或一份 projection cache；但 entries 仍来自 repair/fallback/lifecycle evidence，尚未升级为独立长期 fact source。
- full repair payload 现在把完整 filtered running-app `RuntimeAppDirectoryEntry` evidence 显式交给 `RuntimeFullRepairProjectionPayload`，再由 `RuntimeProjectionService` 提交到 store；app directory projection 不再从已筛选的 app-switcher rows / current-app payload 反推，因此被 app-layer 过滤掉但仍属于 runtime app directory 的 running app evidence 不会在 full repair commit 时丢失。
- app launch lifecycle signal 现在会把 `NSRunningApplication` 派生的 `RuntimeAppDirectoryEntry` 随 dirty signal 写入 `RuntimeReadModelStore` 的 app directory state；repair 尚未完成时由该 state 派生出的 projection 仍携带 dirty/stale freshness metadata，不会被命名为 fresh/complete。
- app directory state 现在只接受显式 app directory evidence：`RuntimeReadModelStore.commitAppSwitcherProjection(...)` 必须显式传入 `appDirectoryEntries` 或显式 `nil`，显式 `nil` 不会从 `contextsByID` 合成或替换 directory；`RuntimeFullRepairProjectionPayload` 则必须显式传入 full repair directory entries 或显式空 evidence，不能从 contexts 反推。full repair / current-app repair / lifecycle signal 必须显式携带 directory evidence 才能通过 `RuntimeAppDirectoryState` 更新 directory state。
- current-app projection payload direct boundaries now also require explicit app directory evidence: `RuntimeCurrentAppWindowProjectionAssemblyInput(...)` and the direct `RuntimeCurrentAppWindowPayload(summary:candidate:context:...)` initializer must pass `appDirectoryEntries`, and no longer synthesize `RuntimeAppDirectoryEntry` from `runningApp` / `context.runningApp` defaults. Full/current-app repair builders may still derive entries through the ranked app/appGroup assembly input, but fixture, recency rewrite, and scoped payload callsites must either carry explicit entries or spell explicit empty evidence.
- `RuntimeFullRepairProjectionAssembler` 必须接收显式 `appDirectoryEntries` 参数，省略时只代表明确空 evidence，且不会从 current-app payloads / projection inputs 合成 directory evidence；assembler 只排序 app rows 与 contexts，完整 app directory 必须由 full repair fact collection 显式传入。
- app termination lifecycle signal 现在在 committed app directory state 存在同 appID 多 PID entries 时以 directory entries 作为 authoritative pid scope：terminated PID 只会从 app directory state 中剪掉，app-switcher/Home/Search committed projection 会保留 grouped app 并标记 dirty/stale/pending repair。此时 Search 只能返回 last committed index 的 `degradedStaleCommittedResult` / stale committed read 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed；只有最后一个 surviving PID termination 才删除 grouped app projection 与 committed Search entry。
- `RuntimeReadModelStore.commitCurrentAppWindowProjection(_:)` 现在在同一 store transaction 内同步维护 current-app、app-switcher 与 Home summary projection，并从既有 Home/app-switcher projection 作为 base 后 upsert repaired summary；scoped current-app payload 不再只刷新 window/detail 投影后让 Home summary 依赖 surface fallback 派生，也不会把单 app repair 暴露成完整 Home list。
- Space topology signal、runtime repair-provider full repair builder 与 current-app projection payload builder 现在都通过 `collectCGWindowsWithSpaceTopologyDiff` 消费 provider 记录的 `RuntimeSpaceTopologyDiff`，并把 `affectedCGWindowIDs` 写入 `RuntimeReadModelStore` 的 dirty/freshness metadata；旧 `collectCGWindowsByPID` 兼容包装已删除。
- `RuntimeCurrentAppWindowPayload` 现在拥有 app-window projection seed 到 Home summary、app-switcher candidate、`RuntimeAppContext` 的组装规则；repair-provider 的 `currentAppWindowPayload(for:)` 与 `focusedCurrentAppWindowPayload(processIdentifier:)` 直接产出 current-app projection payload，`RuntimeAppWindowReconciliationResult` 直接携带 `currentAppWindowPayload`，`RuntimeProjectionService` drain 只消费 projection payload，不再接触 repair-shaped result 或维护 snapshot/repair-shaped conversion helper。
- scoped repair 遇到 transient empty current-app payload 时，`RuntimeProjectionService.ReconciliationExecutionOutcome.transientEmptyCurrentAppWindowPayload` 会进入 `RuntimeReconciliationCoordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(...)`；service/coordinator retry 边界不再暴露 AX snapshot-shaped outcome 名称。
- `RuntimeProjectionPayloads.swift` 现在承载 runtime-owned projection payload 类型与 production assembly 入口：`RuntimeFullRepairProjectionPayload`、`RuntimeAppContext`、`RuntimeAppWindowProjectionSeed`、`RuntimeCurrentAppWindowPayload` 与 `RuntimeCurrentAppWindowProjectionAssemblyInput`。`RuntimeAppWindowProjectionSeed` conversion、`RuntimeCurrentAppWindowProjectionAssemblyInput` 的 app/display/rank/group/timestamp 派生，以及 summary/candidate/context payload fact assembly 都在该 payload 边界；`RuntimeFullRepairProjectionAssembler` 只负责 current-app assembly input / current-app payload 到 full-repair payload 的 sorting 与 context map assembly；app grouping、primary selection、stats/rank sorting、preferred rank 与 app-layer eligibility/filtering 规则属于 `RuntimeAppDirectory.swift` 的 `RuntimeAppDirectoryEntry` / `RuntimeAppDirectory` / `RuntimeAppLayerProjectionFilter`。迁移期 `RuntimeFullRepairProjectionAssembly*` DTO 与 `assembleRows(...)` testing seam 已删除，provider builder 文件不再拥有或依赖这些 payload/assembly testing API。
- `RuntimeCurrentAppWindowPayload` 不再暴露 `app` / `appGroup` / rank convenience initializer，seed-to-summary/candidate/context initializer 也已降为 private；`RuntimeProjectionRepairProvider` current-app builders 必须先显式构造 `RuntimeCurrentAppWindowProjectionAssemblyInput`，再交给 payload 组装 summary/candidate/context。app/display/rank/group/timestamp 与 projection seed 派生入口因此只剩 assembly input，payload 边界不再形成第二个事实派生入口；已组装的 summary/candidate/context initializer 只保留给 recency rewrite 与 fixture seeding，不参与 seed 派生。
- runtime repair-provider full repair builder 现在只把 sampled app、rank 与 top-level `RuntimeWindowListEntry.projectionSeed(lastActiveAt:)` 事实交给 `RuntimeCurrentAppWindowProjectionAssemblyInput`，再交给 `RuntimeFullRepairProjectionAssembler.payload(fromCurrentAppWindowProjectionInputs:)` 组装 `RuntimeCurrentAppWindowPayload`、app-switcher candidate 排序与 `contextsByID`；assembler 的 direct current-app payload helper 已降为 private，生产调用入口不能绕过 assembly input。`fullRepairProjectionPayload()` 与其 private full-repair `collectWindowData(for:)` 聚合入口已迁到 `RuntimeProjectionRepairProvider+ProjectionBuilders.swift`，通过组合的 `RuntimeSnapshotProvider` 读取底层 CG/AX/Space facts；provider core 文件只保留底层 CG/AX/Space 采样与窗口事实基础设施。
- `RuntimeProjectionRepairProvider+ProjectionBuilders.swift` 内 full repair / current-app projection payload builder 的 timing、filtering 与 app-row diagnostics 现在写入 `RuntimeLogCategory.projection`；`RuntimeSnapshotProvider.swift` 底层 CG/AX/Space fact collection 才继续使用 snapshot diagnostic category。
- `RuntimeProjectionRepairProvider+Reconciliation.swift` 现在承载 app affected-target derivation 与 app-window reconciliation result assembly；`RuntimeProjectionService.swift` 只保留 repair provider protocol、默认 facade wiring、read-model store ownership、scheduler drain 与 commit/freshness 条件，不再直接实现 repair-provider 的 WindowRecord/payload 组装细节。
- `RuntimeAppWindowRepairPayload` 类型级 app-window repair 兼容 wrapper 已删除；provider 只把采样事实转换为 `RuntimeAppWindowProjectionSeed` 并产出 `RuntimeCurrentAppWindowPayload`，不再私有维护 candidate/context/summary projection assembly，也不再保留 repair-shaped current-app projection 上游。
- app identity 规则现在直接由 `RuntimeAppIdentity.appID(for:)` / `groupID(for:fallbackName:)` 服务 AppDelegate lifecycle、Switcher focused-current-app projection、repair-provider full repair grouping input、reconciliation target、UI-test runtime projection seed 与 groupID projection assembly；`RuntimeAppDirectoryEntry` / `RuntimeAppDirectory` 负责 app grouping、primary app selection、app stats/rank sorting、preferred rank、stable last-active、app-layer nested/zero-window suppression、app-window stats derivation、group 内 window merge 和 app-window stats based candidate filtering，`RuntimeAppLayerProjectionFilter` 负责 running-app include 与 minimized/empty-window app-layer include 规则。repair-provider full/current-app projection builders 都委托该 runtime-owned filter 判断 app-layer eligibility/minimized-only current-app payload，不再内联 app-layer include 条件；provider `filterAppsForAppLayer(...)` adapter seam 已删除，full repair builder 直接调用 `RuntimeAppDirectory.windowStats(...)` 与 `filterAppLayerCandidates(...)`。`RuntimeSnapshotProvider.baseAppID(for:)`、`groupID(for:)`、`groupIDForTesting(...)`、`selectPrimaryApps(...)`、provider-owned app scoring/stable-last-active helper、provider-owned app grouping/window merge extension、assembler-owned deterministic app scoring、`shouldIncludeRunningApplication(...)`、`shouldIncludeAppInAppLayer(...)`、nested app suppression helper 与 provider-owned `AXWindowStats` wrapper 已删除或降级为 runtime-owned 类型/委托调用，provider 和 assembler 不再拥有 app identity / app directory 派生入口。
- `RuntimeCGWindowEntry` / `RuntimeCGWindowCollection` 已迁入 `RuntimeCGWindowFacts.swift`，由 runtime CG fact payload 文件承载而不是定义在 `RuntimeSnapshotProvider.swift` provider core 中；CG validity constraints 也由 `RuntimeCGWindowFacts.passesValidityConstraints(_:)` 拥有，provider supplemental CG merge、exact AX/CG assignment、activation readback/visibility 与 Chrome target-ordinal filtering 不再通过 `RuntimeSnapshotProvider` 命名空间读取该 fact 规则；`RuntimeWindowRecord` 的 CG state refresh、exact-match CG attachment 与 synthesized known-CG evidence API 现在直接使用 top-level `RuntimeCGWindowEntry`；provider window-mapping resolution、known-CG synthesis、fullscreen artifact filters 与 AX recovery diagnostics 也已改为 top-level `RuntimeCGWindowEntry`。生产代码和 deterministic tests 不再通过 `RuntimeSnapshotProvider.CGWindowEntry` / `CGWindowCollection` 嵌套名表达 CG fact ownership；迁移期 typealias 与 `CGWindowEntryForTesting` 已删除，provider testing helpers 也直接接收 top-level `RuntimeCGWindowEntry` fixtures。
- `RuntimeAXWindowEntry` 现在与 `RuntimeAXWindowState` / `RuntimeCurrentAXAttachment` 一起由 `RuntimeWindowRecord.swift` 承载，作为 production AX window fact payload；provider internals、WindowRecord exact-match AX attachment、window mapping/recovery helpers、activation public-AX recovery 与 deterministic fixtures 都直接使用 top-level `RuntimeAXWindowEntry`。生产路径已删除 `RuntimeSnapshotProvider.AXWindowEntry` 嵌套 fact 类型；`AXWindowEntryForTesting` 也已删除，provider testing helpers 直接接收 top-level `RuntimeAXWindowEntry` fixtures，测试期 private exact bridge evidence 通过显式 `exactBridgeMatches` 输入表达。
- `RuntimeWindowAssignmentMatcher.swift` 现在承载 AX/CG public assignment 规则、public AX focused/main/minimized tie-breaker 与 ambiguous diagnostics；provider stable window mapping 与 `RuntimeAXWindowRecovery` 都调用该 runtime-owned matcher，不再通过 `RuntimeSnapshotProvider.matchCGWindowAssignments*` 命名空间表达 assignment ownership。
- `RuntimeAXWindowRecovery.swift` 现在承载 public AX recovery 决策、exact bridge/public-assignment fallback 与 recovery diagnostics；`RuntimeActivator` 直接调用 `RuntimeAXWindowRecovery.recoverAXWindowFromPublicSourcesWithDiagnostics(...)`，provider 不再拥有 public-AX recovery helper API。activation 成功证明仍必须回到 focused AX/CG readback，不以 recovery helper 返回值作为成功 oracle。
- `RuntimeActivator` 的 activation readback、target visibility、CG-only / same-Space route helpers 和 test override seam 现在也直接使用 top-level `RuntimeCGWindowEntry`；activation 成功证明仍来自 selected `CGWindowID` / focused AX/CG readback，而不是 provider-nested snapshot fact 命名。
- `RuntimeChromeWindowFocusBridge` 的 Chrome candidate selection / target-ordinal tie-break helpers 现在也直接接收 top-level `RuntimeCGWindowEntry`；Chrome-style activation 辅助路径不再把 current CG fact 输入表达成 `RuntimeSnapshotProvider` namespace。
- `RuntimeProjectionService` 现在只持有 `RuntimeProjectionRepairProviding` 窄接口：service 可以调度 coordinator、读取 CG/Space fact diff、消费 current-app/full-repair projection payload、记录 verified focus/AX destroyed evidence，但不再以完整 `RuntimeSnapshotProvider` 作为自身依赖或 executor 类型边界。默认 service wiring 进入 runtime-owned `RuntimeProjectionRepairProvider` facade；该 facade 组合底层 `RuntimeSnapshotProvider` fact source，`RuntimeSnapshotProvider` 本身不再直接 conform service repair protocol。CG fact payload 也已抽为 top-level `RuntimeCGWindowEntry` / `RuntimeCGWindowCollection` 并由 `RuntimeCGWindowFacts.swift` 承载，provider internals 与 tests 也直接使用 top-level CG fact 类型；`RuntimeSnapshotProvider` 只能作为底层 fact-source/repair bridge 存在，不能被 feature surface 当作 hot-path snapshot read seam 重新扩张。

但当前实现仍有迁移对象：

- service 层 `RuntimeProjectionService.fallbackRuntimeSnapshot()` full snapshot bridge 与 concrete-only `fallbackLightweightAppSnapshot()` lightweight bridge 均已删除；`RuntimeProjectionServing` 已不再暴露 full snapshot bridge、同步 lightweight bridge 或 `currentCGWindowsByPID()` live CG z-order read，Switcher/Home 的 P0 首读路径已优先读取 projection，`Option+Tab` 缺 app-switcher projection 时只请求 shared runtime maintenance，不再同步调用 lightweight snapshot bridge；`Control+Tab` 缺 current-app projection 时只发送 runtime dirty/repair signal，不再同步调用 focused snapshot bridge。service-facing focused snapshot 兼容入口已删除，repair-provider app-local reconciliation pullback 现在直接返回 `RuntimeCurrentAppWindowPayload`；provider-facing `appWindowRepairPayload` / `focusedAppWindowRepairPayload` 兼容 API 与 `RuntimeAppWindowRepairPayload` 类型级 wrapper 已删除。
- `RuntimeSnapshotProvider.snapshot()` wrapper 已删除；full repair 现在只通过 `RuntimeProjectionRepairProvider+ProjectionBuilders.swift` 内的 `fullRepairProjectionPayload()` 枚举 running apps 并进入同文件的 private `collectWindowData(for:)` full-repair 聚合入口，其内部会通过底层 provider fact source 取 onscreen/all CG 和 AX window data。该路径性质是 scheduler repair/fallback，不是 hot-path read。
- Phase 3 P0 已移除 Switcher session-start 后的 surface-owned background full snapshot delayed/apply path；`LiveSwitcherModel` 只向 `RuntimeProjectionService.requestAppSwitcherProjectionMaintenance(reason:)` 发送 runtime maintenance request，旧 full snapshot bridge 不再由 Switcher open 后台路径调用。
- Search 已迁移到 maintained `committedSearchIndex` read，runtime maintenance 在 internal `stagingSearchIndex` 验证通过后再原子提交；真实 committed/staging UI proof 与外部 pressure proof 仍是 gap。
- `RuntimeSearchIndexRead` 现在拥有 Search read 的 result-state 命名：`currentGenerationCommitted` 对应 `verifiedCurrentGenerationCommittedResult`，`staleCommitted` 对应 `degradedStaleCommittedResult`，`missingCommittedIndex` 对应缺 committed index；Switcher 只消费该 runtime-owned contract，不再在 surface 层自行解释 stale/fresh/complete 状态。
- Search freshness barrier 的 runtime drain 现在会在 runtime coordinator 内把 pending/waiting retry repair 提升为 high-priority `searchFreshnessBarrier` request，然后按固定 ready-repair batch bound 执行；超过该 batch 或出现 deferred/pending repair 时，service 只保留 last committed index 的 stale/degraded read，不提交 staging index，也不把部分 repair 结果提升为最新搜索结果。
- Search staging 的 scoped repair 输入由 `RuntimeReadModelStore.stageSearchIndexCurrentAppWindowPayloads(_:)` 消费 repaired current-app projection payload；`RuntimeProjectionService` 只负责 barrier drain 和 commit 条件，不再手动从 repair/current-app payload 中挑 app candidate 维护 staging index。
- Space topology 生产路径已有 snapshot/diff 与 display-level signature；`collectCGWindows` diagnostic 已输出 signature change/display/space/window summary，`RuntimeProjectionService.signalSpaceTopologyChanged()` 会把 diff 的 affected `CGWindowID` 同步写入 read-model dirty metadata 并驱动 scoped repair，代表性 noisy fullscreen fixture UI 已断言 signature diagnostic。系统权威 fullscreen owner、多显示器与更广真实拓扑 pressure 仍需继续推进。

## 迁移阶段

### Phase 1: Store 与 projection 边界

状态（2026-06-16）：P0 已落地；P1 的 priority / coalescing / promoted backoff bypass 已落地；P2 保留。

- 引入或扩展 `RuntimeReadModelStore`。
- 明确主表、派生索引、projection cache。
- 给每个 projection 增加 freshness/confidence/dirty metadata。
- 保留现有 snapshot API 作为兼容入口。

已落地的 P0：

- 新增 `RuntimeReadModelStore`，集中维护 `appSwitcherProjection`、`homeSummaryProjection`、`currentAppWindowProjection`、generation、dirty app/pid/CGWindowID 与 pending repair scope metadata。
- `RuntimeReadModelStore` 集中维护 `RuntimeAppDirectoryState`，full/current-app repair payload 中的 app directory entries 会随 projection commit 写入该 PID-keyed state，并在 app/window dirty、app termination 与 read diagnostics 中派生出 freshness/generation-bearing `RuntimeAppDirectoryProjection`。
- full repair commit 使用完整 filtered running-app directory entries，scoped current-app commit 只 upsert affected app group 的 directory entries，避免把 app-switcher projection 行当成 app directory 主表。
- app launch signal 使用 runtime service API 携带 app directory entry；store 会在标记 app lifecycle dirty 的同一事务里通过 `RuntimeAppDirectoryState` upsert PID-keyed directory entry，并保持 pending repair scope / dirty metadata。
- app-switcher projection commit 与 full-repair payload 初始化已删除 context-derived app directory fallback；store commit callsite 必须用显式 `nil` 表达没有 directory evidence，此时不会创建或替换 app directory state，避免把 app-switcher/context 兼容桥重新升级为 directory fact source。
- `RuntimeFullRepairProjectionAssembler` 已删除 current-app payload derived app directory fallback；没有显式 full-repair app directory entries 时 assembler 产物保持空 directory evidence，避免把 scoped current-app projection inputs 升级成 full app directory 主表。
- app termination signal 在 `RuntimeAppDirectoryState` 有同 appID 多 PID entries 时只剪掉 terminated PID 的 directory entry，并保留 grouped app、Home summary 与 committed Search index 为 degraded/stale committed projection；dirty metadata 与 `appTerminated:<appID>` repair scope 会驱动后续 scoped repair，重复 terminated-PID signal 不会推进 generation。
- `RuntimeProjectionService` 成为 read model store owner；旧 provider 采样桥只负责生成兼容数据，service 负责提交 projection 或标脏 metadata。
- `RuntimeProjectionServing` 暴露 projection read seam：`readAppSwitcherProjection()`、`readHomeSummaryProjection()`、`readCurrentAppWindowProjection(appID:)` 与 `runtimeReadModelDiagnostics()`，供 Phase 2 迁移 hot-path read API。
- app/window dirty、app launch/termination、AX destroyed、Space topology、activation verified-focus signal 均会进入 store generation/dirty metadata，避免 Switcher、Home、Search 各自扩张 surface-local freshness state。

仍保留的 P1/P2：

- projection builders 仍由旧 snapshot/home/focused 兼容桥提交，尚未完全从底层 `RuntimeWindowRecord`、app directory、Space topology 主表独立 rebuild。
- PID-keyed app directory state 已作为 `RuntimeAppDirectoryState` 进入 runtime-owned app directory boundary，并由 `RuntimeReadModelStore` 持有；app launch lifecycle signal、同 appID 多 PID termination scoped pruning 和 full/current-app repair payload 都会显式走 app directory entries，context-derived fallback 已删除，`RuntimeAppDirectoryProjection` 只作为 read 派生物存在；但 directory entries 仍未升级为独立长期 fact source，从 WindowRecord/app directory/topology 主表直接 rebuild projection 仍是 Phase 5 gap。
- Switcher/Home 首帧只读 projection 的 P0 已在 Phase 2 落地；旧采样桥仍作为 service-owned repair/fallback 兼容入口，不是目标热路径。
- Search committed/staging index 已在 Phase 4 落地到 `RuntimeReadModelStore` ownership；Phase 1 的剩余 gap 不再是 Search index 缺失，而是 projection builders 尚未完全从底层 `RuntimeWindowRecord`、app directory、Space topology 主表独立 rebuild。

验证：

- deterministic tests 证明主表与派生索引一致。
- projection rebuild 不依赖 feature surface 局部状态。
- `FlowTabPriorityCoverageTests.testRuntimeReadModelStoreCommitsProjectionsAndMarksDirtyMetadata` 证明 store commit/read、generation、dirty metadata 与 current-app projection scope。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals` 证明 service owns store，旧 repair bridge 会提交 app projection，dirty signal 会标脏 projection metadata。

### Phase 2: Hot path read API

状态（2026-06-16）：P0 已落地，P1/P2 保留。

- 新增 `readAppSwitcherProjection()`。
- 新增 `readCurrentAppWindowProjection(appID/pid)`。
- Search read 在 Phase 2 保持 deferred，后续由 committed/staging search index 边界承接，不能成为第二个 runtime store。
- 新增 Home summary/detail projection read。
- 这些 read API 不进入 sampling queue，不触发 CG/AX/Space 采样。

已落地的 P0：

- `LiveSwitcherModel` 的 app-layer fast snapshot 只读取 `RuntimeAppSwitcherProjection`；projection 存在时不会调用 `lightweightAppSnapshot()` 或全量 snapshot provider，projection 缺失时返回空首帧并请求 shared runtime projection maintenance。
- Switcher terminate refresh 不再读取 full snapshot bridge；`RuntimeReadModelStore.markAppTerminated` 会同步从 committed app-switcher projection 和 committed search index 移除 terminated app，Switcher 只读取更新后的 projection，projection 缺失时只请求 shared runtime maintenance 并保留当前 session。Session/Search behavior tests now prove this through `RuntimeProjectionServing` projection-read counters, runtime maintenance/termination signals, and committed Search read diagnostics instead of dead full/lightweight snapshot counters.
- `RuntimeProjectionServing` 已不再向 feature surface 暴露泛化的 `snapshot()` 方法或 full snapshot bridge。`RuntimeSnapshotProvider.snapshot()` wrapper 已删除；provider full builder / repair primitive 是 `fullRepairProjectionPayload()`。
- `RuntimeProjectionServing` 已不再向 feature surface 暴露同步 `lightweightAppSnapshot()` 方法；`RuntimeProjectionService.fallbackLightweightAppSnapshot()` 和 provider `lightweightAppSnapshot()` 已删除，feature surface 只能读 app-switcher projection 或发送 runtime maintenance signal。
- `RuntimeProjectionServing` 已不再向 feature surface 暴露 Home provider-backed refresh bridge；Home summary/detail refresh 只能读取 Home/current-app projection 或 app-switcher projection，projection 缺失时返回当前 committed UI state 并发送 shared runtime maintenance/app-window dirty signal。
- selected/current app window refresh 只读取 `RuntimeCurrentAppWindowProjection`；projection 存在时不会调用 Home snapshot bridge，projection 缺失时只向 shared runtime 发送 app-window dirty signal 并保持 app-cycle 投影状态。
- Home window activation 使用调用方传入的 cached detail projection 或 `RuntimeCurrentAppWindowProjection` 构造 activation target；缺 projection 时只向 shared runtime 发送 app-window dirty signal，不再同步调用 Home snapshot bridge。
- 迁移期 `RuntimeProjectionServing.homeAppSnapshotSynchronously` 兼容入口已删除；生产 surface 无法再通过 shared runtime service 重新引入该同步 Home snapshot bridge。
- `Control+Tab` focused-current-app startup 只读取 `RuntimeCurrentAppWindowProjection`；projection 存在时不会调用 provider repair pullback，projection 缺失时只向 shared runtime 发送 app-window dirty signal 并降级退出。
- 迁移期 focused snapshot 兼容入口已从 `RuntimeProjectionServing` 删除；生产 surface 无法再通过 shared runtime service 重新引入该同步 focused snapshot bridge。
- `LiveSwitcherModel` startup recency 不再读取 live focused AX 或 live CG z-order；`Option+Tab` / `Control+Tab` 仅应用 committed `RuntimeWindowRecencyTracker` evidence 和 projection order，`RuntimeProjectionServing` 也不再向 feature surface 暴露 `currentCGWindowsByPID()`。
- Home initial summary projection、summary refresh、single-app summary、selected app detail 通过 `HomeRuntimeProjectionReader`/`HomeRuntimeRefreshReader` 读取 projection，Home refresh diagnostics 使用 `RuntimeLogCategory.projection`；projection 缺失时不再调用旧 Home snapshot service，concrete `RuntimeProjectionService` 的 provider-backed Home fallback bridge 已删除。
- Home activation / projection reader behavior tests now name their injected `RecordingRuntimeProjectionService` fixtures `runtimeProjectionService`; the test double no longer carries Home snapshot fallback recorders or Home summary request counters, and `FlowTabTests+HomeWindowActivation` now proves the old Home bridge absence through Home/app-switcher/current-app projection-read counts plus dirty-signal behavior instead of dead full/lightweight snapshot counters.
- `FlowTabPriorityCoverageTests+SessionAndPanelSearch` no longer uses full/lightweight snapshot fake counters as proof for Search/session paths. App search and window search tests assert `readCommittedSearchIndexForSearch()` diagnostics (`currentGenerationCommitted` / `verifiedCurrentGenerationCommittedResult` / no freshness-barrier request), app-layer panel tests assert `readAppSwitcherProjection()` plus shared maintenance, and focused-window panel tests assert `readCurrentAppWindowProjection()` plus no selected-current-app dirty signal.
- Preview paging/session-pinning/provider behavior tests now use the shared `makeAppSwitcherProjectionModel` helper with a `runtimeProjectionService` return label and assert app-switcher projection reads plus `.switcherSessionStarted` maintenance requests. The `WindowPreviewSessionPinning` coverage and terminal provider resolver coverage no longer treat dead full/lightweight snapshot request counters as service ownership proof.
- `RuntimeAppSwitcherProjection.appCycleApps` 与 `RuntimeHomeSummaryProjection.summary(for:)` 作为 shared projection helper，避免 surface 复制 app-cycle projection assembly 或 summary lookup 状态。

仍保留的 P1/P2：

- Search hot-path read 已由 Phase 4 的 committed/staging index 和 readiness-bearing `readCommittedSearchIndexForSearch()` 承接；不再新增 surface-facing `readSearchWindowProjection()`，避免 Search 成为第二个 runtime store。
- Switcher session-start background full snapshot 已在 Phase 3 P0 降级为 runtime-owned projection maintenance request；priority/coalescing/cancellation/backoff breadth 仍留给 Phase 3 P1/P2。
- 本阶段新增的是 behavior/pressure 证明；真实 UI/E2E 拓扑 proof 沿用既有 fixture 覆盖，未新增专门的 projection-read UI 断言。

验证：

- targeted unit/behavior 证明 hot read 不调用采样 provider。
- pressure proof 记录 `Option+Tab` / `Control+Tab` 首帧不被后台 maintenance 阻塞。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelStartsAppSessionFromRuntimeProjectionWithoutLightweightSampling` 证明 app switcher projection 存在时读取 committed app-switcher projection，且在 maintenance disabled fixture 下不会发送 surface-local repair request。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelSelectedAppWindowSnapshotUsesRuntimeProjectionWithoutHomeSampling` 证明 selected/current app window projection 存在时不会调用 Home snapshot bridge；`testLiveSwitcherModelSelectedAppWindowSnapshotSignalsRuntimeRepairWhenProjectionIsMissing` 证明 projection 缺失时即使旧 Home snapshot bridge 有污染数据也不会被读取，只会发送 shared runtime app-window dirty signal。
- `FlowTabTests.testHomeWindowActivationControllerUsesRuntimeProjectionWithoutHomeSnapshotBridge` 证明 Home window activation 读取 runtime current-app window projection 后提交 activation target，且不会发送 app-window dirty signal；`testHomeWindowActivationControllerSignalsRuntimeRepairWhenProjectionIsMissing` 证明 projection 缺失时只读取 current-app/app-switcher/Home summary projection 边界以定位 pid，然后发送 shared runtime app-window dirty signal。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelFocusedWindowSessionUsesRuntimeProjectionWithoutFocusedSampling` 现在用 current-app projection read count 与 no selected-current-app dirty signal 证明 `Control+Tab` focused-current-app projection 存在时只读 committed projection；`testLiveSwitcherModelFocusedWindowSessionSignalsRuntimeRepairWhenProjectionIsMissing` 证明 projection 缺失时只读一次 current-app projection 并发送 shared runtime app-window dirty signal。这两个 focused session tests 不再用 dead snapshot counters 作为 focused snapshot bridge absence 的主证明。
- `FlowTabPriorityCoverageTests.testSwitcherPanelControllerDelayedAutoEnterUsesCommittedSelectedAppProjection` 现在用 app-switcher projection read count、`.switcherSessionStarted` maintenance request、delayed current-app projection read count 与 no selected-current-app dirty signal 证明延迟进入 window layer 只消费 committed selected-app projection，不再用 full/lightweight snapshot fake counters 作为旧路径反证。
- `FlowTabPriorityCoverageTests.testAppDelegateReloadedHotkeyMonitorRoutesCallbacksToSwitcherSession` 现在用 app-switcher / current-app projection read counts、`.switcherSessionStarted` maintenance request 与 no selected-current-app dirty signal 证明 reloaded `Option+Tab` / in-app window hotkey callbacks 进入 projection-owned session startup，而不是用 full/lightweight snapshot fake counters 作为主证明。
- `FlowTabPriorityCoverageTests.testAppDelegateLaunchOpenSwitcherWaitsForStableProjectionBeforeKeepingPanelOpen` / `testAppDelegateLaunchOpenSwitcherWithoutResultsDoesNotEnterSearchAndSeedZeroSkipsSeededLogs` 现在用 app-switcher projection read counts、`.switcherSessionStarted` maintenance reasons 与 no committed Search index read 证明 launch-open-switcher bootstrap 只读 committed app-switcher projection，空 projection 不进入 Search，也不把 full/lightweight snapshot fake counters 当主证明。
- `FlowTabTests.testHomeRuntimeProjectionReaderUsesRuntimeProjectionsWithoutSnapshotBridge` 证明 Home summary/detail reader 读取 Home summary projection 与 current-app projection，不回退到 app-switcher projection 或 lightweight snapshot；`testHomeInitialAppSummaryReaderDoesNotUseLightweightSnapshotFallback` 证明 initial reader 只读 Home summary/app-switcher projection，missing projection 时返回空且不请求 maintenance；`testHomeRuntimeProjectionReaderDerivesHomeDataFromAppSwitcherProjectionWithoutSnapshotBridge` 证明 Home 可从 app-switcher projection 派生 summary/detail；`testHomeRuntimeRefreshReaderSignalsRuntimeRepairWhenProjectionIsMissingWithoutHomeFallback` 证明 projection 缺失时污染的 Home fallback 数据不会被读取，只发送 shared runtime maintenance/app-window dirty signal 并保留当前 committed UI state。
- `FlowTabPriorityCoverageTests.testRuntimeReadModelStoreRemovesTerminatedAppFromCommittedProjectionsAndSearch` 证明 terminated app lifecycle signal 由 `RuntimeReadModelStore` 幂等地同步剪掉 committed app-switcher projection 与 committed search index；`FlowTabTests.testHandleApplicationTerminatedRefreshesFromRuntimeProjectionWithoutFullSnapshot` 证明 Switcher termination refresh 只消费 runtime app-switcher projection、shared maintenance/termination signal 与 committed Search read diagnostic；`FlowTabPriorityCoverageTests.testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterAutomaticTerminationRefresh` 现在用 app-switcher projection read count 与 termination signal 证明 panel refresh path，而不是 full/lightweight snapshot fake counters；`FlowTabPriorityCoverageTests.testLiveSwitcherModelHandleApplicationTerminatedRefreshesSessionAndKeepsPreferredNextSelection` / `testLiveSwitcherModelHandleApplicationTerminatedIgnoresUntrackedApp` 进一步用 model-level app-switcher projection read counts 与 termination signal/no-signal evidence 证明 app termination refresh 和 unrelated termination ignore path 都不把旧 snapshot counters 当主证明。
- `FlowTabTests.testOptionTabWindowScalePressureKeepsSelectedAppApplyAndPreviewCaptureBounded` 本轮重跑通过，81 apps / 1,000 selected windows / 60 iterations 下 `selectedAppApplyP95=1.46ms`、`enterP95=0.03ms`、`previewItemsP95=0.35ms`、`previewCaptureCalls=360`。
- `FlowTabTests.testOptionTabFastStartPressureStaysUnderHundredMilliseconds` 与 `FlowTabTests.testOptionTabFastStartPressureIgnoresLargeFrontmostWindowSet` 本轮重跑通过，`fullSnapshotCalls=0`，p95 分别为 0.90ms 和 0.61ms。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelGlobalAndFocusedSessionsUseSameSpaceTopologyRuntimeTruth` 现在用 app-switcher / current-app projection read counts 与 no selected-current-app dirty signal 证明 global 与 focused session 共享同一 topology-filtered WindowRecord-derived candidate truth，而不是用 full/lightweight snapshot fake counters 作为主证明。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelAppliesCommittedVerifiedFocusRecencyWithoutLiveFocusedRead`、`testLiveSwitcherModelFocusedRuntimeProjectionUsesCommittedRecencyBeforeOrdering` 和 `testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges` 现在用 app-switcher / current-app projection read counts 与 recency order assertions 证明 committed recency/projection order 已替代 startup live focused AX / live CG z-order sampling，而不是用 dead full/lightweight snapshot counters 作为主证明。
- `FlowTabTests.testControlTabFocusedProjectionFastStartPressureIgnoresFocusedSnapshotBridge` 证明 1,000-window current-app projection 下 `Control+Tab` focused startup p95 为 0.83ms，80 次 startup 均读取 committed current-app window projection，且 projection 存在时不发送 selected-current-app repair dirty signal。

### Phase 3: Scheduler 取代 background full snapshot

状态（2026-06-16）：P0 已落地，P1/P2 保留。

- Switcher open 只读 projection，并标记 selected/current/search scopes。
- background full snapshot 改为 low-priority repair。
- dirty app/window/space 统一进入 scheduler。
- scheduler 支持 priority、coalescing、cancellation、retry/backoff。

已落地的 P0：

- `LiveSwitcherModel` 不再持有 `BackgroundFullSnapshotRefreshRequest`、deferred background full snapshot request、background full snapshot provider override 或 delayed/apply worker。
- `startSession` 的后续维护入口改为 `requestRuntimeProjectionMaintenance(triggerDirection:)`，只调用 `RuntimeProjectionService.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)`。
- `RuntimeProjectionService` 在自己的 `maintenanceQueue` 内处理 app switcher projection maintenance request，读取 store diagnostics、drain 已有 reconciliation requests，并用 `Projection` log category 记录 `runtimeMaintenance` / lifecycle / destroyed-window 信号；不从 Switcher surface 同步或异步拉 full snapshot bridge。
- Switcher 只保留 runtime projection maintenance generation/diagnostic/invalidation，用于取消和日志，不再保存 surface-local full snapshot result 或 repair state。

已落地的 P1：

- `RuntimeReconciliationCoordinator` 已给 dirty reason 建立 scheduler priority：activation verified / app launched / Search freshness barrier / selected-current app windows 为 high，AX notification / Space topology 为 normal，manual refresh 为 low。
- coalesced request 会保留最高 priority；低优先级 request 在 retry/backoff 中收到高优先级 dirty signal 时会提升为 pending、重置 attempt，并绕过旧 retry `notBefore`。
- ready request drain 现在按 priority 优先、同 priority 按 request id 稳定排序；`RuntimeProjectionService.requestAppSwitcherProjectionMaintenance(reason:)` 通过 shared coordinator 顺序 drain ready requests，而不是让 Switcher surface 自己维护 retry/debounce/pending scheduler。
- selected/current app-window 缺 projection 时，Switcher 只发送 `signalSelectedCurrentAppWindowsChanged` dirty signal；`RuntimeProjectionService` 把它映射成 high-priority `selectedCurrentAppWindows` repair request，继续由 shared coordinator drain，不回到 surface-local snapshot/retry。
- full repair fallback 已建模为 low-priority `RuntimeReconciliationTarget.fullRepair`；runtime-owned maintenance 只有在缺 app-switcher projection 且没有 pending scoped repair 时才安排该 target，高优先级 scoped repair 会取消尚未 in-flight 的 low-priority full repair。
- full repair 在 `RuntimeProjectionService` 的 drain/outcome 边界已改为 `RuntimeFullRepairProjectionPayload`，service 不再把 `RuntimeSnapshot` 作为 in-flight repair result 保存或提交；默认 executor 直接调用 runtime repair-provider `fullRepairProjectionPayload()` builder，provider-facing `RuntimeSnapshotProvider.snapshot()` wrapper 与 `RuntimeSnapshot` 类型已删除。
- full repair fallback 提交已分成 clean cold-start 与 dirty degraded fallback：只有没有 app-switcher projection 且没有 dirty/pending repair metadata 时才允许清 dirty 并生成 verified current-generation committed Search index；dirty/pending 状态下的 full repair 只能提交 degraded app-switcher projection，必须保留 dirty/freshness metadata、staging search index 和 last committed Search index，不能把 fallback 结果命名或暴露为 fresh/complete/latest。
- Search freshness barrier 的 promote/drain 明确排除 full repair fallback；barrier 只能完成 bounded scoped repair、由本轮 repaired payload 写入 staging，并提交新 generation 后进入最新搜索结果态。pending full repair 可能被后来的 high-priority scoped repair 取消，但不会被 Search 提升、执行或命名为 fresh/complete/latest。

仍保留的 P1/P2：

- full repair fallback 的 target / high-priority cancellation 已落到 scheduler；scoped repair retry exhausted 后会自动降级安排 low-priority full repair fallback，并且 dirty fallback commit 不会清 dirty 或刷新 committed Search。更广 backoff policy 与更细粒度 facts 拆分仍需扩展。
- service 层 feature-facing full snapshot fallback 已从 `RuntimeProjectionService` 删除；full repair outcome 现在也只携带 `RuntimeFullRepairProjectionPayload`。full repair builder 已命名为 repair-provider `fullRepairProjectionPayload()`，性质是 low-priority repair/diagnostic 或 cold-start 输入；provider-facing `RuntimeSnapshotProvider.snapshot()` wrapper 已删除，不是 Switcher/Home/Search hot-path read API，也不是 Search freshness barrier 的成功 oracle。
- `RuntimeProjectionService` 的 provider 依赖已收窄为 `RuntimeProjectionRepairProviding`，default executor 只通过该 repair/fact-provider contract 消费 scoped repair、Space topology affected-target derivation 与 full repair projection payload。默认 implementation 是 runtime-owned `RuntimeProjectionRepairProvider` facade；测试若需要观察同一个 provider 的 WindowRecord/coordinator state，也必须显式把 `RuntimeSnapshotProvider` 包进该 facade，而不是让 provider 本体 conform service repair protocol。该 contract、provider internals 与 deterministic tests 现在使用 top-level runtime CG fact types，不再暴露 `RuntimeSnapshotProvider.CGWindowEntry/Collection` 嵌套名；迁移期仍保留 `RuntimeSnapshotProvider` 名称作为底层 fact-source/repair bridge，但 service/executor 边界不再拿完整 snapshot provider 类型。
- Search committed/staging index 已在 Phase 4 推进；真实 committed/staging UI proof 与外部 pressure proof 仍需补齐。
- 真实 UI/E2E 与多拓扑 pressure proof 本轮未新增；现有证明是 behavior + deterministic pressure。

验证：

- `FlowTabPriorityCoverageTests.testLiveSwitcherModelStartSessionRequestsRuntimeMaintenanceWithoutSurfaceSampling` 证明 app switcher projection 存在时，`startSession` 通过 app-switcher projection read count 读取 committed projection，并只提交 `.switcherSessionStarted` shared runtime maintenance；`testLiveSwitcherModelStartsAppSessionFromRuntimeProjectionWithoutLightweightSampling` / `testLiveSwitcherModelRequestsMaintenanceWhenAppSwitcherProjectionIsMissing` / `testLiveSwitcherModelDoesNotExposeDirtyProjectionWindowsAsFreshWindowCycle` 也用 app-switcher projection read count 与 maintenance request 证明 projection-owned startup path，而不是 dead full/lightweight snapshot counters。
- `FlowTabPriorityCoverageTests.testSwitcherPanelControllerTerminateRefreshIgnoresFollowUpActiveSpaceChangeAfterModifierRelease` 证明 workspace termination refresh 先提交 runtime app-termination dirty signal，再通过第二次 app-switcher projection read 剪掉 terminated app 并保护后续 active-Space change；`testSwitcherPanelControllerTerminateRequestProtectsPanelResignAfterModifierRelease` 证明 terminate request 的 panel-resign protection 入口也从 committed app-switcher projection 启动，而不是用 dead full/lightweight snapshot counters 证明没有采样。
- `FlowTabTests.testLiveSwitcherModelMaintenanceDiagnosticTracksGenerationReasonWithoutApply` 证明 maintenance diagnostic 记录 generation/reason，`applyGeneration=nil`，不会把后台结果 apply 回 surface session。
- `FlowTabPriorityCoverageTests.testRuntimeReconciliationCoordinatorPromotesPriorityAndBypassesRetryBackoff` 证明 high-priority activation verified signal 可以提升已有 low-priority retry request，重置 attempt 并绕过 retry backoff。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceMaintenanceRequestDrainsReadyRequestsBySchedulerPriority` 证明 runtime maintenance drain 按 shared coordinator priority 执行 high-priority request，再执行 low-priority request。
- `FlowTabPriorityCoverageTests.testRuntimeReconciliationCoordinatorCancelsPendingFullRepairForHighPriorityScopedRepair` 证明 pending low-priority full repair fallback 会被后来的 high-priority scoped repair 取消。
- `FlowTabPriorityCoverageTests.testRuntimeReconciliationCoordinatorSchedulesFullRepairFallbackWhenRetryPolicyExhausts` 证明 scoped repair retry policy exhausted 时，coordinator 会移除失败 scoped request 并安排 low-priority full repair fallback。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceMaintenanceSchedulesLowPriorityFullRepairWhenProjectionMissing` 证明缺 app-switcher projection 且没有 scoped pending repair 时，runtime-owned maintenance 才会安排 low-priority full repair fallback 并提交 cold-start projection。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceMaintenanceSchedulesLowPriorityFullRepairWhenProjectionMissing` 和 `testRuntimeProjectionServiceFullRepairFallbackCommitsDegradedProjectionWithoutRefreshingSearch` 的 injected executor 已改为返回 `RuntimeFullRepairProjectionPayload`，编译层证明 service-level full repair outcome 不再接受 `RuntimeSnapshot` result。
- `FlowTabTests.testRuntimeProjectionRepairProviderUsesProjectionPayloadForUITestMockDatasetWhenLaunchFlagEnabled` 证明 repair-provider `fullRepairProjectionPayload()` 可直接产出 app/context projection payload，不再经过 provider `snapshot()` wrapper；`testRuntimeProjectionServiceDefaultFullRepairCommitsProviderProjectionPayload` 证明默认 full repair executor 通过 runtime-owned `RuntimeProjectionRepairProvider` facade 提交 provider-derived projection payload，不经 injected snapshot result，也不要求 `RuntimeSnapshotProvider` 本体 conform service repair protocol。
- `FlowTabPriorityCoverageTests.testRuntimeFullRepairProjectionAssemblerSortsCurrentAppInputsAndBuildsContexts` 与 `testRuntimeFullRepairProjectionAssemblerPreservesMinimizedSeedsAndFallbackGroupIDs` 证明 full-repair payload assembly 只通过 `RuntimeCurrentAppWindowProjectionAssemblyInput` production entry 组装 app-switcher candidates 与 contexts，不再暴露 provider-owned 或 testing-only row assembly API。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceSearchFreshnessBarrierDoesNotPromoteOrDrainFullRepairFallback` 证明 Search freshness barrier 不提升、不 drain full repair fallback；在没有新 generation 成功提交时，Search 仍返回 degraded/stale committed result。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRetryExhaustsToFullRepairFallback` 证明 Search barrier 内 scoped repair exhausted 后只留下 low-priority full repair fallback，committed search index 继续保持 degraded/stale，不提交 staging partial result。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceSearchFreshnessBarrierDoesNotCommitStaleStagingWithoutRepairPayload` 证明本轮 barrier 只有 completed request 但没有 repaired payload 时，不会提交残留 staging search index，也不会清 dirty metadata 或把旧 staging 暴露成最新完整结果。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceFullRepairFallbackCommitsDegradedProjectionWithoutRefreshingSearch` 证明 retry exhausted 后真正执行 full repair fallback 时，runtime 也只能提交 degraded app-switcher projection，Search 仍读取 last committed index + dirty metadata，不清 staging/dirty 状态，也不进入最新完整结果态。
- `FlowTabTests.testOptionTabWindowScalePressureKeepsSelectedAppApplyAndPreviewCaptureBounded` 证明 1,000-window selected-app projection/snapshot apply、window-layer entry 和 current-page preview item 生成保持 bounded；本轮 p95 分别为 0.68ms、0.01ms、0.24ms。
- 本轮 targeted `FlowTabPriorityCoverageTests` full repair / Search barrier 6 个用例通过；类级 `FlowTabPriorityCoverageTests` 当前执行 347 tests，仍有非本阶段 `testSwitcherPanelControllerRecoverableOcclusionKeepsSessionVisible` visibility diagnostic 断言失败，未作为本阶段 runtime ownership blocker。
- P2 待补：完整 full repair fallback facts 拆分、更广 backoff policy、真实 topology UI/E2E 与 pressure proof。

### Phase 4: Search read model

- Search index 从 `RuntimeWindowRecord` + app directory 投影。
- Search index 分为 internal staging 与 surface-readable committed 两层。
- 日常 maintenance 持续用 dirty/current/recent/affected scopes 更新 staging，并在验证 generation 覆盖后原子提交 committed index。
- Search 激活先做 freshness validation；若 committed index 未覆盖当前 app/CG/Space/AX dirty generation，则执行 bounded freshness barrier。只有 barrier 成功提交新 committed generation 后，Search 才能进入最新搜索结果态；未提交时的当前行为必须保持 `degradedStaleCommittedResult` / stale committed read。
- 当前迁移状态：Search 已改为读取 runtime-owned committed index；`RuntimeReadModelStore` 提供 `currentGenerationCommitted` / `staleCommitted` / `missingCommittedIndex` freshness read，并由 `RuntimeSearchIndexRead` 同步返回 surface 必须记录的 result state。`staleCommitted` 时仍返回 last committed index + dirty metadata，并由 `RuntimeProjectionService` 发起 bounded runtime maintenance drain；这个返回值是 degraded/stale committed result，即使有可展示 entries，也不能称为 fresh、complete、latest 或 current-generation result。Search freshness barrier 会把 pending/waiting retry repair 提升为 high-priority `searchFreshnessBarrier` request，每次只 drain 固定数量的 ready scoped repair；只有 completed scoped repair 先写 internal staging、验证 coordinator 无未完成 repair、并原子提交新 committed generation 后，Search 才能进入 `verifiedCurrentGenerationCommittedResult`。completed request 若没有本轮 repaired payload，则不能借用历史 staging 提交新 committed generation。barrier 未提交、repair deferred、batch bound 后仍有 pending repair，或 retry exhausted 后执行 low-priority full repair fallback 但仍有 dirty metadata 时，当前行为必须暴露为 `degradedStaleCommittedResult` + dirty/freshness metadata，不回退到 session completeness、同步 full sampling，也不把该结果命名为 fresh/complete/latest。Search committed-index behavior tests now prove this through `RuntimeSearchIndexReadDiagnostic` (`source=committedRuntimeIndex`, `readiness`, `resultState`, generation coverage) plus explicit freshness-barrier request assertions, rather than relying on dead full/lightweight snapshot counters in the recording service fixture.
- dirty/pending app 只能作为 barrier/blocker/log 状态，不作为正常搜索结果状态。
- Search 激活可以提升 repair priority，但不能同步拉全量 AX tree 才开始搜索。

验证：

- session window 不完整时，Search 仍只读取 committed search index，不依赖 session completeness。
- 同一 committed generation 下连续搜索结果稳定。
- background repair 中间态不会暴露给 Search。
- freshness barrier 未完成时，不能把旧/部分 index 标记为最新完整。
- `FlowTabPriorityCoverageTests+SessionAndPanelSearch` 的 model-level Search/session result apply cases 从 runtime-owned committed projection service 启动，并断言 Search entry / app result apply / window result apply / window target commit 不调用 full/lightweight snapshot 请求。

### Phase 5: Space signature 与真实拓扑证明

- 建立 display-level Space signature。
- normal/fullscreen 转换通过 signature/diff 快速判定。
- affected `CGWindowID` 转 scoped app repair。
- 当前迁移状态：`RuntimeSpaceTopologySnapshot` 已能派生 display-level signature，signature 覆盖 current space、space membership、window membership 与 fullscreen window；`RuntimeSpaceTopologyDiff` 携带 previous/current signature，normal/fullscreen 状态变化可通过 signature/diff 标记 affected `CGWindowID` 并进入已有 scoped repair。runtime `collectCGWindows` diagnostic 已携带 signature summary，Space topology signal 已把 diff 的 affected `CGWindowID` 写入 `RuntimeReadModelStore` dirty metadata，而不是只让 coordinator 持有 affected request；真实 noisy fullscreen fixture UI 已在每次确认激活后断言 `signatureChanged`、display/space/window/fullscreen count 与 signature summary，代表性真实 Space signature proof 已闭环。
- 补真实 fullscreen、多显示器、off-space、same-space CG-only、non-registry focused readback UI/E2E proof。

验证：

- deterministic Space diff。
- real UI/E2E topology path。
- runtime logs 证明 target `CGWindowID`、affected diff、verified readback。

## 完成标准

不能把 mock-only 或局部 fallback 当完成。完成标准是：

- `Option+Tab` 首帧只读 app projection。
- `Control+Tab` 只读 current app window projection。
- Search 只读原子提交的 committed search index；进入 Search 前完成 freshness validation。必要时只有 bounded freshness barrier 成功提交新 generation，才能进入最新搜索结果态；否则只能返回 degraded/stale committed result 与 dirty/freshness metadata。
- Home 读 summary/detail projection，不驱动 hotkey 全局采样。
- full snapshot 不再是 surface 主流程。
- AX notification 只作为 dirty/repair input，不作为唯一真相。
- Space topology 有 signature/diff/affected-window 闭环。
- activation 有 verified readback 写回。
- runtime logs 能证明真实 target `CGWindowID` 经过预期路径。
- required unit/behavior/UI/pressure proof 都按场景落地；未证明项留作 known gap。

## Known Gaps

当前文档目标下仍需显式保留这些 gap，直到代码和验证都闭环：

- Phase 5 本轮 P0 收窄 current-app projection payload 派生入口：`RuntimeCurrentAppWindowPayload` 已删除 `app` / `appGroup` / rank convenience initializer，并把 seed-to-summary/candidate/context initializer 降为 private；repair-provider `currentAppWindowPayload(for:)` 与 `focusedCurrentAppWindowPayload(processIdentifier:)` 显式提交 `RuntimeCurrentAppWindowProjectionAssemblyInput`。这只是 projection payload ownership cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result，而不能命名为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 full-repair assembler entry：`RuntimeFullRepairProjectionAssembler.payload(fromCurrentAppWindowPayloads:)` 已降为 private，repair-provider full repair 与 tests 只能通过 `payload(fromCurrentAppWindowProjectionInputs:)` 进入，避免 full repair assembly 重新暴露 prebuilt payload 数组作为生产入口。这只是 projection payload ownership cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 UI-test projection seed ownership：`FlowTabUITestRuntimeProjectionDataset` 现在在 TestingSupport 边界承载 mock runtime app-switcher seed、contexts 与 current-app payloads，repair-provider full/current-app projection builders 和 `AppInventoryService` 只读取该 projection dataset，不再通过 `RuntimeSnapshotProvider.UITestRuntimeDataset` / `uiTestRuntimeDataset()` 表达 mock runtime seed ownership。这只是测试启动 projection seed ownership cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 service repair provider ownership：`RuntimeProjectionRepairProvider` 现在是 `RuntimeProjectionService` 的默认 repair/fact facade，组合底层 `RuntimeSnapshotProvider` 执行 scoped repair、Space affected-target derivation、verified focus/AX destroyed evidence 与 low-priority full repair fallback；`RuntimeSnapshotProvider` 本体不再直接 conform `RuntimeProjectionRepairProviding`。这只是 service/executor ownership cleanup；repair-provider `fullRepairProjectionPayload()` / current-app projection builders 仍是 full-repair 迁移桥，Search freshness contract 不变，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 projection builder ownership：`RuntimeProjectionRepairProvider+ProjectionBuilders.swift` 现在承载 full/current-app projection payload builders 与 full-repair `collectWindowData(for:)` 聚合入口，`RuntimeProjectionRepairProvider+Reconciliation.swift` 承载 app affected-target derivation 与 app-window reconciliation result assembly；`RuntimeSnapshotProvider` 只作为组合注入的底层 CG/AX/Space fact source、WindowRecord table 与 focus/AX-destroyed evidence writer。provider-facing `fullRepairProjectionPayload()`、`currentAppWindowPayload(for:)`、`focusedCurrentAppWindowPayload(processIdentifier:)`、`appReconciliationTargets(...)`、`reconcileAppWindows(...)` API 已删除，测试与 UI-test bootstrapper 也通过 repair-provider facade 读取 projection payload。这仍不是长期主表生成：full/current-app builders 还会在 repair/fallback 路径即时采样 running apps、CG、AX 与 app directory facts；Search freshness contract 不变，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- hot-path read APIs 的 P0 已从 Switcher/Home 首屏采样队列中解耦；selected/current app window refresh 和 Home window activation 已移除缺 projection 时的 `homeAppSnapshotSynchronously` fallback，改为 dirty signal + projection-only 状态；Home initial app summary 已移除缺 projection 时的 `lightweightAppSnapshot()` 同步 fallback，Home initial/refresh diagnostics 也迁到 projection category；Home summary/detail refresh 已从 service-facing Home fallback bridge 迁移到 Home/current-app/app-switcher projection read + shared runtime maintenance signal；Switcher startup recency 已移除 live focused AX 与 live CG z-order read seam，改为 committed recency/projection order，且 `RuntimeWindowRecencyTracker` 不再暴露 Home snapshot-shaped recency helper；Switcher app-cycle hidden-app filtering 现在也作为 projection payload diagnostic 记录，不再占用 snapshot log category；Switcher termination refresh 已由 runtime store 同步剪枝 committed projection/search index，不再走 feature-facing full snapshot fallback；Search read model 已进入 runtime-owned committed index/freshness-read/committed-generation advance 边界，barrier 未提交时当前行为是 degraded/stale committed result 而不是 fresh/complete/latest，deterministic committed-index pressure 已证明 `LiveSwitcherModel` Search hot path 在 400 apps / 10,000 windows 下不调用 full/lightweight snapshot 且不请求 freshness barrier；真实 UI/E2E committed/staging proof 与外部 pressure proof 仍需补齐。
- `RuntimeReadModelStore` 与 projection cache 的 P0 边界已落地；Home surface state/API 已把 selected-app detail cache 和 API payload 类型迁移为 `RuntimeHomeAppDetailProjection`，不再把 projection read boundary 表达成 Home snapshot cache；app identity 规则已收敛到 runtime-owned `RuntimeAppIdentity`，AppDelegate lifecycle signal、Switcher focused-current-app projection read、repair-provider full repair grouping、reconciliation target 和 UI-test runtime projection seed 都直接读取该入口，不再向 `RuntimeSnapshotProvider` 查询 appID，`RuntimeSnapshotProvider.baseAppID(for:)` 兼容 wrapper 已删除；provider-facing current-app payload pullback、`appWindowRepairPayload` / `focusedAppWindowRepairPayload(processIdentifier:)` 兼容 API 与 `RuntimeAppWindowRepairPayload` 类型级 wrapper 已删除；provider summary compatibility APIs `homeSummaryProjections()` / `homeSummaryProjection(for:)` 已删除，Home summary 只能来自 `RuntimeReadModelStore` projection 或 current-app payload 的 summary fact；承载 full/current-app projection/repair builders 的文件已迁为 `RuntimeProjectionRepairProvider+ProjectionBuilders.swift`，不再保留 `HomeApps` 或 provider builder 文件边界，并且 `fullRepairProjectionPayload()` 与其 private full-repair `collectWindowData(for:)` 聚合入口也已迁入 repair-provider builder 文件；`RuntimeProjectionPayloads.swift` 承载 top-level `RuntimeFullRepairProjectionPayload`、`RuntimeCurrentAppWindowPayload`、`RuntimeAppWindowProjectionSeed`、`RuntimeAppContext` 与 `RuntimeCurrentAppWindowProjectionAssemblyInput`，top-level `RuntimeWindowListEntry` 承载 provider 采样后进入 window-layer / projection seed 的 window list fact，`RuntimeAppWindowProjectionSeed` conversion、`RuntimeCurrentAppWindowProjectionAssemblyInput` / `RuntimeCurrentAppWindowPayload` 已拥有 app/display/rank/group/timestamp + projection seed 到 summary/candidate/context payload fact 的 assembly，`RuntimeFullRepairProjectionAssembler` 已取代 provider-owned deterministic assembly seam，production full repair payload sorting/context map assembly 也由该 assembler 执行；`RuntimeAppLayerProjectionFilter` 已迁到 `RuntimeAppDirectory.swift`，与 app directory eligibility/filtering 规则同层，取代 provider-owned filter seam，repair-provider current-app payload pullback 也不再内联 minimized-only include 条件，provider full repair builder 也不再保留 `filterAppsForAppLayer(...)` adapter seam；full repair payload 已收敛到 repair-provider `fullRepairProjectionPayload()` 与 shared `RuntimeFullRepairProjectionPayload`，且 full/current-app repair builders 现在共用 runtime-owned projection seed 和 `RuntimeCurrentAppWindowPayload` assembly；迁移期 `RuntimeFullRepairProjectionAssembly*` DTO 与 `assembleRows(...)` testing seam 已删除；provider-facing `RuntimeSnapshotProvider.snapshot()` wrapper、`RuntimeSnapshot` 类型与 `collectCGWindowsByPID` CG-read 兼容包装已删除，repair-provider full/current-app builders 也直接消费 topology-aware `collectCGWindowsWithSpaceTopologyDiff`；`RuntimeCGWindowFacts.swift` 承载 top-level CG fact payload 和 CG validity constraints，`RuntimeWindowRecord`、provider window-mapping helpers、`RuntimeActivator`、`RuntimeChromeWindowFocusBridge`、provider internals 与 deterministic tests 已直接接收/合成 top-level `RuntimeCGWindowEntry` / `RuntimeCGWindowCollection`，生产代码不再引用 provider-nested CG fact 名称或 provider-owned validity helper，`RuntimeSnapshotProvider.CGWindowEntry` / `CGWindowCollection` 迁移期 typealias、`CGWindowEntryForTesting` 与 `RuntimeSnapshotProvider.cgWindowPassesValidityConstraints(_:)` 已删除；production AX window fact 也已迁为 top-level `RuntimeAXWindowEntry`，由 `RuntimeWindowRecord.swift` 与 AX attachment state 同层拥有，provider-nested `RuntimeSnapshotProvider.AXWindowEntry` 与 `AXWindowEntryForTesting` 均已删除，provider testing helpers 也直接接收 top-level `RuntimeAXWindowEntry` fixtures；AX/CG public assignment 与 public-AX recovery 已分别迁到 `RuntimeWindowAssignmentMatcher` 和 `RuntimeAXWindowRecovery`，provider 不再拥有 `matchCGWindowAssignments*` 或 `recoverAXWindowFromPublicSources*` helper API；service/coordinator transient-empty retry outcome 已命名为 current-app payload 边界，不再暴露 AX snapshot-shaped outcome；full/current-app projection builder timing 与 filtering diagnostics 已进入 projection log category，snapshot category 保留给底层 CG/AX/Space fact collection；provider core 文件只保留底层 CG/AX/Space 采样与窗口事实基础设施；current-app payload 提交时会由 store 以既有 projection 为 base 同步 upsert current-app、app-switcher 与 Home summary projection；UI-test runtime dataset 也只维护 app-switcher projection seed、contexts 与 current-app payloads，test launch option 内部 API 使用 projection 命名。仍需把 repair-provider projection builders 从 repair/fallback 即时采样迁移到底层 `RuntimeWindowRecord`、app directory、Space topology 主表生成。
- `RuntimeAppDirectoryEntry` / `RuntimeAppDirectory` 现在承载 app grouping、primary app selection、app stats/rank sorting、preferred rank、stable last-active、app-layer nested/zero-window suppression、sampled-window stats derivation、group 内 window merge 与 app-window stats based candidate filtering；provider 只把采样窗口 facts 和 minimized/visible 映射交给 runtime-owned app directory，`RuntimeSnapshotProvider+AppGrouping.swift` provider extension seam 已删除；`RuntimeFullRepairProjectionAssembler` 只消费 current-app projection input / payload 来排序 app-switcher candidates 并生成 context map，不再拥有 app directory 规则、testing-only row assembly seam，且不再从 current-app inputs 反推 app directory entries。full repair payload 已显式携带完整 filtered running-app directory evidence，而不是从 selected app-switcher rows 或 scoped current-app inputs 反推 directory；长期 gap 仍是把 directory 从 full-repair 兼容桥输入推进为 Runtime 长期维护的 app directory 主表。
- Switcher session-start background full snapshot 已降级为 runtime-owned maintenance request；scheduler priority/coalescing/promoted-backoff P1 已落地，Search freshness barrier priority 与 selected/current app-window priority 已进入 runtime coordinator，full repair fallback target / low-priority scheduling / high-priority scoped cancellation / retry-exhaustion 自动降级已建模；dirty full repair fallback 现在只能提交 degraded projection，不能清 dirty 或刷新 committed Search。完整 full repair facts 拆分与更广 backoff policy 仍需补齐。
- search index 已从 session completeness 迁移到 committed runtime index read，并补齐 stale/dirty freshness read、bounded maintenance request、completed scoped repair 后 new committed generation 进入 verified current-generation committed result 的边界；repaired current-app projection payload 现在由 store-owned staging API 消费，barrier 未产生本轮 repaired payload、barrier 未提交或 dirty full repair fallback 执行后，当前 Search 行为记录为 degraded/stale committed result，而非 fresh/complete/latest。deterministic committed-index pressure 已覆盖 current-generation committed index 的 Search entry/query hot path，仍需补真实 committed/staging UI proof 与外部 pressure proof。
- Space signature P0 已落到 deterministic model/diff、runtime diagnostic fields、read-model dirty affected-window metadata 与代表性 noisy fullscreen fixture UI signature proof；`scripts/perf/runtime-topology-pressure.sh` 已提供外部 CPU/RSS wrapper，非 sandbox 复跑通过 70 个 0.5s 样本（CPU avg/p95/max 29.37/59.50/84.70，RSS avg/p95/max 112.12/174.67/202.70MB）。首次 pressure wrapper 运行曾暴露 dirty app-switcher projection 可在 pending repair 未 ready 时把 5-window stale Chrome Fixture 列表当正常 window cycle 呈现，而 runtime `window-entries` 已修复回 4；当前 `RuntimeAppSwitcherProjection.appCycleApps` 已让 dirty app-switcher projection 在 app-cycle 热路径压制 stale window lists，行为回归测试先失败后通过，外部 wrapper 复跑也通过 70 个 0.5s 样本（CPU avg/p95/max 31.63/55.50/78.80，RSS avg/p95/max 118.34/180.17/207.23MB）。系统权威 fullscreen owner、多显示器 Space/window 视图仍需补齐。
- 更广 fullscreen Space 拓扑、多显示器组合、normal/fullscreen 往返仍需真实 UI/E2E proof。
- non-registry focused AX readback 的真实系统形态仍需 UI/E2E proof。
- focused/main/minimized public AX tie-breaker 仍需更广状态排列 proof。
- minimized tie-breaker、多显示器 fullscreen 组合、真实逐路径提交与非曝光证明仍需补覆盖。
