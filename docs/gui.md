# Token Dashboard GUI

macOS 菜单栏应用，统一查看 AI 服务用量。原生 Swift/SwiftUI 实现，无 Python 依赖。

## 支持的 Provider

| Provider | 计价方式 | 数据源 | 认证方式 |
|----------|----------|--------|----------|
| OpenCode Go | 5h/周/月限额（百分比） | HTML 解析 | cookie |
| MiniMax Token Plan | 5h + 周窗口（百分比） | API | api_key |
| Xiaomi MiMo | Token Plan + 按量付费 | API | cookie |
| 讯飞星辰 Coding Plan | 请求次数 | API | cookie |
| DeepSeek | 按量付费（余额） | API | api_key |

## 安装

### 从源码构建

```bash
cd gui
swift build -c release
```

### 打包为 .app

```bash
# 1. 创建 app bundle
mkdir -p /tmp/TokenDashboard.app/Contents/MacOS
mkdir -p /tmp/TokenDashboard.app/Contents/Resources

# 2. 复制 Info.plist（见下方）
# 3. 复制二进制
cp .build/release/TokenDashboard /tmp/TokenDashboard.app/Contents/MacOS/

# 4. 安装
cp -R /tmp/TokenDashboard.app /Applications/
```

Info.plist：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TokenDashboard</string>
    <key>CFBundleIdentifier</key>
    <string>com.token-dashboard.gui</string>
    <key>CFBundleName</key>
    <string>Token Dashboard</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

## 使用

### 启动

双击 `/Applications/TokenDashboard.app`，或通过 Spotlight 搜索 "Token Dashboard"。

启动后出现在菜单栏，无 Dock 图标（LSUIElement）。

### 菜单栏图标

- **有数据时**：显示所有 provider 中最紧张的使用百分比（如 `60%`）
- **无数据时**：显示仪表盘图标

### 添加凭证

点击菜单栏图标 → 齿轮按钮 → Settings → Credentials 标签页。

#### API Key（MiniMax、DeepSeek）

1. 选择 Provider
2. 在 API Key 输入框粘贴 key
3. 点击 Save

#### Cookie（OpenCode、MiMo、讯飞）

1. 选择 Provider
2. 在 Cookie 输入框粘贴 cookie，支持以下格式：
   - **cURL 格式**：直接粘贴浏览器 "Copy as cURL" 的完整命令
   - **Cookie header**：`Cookie: name=value; name2=value2`
   - **纯 cookie 字符串**：`name=value; name2=value2`
3. OpenCode 可选填 Workspace ID（留空则自动获取）
4. 点击 Save

**获取 Cookie 的方法**：

1. 用浏览器打开 provider 网站并登录
2. 按 F12 打开 DevTools
3. 切换到 Network 标签，刷新页面
4. 右键点击任意请求 → Copy → Copy as cURL
5. 粘贴到 Cookie 输入框

**Provider 网站**：
- OpenCode: https://opencode.ai/auth
- MiMo: https://platform.xiaomimimo.com
- 讯飞: https://maas.xfyun.cn

### 查看用量

点击菜单栏图标，弹出面板显示所有已配置 provider 的用量卡片。

每个卡片包含：
- Provider 名称和计划类型
- 各时间窗口的用量进度条和百分比（颜色：<70% 绿色，70-90% 黄色，>90% 红色）
- 重置时间（如 `6d 15h`、`2h 30m`）
- 余额（按量付费 provider）
- 警告信息（如 cookie 过期）

### 设置

点击齿轮按钮 → Settings：

**Credentials 标签页**：
- 选择 Provider 添加/修改凭证

**General 标签页**：
- 刷新间隔（10-600 秒，默认 60 秒）
- 警告阈值（默认 70%）
- 严重阈值（默认 90%）

## 数据目录

