# FlowTabApp

FlowTabApp 是一个 macOS 应用切换器项目，目标是提供接近系统 `Command + Tab` 的体验，并支持可扩展的分组/窗口切换逻辑。

本仓库已合并为单仓库结构（Monorepo）：
- `FlowTabApp/`：macOS 应用（Xcode Target）
- `FlowTabCore/`：核心状态机与模型（Swift Package）
- `FlowTabAppTests/`、`FlowTabAppUITests/`：应用测试
- `docs/`：项目文档与注意事项

## 环境要求

- macOS 14+
- Xcode 15+
- Swift 5.9+

## 快速开始

### 1) Xcode 运行（推荐）

1. 打开 `FlowTabApp.xcodeproj`
2. 选择 `FlowTabApp` Scheme
3. 直接 `Run`（`Cmd + R`）

### 2) 命令行构建

```bash
xcodebuild \
  -project FlowTabApp.xcodeproj \
  -scheme FlowTabApp \
  -configuration Debug \
  build
```

### 3) Core 包测试

```bash
cd FlowTabCore
swift test
```

## 当前交互

- `Option + Tab`：正向切换
- `Option + Shift + Tab`：反向切换
- 在面板内支持 `Tab / Shift+Tab / ↑ / ↓ / ← / →`
- 松开 `Option` 自动确认并激活目标

## 权限说明

首次运行需要在系统设置中授予辅助功能权限：

- `系统设置 -> 隐私与安全性 -> 辅助功能`

未授权时，窗口级聚焦能力会降级为应用级激活。

## 开源发布建议

- 建议开源：应用代码、Core 逻辑、测试、文档
- 不建议开源：任何密钥/证书/私有数据/未授权素材

## 额外文档

- 注意事项见：[docs/README.md](docs/README.md)
