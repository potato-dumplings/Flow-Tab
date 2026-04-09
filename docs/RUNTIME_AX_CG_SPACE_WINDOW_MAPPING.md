# Runtime AX/CG/Space Window Mapping

## 目标

- `window-layer` 只展示可切换、可恢复、可稳定维护的窗口条目，不暴露死条目或短暂幻觉。
- 构建阶段与维护阶段使用一致的对账管线，保证启动期与运行期行为一致。

## 实现模型概览

为实现上述目标，运行时模型围绕四件事展开：

1. 用 `CGWindowID` 维护长期稳定身份。
2. 用 `CG -> AX` 句柄承担“这次能不能切过去”。
3. 用 `CG -> Space` 关系回答“这个窗口当前能不能被找回到正确 Space”。
4. 用私有精确桥接或提交后的回读学习，把公开信息无法唯一确定的窗口重新拉回 exact binding。

概览上，运行时会把可恢复窗口理解为三类：

- `exact binding`: 当前已经唯一确认 `AX <-> CG` 对应关系，既知道“它是谁”，也有当前优先使用的 AX 激活句柄。
- `sticky binding`: 某个 `CGWindowID` 历史上曾被 exact 确认过；即使当前 AX attachment 暂时丢失，只要没有硬删除信号，仍保留这份长期绑定。
- `space-backed window`: 当前没有 AX exact，也没有历史 sticky binding，但已经确认 `CG -> Space` 关系，并且提交阶段仍有机会先切回目标 Space 再恢复 AX 激活。

## 角色划分

### `CGWindowID`

- 负责长期稳定身份。
- 是 sticky binding 的主锚点。
- 适合回答“这个窗口长期上是谁”。
- 是启动阶段最先建立的主记录。
- 不直接承担第三方窗口激活。

### `AXWindowID` 与 `AXUIElement`

- `AXWindowID` 只是当前快照下的索引键。
- `AXUIElement` 是当前提交时最优先的激活句柄。
- 适合回答“我现在能不能切它”。
- 不适合独自承担跨重排、跨全屏、跨恢复的长期身份。

### 私有 exact bridge

- 当前使用 `_AXUIElementGetWindow` 作为 `AX -> CG` 精确桥接。
- 只在公开路径无法形成唯一匹配时才触发。
- 只负责把当前 AX 句柄精确映射到 `CGWindowID`。
- 优先于继续扩大猜测匹配，不优先于已经成立的公开唯一匹配。
- 不负责替代整套公开匹配逻辑。

### `CG -> Space` 关系

- 是独立于 `AX <-> CG exact binding` 的恢复证据。
- 适合回答“当前没有 AX 时，这个 CG 窗口能不能先切回它所在的 Space”。
- 不等价于历史 sticky binding，但可以单独支撑提交阶段的恢复路径。
- 当 `AX` 暂时不可确认时，仍可让 `CGWindowID` 保持为可恢复条目，而不是直接丢弃。

### 私有窗口激活 fallback

- 只在用户明确提交某个窗口、且当前没有 AX 句柄时才考虑。
- 用于按 `CGWindowID` 激活目标窗口。
- 激活成功后必须立刻回读 AX 焦点窗口，并重新学习 exact binding。

## 基本原则

1. `AXWindowID` 不是长期稳定身份。
   当前实现里的 `AXWindowID` 只是快照索引键，不能作为跨快照长期主键。

2. sticky binding 必须以 `CGWindowID` 为主锚点维护。
   一旦某个窗口被精确确认，后续只要没有收到硬删除信号，就继续保留其历史绑定。

3. 公开信息优先，私有桥接其次。
   对当前 AX 窗口，先尝试用 focused/main、标题、frame、最小化状态等公开信息做唯一匹配；只有公开路径不能唯一确认时，才调用 `_AXUIElementGetWindow` 做精确桥接。

4. 被动快照阶段不能做有副作用的探测。
   任何会切前台窗口、切 Space、打断用户的私有激活，只能发生在明确的用户提交时。

5. 启动阶段先完成 `CG-first` 建模。
   启动或全量重建时，先以 `validCG` 建立主记录，再补 `AX <-> CG` 与 `CG -> Space` 关系；不能要求所有窗口先匹配到 AX 才算存在。

