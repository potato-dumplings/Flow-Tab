# Control + Tab 压测解耦验证记录

当前状态：重构实现及计划验证已执行完成。验收保留一项证据问题：共享面板 application realistic 首轮高亮已实际绘出，绘制回执缺失；冻结版本和同一候选的完整复跑均通过，首次失败的原因尚未确定。现有 CPU/SLO、extreme 延迟及搜索输入就绪失败继续分别保留 `failed`。

## 实现边界

生产编排通过业务接口访问输入、会话状态、投影、截图、预览、面板及激活组件；TestingSupport 装饰真实实现并持有测量资源。默认初始化使用系统实现，测试装配通过 `ControlTabPressureRun` 独立创建、配置和取消。

| 边界 | 生产责任 | 测试责任 |
|---|---|---|
| 输入与会话 | `HotkeyMonitoring`、`SwitcherSessionState`、`SwitcherSessionResources` | 输入回调包装、同步发布与选择测量、资源释放证据 |
| 投影与事实 | `RuntimeProjectionDependencies`、`RuntimeFocusedWindowFactCollector`、`RuntimeWindowEntryProjector` | 转发通知源身份，记录 CG、AX、映射及严格新鲜投影等待 |
| 捕获与图像 | `RuntimeWindowPreviewCaptureBatch`、`RuntimeWindowImageCapturer`、`RuntimePreviewImageProcessor` | 按真实操作采样，随批次传播取消及测量上下文 |
| 预览状态 | `SwitcherPreviewStorage`、`SwitcherPreviewSession`、`SwitcherPreviewPlanner`、`SwitcherPreviewPublication` | 缓存命中、过期批次、发布和工作量证据 |
| 面板 | 呈现协调器、几何、窗口、辅助功能、监听、延迟任务及可复用外壳组件 | 原生可见性观察，实际外壳准备完成回执，细阶段装饰器 |
| 激活 | `WindowActivating` 与 `RuntimeActivator` | 请求/分发测量，PID、窗口 ID 与 CGWindowID 精确验证 |
| 绘制 | `SwitcherPanelContentBuilding` 与共享根视图 | 独立绘制探针、诊断视图及展示/窗口/预览版本身份校验 |

系统依赖包共享窗口记录库、协调器、事实提供器、索引构建器、应用目录和权限策略。会话及预览的状态所有者保留同步发布顺序；普通应用沿用已有投影、预览、显示、激活及清理策略。

## 协议兼容性

协议升级为 v6，保留六阶段、50 项指标、单位、阈值、inclusive/exclusive 口径与 0.5ms 对账容差。完整定义见 [组件迁移表](control-tab-pressure-component-migration-v6.md) 与 [机器契约](../scripts/perf/lib/control_tab_pressure_v6_schema.json)。

Swift/Python schema digest：`06907e5b048ab5eff629e08944b734d3ed6ef798e3a9ea4cfde9af3313d29ad6`。

正式细阶段基线要求 v6 与一致 digest。v5 保留为历史证据；跨版本外部对照限定在相同负载、采样范围及可对齐的进程指标和链路端点，单独报告适用范围。

## 已完成验证

| 层次 | 当前结果 | 证据 |
|---|---|---|
| Unit | passed | 装饰器参数、结果、错误、取消转发；批次代次、重叠时间线、CPU 对账、指标完整性和协议兼容性 |
| Behavior | passed | 标准 `run-flowtabtests-local.sh`：239 项相关用例通过；随后补充转发、重复准备、Home 订阅及旧事实批次隔离；Unit/Behavior 合计 284 项不同用例通过 |
| UI | failed，保留既有失败 | 最终 `shared-ui-03` 为 13/14 通过；唯一失败为冻结的重构前版本也能复现的搜索输入 keyboard-readiness 超时 |
| Pressure | failed，性能与首次回执失败分别保留 | Control + Tab 12 轮完整矩阵和最终外部采样 12 轮的行为、证据、清理及 RSS 门禁全部通过；CPU/SLO 和 extreme 延迟保留超标。共享六场景均有完整通过记录，首轮单次回执失败保留待闭环 |
| Process/Tooling | passed | 证据/协议、共享面板证据、Runner 环境、拓扑目标及契约、工程 plist、业务依赖边界、Skill 校验与 `git diff --check` |
| 构建 | passed | 普通 Release 和压测 Release 均经标准安装器生成 Apple Development 签名 App；普通 Release 编译条件及二进制检查通过 |

