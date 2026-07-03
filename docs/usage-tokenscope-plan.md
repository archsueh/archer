# Usage × tokenscope 集成方案

> 目标:把 [tokenscope](https://github.com/HduSy/tokenscope)(Tauri/Rust 菜单栏 app,仅 Claude)的**增量价值**搬进 archer 原生 Swift `Sources/ArcherKit/Usage/`。
> 原则:借鉴数据源与算法,**不移植其外壳**(架构不兼容)。小 PR,逐 Stage 落地。
> 状态:草案 · 待评审后实施 · 参 `STATE.md` §3(工作树未提交 Dashboard)

## 0. 定位:archer 已有 vs tokenscope 增量

archer Usage 采集广度已强于 tokenscope(五源 Claude/Codex/Hermes/Grok/proxy、token 六项拆分、去重、增量缓存,见 `UsageModels.swift` / `UsageCollector.swift`)。**只需补三项增量:**

| 增量 | 现状缺口 | Stage |
|---|---|---|
| models.dev 动态定价 + 缓存 + fallback | 定价硬编码在 `estimateCost`,且两处 drift | 1 |
| 全年 heatmap + cost donut | 只有 ~7–8 天条形/圈图 | 2 |
| 按 MCP / 按 Skill 成本归因 | 完全没有该维度 | 3 |

---

## Stage 0 — 清理脏工作树(前置,非本特性)

按 `STATE.md` §3/§5 的 Next 先落地未提交的 Sessions Dashboard,拿到干净基线:

1. `swift test` — 确认 `SessionDashboardTests` 通过。
2. 按 `STATE.md` §2「NSWindow 生命周期」复核 `SessionsWindowController`(新窗口):`isReleasedWhenClosed`、是否在 `windowControllers`、`handleWindowWillClose` cascade。
3. 决定 `.grok/`、`.xcodebuildmcp/` 是否入 `.gitignore`。
4. 提交 Dashboard 特性 + 伴随的 `AppDelegate.swift`/`UsageCollector.swift` 改动。
5. 走前更新 `STATE.md`。

> 完成后再开 Stage 1,避免新特性和 Dashboard 搅进一个大 diff。

---

## Stage 1 — PricingProvider(最高性价比,含 bug 修复)

### 要解决的现有缺陷
成本在两处各自硬编码,已在 drift:
- `UsageCollector.swift:1277-1286` `estimateCost`(opus 15/75/18.75/1.5、sonnet 3/15/3.75/0.3、gpt-5.5 5/0.5/30…)
- `UsageView.swift:1146-1148` 内联 sonnet 3.0/15.0/0.30

违反 `STATE.md` §2「单一派生」。Stage 1 收敛成唯一定价源。

### 新增
`Sources/ArcherKit/Usage/PricingProvider.swift`

```
struct ModelPrice {            // 单位:USD / 1M tokens
    var input: Double
    var output: Double
    var cacheWrite: Double     // = cacheCreation
    var cacheRead: Double
}

actor PricingProvider {
    static let shared = PricingProvider()
    func price(for model: String, tool: String) -> ModelPrice   // 命中链见下
    func refreshIfStale() async                                 // 24h TTL
}
```

### 价格解析链(逐级 fallback,任一步命中即返回)
1. **记录自带成本**:`UsageRecord.costUSD != nil`(Codex/proxy SQLite 的 `estimated_cost_usd`/`total_cost_usd`)—— 保持现状,最高优先,PricingProvider 不覆盖。
2. **models.dev 缓存**:`~/.archer/pricing-cache.json`,24h TTL。
3. **models.dev 网络**:`GET https://models.dev/api.json`,成功后写缓存。
   - ⚠️ 待核实字段:确认 `cost.{input,output,cache_read,cache_write}` 的**单位**(per-1M 还是 per-token)与模型 key 命名,写一个到 `ModelPrice` 的 adapter。
4. **LiteLLM fallback**(可选,tokenscope 也用):其 pricing JSON 为 per-token,需 ×1e6。
5. **内置快照**:把当前 `estimateCost` 的硬编码表原样挪进 `PricingProvider` 作为最终兜底(离线/首启可用)。

### 模型匹配
沿用 `estimateCost` 现有的 `lowercased().contains("opus"/"sonnet"/"gpt-5.5")` 模糊匹配思路;models.dev 精确 key 匹配失败时降级到该模糊匹配,再降级到快照。

### 改造点(单一派生)
- `estimateCost(usage:tool:model:)` 改为:取 `PricingProvider.price(...)` → 复用现有 `costByParts`/`openAICostByParts` 计算(算法不变,只换价来源)。
- `UsageView.swift:1146-1148` 删掉内联数字,改调同一入口。
- 网络失败/首次启动:静默用快照,不阻塞 UI;`SourceInfo` 可加一个 `pricingSource: "models.dev|snapshot"` 字段供诊断(可选)。

### 验证
- 单测:给定固定 token 分项 + 快照价,`estimateCost` 输出与旧值逐位一致(防回归)。
- 断网跑一次:确认 fallback 到快照、UI 不卡。
- 有网跑一次:确认 `pricing-cache.json` 生成、24h 内二次启动不重复请求。

---

## Stage 2 — 全年 heatmap + cost donut(纯视图,低风险)

不碰采集层,只加 SwiftUI 视图,数据来自现成的 `UsageSnapshot.daily` / `records`。

- **年度 heatmap**:`Sources/ArcherKit/Usage/YearHeatmapView.swift`。GitHub 式 53×7 网格,色阶按当日 `totalTokens`(或 `cost`)分位。需把采集窗口从当前 ~7–8 天(`UsageCollector.swift:1004`、`UsageView.swift:74` 的 `-8`)扩到 365 天——**注意成本**:全量重扫 jsonl 可能慢,依赖 §增量缓存 `CollectorCache`;必要时 heatmap 单独走一条"仅按天聚合、不留明细"的轻量聚合,避免把一年 records 全驻内存。
- **cost donut**:`Sources/ArcherKit/Usage/CostDonutView.swift`。按模型(或按工具)切分当期成本;复用 `ModelUsage`/`DailyUsage.models`。配色走 `Theme`,遵守 Glass 基线(`STATE.md` §2,勿碰 `glassOpacity` 等三值)。

### 验证
- 用固定 snapshot 渲染,快照对比 or 手测:heatmap 空日/峰值日配色正确;donut 各扇区比例求和=100%。

---

## Stage 3 — 按 MCP / 按 Skill 成本归因(最重,独立 PR)

tokenscope 的能力:回答"哪个 MCP server / 哪个 Skill 最烧 token"。archer 现无此维度。

### 数据来源
- MCP 清单:`~/.claude.json`(archer 已知路径)。
- Skills:`~/.claude/skills/`(archer Skills 面板已在扫,可复用其扫描器)。
- 归因信号:Claude Code jsonl 的 assistant turn 里,`tool_use` 块的名字(MCP 工具通常形如 `mcp__<server>__<tool>`;Skill 调用体现为 `Skill`/skill 名)。

### 归因算法(草案,需先做数据勘探)
1. 解析每个 assistant turn:该 turn 的 `usage`(token)+ 该 turn 触发的 tool_use 名称集合。
2. 把 turn 的 token/成本按规则分摊到 MCP server / Skill:
   - 简化版:**turn 级归属**——若该 turn 调了某 MCP 工具,把整 turn 成本记到该 server(多工具时可均摊或记"混合")。
   - 说明口径:这是"关联成本"非"纯增量成本",UI 需标注避免误读。
3. 新增聚合维度 `mcpUsage: [ToolUsage]` / `skillUsage: [ToolUsage]`,复用现有 `TokenRankView` 展示。

### 风险
- jsonl 的 tool_use ↔ usage 对应关系需**先勘探真实数据**再定口径(先写个一次性脚本抽样,别拍脑袋)。
- 仅 Claude Code 有此结构;Codex/Grok 归因口径不同,首版可只做 Claude。

### 验证
- 抽样若干 session 人工核对归因;跨源缺失时降级为"未归因"桶,不报错。

---

## 落地顺序与 PR 切分
1. **PR-0**:Stage 0 Dashboard 落地(已在 §3 待办)。
2. **PR-1**:Stage 1 PricingProvider + 收敛两处 drift + 单测。
3. **PR-2**:Stage 2 heatmap + donut。
4. **PR-3**:Stage 3 MCP/Skill 归因(前置一次数据勘探)。

每个 PR 走前更新 `STATE.md`;PR-1 完成后把"定价单一源"写进 §2 General rules。
