# Token Dashboard

统一的 AI 服务用量查看器，支持 OpenCode、MiniMax、MiMo、讯飞、DeepSeek。

- **CLI**：Python 终端工具，`td status` / `td watch` 查看用量
- **GUI**：macOS 菜单栏应用，原生 Swift/SwiftUI，无 Python 依赖 → [GUI 文档](docs/gui.md)

## 支持的 Provider

| Provider | 计价方式 | 数据源 | 认证方式 |
|----------|----------|--------|----------|
| OpenCode Go | 5h/周/月限额（百分比） | HTML 解析 | cookie |
| MiniMax Token Plan | 5h + 周窗口（百分比） | API | api_key |
| Xiaomi MiMo | Token Plan + 按量付费 | API | cookie |
| 讯飞星辰 Coding Plan | 请求次数 | API | cookie |
| DeepSeek | 按量付费（余额） | API | api_key |

## 安装

需要 Python 3.11+ 和 [uv](https://docs.astral.sh/uv/)。

```bash
cd token-dashboard
uv sync
```

## 快速开始

### 1. 查看 Provider 列表

```bash
uv run td list
```

### 2. 添加凭证

**API key 方式**（MiniMax、DeepSeek）：
```bash
uv run td add minimax --api-key sk-cp-...
uv run td add deepseek --api-key sk-...
```

**Cookie 方式**（OpenCode、MiMo、讯飞）：

1. 用浏览器打开 provider 网站并登录
2. 按 F12 打开 DevTools
3. 切换到 Network 标签，刷新页面
4. 右键点击任意请求 -> Copy -> Copy as cURL
5. 从 cURL 命令中提取 `-b '...'` 部分的 cookie

```bash
uv run td login opencode -c 'auth=xxx; ...'
uv run td login mimo -c 'api-platform_serviceToken="xxx"; userId=123'
uv run td login xunfei -c 'ssoSessionId=xxx'
```

Provider 网站：
- OpenCode: https://opencode.ai/auth
- MiMo: https://platform.xiaomimimo.com
- 讯飞: https://maas.xfyun.cn

### 3. 查看用量

```bash
uv run td status            # 所有 provider
uv run td status -p minimax # 单个 provider
uv run td status --json     # JSON 格式
```

### 4. 持续监控

```bash
uv run td watch             # 默认 60s 刷新
uv run td watch -i 30       # 30s 刷新
```

### 5. 导出数据

```bash
uv run td export snapshot.json
```

### 6. 配置

```bash
uv run td config --show
```

编辑 `~/.token-dashboard/config.yaml`：

```yaml
providers:
  opencode: { enabled: true, auth: cookie }
  minimax: { enabled: true, auth: api_key }
  mimo:    { enabled: true, auth: cookie }
  xunfei:  { enabled: true, auth: cookie }
  deepseek: { enabled: true, auth: api_key }

alerts:
  warn_pct: 70
  critical_pct: 90

watch:
  interval_seconds: 60
```

### 7. 重置凭证

```bash
uv run td reset opencode
uv run td reset minimax -a main  # 指定账号
```

## Cookie 需求

| Provider | 必需 Cookie |
|----------|-------------|
| OpenCode | `auth` |
| MiMo | `api-platform_serviceToken`, `userId` |
| 讯飞 | `ssoSessionId` |
| MiniMax | 不需要（用 API key） |
| DeepSeek | 不需要（用 API key） |

## 项目结构

```
src/td/
├── cli.py              # Click CLI
├── models.py           # 数据模型
├── config.py           # 配置和凭证管理
├── output.py           # Rich 输出格式化
├── cookies.py          # Cookie 管理
└── adapters/
    ├── base.py         # Adapter 基类
    ├── registry.py     # Provider 注册表
    ├── opencode.py     # OpenCode Go
    ├── minimax.py      # MiniMax Token Plan
    ├── mimo.py         # Xiaomi MiMo
    ├── xunfei.py       # 讯飞星辰
    └── deepseek.py     # DeepSeek
```

## 技术栈

- Python 3.11+
- click, rich, pydantic, httpx, pyyaml, keyring, platformdirs, beautifulsoup4
- 构建：hatchling
- 包管理：uv
- Lint：ruff
- 测试：pytest

## 未来规划

- **更多 provider**：智谱 GLM、阿里云百炼、火山方舟
- **告警系统**：阈值突破时通知
- **历史数据**：SQLite 存储，趋势图
- **macOS ControlWidget**：系统控制中心小组件（需 macOS 26 SDK）

## License

MIT
