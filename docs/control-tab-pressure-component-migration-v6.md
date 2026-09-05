# Control + Tab 全链路压测组件迁移表（v6）

协议保留 6 个生命周期阶段和 50 个细阶段名称。正式基线使用 v6 与相同 schema digest；v5 证据保存在历史恢复目录。

- 单位：wall/CPU time 为 ms，CPU 为 percent，工作量为 count。
- 组件为 inclusive，时间线为 exclusive，wall/CPU 对账容差均为 0.5ms。
- 保持 CPU 50% 和既有延迟阈值。既有超标独立保留 failed 状态。
- 同步测量包围真实操作；异步批次绑定独立业务批次 ID，在实际完成、取消或失败处结束。
- 绘制身份固定为展示代次、选中窗口及预览版本，透明绘制由测试可见性观察器保留至读回。
- 本表和必需项集合的机器源为 `scripts/perf/lib/control_tab_pressure_v6_schema.json`；自检验证 Swift/Python 名称、版本与 digest。

| 指标 | 生产所有者 / 测试装饰器 | 起止边界 | 父级 | 工作量 | outcome | 必需阶段 |
|---|---|---|---|---|---|---|
| `input_routing` | OptionTabHotkeyMonitor / ControlTabPressureHotkeyMonitor | 真实输入回调进入 → 业务回调返回 | none | 输入事件数 | 返回=completed | open, forward, reverse |
| `projection_read` | SwitcherFocusedWindowSessionCoordinator / ControlTabPressureFocusedSession | focused projection read 调用 → 返回 | input_routing, ax_cg_space_reconciliation | 读取次数 | 返回=completed | open |
| `ax_cg_space_reconciliation` | SwitcherFocusedWindowSessionCoordinator / ControlTabPressureFocusedSession | 请求新鲜投影前 → 严格更新的完整投影被接受或取消 | projection_read | 请求数 | 已有完整投影=cache_hit;匹配=completed;取消=cancelled | open |
| `on_screen_cg_read` | RuntimeFocusedWindowFactCollector / ControlTabPressureFactDecorators | on-screen CG 查询调用 → 返回 | ax_cg_space_reconciliation | 目标 PID 查询数 | 执行=completed;复用=cache_hit | open |
| `all_cg_read` | RuntimeFocusedWindowFactCollector / ControlTabPressureFactDecorators | all CG 查询调用 → 返回 | ax_cg_space_reconciliation | 目标 PID 查询数 | 执行=completed;复用=cache_hit | open |
| `ax_read` | RuntimeFocusedWindowFactCollector / ControlTabPressureFactDecorators | AX facts 查询调用 → 返回 | ax_cg_space_reconciliation | 目标 PID 查询数 | 执行=completed;复用=cache_hit | open |
| `mapping_space_filter` | RuntimeWindowEntryProjector / ControlTabPressureFactDecorators | 窗口映射与 Space 过滤调用 → 返回 | ax_cg_space_reconciliation | 目标 PID 查询数 | 执行=completed;复用=cache_hit | open |
| `session_build` | SwitcherSessionState / ControlTabPressureSessionState | buildWindowSession 调用 → 返回 | input_routing | 候选窗口数 | session=completed;nil=failed | open |
| `session_publish` | SwitcherSessionState / ControlTabPressureSessionState | publish 调用 → 同步通知与业务发布回调返回 | input_routing, selection_mutation | 发布次数 | 返回=completed | open, forward, reverse |
| `preview_planning` | SwitcherPreviewPlanner / ControlTabPressurePreviewPlanner | plan 调用 → 返回含缓存及待捕获请求的业务计划 | input_routing | 候选窗口数 | 返回=completed | open |
| `preview_capture` | SwitcherPreviewCaptureBatch / ControlTabPressurePreviewBatch | 创建业务批次前 → 实际捕获返回;同步 override 调用 → 返回 | preview_planning | 捕获请求数 | 捕获返回=completed;已取消=cancelled;全复用=cache_hit | open, forward, reverse |
| `preview_shareable_content_lookup` | RuntimeWindowImageCapturer / ControlTabPressurePreviewDecorators | 共享窗口查询调用 → 实际返回 | preview_capture | 查询数 | 成功=completed;不可用=failed;条件未执行=not_required;复用=cache_hit | open |
| `preview_screenshot_manager_capture` | RuntimeWindowImageCapturer / ControlTabPressurePreviewDecorators | ScreenCaptureKit 截图调用 → 成功或失败返回 | preview_capture | 截图请求数 | 图像=completed;失败=failed;未选择=not_required;复用=cache_hit | open |
| `preview_core_graphics_capture` | RuntimeWindowImageCapturer / ControlTabPressurePreviewDecorators | CG 截图调用 → 返回 | preview_capture | 截图请求数 | 图像=completed;失败=failed;未选择=not_required;复用=cache_hit | open |
| `preview_transparent_trim` | RuntimePreviewImageProcessor / ControlTabPressurePreviewDecorators | 透明裁剪调用 → 返回 | preview_capture | 图像数 | 返回=completed;流水线未执行=not_required;复用=cache_hit | open |
| `preview_image_scale` | RuntimePreviewImageProcessor / ControlTabPressurePreviewDecorators | 缩放调用 → 返回 | preview_capture | 图像数 | 图像=completed;nil=failed;未执行=not_required;复用=cache_hit | open |
| `preview_image_materialization` | RuntimePreviewImageProcessor / ControlTabPressurePreviewDecorators | NSImage 实例化调用 → 返回 | preview_capture | 图像数 | 返回=completed;未执行=not_required;复用=cache_hit | 条件执行 |
| `preview_title_bar_inference` | RuntimePreviewImageProcessor+TitleBar / ControlTabPressurePreviewDecorators | 标题栏推断调用 → 返回 | preview_capture | 图像数 | 执行=completed;策略关闭=not_requested;未执行=not_required;复用=cache_hit | open |
| `preview_image_process_cache` | SwitcherPreviewSession / ControlTabPressurePreviewSession | 单个缓存应用或整批结果应用调用 → 返回 | preview_planning | 图像或请求数 | 返回=completed;全复用=cache_hit | open, forward, reverse |
| `preview_batch_publication` | SwitcherPreviewPublication / ControlTabPressurePreviewSession | 批次发布调用 → 业务准备状态回调返回 | preview_image_process_cache | 完成项数 | 返回=completed;复用=cache_hit | 条件执行 |
| `preview_result_discard` | SwitcherPreviewSession+Batch / ControlTabPressurePreviewSession | 批次结果判定返回时记录业务结果 | preview_planning | 请求数 | cancelled=cancelled;stale=stale_generation;applied=not_required | 条件执行 |
| `appkit_panel_presentation` | SwitcherPanelPresentationCoordinator+Presentation / ControlTabPressurePanelPresentation | presentStartedHotkeySession 调用 → 返回 | input_routing | 预览窗口数 | 返回=completed | open |
| `screen_geometry` | SwitcherPanelGeometry / ControlTabPressurePanelGeometry | resolveActivePresentationScreen 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `panel_size` | SwitcherPanelGeometry / ControlTabPressurePanelGeometry | 展示期间 updatePanelSize 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `panel_center` | SwitcherPanelGeometry / ControlTabPressurePanelGeometry | centerPanelOnActiveScreen 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `panel_accessibility` | SwitcherPanelAccessibility / ControlTabPressurePanelOperations | syncPanelAccessibilityAnchors 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `panel_level` | SwitcherPanelWindowOperations / ControlTabPressurePanelOperations | updatePanelPresentationLevel 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `initial_visibility_tracking` | SwitcherPanelDelayedOperations / ControlTabPressurePanelDelays | beginInitialVisibilityTracking 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `make_key` | SwitcherPanelWindowOperations / ControlTabPressurePanelOperations | makeKey 或 makeKeyAndOrderFront 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `order_front` | SwitcherPanelWindowOperations / ControlTabPressurePanelOperations | orderFrontRegardless 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `panel_hide` | SwitcherPanelWindowOperations / ControlTabPressurePanelOperations | hideNonPanelWindowsIfNeeded 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `presentation_readback` | SwitcherPanelDelayedOperations / ControlTabPressurePanelDelays | scheduleInitialVisibilityRecovery 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `event_monitor_install` | SwitcherPanelEventMonitoring / ControlTabPressurePanelOperations | 安装本地及全局事件监听调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `delayed_entry_scheduling` | SwitcherPanelDelayedOperations / ControlTabPressurePanelDelays | scheduleDelayedWindowLayerEntryIfNeeded 调用 → 返回 | appkit_panel_presentation | 调用数 | 返回=completed | 条件执行 |
| `swiftui_layout_first_draw` | SwitcherPanelContentBuilder / ControlTabPressureObservation | open 观察开始 → 当次真实绘制满足会话身份且可见 | none | 预览窗口数 | 匹配=completed;观察超时=timed_out | open |
| `visibility_readback` | SwitcherPanelController / ControlTabPressureObservation | 匹配绘制后开始可见性读回 → 状态条件满足 | none | 读回次数 | 满足=completed;超时=timed_out | open |
| `selection_mutation` | SwitcherSessionState / ControlTabPressureSessionState | applying 输入归约调用 → 返回 | input_routing | 输入数 | 返回=completed | forward, reverse |
| `panel_geometry_update` | SwitcherPanelGeometry / ControlTabPressurePanelGeometry | 非初次展示 updatePanelSize 调用 → 返回 | input_routing | 预览窗口数 | 返回=completed | forward, reverse |
| `swiftui_diff_layout_draw` | SwitcherPanelContentBuilder / ControlTabPressureObservation | 切换观察开始 → 当次选中窗口与预览版本的真实绘制 | none | 预览窗口数 | 匹配=completed;超时=timed_out | forward, reverse |
| `selection_readback` | SwitcherPanelController / ControlTabPressureObservation | 匹配选择绘制后开始读回 → 选中窗口与可见性满足 | none | 读回次数 | 满足=completed;超时=timed_out | forward, reverse |
| `target_resolution` | SwitcherSessionState / ControlTabPressureSessionState | resolvingSelection 调用 → 返回 | none | 解析数 | 返回=completed | commit |
| `activation_dispatch` | RuntimeActivator / ControlTabPressureWindowActivator | activate 调用 → 分发返回 | target_resolution | 请求数 | 返回=completed | commit |
| `exact_window_activation` | RuntimeActivator / ControlTabPressureActivationCoordinator | 精确目标激活请求前 → PID/窗口 ID/CGWindowID 匹配的验证回调 | activation_dispatch | 请求数 | 验证=completed;无需精确目标=not_required;超时=timed_out | commit |
| `focus_readback` | RuntimeWindowFocusRequest / ControlTabPressureObservation | 激活状态读回开始 → 精确目标验证及隐藏状态满足 | none | 读回次数 | 满足=completed;无需精确目标=not_required;超时=timed_out | commit |
| `panel_teardown` | SwitcherPanelPresentationCoordinator+Teardown / ControlTabPressurePanelPresentation | endPresentationSession 调用 → 返回 | none | 调用数 | 返回=completed;已关闭=not_required | commit, cancel |
| `observer_removal` | SwitcherPanelEventMonitoring / ControlTabPressurePanelOperations | 移除监听及其业务清理调用 → 返回 | panel_teardown | 调用数 | 返回=completed;已关闭=not_required | commit, cancel |
| `delayed_task_cancellation` | SwitcherPanelDelayedOperations / ControlTabPressurePanelDelays | 取消展示工作或待新鲜投影展示调用 → 返回 | panel_teardown | 调用数 | 返回=completed;已关闭=not_required | commit, cancel |
| `cache_session_cleanup` | SwitcherSessionResources / ControlTabPressureSessionResources | resetRuntime 调用 → 上下文、缓存、捕获取消与状态清理返回 | none | 清理前应用上下文数 | 返回=completed;已关闭=not_required | commit, cancel |
| `reusable_shell_prepare` | SwitcherReusablePanelShell / ControlTabPressurePanelOperations | prepare 调用前 → 实际完成或取消回调 | panel_teardown | 请求数 | prepared=completed;无尺寸=not_required;superseded=cancelled | cancel |
| `closed_state_readback` | SwitcherPanelController / ControlTabPressureObservation | 关闭状态读回开始 → 隐藏与清理回执及状态满足 | none | 读回次数 | 满足=completed;超时=timed_out | cancel |

全部组件沿用条件执行规则：仅真实发生的操作产生测量，缓存或路径未选择使用表内已有 outcome；旧运行或旧阶段事件由测量上下文拒绝。总量采用进程 CPU 和互斥时间线核对，inclusive 子阶段允许重叠。

截图批次返回时，测试收集器补齐尚无记录的截图阶段：取消使用 `cancelled`，其余缺失使用 `failed`，使失败及证据缺失继续保留非绿色状态。补齐记录的 wall/CPU 均为零，时间与 CPU 快照绑定捕获返回边界，工作量为该批次请求数，表示受影响请求。已经执行或显式标记条件未执行的记录保持原值和数量；同一阶段多次真实操作分别保留。此规则适用于查询前退出、查询失败和捕获中途退出，协议版本、指标定义和 schema digest 保持 v6。
