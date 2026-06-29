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
- `RuntimeSystemRepairFactProvider` 只是底层 CG/AX/Space fact source、WindowRecord mapping/evidence bridge 与 repair/fallback 兼容入口；normal projection 构建属于 `RuntimeMainTableProjectionBuilder` / `RuntimeReadModelStore` 边界，repair/fallback fact 更新属于 `RuntimeProjectionRepairProvider` / fact source，不能回流成 surface hot-path read seam。
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

Search 是更强约束：Search surface 只能读取 `committedSearchIndex`。当前 production read model 不维护 surface-readable staging index，也不允许 repaired payload / partial / repair 中间态进入 Search 结果；如果后续重新引入 staging，只能作为 runtime maintenance 私有验证状态，且 barrier 成功提交新 generation 前仍必须暴露 last committed index 的 degraded/stale committed result。pending/dirty 可以作为内部 barrier 或日志状态存在，但不能成为正常搜索结果的一部分。

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
- 如果 committed index 未覆盖当前 generation，必须先执行 bounded freshness barrier：只对 dirty/current/selected/recent/affected scopes 做 scoped repair，或从已覆盖当前 runtime generation 的 committed projection cache 构建 index，验证通过后原子提交为新的 `committedSearchIndex`。
- bounded freshness barrier 被请求但尚未提交新 generation 时，Search 当前读到的只能是 last committed index，并且必须标记为 `degradedStaleCommittedResult` / stale committed read，携带 dirty/freshness metadata；不能把这个状态命名为 fresh、complete、latest 或 current-generation committed。
- Search 不读取 staging / repair 中间态，不把旧 index 或部分 index 当作最新完整结果。
- Runtime service 的 Search barrier 成功路径不能从 repaired current-app payload、staging 或 repair 中间态直接提交最新结果；repair outcome 必须先降级为 evidence trigger，经 runtime 主表重建并提交覆盖当前 generation 的 projection cache 后，Search index 才能从该 projection cache 重建并提交。
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

