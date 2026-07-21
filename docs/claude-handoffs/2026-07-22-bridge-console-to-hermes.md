# Handoff → Hermes · Archer Bridge 指挥台 + 未提交切片

> **For**: Hermes（或任意接棒 agent）  
> **From**: Grok · 2026-07-22  
> **Repo**: `/Users/mac/Developer/archer` · branch `main` · **ahead of origin only by uncommitted WIP**  
> **Rule**: 冲突时以 **仓库现树** 为准；本文件是可执行交接，不是聊天摘要。

```bash
# 启动句（用户可复制）
cd /Users/mac/Developer/archer
# 读本文件后执行 §8 Next Steps。Repo wins if conflict.
```

---

## 1. Goal（产品立场）

- Archer 是 **多 agent 座舱**，桥接模型是 **`@label` 寻址**，**不是** 中央 IM / 多 agent 聊天室。
- 本切片目标：GUI 指挥台（Agent Bridge console + roster + activity bar）+ handoff 写路径 + parallelTaskGroup 起步。
- **Usage 窗已取消**（`10d952b` + 2026-07-22 确认）：不恢复 `UsageView` / panel；`Usage/` 采集库可保留给 Sessions token。

---

## 2. What is DONE（已验证，勿重做）

### 2.1 @label + handoff 写路径

| 能力 | 落点 |
|------|------|
| PaneRegistry 登记 **全部** non-shell tabs；`normalizeLabel` / `at` / `label(for:)` | `Sources/ArcherKit/Bridge/PaneRegistry.swift` |
| `Session.drivenByLabel`；`openAgentTab` 写 driven + seed prompt | `Session.swift` · `WorkspaceStore.openAgentTab` |
| Bridge socket：`handoff` / `open` / `agents` + `@` 日志 | `BridgeServer.swift` |
| CLI：`archer-bridge handoff\|open\|agents`（参数 strip `@`） | `Sources/ArcherBridge/main.swift` |
| 侧栏 Hand off → brief → `openAgentTab` | `SidebarView.swift`（三处） |
| Tab 显示 `@label` + `←@source`；driven pane inset ring | `TabBarItem` · `PaneTreeView` |

### 2.2 Agent Bridge 指挥台（design `bridge.html`）

| 能力 | 落点 |
|------|------|
| `BridgeConsoleView` + `BridgeAction`（type/keys/handoff 组合） | `Bridge/BridgeConsoleView.swift` · `BridgeAction.swift` |
| `BridgeConsoleLauncher.open(store:)` / `open(storeProvider:)` | `BridgeConsoleLauncher.swift` |
| `LogPanelWindowController.show(storeProvider:)` **必填**，无 bare `show()` | `LogPanelView.swift` |
| `BridgeActivityBar(store:)` 主窗底；↗ 必走 launcher | `BridgeActivityBar.swift` |
| `AgentRosterStrip` 主窗顶 live `@labels` | `AgentRosterStrip.swift` |
| ContentView 接线 | `ContentView.swift` L142 `BridgeActivityBar(store: store)` |
| Window 菜单 Agent Bridge ⌘⇧B | `AppDelegate.swift` |
| ⌘P `showAgentBridge` | `CommandPalette.swift` |
| console **无 store 时不 `sync(nil)`**（防清 registry） | `BridgeConsoleView.refreshLabels` |

### 2.3 Workspace 拖放 + parallelTaskGroup 起步

| 能力 | 落点 |
|------|------|
| chrome drop → open agent tab | `WorkspaceStore.handleChromeDrop` / `openAgentTabFromWorkspaceDrag` · `TabBarView` |
| `Workspace.parallelTaskGroupId`；launch 打标；侧栏 `∥`；members/activity API | `Workspace.swift` · `WorkspaceStore` · Sidebar |

### 2.4 Usage 窗

- **不要恢复**。Cockpit 仅 Skills；`docs/usage-tokenscope-plan.md` SUPERSEDED；design PR4 CANCELLED。

### 2.5 Skeptic 三项（2026-07-22 终验）

1. `BridgeActivityBar`：`let store`；↗ → `BridgeConsoleLauncher.open(store: store)`  
2. `ContentView`：`BridgeActivityBar(store: store)`  
3. `show(storeProvider:)` 必填；Sources 仅 launcher 调 `show(storeProvider:)`

**回归（已跑）**:

