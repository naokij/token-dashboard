# Token Dashboard 项目文档

> 更新日期：2026-06-06

## 1. 项目概述

### 1.1 背景

当前 AI 编程助手市场存在多个提供商（OpenCode、MiniMax、小米 MiMo、讯飞星辰、DeepSeek），每个提供商都有独立的计费和用量查看系统。开发者如果同时使用多个服务，需要分别登录各个控制台查看剩余额度，操作繁琐且缺乏统一视图。

### 1.2 目标

构建一个统一的 CLI 工具，让用户能够在一个界面中查看所有 AI 服务的用量和配额状态，支持持续监控。

### 1.3 目标用户

- 同时使用多个 AI 编程助手的开发者
- 需要监控 API 用量以控制成本的团队

### 1.4 项目结构

```
token-dashboard/
├── src/td/
│   ├── cli.py              # Click CLI 入口
│   ├── models.py           # 数据模型
│   ├── config.py           # 配置和凭证管理
│   ├── output.py           # Rich 输出格式化
│   ├── cookies.py          # Cookie 管理
│   └── adapters/
│       ├── base.py         # Adapter 基类
│       ├── registry.py     # Provider 注册表
│       ├── opencode.py     # OpenCode Go
│       ├── minimax.py      # MiniMax Token Plan
│       ├── mimo.py         # Xiaomi MiMo
│       ├── xunfei.py       # 讯飞星辰
│       └── deepseek.py     # DeepSeek
├── docs/
│   ├── project.md          # 项目文档
│   └── competitive-analysis.md  # 竞品分析
├── tests/
├── pyproject.toml
└── README.md
```

---

## 2. 功能需求

### 2.1 Provider 管理

#### 支持的 Provider

| Provider | 计价方式 | 数据源 | 认证方式 | 必需 Cookie |
|----------|----------|--------|----------|-------------|
| OpenCode Go | 5h/周/月限额（百分比） | HTML 解析 | cookie | `auth` |
| MiniMax Token Plan | 5h + 周窗口（百分比） | API | api_key | - |
| 小米 MiMo | Token Plan + 按量付费 | API | cookie | `api-platform_serviceToken`, `userId` |
| 讯飞星辰 Coding Plan | 请求次数 | API | cookie | `ssoSessionId` |
| DeepSeek | 按量付费（余额） | API | api_key | - |

#### Provider 详细实现

**OpenCode Go**
- 数据源：`GET https://opencode.ai/workspace/{workspace_id}/go`（HTML 解析）
- 必需 Cookie：`auth`
- 支持中文和英文界面
- workspace_id 从页面自动提取

**MiniMax Token Plan**
- 数据源：`GET https://www.minimaxi.com/v1/token_plan/remains`
- 认证：API Key（Bearer token）
- 返回各模型（general/video）的 5h 和周窗口使用百分比

**Xiaomi MiMo**
- 数据源：
  - 按量付费余额：`GET https://platform.xiaomimimo.com/api/v1/balance`
  - 套餐用量：`GET https://platform.xiaomimimo.com/api/v1/tokenPlan/usage`
- 必需 Cookie：`api-platform_serviceToken`, `userId`
- 支持 Token Plan 和按量付费两种模式

**讯飞星辰 Coding Plan**
- 数据源：`GET https://maas.xfyun.cn/api/v1/gpt-finetune/coding-plan/list`
- 必需 Cookie：`ssoSessionId`
- 返回 5h、周、套餐总量的使用次数

**DeepSeek**
- 数据源：`GET https://api.deepseek.com/user/balance`
- 认证：API Key（Bearer token）
- 返回余额信息（CNY/USD）

#### Provider 列表查看

- 命令：`td list`
- 显示内容：Provider ID、名称、类型、配置状态、支持的认证方式
- 输出格式：Rich 表格

### 2.2 认证管理

#### Cookie 认证

- 命令：`td login <provider_id> -c <cookie>`
- 支持多账号，通过 `-a` 参数指定账号名称（默认为 "default"）

**如何获取 Cookie**：

1. 用浏览器打开 provider 网站并登录
2. 按 F12 打开 DevTools
3. 切换到 Network 标签，刷新页面
4. 右键点击任意请求 -> Copy -> Copy as cURL
5. 从 cURL 命令中提取 `-b '...'` 部分的 cookie

**Provider 网站**：
- OpenCode: https://opencode.ai/auth
- MiMo: https://platform.xiaomimimo.com
- 讯飞: https://maas.xfyun.cn