当前实现已删除 provider-facing `RuntimeSystemRepairFactProvider.snapshot()` wrapper；scheduler full repair 入口使用 service-facing `RuntimeFullRepairEvidence` / `fullRepairEvidence()`，不再构造 `RuntimeSnapshot` wrapper。`RuntimeProjectionRepairProvider.fullRepairProjectionPayload()` 也已删除；`RuntimeFullRepairProjectionPayload` / `RuntimeFullRepairProjectionAssembler` 已移到 `FlowTab/TestingSupport/RuntimeFullRepairProjectionTestSupport.swift`，只作为 fixture/test helper 保留，不是 `Infrastructure/Runtime` 的正常 payload 边界，也不是 provider/service/drainer 的提交或诊断读入口。

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
- `RuntimeReadModelStore` 现在也维护 `RuntimeAppDirectoryState`：该 runtime-owned state 类型拥有 PID-keyed replace/upsert/remove、same appID scoped pruning 与 projection derivation 规则。full repair、current-app repair、workspace provider 与 lifecycle signal 会携带 `RuntimeAppDirectoryEntry` evidence，并且只有这些显式 evidence API 会写入 app directory state；app-switcher/current-app projection commit 不再从 projection payload 反推或 upsert directory fact。`readAppDirectoryProjection()` 从该主表派生 `RuntimeAppDirectoryProjection` 与 generation/freshness/dirty metadata。app directory 因此不再只是 repair-provider builder 的局部 grouping helper 或一份 projection cache；但 entries 仍来自 repair/fallback/lifecycle/provider evidence，尚未升级为独立长期 fact source。
- full repair 现在通过 service-facing `RuntimeFullRepairEvidence` 把完整 filtered running-app `RuntimeAppDirectoryEntry` evidence 显式交给 drainer/service；`RuntimeProjectionService` 只把这份 full-repair evidence 写入 `RuntimeReadModelStore.commitFullRepairAppDirectoryEvidence(...)`，然后通过主表 app-switcher projection builder 生成 projection。app directory projection 不再从已筛选的 app-switcher rows / current-app payload 反推，因此被 app-layer 过滤掉但仍属于 runtime app directory 的 running app evidence 不会在 full repair evidence commit 时丢失；`RuntimeFullRepairProjectionPayload.apps` / `contextsByID` 不再跨过 reconciliation drainer/service 边界，也不是正常 app-switcher/Home projection cache 的直接来源。
- app launch lifecycle signal 现在会把 `NSRunningApplication` 派生的 `RuntimeAppDirectoryEntry` 随 dirty signal 写入 `RuntimeReadModelStore` 的 app directory state，并在 runtime maintenance queue 内尝试通过 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 从 app directory + WindowRecord 主表预提交 app-switcher/Home summary projection cache；normal app-switcher 整表预提交要求主表 app directory 覆盖既有 app-switcher appIDs，若迁移期 legacy cache 没有对应 directory evidence，则保持旧 projection 的 degraded/stale 状态并等待 repair/full evidence 补齐，避免用部分主表替换完整旧 cache。repair 尚未完成时这份 projection 仍携带 dirty/stale freshness metadata，不提交 Search index，不会被命名为 fresh/complete/latest。
- Phase 6 已开始把正常 app-only projection generation 从 repair payload 推向 runtime 主表：`RuntimeReadModelStore.readAppSwitcherProjection()` 与 `readHomeSummaryProjection()` 在 committed projection cache 缺失时，可从 `RuntimeAppDirectoryState` 派生 app identity/group/order、empty windows/context 与 Home app summaries，并携带同一 generation/freshness/dirty metadata。该 derived projection 不读取 CG/AX/Space，不提交 Search index；在 dirty/pending repair 存在时只能是 degraded/stale projection，不能被称为 fresh、complete 或 latest。
- Phase 6 的 window fact 输入也开始从 WindowRecord 主表生成：`RuntimeWindowRecordStore.projectedWindowEntries(processIdentifier:appName:)` 现在是 WindowRecord -> `RuntimeWindowListEntry` 的语义出口；full/current/focused repair fact collection 仍可采样 CG/AX/Space 来更新 WindowRecord，但返回给 projection selection / payload assembly 的 window facts 由 `RuntimeWindowRecordStore` 派生，而不是直接复用 `RuntimeSystemRepairFactProvider.collectAXWindowData(...)` 的即时 sampled entries。该路径仍处于 repair/fallback scheduler 内，但 normal projection builder 的 window rows 已开始读长期 WindowRecord facts。
- `RuntimeMainTableProjectionBuilder` 现在是 service-facing normal projection builder concrete owner：`RuntimeProjectionService` 通过 `RuntimeMainTableProjectionBuilding` 从 app directory + WindowRecord 主表生成 current-app 与 app-switcher/Home projection payload；`RuntimeProjectionRepairProviding` 不再暴露 `currentAppWindowPayloadFromMainTables(...)` 或 `appSwitcherProjectionPayloadFromMainTables(...)`，concrete `RuntimeProjectionRepairProvider` 也不再 conform 该 builder。默认 `RuntimeProjectionService` wiring 会创建同一个 `RuntimeWindowRecordStore` 并分别注入 repair provider 与 main-table builder；custom tests / wiring 若注入 repair provider 且需要 normal projection，也必须显式注入同 store 的 builder。`RuntimeUnavailableMainTableProjectionBuilder` 只是 custom injection 的 fail-closed compatibility fallback，不是 production normal read path。
- current-app normal projection builder 现在要求 `RuntimeReadModelStore` 的 app directory 主表已经有匹配 appID/pid 的 `RuntimeAppDirectoryEntry`；即使 `NSRunningApplication(processIdentifier:)` 仍可用于 `RuntimeAppContext` activation handle 兼容，builder 也不会在 app directory 缺失时从 running app 合成 directory fact。app directory 缺失时 current-app projection fail-closed，等待 lifecycle / current-app repair / full repair evidence 先写入主表；normal projection builder 因此只读 app directory fact，而不是第二个 app fact source。
- app-window dirty signal 与 selected-current-app dirty signal 现在都会在 runtime maintenance queue 内尝试从主表预提交 current-app/Home detail projection cache：`RuntimeMainTableProjectionBuilding.currentAppWindowPayloadFromMainTables(...)` 只读取 `RuntimeWindowRecordStore.projectedWindowEntries(...)` 与 `RuntimeReadModelStore` 已维护的 app directory entries，生成 `RuntimeCurrentAppWindowPayload` 后由 `RuntimeReadModelStore.commitCurrentAppWindowProjection(..., clearsDirtyState: false)` 写入 current-app/Home detail 可读 projection cache。若 app directory 主表尚无匹配 entry，该 path 不会从 running app 补造 directory fact，而是等待 repair/lifecycle evidence；该 projection 保留 dirty/pending repair metadata，是 degraded/stale committed projection，不提交 Search index，也不把未完成 app-window repair 命名为 fresh/complete/latest。app-switcher/Home summary 由 app-switcher main-table payload commit 或 app-directory-derived read model 单独维护。
- current-app repair drain 现在也走同一主表 projection builder，并且 reconciliation/drainer/service 边界不再运输 repaired `RuntimeCurrentAppWindowPayload` projection rows：`RuntimeAppWindowReconciliationResult` 直接携带 `RuntimeCurrentAppRepairEvidence`，不再暴露 `currentAppWindowPayload` 或从 payload computed evidence；`RuntimeProjectionReconciliationDrainer` 把 app/space repair result 作为 evidence-only outcome 传递，只携带 appID、pid、app directory entries 与 transient-empty evidence。`RuntimeProjectionService` 只 upsert 这份 directory evidence，然后用 evidence 的 appID/pid 调用 `RuntimeMainTableProjectionBuilding.currentAppWindowPayloadFromMainTables(...)` 从 app directory + WindowRecordStore 生成 current-app/Home detail projection cache。repaired payload 的 candidate/window rows 不能穿过 reconciliation/drain/service 边界刷新正常 projection cache 或 Search freshness；Search barrier 成功态只能来自随后覆盖当前 generation 的 projection cache commit，未提交时只能是 degraded/stale committed result。
- app-switcher maintenance 现在也可从主表整表预提交 projection cache：`RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 只读取 `RuntimeReadModelStore` 已维护的 app directory entries 与 `RuntimeWindowRecordStore.projectedWindowEntries(...)`，生成 `RuntimeAppSwitcherProjectionPayload` 后由 `RuntimeReadModelStore.commitMainTableAppSwitcherProjectionPayload(...)` 写入 app-switcher 与 Home summary projection cache。该 payload/store API 不携带也不写入 app directory evidence，不接受 full-repair sampled rows 作为 directory source；full repair 只能先通过 `commitFullRepairAppDirectoryEvidence(...)` 补主表事实，再由主表 builder 生成 projection。该 path 不调用底层 CG/AX/Space fact source，不提交 Search index；dirty/pending repair 存在时只能是 degraded/stale committed projection，不能命名为 fresh、complete、latest 或 current-generation committed。
- full-repair fallback drain 现在也走同一主表 projection builder：`RuntimeProjectionReconciliationDrainer` 对 `.fullRepair` request 只返回 `RuntimeFullRepairEvidence`，`RuntimeProjectionService` 只提交其 `appDirectoryEntries` evidence，再调用 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 从 app directory + WindowRecordStore 生成 app-switcher/Home projection cache。full repair 即时 sampled payload 的 `apps` / `contextsByID` 不能跨过 drainer/service 边界刷新正常 projection cache 或 Search freshness；若主表没有足够 evidence，full repair 只作为事实补充/迁移桥保留。
- Search freshness barrier 现在只能从 runtime-owned committed app-switcher projection cache 提交 `committedSearchIndex`：`RuntimeProjectionService.requestSearchIndexFreshnessBarrier(...)` 会先尝试通过 main-table app-switcher projection maintenance 刷新 projection cache，随后把 scoped repaired current-app outcome 降级为 directory evidence/appID/pid trigger，并通过 main-table current-app builder 更新 projection cache；只有在无 deferred/pending repair 且 projection cache `sourceGeneration` 覆盖当前 runtime generation 时，`RuntimeReadModelStore.commitSearchFreshnessBarrierFromProjectionCache(...)` 才会构建并原子提交新的 Search index。service/store 不再保留 repaired-payload `commitSearchFreshnessBarrierPayloads(...)`、production `stagingSearchIndex`、普通 app-switcher direct commit API 或任何隐式 Search commit 成功路径；stale projection cache、repair 中间态和任何 partial/staging 数据都不能进入 latest/fresh Search 结果态。barrier 未成功提交新 generation 时仍只能暴露 last committed index 的 degraded/stale committed result 与 dirty/freshness metadata。
- Search committed read 现在保留 `committedSearchIndex` 自身的 `sourceGeneration`，只叠加当前 dirty/pending metadata；`RuntimeReadModelStore.readCommittedSearchIndexForSearch()` 只有在 committed index 的 `sourceGeneration == RuntimeReadModelStore.generation` 且无 dirty 时才返回 `committedGenerationValidated` / `committedGenerationResult`。如果 current-app/app-switcher/Home projection repair 清掉 dirty、普通 app-switcher projection commit 清掉 dirty，或 app termination 只更新主表 metadata / 后续 projection cache，但没有通过 freshness barrier 原子提交新的 Search generation，Search 仍必须返回 `degradedStaleCommittedResult`，不能因为 dirty 已清空、projection cache 可读或 terminated-app metadata 已更新而被命名为 fresh/complete/latest/current-generation committed。
- Home detail projection read 现在也归 Runtime read-model 边界：`RuntimeProjectionServing.readHomeAppDetailProjection(appID:)` / `RuntimeReadModelStore.readHomeAppDetailProjection(appID:)` 只从 current-app projection cache 返回 `RuntimeHomeAppDetailProjection`，Home feature 只读这个 projection API，不再在 surface 层读取 current-app/app-switcher projection 后自行拼 detail，也不再由 read-model 从 app-switcher projection cache/context 兼容派生 detail。普通 app-window dirty signal 可以先从 app directory + WindowRecord 主表预提交 current-app projection cache，因此 Home detail 缺 projection 时的下一次 refresh 可读到主表生成的 dirty/stale Home detail projection，而不是等待 repaired payload rows。该 read 不触发 CG/AX/Space sampling，也不提交 Search index。
- app directory state 现在只接受显式 app directory evidence：full repair、current-app repair、workspace provider 与 lifecycle signal 必须通过 `commitFullRepairAppDirectoryEvidence(...)`、`commitCurrentAppRepairAppDirectoryEvidence(...)`、`commitAppDirectoryProviderEvidence(...)` 或 dirty signal 携带 `RuntimeAppDirectoryEntry` 才能更新 `RuntimeAppDirectoryState`。`commitMainTableAppSwitcherProjectionPayload(...)` 只提交由主表 builder 产出的 app-switcher/Home projection cache，不携带、不合成、也不替换 app directory evidence；production `RuntimeReadModelStore.commitAppSwitcherProjection(...)` direct write 入口已删除。`RuntimeFullRepairProjectionPayload` 仅保留为 TestingSupport fixture shape，且必须显式传入 full repair directory entries 或显式空 evidence，不能从 contexts 反推。
- full-repair、current-app repair 与 workspace provider 的 app directory evidence 现在在实际改变 `RuntimeAppDirectoryState` entries 或首次初始化该主表时推进 `RuntimeReadModelGeneration.appLifecycle`；重复提交相同 entries 只刷新 evidence timestamp，不推进 generation。Search freshness barrier 的 service ordering 也已调整为先提交 scoped current-app repair app-directory evidence，再从 app directory + WindowRecord 主表生成 app-switcher/Home projection cache，最后才尝试 `commitSearchFreshnessBarrierFromProjectionCache(...)`。因此 committed Search index 的 current-generation 成功态必须覆盖 app directory fact 的新 generation；barrier 未成功提交时仍只能暴露 degraded/stale committed 或 missing committed index。
- app directory evidence 现在携带 optional activation/recency rank，并由 `RuntimeWorkspaceAppDirectoryProvider` 与 full-repair running-app evidence 在 public running-app fact collection 时写入 `RuntimeAppDirectoryEntry.activationRank`。`RuntimeReadModelStore` 把 rank 作为 app directory entry equality/generation 的一部分：rank 改变会推进 `appLifecycle` generation，重复相同 rank evidence 不推进 generation。app-directory-derived app-switcher/Home summary projection 与 `RuntimeMainTableProjectionBuilder.appSwitcherProjectionPayloadFromMainTables(...)` 都从 runtime-owned app directory entries 还原 `rankByPID` 来选择同 appID primary PID、排序 app rows、设置 stable `lastActiveAt`，不再在 normal builder path 中用空 rank map 或字母序替代 runtime evidence。Search 仍不因 rank/app-directory projection 更新而进入 latest/current-generation result；只有 bounded freshness barrier 成功提交覆盖新 generation 的 committed index 后才能返回 `committedGenerationValidated`，否则必须是 degraded/stale committed 或 missing committed index。
- current-app projection payload direct boundaries now also require explicit app directory evidence: `RuntimeCurrentAppWindowProjectionAssemblyInput(...)` and the direct `RuntimeCurrentAppWindowPayload(summary:candidate:context:...)` initializer must pass `appDirectoryEntries`, and no longer synthesize `RuntimeAppDirectoryEntry` from `runningApp` / `context.runningApp` defaults. Normal main-table builders carry app directory entries read from `RuntimeReadModelStore` for payload provenance, but `RuntimeReadModelStore.commitCurrentAppWindowProjection(...)` no longer writes those entries back into `RuntimeAppDirectoryState`; fixture, recency rewrite, and scoped payload callsites must either commit directory evidence through explicit full/current/provider/lifecycle APIs first or spell explicit empty evidence.
- `RuntimeFullRepairProjectionAssembler` 必须接收显式 `appDirectoryEntries` 参数；只有调用方显式传入 `[]` 时才代表明确空 evidence，assembler 不会从 current-app payloads / projection inputs 合成 directory evidence。assembler 只排序 app rows 与 contexts，完整 app directory 必须由 full repair fact collection 显式传入。
- app termination lifecycle signal 现在在 committed app directory state 存在同 appID 多 PID entries 时以 directory entries 作为 authoritative pid scope：terminated PID 只会从 app directory state 中剪掉，app-switcher/Home projection 会保留 grouped app 并标记 dirty/stale/pending repair。底层 cleanup 通过 repair-provider `recordAppTerminated(processIdentifier:)` 边界提交，service 不再直接调用 coordinator cancel / WindowRecord clear / AX live registry remove；repair-provider 内部负责取消 pending repair、移除 terminated PID 的 WindowRecord mapping state 与 AX live registry。正常 service termination path 现在只在 runtime maintenance queue 内调用 `RuntimeReadModelStore.markAppTerminatedForMainTableProjection(...)` 维护 app directory/current-app/dirty metadata，caller thread 只发送 lifecycle signal；该 metadata path 不剪枝或重写 `committedSearchIndex`。cleanup 后再通过 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 从剩余 app directory + WindowRecord 主表预提交 app-switcher/Home summary projection cache，coverage guard 允许被 terminated appID 缺席但仍要求其它既有 appID 被主表覆盖。此时 Search 只能返回 last committed index 的 `degradedStaleCommittedResult` / stale committed read 与 dirty/freshness metadata，旧 index 里可以仍含 terminated app/window row，不能命名为 fresh、complete、latest、current-generation committed 或最新完整结果。旧的 `RuntimeReadModelStore.markAppTerminated(...)` direct-call 同步 projection/Search 剪枝入口已删除；termination 不能再通过 store-local sanitization 或 queue 外同步 metadata mutation 冒充 freshness barrier 成功 proof。
- AX destroyed signal 现在通过 repair-provider `signalAXWindowDestroyed(appID:processIdentifier:axWindowID:now:)` 边界提交：repair-provider 内部调用 `RuntimeWindowRecordStore.clearDestroyedAXAttachment(...)` 清理 WindowRecord 的 destroyed AX attachment evidence，并用同一 affected `CGWindowID` evidence 调度 coordinator `.axNotification` scoped repair；`RuntimeProjectionService.signalAXWindowDestroyed(...)` 写 read-model dirty/freshness metadata 后，会调用 `commitMainTableCurrentAppProjectionLocked(..., clearsDirtyState: false, ...)` 从清理后的 WindowRecord 主表预提交 current-app/Home detail projection cache，随后记录 projection diagnostic 并 drain，不再直接调用 coordinator `markAppDirty(...)`。这份 projection 仍保留 dirty/pending repair metadata，不能命名为 fresh、complete、latest 或 current-generation committed；Search freshness contract 不变，freshness barrier 未成功提交新 generation 前只能暴露 degraded/stale committed result。
- activation verified-focus signal 现在通过 repair-provider `recordWindowFocusVerification(..., now:)` 边界提交：repair-provider 内部调用 `RuntimeWindowRecordStore.recordWindowFocusVerification(...)` 把 focused AX/CG readback 写入 WindowRecord verified-focus evidence，并调度 coordinator 的 activation-verified scoped repair request；`RuntimeProjectionService.signalWindowFocusVerified(...)` 消费 repair-provider 返回的 affected `CGWindowID` evidence 写 read-model dirty/freshness metadata 后，会调用 `commitMainTableCurrentAppProjectionLocked(..., clearsDirtyState: false, ...)` 从 verified-focus 后的 WindowRecord 主表预提交 current-app/Home detail projection cache，不再自己重算 affected set 或直接调用 coordinator `markWindowFocusVerified(...)`。activation 成功证明仍必须来自提交后的 focused AX/CG readback；这份 projection 仍是 dirty/stale committed projection，不会让 Search 进入 fresh/complete/latest/current-generation 结果态。Search freshness contract 不变，freshness barrier 未成功提交新 generation 前只能暴露 degraded/stale committed result。
- `RuntimeReadModelStore.commitCurrentAppWindowProjection(_:)` 现在只维护 current-app / Home detail projection cache；它不再同步 upsert app-switcher 或 Home summary projection，也不把 payload app directory entries 写回 `RuntimeAppDirectoryState`。app-switcher/Home summary 只能由 `commitMainTableAppSwitcherProjectionPayload(...)` 或 app-directory-derived read model 维护，current-app scoped payload 不能成为跨 projection 的 normal write source。
- Space topology signal 与 `RuntimeProjectionRepairFactSource` 现在都通过 `collectCGWindowsWithSpaceTopologyDiff` 消费 provider 记录的 `RuntimeSpaceTopologyDiff`；repair/fallback fact collection 只更新 WindowRecord / directory evidence 并把 `affectedCGWindowIDs` 写入 `RuntimeReadModelStore` 的 dirty/freshness metadata，normal projection rows 由 main-table builder 读取主表生成。旧 `collectCGWindowsByPID` 兼容包装已删除。
- `RuntimeCurrentAppWindowPayload` 现在拥有 app-window projection seed 到 Home summary、app-switcher candidate、`RuntimeAppContext` 的组装规则；repair-provider 已删除 appID-scoped `currentAppWindowPayload(for:)` 与 focused-PID `focusedCurrentAppWindowPayload(processIdentifier:)` scoped payload helper。UI-test current-app payload seed 只留在 `FlowTabUITestRuntimeProjectionDataset` TestingSupport 边界，focused-PID scoped repair 只通过 `focusedCurrentAppRepairEvidence(...)` 暴露 `RuntimeCurrentAppRepairEvidence`。正常 projection cache 重新由 `RuntimeMainTableProjectionBuilding.currentAppWindowPayloadFromMainTables(...)` 生成，不再把 repaired payload candidate/window rows 当 normal projection source。
- scoped repair 遇到 transient empty current-app payload 时，`RuntimeProjectionService.ReconciliationExecutionOutcome.transientEmptyCurrentAppWindowPayload` 会进入 `RuntimeReconciliationCoordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(...)`；service/coordinator retry 边界不再暴露 AX snapshot-shaped outcome 名称。
- transient empty current-app payload 的 retry 判定现在由 `RuntimeWindowMappingState` 拥有：`isLikelyTransientAXRebuild` 组合 observed AX handle 与 AX collection miss grace，`isTransientEmptyCurrentAppWindowPayload(...)` 再组合 empty current-app payload 事实。repair-provider reconciliation implementation 只消费 WindowRecord state-owned 判定，不再在 provider/reconciliation 层拼接 `payloadWasEmpty && transientAXRebuild`；feature-facing `RuntimeProjectionServing`、repair-provider protocol 与 `RuntimeSystemRepairFactProvider` 也不再暴露 `isLikelyTransientAXRebuild(for:)` read seam。Home 无 switchable windows 文案改为只读 projection freshness/dirty metadata 判断是否等待缓存更新，不再同步读取 transient AX rebuild state。该路径仍只是 scheduler repair/retry decision 输入，不是 surface hot-path read，也不是长期 WindowRecord/app-directory/topology 直接 rebuild projection；Search contract 不变，barrier 未成功提交新 generation 时只能暴露 degraded/stale committed result 与 dirty/freshness metadata。
- `RuntimeProjectionPayloads.swift` 现在只承载 runtime-owned normal projection payload 类型与 production assembly 入口：`RuntimeAppSwitcherProjectionPayload`、`RuntimeAppContext`、`RuntimeAppWindowProjectionSeed`、`RuntimeCurrentAppWindowPayload` 与 `RuntimeCurrentAppWindowProjectionAssemblyInput`。`RuntimeAppSwitcherProjectionPayload` 是主表 app-switcher/Home projection cache commit 的正常 payload，不携带 app directory evidence；`RuntimeFullRepairProjectionPayload` / `RuntimeFullRepairProjectionAssembler` 已降级到 `FlowTab/TestingSupport/RuntimeFullRepairProjectionTestSupport.swift`，只保留给 explicit fixture 与 assembler 测试，不是 repair-provider diagnostic API，也不是 drainer/service-facing full-repair evidence。`RuntimeAppWindowProjectionSeed` conversion、selection facts 到 current-app assembly input 的转换、`RuntimeCurrentAppWindowProjectionAssemblyInput` 的 app/display/rank/group/timestamp 派生，以及 summary/candidate/context payload fact assembly 都在 normal payload 边界；app grouping、primary selection、stats/rank sorting、preferred rank 与 app-layer eligibility/filtering 规则属于 `RuntimeAppDirectory.swift` 的 `RuntimeAppDirectoryEntry` / `RuntimeAppDirectory` / `RuntimeAppLayerProjectionFilter`。迁移期 `RuntimeFullRepairProjectionAssembly*` DTO 与 `assembleRows(...)` testing seam 已删除，provider builder 文件不再拥有或依赖 full-repair payload/assembly testing API。
- `RuntimeCurrentAppWindowPayload` 不再暴露 `app` / `appGroup` / rank convenience initializer，seed-to-summary/candidate/context initializer 也已降为 private；`RuntimeMainTableProjectionBuilder` 必须先显式构造 `RuntimeCurrentAppWindowProjectionAssemblyInput`，再交给 payload 组装 summary/candidate/context。app/display/rank/group/timestamp 与 projection seed 派生入口因此只剩 assembly input，payload 边界不再形成第二个事实派生入口；已组装的 summary/candidate/context initializer 只保留给 recency rewrite 与 fixture seeding，不参与 seed 派生。
- runtime repair-provider full repair builder 现在只保留 service-facing evidence 边界：`fullRepairEvidence()` 是 `RuntimeProjectionRepairProviding` 的 full-repair contract，它可以通过 `RuntimeProjectionRepairFactSource.collectFullRepairWindowFacts(for:)` 采样 CG/AX/Space 来更新 WindowRecord 主表，但只返回 `RuntimeFullRepairEvidence(appDirectoryEntries:)`。provider 不再暴露 `fullRepairProjectionPayload()`，因此 sampled app、rank 与 fact-source selection facts 不能通过 repair facade 组装成正常 app-switcher candidate / `contextsByID` payload；`RuntimeFullRepairProjectionAssembler` 只剩 `FlowTab/TestingSupport` explicit fixture / builder-test 使用。drainer/service 正常路径不能从 full repair payload 获得 Search fresh/current-generation success。appID-scoped current-app repair payload helper 已删除，focused-PID repair 现在通过 `focusedCurrentAppRepairEvidence(...)` 读取 running-app、cleanup/prune、rank/CG/AX facts、timing evidence 与 focused app/window selection，只返回 appID/pid/app-directory evidence 和 empty/transient metadata，不再组装 scoped projection payload。provider core 文件只保留底层 CG/AX/Space 采样编排，AX app collection payload 与 sampled window-list fact shape 由 `RuntimeWindowListFacts.swift` 承载。
- `RuntimeProjectionDiagnostics.swift` 现在拥有 projection timing line、projection log category 写入与 projection 毫秒格式化；repair evidence timing 与 normal main-table projection timing 均使用该 diagnostic boundary。底层 CG/AX/Space fact collection timing 与 app-name formatting helpers 现在由 `RuntimeFactCollectionDiagnostics.swift` 承载；`RuntimeSystemRepairFactProvider+Diagnostics.swift` 已删除。
- `RuntimeProjectionRepairProvider.swift` 现在承载 repair-provider contract、facade-owned WindowRecord/coordinator storage、app affected-target derivation 与 app-window reconciliation result assembly；`RuntimeMainTableProjectionBuilding.swift` 承载 normal main-table projection builder protocol、concrete builder 与 fail-closed unavailable fallback；`RuntimeProjectionService.swift` 保留 repair provider protocol、main-table builder、默认 shared-store wiring、read-model store ownership、scheduler drain 与 commit/freshness 条件。底层 `runtimeFactProvider` 只由 `RuntimeProjectionRepairFactSource` 持有，不能作为 same-module unwrap seam 暴露给 surface/service，也不再作为 concrete facade field 存在。
- `RuntimeAppWindowRepairPayload` 类型级 app-window repair 兼容 wrapper 已删除；provider 只把采样事实转换为 `RuntimeAppWindowProjectionSeed` 并产出 `RuntimeCurrentAppWindowPayload`，不再私有维护 candidate/context/summary projection assembly，也不再保留 repair-shaped current-app projection 上游。
- app identity 规则现在直接由 `RuntimeAppIdentity.appID(for:)` / `groupID(for:fallbackName:)` 服务 AppDelegate lifecycle、Switcher focused-current-app projection、repair-provider full repair evidence、reconciliation target、UI-test runtime projection seed 与 groupID projection assembly；`RuntimeAppDirectoryEntry` / `RuntimeAppDirectory` 负责 app grouping、primary app selection、app stats/rank sorting、preferred rank、stable last-active、app-layer nested/zero-window suppression、app-window stats derivation、group 内 window merge 和 app-window stats based candidate filtering，`RuntimeAppLayerProjectionFilter` 负责 running-app include 与 minimized/empty-window app-layer include 规则。repair fact-source 仍可采集 repair policy facts 和 focused current-app selection evidence 来更新主表 / evidence，但 normal app-layer candidate 与 context rows 由 `RuntimeMainTableProjectionBuilder` 从 app directory + WindowRecord 主表生成；provider `filterAppsForAppLayer(...)` adapter seam 已删除，full repair 不再直接编排正常 projection rows。`RuntimeSystemRepairFactProvider.baseAppID(for:)`、`groupID(for:)`、`groupIDForTesting(...)`、`selectPrimaryApps(...)`、provider-owned app scoring/stable-last-active helper、provider-owned app grouping/window merge extension、assembler-owned deterministic app scoring、`shouldIncludeRunningApplication(...)`、`shouldIncludeAppInAppLayer(...)`、nested app suppression helper 与 provider-owned `AXWindowStats` wrapper 已删除或降级为 runtime-owned 类型/委托调用，provider 和 assembler 不再拥有 app identity / app directory 派生入口。
- `RuntimeCGWindowEntry` / `RuntimeCGWindowCollection` 已迁入 `RuntimeCGWindowFacts.swift`，由 runtime CG fact payload 文件承载而不是定义在 `RuntimeSystemRepairFactProvider.swift` provider core 中；CG validity constraints 也由 `RuntimeCGWindowFacts.passesValidityConstraints(_:)` 拥有，provider supplemental CG merge、exact AX/CG assignment、activation readback/visibility 与 Chrome target-ordinal filtering 不再通过 `RuntimeSystemRepairFactProvider` 命名空间读取该 fact 规则；`RuntimeWindowRecord` 的 CG state refresh、exact-match CG attachment 与 synthesized known-CG evidence API 现在直接使用 top-level `RuntimeCGWindowEntry`；provider window-mapping resolution、known-CG synthesis、fullscreen artifact filters 与 AX recovery diagnostics 也已改为 top-level `RuntimeCGWindowEntry`。生产代码和 deterministic tests 不再通过 `RuntimeSystemRepairFactProvider.CGWindowEntry` / `CGWindowCollection` 嵌套名表达 CG fact ownership；迁移期 typealias 与 `CGWindowEntryForTesting` 已删除，provider testing helpers 也直接接收 top-level `RuntimeCGWindowEntry` fixtures。
- `RuntimeWindowRecord` 现在也拥有 window-layer CG fact 派生：`RuntimeWindowMappingResolution` 与 `windowLayerCGWindows(...)` / `knownCGWindowsByID(...)` 同层承载 mapping resolution payload 和 live valid CG facts + record-synthesized known-CG evidence 合并规则，并保持 live facts 优先、stale synthesized evidence 只作为补充。`RuntimeWindowMappingPresentationAssembler` 消费这个 WindowRecord-owned resolution/derived-fact boundary 来组装 window-layer entries；provider 不再在 window-mapping extension 文件定义 mapping resolution shape 或自己拼接 live/synthesized CG fact list。
- `RuntimeWindowMappingState` 现在拥有单次 AX/CG collection 对 WindowRecord state 的事务规则：AX collection presence / miss metadata、valid CG refresh 与 record seeding、matching 前清空 current AX attachment、fallback display state 更新、record lifecycle reconcile，以及 `currentAXToCG` / `validCGWindowIDs` / `lastAXWindowIDs` derived indexes 提交。`RuntimeWindowRecordStore.resolveStableWindowMapping(...)` 调用该 state transaction 并拥有后续 public/private/topology binding source orchestration；`RuntimeWindowMappingPresentationAssembler` 只把采样 fact 交给 store resolver，再消费返回的 resolution 组装 presentation entries。`RuntimeSystemRepairFactProvider` 的私有 app-window collection path 只调用 assembler，不再暴露 provider-owned `resolvedStableWindowEntries(...)` API。Search freshness contract 不变：bounded freshness barrier 成功提交新 generation 前，Search 只能读取 last committed index 的 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- `RuntimeWindowMappingState` 现在也拥有 sticky binding 复用的 state mutation：按 recorded `RuntimeWindowRecord` 顺序复用 AX ID / AX element continuity、运行 sticky conflict diagnostic、解析 title、调用 `record.applyExactMatch(...)`、维护本轮 `exactMatchesByAXWindowID` 与 assigned AX IDs，并返回 binding diagnostics。`RuntimeWindowRecordStore.resolveStableWindowMapping(...)` 消费 `applyReusableStickyBindings(...)` 的结果继续 public/private/topology binding orchestration；provider 不再直接写 sticky attachment、conflict fallback state，或继续承担 stable mapping resolution ownership。Search freshness contract 不变：barrier 未成功提交新 generation 前仍只能暴露 degraded/stale committed result。
- `RuntimeWindowRecordStore` 现在拥有 stable mapping resolution 与 mapping state commit 语义：`resolveStableWindowMapping(...)` 在 PID-keyed store 边界内完成 sticky reuse、public/private/topology exact binding、fullscreen/desktop sibling fallback binding、derived-index commit、lifecycle cleanup 与 final state commit；`commitState(_:for:)` 会把空 `RuntimeWindowMappingState` 作为删除处理，非空 state 才保留到 PID-keyed table。provider 不再暴露 `resolveStableWindowMapping(...)` / `resolvedStableWindowEntries(...)` 或手写空 state deletion branch；terminated PID cleanup 仍可直接调用 remove 作为生命周期 signal cleanup。Search freshness contract 不变：barrier 未成功提交新 generation 前仍只能暴露 degraded/stale committed result。
- `RuntimeWindowRecordStore` 现在拥有 Space topology 面向 WindowRecord table 的 evidence/scope 入口：`recordSpaceTopologySnapshot(...)` 包住 topology snapshot diff 写回与 affected record 标记，`affectedCGWindowIDsByPID(...)` 包住 current CG facts + recorded WindowRecord history 到 PID/window scope 的 pullback。provider CG collection 和 repair fact source 不再直接传递或读取 raw `mappingStatesByPID` 来完成 topology evidence。Search freshness contract 不变：barrier 未成功提交新 generation 前仍只能暴露 degraded/stale committed result。
- `RuntimeWindowRecordStore` 现在也拥有 verified-focus / AX-destroyed 面向 WindowRecord table 的 evidence entry：`recordWindowFocusVerification(...)` 包住 focused AX/CG readback exact evidence seeding，`clearDestroyedAXAttachment(...)` 包住 destroyed AX attachment downgrade 与 affected `CGWindowID` return。`RuntimeProjectionRepairProvider.swift` 里的 repair-provider reconciliation implementation 只调用 store semantic methods 并调度 coordinator，不再把 raw `mappingStatesByPID` inout 传给 evidence helper，也不暴露底层 `runtimeFactProvider` field。Search freshness contract 不变：barrier 未成功提交新 generation 前仍只能暴露 degraded/stale committed result。
- `RuntimeWindowRecordStore` 的 PID-keyed table 现在是 store-private storage：外部 production、TestingSupport 与 FlowTabTests 都不能再直接读写 `mappingStatesByPID`。seed / writeback 必须走 `setState(...)`、`commitState(...)`、`removeState(...)` 或 evidence/scope semantic methods；inspection 走 `state(for:)`。这把 raw table 从 public seam 降为 store implementation detail，避免后续 repair/surface 路径绕过 WindowRecord ownership。Search freshness contract 不变：barrier 未成功提交新 generation 前仍只能暴露 degraded/stale committed result。
- `RuntimeAXWindowEntry` 现在与 `RuntimeAXWindowState` / `RuntimeCurrentAXAttachment` 一起由 `RuntimeWindowRecord.swift` 承载，作为 production AX window fact payload；provider internals、WindowRecord exact-match AX attachment、window mapping/recovery helpers、activation public-AX recovery 与 deterministic fixtures 都直接使用 top-level `RuntimeAXWindowEntry`。生产路径已删除 `RuntimeSystemRepairFactProvider.AXWindowEntry` 嵌套 fact 类型；`AXWindowEntryForTesting` 也已删除，provider testing helpers 直接接收 top-level `RuntimeAXWindowEntry` fixtures，测试期 private exact bridge evidence 通过显式 `exactBridgeMatches` 输入表达。
- `RuntimeWindowAssignmentMatcher.swift` 现在承载 AX/CG public assignment 规则、public AX focused/main/minimized tie-breaker、assignment result DTO 与 ambiguous diagnostics；provider stable window mapping、topology resolver 与 `RuntimeAXWindowRecovery` 都调用该 runtime-owned matcher，不再通过 `RuntimeSystemRepairFactProvider.matchCGWindowAssignments*` 命名空间或 provider window-mapping file 表达 assignment ownership。
- `RuntimeAXWindowRecovery.swift` 现在承载 public AX recovery 决策、exact bridge/public-assignment fallback 与 recovery diagnostics；`RuntimeActivator` 直接调用 `RuntimeAXWindowRecovery.recoverAXWindowFromPublicSourcesWithDiagnostics(...)`，provider 不再拥有 public-AX recovery helper API。activation 成功证明仍必须回到 focused AX/CG readback，不以 recovery helper 返回值作为成功 oracle。
- `RuntimeActivator` 的 activation readback、target visibility、CG-only / same-Space route helpers 和 test override seam 现在也直接使用 top-level `RuntimeCGWindowEntry`；activation 成功证明仍来自 selected `CGWindowID` / focused AX/CG readback，而不是 provider-nested snapshot fact 命名。
- `RuntimeChromeWindowFocusBridge` 的 Chrome candidate selection / target-ordinal tie-break helpers 现在也直接接收 top-level `RuntimeCGWindowEntry`；Chrome-style activation 辅助路径不再把 current CG fact 输入表达成 `RuntimeSystemRepairFactProvider` namespace。
- `RuntimeProjectionService` 现在持有 `RuntimeProjectionRepairProviding` 窄接口与 `RuntimeMainTableProjectionBuilding` normal builder：service 只能通过 repair-provider methods 调度 pending/full-repair/search-barrier/ready-request lifecycle，app launch / app windows / selected-current-app dirty signals 与 Search freshness-barrier promotion 都只调用 semantic repair-provider methods，不再传 raw `RuntimeReconciliationReason`；service 只消费 repair-provider/fact-source 返回的 affected evidence、current-app repair evidence 与 full-repair evidence，再通过 main-table builder 从主表生成 normal projection rows；protocol 不再暴露 concrete `RuntimeReconciliationCoordinator`。默认 service wiring 进入 runtime-owned `RuntimeProjectionRepairProvider` facade 与独立 `RuntimeMainTableProjectionBuilder`，二者共享 `RuntimeWindowRecordStore`；repair-provider protocol 与 concrete facade 已共同独立到 `RuntimeProjectionRepairProvider.swift`，组合底层 `RuntimeSystemRepairFactProvider` fact source。AX destroyed、app termination 与 verified-focus repair-provider implementations 已 co-located in `RuntimeProjectionRepairProvider.swift`，并通过 facade-owned `RuntimeWindowRecordStore` / `RuntimeReconciliationCoordinator` 编排底层 state mutation，不再留在 service 文件中直接承载 coordinator mutation，也不再通过 extension 文件暴露底层 fact provider field。`RuntimeSystemRepairFactProvider` 本身不再直接 conform service repair protocol。CG fact payload 也已抽为 top-level `RuntimeCGWindowEntry` / `RuntimeCGWindowCollection` 并由 `RuntimeCGWindowFacts.swift` 承载，provider internals 与 tests 也直接使用 top-level CG fact 类型；`RuntimeSystemRepairFactProvider` 只能作为底层 fact-source/repair bridge 存在，不能被 feature surface 当作 hot-path snapshot read seam 重新扩张。
- AX live registry 批量写入现在命名为 `AXLiveWindowRegistry.replaceWindows(forPID:with:)`，表达长期 live registry 对某 PID 当前 AX window handles 的原子替换，而不是“刷新 snapshot”。底层 provider 采样后仍可写入该 registry 作为 AX/CG readback 与 destroyed routing evidence；这不新增 surface-local state、scheduler 或 Search 行为。Search freshness contract 不变：freshness barrier 未成功提交新 generation 时当前 Search 行为只能暴露为 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- `RuntimeProjectionRepairFactProviding` 现在是 repair/fallback 底层 fact-sampling 窄 contract，只暴露 AX window collection 与带 Space topology diff 的 CG collection；contract 与 `RuntimeSystemRepairFactProvider` 默认 conformance 由 `RuntimeProjectionRepairFactProviding.swift` 独立承载，`RuntimeProjectionRepairFactSource.swift` 只消费该 contract 聚合 repair/fallback facts。`RuntimeProjectionRepairProvider` / `RuntimeProjectionRepairFactSource` 依赖该 contract，而不是具体 `RuntimeSystemRepairFactProvider` 类型。`RuntimeSystemRepairFactProvider` 只是默认实现这个底层 CG/AX/Space fact source contract，不能重新扩张成 service/surface hot-path read seam；fact source 仍只在 scheduler repair、fallback、cold-start 兼容路径即时采样。Search freshness contract 不变：bounded freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 last committed index 的 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- `RuntimeProjectionRepairProvider` 不再保留底层 fact provider field；初始化时构造的默认 `RuntimeSystemRepairFactProvider` 只被注入 `RuntimeProjectionRepairFactSource`，由 fact source 私有持有 `RuntimeProjectionRepairFactProviding`。concrete repair facade 只持有 `RuntimeWindowRecordStore`、`RuntimeReconciliationCoordinator` 与 `RuntimeProjectionRepairFactSource`，避免后续 repair-provider implementation 又绕开 fact-source contract 直接调用 bottom CG/AX/Space sampling。
- `RuntimeSnapshotProvider.swift` 已重命名为 `RuntimeSystemRepairFactProvider.swift`，生产默认 wiring 现在构造 `RuntimeSystemRepairFactProvider` 作为底层 repair/fallback fact source。代码中不再保留 `RuntimeSnapshotProvider` 类型或 app target 文件引用；`RuntimeSnapshot` / full snapshot 只能作为已删除/历史迁移语境出现，不能重新成为 Switcher、Home、Search 或 activation 的 hot-path read boundary。

但当前实现仍有迁移对象：

- service 层 `RuntimeProjectionService.fallbackRuntimeSnapshot()` full snapshot bridge 与 concrete-only `fallbackLightweightAppSnapshot()` lightweight bridge 均已删除；`RuntimeProjectionServing` 已不再暴露 full snapshot bridge、同步 lightweight bridge 或 `currentCGWindowsByPID()` live CG z-order read，Switcher/Home 的 P0 首读路径已优先读取 projection，`Option+Tab` 缺 app-switcher projection 时只请求 shared runtime maintenance，不再同步调用 lightweight snapshot bridge；`Control+Tab` 缺 current-app projection 时只发送 runtime dirty/repair signal，不再同步调用 focused snapshot bridge。service-facing focused snapshot 兼容入口已删除，repair-provider app-local reconciliation pullback 现在直接返回 `RuntimeCurrentAppWindowPayload`；provider-facing `appWindowRepairPayload` / `focusedAppWindowRepairPayload` 兼容 API 与 `RuntimeAppWindowRepairPayload` 类型级 wrapper 已删除。
- `RuntimeSystemRepairFactProvider.snapshot()` wrapper 已删除；full repair 现在通过 repair-provider `fullRepairEvidence()` 进入 scheduler repair/fallback，并调用 `RuntimeProjectionRepairFactSource.collectFullRepairRunningAppFacts()` / `collectFullRepairWindowFacts(for:)` 采集 app-layer running apps、explicit app directory entries、cleanup/prune、onscreen/all CG、AX window data 与 rank facts来更新主表，但 drainer/service 只接收 `RuntimeFullRepairEvidence(appDirectoryEntries:)`。provider-facing `fullRepairProjectionPayload()` 已删除；full-repair app/context rows 只剩 `FlowTab/TestingSupport` fixture / assembler-test shape，不参与正常 service commit 或 diagnostic read。focused-PID current-app repair 通过 `collectRepairRunningApps()` 只采集 running-app lookup，再通过同一 fact-source 边界采集 rank/CG/AX window facts，并通过 `RuntimeAppWindowSelectionFacts` 消费 scoped app-window selection、merged-window 与 minimized-only eligibility；focused-PID path 保留 projection timing evidence 但不再由 builder 直接编排底层 collection 或 scoped app-directory selection/filtering。该路径性质是 scheduler repair/fallback，不是 hot-path read。
- Phase 3 P0 已移除 Switcher session-start 后的 surface-owned background full snapshot delayed/apply path；`LiveSwitcherModel` 只向 `RuntimeProjectionService.requestAppSwitcherProjectionMaintenance(reason:)` 发送 runtime maintenance request，旧 full snapshot bridge 不再由 Switcher open 后台路径调用。
- Search 已迁移到 maintained `committedSearchIndex` read；runtime maintenance 只能在 projection cache 覆盖当前 generation 且 barrier 无 deferred/pending repair 时，通过 freshness barrier 原子提交新的 committed index。production `stagingSearchIndex` / repaired-payload barrier commit API 已删除，普通 app-switcher projection commit 与 app termination cleanup 不会生成 current-generation committed Search success；真实 committed-index UI proof 与外部 pressure proof 仍是 gap。
- `RuntimeSearchIndexRead` 现在拥有 Search read 的 readiness/result-state 命名：只有 committed index 已覆盖 runtime 当前 generation 时才返回 `committedGenerationValidated` / `committedGenerationResult`；`degradedStaleCommitted` 一律对应 `degradedStaleCommittedResult`，`missingCommittedIndex` 对应缺 committed index。Switcher 只消费该 runtime-owned contract，不再在 surface 层自行解释 stale/fresh/complete 状态。
- Search freshness barrier 的 runtime drain 现在只通过 repair-provider `promoteSearchFreshnessBarrierRequests(now:)` 语义入口请求 promotion；provider 内部再把 pending/waiting retry repair 提升为 high-priority `searchFreshnessBarrier` request，然后 service 按固定 ready-repair batch bound 执行。scoped repair outcome 在 drainer/service 边界只作为 `RuntimeCurrentAppRepairEvidence` 触发主表 projection rebuild；Search index 只允许通过覆盖当前 runtime generation 的 committed projection cache 原子提交。超过该 batch、没有覆盖当前 generation 的 projection cache commit，或出现 deferred/pending repair 时，store 只保留 last committed index 的 stale/degraded read，不把部分 repair 结果提升为最新搜索结果。
- 旧 Search staging scoped-repair 输入已被 Phase 6 删除：`RuntimeReadModelStore` 不再暴露 `commitSearchFreshnessBarrierPayloads(...)`，也不再维护 production `stagingSearchIndex`。barrier drain facts 只作为 repair/evidence trigger 更新主表 projection cache；Search index commit 只走 `commitSearchFreshnessBarrierFromProjectionCache(...)`。即使 scoped current-app projection commit 已清掉普通 dirty/pending metadata，只要 freshness barrier 没有成功提交新 generation，Search 读到的 last committed index 仍只能是 `degradedStaleCommitted` / `degradedStaleCommittedResult`，不能被命名为 verified/fresh/complete/current-generation committed。
- Space topology 生产路径已有 snapshot/diff 与 display-level signature；`collectCGWindows` diagnostic 已输出 signature change/display/space/window summary，`RuntimeProjectionService.signalSpaceTopologyChanged()` 会把 diff 的 affected `CGWindowID` 与 signature summary 同步写入 read-model dirty/freshness metadata，并通过 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 从 app directory + WindowRecord 主表预提交 app-switcher/Home summary projection cache，再驱动 scoped repair。该 projection 不消费 Space signal 里的 sampled CG rows 作为 normal payload，dirty/pending repair metadata 会保留，Search stale committed read 也会携带该 Space signature evidence；freshness barrier 未提交新 generation 前仍只能是 degraded/stale committed result。代表性 noisy fullscreen fixture UI 已断言 signature diagnostic；系统权威 fullscreen owner、多显示器与更广真实拓扑 pressure 仍需继续推进。

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
- `RuntimeFullRepairProjectionAssembler` 已删除 current-app payload derived app directory fallback；调用方必须显式传入 full-repair app directory entries 或显式空 evidence，避免把 scoped current-app projection inputs 升级成 full app directory 主表。
- app termination signal 在 `RuntimeAppDirectoryState` 有同 appID 多 PID entries 时只剪掉 terminated PID 的 directory entry，并保留 grouped app、Home summary 与 committed Search index 为 degraded/stale committed projection；dirty metadata 与 `appTerminated:<appID>` repair scope 会驱动后续 scoped repair，重复 terminated-PID signal 不会推进 generation。
- `RuntimeProjectionService` 成为 read model store owner；旧 provider 采样桥只负责生成兼容数据，service 负责提交 projection 或标脏 metadata。
- `RuntimeProjectionServing` 暴露 projection read seam：`readAppSwitcherProjection()`、`readHomeSummaryProjection()`、`readCurrentAppWindowProjection(appID:)` 与 `runtimeReadModelDiagnostics()`，供 Phase 2 迁移 hot-path read API。
- app/window dirty、app launch/termination、AX destroyed、Space topology、activation verified-focus signal 均会进入 store generation/dirty metadata，避免 Switcher、Home、Search 各自扩张 surface-local freshness state。

仍保留的 P1/P2：

- projection builders 仍由旧 snapshot/home/focused 兼容桥提交，尚未完全从底层 `RuntimeWindowRecord`、app directory、Space topology 主表独立 rebuild。
- PID-keyed app directory state 已作为 `RuntimeAppDirectoryState` 进入 runtime-owned app directory boundary，并由 `RuntimeReadModelStore` 持有；app launch lifecycle signal、同 appID 多 PID termination scoped pruning 和 full/current-app repair payload 都会显式走 app directory entries，context-derived fallback 已删除，`RuntimeAppDirectoryProjection` 只作为 read 派生物存在；但 directory entries 仍未升级为独立长期 fact source，从 WindowRecord/app directory/topology 主表直接 rebuild projection 仍是 Phase 5 gap。
- Switcher/Home 首帧只读 projection 的 P0 已在 Phase 2 落地；旧采样桥仍作为 service-owned repair/fallback 兼容入口，不是目标热路径。
- Search committed index 已在 Phase 4/6 落地到 `RuntimeReadModelStore` ownership，并且 production staging 入口已删除；Phase 1 的剩余 gap 不再是 Search index 缺失，而是 projection builders 尚未完全从底层 `RuntimeWindowRecord`、app directory、Space topology 主表独立 rebuild。

验证：

- deterministic tests 证明主表与派生索引一致。
- projection rebuild 不依赖 feature surface 局部状态。
- `FlowTabPriorityCoverageTests.testRuntimeReadModelStoreCommitsProjectionsAndMarksDirtyMetadata` 证明 store commit/read、generation、dirty metadata 与 current-app projection scope。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals` 证明 service owns store，旧 repair bridge 会提交 app projection，dirty signal 会标脏 projection metadata。

