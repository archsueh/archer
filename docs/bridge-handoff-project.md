# Project · Bridge-Native Handoff（GUI 可直接交接）

> **Goal**: 任意 agent（含本机 Grok / Claude / CLI）无需已打开目标 pane，就能经 Archer **打开** Hermes（或任意 agent）tab 并注入初始任务。  
> **Status**: **P0 MVP landed 2026-07-21**（openAgentTab + Bridge wire + CLI + GUI brief）  
> **Related backlog**: `agent-interop-layer`（会话列举/转换）是兄弟能力；**本项目更窄、更急**——先补「开 tab + 带 prompt」。

---

## 0. 问题陈述（你已核实的事实）

| 层 | 现状 | 缺口 |
|---|---|---|
| Bridge socket | `~/.archer/bridge.sock` 活着 | — |
| Wire cmds | `list` / `sync` / `read` / `type` / `keys` | **无 open / handoff / agents** |
| PaneRegistry | 只登记**当前 active workspace 里已有** pane 的 label | 没 Hermes pane → `list` 只有 `["grok"]` |
| GUI Hand off | 侧栏右键 → `addTab(in:ws, template:)` | **不传 `initialPrompt`**；桥接层接不到 |
| 底层 spawn | `WorkspaceStore.addTab(..., initialPrompt:)` + `AgentTemplate.makeSessionConfig(initialPrompt:)` | **已就绪**，GUI/Bridge 未用满 |

**一句话**：座舱内部「能开 tab」，对外协议「只能对已开 pane 打字」——交接半成品。

---

## 1. 产品目标（验收口径）

用户故事：

1. **作为** 正在跑的 Grok（或 shell 里的 `archer-bridge`），**我要** 把一段 handoff 文本交给 Hermes，**即使** 当前没有 Hermes 窗格。  
2. **作为** 人手，**我要** 在侧栏 Hand off 时可选「附带当前任务说明」，而不是开一个空白 agent tab。  
3. **作为** 座舱，**我要** 仍本地优先、不改 agent 本体、不引入远端服务。

**Done 定义（可测）**：

```bash
# Archer 运行中；当前只有 grok pane
archer-bridge list
# → grok

archer-bridge handoff hermes --prompt "Read STATE.md §5 and continue SSH hand-test. Repo wins."
# → ok, label=hermes (or hermes-2), sessionId=…

archer-bridge list
# → grok
# → hermes

archer-bridge read hermes 30
# → 屏幕里能看到 Hermes 已启动且 prompt 已进入（或在等首屏后 type 路径，见 §3.3）
```

GUI 并行验收：

- 侧栏「Hand off to… → Hermes」弹出/带入可选 prompt（默认空 = 旧行为空白 tab）。  
- ⌘P 新增 `Hand off to <agent>…`（或 `Open agent tab`）可搜 agent + 粘贴 prompt。  
- 交接后 focus 目标 tab（可选设置：是否抢前台窗口）。

---

## 2. 范围

### In scope（P0 MVP）

| ID | 交付 | 落点 |
|----|------|------|
| **P0.1** | Bridge `open` / `handoff` 命令 | `BridgeServer` + `PaneRegistry` 或 store 门面 |
| **P0.2** | `archer-bridge` CLI 子命令 | `Sources/ArcherBridge/main.swift` |
| **P0.3** | GUI Hand off 接 `initialPrompt` | `SidebarWorkspaceRow` / `SidebarView` 回调签名 |
| **P0.4** | 解析 agent id → `AgentTemplate` | 复用 `AgentTemplate.all` / `visibleOrdered`，**禁止**硬编码 `"hermes"` |
| **P0.5** | 单测 | Bridge handle JSON + store 门面；不测 PTY 真 Hermes |

### In scope（P1 体验）

| ID | 交付 |
|----|------|
| **P1.1** | ⌘P：`Hand off to <agent>` + 多行 prompt sheet |
| **P1.2** | Bridge `agents`：列出可交接 agent（id + displayName + installed?） |
| **P1.3** | `handoff` 支持 `workspace` 选择（path / id / active） |
| **P1.4** | 交接后可选 `focus:true` 把目标窗提到前台 |