**示例**：
```bash
td login opencode -c 'auth=Fe26.2**...'
td login mimo -c 'api-platform_serviceToken="xxx"; userId=123'
td login xunfei -c 'ssoSessionId=xxx'
```

#### API Key 认证

- 命令：`td add <provider_id> --api-key <key> [-a <account>]`
- 存储方式：keyring 优先，文件兜底
- MiniMax 和 DeepSeek 仅支持 API key（无需 cookie）
- 支持多账号，通过 `-a` 参数指定账号名称（默认为 "default"）

#### 凭证重置

- 命令：`td reset <provider_id> [-a <account>]`
- 支持 `-y` 跳过确认
- 清除该 provider 的所有凭证（api_key 和 cookie）
- 如果指定 `-a` 参数，只清除该账号的凭证

### 2.3 用量查询

#### 一次性状态查看

- 命令：`td status`
- 选项：
  - `-p, --provider <id>`：限制到特定 provider（可多次指定）
  - `-a, --account <name>`：限制到特定账号
  - `--json`：输出 JSON 格式
  - `--raw`：包含原始数据
  - `--no-color`：禁用颜色输出
- 输出内容：Provider、Plan、Account、Window、Usage、Bar、Resets

#### 持续监控

- 命令：`td watch`
- 选项：
  - `-p, --provider <id>`：限制到特定 provider
  - `-i, --interval <seconds>`：刷新间隔（默认 60s）
  - `--once`：渲染一次后退出
- 显示格式：紧凑单行视图
- 支持 Ctrl-C 退出

#### 数据导出

- 命令：`td export <path>`
- 输出格式：JSON
- 包含所有 provider 的快照数据

### 2.4 配置管理

#### 查看配置

- 命令：`td config --show`
- 显示内容：配置文件路径、数据目录、凭证路径、配置内容

#### 配置文件

- 路径：`~/.token-dashboard/config.yaml`
- 可通过 `TD_CONFIG_DIR` 环境变量覆盖
- 配置项：

```yaml
providers:
  opencode: { enabled: true, auth: cookie }
  minimax: { enabled: true, auth: api_key }
  mimo:    { enabled: true, auth: cookie }
  xunfei:  { enabled: true, auth: cookie }
  deepseek: { enabled: true, auth: api_key }

alerts:
  warn_pct: 70       # 黄色警告阈值
  critical_pct: 90   # 红色告警阈值

watch:
  interval_seconds: 60

display:
  currency_preference: original  # original | cny | usd
  show_raw: false
```

---

## 3. 数据模型

### 3.1 ProviderId

枚举值：`opencode`, `minimax`, `mimo`, `xunfei`, `deepseek`

### 3.2 PlanKind

| 类型 | 说明 |
|------|------|
| `coding_plan` | 固定月度订阅，按请求数/次数计费 |
| `token_plan` | 固定月度订阅，按 token 积分计费 |
| `pay_as_you_go` | 按量付费，持续扣费 |

### 3.3 QuotaUnit

| 单位 | 说明 |
|------|------|
| `credits` | Provider 特定积分 |
| `tokens` | Token 数量 |
| `requests` | 请求数量 |
| `usd` | 美元 |
| `cny` | 人民币 |
| `prompts` | Prompt 数量 |
| `percent` | 百分比 |
| `unknown` | 未知单位 |

### 3.4 WindowKind

| 窗口类型 | 说明 |
|----------|------|
| `rolling_5h` | 5 小时滚动窗口 |
| `rolling_week` | 周滚动窗口 |
| `rolling_month` | 月滚动窗口 |
| `calendar_month` | 日历月 |
| `calendar_day` | 日历日 |
| `fixed_period` | 固定订阅周期 |
| `balance` | 按量付费余额（无重置） |

### 3.5 QuotaWindow

| 字段 | 类型 | 说明 |
|------|------|------|
| `kind` | WindowKind | 窗口类型 |
| `label` | str | 人类可读标签 |
| `used` | float | 已使用量 |
| `limit` | float \| None | 限额（None 表示无限制） |
| `remaining` | float \| None | 剩余额度 |
| `unit` | QuotaUnit | 计量单位 |
| `used_pct` | float \| None | 使用百分比 0..100 |
| `reset_at` | datetime \| None | 窗口重置时间 |
| `raw` | dict | 原始 provider 数据 |

### 3.6 UsageSnapshot