6. `window-layer` 不承载死条目。
   如果某个条目既不能通过当前 AX 激活，也没有历史 sticky binding、`CG -> Space` 关系或其他可确认的后续恢复路径，就不应进入主窗口切换路径。

7. 删除只接受强删除信号或连续缺席超时。
   当前可见于 AX 的窗口以 `AX destroyed` 为强删除或强降级信号；当前不在 AX 列表里的窗口以 `space evidence timeout` 为延迟删除信号；整个应用只在 `pid terminated` 时清空全部状态。

## 术语

- `AX Window`: 来自 Accessibility API 的窗口对象。
- `CG Window`: 来自 `CGWindowListCopyWindowInfo` 的窗口对象。
- `validCG`: 当前进程下满足有效性约束的 CG 窗口集合。
- `exact binding`: 已确认唯一的 `AX <-> CG` 绑定。
- `sticky binding`: 以 `CGWindowID` 为主键长期保留的 exact binding。
- `space-backed window`: 当前没有 AX exact，也没有历史 sticky binding，但已确认 `CG -> Space` 关系、并具备提交恢复路径的窗口条目。
- `current attachment`: 当前快照里 sticky binding 关联到的 AX 快照键。
- `unresolved AX`: 当前快照中尚未形成 exact binding 的 AX 窗口。
- `unresolved CG`: 当前快照中尚未形成 exact binding 的 CG 窗口。
- `exact bridge`: 能直接给出 `AX -> CG` 精确映射的能力，当前首选 `_AXUIElementGetWindow`。
- `private activation fallback`: 当当前没有 AX 句柄时，按 `CGWindowID` 激活窗口的私有兜底能力。
- `provisional CG-only`: 只有 CG 观测、尚未获得 AX、sticky 或 Space 证据的短期候选条目。

## 运行态数据

每个 `pid` 的运行态长期应收敛为一个 `CG-first` 主表和若干派生索引：

- `windowRecordsByCGID: [CGWindowID: WindowRecord]`
- `currentAXToCG: [AXWindowID: CGWindowID]`
- `currentCGToAX: [CGWindowID: AXWindowID]`
- `validCGIDs: Set<CGWindowID>`
- `lastAXIDs: Set<AXWindowID>`
- `currentSpaceSnapshot: SpaceSnapshot`

其中 `WindowRecord` 至少需要包含：

- `cgWindowID`
- `stableWindowID`
- `lastKnownCGTitle`
- `lastKnownCGFrame`
- `currentAXAttachment`
- `lastExactAXWindowID`
- `lastConfirmationSource`
- `lastExactConfirmedAt`
- `spaceRecovery`
- `firstSeenAt`
- `lastSeenAt`
- `suspectDeletedAt`

其中 `SpaceRecoveryState` 至少需要包含：

- `cgWindowID`
- `spaceIDs`
- `hasConfirmedActivationRoute`
- `lastValidatedAt`
- `invalidatedAt`

其中 `SpaceSnapshot` 至少需要包含：

- `currentSpaceIDByDisplay`
- `spacesByID`
- `windowIDsBySpaceID`
- `spaceIDsByCGWindowID`
- `fullscreenWindowIDBySpaceID`

约束如下：

- `CGWindowID` 是 `WindowRecord` 的主键，也是长期唯一真相层。
- `AXWindowID` 只服务于当前快照和短周期增量，不承担长期身份。
- `currentAXToCG/currentCGToAX` 代表当前快照视图，是 `WindowRecord` 的派生索引。
- `spaceRecovery` 是 `WindowRecord` 的一个字段，而不是与 `WindowRecord` 并列的第二份真相。
- 旧的 `stickyBindingsByCGID` 与 `spaceRecoveryByCGID` 若仍存在实现层投影，应被视为 `windowRecordsByCGID` 的投影，而不是独立主数据。

## `SpaceSnapshot`

`CG -> Space` 不应只表现为一条临时查询结果，而应维护成一份可 diff 的快照。

推荐的快照来源与职责如下：

1. 通过 `CGSCopyManagedDisplaySpaces` 获取按 display 分组的 Space 拓扑。
2. 通过 `CGSCopySpacesForWindows` 或 `SLSCopySpacesForWindows` 获取 `cgWindowID -> [spaceID]` 关系。
3. 将两者合并成 `SpaceSnapshot`，供运行态 diff 与恢复路径判断使用。

