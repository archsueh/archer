# Archer · TODO

> 活清单。完成即勾掉并移入「已完成」或删行。  
> 更新：2026-07-22 · 详日志 [`worklogs/2026-07-22.md`](worklogs/2026-07-22.md) · 交接 [`claude-handoffs/2026-07-22-bridge-console-to-hermes.md`](claude-handoffs/2026-07-22-bridge-console-to-hermes.md)

---

## P0 · 立刻（Hermes / 下一会话）

- [ ] **T0** 读 `STATE.md` + handoff；`git status` 分清 **Bridge** vs **Memory***
- [ ] **T1** 复验：`swift test --filter 'BridgeActionTests|BridgeHandoffTests|PaneRegistryTests'`（期望 0 fail）
- [ ] **T2** 手测清单  
  - [ ] ⌘⇧B 开 Agent Bridge  
  - [ ] 主窗 Bridge 条 ↗ / roster  
  - [ ] `archer-bridge agents` / `handoff … --prompt`  
  - [ ] 侧栏 Hand off + brief  
  - [ ] workspace 拖到 tab bar  
  - [ ] Parallel Task 后侧栏 `∥`
- [ ] **T3** path-select **仅 stage Bridge**；`git diff --cached` 无 Memory*
- [ ] **T4** 用户批准后 commit Bridge 切片（**默认不 push**）
- [ ] **T5** Memory* 另会话处理或 stash，勿混提

---

## P1 · 功能推进（commit 之后）

- [x] **parallelTaskGroup 结果 Dashboard** — `ParallelGroupDashboardView/WindowController/Controller`; ⌘⇧G / palette / window menu
- [x] **Observability timeline** 最小岛已落地并接真实数据源；⌘⇧I / palette / window menu
- [ ] Skills 视觉对齐 `archer-design-system`（design-system-refactor-plan PR3 一类）
- [ ] 全量 `swift test` 绿后再谈 release 切片

---

## P2 · Backlog（用户点名再开）

- [ ] workspace-template（`.archer-workspace.yml`）— BACKLOG A.3
- [ ] agent-interop-layer（`AgentSessionProvider` list/resume）— BACKLOG A.5
- [ ] EdgeGlow P3 marquee（running 持续态）

---

## P3 · 可选 / 低优

- [ ] yibie star 筛选
- [ ] God Object 拆文件（>1300 行）
- [ ] Heartbeat L2+（cron / trust.tsv / goals 日验）

---

## 已完成 · 2026-07-22（勿重做）

- [x] @label PaneRegistry + drivenBy + Tab 徽章
- [x] Bridge `handoff` / `open` / `agents` + CLI
- [x] GUI Hand off brief → `openAgentTab`
- [x] Agent Bridge console + Action + Launcher
- [x] BridgeActivityBar(store:) + AgentRosterStrip + ContentView 接线
- [x] ⌘⇧B / ⌘P showAgentBridge
- [x] storeProvider 必填；Skeptic 三项测绿（13/0）
- [x] chrome drop 开 agent tab
- [x] parallelTaskGroupId + 侧栏 `∥`（标记起步）
- [x] **Usage 窗取消**（不恢复；docs/PR4 作废）
- [x] design-system 计划 / tokens 矩阵文档
- [x] Hermes handoff + 本日工作日志

---

## 明确不做

| 项 | 原因 |
|----|------|
| 恢复 Usage 窗 / usage-dashboard | 产品 2026-07-22 取消 |
| 中央 multi-agent chat room | 桥 = `@label` 寻址 |
| 改 Theme glass 三全局默认 | STATE 红线 |
| Memory* 与 Bridge 同 commit | 工作树卫生 |
| 未要求时 `git push` | 工程纪律 |

---

## 提交时 path 提示（Bridge only）

```text
Sources/ArcherKit/Bridge/**
Sources/ArcherBridge/main.swift
Sources/ArcherKit/App/{AppDelegate,CommandPalette,ContentView}.swift
Sources/ArcherKit/Sessions/{Session,TabBar*,Workspace,WorkspaceStore}.swift
Sources/ArcherKit/Terminal/PaneTreeView.swift
Sources/ArcherKit/Cockpit/CockpitView.swift
Tests/ArcherKitTests/{Bridge*,PaneRegistry*,WorkspaceStoreTests}.swift
docs/{BACKLOG,bridge-handoff*,design-*,usage-tokenscope*,claude-handoffs/**,worklogs/**,TODO}.md
STATE.md
# SidebarView：-p 只选 Hand off / parallel；跳过 Memory*
# 勿 add：MemoryDedup / MemoryEntityGraph / MemorySemanticSearch + 其 Tests
```