行为覆盖保留原有 49 项压测保护，并包含通知源身份、同步重入、旧代次回调、缓存命中、取消传播、外壳实际完成、对象释放恢复装配与精确激活验证。

共享 UI 已通过 Control+Tab 悬停/点击、Option+Tab 悬停/点击及按住释放、搜索切换与中文查询、搜索悬停/点击、透明/遮挡可见性、快速重开、延迟预览和大窗口集分页。搜索输入超时的重构前后失败日志分别保留。

Control + Tab 完整矩阵采用每场景三轮 `120s + 15s cooldown`、`0.5s` 采样。12 轮预热与活动阶段的事件失败均为零，六阶段及 50 项条件指标完整，对账、绘制身份与精确激活均通过。紧凑结果为 `v6-formal-01-compact.json`。

共享面板 application、app-to-window、search 的 realistic/extreme 场景使用 `120s + 15s cooldown`、`0.5s` 采样。application realistic 首轮高亮命令返回后缺少 appContent 绘制回执，4 秒 watchdog 结束；随后冻结基线通过 2,149 次循环，同一候选复跑通过 2,271 次循环。观察器在命令执行前安装，现有证据排除了订阅安装晚于同步操作的假设。首次失败继续保留，归因尚未确定；其余五场景首轮均通过。

保存的失败录像在第 5 秒和第 25 秒均显示第三个应用高亮，与失败回执中的 `com.flowtab.pressure.app.0002` 一致。该证据将问题范围缩小至绘制事件的采集、代次接受或交付；它尚不足以确定其中的具体原因。后续最小定位范围为 TestingSupport 中的 AppPanel 绘制回执路径，记录准备、事件到达和拒绝原因，并复现首次展示后的高亮。

| 共享压测场景 | 完整通过循环数 |
|---|---:|
| application realistic（同候选复跑） | 2,271 |
| application extreme | 973 |
| app-to-window realistic | 1,856 |
| app-to-window extreme | 654 |
| search realistic | 1,384 |
| search extreme | 1,163 |

## 三轮外部对照

对照采用 `external-only`、四场景各三轮 `30s + 15s cooldown`、`0.5s` 采样。逐项核对机器、系统、架构、Release 配置、lane、scenario 及实际规模一致。只用活动区间的稳定进程指标和链路端点比较历史 v5 与当前 v6，正式细阶段兼容性仍按 v6 单独验收。

下表为最终候选相对对照的三轮中位数变化。realistic 使用相邻补采的冻结版本；mutation 使用同一严格夹具断言的冻结版本；topology 使用交叉对照。对应文件为 `external-after-02-topology-cross-over-comparison.json`。

| 场景 | CPU 平均值 | RSS P95 | 吞吐 | 每循环链路总量 | 5% 门槛 |
|---|---:|---:|---:|---:|---|
| ready realistic | +1.09% | +3.87% | +3.48% | −4.67% | passed |
| ready extreme | −2.24% | −0.03% | −1.62% | +1.04% | passed |
| mutation closed-panel | −1.04% | +4.18% | +0.35% | −6.51% | passed |
| topology noisy | −5.16% | +3.67% | +0.51% | +1.45% | passed |

使用起始 topology 基线的第一次对照，RSS P95 增加 **5.57%**，其比较结果在 `external-after-02-final-comparison.json` 中继续保持 `failed`。追加的冻结版本交叉对照得到 **3.67%**；两组原始三轮均保留。RSS 对运行环境和样本组存在敏感性，当前证据未稳定复现超过 5% 的增量；本记录同时提供两次结果，后续内存归因可继续使用这一具名证据包。

早期候选的 realistic 吞吐下降与链路总量增加，在最终候选的相邻三轮对照中均未复现。所有最终外部采样轮次的预热和活动事件失败均为零。

## 当前 v6 性能超标

下表为完整 `120s` 三轮的中位数，采用完整 recorder；其数值独立于上述外部对照。

| 场景 | 活动 CPU 平均值 | RSS P95（KiB） | open wall P95（ms） | cancel wall P95（ms） |
|---|---:|---:|---:|---:|
| ready realistic | 33.430% | 64,928 | 9.545 | 23.808 |
| ready extreme | 57.577% | 208,736 | 53.862 | 158.524 |
| mutation closed-panel | 9.001% | 230,240 | 117.741 | 36.970 |
| topology noisy | 12.497% | 230,240 | 134.844 | 24.589 |