`SpaceSnapshot` 的职责不是直接替代 `WindowRecord`，而是回答三件事：

1. 当前系统里有哪些 `spaceID`。
2. 某个 `CGWindowID` 当前属于哪些 `spaceID`。
3. 某个 `spaceID` 的窗口集合或 fullscreen 归属是否发生了拓扑变化。

每次生成新快照后，都应与上一份快照做 diff。diff 至少需要产出：

- `removedSpaceIDs`
- `addedSpaceIDs`
- `changedSpaceIDs`
- `affectedCGWindowIDs`

这些 diff 结果不直接删除窗口条目，而是把相关 `WindowRecord` 标记为 `needsReconciliation`。

## 统一绑定管线

构建阶段与维护阶段共用同一条绑定管线。差别只在于什么时候触发、以及遇到硬删除信号时如何清理。

对单个 `pid` 的一次绑定处理，按以下顺序执行：

1. 枚举当前 AX 可切换窗口列表。
2. 枚举当前 CG 窗口列表，并过滤得到 `validCG`。
3. 对每个 `validCG` 先建立 `CG-first` 主记录，并尽可能补 `CG -> Space` 恢复状态。
4. 对每个当前 AX 窗口，先尝试使用 focused/main、标题、frame、最小化状态等公开信息做唯一匹配。
5. 若公开路径能形成唯一匹配，则建立 exact binding，并写入或刷新 sticky binding。
6. 若公开路径仍不能唯一确认，则调用 `_AXUIElementGetWindow` 做 `AX -> CG` 精确桥接。
7. 若私有 exact bridge 成功，且返回的 `CGWindowID` 属于 `validCG`，则建立 exact binding，并写入或刷新 sticky binding。
8. 对仍 unresolved 的新窗口，不做猜测性长期绑定；若其具备 `CG -> Space` 恢复证据，则保留为 `space-backed window`，否则仅保留为 `provisional CG-only` 候选。
9. 对仍 unresolved 但已存在历史 sticky binding 的 `CGWindowID`，只要没有收到硬删除信号，就继续保留该 sticky binding。
10. 保存 `windowRecordsByCGID`、`currentAXToCG`、`currentCGToAX`、`validCGIDs`、`lastAXIDs` 与 `currentSpaceSnapshot`。

这条管线表达的是两个关键政策：

- 无法唯一确认时，不扩大猜测匹配。
- 一次快照重新变歧义，不等于历史 sticky binding 被证伪。
- `CG -> Space` 是独立证据层，不应因为暂时没有 AX exact 就被忽略。

## 状态转换

运行时窗口状态应从 `WindowRecord` 派生，而不是维护四套并列主数据。推荐的派生状态与转换如下：

1. `provisional -> exact`
   当公开唯一匹配或私有 exact bridge 成功时，建立 `AX <-> CG exact binding`。
2. `provisional -> space-backed`
   当当前没有 AX exact，但 `CG -> Space` 已确认且存在提交恢复路径时，升级为 `space-backed`。
3. `exact -> sticky`
   当当前 AX attachment 丢失，但历史 exact 仍成立且没有硬删除信号时，降级为 `sticky`。
4. `sticky -> exact`
   当后续 reconciliation 重新恢复 AX exact 时，回到 `exact`。
5. `space-backed -> exact`
   当切回目标 Space 或后续快照使 AX 恢复时，升级为 `exact`。
6. `space-backed -> provisional`
   当 `CG -> Space` 恢复证据失效，但 `CGWindowID` 仍然存在于 `validCG` 中时，暂时降级为 `provisional`。
7. `provisional -> deleted`
   当该条目在 grace window 内持续缺席于 AX、CG、Space 三类证据时，才真正删除。
8. `sticky/space-backed -> deleted`
   仅在命中强删除信号，或在 grace window 内确认 AX、CG、Space 三类证据持续缺席时发生。

## 构建阶段

构建阶段包括应用启动后的首次建模，以及需要对某个 `pid` 做全量重建的场景。

### 启动或全量重建