```
~/.token-dashboard/
├── config.yaml           # 配置文件（与 CLI 版共用）
├── credentials/          # 凭证文件（GUI 专用）
│   ├── opencode:default:cookie
│   ├── minimax:default:api_key
│   └── ...
└── credentials.json      # CLI 版凭证（GUI 不使用）
```

凭证以 JSON 文件存储在 `~/.token-dashboard/credentials/` 目录下，key 格式为 `{provider}:{account}:{kind}`。文件存储不依赖 Keychain，rebuild 后凭证不会丢失。

## 项目结构

```
gui/
├── Package.swift                  # SPM 配置，依赖 SwiftSoup + Yams
├── TokenDashboard/
│   ├── TokenDashboardApp.swift    # App 入口，MenuBarExtra + Window
│   ├── Models/
│   │   ├── ProviderId.swift       # Provider 枚举
│   │   ├── QuotaWindow.swift      # 配额窗口模型
│   │   └── UsageSnapshot.swift    # 用量快照模型
│   ├── Adapters/
│   │   ├── AdapterProtocol.swift  # Adapter 协议 + 默认实现
│   │   ├── AdapterRegistry.swift  # Provider 注册表
│   │   ├── CookieHelper.swift     # Cookie 格式化工具
│   │   ├── OpenCodeAdapter.swift  # HTML 解析 + JS hydration fallback
│   │   ├── MiniMaxAdapter.swift   # MiniMax API
│   │   ├── MiMoAdapter.swift      # MiMo API
│   │   ├── XunfeiAdapter.swift    # 讯飞 API
│   │   └── DeepSeekAdapter.swift  # DeepSeek API
│   ├── Store/
│   │   ├── CredentialStore.swift  # 文件存储凭证
│   │   ├── ConfigStore.swift      # config.yaml 读取
│   │   ├── UsageFetcher.swift     # 数据获取调度
│   │   └── SharedDefaults.swift   # App Group UserDefaults
│   ├── Views/
│   │   ├── MenuBarView.swift      # 菜单栏弹出面板
│   │   ├── ProviderCardView.swift # Provider 用量卡片
│   │   ├── UsageBarView.swift     # 用量进度条
│   │   └── SettingsView.swift     # 设置窗口
│   └── MenuBar/
│       └── MenuBarView.swift      # （同 Views/MenuBarView）
└── TokenDashboardTests/           # 35 个单元测试
```

## 技术栈

- **语言**：Swift 5.9+
- **最低版本**：macOS 13+
- **UI 框架**：SwiftUI（MenuBarExtra + Window）
- **依赖**：
  - [SwiftSoup](https://github.com/scinfu/SwiftSoup) — HTML 解析
  - [Yams](https://github.com/jpsim/Yams) — YAML 配置读取
- **凭证存储**：文件系统（`~/.token-dashboard/credentials/`）
- **构建**：Swift Package Manager
- **测试**：XCTest

## 与 CLI 版本的关系

- 共享 `~/.token-dashboard/config.yaml` 配置文件
- 凭证存储独立（CLI 用 `credentials.json`，GUI 用 `credentials/` 目录）
- 所有 adapter 逻辑纯 Swift 重写，无 Python 依赖
- 数据模型与 CLI 版兼容（snake_case JSON CodingKeys）

## 已知限制

1. **Cookie 有效期**：cookie 会过期，需要重新添加
2. **OpenCode workspace ID**：自动获取依赖 `/workspace/usage` 页面重定向时保留 cookie，部分情况下可能失败，需手动填写
3. **菜单栏图标**：目前使用系统默认图标，待替换为自定义图标
4. **ControlWidget**：macOS 26+ 系统控制中心小组件，需要 macOS 26 SDK，暂未实现
5. **内存占用**：约 80-100MB（SwiftUI 开销），可接受但有优化空间

## 未来规划

- 自定义菜单栏图标
- macOS 26 ControlWidget 支持
- 用量阈值通知（macOS Notification Center）
- 历史数据存储与趋势图
- 更多 provider（智谱 GLM、阿里云百炼、火山方舟）