### Phase 2: Hot path read API

状态（2026-06-16）：P0 已落地，P1/P2 保留。

- 新增 `readAppSwitcherProjection()`。
- 新增 `readCurrentAppWindowProjection(appID/pid)`。
- Search read 在 Phase 2 保持 deferred，后续由 committed search index 边界承接，不能成为第二个 runtime store。
- 新增 Home summary/detail projection read。
- 这些 read API 不进入 sampling queue，不触发 CG/AX/Space 采样。

已落地的 P0：

- `LiveSwitcherModel` 的 app-layer fast snapshot 只读取 `RuntimeAppSwitcherProjection`；projection 存在时不会调用 `lightweightAppSnapshot()` 或全量 snapshot provider，projection 缺失时返回空首帧并请求 shared runtime projection maintenance。
- Switcher terminate refresh 不再读取 full snapshot bridge；后续 Phase 6 已删除 `RuntimeReadModelStore.markAppTerminated(...)` direct pruning API，termination 只更新 main-table app directory/current-app/dirty metadata，并让 runtime maintenance 从主表重建 projection cache，不重写 committed Search index。Switcher 只读取更新后的 projection，projection 缺失时只请求 shared runtime maintenance 并保留当前 session。Session/Search behavior tests now prove this through `RuntimeProjectionServing` projection-read counters, runtime maintenance/termination signals, and committed Search read diagnostics instead of dead full/lightweight snapshot counters；termination 后 Search 仍必须是 degraded/stale committed result，不能命名为 current-generation committed。
- `RuntimeProjectionServing` 已不再向 feature surface 暴露泛化的 `snapshot()` 方法或 full snapshot bridge。`RuntimeSystemRepairFactProvider.snapshot()` wrapper 已删除；service-facing full repair primitive 是 `fullRepairEvidence()`，provider-facing `fullRepairProjectionPayload()` 也已删除，full-repair payload 仅保留为 `FlowTab/TestingSupport` fixture/assembler-test shape。
- `RuntimeProjectionServing` 已不再向 feature surface 暴露同步 `lightweightAppSnapshot()` 方法；`RuntimeProjectionService.fallbackLightweightAppSnapshot()` 和 provider `lightweightAppSnapshot()` 已删除，feature surface 只能读 app-switcher projection 或发送 runtime maintenance signal。
- `RuntimeProjectionServing` 已不再向 feature surface 暴露 Home provider-backed refresh bridge；Home summary/detail refresh 只能读取 Home summary/detail projection API，projection 缺失时返回当前 committed UI state 并发送 shared runtime maintenance/app-window dirty signal。app-switcher projection 不能作为 Home detail compatibility/read-model fallback，也不能由 Home surface 层自行派生 summary/detail。
- selected/current app window refresh 只读取 `RuntimeCurrentAppWindowProjection`；projection 存在时不会调用 Home snapshot bridge，projection 缺失时只向 shared runtime 发送 app-window dirty signal 并保持 app-cycle 投影状态。
- Home window activation 使用调用方传入的 cached detail projection 或 `RuntimeCurrentAppWindowProjection` 构造 activation target；缺 projection 时只向 shared runtime 发送 app-window dirty signal，不再同步调用 Home snapshot bridge。
- 迁移期 `RuntimeProjectionServing.homeAppSnapshotSynchronously` 兼容入口已删除；生产 surface 无法再通过 shared runtime service 重新引入该同步 Home snapshot bridge。
- `Control+Tab` focused-current-app startup 只读取 `RuntimeCurrentAppWindowProjection`；projection 存在时不会调用 provider repair pullback，projection 缺失时只向 shared runtime 发送 app-window dirty signal 并降级退出。
- 迁移期 focused snapshot 兼容入口已从 `RuntimeProjectionServing` 删除；生产 surface 无法再通过 shared runtime service 重新引入该同步 focused snapshot bridge。
- `LiveSwitcherModel` startup recency 不再读取 live focused AX 或 live CG z-order；`Option+Tab` / `Control+Tab` 仅应用 committed `RuntimeWindowRecencyTracker` evidence 和 projection order，`RuntimeProjectionServing` 也不再向 feature surface 暴露 `currentCGWindowsByPID()`。
- Home initial summary projection、summary refresh、single-app summary、selected app detail 通过 `HomeRuntimeProjectionReader`/`HomeRuntimeRefreshReader` 读取 projection，Home refresh diagnostics 使用 `RuntimeLogCategory.projection`；projection 缺失时不再调用旧 Home snapshot service，concrete `RuntimeProjectionService` 的 provider-backed Home fallback bridge 已删除。
- Home activation / projection reader behavior tests now name their injected `RecordingRuntimeProjectionService` fixtures `runtimeProjectionService`; the test double no longer carries Home snapshot fallback recorders or Home summary request counters, and `FlowTabTests+HomeWindowActivation` now proves the old Home bridge absence through Home/app-switcher/current-app projection-read counts plus dirty-signal behavior instead of dead full/lightweight snapshot counters.
- `FlowTabPriorityCoverageTests+SessionAndPanelSearch` no longer uses full/lightweight snapshot fake counters as proof for Search/session paths. App search and window search tests assert `readCommittedSearchIndexForSearch()` diagnostics (`committedGenerationValidated` / `committedGenerationResult` / no freshness-barrier request), app-layer panel tests assert `readAppSwitcherProjection()` plus shared maintenance, and focused-window panel tests assert `readCurrentAppWindowProjection()` plus no selected-current-app dirty signal. `SwitcherSearchCoordinator` production code no longer exposes a `[AppSwitchCandidate]`/session-app rebuild API; Search index rebuild now accepts only `RuntimeSearchIndexProjection`, while tests seed coordinator rule coverage through explicit committed-index projection fixtures.
- Preview paging/session-pinning/provider behavior tests now use the shared `makeAppSwitcherProjectionModel` helper with a `runtimeProjectionService` return label and assert app-switcher projection reads plus `.switcherSessionStarted` maintenance requests. Focused preview capture/cache behavior tests assert current-app projection reads plus no app-switcher projection reads and no selected-current-app dirty repair signal. The `WindowPreviewSessionPinning`, terminal provider resolver, and focused-preview coverage no longer treat dead full/lightweight snapshot request counters as service ownership proof, and `RecordingRuntimeProjectionService` no longer exposes those counters as a test oracle.
- `RuntimeAppSwitcherProjection.appCycleApps` 与 `RuntimeHomeSummaryProjection.summary(for:)` 作为 shared projection helper，避免 surface 复制 app-cycle projection assembly 或 summary lookup 状态。

仍保留的 P1/P2：

- Search hot-path read 已由 Phase 4/6 的 committed index 和 readiness-bearing `readCommittedSearchIndexForSearch()` 承接；不再新增 surface-facing `readSearchWindowProjection()`，避免 Search 成为第二个 runtime store。
- Switcher session-start background full snapshot 已在 Phase 3 P0 降级为 runtime-owned projection maintenance request；priority/coalescing/cancellation/backoff breadth 仍留给 Phase 3 P1/P2。
- 本阶段新增的是 behavior/pressure 证明；真实 UI/E2E 拓扑 proof 沿用既有 fixture 覆盖，未新增专门的 projection-read UI 断言。

验证：

- targeted unit/behavior 证明 hot read 不调用采样 provider。
- pressure proof 记录 `Option+Tab` / `Control+Tab` 首帧不被后台 maintenance 阻塞。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelStartsAppSessionFromRuntimeProjectionWithoutLightweightSampling` 证明 app switcher projection 存在时读取 committed app-switcher projection，且在 maintenance disabled fixture 下不会发送 surface-local repair request。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelSelectedAppWindowSnapshotUsesRuntimeProjectionWithoutHomeSampling` 证明 selected/current app window projection 存在时不会调用 Home snapshot bridge；`testLiveSwitcherModelSelectedAppWindowSnapshotSignalsRuntimeRepairWhenProjectionIsMissing` 证明 projection 缺失时即使旧 Home snapshot bridge 有污染数据也不会被读取，只会发送 shared runtime app-window dirty signal。
- `FlowTabTests.testHomeWindowActivationControllerUsesRuntimeProjectionWithoutHomeSnapshotBridge` 证明 Home window activation 读取 runtime current-app window projection 后提交 activation target，且不会发送 app-window dirty signal；`testHomeWindowActivationControllerSignalsRuntimeRepairWhenProjectionIsMissing` 证明 detail projection 缺失时只读取 Home summary projection 边界以定位 pid，然后发送 shared runtime app-window dirty signal。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelFocusedWindowSessionUsesRuntimeProjectionWithoutFocusedSampling` 现在用 current-app projection read count 与 no selected-current-app dirty signal 证明 `Control+Tab` focused-current-app projection 存在时只读 committed projection；`testLiveSwitcherModelFocusedWindowSessionSignalsRuntimeRepairWhenProjectionIsMissing` 证明 projection 缺失时只读一次 current-app projection 并发送 shared runtime app-window dirty signal。这两个 focused session tests 不再用 dead snapshot counters 作为 focused snapshot bridge absence 的主证明。
- `FlowTabPriorityCoverageTests.testSwitcherPanelControllerDelayedAutoEnterUsesCommittedSelectedAppProjection` 现在用 app-switcher projection read count、`.switcherSessionStarted` maintenance request、delayed current-app projection read count 与 no selected-current-app dirty signal 证明延迟进入 window layer 只消费 committed selected-app projection，不再用 full/lightweight snapshot fake counters 作为旧路径反证。
- `FlowTabPriorityCoverageTests.testAppDelegateReloadedHotkeyMonitorRoutesCallbacksToSwitcherSession` 现在用 app-switcher / current-app projection read counts、`.switcherSessionStarted` maintenance request 与 no selected-current-app dirty signal 证明 reloaded `Option+Tab` / in-app window hotkey callbacks 进入 projection-owned session startup，而不是用 full/lightweight snapshot fake counters 作为主证明。
- `FlowTabPriorityCoverageTests.testAppDelegateLaunchOpenSwitcherWaitsForStableProjectionBeforeKeepingPanelOpen` / `testAppDelegateLaunchOpenSwitcherWithoutResultsDoesNotEnterSearchAndSeedZeroSkipsSeededLogs` 现在用 app-switcher projection read counts、`.switcherSessionStarted` maintenance reasons 与 no committed Search index read 证明 launch-open-switcher bootstrap 只读 committed app-switcher projection，空 projection 不进入 Search，也不把 full/lightweight snapshot fake counters 当主证明。
- `FlowTabTests.testHomeRuntimeProjectionReaderUsesRuntimeProjectionsWithoutSnapshotBridge` 证明 Home summary/detail reader 读取 Home summary projection 与 current-app projection，不回退到 app-switcher projection 或 lightweight snapshot；`testHomeInitialAppSummaryReaderDoesNotUseLightweightSnapshotFallback` 证明 initial reader 只读 Home summary projection，missing projection 时返回空且不请求 maintenance；`testHomeRuntimeProjectionReaderDoesNotDeriveHomeDataFromAppSwitcherProjection` 证明 app-switcher-only contamination 不能被 Home surface 派生成 summary/detail，也不能驱动 no-switchable wait-cache 判断；`testHomeRuntimeRefreshReaderSignalsRuntimeRepairWhenProjectionIsMissingWithoutHomeFallback` 证明 projection 缺失时污染的 Home fallback 数据不会被读取，只发送 shared runtime maintenance/app-window dirty signal 并保留当前 committed UI state。
- `FlowTabPriorityCoverageTests.testRuntimeReadModelStoreMarksTerminatedAppForMainTableProjectionWithoutRefreshingSearch` 证明 terminated app lifecycle signal 在 store 边界只更新 app directory/current-app/dirty metadata，不同步剪 app-switcher projection 或 committed Search index；旧 committed Search rows 必须继续作为 `degradedStaleCommittedResult` 暴露，直到 bounded freshness barrier 成功提交新 generation。`FlowTabTests.testHandleApplicationTerminatedRefreshesFromRuntimeProjectionWithoutFullSnapshot` 证明 Switcher termination refresh 只消费 runtime app-switcher projection、shared maintenance/termination signal 与 committed Search read diagnostic；`FlowTabPriorityCoverageTests.testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterAutomaticTerminationRefresh` 现在用 app-switcher projection read count 与 termination signal 证明 panel refresh path，而不是 full/lightweight snapshot fake counters；`FlowTabPriorityCoverageTests.testLiveSwitcherModelHandleApplicationTerminatedRefreshesSessionAndKeepsPreferredNextSelection` / `testLiveSwitcherModelHandleApplicationTerminatedIgnoresUntrackedApp` 进一步用 model-level app-switcher projection read counts 与 termination signal/no-signal evidence 证明 app termination refresh 和 unrelated termination ignore path 都不把旧 snapshot counters 当主证明。
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
- full repair 在 `RuntimeProjectionService` 的 drain/outcome 边界已改为 `RuntimeFullRepairEvidence`，service 不再把 `RuntimeSnapshot` 或 full-repair projection rows 作为 in-flight repair result 保存或提交；默认 executor 直接调用 runtime repair-provider `fullRepairEvidence()`，provider-facing `RuntimeSystemRepairFactProvider.snapshot()` wrapper 与 `RuntimeSnapshot` 类型已删除。
- full repair fallback 提交已分成 clean cold-start projection 与 dirty degraded fallback：没有 app-switcher projection 且没有 dirty/pending repair metadata 时只允许提交 projection/app-directory evidence；它不能直接生成 verified/current-generation committed Search index。dirty/pending 状态下的 full repair 只能提交 degraded app-switcher projection，必须保留 dirty/freshness metadata 和 last committed Search index；Search 只有在 freshness barrier 成功提交新 generation 后才能进入 fresh/complete/latest 结果态。
- Search freshness barrier 的 promote/drain 明确排除 full repair fallback；barrier 只能完成 bounded scoped repair、把 scoped outcome 降级为 evidence trigger，经主表 projection cache 覆盖当前 generation 后提交新 Search generation，才能进入最新搜索结果态。pending full repair 可能被后来的 high-priority scoped repair 取消，但不会被 Search 提升、执行或命名为 fresh/complete/latest。

仍保留的 P1/P2：

- full repair fallback 的 target / high-priority cancellation 已落到 scheduler；scoped repair retry exhausted 后会自动降级安排 low-priority full repair fallback，并且 dirty fallback commit 不会清 dirty 或刷新 committed Search。更广 backoff policy 与更细粒度 facts 拆分仍需扩展。
- service 层 feature-facing full snapshot fallback 已从 `RuntimeProjectionService` 删除；full repair outcome 现在也只携带 `RuntimeFullRepairEvidence`。full repair service-facing builder 已命名为 repair-provider `fullRepairEvidence()`，性质是 low-priority repair/cold-start evidence 输入；provider-facing `RuntimeSystemRepairFactProvider.snapshot()` wrapper 与 `RuntimeProjectionRepairProvider.fullRepairProjectionPayload()` 均已删除，不是 Switcher/Home/Search hot-path read API，也不是 Search freshness barrier 的成功 oracle。full-repair payload 只保留为 `FlowTab/TestingSupport` fixture/assembler-test shape。
- `RuntimeProjectionService` 的 provider 依赖已收窄为 `RuntimeProjectionRepairProviding`，default executor 只通过该 repair/fact-provider contract 消费 scoped repair、Space topology affected-target derivation 与 full repair projection payload。默认 implementation 是 runtime-owned `RuntimeProjectionRepairProvider` facade；测试若需要观察同一个 provider 的 WindowRecord/coordinator state，也必须显式把 `RuntimeSystemRepairFactProvider` 包进该 facade，而不是让 provider 本体 conform service repair protocol。该 contract、provider internals 与 deterministic tests 现在使用 top-level runtime CG fact types，不再暴露 `RuntimeSystemRepairFactProvider.CGWindowEntry/Collection` 嵌套名；迁移期仍保留 `RuntimeSystemRepairFactProvider` 名称作为底层 fact-source/repair bridge，但 service/executor 边界不再拿完整 snapshot provider 类型。
- scoped repair affected-target derivation 现在由 `RuntimeProjectionRepairProvider.swift` 里的 repair-provider implementation 组装；`RuntimeAppWindowReconciliationResult` 也定义在同一文件，与返回它的 `RuntimeProjectionRepairProviding` contract 同层。`RuntimeSystemRepairFactProvider+Reconciliation.swift` 与 `RuntimeProjectionRepairProvider+Reconciliation.swift` 均已删除，Space topology / verified focus / AX destroyed evidence 写回现在只通过 `RuntimeWindowRecordStore` semantic methods 进入；raw table mutation helper 已降为 store 文件内 private implementation detail，provider 与 repair-provider 不再传入 WindowRecord mapping state。
- Search committed index 已在 Phase 4/6 推进；真实 committed-index UI proof 与外部 pressure proof 仍需补齐。
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
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceMaintenanceSchedulesLowPriorityFullRepairWhenProjectionMissing` 和 `testRuntimeProjectionServiceFullRepairFallbackCommitsMainTableProjectionWithoutRefreshingSearch` 的 injected executor 已改为返回 `RuntimeFullRepairEvidence`，编译层证明 service-level full repair outcome 不再接受 `RuntimeSnapshot` result 或 projection rows。
- `FlowTabTests.testUITestMockDatasetBuildsExplicitFullRepairProjectionPayloadWhenLaunchFlagEnabled` 证明 UI-test fixture 可显式构造 full-repair app/context payload，不再经过 provider `snapshot()` wrapper 或 repair-provider payload facade；`testRuntimeProjectionServiceDefaultFullRepairCommitsEvidenceThroughMainTableProjection` 证明默认 full repair executor 通过 runtime-owned `RuntimeProjectionRepairProvider.fullRepairEvidence()` 提交 app directory evidence，再经主表 builder 生成 projection，不经 injected snapshot result，也不要求 `RuntimeSystemRepairFactProvider` 本体 conform service repair protocol。
- `FlowTabPriorityCoverageTests.testRuntimeFullRepairProjectionAssemblerSortsCurrentAppInputsAndBuildsContexts` 与 `testRuntimeFullRepairProjectionAssemblerPreservesMinimizedSeedsAndFallbackGroupIDs` 证明 full-repair payload assembly 只通过 `RuntimeCurrentAppWindowProjectionAssemblyInput` production entry 组装 app-switcher candidates 与 contexts，不再暴露 provider-owned 或 testing-only row assembly API。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceSearchFreshnessBarrierDoesNotPromoteOrDrainFullRepairFallback` 证明 Search freshness barrier 不提升、不 drain full repair fallback；在没有新 generation 成功提交时，Search 仍返回 degraded/stale committed result。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRetryExhaustsToFullRepairFallback` 证明 Search barrier 内 scoped repair exhausted 后只留下 low-priority full repair fallback，committed search index 继续保持 degraded/stale，不提交 partial repair intermediate result。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceSearchFreshnessBarrierDoesNotCommitWithoutRepairEvidence` 证明本轮 barrier 只有 completed request 但没有 repair evidence 时，不会提交新 Search generation，也不会清 dirty metadata 或把 repair 中间态暴露成最新完整结果。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceFullRepairFallbackCommitsMainTableProjectionWithoutRefreshingSearch` 证明 retry exhausted 后真正执行 full repair fallback 时，runtime 也只能从主表提交 degraded app-switcher projection，Search 仍读取 last committed index + dirty metadata，不清 dirty 状态，也不进入最新完整结果态。
- `FlowTabTests.testOptionTabWindowScalePressureKeepsSelectedAppApplyAndPreviewCaptureBounded` 证明 1,000-window selected-app projection/snapshot apply、window-layer entry 和 current-page preview item 生成保持 bounded；本轮 p95 分别为 0.68ms、0.01ms、0.24ms。
- 本轮 targeted `FlowTabPriorityCoverageTests` full repair / Search barrier 6 个用例通过；类级 `FlowTabPriorityCoverageTests` 当前执行 347 tests，仍有非本阶段 `testSwitcherPanelControllerRecoverableOcclusionKeepsSessionVisible` visibility diagnostic 断言失败，未作为本阶段 runtime ownership blocker。
- P2 待补：完整 full repair fallback facts 拆分、更广 backoff policy、真实 topology UI/E2E 与 pressure proof。

### Phase 4: Search read model

- Search index 从 `RuntimeWindowRecord` + app directory 投影。
- Search index 目前只有 surface-readable committed read；若后续重新引入 internal staging，也只能作为 runtime maintenance 私有验证状态。
- 日常 maintenance 只能用 dirty/current/recent/affected scopes 更新 runtime main tables / projection cache，并在 freshness barrier 验证 generation 覆盖后原子提交 committed index。
- Search 激活先做 freshness validation；若 committed index 未覆盖当前 app/CG/Space/AX dirty generation，则执行 bounded freshness barrier。只有 barrier 成功提交新 committed generation 后，Search 才能进入最新搜索结果态；未提交时的当前行为必须保持 `degradedStaleCommittedResult` / stale committed read。
- 当前迁移状态：Search 已改为读取 runtime-owned committed index；`RuntimeReadModelStore` 提供 `committedGenerationValidated` / `degradedStaleCommitted` / `missingCommittedIndex` freshness read，并由 `RuntimeSearchIndexRead` 同步返回 surface 必须记录的 result state。`degradedStaleCommitted` 时仍返回 last committed index + dirty metadata，并由 `RuntimeProjectionService` 发起 bounded runtime maintenance drain；这个返回值是 degraded/stale committed result，即使有可展示 entries，也不能称为 fresh、complete、latest 或 current-generation result。Search freshness barrier 会把 pending/waiting retry repair 提升为 high-priority `searchFreshnessBarrier` request，每次只 drain 固定数量的 ready scoped repair；completed scoped repair 只作为 `RuntimeCurrentAppRepairEvidence` 触发主表 projection rebuild，只有 committed projection cache 的 `sourceGeneration` 覆盖当前 runtime generation、无 deferred/pending repair，并原子提交新 Search generation 后，Search 才能进入 `committedGenerationValidated` / `committedGenerationResult`。completed request 若没有让 projection cache 覆盖当前 generation，则不能借用 repair 中间态、普通 projection commit、termination metadata update 或 stale committed index pruning 提交新 committed generation。barrier 未提交、repair deferred、batch bound 后仍有 pending repair，或 retry exhausted 后执行 low-priority full repair fallback 但仍有 dirty metadata 时，当前行为必须暴露为 `degradedStaleCommitted` / `degradedStaleCommittedResult` + dirty/freshness metadata，不回退到 session completeness、同步 full sampling，也不把该结果命名为 fresh/complete/latest。Search coordinator 生产索引重建入口也只接受 `RuntimeSearchIndexProjection`；既有 coordinator rule/pressure tests 通过 test-target fixture 把 sample apps 转为 committed-index projection，而不是要求生产保留 session-app index source。Search committed-index behavior tests now prove this through `RuntimeSearchIndexReadDiagnostic` (`source=committedRuntimeIndex`, `readiness`, `resultState`, generation coverage) plus explicit freshness-barrier request assertions, rather than relying on dead full/lightweight snapshot counters in the recording service fixture.
- dirty/pending app 只能作为 barrier/blocker/log 状态，不作为正常搜索结果状态。
- Search 激活可以提升 repair priority，但不能同步拉全量 AX tree 才开始搜索。

验证：

- session window 不完整时，Search 仍只读取 committed search index，不依赖 session completeness。
- 同一 committed generation 下连续搜索结果稳定。
- background repair 中间态不会暴露给 Search。
- freshness barrier 未完成时，不能把旧/部分 index 标记为最新完整。
- `FlowTabTests.testLiveSwitcherModelSearchReportsDegradedStaleCommittedIndexUntilFreshnessBarrierCommits` 证明 stale committed Search read 即使返回可展示 entries，也必须记录 `readiness=degradedStaleCommitted`、`resultState=degradedStaleCommittedResult`、`degraded=1`、`freshnessBarrierRequested=1` 与 `committedIndexCoversCurrentGeneration=0`，并且不得出现 fresh/complete/latest/current-generation result 命名。
- `FlowTabPriorityCoverageTests+SessionAndPanelSearch` 的 model-level Search/session result apply cases 从 runtime-owned committed projection service 启动，并断言 Search entry / app result apply / window result apply / window target commit 不调用 full/lightweight snapshot 请求。

### Phase 5: Space signature 与真实拓扑证明

- 建立 display-level Space signature。
- normal/fullscreen 转换通过 signature/diff 快速判定。
- affected `CGWindowID` 转 scoped app repair。
- 当前迁移状态：`RuntimeSpaceTopologySnapshot` 已能派生 display-level signature，signature 覆盖 current space、space membership、window membership 与 fullscreen window；`RuntimeSpaceTopologyDiff` 携带 previous/current signature，normal/fullscreen 状态变化可通过 signature/diff 标记 affected `CGWindowID` 并进入已有 scoped repair。runtime `collectCGWindows` diagnostic 已携带 signature summary，Space topology signal 已把 diff 的 affected `CGWindowID` 写入 `RuntimeReadModelStore` dirty metadata，而不是只让 coordinator 持有 affected request；真实 noisy fullscreen fixture UI 已在每次确认激活后断言 `signatureChanged`、display/space/window/fullscreen count 与 signature summary，代表性真实 Space signature proof 已闭环。
- Phase 5 本轮 P0 继续收窄 presentation ownership：`RuntimeWindowPresentationFilter` 现在拥有 duplicate fullscreen geometry host / topology content surface 去重规则，并作为 provider `presentation-final` 与 ordering 的最终 presentation cache 边界。规则只丢弃无 AX/activation handle、off-desktop Space、fullscreen-like geometry、同 title/Space 且包含强 topology content surface 的 CG-only host；provider 不新增 surface state、retry/debounce 或 Space 私有 API 依赖。P1 行为覆盖包含 direct duplicate host/content pair 与两阶段 CGID 从 desktop window 迁入 fullscreen geometry host 后的新 topology content surface，证明最终 window list 保持四个用户窗口。UI runtime-log oracle 同时修正为保留 FlowTab prelaunch 之前的 log snapshot，避免 prelaunch path 已经产生日志时被二次 reset 丢证据。Search freshness contract 不变：freshness barrier 成功提交新 generation 之前，当前 Search 行为只能暴露为 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
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