1. 对每个 `pid` 执行一次统一绑定管线。
2. 启动阶段先以 `validCG` 建立主记录，再补 `AX <-> CG` 与 `CG -> Space` 关系。
3. 当前快照能重新确认的窗口，直接恢复 exact binding。
4. 当前快照暂时无法重新确认，但历史 sticky binding 仍在、且未收到硬删除信号的窗口，继续保留 sticky binding。
5. 当前没有 AX exact、但 `CG -> Space` 已确认且提交阶段存在恢复路径的窗口，保留为 `space-backed window`。
6. 对首次出现且无法唯一确认的新窗口，不建立猜测性长期绑定；若仍没有 Space 或其他恢复证据，只保留为短期 `provisional CG-only` 候选。
7. 只有在没有 AX exact、没有历史 sticky binding、没有 `CG -> Space` 关系、也没有其他已确认恢复路径，且超出 `provisional` 的 grace window 后，条目才真正丢弃。

构建阶段的核心目标不是“把所有窗口都展示出来”，而是“给主窗口切换路径输出可提交的条目”。

## 维护阶段

维护阶段与构建阶段属于同一类型，都在执行同一条绑定管线，只是触发入口来自 AX 增量事件或进程生命周期事件。

### AX 通知语义与局部刷新

AX 通知应被视为“某个应用发生了变化”的脏信号，而不是最终窗口真相。运行时策略应满足以下约束：

1. 通知粒度至少要定位到 `pid` 或 `appID`，并且只刷新受影响应用的数据，不把单应用事件升级为全量应用重建。
2. 通知载荷通常不提供完整窗口增量，不足以直接维护最终状态；收到通知后仍需对该应用回拉一次当前 `AXWindows` 快照并重新跑 reconciliation。
3. 在同一次事件序列中，`AXWindows` 可能短暂返回空数组再恢复，因此“通知到达”与“最终窗口集合稳定”不是同一时刻。

实践上，运行日志中出现 `rawWindows=0` 并不自动等价于“该应用当前没有可切换窗口”；最终展示应以 reconciliation 结果为准。

### 普通维护事件

以下事件都应重新跑一次统一绑定管线，或对受影响窗口做局部等价处理：

- `AX created`
- `focused`
- `main`
- `minimized`
- `deminiaturized`

维护策略如下：

1. 先尝试公开唯一匹配。
2. 公开路径无法唯一确认时，再尝试私有 exact bridge。
3. 若形成 exact binding，立即刷新 sticky binding 的标题、frame 和当前 attachment。
4. 若仍无法确认，则保持 unresolved，不做猜测性长期绑定；若存在 `CG -> Space` 恢复证据，则保留为 `space-backed window`。
5. 这类事件默认只修复和增强绑定，不主动解绑历史 sticky binding。

### 通知后 `AXWindows` 拉空

当通知已到达，但对该应用回拉 `AXWindows` 得到空结果时，默认按“瞬时空窗”处理，而不是直接删窗：

1. 先保留该应用已有的 `sticky` 与 `space-backed` 记录，只把当前 `exact` attachment 视为暂时缺席。
2. 以该应用为粒度做短间隔重试（例如 `100ms / 300ms / 800ms`），每次重试仍走同一条绑定管线。
3. 重试窗口期间，允许 `rawWindows=0` 与 `switchableWindows>0` 并存；这是“AX 瞬时缺席 + sticky/CG/Space 兜底”状态，不是异常。
4. 只有在 grace window 内连续多次 reconciliation 都缺席于 AX、CG、Space 三类证据时，才进入真正删除流程。
5. 进程退出(`pid terminated`)仍是唯一允许立即清空该应用全部记录的最强信号。

该策略的目标是避免把 AX 树重建期间的短暂空返回误判为“窗口已消失”。

### 通知路径与首页稳定行为对齐

通知维护路径应尽量向首页首次打开时的“稳定优先”行为对齐，避免业务结果直接暴露 AX 瞬时抖动：

1. 通知只负责标记受影响 `pid/appID` 为 `dirty`，不应在回调边缘直接提交“空窗口结果”。
2. 对 `dirty` 应用走统一的去抖刷新窗口；若首次回拉 `rawWindows=0`，应在短重试窗口内继续回拉，而不是立刻覆盖为 0 窗口状态。
3. 在重试窗口内，如果历史快照已有可提交窗口，应优先保留历史快照（`sticky`、`space-backed` 与可确认 `CG` 证据），直到获得新的稳定快照或命中删除条件。
4. 只有在 grace window 内连续多次 reconciliation 都缺席于 AX、CG、Space 三类证据时，才允许把该应用窗口状态提交为空。

