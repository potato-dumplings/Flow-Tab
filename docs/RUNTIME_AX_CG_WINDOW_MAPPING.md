# Runtime AX/CG Window Mapping

## 目标

统一 FlowTab 在运行时对 AX 窗口与 CG 窗口的关联策略，确保以下行为稳定：

- `window-layer` 以“可切换可展示”为第一优先，而不是“只能展示或只能切换”。
- 已确认的窗口级 `exact binding` 在后续快照变歧义时继续保留，不因一次重建被整体抹掉。
- 公开 API 能解决的问题优先用公开能力解决；当公开信息不足以唯一确认时，再使用小范围私有 API 做精确桥接。
- 构建阶段与维护阶段走同一条绑定管线，只是在触发入口与清理动作上不同。

## 一句话结论

运行时窗口绑定围绕三件事展开：

1. 用 `CGWindowID` 维护长期稳定身份。
2. 用当前 AX 句柄承担“这次能不能切过去”。
3. 用私有精确桥接或提交后的回读学习，把公开信息无法唯一确定的窗口重新拉回 exact binding。

## 角色划分

### `CGWindowID`

- 负责长期稳定身份。
- 是 sticky binding 的主锚点。
- 适合回答“这个窗口长期上是谁”。
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

5. `window-layer` 不承载死条目。
   如果某个条目既不能通过当前 AX 激活，也没有可确认的后续恢复路径，就不应进入主窗口切换路径。

6. 解绑只接受硬删除信号。
   单窗口只在 AX 销毁时解绑；整个应用只在 `pid terminated` 时清空全部状态。

## 术语

- `AX Window`: 来自 Accessibility API 的窗口对象。
- `CG Window`: 来自 `CGWindowListCopyWindowInfo` 的窗口对象。
- `validCG`: 当前进程下满足有效性约束的 CG 窗口集合。
- `exact binding`: 已确认唯一的 `AX <-> CG` 绑定。
- `sticky binding`: 以 `CGWindowID` 为主键长期保留的 exact binding。
- `current attachment`: 当前快照里 sticky binding 关联到的 AX 快照键。
- `unresolved AX`: 当前快照中尚未形成 exact binding 的 AX 窗口。
- `unresolved CG`: 当前快照中尚未形成 exact binding 的 CG 窗口。
- `exact bridge`: 能直接给出 `AX -> CG` 精确映射的能力，当前首选 `_AXUIElementGetWindow`。
- `private activation fallback`: 当当前没有 AX 句柄时，按 `CGWindowID` 激活窗口的私有兜底能力。

## 运行态数据

每个 `pid` 维护以下运行态缓存：

- `stickyBindingsByCGID: [CGWindowID: StickyBinding]`
- `currentAXToCG: [AXWindowID: CGWindowID]`
- `currentCGToAX: [CGWindowID: AXWindowID]`
- `validCGIDs: Set<CGWindowID>`
- `lastAXIDs: Set<AXWindowID>`

其中 `StickyBinding` 至少需要包含：

- `cgWindowID`
- `lastKnownAXWindowID`
- `lastKnownTitle`
- `lastKnownFrame`
- `lastConfirmationSource`
- `hasCurrentAXAttachment`

约束如下：

- `CGWindowID` 是 sticky binding 的主键。
- `AXWindowID` 只服务于当前快照和短周期增量，不承担长期身份。
- `currentAXToCG/currentCGToAX` 代表当前快照视图。
- `stickyBindingsByCGID` 代表跨快照保留的历史真相层。

## 统一绑定管线

构建阶段与维护阶段共用同一条绑定管线。差别只在于什么时候触发、以及遇到硬删除信号时如何清理。

对单个 `pid` 的一次绑定处理，按以下顺序执行：

1. 枚举当前 AX 可切换窗口列表。
2. 枚举当前 CG 窗口列表，并过滤得到 `validCG`。
3. 对每个当前 AX 窗口，先尝试使用 focused/main、标题、frame、最小化状态等公开信息做唯一匹配。
4. 若公开路径能形成唯一匹配，则建立 exact binding，并写入或刷新 sticky binding。
5. 若公开路径仍不能唯一确认，则调用 `_AXUIElementGetWindow` 做 `AX -> CG` 精确桥接。
6. 若私有 exact bridge 成功，且返回的 `CGWindowID` 属于 `validCG`，则建立 exact binding，并写入或刷新 sticky binding。
7. 对仍 unresolved 的新窗口，不做猜测性长期绑定，也不放进主 `window-layer`。
8. 对仍 unresolved 但已存在历史 sticky binding 的 `CGWindowID`，只要没有收到硬删除信号，就继续保留该 sticky binding。
9. 保存 `stickyBindingsByCGID`、`currentAXToCG`、`currentCGToAX`、`validCGIDs`、`lastAXIDs`。

这条管线表达的是两个关键政策：

- 无法唯一确认时，不扩大猜测匹配。
- 一次快照重新变歧义，不等于历史 sticky binding 被证伪。