```bash
swift test --filter 'BridgeActionTests|BridgeHandoffTests'
# → 13 XCT / 0 failures
# 含 testActivityBarOpenPathKeepsStoreAndRegistry
#    testSyncNilWipesRegistryButStorePathPreservesLabels
#    testBridgeActivityBarRequiresStoreProperty
```

---

## 3. Working tree（未 commit · 必须先看）

`git status` 约 **40 条** 变更，**混有两类工作**——**禁止一把 `git add -u` 全提**。

### A. Bridge / multi-agent 切片（建议单独 commit）

**Modified（相关）**:

- `STATE.md`
- `Sources/ArcherBridge/main.swift`
- `Sources/ArcherKit/App/{AppDelegate,CommandPalette,ContentView}.swift`
- `Sources/ArcherKit/Bridge/{BridgeServer,LogPanelView,PaneRegistry}.swift`
- `Sources/ArcherKit/Cockpit/CockpitView.swift`
- `Sources/ArcherKit/Sessions/{Session,TabBarItem,TabBarView,Workspace,WorkspaceStore}.swift`
- `Sources/ArcherKit/Sidebar/{SidebarView,SidebarWorkspaceRow,SkillsView}.swift`
- `Sources/ArcherKit/Terminal/PaneTreeView.swift`
- `Sources/ArcherKit/Usage/SessionLiveUsage.swift`（若仅无关小改，仔细看 diff）
- `Tests/ArcherKitTests/WorkspaceStoreTests.swift`
- `docs/{BACKLOG,usage-tokenscope-plan,design-system-refactor-plan,design-tokens-matrix,bridge-handoff-project}.md`

**Untracked（Bridge 核心）**:

- `Sources/ArcherKit/Bridge/{AgentRosterStrip,BridgeAction,BridgeActivityBar,BridgeConsoleLauncher,BridgeConsoleView}.swift`
- `Sources/ArcherKit/Sessions/ExecutionRouter.swift`（若存在，确认是否本切片）
- `Tests/ArcherKitTests/{BridgeActionTests,BridgeHandoffTests,PaneRegistryTests}.swift`
- `docs/claude-handoffs/2026-07-22-bridge-console-to-hermes.md`（本文件）

### B. Memory* WIP（**勿与 Bridge 混提**）

- `Sources/ArcherKit/Sidebar/{MemoryDedup,MemoryEntityGraph,MemorySemanticSearch}.swift`
- `Tests/ArcherKitTests/{MemoryDedupTests,MemoryEntityGraphTests,MemorySemanticSearchTests}.swift`
- 相关 `SidebarView` MemoryBank 接线若与 mem0 绑在一起，commit 时用 path 精选或 stash Memory 改动。

STATE 原文：**WIP 勿卷**——一个工作树只容一个逻辑切片提交；pre-commit 可能 `git add -u`，先 stash 无关。

---

## 4. Verified facts（别再猜）

- Build/Test: `swift build` / `swift test` / `swift run`（SwiftPM）
- Bridge socket: `~/.archer/bridge.sock`（存在 = 服务活）
- Glass 三全局值 **勿改**: `Theme.glassOpacity` / `chromeBackgroundBlur` / `chromeBackgroundSaturate`
- Branding: **Archer** only（无 Kooky/Sailor）
- agentDefs 单一派生；增 agent 全仓搜硬编码 key
- Design truth: `~/Developer/archer-design-system`（origin `archsueh/archer-design-system`）
- 权威记忆: `STATE.md` + `Claude.md` + `docs/BACKLOG.md`

---

## 5. Product backlog 真实缺口（commit 之后可做）

| 优先级 | 项 | 状态 |
|--------|-----|------|
| P0 手测 | ⌘⇧B / roster ↗ / 侧栏 Hand off / `archer-bridge handoff` / chrome drop / 侧栏 `∥` | **未手测** |
| P0 提交 | 只 commit Bridge 切片；Memory* 另提或 stash | **未做** |
| P1 | parallelTaskGroup **结果 Dashboard 汇总**（退出码/状态/diff） | 仅 tag+chip+API |
| P1 | design-system PR：Skills 视觉；**禁止** Usage PR | 计划在 `docs/design-system-refactor-plan.md` |
| P2 | workspace-template（`.archer-workspace.yml`） | 仅 SDD |
| P2 | agent-interop-layer（`AgentSessionProvider` list/resume） | 仅 SDD；与 handoff 兄弟能力 |
| P3 | EdgeGlow P3 marquee（running 持续态） | P1/P2 已入库 |
| — | Usage 窗 / usage-dashboard | **取消 · 不实现** |