### Out of scope（明确不做）

- 跨 agent **会话 resume**（Hermes resume id 捕获）——STATE §2 的 `--resume` 两层 guard 另案。  
- lemma 式 `AgentSessionProvider` 全量会话总线（BACKLOG A.5）——可后接。  
- 自动「Grok 写完就推 Hermes」无确认流水线——Archer 只提供门面，策略在用户/CLI。  
- 远程 HTTP Bridge / 鉴权网关——本地 unix socket `0600` 保持。  
- 改 Hermes CLI 本体。

---

## 3. 设计

### 3.1 核心语义：`handoff` = open + seed

```
handoff(agentId, prompt?, workspace?, cwd?, focus?)
  1. resolve AgentTemplate by id (all / visibleOrdered；unknown → error)
  2. resolve Workspace（default = storeProvider().active）
  3. store.addTab(in: ws, template: t, initialCwd: cwd, initialPrompt: prompt)
  4. PaneRegistry.sync(ws)
  5. return { ok, label, sessionId, agentId }
```

命名：

- Wire 推荐 **`handoff`**（产品语义）与 **`open`**（无 prompt 的子集，`open` ≡ `handoff` without prompt）。  
- 实现可只做一个 cmd，`prompt` 可选。

### 3.2 Wire 协议（向后兼容）

**不变**：`list` / `sync` / `read` / `type` / `keys` 响应形状不变。

**新增**：

```jsonc
// → open / handoff
{"cmd":"handoff","agent":"hermes","prompt":"…","focus":true}
// optional: "cwd":"/Users/…/repo", "workspace":"active"|"path:/…"|uuid

// ← success
{"ok":true,"label":"hermes","agent":"hermes","sessionId":"<uuid>"}

// ← failure
{"ok":false,"error":"unknown agent: hermes"}
{"ok":false,"error":"no active workspace"}
{"ok":false,"error":"agent not in order / not installed: …"}  // 仅当选 strict 模式
```

```jsonc
// → agents（P1）
{"cmd":"agents"}
// ←
{"ok":true,"agents":[{"id":"hermes","name":"Hermes","shell":false}, …]}
```

**严格模式（建议默认宽松）**：

- 默认：`AgentTemplate.all` 能解析即可开（含 custom agent）。  
- `strict:true`：仅 `visibleOrdered`（设置里 agent order 可见且非 shell）。与 GUI Hand off 的 `handoffTargets` 对齐。

### 3.3 Prompt 注入策略（关键）

底层已有 `initialPrompt` → `ARCHER_AGENT` 启动串（`AgentTemplate.launchCommand`）。  
**优先路径 A（推荐）**：handoff 走 `addTab(..., initialPrompt:)`，与「Ask &lt;agent&gt; / Parallel Task」同路径。

路径 B（降级，仅当 template 不支持 prompt 位）：

1. `addTab` 无 prompt  
2. 短等 / 轮询 `read` 直到屏幕非空或超时  
3. `type` prompt + `keys Enter`  

P0 **只实现 A**；B 记为 P2，避免假「已交付」的 flaky 等待。

Hermes 若是 **custom agent**（builtin 列表无 `hermes` 静态项时）：

- 必须用设置里的 custom `id` 解析；  
- 确认 custom 的 `promptLaunchFlag` / positional prompt 与 Hermes CLI 兼容；  
- 不兼容则 handoff 开空白 tab + 返回 warning，或拒绝并提示改 custom 配置。

### 3.4 GUI 接线

**现状**（`SidebarView`）：

```swift
onHandoff: { store.activateWorkspace(ws); store.addTab(in: ws, template: $0) }
```

**目标**：

```swift
// 回调升级
onHandoff: (AgentTemplate, String?) -> Void
// 或先加 overload：无 prompt 的菜单保持；「Hand off with brief…」子项带 sheet

store.addTab(in: ws, template: template, initialPrompt: brief?.nilIfEmpty)
```

菜单形态（二选一，实现时拍板）：

| 方案 | 交互 | 复杂度 |
|------|------|--------|
| **A 简** | 每个 agent 一行；长按 / ⌥-click 带 prompt sheet | 中 |
| **B 清** | 「Hand off to…」下列 agent；选中后始终出 sheet（可空） | 低，推荐 P0 |