## 构建阶段

构建阶段包括应用启动后的首次建模，以及需要对某个 `pid` 做全量重建的场景。

### 启动或全量重建

1. 对每个 `pid` 执行一次统一绑定管线。
2. 当前快照能重新确认的窗口，直接恢复 exact binding。
3. 当前快照暂时无法重新确认，但历史 sticky binding 仍在、且未收到硬删除信号的窗口，继续保留 sticky binding。
4. 对首次出现且无法唯一确认的新窗口，不建立猜测性长期绑定。
5. 无法匹配且没有提交路径的条目直接丢弃，避免只展示不能切换，或只能切换却无法稳定展示。

构建阶段的核心目标不是“把所有窗口都展示出来”，而是“给主窗口切换路径输出可提交的条目”。

## 维护阶段

维护阶段与构建阶段属于同一类型，都在执行同一条绑定管线，只是触发入口来自 AX 增量事件或进程生命周期事件。

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
4. 若仍无法确认，则保持 unresolved，不做猜测性长期绑定。
5. 这类事件默认只修复和增强绑定，不主动解绑历史 sticky binding。

### 硬删除维护事件

#### `AX destroyed`

1. 找到被移除 AX 对应的当前快照键。
2. 若其当前关联到某个 sticky binding，则解绑该 `CGWindowID`。
3. 删除该窗口的 sticky binding。
4. 删除当前快照里的 `currentAXToCG/currentCGToAX` 关联。
5. 刷新 `validCG`，移除当前失效的 CG 条目。

#### `pid terminated`

1. 清空该 `pid` 下全部 sticky binding。
2. 清空 `currentAXToCG/currentCGToAX`。
3. 清空 `validCGIDs/lastAXIDs`。

## `window-layer` 输出规则

对每个应用的窗口输出按以下规则构建：

1. 先输出当前存在 AX 句柄、且已形成 exact binding 的条目。
2. 再输出 sticky binding 仍有效、虽然当前暂时没有 AX，但已知提交阶段存在恢复路径的 CG-backed 条目。
3. 对仅有 CG 信息、且没有历史 sticky binding、也没有已确认提交路径的新 unresolved 条目，不进入主窗口切换路径。
4. 对既不能切换、也不能稳定展示的死条目，只允许进入诊断或调试视图，不进入主 `window-layer`。

这条规则的目标是：

- 不把死条目暴露给用户。
- 不因为一次歧义快照就让原本可切换的窗口消失。
- 让主窗口切换路径始终服务于“可切换可展示”。

## 提交流程

用户在 `window-layer` 提交某个窗口时，按以下顺序执行：

1. 若条目有当前 AX 句柄，优先走 AX 激活。
2. 若条目没有当前 AX 句柄，先尝试基于当前 sticky binding 和当前快照重跑公开 AX 恢复路径。
3. 若公开恢复成功，回到 AX 激活路径。
4. 若公开恢复失败，但条目支持私有窗口激活 fallback，则按 `CGWindowID` 做私有激活。
5. 私有激活成功后，立刻回读 `AXFocusedWindow` 或等价焦点窗口。
6. 对回读到的 AX 窗口再次调用 `_AXUIElementGetWindow`，重新确认 exact binding，并刷新 sticky binding。
7. 若提交失败，则保留已有 sticky binding，不因单次提交失败解绑。

## 不会触发解绑的情况

以下情况都不应主动解绑 sticky binding：

- 某次全量重建时重新证明失败。
- CG 临时没扫到。
- 标题变化。
- frame 变化。
- 当前没有 AX 句柄。
- 快照顺序变化。

原因很简单：

- 这些都可能只是观测不足。
- 它们不是窗口已经被硬删除的证据。

## 边界与限制

1. 若某个窗口首次出现时就处于“无历史、标题完全一致、几何完全一致、AX 不可区分、私有 exact bridge 不可用”的状态，仅靠公开 API 无法精确确定它。
2. 若私有窗口激活能力在某个 macOS 版本不可用，则该类极小概率首次歧义场景仍可能无法首轮精确学习。
3. 私有 API 存在系统兼容性与上架风险，应通过独立 wrapper 与运行时符号探测隔离。
4. 任何被动快照流程都不得通过激活窗口来“试探绑定”，避免对用户造成可见副作用。

## 实现检查清单

- sticky binding 以 `CGWindowID` 为主键，而不是以 `AXWindowID` 为主键。
- 构建阶段与维护阶段共用同一条绑定管线。
- 公开唯一匹配优先于私有 exact bridge。
- `_AXUIElementGetWindow` 已被封装为独立私有 bridge。
- 单窗口解绑仅发生在 AX 销毁事件。
- 整个 `pid` 的状态清理仅发生在进程退出。
- 一次重建失败、CG 暂时缺席、标题变化、frame 变化，都不会主动解绑 sticky binding。
- `window-layer` 只展示可提交的窗口条目，不展示无法激活的死条目。