详见 `docs/BACKLOG.md` §真实待办 A.4 / A.5。

---

## 6. Logic checks（边推边查 · 已知约束）

接棒时每步改完都跑对应检查，避免「编译过 ≠ 行为对」：

1. **storeProvider 不变量**  
   - 任何打开 Agent Bridge 的路径必须带 live store。  
   - 禁 bare `LogPanelWindowController.show()`。  
   - 测：`testActivityBarOpenPathKeepsStoreAndRegistry`。

2. **sync(nil) 危险**  
   - 无 workspace 时 `PaneRegistry.sync(nil)` 会 **清空** `@labels`。  
   - console 无 store 时 **不要** sync。  
   - 测：`testSyncNilWipesRegistryButStorePathPreservesLabels`。

3. **@label 规范化**  
   - CLI/Bridge 入参 strip `@`；UI 展示可带 `@`。  
   - handoff `from` / driven 用 normalize 后的 label。

4. **Reference Sweep**  
   - 改 `openAgentTab` / Bridge 命令 / enum case 后全仓 grep 旧调用点。

5. **Commit 卫生**  
   - 不 `git push` 除非用户本会话明确要求。  
   - 不 `git add -u` 在有 Memory* 混杂时。  
   - Verify 后再 claim done：贴 `swift test` 输出。

6. **产品逻辑**  
   - 多 agent = 多 tab + `@` 寻址 + handoff，**不是** 中央 chat。  
   - Usage 窗已死，别从 design HTML 再接回来。

---

## 7. Do Not Touch

- `Theme.glassOpacity` / `chromeBackgroundBlur` / `chromeBackgroundSaturate` 全局默认  
- 恢复 `UsageView` / Usage panel / Cockpit Usage 入口  
- 引入中央 multi-agent chat room  
- 自动改写 memory 文件 / 自动 inject agent system prompt（策展哲学）  
- SleepGuard / ClosedLidSleep / CrashForensics 等他人 WIP（若仍存在）  
- 与 Memory* 未完成文件混 commit  
- 未要求时 `git push` / `git reset --hard`

---

## 8. Next Steps（Hermes 可独立执行 · 顺序）

### Step 0 — 开局

```bash
cd /Users/mac/Developer/archer
cat STATE.md | head -120
git status -sb
# 确认无其他 agent 正占此工作树（ps / 用户确认）
```

### Step 1 — 复验 Skeptic + 相关测

```bash
swift test --filter 'BridgeActionTests|BridgeHandoffTests|PaneRegistryTests'
# 期望: 0 failures
# 可选全量: swift test
```

若失败：先修 storeProvider / sync 路径，再继续。

### Step 2 — 用户手测清单（或协助用户）

| # | 操作 | 期望 |
|---|------|------|
| 1 | Archer 运行 · ⌘⇧B | 开「Agent Bridge」窗；roster 有 `@labels` |
| 2 | 主窗 Bridge 条 ↗ | 同上；handoff 目标 label 可选 |
| 3 | `echo '{"cmd":"agents"}' \| ...` 或 `archer-bridge agents` | 列出可交接 agent |
| 4 | `archer-bridge handoff hermes --prompt "ping from handoff"` | 新 tab + drivenBy + 日志 |
| 5 | 侧栏 Hand off → brief | 开 tab 带 prompt |
| 6 | 拖 workspace 到 tab bar | open agent tab |
| 7 | Parallel Task 后侧栏 | 见 `∥` chip |

手测失败 → 修代码 + 补测；通过 → Step 3。

### Step 3 — 拆分 commit（Bridge only）

