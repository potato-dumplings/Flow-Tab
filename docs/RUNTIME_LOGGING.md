# Runtime Logging

本页定义 FlowTab 生产运行时日志的级别口径。新增或调整日志时，优先复用 `RuntimeLog` 和 `RuntimeLogCategory`，不要在生产代码里直接调用 `RuntimeDiagnostics.shared.log(...)`，除非是在日志基础设施本身或测试启动数据里写入原始记录。

## 级别规则

- `debug`：高频诊断、候选项、逐窗口/逐输入细节、耗时拆解、布局测量、内部探测路径和成功细节。
- `info`：正常生命周期、用户偏好生效、成功注册/恢复、以及预期内 fallback 策略选择。
- `warning`：权限缺失、能力降级、超时、缓存异常、搜索无结果诊断等可恢复但需要关注的状态。
- `error`：最终请求操作失败，例如热键注册失败、Command+Tab 接管或恢复失败、activation recovery 耗尽、launch-at-login 写入失败、预览批量获取失败。

内部路线失败不自动等于 `error`。例如 activation 可以先尝试 CG，再尝试 AX、public recovery 或 Chrome internal；单条路线不可用应保持 `debug`，只有所有可用恢复路径耗尽后才记录 `error`。

## DEBUG 诊断语义

运行时日志等级是唯一的记录门槛。选择 `DEBUG` 时，FlowTab 完整记录现有高频脱敏诊断，包括 `Projection`、`Activation`、`AX`、`Preview`、`Search*` 与 `SwitcherLayout` 等热路径分类。默认等级为 `ERROR`。

`Projection` 记录运行时投影的构建、修复、协调与一致性诊断。它用于说明窗口与应用事实如何形成 Home、切换器和搜索所消费的读模型；在窗口拓扑频繁变化时，这一分类会产生较高日志量。

每次达到等级门槛的调用仍生成一条持久化事件。`RuntimeLogPrivacyFormatter` 把消息解析为内部隐私信封，保留消息、事件和字段的顺序、类型、字符长度、项目数量，以及由本机持久密钥生成的 96-bit HMAC 指纹。原始事件文本、字段名和字段值不进入磁盘。

新记录使用一行一事件的 v2 payload：

```text
privacy=v2 m=<length>,<fieldCount>,<fingerprint> e=<length>,<count>,<fingerprint>|- f=<nameLength>,<nameFingerprint>,<typeCode>,<valueLength>,<valueCount>,<valueFingerprint>[;...]|-
```

磁盘指纹为 16 字符 Base64URL；Logs 页展开为既有的 24 字符十六进制指纹。字段类型码为 `t`（text）、`s`（search-text）、`b`（browser-tab-title）、`w`（window-title）、`p`（file-path）、`u`（url）、`a`（application-identifier）、`e`（error-text）和 `i`（identifier）。v2 行的时间戳、等级、头部分隔和已知分类也采用可逆紧凑表示：时间戳按当日毫秒数编码为 6 字符 Base36，等级使用 `D/I/W/E`，已知分类使用单字符码；读取后恢复既有可读格式，并兼容早期 v2 紧凑行头。

## 存储与读取

- 本地保留策略固定为每个文件 `1,000,000 bytes`、最多 `20` 个日志文件，总预算约 `20 MB`。
- 日志目录权限为 `0700`，日志文件、隐私标记和指纹密钥权限为 `0600`。
- `.runtime-log-privacy-v1` 继续作为回滚兼容标记，`.runtime-log-privacy-v2` 标识紧凑格式；升级时原地保留 v1 日志和指纹密钥，新旧格式可以混合读取。
- 尾部读取器在等级筛选和最新 `300` 行选择完成后展开 v2；v1 行原样返回，损坏的 v2 行以安全原文返回并继续读取。旧版本回滚时可把 v2 作为安全紧凑文本读取。
- Logs 页展示最新 `300` 条达到当前筛选等级的持久化记录。
- 首次读取、等级变化、清空、文件截断与保留轮转后执行完整尾部读取；普通的新文件轮转、同等级重新进入和普通刷新通过文件偏移快照增量补齐。
- Logs 页存在缓存时会立即呈现缓存；页面连续可见 `100 ms` 后补齐增量，快速往返期间取消尚未开始的读取。
- 完整读取以 `64 KB` 数据块从文件尾部逆向扫描换行字节，收集满 `300` 条匹配记录后停止。
- 写入仍按 `50 ms` 批量 flush，并保留既有 generation、取消、增量快照和轮转行为。
- 读取失败时保留最近一次成功画面，下一次日志变更或重新进入 Logs 页继续恢复。

## 放置原则

- 可复用生产日志入口放在 `FlowTab/Infrastructure/Runtime/RuntimeLogging.swift`。
- 文件存储与轮转放在 `RuntimeLogFileStore.swift`，尾部字节解析放在 `RuntimeLogTailReader.swift`。
- 运行时拓扑、权限、activation、preview、projection 与 fact collection 等诊断日志应留在 runtime infrastructure 或对应的 feature coordinator，不要散落到纯 UI 渲染代码。
- 临时排障日志必须在交付前移除；需要长期保留的日志应按本页级别重新判断。