- Phase 5 本轮 P0 继续补 Space signature 到 read-model freshness metadata：`RuntimeSpaceTopologySignalFacts` 现在携带 `affectedCGWindowIDs` 与 `signatureSummary`，`RuntimeProjectionService.signalSpaceTopologyChanged()` 把它提交给 `RuntimeReadModelStore.markSpaceTopologyDirty(...)`，store diagnostics 与 projection/Search freshness 都会带 `spaceTopologySignatureSummary`。这让 Search 在 freshness barrier 未提交新 generation 时读取 last committed index 的 stale/degraded result，也能携带触发 stale 的 Space signature evidence；不会在 Search hot path 同步采样 CG/AX/Space，也不新增 surface-local topology state。真实多显示器/fullscreen owner/topology pressure 仍是 gap；Search freshness contract 不变：freshness barrier 未成功提交新 generation 时当前行为必须暴露为 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 app-rank MRU state proof boundary：`SystemAppMRUTracker` 不再暴露 `resetStateForTesting` / `recordActivationForTesting` / `removeForTesting` / `trackedMRUOrderForTesting` / `handleApplicationNotificationForTesting` 这组 production file 内的 testing facade；tests 现在使用独立 `SystemAppMRUTracker` 实例与生产语义的 MRU operations 验证 activation ordering、termination removal、pruning 与 notification handling，shared tracker 不再被测试 reset/mutate。`RuntimeAppRankProvider` 仍组合 `SystemAppMRUTracker.shared` 与 CG window stack fallback 作为 repair/fallback projection assembly 的 app-rank fact source；这不改变 ranking、sampling、Search、activation 或 surface 行为。Search freshness contract 不变：freshness barrier 未成功提交新 generation 时当前行为必须暴露为 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 remote AX deterministic proof boundary：`RuntimeAXRemoteWindowResolverForTesting` 已从 `FlowTab/Infrastructure/Runtime/RuntimeAXRemoteWindowResolver.swift` 移到 `FlowTab/TestingSupport/RuntimeAXRemoteWindowResolverTestSupport.swift`，生产 resolver 文件不再在底部暴露 Testing facade；resolver 只保留生产语义的 remote token construction、scan policy/completeness、resolve failure classification 与 merge rules，测试 support facade 通过这些 production rule APIs 证明 deterministic contracts。provider 仍只在 AX app collection 采样时调用 remote scan policy/scan result；这不改变 AX/CG/Space sampling、Search、activation 或 surface 行为。Search freshness contract 不变：freshness barrier 未成功提交新 generation 时当前行为必须暴露为 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 AX app collection pressure proof boundary：`RuntimeAXAppCollectionCoordinator` 现在只暴露生产运行时需要的 bounded ordered `collect(count:collect:)` 与 `maxConcurrentCollections`，不再承载 `PressureResultForTesting` / `pressureResultForTesting(...)` 这类测试压力模拟 seam；压力测试在 `FlowTabTests` 内直接调用 production `collect` API 自行量测 ordered results、configured concurrency、max in-flight 与 elapsed time。provider 仍只在底层 AX/CG/Space 采样编排中消费 coordinator；这不改变 sampling、Search、activation 或 surface 行为。Search freshness contract 不变：freshness barrier 未成功提交新 generation 时当前行为必须暴露为 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 收窄 current-app projection payload 派生入口：`RuntimeCurrentAppWindowPayload` 已删除 `app` / `appGroup` / rank convenience initializer，并把 seed-to-summary/candidate/context initializer 降为 private；当时 repair-provider `currentAppWindowPayload(for:)` 与 `focusedCurrentAppWindowPayload(processIdentifier:)` 显式提交 `RuntimeCurrentAppWindowProjectionAssemblyInput`。2026-06-24 Phase 6 后两个 scoped repair-provider payload helper 均已删除：focused-PID repair 改为 evidence-only，appID-scoped mock current-app payload lookup 回到 TestingSupport projection seed。这只是 projection payload ownership cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result，而不能命名为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 full-repair assembler entry：`RuntimeFullRepairProjectionAssembler.payload(fromCurrentAppWindowPayloads:)` 已降为 private，repair-provider full repair 与 tests 只能通过 `payload(fromCurrentAppWindowProjectionInputs:)` 进入，避免 full repair assembly 重新暴露 prebuilt payload 数组作为生产入口。这只是 projection payload ownership cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 selection facts 到 projection assembly input 的转换 ownership：`RuntimeAppWindowSelectionFacts.currentAppProjectionAssemblyInput(...)` 与 `RuntimeFullRepairAppSelectionFacts.currentAppProjectionAssemblyInputs(...)` 现在把 app/window selection facts 转为 `RuntimeCurrentAppWindowProjectionAssemblyInput`，repair-provider projection builders 不再重复手写 projection seed lastActive、rank fallback、app group 和 scoped/focused payload input 组装规则。当前这仍是 projection payload assembly cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 UI-test projection seed ownership：`FlowTabUITestRuntimeProjectionDataset` 现在在 TestingSupport 边界承载 mock runtime app-switcher seed、contexts 与 current-app payloads；`RuntimeProjectionRepairFactSource.collectUITestProjectionDatasetFacts()` 是 repair-provider UI-test evidence 入口，不再直接调用 `FlowTabUITestRuntimeProjectionDataset.current()` 的 projection payload helpers。2026-06-24 Phase 6 后该 facts DTO 也只暴露 app directory evidence、app/window counts 与 focused repair evidence，不再携带 `RuntimeFullRepairProjectionPayload` 或 current-app payload map。`AppInventoryService` 仍从 TestingSupport projection seed 读取 installed-app mock runtime records，不再通过 `RuntimeSystemRepairFactProvider.UITestRuntimeDataset` / `uiTestRuntimeDataset()` 表达 mock runtime seed ownership。这只是测试启动 projection seed ownership cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 service repair provider ownership：`RuntimeProjectionRepairProvider` 现在是 `RuntimeProjectionService` 的默认 repair/fact facade，组合底层 `RuntimeSystemRepairFactProvider` 执行 scoped repair、Space affected-target derivation、verified focus/AX destroyed evidence 与 low-priority full repair fallback；`RuntimeSystemRepairFactProvider` 本体不再直接 conform `RuntimeProjectionRepairProviding`。这只是 service/executor ownership cleanup；当时的 repair-provider projection builders 后续已在 Phase 6 进一步收口为 evidence/main-table builder，`fullRepairProjectionPayload()` 已删除，Search freshness contract 不变，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 projection builder ownership：`RuntimeProjectionRepairProvider.swift` 现在承载 repair-provider contract、facade-owned WindowRecord/coordinator storage、private repair fact-source storage、full/current-app projection payload builders、app affected-target derivation 与 app-window reconciliation result assembly；`RuntimeProjectionRepairProvider+ProjectionBuilders.swift` 已删除。`RuntimeProjectionRepairFactSource` 承载 full-repair 的 running-app/app-directory/window/rank fact aggregation、app-layer policy facts 与 app-selection facts，以及当时 appID-scoped current-app repair 与 focused-PID current-app repair 的 running-app/window/rank fact aggregation、app-layer policy facts 和 `RuntimeAppWindowSelectionFacts` scoped selection facts，并私有持有底层 fact provider contract；builder 只消费 selection facts 组装 projection payload，不再直接运行 scoped `RuntimeAppDirectory.windowStats(...)` / `sortedAppsWithinGroup(...)` / `mergedWindows(...)` / `RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(...)`，且 callers 不能 unwrap repair-provider facade 读取 `repairFactSource`。`RuntimeSystemRepairFactProvider` 只作为组合注入的底层 CG/AX/Space fact source、WindowRecord table 与 focus/AX-destroyed evidence writer。provider-facing bottom fact APIs 已删除；2026-06-24 Phase 6 后 focused-PID scoped repair further returns evidence directly instead of a payload, appID-scoped provider payload helper 也已删除，UI-test current-app payload seed 只留在 TestingSupport，mock dataset facts 也只给 provider evidence。full-repair payload builder 仍不是长期主表生成：fact-source 还会在 repair/fallback 路径即时采样 running apps、CG、AX 与 full-repair app directory facts；Search freshness contract 不变，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 app-directory fact source ownership：`RuntimeAppDirectoryFactSource` 现在拥有 app-layer running app fact 输入过滤与 app-directory entry projection，`RuntimeProjectionRepairFactSource.collectFullRepairRunningAppFacts()` 是 full-repair builder 唯一 running-app + app-directory evidence 入口，`collectRepairRunningApps()` 是 scoped current-app/focused repair 的 running-app lookup 入口；projection builders 不再直接读取 app-directory fact source 或保留 provider-local `filteredRunningApplications()` helper，scoped repair 仍可通过 current-app payload 携带 scoped app-group directory entries，但不再从 running-app fact source 构造完整 directory evidence。当前这仍是 repair/fallback 输入边界，不是长期 app directory 主表生成；Search freshness contract 不变，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 WindowRecord reconciliation evidence ownership：`RuntimeWindowMappingState.affectedWindowEvidence(for:)` 现在拥有 scoped repair 里 affected CGWindowID 命中 WindowRecord 与 exact binding 的证据分类，repair-provider reconciliation implementation 只消费该 WindowRecord evidence，不再内联读取 `windowRecordsByCGWindowID` 与 `bindingConfidence` 规则。当前这仍是 repair-provider reconciliation 输入，不是长期 WindowRecord/app-directory/topology 直接 rebuild projection；Search freshness contract 不变，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 WindowRecord affected-target scope ownership：`RuntimeWindowMappingState.affectedCGWindowIDsByPID(...)` 现在拥有 scoped repair affected CGWindowID 从 current CG facts 与 WindowRecord history 合并成 pid->affected-window scope 的规则；`RuntimeProjectionRepairFactSource.collectSpaceTopologyReconciliationTargets(...)` 消费该 WindowRecord-owned scope 组装 `RuntimeSpaceTopologyReconciliationTarget`，repair-provider implementation 只消费 fact-source target，不再内联 current-CG/window-record 双路径分组，也不再把 app identity pullback 放在 topology target seam。当前这仍是 repair-provider reconciliation 输入，不是长期 WindowRecord/app-directory/topology 直接 rebuild projection；Search freshness contract 不变，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 repair-provider result-shape ownership：`RuntimeAppWindowReconciliationResult` 已从 deleted reconciliation extension 移到 `RuntimeProjectionRepairProvider.swift`，与返回它的 `RuntimeProjectionRepairProviding.reconcileAppWindows(...)` contract 同层；provider-core implementation 负责组装该 result 与底层 coordinator/fact-source mutation。当前这仍是 repair-provider contract cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续切断 Home surface transient AX read：`RuntimeProjectionServing` / `RuntimeProjectionRepairProviding` / `RuntimeSystemRepairFactProvider` 不再暴露 `isLikelyTransientAXRebuild(for:)`，Home 的 no-switchable-window subtitle 只通过 `HomeRuntimeProjectionReader.shouldWaitForNoSwitchableWindowProjection(...)` 读取 current-app 与 Home summary projection freshness，stale/dirty projection 时显示 wait-cache，clean projection 时才回到 accessibility guidance。后续 Phase 6 已删除该 helper 的 app-switcher projection fallback；provider transient AX behavior tests 现在直接断言 `RuntimeWindowMappingState.isLikelyTransientAXRebuild`，证明 transient 判定 ownership 停在 WindowRecord state；这不改变 Search freshness contract，barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 window-list fact ownership：`RuntimeWindowListEntry` 与 AX app collection payload `RuntimeAXAppWindowCollection` 已从 `RuntimeSystemRepairFactProvider.swift` provider core 移入 `RuntimeWindowListFacts.swift`，作为 top-level sampled window-list fact、AX/CG collection payload 与 binding diagnostic carrier。provider core 不再定义 projection/window-list/AX-collection DTO，只消费这些 runtime fact 类型执行底层 CG/AX/Space 采样和 WindowRecord 写回；这不改变 sampling 或 projection assembly 行为，仍只是把 repair/fallback 兼容桥的 fact shape 从 provider core 文件边界挪出。
- Phase 5 本轮 P0 继续收窄 deterministic window-mapping proof entry：`RuntimeWindowMappingTestSupport` 现在承载 CG assignment diagnostics、resolved window entries、supplemental off-Space merge 与 supplemental title/valid-CG deterministic proof 入口，tests 不再通过 `RuntimeSystemRepairFactProvider.*ForTesting` 或 `RuntimeSystemRepairFactProvider.SupplementalMergeEntryForTesting` 表达 window-mapping 规则 ownership；该 helper 已移到 `FlowTab/TestingSupport`，避免把 deterministic proof facade 放在 production runtime directory 里扩张成正常运行时 API。provider 仍作为底层 CG/AX/Space fact source 被组合调用，尚未把 repair/fallback 即时采样迁移为长期主表生成；这不改变 Search freshness contract，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result，而不能称为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 remote AX scan policy ownership：`RuntimeAXRemoteWindowResolver.shouldIncludeRemoteWindows(...)` 现在拥有 public AX 是否需要 remote AX scan 的 off-Space/user-facing CG decision，`RuntimeSystemRepairFactProvider` 只在 AX app collection 采样时调用该 policy；`RuntimeSystemRepairFactProvider.shouldIncludeRemoteAXWindowsForTesting` 与 provider-private decision helper 已删除，deterministic resolver proof facade 也已移到 `FlowTab/TestingSupport`。provider 仍保留底层 AX/CG/Space 采样编排；这不改变 Search freshness contract，barrier 未成功提交新 generation 时仍必须暴露为 degraded/stale committed result，而不能称为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 stable window title ownership：`RuntimeWindowTitleResolver` 现在拥有 normalized title、stable AX/CG/refreshed-AX title fallback 和 supplemental CG title 规则，provider/window-mapping 只消费 resolver；`RuntimeSystemRepairFactProvider.resolvedAXWindowTitleForTesting` 与 provider-private title helpers 已删除。这仍是 repair/fallback 兼容桥内部的 title 规则 ownership cleanup，不改变 Search freshness contract；barrier 未成功提交新 generation 时当前 Search 行为只能暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 AX app collection concurrency ownership：`RuntimeAXAppCollectionCoordinator` 现在拥有 AX app collection 的 bounded ordered execution policy 与 max concurrency；`RuntimeSystemRepairFactProvider` 只在采样编排中调用 coordinator，并不再暴露 `boundedAXAppCollectionPressureForTesting` 或 provider-owned concurrency limit。deterministic pressure proof 通过 `FlowTabTests` 直接调用 production `collect(count:collect:)` API 覆盖，不作为 production runtime testing seam 暴露。这不改变 AX/CG/Space sampling 行为，也不改变 Search freshness contract；barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 app rank fact ownership：`RuntimeAppRankProvider` 现在拥有 app rank fact source，组合 `SystemAppMRUTracker` 与 CG window stack fallback 并通过 projection diagnostics 记录 `collectAppRank`；repair-provider full/current-app projection builders 直接消费该 runtime-owned rank provider，`RuntimeSystemRepairFactProvider.collectAppRankByPID` 与 provider-private window-stack rank helper 已删除。`SystemAppMRUTracker` 的 deterministic proof 也不再通过 production file 的 `*ForTesting` facade 操作 shared singleton，而是通过独立 tracker 实例验证 MRU state operations。这不改变 app ranking 规则或 sampling 行为，也不改变 Search freshness contract；barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 CG-only stable window ID ownership：`RuntimeWindowListEntry.cgStableWindowID(pid:cgWindowID:)` 现在拥有 CG-only stable window ID 规则，WindowRecord seeding、verified-focus readback fallback、supplemental off-Space CG entries 与 deterministic mapping test support 都直接消费 window-list fact boundary；`RuntimeSystemRepairFactProvider.makeCGWindowID` 已删除。provider 仍负责底层采样和 WindowRecord 写回，但不再把该 ID 形状挂在 provider namespace 下；这不改变 mapping、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 Search readiness test boundary：`RecordingRuntimeProjectionService` 现在保存并返回 `RuntimeSearchIndexRead`，不再从 `RuntimeSearchIndexProjection.freshness.isCompleteForScope` 在测试服务里二次推断 `.committedGenerationValidated` / `.degradedStaleCommitted`。stale committed 测试直接传入 `RuntimeReadModelStore.readCommittedSearchIndexForSearch()` 产出的 read contract，确保 Search readiness/result-state 命名只由 runtime-owned store/read model 决定；barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 app termination cleanup ownership：`RuntimeProjectionService.signalAppTerminated(...)` 现在只提交 read-model termination signal 和 repair-provider `recordAppTerminated(processIdentifier:)` evidence；coordinator cancel、terminated PID WindowRecord mapping state removal 与 AX live registry removal 都由 `RuntimeProjectionRepairProvider` 拥有，service 不再跨 boundary 调用 raw `clearWindowMappingState` 或 AX registry cleanup。当前这仍是 termination repair/cleanup boundary，不是长期 WindowRecord/app-directory/topology 直接 rebuild projection；Search freshness contract 不变，barrier 未成功提交新 generation 时当前行为必须暴露为 degraded/stale committed result 与 dirty/freshness metadata，不能称为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 CG fact ownership：`RuntimeCGWindowFacts` 现在拥有 all-scope CG facts 与 current onscreen CG evidence 合并 onscreen 状态的规则；provider AX app collection 只消费 `RuntimeCGWindowFacts.mergingCurrentOnscreenStatus(allCGWindows:currentOnscreenCGWindows:)`，`RuntimeSystemRepairFactProvider.swift` 内的 `markCurrentOnscreenCGWindows(...)` 私有 helper 已删除。这不改变 CG/AX/Space sampling、remote AX scan decision 或 Search freshness 行为；barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 Space-enriched CG fact ownership：`RuntimeCGWindowFacts` 现在拥有 Space topology snapshot 输出的 `spaceIDs` 合并回 CG fact payload 的规则；provider CG collection 只消费 `RuntimeCGWindowFacts.mergingSpaceTopology(windowsByPID:spaceIDsByCGWindowID:)`。`RuntimeSystemRepairFactProvider.collectCGWindowsWithSpaceTopologyDiff(...)` 不再内联重建 enriched CG entries，只保留 CG sampling、Space topology snapshot/diff recording 与 diagnostic logging。这不改变 CG/AX/Space sampling、read-model dirty metadata 或 Search freshness 行为；barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 Space topology signal/reconciliation ownership：`RuntimeProjectionService` 的 repair-provider protocol 不再暴露 `collectCGWindowsWithSpaceTopologyDiff(...)` 或 raw target APIs；`signalSpaceTopologyChanged()` 只调用 `RuntimeProjectionRepairProvider.recordSpaceTopologyChanged(now:)` 取得 affected CGWindowID evidence 并写入 read-model dirty metadata，space-topology executor 只调用 `reconcileSpaceTopology(affectedCGWindowIDs:)`。底层 CG/Space sampling、WindowRecord/current-CG pullback 与 affected-target derivation 都停在 `RuntimeProjectionRepairFactSource.collectSpaceTopologySignalFacts(...)` / `collectSpaceTopologyReconciliationTargets(...)`，repair-provider reconciliation 只消费 fact-source facts/targets；这仍是 repair/fallback 兼容桥，不是长期 WindowRecord/app-directory/topology 主表直接 rebuild projection。Search freshness contract 不变，barrier 未成功提交新 generation 时当前行为仍只能暴露为 degraded/stale committed result，不能称为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 Space topology affected-target API ownership：`RuntimeSpaceTopologyReconciliationTarget` 现在由 `RuntimeProjectionRepairFactSource` 承载，repair-provider implementation 不再定义 private `RuntimeAffectedWindowReconciliationTarget` 或 `appReconciliationTargets(...)` helper；test target 和 service 都只能通过 `reconcileSpaceTopology(affectedCGWindowIDs:)` 证明 topology reconciliation。该 fact-source target 只承载 PID + affected CGWindowID scope，删除旧 appID pullback 与 `AppKit` dependency；app identity 仍由 current-app payload / app-directory assembly 边界负责。Search freshness contract 不变，barrier 未成功提交新 generation 时当前行为仍只能暴露为 degraded/stale committed result，不能称为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 activation Space-enriched CG fact ownership：`RuntimeActivator` 的 target visibility / focused readback CG window path 现在也复用 `RuntimeCGWindowFacts.mergingSpaceTopology(windows:spaceIDsByCGWindowID:)`，不再内联通过 `RuntimeCGSpaceInspector.spaceIDsByWindowID(...)` 重建 Space-enriched CG entries。activation 成功 oracle 仍是提交后的 focused AX/CG readback，不以 Space enrichment helper 或 Space API 作为成功证明；Search freshness contract 不变，freshness barrier 未成功提交新 generation 时只能暴露 degraded/stale committed result，不能称为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 activation topology candidate ownership：`RuntimeWindowTopologyClassifier` 现在拥有 fullscreen activation target、shared off-desktop Space、related AX fullscreen surface、same-Space CG activation surface 与 activation candidate sort 规则；`RuntimeActivator` 只消费这些 topology policy 来选择候选，然后继续通过 focus attempt 和 committed focused AX/CG readback 证明 activation 成功。activation 不再在文件尾部保留 CG/Space topology 私有规则；Search freshness contract 不变，freshness barrier 未成功提交新 generation 时只能暴露 degraded/stale committed result，不能称为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 supplemental CG window-list ownership：`RuntimeWindowListSupplementer` 现在拥有 supplemental off-Space CG window selection 与 append 规则，组合 CG validity constraints、CG-only stable ID、supplemental title fallback 和 unmatched-CG diagnostics；provider window mapping 与 deterministic test support 直接消费该 window-list supplement boundary，`RuntimeSystemRepairFactProvider.appendOffSpaceCGWindows` / `selectSupplementalOffSpaceCGWindows` 与 provider-private supplemental title helper 已删除。provider 仍负责底层采样与 WindowRecord 写回；这不改变 mapping、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 no-current-AX exposure policy ownership：`RuntimeWindowTopologyClassifier.canExposeWithoutCurrentAXHandle(...)` 现在拥有 window-layer 在没有 current AX handle 时是否暴露 CG/Space-backed entry 的 policy；provider window mapping 只消费该 topology classifier API，`RuntimeSystemRepairFactProvider+SpaceTopologyMapping.swift` 中的全局 `runtimeWindowCanBeExposedWithoutCurrentAXHandle` 已删除。这不改变 window-layer exposure、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 fullscreen topology binding resolver ownership：`RuntimeWindowTopologyBindingResolver` 现在拥有 fullscreen wrapper -> off-desktop content rebind、desktop sibling AX binding 与 fullscreen content fallback binding/diagnostic 规则；provider window mapping 只消费该 resolver，`RuntimeSystemRepairFactProvider+SpaceTopologyMapping.swift` 已重命名为 `RuntimeWindowTopologyBindingResolver.swift`，`RuntimeSystemRepairFactProvider.resolveFullscreenContentRebindings` / `resolveDesktopSiblingAXBindings` / `resolveFullscreenContentFallbackBindingsWithDiagnostics` provider-static 入口和未使用的 fallback wrapper 已删除。这不改变 CG/AX/Space sampling、WindowRecord 写回、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 private exact bridge ownership：`RuntimeAXWindowRecovery` 现在拥有 private AX -> CG bridge exact-match resolution 与 sticky-binding conflict diagnostic 规则；provider window mapping 只消费 `RuntimeAXWindowRecovery.resolvePrivateExactBridgeMatches(...)` / `stickyBindingConflictDiagnostic(...)`，`RuntimeSystemRepairFactProvider` 内的 private bridge static helpers 已删除。provider 仍负责 WindowRecord 状态写回与底层采样编排；这不改变 mapping、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 AX absence / transient rebuild policy ownership：`RuntimeAXWindowAbsencePolicy` 现在拥有 remote scan completeness 是否足以让 AX absence 变成 authoritative、AX collection miss grace 上限、Space 1 无 current AX handle 暂留与 transient rebuild 判定规则；provider window mapping 只消费该 policy 并继续负责 WindowRecord state 写回。`RuntimeSystemRepairFactProvider` 内的 `runtimeAXRebuildGraceMissingSnapshotLimit` 与 `axWindowAbsenceIsAuthoritative(...)` 已删除。这不改变 mapping、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 window presentation filtering ownership：`RuntimeWindowPresentationFilter` 现在拥有 fullscreen host artifact filtering、fullscreen sibling artifact filtering、auxiliary overlay filtering 与 fullscreen topology presentation ordering 规则；provider window mapping 只提交 resolved exact/sticky/provisional entries、known CG facts 与 CG z-order，再消费该 filter 的 presentation result。`RuntimeSystemRepairFactProvider+WindowMapping.swift` 内的 presentation/artifact private helpers 与阈值常量已删除。这不改变 CG/AX/Space sampling、WindowRecord state 写回、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 WindowRecord-derived fact ownership：`RuntimeWindowRecord` 现在拥有 live CG facts 与 record-synthesized CG facts 合并成 `knownCGWindowsByID` 的规则，以及 sticky binding 复用时 title/frame compatibility 判定；provider window mapping 只消费 `RuntimeWindowRecord.knownCGWindowsByID(...)` 与 `record.canReuseStickyBinding(with:)`。`RuntimeSystemRepairFactProvider+WindowMapping.swift` 内的 `runtimeKnownCGWindowsByID` / `stickyBindingCanReuse` 私有 helper 已删除。这不改变 CG/AX/Space sampling、WindowRecord state 写回、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 WindowRecord mapping resolution ownership：`RuntimeWindowMappingResolution` 已从 `RuntimeSystemRepairFactProvider+WindowMapping.swift` 移到 `RuntimeWindowRecord.swift`，与 `RuntimeWindowMappingState`、WindowRecord affected evidence 和 WindowRecord-derived CG fact accessors 同层。provider window mapping 继续负责底层采样后写回 WindowRecord，但不再定义 mapping resolution DTO；bounded freshness barrier 未成功提交新 generation 时，当前 Search 行为仍只能暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 window-list dedup ownership：`RuntimeWindowListDeduplicator` 现在拥有 sticky Space binding 覆盖 weaker unmatched CG-only entry 的 suppression 规则；provider window mapping 只消费 `RuntimeWindowListDeduplicator.suppressUnmatchedEntriesCoveredByStickySpace(...)`。`RuntimeSystemRepairFactProvider+WindowMapping.swift` 内的 `suppressUnmatchedAXEntriesCoveredByStickySpace` 私有 helper 已删除。这不改变 CG/AX/Space sampling、WindowRecord state 写回、activation 或 Search freshness 行为，barrier 未成功提交新 generation 时当前 Search 行为仍只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 sticky AX reuse ownership：`RuntimeWindowRecord` 现在拥有 sticky binding 复用的 AX ID continuity 与 AX element identity continuity 规则；provider window mapping 只消费 `record.reusableStickyAXWindow(from:assignedAXWindowIDs:)`。`RuntimeSystemRepairFactProvider+WindowMapping.swift` 内的 `resolveStickyAXWindow(...)` 私有 helper 已删除。这不改变 CG/AX/Space sampling、WindowRecord state 写回、activation 或 Search freshness 行为；bounded freshness barrier 未成功提交新 generation 时，当前 Search 行为只能暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 full-repair directory evidence ownership：`RuntimeFullRepairProjectionAssembler.payload(fromCurrentAppWindowProjectionInputs:appDirectoryEntries:)` 现在要求调用方显式传入 `appDirectoryEntries`，不再提供默认空 evidence。生产 full-repair builder 必须提交 `RuntimeProjectionRepairFactSource.collectFullRepairRunningAppFacts()` 采集到的 full directory evidence；测试或迁移桥若确实没有 directory evidence，也必须显式写 `[]`。这不改变 projection 排序、Search freshness、CG/AX/Space sampling 或 surface 行为，只把“空 evidence”从 API 默认值变成调用方显式选择；bounded freshness barrier 未成功提交新 generation 时，当前 Search 行为只能暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation result。
- Phase 5 本轮 P0 继续收窄 provider app-window stats ownership：未使用的 `RuntimeSystemRepairFactProvider.collectAXWindowStats(for:)` 已删除，provider 不再暴露 AX-derived `RuntimeAppWindowStats` 采集 API。app-window stats 的确定性规则只由 `RuntimeAppDirectory.windowStats(...)` / `mergedWindowStats(...)` 与 repair fact-source selection facts 消费 sampled window facts；底层 provider 仍只负责 AX/CG/Space 采样与 WindowRecord 写回。这不改变采样、projection assembly、Search freshness 或 surface 行为；bounded freshness barrier 未成功提交新 generation 时，当前 Search 行为只能暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation result。
- hot-path read APIs 的 P0 已从 Switcher/Home 首屏采样队列中解耦；selected/current app window refresh 和 Home window activation 已移除缺 projection 时的 `homeAppSnapshotSynchronously` fallback，改为 dirty signal + projection-only 状态；Home initial app summary 已移除缺 projection 时的 `lightweightAppSnapshot()` 同步 fallback，Home initial/refresh diagnostics 也迁到 projection category；Home summary/detail refresh 已从 service-facing Home fallback bridge 迁移到 Home summary/detail projection read + shared runtime maintenance signal，Home surface 不再从 app-switcher projection 自行派生 summary/detail；Switcher startup recency 已移除 live focused AX 与 live CG z-order read seam，改为 committed recency/projection order，且 `RuntimeWindowRecencyTracker` 不再暴露 Home snapshot-shaped recency helper；Switcher app-cycle hidden-app filtering 现在也作为 projection payload diagnostic 记录，不再占用 snapshot log category；Switcher termination refresh 已由 runtime store 同步剪枝 committed projection/search index，不再走 feature-facing full snapshot fallback；Search read model 已进入 runtime-owned committed index/freshness-read/committed-generation advance 边界，barrier 未提交时当前行为是 degraded/stale committed result 而不是 fresh/complete/latest，deterministic committed-index pressure 已证明 `LiveSwitcherModel` Search hot path 在 400 apps / 10,000 windows 下不调用 full/lightweight snapshot 且不请求 freshness barrier；真实 UI/E2E committed-index proof 与外部 pressure proof 仍需补齐。
- `RuntimeReadModelStore` 与 projection cache 的 P0 边界已落地；Home surface state/API 已把 selected-app detail cache 和 API payload 类型迁移为 `RuntimeHomeAppDetailProjection`，不再把 projection read boundary 表达成 Home snapshot cache；app identity 规则已收敛到 runtime-owned `RuntimeAppIdentity`，AppDelegate lifecycle signal、Switcher focused-current-app projection read、repair-provider full repair grouping、reconciliation target 和 UI-test runtime projection seed 都直接读取该入口，不再向 `RuntimeSystemRepairFactProvider` 查询 appID，`RuntimeSystemRepairFactProvider.baseAppID(for:)` 兼容 wrapper 已删除；provider-facing current-app payload pullback、`appWindowRepairPayload` / `focusedAppWindowRepairPayload(processIdentifier:)` 兼容 API 与 `RuntimeAppWindowRepairPayload` 类型级 wrapper 已删除；provider summary compatibility APIs `homeSummaryProjections()` / `homeSummaryProjection(for:)` 已删除，Home summary 只能来自 `RuntimeReadModelStore` projection 或 current-app payload 的 summary fact；full/current-app projection/repair builders 已 co-located in `RuntimeProjectionRepairProvider.swift`，不再保留 `HomeApps` 或 provider builder extension 文件边界，并且 full-repair running-app/app-directory/CG/AX/rank 聚合、UI-test projection dataset facts、appID-scoped/focused-PID current-app repair running-app/CG/AX/rank 聚合和 scoped app-window selection/filtering facts 已抽入 `RuntimeProjectionRepairFactSource`；`RuntimeProjectionPayloads.swift` 承载 top-level `RuntimeFullRepairProjectionPayload`、`RuntimeCurrentAppWindowPayload`、`RuntimeAppWindowProjectionSeed`、`RuntimeAppContext` 与 `RuntimeCurrentAppWindowProjectionAssemblyInput`，top-level `RuntimeWindowListEntry` 承载 provider 采样后进入 window-layer / projection seed 的 window list fact，`RuntimeAppWindowProjectionSeed` conversion、`RuntimeCurrentAppWindowProjectionAssemblyInput` / `RuntimeCurrentAppWindowPayload` 已拥有 app/display/rank/group/timestamp + projection seed 到 summary/candidate/context payload fact 的 assembly，`RuntimeFullRepairProjectionAssembler` 已取代 provider-owned deterministic assembly seam，production full repair payload sorting/context map assembly 也由该 assembler 执行；`RuntimeAppLayerProjectionFilter` 已迁到 `RuntimeAppDirectory.swift`，与 app directory eligibility/filtering 规则同层，取代 provider-owned filter seam，repair-provider current-app payload pullback 也不再内联 minimized-only include 条件或 scoped app-directory selection/merge pipeline，provider full repair builder 也不再保留 `filterAppsForAppLayer(...)` adapter seam；full repair payload 已收敛到 repair-provider `fullRepairProjectionPayload()` 与 shared `RuntimeFullRepairProjectionPayload`，且 full/current-app repair builders 现在共用 runtime-owned projection seed 和 `RuntimeCurrentAppWindowPayload` assembly；迁移期 `RuntimeFullRepairProjectionAssembly*` DTO 与 `assembleRows(...)` testing seam 已删除；provider-facing `RuntimeSystemRepairFactProvider.snapshot()` wrapper、`RuntimeSnapshot` 类型与 `collectCGWindowsByPID` CG-read 兼容包装已删除，`RuntimeProjectionRepairFactSource` 直接消费 topology-aware `collectCGWindowsWithSpaceTopologyDiff`，repair-provider full/current-app builders 只消费 fact-source payload；`RuntimeCGWindowFacts.swift` 承载 top-level CG fact payload 和 CG validity constraints，`RuntimeWindowRecord`、provider window-mapping helpers、`RuntimeActivator`、`RuntimeChromeWindowFocusBridge`、provider internals 与 deterministic tests 已直接接收/合成 top-level `RuntimeCGWindowEntry` / `RuntimeCGWindowCollection`，生产代码不再引用 provider-nested CG fact 名称或 provider-owned validity helper，`RuntimeSystemRepairFactProvider.CGWindowEntry` / `CGWindowCollection` 迁移期 typealias、`CGWindowEntryForTesting` 与 `RuntimeSystemRepairFactProvider.cgWindowPassesValidityConstraints(_:)` 已删除；production AX window fact 也已迁为 top-level `RuntimeAXWindowEntry`，由 `RuntimeWindowRecord.swift` 与 AX attachment state 同层拥有，provider-nested `RuntimeSystemRepairFactProvider.AXWindowEntry` 与 `AXWindowEntryForTesting` 均已删除，provider testing helpers 也直接接收 top-level `RuntimeAXWindowEntry` fixtures；AX/CG public assignment 与 public-AX recovery 已分别迁到 `RuntimeWindowAssignmentMatcher` 和 `RuntimeAXWindowRecovery`，provider 不再拥有 `matchCGWindowAssignments*` 或 `recoverAXWindowFromPublicSources*` helper API；service/coordinator transient-empty retry outcome 已命名为 current-app payload 边界，不再暴露 AX snapshot-shaped outcome；full/current-app projection builder timing 与 filtering diagnostics 已进入 projection log category，RuntimeFacts category 承载底层 CG/AX/Space fact collection；provider core 文件仍只是 repair-provider facade、projection payload builders 与 reconciliation implementations，底层采样聚合经 private fact-source storage 进入；current-app payload 提交时会由 store 以既有 projection 为 base 同步 upsert current-app、app-switcher 与 Home summary projection；UI-test runtime dataset 也只维护 app-switcher projection seed、contexts 与 current-app payloads，test launch option 内部 API 使用 projection 命名。仍需把 repair-provider projection builders 从 repair/fallback 即时采样迁移到底层 `RuntimeWindowRecord`、app directory、Space topology 主表生成。
- Supersession note: Phase 6 后续已删除 provider-facing `fullRepairProjectionPayload()`，并把 `RuntimeFullRepairProjectionPayload` / `RuntimeFullRepairProjectionAssembler` 移入 `FlowTab/TestingSupport/RuntimeFullRepairProjectionTestSupport.swift`；上一条中的 full-repair payload 收敛状态只描述早期迁移桥。当前 production full repair 只能通过 `fullRepairEvidence()` 提交 app-directory evidence，再由 main-table builders 生成 projection cache。
- `RuntimeAppDirectoryEntry` / `RuntimeAppDirectory` 现在承载 app grouping、primary app selection、app stats/rank sorting、preferred rank、stable last-active、app-layer nested/zero-window suppression、sampled-window stats derivation、group 内 window merge 与 app-window stats based candidate filtering；provider 只把采样窗口 facts 和 minimized/visible 映射交给 runtime-owned app directory，`RuntimeSystemRepairFactProvider+AppGrouping.swift` provider extension seam 已删除；`RuntimeFullRepairProjectionAssembler` 只消费 current-app projection input / payload 来排序 app-switcher candidates 并生成 context map，不再拥有 app directory 规则、testing-only row assembly seam，且不再从 current-app inputs 反推 app directory entries。full repair payload 已显式携带完整 filtered running-app directory evidence，而不是从 selected app-switcher rows 或 scoped current-app inputs 反推 directory。Phase 6 P0 已开始把 directory 从 full-repair 兼容桥输入推进为 Runtime 长期主表：当 app-switcher projection cache 缺失但 `RuntimeAppDirectoryState` 已有 evidence 时，`RuntimeReadModelStore.readAppSwitcherProjection()` 会从 directory 主表派生 stale/dirty app-only projection，并且不会提交 Search fresh index；window/context projection 仍需从 WindowRecord/app-directory/Space 主表继续迁移。
- Switcher session-start background full snapshot 已降级为 runtime-owned maintenance request；scheduler priority/coalescing/promoted-backoff P1 已落地，Search freshness barrier priority 与 selected/current app-window priority 已进入 runtime coordinator，full repair fallback target / low-priority scheduling / high-priority scoped cancellation / retry-exhaustion 自动降级已建模；dirty full repair fallback 现在只能提交 degraded projection，不能清 dirty 或刷新 committed Search。完整 full repair facts 拆分与更广 backoff policy 仍需补齐。
- search index 已从 session completeness 迁移到 committed runtime index read，并补齐 stale/dirty freshness read、bounded maintenance request、projection-cache generation 覆盖后 new committed generation 进入 verified current-generation committed result 的边界；scoped repair outcome 现在由 drainer/service 边界降级为 evidence trigger，Search success 只从覆盖当前 runtime generation 的 committed projection cache 提交。barrier 未产生当前 generation projection-cache commit、barrier 未提交或 dirty full repair fallback 执行后，当前 Search 行为记录为 degraded/stale committed result，而非 fresh/complete/latest。deterministic committed-index pressure 已覆盖 current-generation committed index 的 Search entry/query hot path，仍需补真实 committed-index UI proof 与外部 pressure proof。
- Phase 5 本轮 P0 继续收窄 concrete repair-provider file ownership：`RuntimeProjectionRepairProvider` facade 定义已从 `RuntimeProjectionService.swift` 移到 `RuntimeProjectionRepairProvider.swift` 并加入 app target。service 文件现在不再定义 concrete repair provider，只保留 projection-serving contract、repair-provider dependency、read-model store ownership、maintenance drain 与 commit/freshness policy。Search freshness contract 不变，barrier 未成功提交新 generation 时当前行为只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 repair-provider implementation ownership：`RuntimeProjectionService.swift` 不再保存 `RuntimeProjectionRepairProvider` 的 AX destroyed、terminated-app cleanup、verified-focus writeback/coordinator scheduling implementations；这些 coordinator-mutating details 现在 co-located in `RuntimeProjectionRepairProvider.swift`，并通过 facade-owned `RuntimeWindowRecordStore` / `RuntimeReconciliationCoordinator` 访问底层 state。service 文件继续只表达 projection-serving contract、repair-provider dependency/default wiring、read-model store ownership、maintenance queue drain 与 commit/freshness 条件。Search freshness contract 不变，barrier 未成功提交新 generation 时当前行为只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 repair-provider protocol ownership：`RuntimeProjectionRepairProviding` 已从 `RuntimeProjectionService.swift` 移到 `RuntimeProjectionRepairProvider.swift`，与 concrete facade 同文件承载 repair-provider API；service 文件只保留 feature-facing `RuntimeProjectionServing`、read-model store ownership、maintenance drain 与 commit/freshness policy。Search freshness contract 不变，freshness barrier 成功提交新 generation 之前，当前 Search 行为只能暴露为 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 当时收窄 runtime reconciliation drainer ownership：`RuntimeProjectionReconciliationExecutionOutcome`、`RuntimeProjectionReconciliationDrainResult`、`RuntimeProjectionReconciliationExecutor`、`RuntimeProjectionReconciliationDrainer` 与默认 repair executor 由 `RuntimeProjectionReconciliationDrainer.swift` 承载。后续 Phase 6 已把 Search 成功条件从 repaired-payload staging 迁到 `RuntimeReadModelStore.commitSearchFreshnessBarrierFromProjectionCache(...)`；repair-provider fact source 与 coordinator mutation 仍不回流到 service。Search freshness contract 不变，bounded barrier 成功提交新 generation 之前，当前 Search 行为只能暴露为 degraded/stale committed result 与 dirty/freshness metadata。
- Phase 5 本轮 P0 继续收窄 runtime maintenance drain ownership：ready-request selection 后的 start/execute/complete/defer loop 已由 `RuntimeProjectionReconciliationDrainer` 承载，`RuntimeProjectionService.swift` 不再直接调用 repair-provider 的 `startReconciliationRequest` / `completeReconciliationRequest` / transient-empty defer API。service 只请求 maintenance drainer 返回 payload/deferred/started summary，再把 Search drain facts 交给 read-model store 的 barrier commit API；provider API 仍作为 repair boundary，coordinator lifecycle 不回流到 service。Search freshness contract 不变，barrier 未成功提交新 generation 时当前行为只能暴露为 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 runtime maintenance vocabulary ownership：`RuntimeProjectionMaintenanceReason` 与 `runtimeSearchFreshnessBarrierMaxReadyRepairs` 已从 `RuntimeProjectionService.swift` 迁入 `RuntimeProjectionMaintenancePolicy.swift`，让 Search barrier batch bound 与 maintenance request reason 跟 policy vocabulary 同层。service 文件只暴露 serving protocol、shared instance 与 read-model commit/queue orchestration，不再定义 maintenance vocabulary。Search freshness contract 不变，barrier 未成功提交新 generation 时当前行为只能暴露为 degraded/stale committed result。
- Phase 5 当时收窄过 full-repair commit/freshness ownership；该迁移桥已在后续 Phase 6 再降级：store 不再暴露 `commitFullRepairProjectionPayload(...)` 作为 normal projection commit API。当前 cold-start / dirty degraded app-switcher projection commit 由 `RuntimeReadModelStore.commitMainTableAppSwitcherProjectionPayload(...)` 承担，app directory evidence 必须先通过显式 evidence commit 写入主表；它不能直接提交 verified current-generation committed Search index。freshness barrier 成功提交新 generation 前，当前 Search 行为必须继续写成 missing committed index 或 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 当时收窄 projection read-model ownership：`RuntimeProjectionReadModels.swift` 承载 `RuntimeReadModelGeneration`、`RuntimeProjectionFreshness`、app/home/current-app/app-directory projections、read-model diagnostics 与 app-switcher projection commit summary。当前 `RuntimeReadModelStore.swift` 只保留 lock-protected state、dirty/freshness mutation、projection cache transaction 与 committed Search transaction，不再把所有 projection contract 定义堆在 store 文件顶部。该拆分不新增 surface state，也不改变 hot-path read；它让 projection cache/read-model contract 成为正式 runtime boundary。
- Phase 5 当时收窄 Search read-model ownership：`RuntimeSearchIndexReadModel.swift` 承载 `RuntimeSearchIndexProjection`、app/window index entry、readiness/result-state 命名；后续 Phase 6 已删除 `RuntimeSearchFreshnessBarrierCommitResult` 和 production staging transaction。Search read contract 因此有独立 read-model 文件边界，但没有第二个 runtime store；surface 仍只能消费 `RuntimeSearchIndexRead`，barrier 未成功提交新 generation 时仍必须暴露 degraded/stale committed result。
- Phase 5 当时收窄过 Search freshness-barrier staging/commit ownership；后续 Phase 6 已删除 production `stagingSearchIndex` 与 `commitSearchFreshnessBarrierPayloads(...)`。当前 service 只调用 `RuntimeProjectionRepairProvider.promoteSearchFreshnessBarrierRequests(now:)`、bounded drain ready repairs，并通过 main-table projection cache rebuild 后调用 `commitSearchFreshnessBarrierFromProjectionCache(...)`；只有 projection cache 覆盖当前 generation、无 deferred repair、无 pending repair 时才原子提交新 committed generation。barrier 未成功提交新 generation 时，当前 Search 行为只能暴露为 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 projection repair fact-source ownership：`RuntimeProjectionRepairFactSource` 现在承载 full-repair cleanup/prune、onscreen/all CG collection、AX window data collection、app rank facts，以及 appID-scoped / focused-PID current-app repair 的 rank/CG/AX facts 和 `RuntimeAppWindowSelectionFacts` selection facts；repair-provider builders 只消费 `RuntimeFullRepairWindowFacts` / `RuntimeCurrentAppWindowFacts` / `RuntimeFocusedCurrentAppWindowFacts` / scoped selection facts 来做 projection seed 与 payload assembly，不再直接执行 scoped app directory selection、merged-window 或 app-layer filter 规则。该拆分不改变 full/current-app repair 的 repair/fallback/cold-start 性质，不新增 hot-path read，也不把 Search barrier 成功 oracle 交给 full repair；barrier 未成功提交新 generation 时 Search 仍只能返回 degraded/stale committed result 与 dirty/freshness metadata。
- Phase 5 本轮 P0 收紧 Search readiness 命名：`RuntimeSearchIndexReadiness` 的成功态现在是 `committedGenerationValidated`，并映射到 `committedGenerationResult`；`degradedStaleCommitted` 仍唯一映射到 `degradedStaleCommittedResult`。因此 freshness barrier 未成功提交新 generation 时，当前 Search 行为在代码、日志、测试和文档中都只能写成 degraded/stale committed result，而不能叫 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 收口 Search stale 命名 contract：既有 stale committed Search 行为测试现在断言 `LiveSwitcherModel` diagnostic log 必须包含 stale/degraded/freshness-barrier-requested/current-generation-not-covered evidence，并禁止 fresh/complete/latest/current-generation result 命名。这把 barrier 未提交时的当前行为固定为 degraded/stale committed result；真实 committed-index UI proof 与外部 pressure proof 仍是 gap。
- Phase 5 本轮 P0 继续把 Search stale 命名推进到 surface trace：`SwitcherPanelController` 的 search trace summary 现在只投射 runtime-owned `RuntimeSearchIndexRead` diagnostic，写出 `searchIndexReadiness`、`searchIndexResultState`、`searchIndexDegraded`、`searchIndexCoversCurrentGeneration` 与 `searchFreshnessBarrierRequested`；barrier 未成功提交新 generation 时 trace 也必须写成 `degradedStaleCommitted` / `degradedStaleCommittedResult`，不能叫 fresh、complete、latest 或 current-generation result。这只是命名/证明边界加固；真实 committed-index UI proof 与外部 pressure proof 仍是 gap。
- Phase 5 本轮 P0 修复 `Option+Tab` app-cycle 到 selected-app window-layer 的 projection race：当用户在 selected app projection 尚未应用、当前 app-strip row 仍为 `windows=0` 时按下 `downArrow`，`LiveSwitcherModel` 现在只记录一次 `pendingManualWindowLayerEntryAppID`，并在后续 `RuntimeCurrentAppWindowProjection` 成功应用后重放进入 window layer 的意图；该路径不触发同步 CG/AX/Space sampling，不新增 surface-local topology scheduler，也不把 stale app-switcher windows 当正常 window layer。行为测试 `testLiveSwitcherModelReplaysManualWindowLayerEntryAfterSelectedAppProjectionApplies` 覆盖 pending -> applied -> windowCycle，真实 pressure 复跑在修复后二进制中记录了 `manualWindowLayerEntry result=pending` / `entered` 与 `mode=windowCycle(com.example.fixture.chrome)`，证明原始 race 已越过。完整 `runtime-topology-pressure.sh 0.5` 仍失败在 noisy fullscreen fixture 的 filtered-artifact runtime log oracle：`results-20260623-103155` 采样 56 个 0.5s 样本，CPU avg/p95/max 14.03/33.30/77.90，RSS avg/p95/max 100.24/179.94/180.03MB，但 UI test 未找到 `Chrome Fixture filtered-fullscreen-(sibling|host)-artifacts` 非零 dropped 日志；因此本轮不能把真实 topology pressure 标为通过。Search contract 不变：bounded freshness barrier 未成功提交新 generation 前只能暴露 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 noisy fullscreen presentation filtering ownership：duplicate fullscreen geometry host / topology content surface 去重已进入 `RuntimeWindowPresentationFilter.filterDuplicateFullscreenContentEntries(...)`，provider 只提交 mapped entries、known CG facts、app name 与 stage；ordering 也会复用同一规则作为 presentation cache 的最终防线。Required behavior coverage: `testRuntimeSystemRepairFactProviderWindowListFiltersDuplicateFullscreenGeometryHosts`、`testRuntimeSystemRepairFactProviderWindowListFiltersFullscreenHostAfterDesktopCGIDMovesToFullscreenSpace`、既有 `testRuntimeSystemRepairFactProviderWindowListFiltersFullscreenSiblingArtifactsAroundNoisyWindows` 已通过 `run-flowtabtests-local.sh` targeted run，证明 direct duplicate、desktop-to-fullscreen CGID move 与既有 sibling artifact 规则都维持四窗口 projection。UI/pressure status: fixed-path `{user-home}/Applications/Flow Tab UITest.app` 已重新安装，但 `./scripts/perf/runtime-topology-pressure.sh 0.5` 本轮结果 `results-20260623-115712` 在 UI runner 测试体启动前被系统 kill，且 `flowtab-samples.csv` 只有表头；直接 `run-ui-tests-local.sh` 用 DerivedData app 与 fixed-path app 也都在 bootstrap 前 `signal kill`。因此真实 UI/pressure proof 当前是环境/bootstrap blocker，而不是产品断言失败；更广 fullscreen/multi-display/system-authoritative topology proof 仍保留为 gap。Search contract 不变：barrier-requested、repair-in-progress、partial/repair 中间态或未提交新 generation 的 Search 读都只能是 degraded/stale committed result，不能称为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 修正 noisy fullscreen UI/pressure proof oracle：`FlowTabUITests` 的 noisy `Option+Tab` round-trip 现在接受 runtime-owned `RuntimeWindowPresentationFilter` 在 provider presentation 阶段输出的 `filtered-fullscreen-duplicate-surfaces stage=presentation-final dropped>0` 证据，同时保留既有 host/sibling artifact dropped-log 证据。该调整不改变 production filtering、activation 或 hot-path read，只让真实拓扑 proof 对齐当前 ownership：duplicate geometry host / topology content 去重已经是 presentation filter 的正式边界，而不是只能由旧 sibling/host artifact log 证明。Validation: `./scripts/testing/run-ui-tests-local.sh -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows` 仍在测试体启动前失败为 `FlowTabUITests-Runner ... signal kill before starting test execution`；sandbox 内 `./scripts/perf/runtime-topology-pressure.sh 0.5` 被 `pgrep`/`sysmond` 采样权限阻断，提升权限后 `results-20260623-174014` 仍因同一 UI runner bootstrap kill 未采到 FlowTab 样本，`flowtab-samples.csv` 只有表头。因此本轮只完成 oracle alignment，真实 topology UI/pressure proof 仍是当前环境/bootstrap blocker。Search contract 同步按严格命名记录：freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 `degradedStaleCommitted` / `degradedStaleCommittedResult` 或 degraded/stale committed read，不能写成 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 committed recency vocabulary：`RuntimeWindowRecencyTracker` 的内部 generation counter 与 evaluation entry 已从 `snapshotGeneration` / `beginSnapshotEvaluation()` 改为 projection evaluation terminology，semantic fallback rejection log 也不再写 `ignore_record_for_this_snapshot`。这不改变 recency state、projection ordering、Search freshness 或任何 CG/AX/Space sampling；它只是避免 committed projection order 的 runtime 证据继续使用 snapshot vocabulary。Required behavior coverage: `testRuntimeWindowRecencyTrackerMatchesRecordedCGWindowAcrossProjectionOrder`、`testRuntimeWindowRecencyTrackerExpiresSemanticFallbackAcrossProjectionEvaluations`、`testRuntimeWindowRecencyMatchDiagnosticIncludesConfidenceAndAction`、`testRuntimeWindowRecencyTrackerAppliesSameOrderingToCurrentAppPayload` 已通过 `run-flowtabtests-local.sh` targeted run。Search contract 不变：freshness barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 repair-provider fact dependency vocabulary：`RuntimeProjectionRepairProvider` 与 `RuntimeProjectionRepairFactSource` 现在把组合注入的底层 `RuntimeSystemRepairFactProvider` 命名为 `runtimeFactProvider`，测试注入也使用同一标签。`RuntimeSystemRepairFactProvider` 类型仍作为底层 CG/AX/Space fact sampling、WindowRecord mapping state 与 focus/AX-destroyed evidence bridge 存在，但 repair-provider boundary 不再把该依赖暴露为 `snapshotProvider`，避免 surface 或 service 重新把它理解成 hot-path snapshot read seam。P1 同轮只更新既有 repair/reconciliation tests 的注入标签；P2 不新增 UI/E2E 或 pressure proof，因为这是 ownership/vocabulary cleanup，不改变采样、surface behavior、activation、Search 或 hot-path cost。Required behavior coverage: `testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals`、`testRuntimeProjectionServiceDrainsSpaceTopologySignalThroughCoordinator`、`testRuntimeProjectionRepairProviderReconcilesSpaceTopologyThroughAffectedTargets`、`testRuntimeProjectionServiceSearchFreshnessBarrierCommitsRepairedSearchGeneration`、`testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRepairDefers`、`testRuntimeProjectionServiceSearchFreshnessBarrierDoesNotCommitWithoutRepairEvidence` 已通过 `run-flowtabtests-local.sh` targeted run。Search contract 不变且必须按 degraded 语义记录：freshness barrier 未成功提交新 generation 时，当前 Search 行为只能返回 last committed index 的 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 transient AX absence vocabulary：`RuntimeWindowMappingState` 的 AX 缺失计数已从 `consecutiveSnapshotsWithoutAXWindows` 改为 `consecutiveAXCollectionMisses`，`RuntimeAXWindowAbsencePolicy` 的 counter/limit API 也改为 `consecutiveAXCollectionMissCount(...)` / `transientRebuildGraceAXCollectionMissLimit`。provider window mapping 的 local variables 与 transient rebuild diagnostic log 现在写 `axCollectionMisses`，不再把 WindowRecord-owned AX collection miss grace 叫 snapshot grace。P1 同轮同步既有 behavior tests 与历史文档措辞；P2 不新增 UI/E2E 或 pressure proof，因为这只是 policy/state/log vocabulary cleanup，不改变 AX/CG/Space sampling、WindowRecord state transition、surface behavior、activation 或 Search architecture。Required behavior coverage: `testRuntimeWindowMappingStateClassifiesTransientEmptyCurrentAppPayload`、`testRuntimeSystemRepairFactProviderWindowListKeepsStickyCGEntriesBoundToSpaceOneDuringTransientAXRebuild`、`testRuntimeSystemRepairFactProviderWindowListHidesStickyCGEntriesBoundToSpaceOneAfterAXRebuildGraceRetriesExhausted`、`testRuntimeSystemRepairFactProviderPartialRemoteAXScanDoesNotConsumeMissingAXGrace` 已通过 `run-flowtabtests-local.sh` targeted run。Search contract 不变：freshness barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 window-list fact diagnostics ownership：`RuntimeSystemRepairFactProvider+CGWindowSupplement.swift` 已删除，Chrome-like topology 与 resolved window-entry summary diagnostics 改由 top-level `RuntimeWindowListDiagnostics.swift` 承载。provider/WindowRecord mapping 只调用 window-list diagnostics boundary，底层日志现在写 `RuntimeFacts` category，事件名/字段保持不变，因为这里记录的是 CG/AX/Space fact sampling 过程；但 diagnostics 不再作为 `RuntimeSystemRepairFactProvider` extension API 暴露，避免旧 provider 文件名继续暗示 surface 可以读取 snapshot-shaped runtime state。P1 同轮只更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为日志字段和值、sampling、WindowRecord mapping、surface behavior、activation 与 Search 架构都未改变。Required behavior coverage: `testRuntimeSystemRepairFactProviderWindowEntriesCarrySpaceEvidence`、`testRuntimeSystemRepairFactProviderWindowListFiltersFullscreenSiblingArtifactsAroundNoisyWindows`、`testRuntimeSystemRepairFactProviderWindowListFiltersDuplicateFullscreenGeometryHosts` 已通过 `run-flowtabtests-local.sh` targeted run，并重新编译 `RuntimeSystemRepairFactProvider.swift` / `RuntimeWindowListDiagnostics.swift`。Search contract 不变：freshness barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 WindowRecord evidence ownership：`RuntimeSystemRepairFactProvider+Reconciliation.swift` 已删除，Space topology snapshot diff 写回、affected WindowRecord reconciliation marking、verified-focus AX/CG evidence seeding 与 destroyed AX attachment cleanup 先从 provider extension 迁出；后续 store-private cleanup 已把 raw table inout 包在 `RuntimeWindowRecordStore` semantic methods 内，并删除独立 module-level evidence source。`RuntimeSystemRepairFactProvider.collectCGWindowsWithSpaceTopologyDiff(...)` 只在采样后调用 store topology evidence entry；`RuntimeProjectionRepairProvider.swift` 只编排 repair-provider semantic API、coordinator dirty request 与 affected evidence，不再调用 provider extension 方法或直接传 raw table 写 WindowRecord state。P1 同轮更新 direct evidence tests 命名与文档；P2 不新增 UI/E2E 或 pressure proof，因为 mapping mutation rule、sampling、activation oracle、surface behavior 与 Search architecture 都未改变。Required behavior coverage: `testRuntimeWindowRecordEvidenceRecordsSpaceTopologyThroughCoordinator`、`testRuntimeWindowRecordEvidenceMarksAffectedWindowRecordsForSpaceTopologyReconciliation`、`testRuntimeProjectionServiceSignalsDestroyedAXWindowThroughCoordinator`、`testRuntimeProjectionServiceDrainsVerifiedFocusThroughCoordinator`、`testRuntimeProjectionServiceSeedsVerifiedFocusRecordWithoutPriorMappingState`、`testRuntimeProjectionServiceSeedsVerifiedFocusRecordWhenFocusedAXWindowIsNotInRegistry` 已通过 `run-flowtabtests-local.sh` targeted run。Search contract 不变：freshness barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result 与 dirty/freshness metadata，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 WindowRecord evidence helper visibility：独立 `RuntimeWindowRecordEvidence.swift` 已删除，Space topology snapshot diff 写回、affected WindowRecord reconciliation marking、verified-focus AX/CG evidence seeding 与 destroyed AX attachment cleanup 的 raw table helper 现在是 `RuntimeWindowRecordStore.swift` 内的 private implementation detail。外部 production、TestingSupport 与 tests 只能通过 `RuntimeWindowRecordStore.recordSpaceTopologySnapshot(...)` / `recordWindowFocusVerification(...)` / `clearDestroyedAXAttachment(...)` / `affectedCGWindowIDsByPID(...)` 等 semantic store APIs 接触 evidence，不再能复用 module-level raw `mappingStatesByPID` inout helper 形成第二个 WindowRecord table write seam。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 helper visibility / file-boundary cleanup，不改变 mapping mutation rule、sampling、activation oracle、surface behavior、Search barrier 或 hot-path cost。Required behavior coverage 复用 topology/verified-focus/AX-destroyed/store tests through `run-flowtabtests-local.sh`，证明 store-private helper 仍支持 Space topology marking/pullback、verified-focus exact evidence、destroyed AX downgrade、terminated cleanup 与 lifecycle deletion。Search freshness 命名保持严格：barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 5 本轮 P0 继续收窄 WindowRecord state ownership：`RuntimeWindowRecordStore.swift` 现在正式拥有 PID-keyed `RuntimeWindowMappingState`，provider cleanup/remove、window mapping resolution writeback、Space topology diff evidence、repair-provider verified-focus / AX-destroyed evidence 与 topology reconciliation target derivation 都改为读写 `windowRecordStore`。迁移期曾短暂保留 provider computed compatibility bridge，但它不再是生产 ownership 边界，也不能被 surface 扩张成 snapshot-shaped read seam。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 mapping rules、sampling、surface behavior、activation oracle、Search barrier 与 hot-path cost 都未改变。Required behavior coverage: `testRuntimeWindowRecordEvidenceRecordsSpaceTopologyThroughCoordinator`、`testRuntimeWindowRecordEvidenceMarksAffectedWindowRecordsForSpaceTopologyReconciliation`、`testRuntimeProjectionServiceSignalsDestroyedAXWindowThroughCoordinator`、`testRuntimeProjectionServiceClearsTerminatedAppRuntimeState`、`testRuntimeSystemRepairFactProviderWindowListKeepsStickyCGEntriesBoundToSpaceOneDuringTransientAXRebuild`、`testRuntimeSystemRepairFactProviderWindowListHidesStickyCGEntriesBoundToSpaceOneAfterAXRebuildGraceRetriesExhausted` 已通过 `run-flowtabtests-local.sh` targeted run。Search contract 继续按严格命名记录：freshness barrier 未成功提交新 generation 时当前 Search 只能返回 last committed index 的 `degradedStaleCommitted` / `degradedStaleCommittedResult` 与 dirty/freshness metadata，不能写成 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续移除 WindowRecord store 的 provider wrapper：`RuntimeSystemRepairFactProvider.cleanupWindowMappingState(...)` 与 `removeWindowMappingState(forTerminatedPID:)` 已删除，full/focused repair fact collection cleanup 直接调用 fact-source 注入的 `RuntimeWindowRecordStore`，app termination cleanup 直接调用 repair facade 自己持有的 `RuntimeWindowRecordStore`。这让 repair-provider/fact-source 语义不再通过 snapshot-provider mutation wrapper 间接维护 WindowRecord state；`RuntimeSystemRepairFactProvider` 仍只是底层 CG/AX/Space fact sampler 与迁移期 compatibility bridge。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 cleanup ownership 命名改变不改变采样、WindowRecord rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage: `testRuntimeProjectionServiceClearsTerminatedAppRuntimeState`、`testRuntimeProjectionServiceMaintenanceSchedulesLowPriorityFullRepairWhenProjectionMissing`、`testRuntimeProjectionServiceFullRepairFallbackCommitsMainTableProjectionWithoutRefreshingSearch` 已通过 `run-flowtabtests-local.sh` targeted run。Search freshness 命名保持严格：barrier 未成功提交新 generation 时只能是 degraded/stale committed read，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 删除 WindowRecord mapping state 的 provider compatibility bridge：`RuntimeSystemRepairFactProvider` 不再暴露 PID-keyed mapping state computed property；后续 store-private cleanup 已把 TestingSupport 与 deterministic tests 的 seed/inspection 也迁到 `setState(...)` / `state(for:)`。这证明 WindowRecord state ownership 已从 snapshot provider field surface 迁出，并进一步把 raw table 降为 store implementation detail；provider 只保留底层 CG/AX/Space fact sampling、WindowRecord writeback 使用 store、以及 repair/fallback 兼容入口。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 migration bridge removal，不改变采样、WindowRecord rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage: `testRuntimeSystemRepairFactProviderStoresCGFirstWindowRecordsAsSingleSourceOfTruth`、`testRuntimeSystemRepairFactProviderResolveCGWindowAssignmentsUsesGeometryWithDuplicateTitles`、`testRuntimeWindowRecordEvidenceRecordsSpaceTopologyThroughCoordinator`、`testRuntimeWindowRecordEvidenceMarksAffectedWindowRecordsForSpaceTopologyReconciliation`、`testRuntimeProjectionServiceSignalsDestroyedAXWindowThroughCoordinator`、`testRuntimeProjectionServiceClearsTerminatedAppRuntimeState`、`testRuntimeProjectionServiceDrainsVerifiedFocusThroughCoordinator`、`testRuntimeProjectionServiceSeedsVerifiedFocusRecordWithoutPriorMappingState`、`testRuntimeSystemRepairFactProviderWindowListKeepsStickyCGEntriesBoundToSpaceOneDuringTransientAXRebuild`、`testRuntimeSystemRepairFactProviderWindowListHidesStickyCGEntriesBoundToSpaceOneAfterAXRebuildGraceRetriesExhausted` 已通过 `run-flowtabtests-local.sh` targeted run。Search freshness 命名保持严格：barrier 未成功提交新 generation 时只能是 degraded/stale committed read，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 exact-match WindowRecord mutation ownership：public exact match、private exact bridge、fullscreen rebinding、desktop sibling binding 与 fullscreen content fallback binding 的 AX/CG matches 现在都通过 `RuntimeWindowRecord.applyExactMatches(...)` 写入 `RuntimeWindowRecord` 与 `exactMatchesByAXWindowID`；`RuntimeSystemRepairFactProvider+WindowMapping.swift` 不再保留 provider-private `applyExactMatches(...)` mutation helper。provider 仍负责底层 AX/CG/Space fact sampling 与 mapping orchestration，但 exact-match record creation/title resolution/attachment writeback 的 ownership 已回到 WindowRecord 类型。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 deterministic WindowRecord mutation helper placement cleanup，不改变采样、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage: `testRuntimeSystemRepairFactProviderStoresCGFirstWindowRecordsAsSingleSourceOfTruth`、`testRuntimeSystemRepairFactProviderResolveCGWindowAssignmentsUsesGeometryWithDuplicateTitles`、`testRuntimeSystemRepairFactProviderWindowListUsesPrivateExactBridgeWhenPublicSignalsRemainAmbiguous`、`testRuntimeSystemRepairFactProviderBindsDesktopSiblingAXHandleWhenFullscreenWrapperCGAlsoExists`、`testRuntimeSystemRepairFactProviderKeepsDesktopSiblingWhenAXOnlySeesFullscreenWrapper` 已通过 `run-flowtabtests-local.sh` targeted run。Search freshness 命名保持严格：barrier 未成功提交新 generation 时只能是 degraded/stale committed read，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 WindowRecord mapping state transaction ownership：`RuntimeWindowMappingState` 现在拥有 AX collection presence/miss metadata、valid CG refresh 与 record seeding、matching 前 current AX attachment 清理、fallback display state 更新、record lifecycle reconcile，以及 derived indexes commit；`RuntimeSystemRepairFactProvider+WindowMapping.swift` 只保留 public/private/topology binding orchestration 和 presentation assembly，不再手写 state transaction / derived-index writeback。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 deterministic state ownership cleanup，不改变 AX/CG/Space sampling、window exposure rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 provider/WindowRecord mapping tests through `run-flowtabtests-local.sh`，证明 CG-first WindowRecord storage、duplicate-title geometry assignment、private exact bridge、desktop sibling binding、fullscreen wrapper fallback 与 transient AX rebuild grace 仍按既有 contract 输出。Search freshness 命名保持严格：barrier 未成功提交新 generation 时只能是 degraded/stale committed read，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 sticky binding application ownership：`RuntimeWindowMappingState.applyReusableStickyBindings(...)` 现在拥有 sticky AX ID/element continuity 复用后的 state mutation、sticky conflict diagnostic、title resolution、`record.applyExactMatch(...)` 写回、assigned AX IDs 与 exact match map 产出；provider window mapping 只消费该 result 继续 public/private/topology binding source orchestration。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 deterministic WindowRecord state mutation placement cleanup，不改变采样、window exposure rules、activation oracle、Search barrier、surface behavior 或 hot-path cost。Required behavior coverage 复用 sticky record/provider tests through `run-flowtabtests-local.sh`，证明 exact sticky AX ID reuse、AX element continuity、sticky conflict preservation 与 provider sticky window exposure 仍按既有 contract 输出。Search freshness 命名保持严格：barrier 未成功提交新 generation 时只能是 degraded/stale committed read，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 WindowRecord store commit ownership：`RuntimeWindowRecordStore.commitState(_:for:)` 现在拥有 mapping state 空表删除/非空保留规则；provider window mapping 只提交完成后的 `RuntimeWindowMappingState`，不再手写 `nextState.isEmpty` writeback branch。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 store writeback ownership cleanup，不改变 lifecycle reconcile、sampling、window exposure rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 `testRuntimeSystemRepairFactProviderDropsWindowRecordAfterLifecycleGraceExpires` through `run-flowtabtests-local.sh`，证明 lifecycle grace 后空 mapping state 仍从 store 删除；sticky/CG-first provider tests 证明非空 state 仍保留并输出稳定 WindowRecord mapping。Search freshness 命名保持严格：barrier 未成功提交新 generation 时只能是 degraded/stale committed read，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 stable WindowRecord mapping resolution ownership：`RuntimeWindowRecordStore.resolveStableWindowMapping(...)` 现在拥有 PID-keyed state read、AX/CG transaction、sticky reuse、public/private/topology exact binding、fullscreen/desktop sibling fallback binding、derived-index commit、lifecycle cleanup 与 final store commit；随后 `RuntimeWindowMappingPresentationAssembler` 消费 returned resolution 组装 presentation entries，provider 不再暴露 provider-owned stable mapping resolver。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 deterministic ownership/file-boundary cleanup，不改变 AX/CG/Space sampling、window exposure rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 provider/WindowRecord mapping tests through `run-flowtabtests-local.sh`，证明 lifecycle deletion、CG-first storage、duplicate-title geometry assignment、private exact bridge、desktop sibling binding、fullscreen wrapper fallback 与 transient AX rebuild grace 仍按既有 contract 输出。Search freshness 命名保持严格：freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 last committed index 的 stale/degraded committed read 或 `degradedStaleCommittedResult`，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 window-entry presentation assembly ownership：`RuntimeSystemRepairFactProvider+WindowMapping.swift` 已改名为 `RuntimeWindowMappingPresentationAssembler.swift`，并从 provider extension 变为 runtime-owned assembler。`RuntimeSystemRepairFactProvider` 只在私有 `resolvedWindowEntries(...)` collection path 调用 assembler；TestingSupport 的 mapping helpers 也直接创建 `RuntimeWindowRecordStore` 并调用 store resolver / assembler，不再为了 deterministic mapping proof 构造 `RuntimeSystemRepairFactProvider`。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 deterministic API/file-boundary cleanup，不改变 AX/CG/Space sampling、window exposure rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 provider/WindowRecord window-entry tests through `run-flowtabtests-local.sh`，证明 sticky/in-grace/space-backed/provisional/filtering presentation 仍按既有 contract 输出。Search freshness 命名保持严格：freshness barrier 成功提交新 generation 前只能返回 last committed index 的 stale/degraded committed read 或 `degradedStaleCommittedResult`，不能命名为 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 Space topology WindowRecord table access：`RuntimeWindowRecordStore.recordSpaceTopologySnapshot(...)` 现在拥有 topology snapshot diff 写回与 affected WindowRecord reconciliation marking 的 store entry，`RuntimeWindowRecordStore.affectedCGWindowIDsByPID(...)` 现在拥有 affected CGWindowID 从 current CG facts + recorded WindowRecord history pull back 到 PID/window scope 的 store entry。`RuntimeSystemRepairFactProvider.collectCGWindowsWithSpaceTopologyDiff(...)` 与 `RuntimeProjectionRepairFactSource.collectSpaceTopologyReconciliationTargets(...)` 不再直接传递或读取 raw `mappingStatesByPID` 完成 topology evidence/scope。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 topology evidence access ownership cleanup，不改变 Space topology fact source、diff rule、sampling、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 store/evidence/coordinator topology tests through `run-flowtabtests-local.sh`，证明 topology snapshot 仍调度 coordinator、signature diagnostics 仍存在、affected WindowRecord 仍标记 reconciliation，且 affected PID/window scope 仍合并 current CG facts 与 recorded history。Search freshness 命名保持严格。
- Phase 5 本轮 P0 继续收窄 verified-focus / AX-destroyed WindowRecord evidence access：`RuntimeWindowRecordStore.recordWindowFocusVerification(...)` 现在拥有 focused AX/CG readback exact evidence 写回，`RuntimeWindowRecordStore.clearDestroyedAXAttachment(...)` 现在拥有 destroyed AX attachment downgrade 与 affected `CGWindowID` evidence return。`RuntimeProjectionRepairProvider.swift` 只通过 store semantic methods 写 WindowRecord table，再调度 coordinator；不再直接把 raw `mappingStatesByPID` inout 传给 evidence helper，也不把底层 `RuntimeSystemRepairFactProvider` storage 暴露给 same-module callers。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 evidence writeback ownership cleanup，不改变 readback oracle、AX destroyed signal source、sampling、surface behavior、activation success proof、Search barrier 或 hot-path cost。Required behavior coverage 复用 store/service/coordinator tests through `run-flowtabtests-local.sh`，证明 destroyed AX attachment downgrade 保留 sticky WindowRecord、AX-destroyed signal 仍带 affected window scope，verified-focus readback 仍写 exact evidence、可 seed 无 prior state，并在 non-registry focused AX readback 时使用 fallback AX id。Search freshness 命名保持严格：barrier 未成功提交新 generation 时仍只能是 degraded/stale committed read，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 repair-provider fact-provider storage ownership：`RuntimeProjectionRepairProvider+Reconciliation.swift` 已删除，reconciliation implementation co-located in `RuntimeProjectionRepairProvider.swift`。`RuntimeProjectionRepairFactSource` 的底层 `runtimeFactProvider` field 降为 private，并保留显式 initializer 给 facade 注入；concrete repair facade 之后也已删除自己的 duplicate bottom fact-provider field，same-module code 不能再从 repair-provider/fact-source facade unwrap 回底层 provider field。Fact source 仍拥有 repair/fallback fact sampling，不是 surface hot-path read。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 access-control/file-boundary cleanup，不改变采样、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 repair-provider/service/search barrier tests through `run-flowtabtests-local.sh`，证明 read-model ownership、Space topology drain、topology reconciliation、AX-destroyed/verified-focus/terminated-app cleanup 与 Search committed-index barrier semantics 仍按既有 contract。Search freshness 命名保持严格：freshness barrier 成功提交新 generation 前只能返回 last committed index 的 `degradedStaleCommitted` / `degradedStaleCommittedResult` 与 dirty/freshness metadata，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 repair-provider projection-builder fact-source storage ownership：`RuntimeProjectionRepairProvider+ProjectionBuilders.swift` 已删除，full/current/focused projection payload builders co-located in `RuntimeProjectionRepairProvider.swift` so `repairFactSource` can be `private` storage on the concrete facade. At that point same-module callers could still request full/current/focused payload helpers through the repair-provider semantic API, but could not grab the fact source and run bottom CG/AX/Space repair sampling directly. 2026-06-24 Phase 6 后，focused-PID scoped repair 已进一步改为 evidence-only path，`focusedCurrentAppWindowPayload(processIdentifier:)` 不再存在；appID-scoped provider payload helper 与 provider-facing `fullRepairProjectionPayload()` 也已删除，UI-test payload seeds 只留在 TestingSupport / assembler fixture 边界。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 access-control/file-boundary cleanup，不改变采样、projection payload assembly rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 mock/full/current repair payload、default full repair commit、read-model ownership 与 Search barrier tests through `run-flowtabtests-local.sh`。Search freshness 命名保持严格：freshness barrier 成功提交新 generation 前只能返回 last committed index 的 `degradedStaleCommitted` / `degradedStaleCommittedResult` 与 dirty/freshness metadata，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 WindowRecord store raw table seam：`RuntimeWindowRecordStore.mappingStatesByPID` 现在是 private storage，production、TestingSupport 与 tests 都必须通过 `setState(...)` / `commitState(...)` / `removeState(...)` / `state(for:)` 或 store-owned evidence/scope methods 接触 PID-keyed state。`RuntimeWindowMappingTestSupport` 与代表性 FlowTabTests seed/inspection 已迁移到 store API，不再下标读写 raw table。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 storage encapsulation cleanup，不改变 WindowRecord rules、sampling、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 store/lifecycle/topology/verified-focus/AX-destroyed/assignment tests through `run-flowtabtests-local.sh`，证明 store private storage 仍支持 commit/delete、topology marking and pullback、verified-focus/AX-destroyed evidence、TestingSupport mapping seed 与 transient AX rebuild behavior。Search freshness 命名保持严格。
- Phase 5 本轮 P0 继续收窄 provider fact-collection diagnostics ownership：`RuntimeSystemRepairFactProvider+Diagnostics.swift` 已删除，底层 CG/AX/Space fact collection timing helper、timing-line formatter、millisecond formatter 与 app-name/app-identifier log formatter 改由 `RuntimeFactCollectionDiagnostics.swift` 承载。底层日志现在写 `RuntimeFacts` category，事件名和字段保持不变，因为这里记录的是 CG/AX/Space fact collection diagnostics；diagnostics helper 不再作为 `RuntimeSystemRepairFactProvider` extension API 暴露，避免 provider 继续拥有 snapshot-shaped timing seam。这不改变采样、projection commit、activation、Search 或 hot-path behavior。Required behavior coverage: `testRuntimeSystemRepairFactProviderWindowEntriesCarrySpaceEvidence` 与 `testRuntimeSystemRepairFactProviderWindowListFiltersDuplicateFullscreenGeometryHosts` 已通过 `run-flowtabtests-local.sh` targeted run，并重新编译 `RuntimeSystemRepairFactProvider.swift` / `RuntimeFactCollectionDiagnostics.swift`。freshness barrier 未成功提交新 generation 时 Search 仍只能是 degraded/stale committed result。
- Phase 5 本轮 P0 继续收窄 production/test boundary：`AXWindowInspectorForTesting` 已从生产 `AXWindowInspector.swift` 移到 `FlowTab/TestingSupport/AXWindowInspectorTestSupport.swift`，测试 facade 只转发 production AX read/log/title helper 与 typed AX extraction helper；生产 AX inspector 不再承载 testing-only enum。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 testing seam placement cleanup，不改变 AX/CG/Space sampling、WindowRecord rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 AX inspector helper、AX destroyed routing、verified-focus readback/seed tests through `run-flowtabtests-local.sh`。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前，当前行为只能写成 last committed index 的 stale/degraded committed read 或 `degradedStaleCommittedResult`，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 repair-provider state ownership：`RuntimeProjectionRepairProvider` 现在显式持有 `RuntimeWindowRecordStore` 与 `RuntimeReconciliationCoordinator`，并把同一实例注入底层 `RuntimeSystemRepairFactProvider` fact sampler；`RuntimeSystemRepairFactProvider.windowRecordStore` / `reconciliationCoordinator` 已降为 private storage，`RuntimeProjectionRepairFactSource` 也通过 facade-owned store 完成 cleanup 与 affected-window pullback，不再从 provider 解包 state。FlowTabTests 若要检查 WindowRecord/coordinator state，必须显式创建并注入 store/coordinator 后检查该 owner，而不是读取 provider 字段。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 ownership/access cleanup，不改变采样、WindowRecord rules、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage: `testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals`、`testRuntimeProjectionServiceDrainsSpaceTopologySignalThroughCoordinator`、`testRuntimeProjectionRepairProviderReconcilesSpaceTopologyThroughAffectedTargets`、`testRuntimeProjectionServiceSignalsDestroyedAXWindowThroughCoordinator`、`testRuntimeProjectionServiceDrainsVerifiedFocusThroughCoordinator`、`testRuntimeSystemRepairFactProviderStoresCGFirstWindowRecordsAsSingleSourceOfTruth`、`testRuntimeSystemRepairFactProviderDropsWindowRecordAfterLifecycleGraceExpires` 已通过 `run-flowtabtests-local.sh` targeted run。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前只能返回 last committed index 的 stale/degraded committed read 或 `degradedStaleCommittedResult`，不能命名为 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 repair selection fact conversion ownership：`RuntimeAppWindowSelectionFacts` / `RuntimeFullRepairAppSelectionFacts` 到 `RuntimeCurrentAppWindowProjectionAssemblyInput` 的转换已从 `RuntimeProjectionPayloads.swift` 移入 `RuntimeProjectionRepairFactSource.swift`，与 repair/fact-source selection DTO 同层。`RuntimeProjectionPayloads.swift` 现在只承载 runtime projection payload/input shape 与 payload assembly 类型，不再通过 extension 了解 repair selection intermediate state。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 deterministic file-boundary cleanup，不改变 AX/CG/Space sampling、projection assembly 输出、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage 复用 projection payload / repair-provider tests through `run-flowtabtests-local.sh`。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 last committed index 的 stale/degraded committed read 或 `degradedStaleCommittedResult`，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 repair-provider contract ownership：`RuntimeProjectionRepairProviding` 与 `RuntimeAppWindowReconciliationResult` 已从 concrete `RuntimeProjectionRepairProvider.swift` 移入 `RuntimeProjectionRepairContract.swift` 并加入 app target。`RuntimeProjectionService` / `RuntimeProjectionMaintenance` 依赖正式 repair contract file，concrete provider 文件只保留 facade storage、fact-source wiring、payload repair builders 与 reconciliation implementation，不再兼任 service-facing protocol 定义位置。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 mechanical contract/file-boundary cleanup，不改变 AX/CG/Space sampling、projection output、surface behavior、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage: `testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals`、`testRuntimeProjectionServiceDrainsSpaceTopologySignalThroughCoordinator`、`testRuntimeProjectionRepairProviderReconcilesSpaceTopologyThroughAffectedTargets`、`testRuntimeProjectionServiceSearchFreshnessBarrierCommitsRepairedSearchGeneration`、`testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRepairDefers` 已通过 `run-flowtabtests-local.sh` targeted run。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 last committed index 的 stale/degraded committed read 或 `degradedStaleCommittedResult`，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 surface-facing projection serving contract ownership：`RuntimeProjectionServing` 已从 concrete `RuntimeProjectionService.swift` 移入 `RuntimeProjectionServing.swift` 并加入 app target。Switcher、Home、Search、AppDelegate testing hooks 与 tests 现在依赖独立的 projection read / dirty-signal / activation-readback signal contract file；`RuntimeProjectionService.swift` 只保留 shared instance、read-model store ownership、maintenance queue、repair-provider drain 与 commit/freshness orchestration。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 mechanical read API contract/file-boundary cleanup，不改变 surface call sequence、AX/CG/Space sampling、projection output、activation oracle、Search barrier 或 hot-path cost。Required behavior coverage: `testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals`、`testLiveSwitcherModelStartsAppSessionFromRuntimeProjectionWithoutLightweightSampling`、`testLiveSwitcherModelSelectedAppWindowProjectionUsesRuntimeProjectionWithoutHomeSampling`、`testHomeRuntimeProjectionReaderUsesRuntimeProjectionsWithoutSnapshotBridge`、`testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRepairDefers` 已通过 `run-flowtabtests-local.sh` targeted run。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 last committed index 的 stale/degraded committed read 或 `degradedStaleCommittedResult`，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 runtime maintenance policy ownership：`RuntimeProjectionMaintenanceReason` 与 bounded Search freshness barrier batch limit `runtimeSearchFreshnessBarrierMaxReadyRepairs` 已移入 `RuntimeProjectionMaintenancePolicy.swift` 并加入 app target。`RuntimeProjectionServing` 与 surface test doubles 只引用 maintenance request vocabulary，`RuntimeProjectionService` 只消费 policy 的 Search barrier bound，reconciliation drain outcome、executor、drainer 与 default execution rules 只由 `RuntimeProjectionReconciliationDrainer.swift` 承载。P1 同轮更新文档与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 mechanical policy/file-boundary cleanup，不改变 scheduler decisions、surface call sequence、AX/CG/Space sampling、projection output、activation oracle、Search barrier bound value 或 hot-path cost。Required behavior coverage: `testRuntimeProjectionServiceSearchFreshnessBarrierPromotesAndBoundsReadyRepairs`、`testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRepairDefers`、`testRuntimeProjectionServiceMaintenanceRequestDrainsReadyRequestsBySchedulerPriority`、`testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals`、`testLiveSwitcherModelRequestsMaintenanceWhenAppSwitcherProjectionIsMissing` 已通过 `run-flowtabtests-local.sh` targeted run。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 last committed index 的 stale/degraded committed read 或 `degradedStaleCommittedResult`，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 runtime reconciliation drainer file ownership：`RuntimeProjectionMaintenance.swift` 已改名为 `RuntimeProjectionReconciliationDrainer.swift` 并更新 app target reference；policy/vocabulary 由 `RuntimeProjectionMaintenancePolicy.swift` 拥有，renamed drainer 文件只承载 reconciliation drain outcome、executor、drainer 与 default execution rules。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 mechanical file-boundary cleanup，不改变 scheduler decisions、surface call sequence、AX/CG/Space sampling、projection output、activation oracle、Search barrier bound value 或 hot-path cost。Required behavior coverage: `testRuntimeProjectionServiceSearchFreshnessBarrierPromotesAndBoundsReadyRepairs`、`testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRepairDefers`、`testRuntimeProjectionServiceMaintenanceRequestDrainsReadyRequestsBySchedulerPriority`、`testRuntimeProjectionServiceOwnsReadModelStoreForProjectionReadsAndDirtySignals`、`testLiveSwitcherModelRequestsMaintenanceWhenAppSwitcherProjectionIsMissing` 已通过 `run-flowtabtests-local.sh` targeted run。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前只能写成 stale/degraded committed read 或 `degradedStaleCommittedResult`。
- Phase 5 本轮 P0 按 freshness-barrier contract 再收紧 Search read-state vocabulary：`RuntimeSearchIndexReadiness` 只保留 `committedGenerationValidated`、`degradedStaleCommitted`、`missingCommittedIndex`，`RuntimeSearchIndexResultState` 只保留 `committedGenerationResult`、`degradedStaleCommittedResult`、`missingCommittedIndex`。成功态只表示 committed index 已通过 validation 覆盖 runtime 当前 generation；barrier 未成功提交新 generation 的当前行为必须记录为 `degradedStaleCommitted` / `degradedStaleCommittedResult` 或 degraded/stale committed read，即使 last committed index 仍有可展示 entries，也不能命名为 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 runtime Search read contract 命名/诊断/测试加固，不改变 scheduler decisions、surface call sequence、AX/CG/Space sampling、projection output、activation oracle、Search barrier bound value 或 hot-path cost。Required behavior coverage: `testLiveSwitcherModelSearchReportsDegradedStaleCommittedIndexUntilFreshnessBarrierCommits`、`testLiveSwitcherModelSearchPressureReadsCommittedGenerationValidatedIndexWithoutSampling`、`testRuntimeReadModelStoreKeepsStagingSearchIndexHiddenWithoutBarrierPayload`、`testRuntimeProjectionServiceSearchFreshnessBarrierCommitsRepairedSearchGeneration`、`testRuntimeProjectionServiceSearchFreshnessBarrierKeepsCommittedIndexStaleWhenRepairDefers` 已通过 `run-flowtabtests-local.sh` targeted run。
- Phase 5 本轮 P0 继续收窄 repair fact-source ownership：新增 `RuntimeProjectionRepairFactProviding` 窄协议，只表达 repair/fallback 所需的 AX window collection 与 CG+Space topology diff collection。`RuntimeProjectionRepairProvider` 和 `RuntimeProjectionRepairFactSource` 不再依赖 concrete `RuntimeSystemRepairFactProvider` 类型；`RuntimeSystemRepairFactProvider` 只是默认底层 fact source implementation，不能被 surface/service 作为 snapshot-shaped hot-path read seam 复用或扩张。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 ownership/type-boundary cleanup，不改变 scheduler decisions、surface call sequence、AX/CG/Space sampling cadence、projection output、activation oracle、Search barrier bound value 或 hot-path cost。Required behavior coverage 复用 read-model ownership、Space topology drain/reconciliation 与 Search committed-index barrier tests through `run-flowtabtests-local.sh`。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 last committed index 的 `degradedStaleCommitted` / `degradedStaleCommittedResult` 与 dirty/freshness metadata，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续收窄 duplicate bottom fact-provider ownership：`RuntimeProjectionRepairProvider` 不再保留 private `runtimeFactProvider` field；initializer 只构造默认 `RuntimeSystemRepairFactProvider` 并注入 `RuntimeProjectionRepairFactSource`。底层 CG/AX/Space fact sampling dependency 的唯一持有点因此是 fact-source 的 `RuntimeProjectionRepairFactProviding` existential，repair facade 不能绕过 fact-source contract 直接调用 bottom sampling。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 ownership/storage cleanup，不改变 scheduler decisions、surface call sequence、AX/CG/Space sampling cadence、projection output、activation oracle、Search barrier bound value 或 hot-path cost。Search freshness 命名保持严格：bounded freshness barrier 成功提交新 generation 前，当前 Search 行为只能写成 last committed index 的 `degradedStaleCommitted` / `degradedStaleCommittedResult` 与 dirty/freshness metadata，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续清理 snapshot-shaped default fact-source vocabulary：`RuntimeSnapshotProvider.swift` / `RuntimeSnapshotProvider` 已重命名为 `RuntimeSystemRepairFactProvider.swift` / `RuntimeSystemRepairFactProvider`，`RuntimeProjectionRepairProvider` 默认 initializer 与 `RuntimeProjectionRepairFactProviding` conformance 均指向新的 repair/fact-source 类型。生产代码不再有 `RuntimeSnapshotProvider` 类型引用或 app target 文件引用；deterministic tests 的 provider constructor 与代表性 test names 也改到 repair fact-provider 语义。P1 同轮更新 runtime docs 与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 mechanical type/file-boundary cleanup，不改变 scheduler decisions、surface call sequence、AX/CG/Space sampling cadence、projection output、activation oracle、Search barrier bound value 或 hot-path cost。Search freshness contract 不变：bounded barrier 未成功提交新 generation 前只能暴露 `degradedStaleCommitted` / `degradedStaleCommittedResult` 或 degraded/stale committed read。
- Phase 5 本轮 P0 继续清理 fact-collection log category ownership：legacy Snapshot category 已从 runtime fact collection 路径移除，`RuntimeFactCollectionDiagnostics.logTiming(...)` 与 `RuntimeWindowListDiagnostics` 的 chrome-topology / window-entries evidence 现在写入 `RuntimeLogCategory.runtimeFacts`。`snapshot` 只保留在非 runtime fact 语境中，例如 log-read snapshot、Space topology snapshot model 或历史迁移文档；底层 CG/AX/Space repair/fallback 采样日志不再通过 Snapshot 类目表达。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是 diagnostic category cleanup，不改变 scheduler decisions、surface call sequence、AX/CG/Space sampling cadence、projection output、activation oracle、Search barrier bound value 或 hot-path cost。Search freshness contract 不变：barrier 未成功提交新 generation 前只能是 degraded/stale committed result，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 5 本轮 P0 继续删除 legacy Snapshot log category：`RuntimeLogCategory.snapshot` enum case 已删除，`RuntimeLogCategory.resolve("Snapshot")` 现在返回 nil；生产代码无法再把新 runtime 诊断写入 Snapshot category，底层 fact collection 只能使用 `RuntimeFacts`，projection assembly / maintenance 只能使用 `Projection` 或更具体 category。P1 同轮更新 runtime logging docs 与 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为这是日志 category ownership cleanup，不改变 scheduler decisions、surface call sequence、AX/CG/Space sampling cadence、projection output、activation oracle、Search barrier bound value 或 hot-path cost。Search freshness contract 不变：barrier 未成功提交新 generation 前只能是 degraded/stale committed result，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 6 本轮 P0 纠正阶段漂移并启动主表生成 projection：连续两轮 P0 都是 log category cleanup 后，本轮停止继续 Phase 5 cleanup，转入 Phase 6。`RuntimeReadModelStore.readAppSwitcherProjection()` 现在在 committed app-switcher projection cache 缺失时，从 `RuntimeAppDirectoryState` 的 PID-keyed entries 派生 app-only app-switcher projection；该 projection 只包含 app layer 与空 window/context，携带 directory 主表 generation/freshness/dirty metadata，不读取 CG/AX/Space，不同步采样，不提交 committed Search index，也不把 staging/repair 中间态暴露为最新结果。P1 同轮让 diagnostics 把 directory-derived app-only projection 视为可读 app-switcher projection，并用 Search barrier stale 回归确认 Search 仍保持 degraded/stale committed contract。P2 不新增 UI/E2E 或 pressure proof，因为本轮只在 store 内把缺 cache 的 app-only projection 从长期 directory 主表派生，不改变 surface call sequence、activation oracle、Search barrier bound、window/context projection 或 hot-path sampling；后续 gap 是把 current-app/window/context projection 从 WindowRecord、app directory、Space topology 主表生成。
- Phase 6 本轮 P0 继续推进主表生成 projection：`RuntimeReadModelStore.readHomeSummaryProjection()` 现在在 committed Home summary projection cache 缺失时，也从 `RuntimeAppDirectoryState` 派生 app-only Home summary rows。derived Home summary 使用 directory entry 的 app identity/group/PID、stable app order 和 `windowCount = 0`，携带 app directory 主表 generation/freshness/dirty metadata；它不读取 CG/AX/Space，不等待 repair，不创建 current-app detail/context，不提交 committed Search index。P1 同轮让 diagnostics 把 directory-derived Home summary 视为可读 Home summary projection，并扩展 lifecycle store test 证明 dirty app launch evidence 产生 stale Home summary。P2 不新增 UI/E2E 或 pressure proof，因为本轮只改变 store-internal projection derivation，不改变 Home/Switcher/Search surface call sequence、activation oracle、Search barrier bound、window/context projection 或 hot-path sampling；后续 gap 仍是 current-app/window/context 和 Home detail 从 WindowRecord、app directory 与 Space topology 主表生成。Search freshness contract 继续保持严格：bounded freshness barrier 未成功提交新 generation 时，只能返回 last committed index 的 degraded/stale committed result 与 dirty/freshness metadata，不能进入最新搜索结果态，也不能命名为 fresh、complete、latest 或 current-generation committed。
- Phase 6 本轮 P0 继续推进 WindowRecord-backed projection input：`RuntimeWindowRecordStore.projectedWindowEntries(processIdentifier:appName:)` 现在把 WindowRecord 主表内的 current AX attachment、display title/frame、CG ID、Space recovery、binding confidence 与 activation handle 派生为 projection window facts；`RuntimeProjectionRepairFactSource.collectFullRepairWindowFacts(...)`、`collectCurrentAppWindowFacts(...)` 与 `collectFocusedCurrentAppWindowFacts(...)` 仍执行 bounded scheduler repair/fallback 采样来更新 WindowRecord，但 payload assembly 的 `windowsByPID` 改为从 WindowRecordStore 读取。测试用 fake provider 返回不同的 sampled entry，证明 current-app window facts 最终来自 WindowRecordStore 而不是 sampled payload。P1 同轮保持 Search freshness-barrier commit/stale 回归；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、activation oracle、Search barrier bound 与采样频率未改变。剩余 gap：ReadModelStore 仍需把 current-app/window/context 和 Home detail projection 直接从 WindowRecord + app directory + Space topology 主表提交/缓存，full repair 仍是把 facts 写入主表的 scheduler bridge。
- Phase 6 本轮 P0 继续把 current-app projection cache 的正常输入推进到主表：selected-current-app dirty signal 在 runtime maintenance queue 内调用 `RuntimeMainTableProjectionBuilding.currentAppWindowPayloadFromMainTables(...)`，用 `RuntimeReadModelStore` 已有 app directory entries + `RuntimeWindowRecordStore.projectedWindowEntries(...)` 生成 `RuntimeCurrentAppWindowPayload`，并通过 `commitCurrentAppWindowProjection(..., clearsDirtyState: false)` 写入 current-app/Home detail projection cache；后续 Phase 6 已删除 current-app commit 对 app-switcher/Home summary 的同步 upsert。该预提交不读取 CG/AX/Space，不清 dirty/pending repair，不提交 Search index；测试证明新窗口可进入 stale current-app projection，但 Search 仍保持 degraded/stale committed index，未进入最新搜索结果态。P1 同轮保持 Search stale 回归；P2 不新增 UI/E2E 或 pressure proof，因为 surface 首屏调用、采样频率、activation oracle 与 Search barrier bound 未改变。剩余 gap：full repair/current-app repair 仍承担部分 fact update/compat bridge，真实 topology UI/E2E proof 仍按 Phase 5 gap 追踪。
- Phase 6 本轮 P0 收口 Home detail ownership 的第一步：`RuntimeProjectionServing` 新增 `readHomeAppDetailProjection(appID:)`，`HomeRuntimeProjectionReader.appDetailProjection(...)` 不再直接读取 current-app/app-switcher projection 来拼 detail。后续 Phase 6 已继续收紧 `RuntimeReadModelStore.readHomeAppDetailProjection(appID:)`，使其只从 current-app projection cache 返回 detail，不再从 app-switcher projection cache/context 兼容派生。P1 同轮更新 Home reader / activation tests，并保留 Search stale 回归；P2 不新增 UI/E2E 或 pressure proof，因为 Home 可见交互、surface refresh signal、sampling cadence、activation oracle 与 Search barrier bound 未改变。剩余 gap：current-app/app-switcher cache 的部分来源仍是 full/current repair 兼容桥；后续需要让这些 cache 的 generation/commit 全部直接来自 WindowRecord + app directory + Space topology 主表。
- Phase 6 本轮 P0 继续推进 app-switcher/Home summary cache 的整表主表生成：app-switcher maintenance 先调用 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)`，用 runtime app directory 主表决定 app/group，用 WindowRecord 主表 `projectedWindowEntries(...)` 决定 windows/context，然后提交到 `RuntimeReadModelStore` 的 app-switcher 与 Home summary projection cache；该提交不调用底层 CG/AX/Space fact source，不提交 Search index，在 dirty/pending repair 存在时保持 degraded/stale committed projection。P1 同轮让 app-switcher payload commit 同步维护 Home summary cache，并用 Search stale 回归证明未提交 freshness barrier 时 Search 仍不能进入最新结果态。后续 Phase 6 已删除 production `commitAppSwitcherProjection(...)` direct write 入口，测试污染 seed 改为 test-only helper。P2 不新增 UI/E2E 或 pressure proof，因为 surface 首屏调用、真实 activation oracle、Search barrier bound 与采样 cadence 未改变。后续 Phase 6 已把 Search committed index success 收口到 freshness barrier + committed projection cache；剩余 gap 是 full/current repair 仍会作为 fact update/compat bridge 写主表，并补真实 committed-index UI 与 pressure proof。
- Phase 6 本轮 P0 继续收口 Search committed index generation：bounded Search freshness barrier 会先刷新 main-table app-switcher projection cache，并且只在 projection cache `sourceGeneration` 覆盖当前 runtime generation、无 deferred/pending repair 时，调用 `RuntimeReadModelStore.commitSearchFreshnessBarrierFromProjectionCache(...)` 从 committed projection cache 构建新的 `committedSearchIndex`。旧 projection cache、repair 中间态或任何 partial/staging 数据仍不能进入最新结果态；barrier 未提交时仍是 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation committed。P1 同轮补 store/service behavior coverage 与文档/coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 Search surface call sequence、barrier bound、sampling cadence 与 activation oracle 未改变。剩余 gap：真实 committed-index Search UI proof、pressure proof，以及 full/current repair 作为 fact-update/compat bridge 的剩余路径仍需后续收口。
- Phase 6 本轮 P0 继续把 Search barrier 成功路径从 staging/repair payload 迁到 projection cache：`RuntimeProjectionService.requestSearchIndexFreshnessBarrier(...)` 现在先刷新 main-table app-switcher projection cache，再把 scoped repaired current-app outcome 降级为 evidence/trigger 并通过 main-table current-app builder 更新 projection cache，最后只调用 `commitSearchFreshnessBarrierFromProjectionCache(...)` 尝试提交 `committedSearchIndex`。service/store 不再调用或暴露 `commitSearchFreshnessBarrierPayloads(...)`，也不再维护 production `stagingSearchIndex`；因此没有 repaired payload/staging 能直接生成最新结果。P1 同轮用 stale/degraded projection-cache behavior tests 加固该 contract，并更新文档/coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 Search surface call sequence、barrier bound、sampling cadence、activation oracle 与 hot-path shape 未改变。剩余 gap：真实 Search UI/pressure proof 与更广 repair/fact bridge 收口后续处理。
- Phase 6 本轮 P0 继续收紧 Search freshness 命名：当时的 direct app-switcher projection commit 不再在 `clearsDirtyState` 时隐式构建 `committedSearchIndex`，普通 app-switcher/Home projection commit 因此不能让 Search 进入 fresh/complete/latest/current-generation 结果态；后续 Phase 6 已进一步删除 production `RuntimeReadModelStore.commitAppSwitcherProjection(...)` direct write API 与 `RuntimeReadModelStore.markAppTerminated(...)` direct termination pruning API。termination metadata/projection 更新不剪 committed Search index；barrier 未成功提交新 generation 前 readback 仍是 `degradedStaleCommittedResult`，旧 index 可保留 terminated rows。P1 同轮把既有 tests 的 committed Search fixture seed 改为显式 `commitSearchFreshnessBarrierFromProjectionCache(...)`，并更新文档/矩阵；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、barrier bound、sampling cadence、activation oracle 与 repeated hot-path cost 未改变。
- Phase 6 本轮 P0 继续降级 full-repair fallback 的 projection ownership：`RuntimeProjectionService` 不再把 `RuntimeFullRepairProjectionPayload.apps` / `contextsByID` 直接提交为正常 app-switcher/Home projection cache；full-repair drain 只写 `RuntimeReadModelStore.commitFullRepairAppDirectoryEvidence(...)`，随后用 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 从 app directory + WindowRecordStore 主表生成 `RuntimeAppSwitcherProjectionPayload`，再由 `RuntimeReadModelStore.commitMainTableAppSwitcherProjectionPayload(...)` 提交 app-switcher/Home projection cache。该 store commit 不写 app directory evidence，不提交 Search index；cold-start full repair 只能留下 missing committed Search index，已有 committed index 时的 fallback 仍保持 degraded/stale committed。行为测试故意让 full-repair sampled payload window 与 WindowRecord 主表 window 不一致，最终 projection 只能包含 CG-stable main-table window。P1 同轮更新文档/coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path shape 未改变。剩余 gap：真实 UI/pressure proof 后续收口；full repair payload 仍作为 repair/fallback evidence DTO 存在，但不再是主表 app-switcher builder output shape。
- Phase 6 本轮 P0 继续降级 current-app repair projection ownership：`RuntimeProjectionService` 不再把 repaired `RuntimeCurrentAppWindowPayload` 的 candidate/window rows 直接提交为 current-app/app-switcher/Home projection cache；drain 只 upsert payload 的 app-directory evidence，再用 payload appID/pid 调用 `RuntimeMainTableProjectionBuilding.currentAppWindowPayloadFromMainTables(...)` 从 app directory + WindowRecordStore 主表生成 projection。Search barrier 成功测试故意让 repaired payload 带 `repair-payload-contamination` window，而 WindowRecord 主表带 CG-stable main-table window；最终 committed Search index 只能包含主表 CG-stable window，并排除 repaired payload contamination。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path shape 未改变。剩余 gap：full repair 仍作为 repair/fallback evidence DTO 存在，真实 UI/pressure proof 后续收口。
- Phase 6 本轮 P0 继续删除 production scoped repair payload bridge：`RuntimeProjectionRepairProvider.currentAppWindowPayload(for:)` 与 `RuntimeUITestProjectionDatasetFacts.currentAppWindowPayload(for:)` 已删除。UI-test window-recency seeding 直接读取 TestingSupport 的 `FlowTabUITestRuntimeProjectionDataset.currentAppWindowPayloadsByAppID`，mock current-app payload tests 也直接验证 TestingSupport seed；production repair provider 不再为了 appID-scoped fixture/current-app lookup 运行 repair/fact sampling 并返回 scoped payload。`RuntimeMainTableProjectionBuilding.currentAppWindowPayloadFromMainTables(...)` 是主表 -> projection cache builder；后续 Phase 6 已把 concrete builder 从 repair provider facade 移到 `RuntimeMainTableProjectionBuilder`。full repair payload 只保留为 repair/fallback evidence DTO，不再作为主表 app-switcher builder output shape。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path shape 未改变。剩余 gap：真实 committed-index Search UI proof 与 topology pressure proof 后续收口。
- Phase 6 本轮 P0 继续切断 full-repair drainer/service 的 projection-row 运输：`RuntimeProjectionRepairProviding` 的 full-repair contract 改为 `fullRepairEvidence()`，`RuntimeProjectionReconciliationExecutionOutcome.completedWithFullRepairEvidence` 与 drain result 只携带 `RuntimeFullRepairEvidence(appDirectoryEntries:)`，`RuntimeProjectionService` 只提交这份 directory evidence 后通过 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 从 app directory + WindowRecordStore 主表生成 app-switcher/Home projection cache。`RuntimeFullRepairProjectionPayload` 仍保留给 fixture 和旧 builder 测试，但不再跨过 drainer/service 正常边界，也不能作为 Search freshness/current-generation oracle。Required behavior coverage uses `testRuntimeProjectionServiceMaintenanceSchedulesLowPriorityFullRepairWhenProjectionMissing`, `testRuntimeProjectionServiceFullRepairFallbackCommitsMainTableProjectionWithoutRefreshingSearch`, `testRuntimeProjectionServiceDefaultFullRepairCommitsEvidenceThroughMainTableProjection`, and Search stale/freshness-barrier regressions through `run-flowtabtests-local.sh`. P1 同轮把文档和 coverage matrix 的 barrier 未提交状态写成 degraded/stale committed result；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Remaining Phase 6 gap:真实 committed-index Search UI proof、topology pressure proof，以及旧 full-repair payload fixture/assembler 的最终降级仍需后续收口。
- Phase 6 本轮 P0 继续删除 production full-repair projection payload facade：`RuntimeProjectionRepairProvider.fullRepairProjectionPayload()` 已删除，mock runtime full-repair payload tests 改为从 `FlowTabUITestRuntimeProjectionDataset` 显式构造 fixture payload，real-path-without-AX coverage 改为验证 `fullRepairEvidence()` + `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 的主表生成路径。production repair provider 现在不能作为 full-repair projection-row 读入口；full repair 只能作为 evidence/fact update 进入主表，Search barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result，不能命名为 fresh、complete、latest 或 current-generation committed。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Remaining Phase 6 gap:真实 committed-index Search UI proof、topology pressure proof，以及 full-repair DTO/fixture 的进一步收口。
- Phase 6 本轮 P0 继续把 mock-runtime repair fact-source 收口为 evidence-only：`RuntimeUITestProjectionDatasetFacts` 不再携带 `RuntimeFullRepairProjectionPayload` 或 `currentAppWindowPayloadsByAppID`，只暴露 full-repair app-directory evidence、diagnostic counts 与 focused current-app repair evidence。`RuntimeProjectionRepairProvider` 因此无法再从 mock fact-source 读到 full/current projection payload rows；mock full/current payload seeds 只留在 TestingSupport fixture 和 tests。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Remaining Phase 6 gap:真实 committed-index Search UI proof、topology pressure proof，以及 full-repair DTO/fixture 的进一步收口。
- Phase 6 本轮 P0 继续把 full-repair payload/assembler 从 production runtime payload 边界降级为测试 fixture：`RuntimeFullRepairProjectionPayload` 与 `RuntimeFullRepairProjectionAssembler` 已从 `FlowTab/Infrastructure/Runtime/RuntimeProjectionPayloads.swift` 移到 `FlowTab/TestingSupport/RuntimeFullRepairProjectionTestSupport.swift`，`RuntimeProjectionPayloads.swift` 只保留 normal app-switcher/current-app projection payload 与 assembly input。production `FlowTab/Infrastructure/Runtime` 现在没有 full-repair projection payload/assembler 类型引用，full repair 只能通过 `fullRepairEvidence()` 写 app-directory evidence，再经主表 app-switcher/current-app builders 生成 normal projection cache；Search barrier 未提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index，不能命名为 fresh、complete、latest 或 current-generation committed。P1 同轮更新 runtime docs、coverage matrix、legacy unit/behavior coverage 文档，并把 timing diagnostic example 从 `fullRepairProjectionPayload` 改为 `fullRepairEvidence`。P2 不新增 UI/E2E 或 pressure proof，因为这是 ownership/file-boundary cleanup，不改变 surface sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost；remaining gaps 仍是真实 committed-index Search UI proof、topology pressure proof 与更广 fixture cleanup。
- Phase 6 本轮 P0 继续把 normal main-table projection builder 从 repair-provider protocol 拆出：新增 `RuntimeMainTableProjectionBuilding`，`RuntimeProjectionService` 通过该 builder 生成 current-app 与 app-switcher/Home projection cache，`RuntimeProjectionRepairProviding` 只保留 repair evidence、scheduler、AX destroyed、verified focus 等 repair/fallback contract。该轮仍让 `RuntimeProjectionRepairProvider` conform builder 作为迁移桥；后续 Phase 6 已把 concrete implementation 移到独立 `RuntimeMainTableProjectionBuilder`。P1 同轮更新 coverage matrix 与测试命名；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Search barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。
- Phase 6 本轮 P0 继续把 concrete normal projection generation 从 repair facade 移出：`RuntimeMainTableProjectionBuilder` 现在持有 `RuntimeWindowRecordStore` 并实现 current-app 与 app-switcher/Home 主表 projection assembly；`RuntimeProjectionRepairProvider` 不再 conform `RuntimeMainTableProjectionBuilding`，也不再包含 normal main-table builder methods。默认 `RuntimeProjectionService` 会创建 shared `RuntimeWindowRecordStore` / `RuntimeReconciliationCoordinator`，把同一 store 注入 repair provider 与 main-table builder；custom injected repair providers 若要 normal projection 必须显式传入同 store builder，未传时只得到 fail-closed unavailable builder，不能伪装 fresh/complete。P1 同轮更新 tests/docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Search barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index。Remaining gaps: repair/fallback 仍负责 app directory/WindowRecord fact update；真实 committed-index Search UI proof、topology pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续收紧 app directory 主表 ownership：`RuntimeMainTableProjectionBuilder.currentAppWindowPayloadFromMainTables(...)` 现在要求 app directory 主表已有匹配 appID/pid entry；即使可以拿到 `NSRunningApplication` 作为 activation context handle，也不会再在 normal current-app builder 内从 running app 合成 `RuntimeAppDirectoryEntry`。app directory 缺失时 current-app projection fail-closed，必须等待 lifecycle / current-app repair / full repair evidence 先写入 `RuntimeAppDirectoryState`，从而避免 normal projection builder 成为第二个 app fact source。P1 同轮补 builder behavior coverage 与 docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Search barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index。Remaining gaps: app directory entries 仍主要来自 lifecycle/repair/fallback evidence，真实 committed-index Search UI proof 与 topology pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 Home detail/current-app cache 的普通 app-window dirty path 迁到主表生成：`RuntimeProjectionService.signalAppWindowsChanged(...)` 现在和 selected-current-app dirty、current-app repair evidence 一样，通过同一个 `commitMainTableCurrentAppProjectionLocked(...)` helper 从 `RuntimeReadModelStore` app directory entries + `RuntimeWindowRecordStore.projectedWindowEntries(...)` 预提交 `RuntimeCurrentAppWindowPayload`。该 path 不等待 repaired payload rows，不清 dirty/pending repair，不提交 Search index；Home detail read 随后可从 current-app projection cache 读取 WindowRecord 主表窗口，Search 仍只能是 degraded/stale committed 或 missing committed index，不能叫 fresh/complete/latest。P1 同轮补 behavior coverage 与 docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为 Home surface read API、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Remaining gaps: app directory evidence 来源仍主要来自 lifecycle/repair/fallback，真实 committed-index Search UI proof 与 topology pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 app launch lifecycle projection cache 迁到主表生成：`RuntimeProjectionService.signalAppLaunched(...)` 在写入 app directory dirty evidence 后，会调用 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 用 runtime app directory entries + WindowRecordStore 预提交 app-switcher/Home summary projection cache。normal 整表预提交现在要求主表 app directory 覆盖既有 app-switcher appIDs，迁移期 legacy cache 缺 directory evidence 时不会用部分主表 payload 覆盖完整旧 cache；该 path 不等待 launched-app repaired payload rows，不清 dirty/pending repair，不提交 Search index。已有 committed Search index 只能继续作为 `degradedStaleCommittedResult` 暴露，missing index 也只能保持 missing，不能因为 launch projection cache 可读而进入 fresh/complete/latest/current-generation committed 搜索结果态。P1 同轮补 behavior coverage 与 docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface read API、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Remaining gaps: app directory evidence 来源仍主要来自 lifecycle/repair/fallback，真实 committed-index Search UI proof 与 topology pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 app termination lifecycle projection cache 迁到主表生成，并把正常 service path 从 direct Search 剪枝兼容入口拆开：`RuntimeProjectionService.signalAppTerminated(...)` 现在调用 `RuntimeReadModelStore.markAppTerminatedForMainTableProjection(...)` 只维护 app directory/current-app/dirty metadata，不剪枝或重写 `committedSearchIndex`；随后交给 repair-provider 清理 terminated PID 的 WindowRecord/AX registry/coordinator state，再用 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 从剩余 app directory + WindowRecord 主表预提交 app-switcher/Home summary projection cache。coverage guard 对 termination path 只允许被 terminated appID 缺席，避免其它既有 app 被部分主表 payload 吞掉；测试用 legacy cache contamination 证明最终 projection windows 来自 WindowRecord 主表，并证明即使 app-switcher/Home projection cache 已 complete，Search 仍只能读取 last committed index 的 `degradedStaleCommittedResult`，其中可以保留 terminated app/window row，不能叫 fresh/complete/latest/current-generation committed。后续 Phase 6 已删除 `RuntimeReadModelStore.markAppTerminated(...)` direct-call 同步剪枝兼容入口。P1 同轮补 docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface read API、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Remaining gaps: 真实 committed-index Search UI proof 与 topology pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 AX destroyed lifecycle/current-app projection cache 迁到主表生成：`RuntimeProjectionService.signalAXWindowDestroyed(...)` 先让 repair-provider 清理 destroyed AX attachment 与调度 `.axNotification` scoped repair，再用 `commitMainTableCurrentAppProjectionLocked(..., clearsDirtyState: false, ...)` 从清理后的 WindowRecord 主表预提交 current-app/Home detail projection cache。行为测试保留 legacy committed Search contamination，断言 projection window 来自主表 CG-stable record、context 不再暴露 destroyed AX window、freshness 仍是 dirty/incomplete，并且 Search readback 只能是 `degradedStaleCommittedResult` 的 last committed index。P1 同轮补 docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface read API、activation oracle、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Remaining gaps: 真实 committed-index Search UI proof、AX destroyed Home/UI proof 与 topology pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 activation verified-focus readback 后的 current-app/Home detail projection cache 迁到主表生成：`RuntimeProjectionService.signalWindowFocusVerified(...)` 先通过 repair-provider 把 focused AX/CG readback 写入 WindowRecord verified-focus evidence 并调度 activation-verified scoped repair，再用 `commitMainTableCurrentAppProjectionLocked(..., clearsDirtyState: false, ...)` 从 verified-focus 后的 WindowRecord 主表预提交 projection。行为测试保留 legacy committed Search contamination，断言 projection window 来自新 seeded CG-stable WindowRecord、context 携带 focused AX handle 与 `.verifiedFocusReadback` source、freshness 仍是 dirty/incomplete，并且 Search readback 只能是 `degradedStaleCommittedResult` 的 last committed index。P1 同轮补 docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为 activation success oracle、surface read API、Search barrier bound、sampling cadence 与 repeated hot-path cost 未改变。Remaining gaps: 真实 activation/Home UI proof、真实 committed-index Search UI proof 与 topology pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 Space topology signal 后的 app-switcher/Home summary projection cache 迁到主表生成：`RuntimeProjectionService.signalSpaceTopologyChanged()` 通过 repair-provider 收集 topology diff/signature evidence 并写入 read-model dirty/freshness metadata 后，会调用 `commitMainTableAppSwitcherProjectionLocked(..., requiresExistingProjectionCoverage: true)` 从 app directory + WindowRecord 主表预提交 projection。行为测试同时放入 legacy committed Search row、WindowRecord 主表 row 与 sampled CG row contamination，断言最终 projection window/title/space evidence 来自主表 WindowRecord，sampled CG title 不能穿过 normal projection，freshness 仍带 Space dirty/signature metadata，并且 Search readback 只能是 `degradedStaleCommittedResult` 的 last committed index。P1 同轮补 docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为真实 topology sampling cadence、surface read API、activation oracle、Search barrier bound 与 repeated hot-path cost 未改变。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 与系统权威 fullscreen owner 继续跟踪。
- Phase 6 本轮 P0 继续把 Home summary/detail read path 从 surface-local app-switcher derivation 收回 runtime read model：`HomeRuntimeProjectionReader.appSummaries(...)`、`initialAppSummaries(...)` 与 `appSummary(...)` 现在只读 `readHomeSummaryProjection()`，`HomeWindowActivationController` 缺 detail projection 时也只通过 Home summary projection 获取 PID 并发送 dirty signal，不再直接读取 app-switcher context。后续 Phase 6 已继续删除 runtime store 内部 app-switcher-to-Home-detail compatibility fallback；app-switcher-only contamination 会返回 missing Home projection/detail，而不是被命名为正常 Home summary/detail。P1 同轮调整既有 Home behavior tests 和 docs/matrix；P2 不新增 UI/E2E 或 pressure proof，因为 Home 可见流程、surface signal、sampling cadence、activation oracle、Search barrier bound 与 repeated hot-path cost 未改变。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续收紧 Home detail read-model source：`RuntimeReadModelStore.readHomeAppDetailProjection(appID:)` 现在只读取 `currentAppWindowProjectionsByAppID` 中的 current-app projection cache，不再从 `appSwitcherProjection` 或 directory-derived app-switcher projection 的 app/context 兼容组装 Home detail。app-switcher projection 仍可生成 Home summary rows，但 Home detail 必须由 current-app/Home-detail projection cache 提供；缺失时 surface 只能保留 current UI state 并发送 dirty/maintenance signal。Required behavior coverage: `testRuntimeReadModelStoreDoesNotDeriveHomeDetailFromAppSwitcherProjection` 证明 app-switcher context contamination 不能成为 Home detail，`testRuntimeReadModelStoreOwnsHomeDetailProjectionFromCurrentAppCache` 证明 current-app cache 仍是正式 detail source，`testRuntimeProjectionServiceCommitsAppWindowDirtyProjectionForHomeDetailFromMainTablesAsStale` 与 provider evidence tests 证明 dirty maintenance 可从 app directory + WindowRecord 主表补齐 current-app/Home-detail projection。Search 仍只能是 degraded/stale committed，不能因为 Home detail cache 可读而进入 fresh/complete/latest/current-generation committed。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。
- Phase 6 本轮 P0 继续把 app directory 从 repair/fallback helper 提升为 runtime maintenance fact source：新增 `RuntimeAppDirectoryProviding` / `RuntimeWorkspaceAppDirectoryProvider`，默认 `RuntimeProjectionService` 在 app-switcher maintenance 与 bounded Search freshness barrier 前先用 public `NSWorkspace.runningApplications` 过滤结果写入 `RuntimeReadModelStore.commitAppDirectoryProviderEvidence(...)`，再通过 `RuntimeMainTableProjectionBuilding.appSwitcherProjectionPayloadFromMainTables(...)` 从 app directory + WindowRecord 主表生成 app-switcher/Home projection cache。custom injected repair-provider 入口默认不启用 workspace provider，避免迁移测试/compat bridge 被隐式 running-app state 覆盖；需要长期 directory evidence 的 service path 必须显式注入 provider 或使用默认 production service。Required behavior coverage: `testRuntimeProjectionServiceCommitsAppDirectoryProviderProjectionFromMainTablesWithoutFullRepair` 证明没有 full-repair payload 时 provider evidence 可补齐 app directory，projection windows 来自 WindowRecord 主表且不启动 full repair；Search readback 仍是 last committed index 的 `degradedStaleCommittedResult`，即使 projection cache 已可读，也不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态，除非 bounded freshness barrier 成功提交新 generation。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 app-directory provider evidence 接入所有 runtime-owned dirty/projection maintenance：Space topology、app launch、app-window/current-app dirty、AX destroyed、app termination 与 verified-focus readback 在主表 projection build 前都会先刷新 `RuntimeAppDirectoryProviding` evidence。这样 current-app/Home detail projection 不再因为 legacy app-switcher cache 缺 directory evidence 而必须等待 scoped current-app repair evidence；`RuntimeMainTableProjectionBuilding.currentAppWindowPayloadFromMainTables(...)` 仍只读取 read-model app directory + WindowRecord 主表，provider 只负责维护长期 directory fact。Required behavior coverage: `testRuntimeProjectionServiceCommitsCurrentAppProjectionFromAppDirectoryProviderEvidence` 用无 app-directory evidence 的 legacy app-switcher/Search cache 作为 contamination，证明 app-window dirty signal 可通过 provider evidence + WindowRecord 主表提交 current-app/Home detail projection，started repair 不携带 projection rows，Search 仍读取 last committed `degradedStaleCommittedResult`，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续收紧 Home summary write ownership：`RuntimeReadModelStore.commitHomeSummaries(...)` 与 `commitHomeSummary(...)` direct write 入口已删除，Home summary projection 只能随 app-switcher/main-table projection commit 或 app-directory-derived read model 维护，不再有独立 Home-only committed projection path 可以清 dirty 并伪装 complete；后续 Phase 6 也删除了 current-app commit 对 Home summary 的同步 upsert。Required behavior coverage 复用 app-directory-derived Home summary、app-switcher/main-table Home summary、current-app/Home detail projection 与 Search stale regressions；编译同时证明 direct Home summary commit API 已不存在。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 Home surface call sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Search barrier 未提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续删除 production app-switcher direct write 入口：`RuntimeReadModelStore.commitAppSwitcherProjection(...)` 已移除，正常 app-switcher/Home summary cache 只能通过 `commitMainTableAppSwitcherProjectionPayload(...)` 写入；该 payload commit 不接收 app directory evidence，directory 只能先经 full/current/provider/lifecycle evidence 写入长期主表。FlowTabTests 中的 legacy projection/cache contamination 改为 `seedAppSwitcherProjectionForTesting(...)` test-only helper，该 helper 不属于 production normal path。Required behavior coverage 复用 app-switcher main-table projection、Home summary/detail、Search stale/barrier 与 read-model ownership regressions；编译证明 production direct API 已不存在。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface call sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Search barrier 未提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续收紧 current-app projection write ownership：`RuntimeReadModelStore.commitCurrentAppWindowProjection(...)` 不再把 `RuntimeCurrentAppWindowPayload.appDirectoryEntries` upsert 回 `RuntimeAppDirectoryState`，也不再同步 upsert app-switcher 或 Home summary projection cache。current-app commit 只维护 current-app/Home detail cache；app-switcher/Home summary 只能由主表 app-switcher payload commit 或 app-directory-derived read model 维护，app directory fact 只能先通过 full repair、current-app repair、workspace provider 或 lifecycle dirty signal 的显式 evidence API 进入长期主表。Required behavior coverage 扩展 `testRuntimeReadModelStoreOwnsHomeDetailProjectionFromCurrentAppCache`，证明 direct current-app projection payload 即使携带 directory entry 也不会创建 app directory、app-switcher 或 Home summary projection，同时复用 provider/current-app main-table 和 Search stale regressions；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Search barrier 未提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index，不能叫 fresh、complete、latest、current-generation committed 或最新完整搜索结果态。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 app termination read-model metadata mutation 收回 runtime maintenance queue：`RuntimeProjectionService.signalAppTerminated(...)` 不再在 caller thread 同步调用 `RuntimeReadModelStore.markAppTerminatedForMainTableProjection(...)`，而是把 metadata update、repair-provider cleanup、app-directory provider evidence 与 main-table app-switcher/Home rebuild 串在同一个 maintenance queue turn 中。surface / app delegate / model path 因此只提交 lifecycle dirty signal，不拥有 app directory/current-app/dirty metadata mutation timing。committed Search index 仍不被 termination metadata path 剪枝或刷新；如果 freshness barrier 没有成功提交覆盖当前 generation 的新 index，只能读 last committed `degradedStaleCommittedResult` 或 stale/missing committed state，不能叫 fresh、complete、latest/current-generation 或最新完整搜索结果。Required behavior coverage 复用 service termination projection/Search stale regression、store termination metadata regressions 与 model-level termination signal tests；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 app directory 主表 evidence 纳入 runtime generation ownership：`RuntimeReadModelStore.commitFullRepairAppDirectoryEvidence(...)`、`commitCurrentAppRepairAppDirectoryEvidence(...)` 与 `commitAppDirectoryProviderEvidence(...)` 会在 entries 实际变化或首次初始化 directory state 时推进 `appLifecycle` generation，重复相同 evidence 不推进 generation。`RuntimeProjectionService.requestSearchIndexFreshnessBarrier(...)` 同步调整为先提交 scoped current-app repair directory evidence，再生成 main-table app-switcher/Home projection cache，最后尝试 committed Search index；这样 projection cache sourceGeneration 能覆盖 repair evidence 更新后的 app directory generation。P1 同轮更新 coverage matrix；P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Search barrier 未成功提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index，不能叫 fresh、complete、latest/current-generation 或最新完整搜索结果。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续把 app directory rank/recency evidence 收回 Runtime 长期主表：`RuntimeAppDirectoryEntry` 现在携带 optional `activationRank`，workspace provider 与 full-repair running-app evidence 在 public running-app fact collection 时写入 rank；`RuntimeReadModelStore` 把 rank 纳入 app directory equality/generation，rank 改变推进 `appLifecycle` generation，重复相同 evidence 不推进 generation。app-directory-derived app-switcher/Home summary projection 与 main-table app-switcher/Home builder 现在从 stored entries 派生 `rankByPID`，用它选择 duplicate appID primary PID、排序 rows 与设置 stable recency，而不是在 normal projection path 传空 rank map 或退回字母序。Required behavior coverage: `testRuntimeMainTableProjectionBuilderUsesAppDirectoryActivationRank` 与 `testRuntimeReadModelStoreAppDirectoryProjectionUsesActivationRankEvidence` 通过 `run-flowtabtests-local.sh` targeted variation；Search 在未有/未过 freshness barrier 时仍只能是 missing committed index 或 degraded/stale committed result，不能把 rank/projection 更新命名为 fresh、complete、latest/current-generation 搜索结果。P2 不新增 UI/E2E 或 pressure proof，因为 surface sequence、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续删除 Home surface app-switcher fallback：`HomeRuntimeProjectionReader.shouldWaitForNoSwitchableWindowProjection(...)` 现在只读取 current-app projection 与 Home summary projection freshness，app-switcher-only contamination 不能再让 Home no-switchable-window 文案进入 wait-cache，也不会被 Home surface 读取。Home 缺 detail/summary 时仍只能保留当前 committed UI state、读 Home summary projection 定位 PID，或发送 shared runtime dirty/maintenance signal。Required behavior coverage 扩展 `testHomeRuntimeProjectionReaderDoesNotDeriveHomeDataFromAppSwitcherProjection`，证明 app-switcher projection 不参与 Home summary/detail/no-switchable wait 判断。P2 不新增 UI/E2E 或 pressure proof，因为 visible Home flow、surface signal、activation oracle、Search barrier bound、CG/AX/Space sampling cadence 与 repeated hot-path shape 未改变。Search barrier 未提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index。Remaining gaps: 真实 committed-index Search UI proof、真实 topology UI/pressure proof 继续跟踪。
- Phase 6 本轮 P0 继续删除 production Search session-app index source：`SwitcherSearchCoordinator.rebuildIndex(with:)` 现在只接受 `RuntimeSearchIndexProjection`，不再暴露 `[AppSwitchCandidate]`/session apps rebuild overload；`LiveSwitcherModel.resetSessionState()` 改为 `searchCoordinator.resetIndex()`，避免用空 session app list 伪造 Search index reset。FlowTabTests 的 coordinator rule/pressure coverage 通过 test-target `runtimeSearchIndexProjection(from:)` fixture 显式构造 committed-index projection，编译层证明生产 Search 不能再从 session apps/completeness 直接 rebuild index。P1 同轮更新 docs/matrix；P2 不新增 UI/E2E 或外部 pressure proof，因为 Search visible flow、activation oracle、bounded freshness barrier、CG/AX/Space sampling cadence 与 repeated query algorithm 未改变；targeted deterministic Search pressure 复跑通过。Search barrier 未提交新 generation 时仍只能暴露 degraded/stale committed result 或 missing committed index，不能命名为 fresh、complete、latest/current-generation。
- Space signature P0 已落到 deterministic model/diff、runtime diagnostic fields、read-model dirty affected-window metadata 与代表性 noisy fullscreen fixture UI signature proof；`scripts/perf/runtime-topology-pressure.sh` 已提供外部 CPU/RSS wrapper，非 sandbox 复跑通过 70 个 0.5s 样本（CPU avg/p95/max 29.37/59.50/84.70，RSS avg/p95/max 112.12/174.67/202.70MB）。首次 pressure wrapper 运行曾暴露 dirty app-switcher projection 可在 pending repair 未 ready 时把 5-window stale Chrome Fixture 列表当正常 window cycle 呈现，而 runtime `window-entries` 已修复回 4；当前 `RuntimeAppSwitcherProjection.appCycleApps` 已让 dirty app-switcher projection 在 app-cycle 热路径压制 stale window lists，行为回归测试先失败后通过，外部 wrapper 复跑也通过 70 个 0.5s 样本（CPU avg/p95/max 31.63/55.50/78.80，RSS avg/p95/max 118.34/180.17/207.23MB）。系统权威 fullscreen owner、多显示器 Space/window 视图仍需补齐。
- 更广 fullscreen Space 拓扑、多显示器组合、normal/fullscreen 往返仍需真实 UI/E2E proof。
- non-registry focused AX readback 的真实系统形态仍需 UI/E2E proof。
- focused/main/minimized public AX tie-breaker 仍需更广状态排列 proof。
- minimized tie-breaker、多显示器 fullscreen 组合、真实逐路径提交与非曝光证明仍需补覆盖。