⌘P（P1）：`PaletteItemKind.handoff(agentId:)` + prompt sheet，与 Parallel Task sheet 复用输入控件。

### 3.5 架构落点（避免 Bridge 变 God Object）

```
archer-bridge CLI
      │  unix JSON
      ▼
UnifiedListener → BridgeServer.handle
      │
      ▼
WorkspaceStore.handoff(agentId:prompt:…)   // 新门面，@MainActor
      │
      ├─ AgentTemplate.resolve(id)
      ├─ addTab(...)
      └─ PaneRegistry.sync → label
```

- **不要**在 `BridgeServer` 里复制 spawn 逻辑。  
- GUI Hand off 与 Bridge **共用** `WorkspaceStore.handoff`（或 `openAgentTab`），防第三套路径。  
- Reference Sweep：改签名后 grep `onHandoff` / `addTab` / `cmd` switch。

### 3.6 安全与多窗口

- Socket 已 `0600` owner-only；handoff 能开进程 → 仍仅本机同用户（与 type 同威胁模型）。  
- `storeProvider` 已存在（修过 first-window pin）；handoff **必须**走 `storeProvider?()`，禁止再钉死 `windowControllers.first`。  
- 默认 workspace = **当前 active**；多窗口时 CLI 用户应 `list`/`agents` 先确认，P1 再加 `workspace` 选择。

### 3.7 Label 稳定性

`PaneRegistry` 只登记 **activeTab** per pane，且同 agent 后缀 `hermes-2`。  
handoff 返回的 `label` 必须在 **同一次** `sync` 后计算，并写进响应；调用方应用返回值，不要猜 `"hermes"`。

可选 P1：`list` 扩字段 `{"labels":[{"label","agent","sessionId","cwd"}]}`——破坏最小的做法是保留 `labels: [String]` 并加 `panes: [...]`。

---

## 4. 任务分解（可直接派给实现 agent）

### Phase 0 — 契约与门面（0.5–1d）

- [ ] **T0.1** 在 `WorkspaceStore` 增加：

  ```swift
  @discardableResult
  func openAgentTab(
      agentId: String,
      prompt: String? = nil,
      in workspace: Workspace? = nil,
      initialCwd: URL? = nil,
      strictVisible: Bool = false
  ) throws -> (session: Session, label: String)
  ```

- [ ] **T0.2** `AgentTemplate.resolve(id:strict:)`：all / visibleOrdered；错误类型明确。  
- [ ] **T0.3** 单元测试：mock/store fixture 开 tab 返回正确 template；unknown id 抛错。（可不启真 PTY——若 spawn 重，抽 resolve + 参数装配测。）

### Phase 1 — Bridge + CLI（0.5–1d）

- [ ] **T1.1** `BridgeServer`：`case "handoff"` / `"open"` → 调 `openAgentTab`。  
- [ ] **T1.2** `archer-bridge handoff <agent> [--prompt …] [--cwd …] [--strict]`；stdin 读 prompt 可选（长文本）。  
- [ ] **T1.3** `BridgeServer` / 纯 JSON handle 单测（仿 `UnifiedListenerTests`）。  
- [ ] **T1.4** 手动：`swift build` 后装 CLI，对 live Archer 跑 §1 验收脚本。

### Phase 2 — GUI（0.5d）

- [ ] **T2.1** Hand off 菜单：选 agent → brief sheet（可空）→ `openAgentTab`。  
- [ ] **T2.2** Reference Sweep：`SidebarView` 三处 `onHandoff`。  
- [ ] **T2.3** 保持无 brief 时行为 = 今日空白 tab（兼容肌肉记忆）。

### Phase 3 — 体验（可选 P1）

- [ ] **T3.1** ⌘P handoff  
- [ ] **T3.2** `cmd: agents`  
- [ ] **T3.3** `list` 富字段 / focus 前台  

### Phase 4 — 文档与记忆

