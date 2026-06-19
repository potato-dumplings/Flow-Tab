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
5. Search 读取持续维护且原子提交的 committed search index；进入 Search 时先做轻量 freshness validation，确认该 index 已覆盖最新 app lifecycle、CG、Space 与 AX dirty generation。若未覆盖，必须先完成 bounded freshness barrier 并提交新 generation；Search 不读取 repair 中间态，也不把旧索引或部分索引伪装成最新完整结果。
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

`snapshot()` 在目标形态中保留，但降级为：

- repair fallback
- migration compatibility
- diagnostic command
- cold start bootstrap 的最后兜底
- test fixture assembly helper

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
- `RuntimeReadModelStore.commitCurrentAppWindowProjection(_:)` 现在在同一 store transaction 内同步维护 current-app、app-switcher 与 Home summary projection，并从既有 Home/app-switcher projection 作为 base 后 upsert repaired summary；scoped repair payload 不再只刷新 window/detail 投影后让 Home summary 依赖 surface fallback 派生，也不会把单 app repair 暴露成完整 Home list。
- Space topology signal 现在通过 `collectCGWindowsWithSpaceTopologyDiff` 消费 provider 记录的 `RuntimeSpaceTopologyDiff`，并把 `affectedCGWindowIDs` 写入 `RuntimeReadModelStore` 的 dirty/freshness metadata；旧 `collectCGWindowsByPID` 只保留为兼容包装。
- provider repair payload 到 current-app projection payload 的转换由 `RuntimeCurrentAppWindowPayload` 类型拥有，`RuntimeProjectionService` 不再维护私有 snapshot/repair-shaped conversion helper。
- `RuntimeAppWindowRepairPayload` 现在拥有 app-window projection seed 到 Home summary、app-switcher candidate、`RuntimeAppContext` 的组装规则；provider 只把采样事实转换为 `RuntimeAppWindowProjectionSeed`，不再私有维护 candidate/context/summary projection assembly。

但当前实现仍有迁移对象：

- service 层 `RuntimeProjectionService.fallbackRuntimeSnapshot()` full snapshot bridge 与 concrete-only `fallbackLightweightAppSnapshot()` lightweight bridge 均已删除；`RuntimeProjectionServing` 已不再暴露 full snapshot bridge、同步 lightweight bridge 或 `currentCGWindowsByPID()` live CG z-order read，Switcher/Home 的 P0 首读路径已优先读取 projection，`Option+Tab` 缺 app-switcher projection 时只请求 shared runtime maintenance，不再同步调用 lightweight snapshot bridge；`Control+Tab` 缺 current-app projection 时只发送 runtime dirty/repair signal，不再同步调用 focused snapshot bridge。service-facing focused snapshot 兼容入口已删除，provider 内部 app-local reconciliation repair pullback 只返回 `RuntimeAppWindowRepairPayload`。
- `RuntimeSnapshotProvider.snapshot()` 仍会枚举 running apps 并进入 `collectWindowData(for:)`，其内部会取 onscreen/all CG 和 AX window data。该路径应降级为 repair/fallback。
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
- `RuntimeProjectionService` 成为 read model store owner；旧 provider 采样桥只负责生成兼容数据，service 负责提交 projection 或标脏 metadata。
- `RuntimeProjectionServing` 暴露 projection read seam：`readAppSwitcherProjection()`、`readHomeSummaryProjection()`、`readCurrentAppWindowProjection(appID:)` 与 `runtimeReadModelDiagnostics()`，供 Phase 2 迁移 hot-path read API。
- app/window dirty、app launch/termination、AX destroyed、Space topology、activation verified-focus signal 均会进入 store generation/dirty metadata，避免 Switcher、Home、Search 各自扩张 surface-local freshness state。

仍保留的 P1/P2：