这意味着运行日志允许出现瞬时 `rawWindows=0`，但 UI 与提交路径应继续保持“稳定可切换”输出。

### `space topology changed`

以下情况都应被视为 Space 拓扑变化，而不是窗口删除信号：

- `NSWorkspace.activeSpaceDidChangeNotification`
- `SpaceSnapshot` diff 中出现 `removedSpaceIDs`
- `SpaceSnapshot` diff 中出现 `changedSpaceIDs`
- fullscreen Space 关闭、迁移或回落到普通桌面

维护策略如下：

1. 刷新整份 `SpaceSnapshot`。
2. 计算 `affectedCGWindowIDs`，并把相关 `WindowRecord` 标记为 `needsReconciliation`。
3. 若某个 `spaceID` 消失，只失效对应的 `spaceRecovery`，不直接删除 `WindowRecord`。
4. 立即对 `affectedCGWindowIDs` 重新跑 reconciliation。
5. reconciliation 后只允许以下结果：
   - 窗口重新进入 AX，升级为 `exact`
   - 窗口仍有 `CG -> Space` 关系，保留为 `space-backed`
   - 窗口只剩 `validCG`，降为 `provisional`
   - 窗口同时失去 AX、CG、Space 三类证据，进入 `suspectDeleted` 与 grace window

### 硬删除维护事件

#### `AX destroyed`

1. 找到被移除 AX 对应的当前快照键。
2. 若其当前关联到某个 `WindowRecord`，先移除当前 AX attachment。
3. 若该记录仍有历史 exact，则降级为 `sticky`，而不是立刻删除。
4. 删除当前快照里的 `currentAXToCG/currentCGToAX` 关联。
5. 刷新 `validCG`，并立即跑一次 reconciliation。

#### `pid terminated`

1. 清空该 `pid` 下全部 `WindowRecord`。
2. 清空 `currentAXToCG/currentCGToAX`。
3. 清空 `validCGIDs/lastAXIDs`。
4. 清空与该 `pid` 关联的 `SpaceSnapshot` 投影与恢复状态。

#### `space evidence timeout`

这类事件专门处理“当前本来就不在 AX 列表里”的 `space-backed` 或 `provisional` 窗口。

1. 若某个 `WindowRecord` 当前没有 AX attachment，且不在 `validCGIDs` 中，也不在 `currentSpaceSnapshot.spaceIDsByCGWindowID` 中，则标记 `suspectDeletedAt`。
2. 若该条目在后续 reconciliation 中重新出现在 AX、CG 或 Space 任一证据层里，清除 `suspectDeletedAt`，恢复正常状态。
3. 只有当该条目连续 `2` 到 `3` 次 reconciliation 都缺席，或超过建议的 `500ms` 到 `1500ms` grace window，才真正删除该 `WindowRecord`。
4. 对于 fullscreen Space 关闭后的窗口：
   - 若窗口回到普通桌面并重新进入 AX，应在 grace window 内升级回 `exact`
   - 若窗口直接关闭，应在 grace window 内连续缺席后删除

## 删除信号优先级

删除窗口记录时，信号强度按以下优先级处理：

1. `pid terminated`
   最强删除信号，可立即清空该应用下全部记录。
2. `AX destroyed`
   只对当前可见于 AX 的 `exact/sticky` 记录构成强删除或强降级信号。
3. `space topology changed`
   不是删除信号，只能失效 `spaceRecovery` 并触发 reconciliation。
4. `space evidence timeout`
   只对当前不在 AX 列表里的 `space-backed/provisional` 记录构成延迟删除信号。

## `window-layer` 输出规则

对每个应用的窗口输出按以下规则构建：

1. 先输出当前存在 AX 句柄、且已形成 exact binding 的条目。
2. 再输出 sticky binding 仍有效、虽然当前暂时没有 AX，但已知提交阶段存在恢复路径的 CG-backed 条目。
3. 再输出没有历史 sticky binding、但 `CG -> Space` 已确认且具备提交恢复路径的 `space-backed window`。
4. 对仅有 CG 信息、且没有历史 sticky binding、也没有 `CG -> Space` 或其他已确认提交路径的新 `provisional CG-only` 条目，不进入主窗口切换路径，只保留在内部候选池。
5. 对既不能切换、也不能稳定展示的死条目，只允许进入诊断或调试视图，不进入主 `window-layer`。