- [ ] **T4.1** 更新 `docs/BACKLOG.md`：新增条目 **bridge-handoff**；可注明与 A.5 agent-interop 关系。  
- [ ] **T4.2** 更新 `STATE.md` §1 Verified + §5 Last session。  
- [ ] **T4.3** `BridgeServer` 文件头协议注释补 handoff。  
- [ ] **T4.4** CHANGELOG 一句用户向说明。

---

## 5. 验收清单

| # | 检查 | 命令 / 操作 | 期望 |
|---|------|-------------|------|
| 1 | Build | `swift build` | 0 error |
| 2 | Tests | `swift test`（至少新测 + 全量） | 全绿 |
| 3 | 无 pane 交接 | §1 handoff hermes | list 出现 hermes |
| 4 | 有 prompt | handoff + prompt | ARCHER_AGENT 带 prompt（或屏幕可见任务） |
| 5 | 未知 agent | `handoff no-such` | `ok:false` 明确 error |
| 6 | GUI | Hand off → Hermes + brief | 新 tab + 非空任务 |
| 7 | 回归 | `list/read/type/keys` | 行为不变 |
| 8 | 多同 agent | 第二次 handoff hermes | label `hermes-2`，响应正确 |

---

## 6. 风险与红线

| 风险 | 缓解 |
|------|------|
| Hermes 仅 custom、prompt 启动 flag 不对 | resolve 后检查 template；单测 custom fixture；文档写清「custom 须支持 Ask 路径」 |
| spawn 异步，CLI 立即 read 为空 | 文档写「handoff 返回后稍等」；P2 再加 `waitReady` |
| 与 SleepGuard / Memory WIP 混 commit | 本功能单独 commit；STATE 已警告 |
| agentDefs 硬编码 | 一律 `AgentTemplate.all` / order API（STATE §2） |
| 误把 handoff 做成自动跨 agent 编排 | 保持显式调用；不自动链式 |

**红线（对齐 STATE / CLAUDE）**：

- Glass 三全局参数不动。  
- 不 `git push` 除非用户本会话明确要求。  
- Verify-don't-assert：宣称完成须附 `swift test` 输出。  
- Edit over Write；Reference Sweep 改签名。

---

## 7. 与现有 backlog 的关系

```
bridge-handoff (本项目, P0 急)
    │  打开 tab + prompt 的「写路径」
    ▼
agent-interop-layer (A.5, 后做)
    │  listSessions / convert / resume 的「会话总线」
    ▼
parallelTaskGroup (A.4)
    │  多 tab 结果聚合
```

本项目是 **写路径最小闭环**；做完后「Grok → Archer → Hermes」不再依赖人工先开窗。

---

## 8. 建议启动命令（给实现会话）

```bash
cd /Users/mac/Developer/archer
# 先读：
#   docs/bridge-handoff-project.md
#   Sources/ArcherKit/Bridge/BridgeServer.swift
#   Sources/ArcherKit/Sessions/WorkspaceStore.swift  (addTab / spawnSession)
#   Sources/ArcherKit/Sidebar/SidebarWorkspaceRow.swift
#   Sources/ArcherBridge/main.swift
#   STATE.md §2 agentDefs / §5

# 实现顺序：T0 → T1 → T2 → 验收 §5 → T4 文档
swift build && swift test
```

**Commit 建议（单独）**：

```
feat(bridge): handoff/open agent tab with initial prompt

Expose WorkspaceStore.openAgentTab to Bridge + CLI + sidebar Hand off,
so agents can start Hermes (or any template) without a pre-opened pane.
```

---

## 9. 决策已冻结 / 待你拍板

**已冻结（从代码与你的 live 探测推出）**：

- 复用 `initialPrompt`，不新造第二套注入。  
- Bridge 扩展 cmd，不新开 socket。  
- GUI 与 Bridge 共用 store 门面。

**待拍板（实现前 30 秒）**：

1. Hand off GUI：选 agent 后是否**总是**出 brief sheet？（推荐：是）  
2. 默认 strict 还是 all？（推荐：all，与 custom Hermes 兼容；CLI 加 `--strict`）  
3. handoff 是否默认 `focus` 前台？（推荐：GUI 是 / CLI 默认否，免抢焦点）

拍板后可直接按 Phase 0→2 开工。