12 轮 CPU/产品 SLO 门禁保留 `failed`；三个 ready extreme 轮次还超过原有 ready open/cancel 延迟阈值。mutation 与 topology 的完整新鲜投影等待按原有条件规则评估，其延迟门禁通过。逐阶段加权 CPU、精确激活回读、50 项组件数据与阈值结果保存在完整证据及紧凑索引中。

## 已确认的历史失败

- 原有 CPU、产品 SLO 及 extreme 延迟阈值超标保留 `failed`，随正式结果列出。
- 初始 mutation 基线在夹具变更后过早断言缓存首帧；测试改用既有严格投影接受者，验证真实窗口数量、PID 和更晚的完整投影代次。冻结版本仅移植同一夹具断言，生产源码保持原快照。
- 冻结版本的部分 mutation 预热绘制回执超时；其活动采样区间中的 16 项事件均满足原断言。外部对照需明确区分活动区间指标和整轮行为结果。
- 共享 UI 的搜索输入 keyboard-readiness 超时在冻结版本与候选版本均复现。

## 验证中发现并修复的问题

topology 归因发现同一次应用启动调用两次测试准备入口，第二次创建新 Run，投影确认观察者仍读取第一份服务，导致夹具 AX 屏蔽握手无法完成。装配入口现按通知路由识别本轮，重复准备复用同一 Run；切换路由和停止操作取消、释放旧资源。新增生命周期测试和真实 topology 回归均通过，后者验证四个精确目标、AX 屏蔽握手和完整细阶段证据。

Home 与测试投影观察者共五处订阅已使用接口提供的通知源身份。新增回归验证真实 Home 观察者接受装饰器底层通知，并拒绝无关通知对象；相关 57 项用例通过。

旧事实采集批次在测量阶段重置后继续执行，可能将后续子操作计入新阶段。确定性回归先复现失败，再通过批次上下文固定测量代次修复；旧批次继续完成业务操作，过期测量被拒绝。相关 18 项用例通过，红绿日志均保留。

## 恢复与证据边界

恢复所有者目录意图：`.build-local/pressure-decoupling-20260905-075822`，以仓库根解析。

- 起始 HEAD：`aa0fe0ecac1ab1a4ef3b16f2b80d98e7f73dee28`。
- `manifest.json`、`original/`、`original.patch` 保存起始 88 项本地变更，包含未跟踪文件。
- `reference-source/` 由 HEAD 与起始工作树叠加构建；夹具测试调整另有原文件、SHA 和调整清单。
- `candidate-source-01.json`、`candidate-source-02.json` 与 `candidate-source-03.json` 分别固定验证候选的 948 个源码、工程和工具文件校验值，第三版包含重复准备、订阅身份与旧事实批次隔离修复。
- `related-behavior-02.log`、`decorator-final-01.log`、`bootstrap-lifecycle-01.log`、`notification-identity-01.log`、`shared-ui-02.log` 及 `shared-ui-reference-01.log` 提供分层验证记录；`unit-behavior-unique-results.json` 固定去重后的用例清单。
- `ordinary-release-final-assembly.json` 保存最终普通 Release 的编译条件、构建中间产物符号与标准安装器签名检查。安装器日志记录实际固定路径 App 的证书签名；构建目录中的中间产物单独标识。
- `candidate-source-final-verification.json` 验证 948 个源码、工程及工具文件与完整验证候选完全一致。
- `process-tooling-final.json`、`skill-final.log`、`shared-pressure-final-compact.json` 与 `external-after-02-compact.json` 汇总最终验证。
- 压测目录按运行、场景、轮次不可变保存；紧凑索引记录相对路径意图与原始 summary SHA。

恢复时以起始 HEAD 建立独立工作目录，再应用 `original.patch` 并按清单恢复 `original/`。最终候选另有 `candidate-worktree.tar.gz`、`candidate-worktree-manifest.json` 和 `candidate-worktree.patch`，可在同一 HEAD 的独立目录中恢复当前差异。

本轮专属构建、DerivedData、结果包与缓存的清理结果记录在 `artifact-cleanup.json`。大体积 CSV、JSON 与日志按 `evidence-compression-manifest.json` 无损压缩，保留原路径意图、大小及 SHA；复核时在证据所属目录解压为原文件名。保留的具名证据包分别服务于 CPU/SLO/extreme 延迟、RSS 对照敏感性、共享绘制回执和搜索输入就绪问题。起始 88 项工作树快照、冻结源代码及其他任务的产物保持独立。