这条规则的目标是：

- 不把死条目暴露给用户。
- 不因为一次歧义快照就让原本可切换的窗口消失。
- 不因为启动时暂时匹配不上 AX 就把仍可通过 Space 找回的窗口直接丢掉。
- 让主窗口切换路径始终服务于“可切换可展示”。

## 提交流程

用户在 `window-layer` 提交某个窗口时，按以下顺序执行：

1. 若条目有当前 AX 句柄，优先走 AX 激活。
2. 若条目没有当前 AX 句柄，先尝试基于当前 sticky binding 和当前快照重跑公开 AX 恢复路径。
3. 若公开恢复成功，回到 AX 激活路径。
4. 若公开恢复失败，但条目存在 `CG -> Space` 恢复路径，则先切到目标 Space。
5. 切到目标 Space 后，立刻重跑 AX 恢复路径；若恢复成功，回到 AX 激活路径。
6. 若仍未恢复 AX，但条目支持私有窗口激活 fallback，则按 `CGWindowID` 做私有激活。
7. 私有激活成功后，立刻回读 `AXFocusedWindow` 或等价焦点窗口。
8. 对回读到的 AX 窗口再次调用 `_AXUIElementGetWindow`，重新确认 exact binding，并刷新 sticky binding。
9. 若提交失败，则保留已有 sticky binding 或 `CG -> Space` 恢复状态，不因单次提交失败解绑。

## 不会触发解绑的情况

以下情况都不应主动解绑 sticky binding：

- 某次全量重建时重新证明失败。
- CG 临时没扫到。
- 某个 `spaceID` 在一次拓扑变化后消失。
- 标题变化。
- frame 变化。
- 当前没有 AX 句柄。
- 快照顺序变化。

原因很简单：

- 这些都可能只是观测不足。
- 它们不是窗口已经被硬删除的证据。
- `spaceID` 变化或消失只会失效恢复路径，不会单独构成删除 `CGWindowID` 主记录的证据。

## 边界与限制

1. 若某个窗口首次出现时就处于“无历史、标题完全一致、几何完全一致、AX 不可区分、私有 exact bridge 不可用”的状态，仅靠公开 API 无法精确确定它。
2. 若私有窗口激活能力在某个 macOS 版本不可用，则该类极小概率首次歧义场景仍可能无法首轮精确学习。
3. 私有 API 存在系统兼容性与上架风险，应通过独立 wrapper 与运行时符号探测隔离。
4. 任何被动快照流程都不得通过激活窗口来“试探绑定”，避免对用户造成可见副作用。

## 实现检查清单

- sticky binding 以 `CGWindowID` 为主键，而不是以 `AXWindowID` 为主键。
- 启动阶段先建立 `CG-first` 主记录，再补 AX 与 Space 关系。
- `windowRecordsByCGID` 是唯一主表，AX、CG、Space 的缓存都是它的字段或派生索引。
- `SpaceSnapshot` 是可 diff 的运行态快照，而不是一次性查询结果。
- 构建阶段与维护阶段共用同一条绑定管线。
- 公开唯一匹配优先于私有 exact bridge。
- `_AXUIElementGetWindow` 已被封装为独立私有 bridge。
- `CG -> Space` 被视为独立证据层，而不是 sticky binding 的附属条件。
- `space topology changed` 只触发 reconciliation，不直接触发窗口删除。
- 对当前不在 AX 列表里的窗口，删除条件依赖 `space evidence timeout`，而不是 `AX destroyed`。
- 当前 AX attachment 的解绑以 `AX destroyed` 为强信号；当前不在 AX 列表里的窗口删除依赖 `space evidence timeout`。
- 整个 `pid` 的状态清理仅发生在进程退出。
- 一次重建失败、CG 暂时缺席、标题变化、frame 变化，都不会主动解绑 sticky binding。
- AX 通知只作为脏信号；通知后以受影响 `pid/appID` 做局部回拉与 reconciliation，若 `AXWindows` 瞬时为空，先重试并保留 sticky/space-backed，不做立即删除。
- 通知维护路径与首页稳定策略保持一致：先去抖与重试，再决定是否提交空窗口状态。
- `window-layer` 采用 exact、sticky、space-backed、provisional 四层判断，只展示可提交的窗口条目，不展示无法激活的死条目。
