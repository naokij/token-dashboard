# 竞品分析：AI 服务用量统一监控

> 调研日期：2026-06-04

---

## 1. 发现的相似项目

| 项目 | Stars | 形态 | 技术栈 | 支持 Provider 数 | 链接 |
|------|-------|------|--------|-----------------|------|
| **AIMeter** | 15 | Web 自托管 | React + Express + TS | 12+ | github.com/bugwz/AIMeter |
| **AiBal** | 26 | macOS 菜单栏 | Tauri + Vue 3 + Rust | 5+ | github.com/DDG0808/aibal |
| **factory-ai-usage** | 8 | Web 单页 | Vue + Vite | 1 | github.com/evergood2025/factory-ai-usage |

---

## 2. 详细对比

### 2.1 AIMeter

**定位**：自托管的 AI 用量仪表板，支持多 provider、多部署方式

**特点**：
- 支持 12+ provider：OpenCode、MiniMax、Claude、Cursor、Copilot、Kimi、Aliyun、Codex、OpenRouter、Ollama 等
- Web 应用，前后端分离（React + Express）
- 支持多种部署：Docker、Vercel、Cloudflare Workers
- 多数据库支持：SQLite、D1、PostgreSQL、MySQL
- 有使用历史和图表功能
- 有 endpoint/proxy 管理功能

**优势**：
- Provider 覆盖最全
- 部署方式灵活
- 社区活跃度尚可

**劣势**：
- 需要自托管，有运维成本
- Web 形态，不如桌面应用方便
- 依赖外部数据库

**与我们的差异**：
- 我们是 CLI 工具，AIMeter 是 Web 应用
- 我们聚焦国内 provider（OpenCode、MiniMax、MiMo、讯飞），AIMeter 更国际化
- 我们用 cookie 抓取，AIMeter 可能用 API key

---

### 2.2 AiBal

**定位**：macOS 菜单栏 AI 用量监控应用

**特点**：
- macOS 原生菜单栏应用（Tauri 2.x）
- 插件系统，可扩展 provider
- 插件市场，社区贡献
- 深色模式
- 支持 Claude、GPT、Gemini 等

**优势**：
- macOS 原生体验，菜单栏常驻
- 插件架构，扩展性强
- 用户体验好

**劣势**：
- 仅限 macOS
- 插件生态初期
- 不支持国内 provider（OpenCode、MiniMax、MiMo、讯飞）

**与我们的差异**：
- 我们是 CLI，AiBal 是桌面应用
- 我们专注国内 provider，AiBal 专注国际 provider
- 我们的 Phase 2 规划正是 AiBal 的形态（macOS 菜单栏）

---

### 2.3 factory-ai-usage

**定位**：Factory AI 专用用量查看工具

**特点**：
- 单一 provider（Factory AI）
- Web 单页应用
- API key 存储在浏览器 localStorage
- 支持多 key 管理和批量操作

**优势**：
- 简单轻量
- 专注单一 provider，体验好

**劣势**：
- 只支持一个 provider
- 功能单一

**与我们的差异**：
- 我们支持多 provider，它是单 provider
- 我们是 CLI，它是 Web

---

## 3. 市场空白分析

| 维度 | 现有方案 | 空白 |
|------|----------|------|
| **形态** | Web 自托管 / macOS 桌面 | CLI 工具较少 |
| **Provider 覆盖** | 国际为主（Claude、GPT、Gemini） | 国内为主（OpenCode、MiniMax、MiMo、讯飞）的统一监控缺失 |
| **认证方式** | 多用 API key | Cookie 抓取方式较少（适合无公开 API 的场景） |
| **部署复杂度** | Web 需要服务器/数据库 | 零配置 CLI 工具有需求 |

---

## 4. 我们的差异化优势

1. **国内 provider 聚焦**：OpenCode、MiniMax、MiMo、讯飞都是国内主流 AI 编程助手，目前没有统一监控工具

2. **CLI 优先**：开发者友好，无需部署服务器，`uv run td status` 即用

3. **Cookie 抓取**：解决「无公开用量 API」的痛点，通过浏览器登录 + cookie 保存实现数据获取

4. **零依赖部署**：Python + uv，不需要 Docker/数据库/云服务

5. **Phase 2 可扩展**：计划做 macOS 菜单栏，可复用 adapter 层

---

## 5. 建议

### 可以借鉴

- **AIMeter 的 provider 架构**：adapter 模式我们已经有了，可以参考它支持更多 provider
- **AiBal 的插件系统**：未来可以考虑让社区贡献 provider adapter
- **factory-ai-usage 的批量操作**：多 key 管理是实用功能

### 可以合作

- **AiBal**：我们的 adapter 可以移植为 AiBal 的插件，覆盖国内 provider
- **AIMeter**：我们的 cookie 抓取逻辑可以贡献给 AIMeter

### 继续独立开发的理由

1. 国内 provider 的统一监控确实是空白
2. CLI 形态有其独特价值（脚本化、管道化、快速查看）
3. Cookie 抓取是我们的核心技术积累
4. Phase 2 的 macOS 菜单栏可以与 AiBal 互补

---

## 6. 结论

**我们的项目有明确的市场定位**：国内 AI 编程助手的 CLI 用量监控工具。

现有竞品主要覆盖国际 provider，形态以 Web 为主。我们聚焦国内 provider + CLI 形态 + Cookie 抓取，填补了这个细分市场的空白。

建议继续开发，同时关注 AIMeter 和 AiBal 的进展，寻找合作机会。