- projection builders 仍由旧 snapshot/home/focused 兼容桥提交，尚未完全从底层 `RuntimeWindowRecord`、app directory、Space topology 主表独立 rebuild。
- Switcher/Home 首帧只读 projection 的 P0 已在 Phase 2 落地；旧采样桥仍作为 service-owned repair/fallback 兼容入口，不是目标热路径。
- Search committed/staging index 未在本阶段实现，必须等 store/generation seam 稳定后推进。

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
- Switcher terminate refresh 不再读取 full snapshot bridge；`RuntimeReadModelStore.markAppTerminated` 会同步从 committed app-switcher projection 和 committed search index 移除 terminated app，Switcher 只读取更新后的 projection，projection 缺失时只请求 shared runtime maintenance 并保留当前 session。Termination behavior tests now name their injected `RecordingRuntimeProjectionService` fixture `runtimeProjectionService`; full/lightweight snapshot counters remain old-path regression oracles.
- `RuntimeProjectionServing` 已不再向 feature surface 暴露泛化的 `snapshot()` 方法或 full snapshot bridge。`RuntimeSnapshotProvider.snapshot()` 仍保留为 provider 内部 full builder / repair primitive。
- `RuntimeProjectionServing` 已不再向 feature surface 暴露同步 `lightweightAppSnapshot()` 方法；`RuntimeProjectionService.fallbackLightweightAppSnapshot()` 和 provider `lightweightAppSnapshot()` 已删除，feature surface 只能读 app-switcher projection 或发送 runtime maintenance signal。
- `RuntimeProjectionServing` 已不再向 feature surface 暴露 Home provider-backed refresh bridge；Home summary/detail refresh 只能读取 Home/current-app projection 或 app-switcher projection，projection 缺失时返回当前 committed UI state 并发送 shared runtime maintenance/app-window dirty signal。
- selected/current app window refresh 只读取 `RuntimeCurrentAppWindowProjection`；projection 存在时不会调用 Home snapshot bridge，projection 缺失时只向 shared runtime 发送 app-window dirty signal 并保持 app-cycle 投影状态。
- Home window activation 使用调用方传入的 cached detail projection 或 `RuntimeCurrentAppWindowProjection` 构造 activation target；缺 projection 时只向 shared runtime 发送 app-window dirty signal，不再同步调用 Home snapshot bridge。
- 迁移期 `RuntimeProjectionServing.homeAppSnapshotSynchronously` 兼容入口已删除；生产 surface 无法再通过 shared runtime service 重新引入该同步 Home snapshot bridge。
- `Control+Tab` focused-current-app startup 只读取 `RuntimeCurrentAppWindowProjection`；projection 存在时不会调用 provider repair pullback，projection 缺失时只向 shared runtime 发送 app-window dirty signal 并降级退出。
- 迁移期 focused snapshot 兼容入口已从 `RuntimeProjectionServing` 删除；生产 surface 无法再通过 shared runtime service 重新引入该同步 focused snapshot bridge。
- `LiveSwitcherModel` startup recency 不再读取 live focused AX 或 live CG z-order；`Option+Tab` / `Control+Tab` 仅应用 committed `RuntimeWindowRecencyTracker` evidence 和 projection order，`RuntimeProjectionServing` 也不再向 feature surface 暴露 `currentCGWindowsByPID()`。
- Home initial summary projection、summary refresh、single-app summary、selected app detail 通过 `HomeRuntimeProjectionReader`/`HomeRuntimeRefreshReader` 读取 projection，Home refresh diagnostics 使用 `RuntimeLogCategory.projection`；projection 缺失时不再调用旧 Home snapshot service，concrete `RuntimeProjectionService` 的 provider-backed Home fallback bridge 已删除。
- Home activation / projection reader behavior tests now name their injected `RecordingRuntimeProjectionService` fixtures `runtimeProjectionService`; legacy Home/full/lightweight snapshot request counters remain only as old-path regression oracles.
- Preview paging/session-pinning/provider behavior tests now use the shared `makeAppSwitcherProjectionModel` helper with a `runtimeProjectionService` return label; legacy full/lightweight snapshot request counters remain old-path regression oracles rather than service ownership names.
- `RuntimeAppSwitcherProjection.appCycleApps` 与 `RuntimeHomeSummaryProjection.summary(for:)` 作为 shared projection helper，避免 surface 复制 app-cycle projection assembly 或 summary lookup 状态。

仍保留的 P1/P2：

- `readSearchWindowProjection()` 未在本阶段实现；Search 必须在 committed/staging index 阶段推进，不能成为第二个 runtime store。
- Switcher session-start background full snapshot 已在 Phase 3 P0 降级为 runtime-owned projection maintenance request；priority/coalescing/cancellation/backoff breadth 仍留给 Phase 3 P1/P2。
- 本阶段新增的是 behavior/pressure 证明；真实 UI/E2E 拓扑 proof 沿用既有 fixture 覆盖，未新增专门的 projection-read UI 断言。