```bash
# 示例：只 stage Bridge 相关（按 status 精调，勿 -u 全加）
git add \
  Sources/ArcherKit/Bridge/ \
  Sources/ArcherBridge/main.swift \
  Sources/ArcherKit/App/AppDelegate.swift \
  Sources/ArcherKit/App/CommandPalette.swift \
  Sources/ArcherKit/App/ContentView.swift \
  Sources/ArcherKit/Sessions/Session.swift \
  Sources/ArcherKit/Sessions/TabBarItem.swift \
  Sources/ArcherKit/Sessions/TabBarView.swift \
  Sources/ArcherKit/Sessions/Workspace.swift \
  Sources/ArcherKit/Sessions/WorkspaceStore.swift \
  Sources/ArcherKit/Terminal/PaneTreeView.swift \
  Sources/ArcherKit/Cockpit/CockpitView.swift \
  Tests/ArcherKitTests/BridgeActionTests.swift \
  Tests/ArcherKitTests/BridgeHandoffTests.swift \
  Tests/ArcherKitTests/PaneRegistryTests.swift \
  Tests/ArcherKitTests/WorkspaceStoreTests.swift \
  docs/BACKLOG.md \
  docs/bridge-handoff-project.md \
  docs/design-system-refactor-plan.md \
  docs/design-tokens-matrix.md \
  docs/usage-tokenscope-plan.md \
  docs/claude-handoffs/2026-07-22-bridge-console-to-hermes.md \
  STATE.md

# SidebarView 若同时含 Memory 改动：用 git add -p 只选 Hand off / parallel 块
# Memory* 文件明确不要 add

git diff --cached --stat
# 确认无 MemoryDedup / MemoryEntityGraph / MemorySemanticSearch

# 用户要求 commit 时再：
# git commit -m "$(cat <<'EOF'
# feat(bridge): Agent Bridge console, @label handoff, parallel group tags
#
# - Console + roster + activity bar with required storeProvider
# - open/handoff/agents wire + CLI; drivenBy + chrome drop
# - parallelTaskGroupId + sidebar ∥; Usage window stays removed
# EOF
# )"
```

**未经用户本会话明确说 commit / push，只 stage 检查，不 commit、不 push。**

### Step 4 — 功能推进（commit 后任选）

按产品优先级：

1. **parallelTaskGroup 结果聚合 Dashboard**（BACKLOG A.4 残余）  
2. Skills 视觉对齐 design-system（**跳过** Usage）  
3. workspace-template / agent-interop 仅在用户点名时开 SDD→实现  

每步：实现 → 测 → 更新 `STATE.md` §5。

### Step 5 — 走前写 STATE

更新 `STATE.md` §5 Last session：试了什么 / 测结果 / 是否已 commit / Next 指针。

---

## 9. Todo list（接棒 checklist）

复制到任务板或直接勾：

- [ ] **T0** 读 `STATE.md` + 本 handoff；`git status` 分清 Bridge vs Memory*
- [ ] **T1** `swift test --filter 'BridgeActionTests|BridgeHandoffTests|PaneRegistryTests'` 绿
- [ ] **T2** 手测 ⌘⇧B / ↗ / handoff CLI / Hand off GUI / drop / `∥`
- [ ] **T3** path-select stage Bridge only；`git diff --cached` 无 Memory*
- [ ] **T4** 用户批准后 commit Bridge 切片（**默认不 push**）
- [ ] **T5** Memory* 单独会话处理或 stash，勿混
- [ ] **T6**（可选）parallelTaskGroup 结果 Dashboard
- [ ] **T7**（可选）Skills design-system 视觉 PR
- [ ] **T8** 更新 `STATE.md` §5；走前写清 Next

**明确取消 / 不做**:

- [x] ~~恢复 Usage 窗~~  
- [x] ~~中央 multi-agent chat~~  
- [x] ~~Skeptic storeProvider 三项（已绿）~~

---

## 10. Key file map

```
Sources/ArcherKit/Bridge/
  PaneRegistry.swift          # @labels
  BridgeServer.swift          # socket cmds
  BridgeAction.swift          # console actions
  BridgeConsoleView.swift     # Agent Bridge UI
  BridgeConsoleLauncher.swift # open paths
  BridgeActivityBar.swift     # main window strip
  AgentRosterStrip.swift      # top roster
  LogPanelView.swift          # window controller

Sources/ArcherKit/Sessions/
  WorkspaceStore.swift        # openAgentTab, drop, parallel group
  Session.swift               # drivenByLabel
  Workspace.swift             # parallelTaskGroupId

Sources/ArcherBridge/main.swift
Tests/ArcherKitTests/Bridge*.swift
docs/bridge-handoff-project.md
docs/design-system-refactor-plan.md
STATE.md
```

---

## 11. Resume one-liner

> Bridge 指挥台 + @label handoff + parallel 标记 **代码已齐、Skeptic 测绿、未 commit**；  
> Hermes：复验 → 手测 → **只提 Bridge**（Memory* 勿混）→ 再开 Dashboard 聚合或 Skills 视觉。  
> **Usage 窗已死。** Repo wins if conflict.
