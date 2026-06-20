# GUI 内存优化 - 实施记录

## 背景

GUI 版本（Swift/SwiftUI macOS 菜单栏应用）内存占用偏高，需要优化。

## 优化分两阶段

### 阶段一：数据层优化

| 优化项 | 文件 | 说明 |
|--------|------|------|
| 移除 QuotaWindow.raw 冗余填充 | MiniMax/Xunfei/MiMo Adapter | 同一 API dict 被转换为 JSONValue 存入多个窗口 |
| 移除 UsageSnapshot.raw 冗余填充 | MiniMax/Xunfei/DeepSeek Adapter | 完整 API 响应存入 snapshot，GUI 无任何消费方 |
| 清理 ParsedAPI.raw / ParsedBalance.raw | MiniMax/DeepSeek Adapter | 中间类型不再需要 raw 字段 |
| SharedDefaults 条件保存 | SharedDefaults.swift | 数据未变时跳过 JSON 编码+UserDefaults 写入 |
| URLSession.shared 替代自定义 session | OpenCodeAdapter.swift | 消除每次 fetch 创建 URLSession 泄漏 |
| TaskGroup 并行 fetch | UsageFetcher.swift | 总耗时从 N 个 provider 之和降到最长那个 |
| CredentialStore 内存缓存 + NSLock | CredentialStore.swift | 消除每分钟 10+ 次文件 I/O |
| DateFormatter / RelativeDateTimeFormatter 静态缓存 | XunfeiAdapter / MenuBarView | 避免每次创建 |
| SettingsView 共享 CredentialStore/AdapterRegistry | SettingsView / TokenDashboardApp | 消除重复实例 |
| 变化检测跳过不必要的 @Published 更新 | UsageFetcher.swift | 数据未变时不触发 SwiftUI 重渲染 |

**实测结果**：UserDefaults snapshots 数据从 10,224 bytes 降至 2,832 bytes（-72.3%），但 App 总 RSS 无可测量变化（业务数据只占 ~7KB vs 总内存 ~100MB）。

### 阶段二：渲染层优化（主要收益）

| 优化项 | 文件 | 说明 |
|--------|------|------|
| 移除 .ultraThinMaterial 毛玻璃背景 | ProviderCardView.swift | 每个卡片创建 GPU 合成层，5 个 provider = 5 个合成层 |
| 移除 GeometryReader 改用固定宽度 | UsageBarView.swift | 消除额外布局 pass，减少属性图节点 |
| Settings Window onDisappear 回收激活策略 | TokenDashboardApp.swift | 关闭设置窗口时释放 .regular 激活策略 |
| 拆分 view 减少 @Published 重渲染范围 | MenuBarView.swift | 隔离 LoadingIndicator 和 SnapshotListView |

**实测结果（3 轮 90s 平均）**：

| 指标 | 优化前 | 优化后 | 变化 |
|------|--------|--------|------|
| RSS | 105,450 KB | 55,221 KB | **-47.6%** |
| Physical footprint | ~37 MB | ~19 MB | **-48.6%** |

## 验证工具

- `gui/TokenDashboardTests/MemoryMetricsTests.swift` — 自动化度量测试（序列化数据大小、raw 占比）
- `scripts/mem_benchmark.sh` — Instruments Allocations 命令行录制脚本