验证：

- targeted unit/behavior 证明 hot read 不调用采样 provider。
- pressure proof 记录 `Option+Tab` / `Control+Tab` 首帧不被后台 maintenance 阻塞。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelStartsAppSessionFromRuntimeProjectionWithoutLightweightSampling` 证明 app switcher projection 存在时不会调用 lightweight snapshot 或 full snapshot bridge。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelSelectedAppWindowSnapshotUsesRuntimeProjectionWithoutHomeSampling` 证明 selected/current app window projection 存在时不会调用 Home snapshot bridge；`testLiveSwitcherModelSelectedAppWindowSnapshotSignalsRuntimeRepairWhenProjectionIsMissing` 证明 projection 缺失时即使旧 Home snapshot bridge 有污染数据也不会被读取，只会发送 shared runtime app-window dirty signal。
- `FlowTabTests.testHomeWindowActivationControllerUsesRuntimeProjectionWithoutHomeSnapshotBridge` 证明 Home window activation 可直接使用 runtime current-app window projection 提交 activation target 且不读取 Home snapshot bridge；`testHomeWindowActivationControllerSignalsRuntimeRepairWhenProjectionIsMissing` 证明 projection 缺失时即使旧 Home snapshot bridge 有污染数据也不会被读取，只会发送 shared runtime app-window dirty signal。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelFocusedWindowSessionUsesRuntimeProjectionWithoutFocusedSampling` 证明 `Control+Tab` focused-current-app projection 存在时不会调用 focused snapshot bridge；`testLiveSwitcherModelFocusedWindowSessionSignalsRuntimeRepairWhenProjectionIsMissing` 证明 projection 缺失时即使旧 focused snapshot bridge 有污染数据也不会被读取，只会发送 shared runtime app-window dirty signal。
- `FlowTabTests.testHomeRuntimeProjectionReaderUsesRuntimeProjectionsWithoutSnapshotBridge` 证明 Home summary/detail projection read 不调用 lightweight/home summary/home detail snapshot bridge；`testHomeRuntimeProjectionReaderDerivesHomeDataFromAppSwitcherProjectionWithoutSnapshotBridge` 证明 Home 可从 app-switcher projection 派生 summary/detail；`testHomeRuntimeRefreshReaderSignalsRuntimeRepairWhenProjectionIsMissingWithoutHomeFallback` 证明 projection 缺失时污染的 Home fallback 数据不会被读取，只发送 shared runtime maintenance/app-window dirty signal 并保留当前 committed UI state。
- `FlowTabPriorityCoverageTests.testRuntimeReadModelStoreRemovesTerminatedAppFromCommittedProjectionsAndSearch` 证明 terminated app lifecycle signal 由 `RuntimeReadModelStore` 幂等地同步剪掉 committed app-switcher projection 与 committed search index；`FlowTabTests.testHandleApplicationTerminatedRefreshesFromRuntimeProjectionWithoutFullSnapshot` 证明 Switcher termination refresh 只消费该 runtime projection，记录 runtime termination signal，并保持 full/lightweight snapshot call count 为 0。
- `FlowTabTests.testOptionTabWindowScalePressureKeepsSelectedAppApplyAndPreviewCaptureBounded` 本轮重跑通过，81 apps / 1,000 selected windows / 60 iterations 下 `selectedAppApplyP95=1.46ms`、`enterP95=0.03ms`、`previewItemsP95=0.35ms`、`previewCaptureCalls=360`。
- `FlowTabTests.testOptionTabFastStartPressureStaysUnderHundredMilliseconds` 与 `FlowTabTests.testOptionTabFastStartPressureIgnoresLargeFrontmostWindowSet` 本轮重跑通过，`fullSnapshotCalls=0`，p95 分别为 0.90ms 和 0.61ms。
- `FlowTabPriorityCoverageTests.testLiveSwitcherModelAppliesCommittedVerifiedFocusRecencyWithoutLiveFocusedRead`、`testLiveSwitcherModelFocusedRuntimeProjectionUsesCommittedRecencyBeforeOrdering` 和 `testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges` 证明 committed recency/projection order 已替代 startup live focused AX / live CG z-order sampling。
- `FlowTabTests.testControlTabFocusedProjectionFastStartPressureIgnoresFocusedSnapshotBridge` 证明 1,000-window current-app projection 下 `Control+Tab` focused startup p95 为 0.32ms，`snapshotCalls=0`。

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
- full repair 在 `RuntimeProjectionService` 的 drain/outcome 边界已改为 `RuntimeFullRepairProjectionPayload`，service 不再把 `RuntimeSnapshot` 作为 in-flight repair result 保存或提交；provider `snapshot()` full builder 只在默认 executor 内作为 repair primitive 立即转换为 projection payload。
- full repair snapshot 提交已分成 clean cold-start 与 dirty degraded fallback：只有没有 app-switcher projection 且没有 dirty/pending repair metadata 时才允许清 dirty 并生成 complete committed Search index；dirty/pending 状态下的 full repair 只能提交 degraded app-switcher projection，必须保留 dirty/freshness metadata、staging search index 和 last committed Search index，不能把 fallback 结果命名或暴露为 fresh/complete/latest。
- Search freshness barrier 的 promote/drain 明确排除 full repair fallback；barrier 只能完成 bounded scoped repair、由本轮 repaired payload 写入 staging，并提交新 generation 后进入最新搜索结果态。pending full repair 可能被后来的 high-priority scoped repair 取消，但不会被 Search 提升、执行或命名为 fresh/complete/latest。

仍保留的 P1/P2：

- full repair fallback 的 target / high-priority cancellation 已落到 scheduler；scoped repair retry exhausted 后会自动降级安排 low-priority full repair fallback，并且 dirty fallback commit 不会清 dirty 或刷新 committed Search。更广 backoff policy 与更细粒度 facts 拆分仍需扩展。
- service 层 feature-facing full snapshot fallback 已从 `RuntimeProjectionService` 删除；full repair outcome 现在也只携带 `RuntimeFullRepairProjectionPayload`。full builder 仍存在于 provider primitive `RuntimeSnapshotProvider.snapshot()`，性质是 low-priority repair/diagnostic、cold-start 或迁移兼容输入，不是 Switcher/Home/Search hot-path read API，也不是 Search freshness barrier 的成功 oracle。
- Search committed/staging index 已在 Phase 4 推进；真实 committed/staging UI proof 与外部 pressure proof 仍需补齐。
- 真实 UI/E2E 与多拓扑 pressure proof 本轮未新增；现有证明是 behavior + deterministic pressure。

验证：

- `FlowTabPriorityCoverageTests.testLiveSwitcherModelStartSessionRequestsRuntimeMaintenanceWithoutSurfaceSampling` 证明 app switcher projection 存在时，`startSession` 只请求 runtime maintenance，且不调用 full/lightweight snapshot bridge。
- `FlowTabTests.testLiveSwitcherModelMaintenanceDiagnosticTracksGenerationReasonWithoutApply` 证明 maintenance diagnostic 记录 generation/reason，`applyGeneration=nil`，不会把后台结果 apply 回 surface session。
- `FlowTabPriorityCoverageTests.testRuntimeReconciliationCoordinatorPromotesPriorityAndBypassesRetryBackoff` 证明 high-priority activation verified signal 可以提升已有 low-priority retry request，重置 attempt 并绕过 retry backoff。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceMaintenanceRequestDrainsReadyRequestsBySchedulerPriority` 证明 runtime maintenance drain 按 shared coordinator priority 执行 high-priority request，再执行 low-priority request。
- `FlowTabPriorityCoverageTests.testRuntimeReconciliationCoordinatorCancelsPendingFullRepairForHighPriorityScopedRepair` 证明 pending low-priority full repair fallback 会被后来的 high-priority scoped repair 取消。
- `FlowTabPriorityCoverageTests.testRuntimeReconciliationCoordinatorSchedulesFullRepairFallbackWhenRetryPolicyExhausts` 证明 scoped repair retry policy exhausted 时，coordinator 会移除失败 scoped request 并安排 low-priority full repair fallback。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceMaintenanceSchedulesLowPriorityFullRepairWhenProjectionMissing` 证明缺 app-switcher projection 且没有 scoped pending repair 时，runtime-owned maintenance 才会安排 low-priority full repair fallback 并提交 cold-start projection。
- `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceMaintenanceSchedulesLowPriorityFullRepairWhenProjectionMissing` 和 `testRuntimeProjectionServiceFullRepairFallbackCommitsDegradedProjectionWithoutRefreshingSearch` 的 injected executor 已改为返回 `RuntimeFullRepairProjectionPayload`，编译层证明 service-level full repair outcome 不再接受 `RuntimeSnapshot` result。
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
- Search 激活先做 freshness validation；若 committed index 未覆盖当前 app/CG/Space/AX dirty generation，则执行 bounded freshness barrier，成功提交新 generation 后再进入最新搜索。
- 当前迁移状态：Search 已改为读取 runtime-owned committed index；`RuntimeReadModelStore` 提供 `currentGenerationCommitted` / `staleCommitted` / `missingCommittedIndex` freshness read，并由 `RuntimeSearchIndexRead` 同步返回 surface 必须记录的 result state。`staleCommitted` 时仍返回 last committed index + dirty metadata，并由 `RuntimeProjectionService` 发起 bounded runtime maintenance drain。Search freshness barrier 会把 pending/waiting retry repair 提升为 high-priority `searchFreshnessBarrier` request，每次只 drain 固定数量的 ready scoped repair；只有 completed scoped repair 先写 internal staging、验证 coordinator 无未完成 repair、并原子提交新 committed generation 后，Search 才能进入 `verifiedCurrentGenerationCommittedResult`。completed request 若没有本轮 repaired payload，则不能借用历史 staging 提交新 committed generation。barrier 未提交、repair deferred、batch bound 后仍有 pending repair，或 retry exhausted 后执行 low-priority full repair fallback 但仍有 dirty metadata 时，当前行为必须暴露为 `degradedStaleCommittedResult` + dirty/freshness metadata，不回退到 session completeness、同步 full sampling，也不把该结果命名为 fresh/complete/latest。Search 行为测试的注入 fixture 也使用 `runtimeProjectionService` 命名；full/lightweight snapshot 计数只作为旧路径未被调用的 regression oracle。
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
- Search 只读原子提交的 committed search index；进入 Search 前完成 freshness validation，必要时完成 bounded freshness barrier 并提交新 generation。
- Home 读 summary/detail projection，不驱动 hotkey 全局采样。
- full snapshot 不再是 surface 主流程。
- AX notification 只作为 dirty/repair input，不作为唯一真相。
- Space topology 有 signature/diff/affected-window 闭环。
- activation 有 verified readback 写回。
- runtime logs 能证明真实 target `CGWindowID` 经过预期路径。
- required unit/behavior/UI/pressure proof 都按场景落地；未证明项留作 known gap。

## Known Gaps

当前文档目标下仍需显式保留这些 gap，直到代码和验证都闭环：

- hot-path read APIs 的 P0 已从 Switcher/Home 首屏采样队列中解耦；selected/current app window refresh 和 Home window activation 已移除缺 projection 时的 `homeAppSnapshotSynchronously` fallback，改为 dirty signal + projection-only 状态；Home initial app summary 已移除缺 projection 时的 `lightweightAppSnapshot()` 同步 fallback，Home initial/refresh diagnostics 也迁到 projection category；Home summary/detail refresh 已从 service-facing Home fallback bridge 迁移到 Home/current-app/app-switcher projection read + shared runtime maintenance signal；Switcher startup recency 已移除 live focused AX 与 live CG z-order read seam，改为 committed recency/projection order，且 `RuntimeWindowRecencyTracker` 不再暴露 Home snapshot-shaped recency helper；Switcher app-cycle hidden-app filtering 现在也作为 projection payload diagnostic 记录，不再占用 snapshot log category；Switcher termination refresh 已由 runtime store 同步剪枝 committed projection/search index，不再走 feature-facing full snapshot fallback；Search read model 已进入 runtime-owned committed index/freshness-read/committed-generation advance 边界，barrier 未提交时当前行为是 degraded/stale committed result 而不是 fresh/complete/latest，deterministic committed-index pressure 已证明 `LiveSwitcherModel` Search hot path 在 400 apps / 10,000 windows 下不调用 full/lightweight snapshot 且不请求 freshness barrier；真实 UI/E2E committed/staging proof 与外部 pressure proof 仍需补齐。
- `RuntimeReadModelStore` 与 projection cache 的 P0 边界已落地；Home surface state/API 已把 selected-app detail cache 和 API payload 类型迁移为 `RuntimeHomeAppDetailProjection`，不再把 projection read boundary 表达成 Home snapshot cache；app identity 规则已收敛到 runtime-owned `RuntimeAppIdentity`，AppDelegate lifecycle signal 与 Switcher focused-current-app projection read 不再向 `RuntimeSnapshotProvider` 查询 appID；provider repair 侧已拆成 `RuntimeAppWindowRepairPayload`，`RuntimeSnapshotProvider.appWindowRepairPayload(for:)` 也不再用 Home 命名暴露 app-window repair pullback，不再输出 Home snapshot-shaped payload；provider 兼容生成的 summary 入口也改为 `homeSummaryProjections()` / `homeSummaryProjection(for:)`，表达为 projection builder 兼容输出而非 Home snapshot bridge；承载这些 provider 兼容 projection/repair builders 的文件已命名为 `RuntimeSnapshotProvider+AppProjectionBuilders.swift`，不再保留 `HomeApps` 文件边界；repair payload 到 current-app projection payload 的转换已收敛到 `RuntimeCurrentAppWindowPayload`，full repair payload 已收敛到 `RuntimeFullRepairProjectionPayload`，而不是 `RuntimeProjectionService` 持有 `RuntimeSnapshot` result；app-window repair payload 自身也拥有 projection seed 到 summary/candidate/context 的 assembly，provider 只负责提供采样事实 seed；current-app repair payload 提交时会由 store 以既有 projection 为 base 同步 upsert current-app、app-switcher 与 Home summary projection；UI-test runtime dataset 也只维护 app-switcher projection seed、contexts、summaries 与 repair payloads，test launch option 内部 API 使用 projection 命名，full `RuntimeSnapshot` 包装只留在 provider `snapshot()` full-builder 兼容入口。仍需把 projection builders 从旧 snapshot/focused repair 兼容桥迁移到底层主表生成。
- Switcher session-start background full snapshot 已降级为 runtime-owned maintenance request；scheduler priority/coalescing/promoted-backoff P1 已落地，Search freshness barrier priority 与 selected/current app-window priority 已进入 runtime coordinator，full repair fallback target / low-priority scheduling / high-priority scoped cancellation / retry-exhaustion 自动降级已建模；dirty full repair fallback 现在只能提交 degraded projection，不能清 dirty 或刷新 committed Search。完整 full repair facts 拆分与更广 backoff policy 仍需补齐。
- search index 已从 session completeness 迁移到 committed runtime index read，并补齐 stale/dirty freshness read、bounded maintenance request、completed scoped repair 后 new committed generation 进入 verified current-generation committed result 的边界；repaired current-app projection payload 现在由 store-owned staging API 消费，barrier 未产生本轮 repaired payload、barrier 未提交或 dirty full repair fallback 执行后，当前 Search 行为记录为 degraded/stale committed result，而非 fresh/complete/latest。deterministic committed-index pressure 已覆盖 current-generation committed index 的 Search entry/query hot path，仍需补真实 committed/staging UI proof 与外部 pressure proof。
- Space signature P0 已落到 deterministic model/diff、runtime diagnostic fields、read-model dirty affected-window metadata 与代表性 noisy fullscreen fixture UI signature proof；`scripts/perf/runtime-topology-pressure.sh` 已提供外部 CPU/RSS wrapper，非 sandbox 复跑通过 70 个 0.5s 样本（CPU avg/p95/max 29.37/59.50/84.70，RSS avg/p95/max 112.12/174.67/202.70MB）。首次 pressure wrapper 运行曾暴露 dirty app-switcher projection 可在 pending repair 未 ready 时把 5-window stale Chrome Fixture 列表当正常 window cycle 呈现，而 runtime `window-entries` 已修复回 4；当前 `RuntimeAppSwitcherProjection.appCycleApps` 已让 dirty app-switcher projection 在 app-cycle 热路径压制 stale window lists，行为回归测试先失败后通过，外部 wrapper 复跑也通过 70 个 0.5s 样本（CPU avg/p95/max 31.63/55.50/78.80，RSS avg/p95/max 118.34/180.17/207.23MB）。系统权威 fullscreen owner、多显示器 Space/window 视图仍需补齐。
- 更广 fullscreen Space 拓扑、多显示器组合、normal/fullscreen 往返仍需真实 UI/E2E proof。
- non-registry focused AX readback 的真实系统形态仍需 UI/E2E proof。
- focused/main/minimized public AX tie-breaker 仍需更广状态排列 proof。
- minimized tie-breaker、多显示器 fullscreen 组合、真实逐路径提交与非曝光证明仍需补覆盖。
