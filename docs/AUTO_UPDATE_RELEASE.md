# FlowTab Sparkle 自动更新与 Community 发布

## 运行时结构

FlowTab 通过 Xcode Swift Package Manager 精确锁定 Sparkle 2.9.6。构建产物包含以下 `Info.plist` 配置：

- Feed：`https://potato-dumplings.github.io/Flow-Tab/appcast.xml`
- EdDSA 公钥：`IX+Vr0uhpQVXoBt7QNj1SAxDtCtPA6dWOX3ttXfOXYI=`
- 自动检查：开启，每 86400 秒一次
- 自动安装：关闭
- Feed 签名和解压前更新签名验证：开启

应用生命周期只创建一个 Sparkle 更新器。alpha、beta 与 rc 版本订阅 `prerelease` 频道，正式版本使用默认频道。后台检查发现更新时，Home 侧栏显示下载按钮；按钮和“检查更新…”菜单都打开 Sparkle 的标准前台版本说明与确认流程。

已知更新状态遵循以下规则：

- “稍后”和短暂检查失败保留侧栏按钮。
- “跳过此版本”、确认安装、确认当前已是最新版时清除按钮。
- 多个 SwiftUI Scene 和直接创建的 Home 窗口共享同一发布状态。

## 首次密钥初始化

使用 Sparkle 2.9.6 官方 release 工具执行：

```bash
generate_keys --account io.github.potato-dumplings.flowtab
```

命令显示的公钥必须与工程中的 `SUPublicEDKey` 完全一致。私钥保存在登录钥匙串的 `io.github.potato-dumplings.flowtab` 账户中。

离线备份需要先导出到受控临时位置，立即加密到离线介质，再销毁明文副本：

```bash
generate_keys --account io.github.potato-dumplings.flowtab \
  -x /secure/temporary/flowtab-sparkle-private-key
openssl enc -aes-256-cbc -salt -pbkdf2 \
  -in /secure/temporary/flowtab-sparkle-private-key \
  -out /offline/media/flowtab-sparkle-private-key.enc
```

导出的明文等同于更新签名密码。备份验收需在隔离账户中解密、导入，并验证同一公钥；备份密码和加密文件应分开保管。

## 发布环境

发布机需要：

- Sparkle 2.9.6 工具包。发布入口使用 `generate_appcast`；`generate_keys` 仅用于初始化和公钥读回，`sign_update` 保留给人工诊断。默认工具目录为 `.build-local/sparkle-tools/bin`，也可通过 `FLOWTAB_SPARKLE_TOOLS_DIR` 指定。
- 一份与上一公开 Community Build 同 TeamIdentifier 的 Apple Development 证书及私钥。
- 一次性安装并完成认证的 GitHub CLI：`gh auth login`。
- 对 `potato-dumplings/Flow-Tab` 的 Release、tag、Pages 与 `gh-pages` 推送权限。
- 可运行固定路径签名 UI 测试的本机环境。

发布前确认：

- 工作树干净。
- `MARKETING_VERSION` 与发布参数相同。
- `CURRENT_PROJECT_VERSION` 是高于上一公开版的正整数。
- Sparkle Keychain 账户可读取；生成结果必须通过应用配置中的公开 Ed25519 公钥验证。
- alpha.05 为 `0.1.0-alpha.05` / build `5`；后续公开构建号保持严格递增。

## 单入口发布

```bash
./scripts/release/publish-sparkle-update.sh \
  --version 0.1.0-alpha.05 \
  --notes docs/releases/v0.1.0-alpha.05.md
```

`--notes` 接受 Markdown 文件或一段 Markdown 文本。通常由脚本从最近一条已公开 GitHub Release 下载基线 DMG；本地复验可显式传入：

```bash
./scripts/release/publish-sparkle-update.sh \
  --version 0.1.0-alpha.05 \
  --notes docs/releases/v0.1.0-alpha.05.md \
  --baseline-dmg /path/to/FlowTab-v0.1.0-alpha.04.dmg
```

发布顺序：

1. 执行包锁定、发布脚本契约、Unit、Behavior、UI、20/50ms Pressure、排版和仓库卫生门禁。
2. 挂载上一公开 DMG，从基线签名读取 Bundle ID、TeamIdentifier、designated requirement 和构建号。
3. 从候选证书字节的 subject OU 解析 TeamIdentifier，选择与基线一致的 Apple Development 身份。
4. 生成 universal Release，按由内到外顺序签署 Sparkle framework、Updater、Installer XPC 与外层 App。
5. 验证候选和基线的双向 designated requirement、Bundle ID、TeamIdentifier、递增构建号、架构、DMG 布局、摘要与 Gatekeeper 实际结果。
6. 创建或恢复 `v<version>` tag 和 draft GitHub Release，上传 DMG 与 SHA-256。
7. 在 `.build-local/gh-pages` 独立 worktree 中，调用 Sparkle 2.9.6：

   ```text
   generate_appcast --channel prerelease --embed-release-notes --maximum-versions 3 --maximum-deltas 0
   ```

8. 使用应用配置中的公开 Ed25519 公钥在本地验证 appcast 与 enclosure 签名，并核对长度、版本、build、频道、最低 macOS 13.0 和下载摘要。验证器不读取私钥；一次发布仅在 `generate_appcast` 签名时访问一次钥匙串。
9. 发布 GitHub Release，读回公开资产并核对 API 长度、API 摘要和重新下载的 SHA-256。
10. 提交并推送只含签名 `appcast.xml` 的 `gh-pages`，从 Pages URL 读回同一内容摘要并再次验证签名。

Release 在 feed 之前公开，因此任何中途失败都会继续保留上一份有效 feed。脚本可以从已有 tag、draft、已上传资产、已公开 Release 或尚未推进的 Pages 阶段重复运行；同一阶段的数据通过摘要与版本读回确认。

## 发布桥接与升级验收

- alpha.04 用户下载 alpha.05 DMG，并手动覆盖 `/Applications/Flow Tab.app`。覆盖后检查辅助功能和屏幕录制权限仍可读取。
- alpha.06 / build 6 是第一条正式应用内升级链路。
- 在隔离 macOS 环境中安装 alpha.05 基线，通过本地 HTTPS 或隔离发布 feed 提供 alpha.06，完成 Sparkle 下载、签名验证、安装、重启与最终版本读回。
- 升级前后分别记录 Bundle ID、TeamIdentifier、designated requirement 摘要、权限状态、`CFBundleShortVersionString` 与 `CFBundleVersion`。
- 对公开 feed 再验证 enclosure 长度、EdDSA 签名、`prerelease` 频道、最低 macOS 13.0、universal 架构和 GitHub 下载 SHA-256。

应用内 E2E 会变更测试机上的已安装应用与权限记录，应在专用隔离账户或虚拟机中执行。

## 故障恢复

- draft 或资产上传失败：重新运行相同发布命令，脚本恢复该 tag 的 Release 并覆盖同名资产。
- Release 已公开、Pages 尚未推进：重新运行后复验公开 DMG，再提交 feed。
- Pages 缓存尚未刷新：脚本按内容 SHA-256 进行有上限的条件读回；超时保留现有任务日志和上一份 feed。
- 私钥不可读：停止发布，使用加密离线备份恢复同一 Keychain 账户。新密钥会改变应用信任根，必须另行设计迁移。
- 候选与基线签名不兼容：停止发布，检查实际证书 OU、TeamIdentifier 和双向 designated requirement 审计结果。
