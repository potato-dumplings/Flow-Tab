# Control + Tab 截图证据清理验证

本轮处理代码审查中确认的无调用方法、空行差异，以及截图失败和取消路径的阶段证据缺口。业务操作、捕获顺序、取消策略、UI 和激活逻辑沿用既有实现。

## 修改与回归证据

- 删除 TestingSupport 中无调用的 `pressureRecordCachedReconciliation()` 和 `recordUnexecutedImageProcessing(...)`。缓存命中继续由真实会话装饰器记录。
- 截图收集器在业务批次实际返回时补齐缺失阶段，保留已有记录、结果、工作量和重复操作；补齐记录采用该返回边界的时间与 CPU 快照，wall/CPU 均为零。
- 清理 `LiveSwitcherModel+Diagnostics.swift` 与 `OptionTabHotkeyMonitor.swift` 的空行差异；两文件当前内容均与 HEAD 一致。
- 协议继续使用 v6，6 个生命周期阶段、50 项组件指标及 schema digest 保持一致。补齐记录的失败/取消语义见 [组件迁移表](control-tab-pressure-component-migration-v6.md)。

独立 Oracle 为截图证据契约：七个截图阶段均有记录，未执行阶段耗时为零、位于父级边界内，已执行记录原值保留，业务返回结果保持一致。新增用例覆盖查询前权限失败、查询失败、查询期间取消、捕获中途失败、图像处理后的取消、重复完成以及成功路径的重复测量。

修复前通过标准 Runner 复现：查询失败和取消均仅记录一个阶段，缺少其余六项；权限失败生成的七条补齐记录全部晚于父级完成时间。四个行为用例中三个失败、成功路径一个通过。

修复后标准 Runner 共执行 28 项相关测试，全部通过，其中新增 7 项；原有测试定义与断言保留。运行时改动集中在 `FlowTab/TestingSupport`。

## 验证状态

| 层 | 状态 | 证据 |
| --- | --- | --- |
| Unit | passed | 新增收集器规则及既有截图、阶段证据用例 |
| Behavior | passed | 新增实际批次/装饰器失败与取消用例，既有装饰器及生命周期保护；与 Unit 合计 28 项 |
| UI | passed | 启动及权限预检、四场景十二轮真实快捷键、绘制、精确激活和清理验证通过；首次应用无 PID 的预检失败单独保留 |
| Pressure | failed | 四场景十二轮行为/证据/清理均通过；CPU/SLO、extreme 延迟继续超标；topology 两轮 RSS 增长超标，三轮修改前同机对照已完成 |
| Process/Tooling | passed | 44 项 Python 证据自检、Runner 契约、v6 schema、生产依赖边界、工程格式及测试目标注册、删除项调用扫描和 `git diff --check` |

标准 FlowTabTests 命令：

```bash
./scripts/testing/run-flowtabtests-local.sh \
  --build-root ./.build-local/pressure-evidence-cleanup-20260905-144334/build-after \
  --output-root ./.build-local/pressure-evidence-cleanup-20260905-144334/green \
  -only-testing:FlowTabTests/ControlTabPressurePreviewCompletionTests \
  -only-testing:FlowTabTests/RuntimePreviewPipelineCompletionTests \
  -only-testing:FlowTabTests/ControlTabPressureDecoratorTests \
  -only-testing:FlowTabTests/ControlTabPressureLifecycleTests \
  -only-testing:FlowTabTests/FlowTabTests/testRuntimePreviewCaptureCollectorKeepsEachScreenshotStage \
  -only-testing:FlowTabTests/FlowTabTests/testRuntimePreviewImageProcessingRecordsTrimAndScale \
  -only-testing:FlowTabTests/FlowTabTests/testControlTabOpenRequiresImportedScreenshotStages
```

允许变化为定向测试过滤、独立前后构建根及不可复用的输出目录。压测使用 `scripts/perf/control-tab-pressure.sh --lane all --scenario all --attempts 3 --duration-seconds 120 --cooldown-seconds 15 --sample-interval 0.5`，构建和输出均由本轮证据目录持有。

正式矩阵保留 28,632 个阶段事件。十二轮行为、证据、清理全部 passed；RSS 为 10/12 passed；延迟为 9/12 passed，三项失败均来自 extreme；CPU/SLO 十二轮继续 failed。四场景均保留首帧附件及验证摘要。

本轮 topology 第 2 轮 RSS 后段 p95 较中段增长 23,408 KiB，门槛为 22,608 KiB；第 3 轮增长 30,912 KiB，门槛为 20,736 KiB。三轮 RSS p95 中位数为 241,792 KiB，相比前次同机正式记录的 230,240 KiB 增长 5.02%，该比较及两轮平台增长失败均保留。

为定位变化来源，从上轮检查点恢复并逐项校验 165 个差异文件，在独立目录使用修改前候选补三轮标准 topology 对照。协议、schema digest、必需阶段、机器、系统、架构、Release 配置及场景身份全部一致。当前环境下的三轮中位数比较如下：

| 进程指标 | 修改前对照 | 本轮候选 | 变化 |
| --- | ---: | ---: | ---: |
| 活动 CPU 平均值 | 12.7244% | 12.7479% | +0.19% |
| 活动 CPU p95 | 36.053% | 33.894% | -5.99% |
| RSS p95 | 255,008 KiB | 241,792 KiB | -5.18% |
| 吞吐 | 0.2663/s | 0.2646/s | -0.66% |

修改前对照三轮的行为、证据、清理、延迟及 RSS 均通过，CPU/SLO 继续 failed。当前对照未显示本轮代码导致进程 RSS 上升；两次 RSS 平台增长失败的具体来源仍待独立定位，压力验收保持 failed。历史与当前对照均为非绿色 v6 证据，作为诊断比较保存，正式绿色基线兼容性规则保持不变。

## 恢复与既有问题

本轮证据路径意图为 `.build-local/pressure-evidence-cleanup-20260905-144334`，由 `repository_root` 解析；目录内相对路径由该证据所有者解析。修改前文件及 SHA 保存在 `before/` 和 `before-manifest.json`；`scope-check.json` 确认此前候选中仅七个预期文件发生变化。新增测试和本报告另行保留。本轮未创建提交。

完整工作树差异由 `candidate-worktree.tar.gz`、补丁及 SHA 清单保存，恢复时可在独立检出的相同 HEAD 上展开。`LATEST-CHECKPOINT.md` 记录恢复入口。测试结果根对象、状态、日志、采样和首帧证据保留；大型证据逐文件 gzip 并验证原始 SHA，索引见 `evidence-compression-manifest.json`。本轮构建与已导出的结果包按 `artifact-cleanup.json` 清理。压测临时退出的正式版 FlowTab 已恢复运行。

此前完整重构的 CPU/SLO、extreme 延迟、共享面板首次绘制回执和搜索输入就绪问题继续见 [重构验证报告](control-tab-pressure-decoupling-validation.md)。本轮清理的完成状态以本报告的验证结果为准。