| 字段 | 类型 | 说明 |
|------|------|------|
| `provider` | ProviderId | Provider ID |
| `fetched_at` | datetime | 获取时间 |
| `plan_name` | str \| None | 计划名称 |
| `plan_kind` | PlanKind | 计划类型 |
| `balance` | float \| None | 按量付费余额 |
| `balance_unit` | QuotaUnit \| None | 余额单位 |
| `windows` | list[QuotaWindow] | 配额窗口列表 |
| `account_name` | str | 账号名称（多账号支持） |
| `account_email` | str \| None | 账户邮箱 |
| `auth_mode` | str | 数据获取方式 |
| `warnings` | list[str] | 警告信息 |
| `raw` | dict | 原始数据 |

---

## 4. 技术实现

### 4.1 数据获取策略

- **API** — 调用 provider API 获取用量数据（MiniMax、DeepSeek、MiMo、讯飞）
- **HTML 解析** — 解析 provider 网页获取用量数据（OpenCode Go）
- **错误处理** — 获取失败时给出明确提示，不假装有数据

### 4.2 凭证存储

- **优先**：操作系统 keyring（macOS Keychain）
- **兜底**：`~/.token-dashboard/credentials.json`（chmod 600）
- **格式**：`td:<provider>:<account>:<kind>` 为键存储 JSON

### 4.3 配置管理

- 配置目录：`~/.token-dashboard/`
- 可通过环境变量覆盖：
  - `TD_CONFIG_DIR`：配置目录
  - `TD_DATA_DIR`：数据目录
- 深度合并：用户配置覆盖默认配置

### 4.4 输出格式

- **表格视图**：Rich 表格，支持颜色
- **JSON 视图**：机器可读格式
- **Watch 视图**：紧凑单行，带时间戳
- **进度条**：文本进度条，按百分比着色（<70% 绿色，70-90% 黄色，>90% 红色）

### 4.5 可扩展性

- Adapter 模式：每个 provider 实现 `Adapter` 基类
- 注册表模式：`REGISTRY` 字典映射 ProviderId 到 Adapter 类
- 新增 provider 只需：
  1. 在 `ProviderId` 枚举中添加
  2. 实现 Adapter 子类
  3. 注册到 `REGISTRY`

---

## 5. CLI 命令

| 命令 | 说明 |
|------|------|
| `td list [--accounts]` | 列出所有 provider 及配置状态 |
| `td status [--provider <id>] [-a <account>] [--json] [--raw] [--no-color]` | 查看当前用量 |
| `td watch [--provider <id>] [--interval <s>] [--once]` | 持续监控 |
| `td login <provider_id> -c <cookie> [-a <account>]` | 保存 cookie |
| `td add <provider_id> --api-key <key> [-a <account>]` | 添加 API key |
| `td export <path>` | 导出 JSON 快照 |
| `td config --show` | 查看配置 |
| `td config --path` | 打印配置路径 |
| `td reset <provider_id> [-a <account>] [-y]` | 重置凭证 |
| `td --version` | 显示版本 |
| `td --config <path>` | 指定配置文件 |

**使用示例**：

```bash
# 添加 API key
td add minimax --api-key sk-cp-...
td add deepseek --api-key sk-...

# 保存 cookie
td login opencode -c 'auth=Fe26.2**...'
td login mimo -c 'api-platform_serviceToken="xxx"; userId=123'
td login xunfei -c 'ssoSessionId=xxx'

# 查看用量
td status                    # 所有 provider
td status -p minimax         # 单个 provider
td status -p deepseek -a main  # 指定账号

# 持续监控
td watch
td watch -i 30               # 30 秒刷新

# 导出数据
td export snapshot.json
```

---

## 6. 技术栈

- **语言**：Python 3.11+
- **依赖**：click, rich, pydantic, httpx, pyyaml, keyring, platformdirs, pyperclip, beautifulsoup4
- **构建**：hatchling
- **包管理**：uv
- **Lint**：ruff (line-length=100, target-version=py311)
- **测试**：pytest, pytest-asyncio

---

## 7. 已知限制

1. **Cookie 有效期**：cookie 可能过期，需要重新登录
2. **OpenCode**：需要手动提供 workspace_id（从 URL 中获取）
3. **DeepSeek**：只有余额查询，没有用量统计

---

## 8. 未来规划

- **Phase 2**：套 Tauri / PyObjC 壳，做 macOS 菜单栏常驻小组件
- **更多 provider**：智谱 GLM、阿里云百炼、火山方舟
- **告警系统**：阈值突破时通过 macOS Notification Center、Slack、邮件通知
- **历史数据**：存储到本地 SQLite，画趋势图
