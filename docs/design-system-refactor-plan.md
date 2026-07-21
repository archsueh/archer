# Archer 整包视觉系统重构计划

> **Status**: **执行中** · 2026-07-21 · 用户授权「你来判定执行」  
> **Design source**: Claude Design `0357fb47-396a-4a92-a05a-e52c955c35ca`  
> **Local mirror**: `~/Downloads/archer-old-0357fb47/`（云端需登录，以本地包为准）  
> **Related**: `docs/bridge-handoff-project.md`（handoff wire 下一刀，本切片未做）  
> **Frozen decisions**（判定默认）:
> 1. 设计包 **不整仓复制**（体积/上传图）；真源 = Downloads 路径 + `docs/design-tokens-matrix.md`
> 2. Cockpit ⌘⇧K：**暂保留**，PR5 再收敛；不当视觉验收真源
> 3. Sessions：独立窗（已有 `SessionsWindowController`），本切片不动
> 4. Bridge handoff wire：**下一刀**（先 bar + @label）
> 5. Hermes 图标：沿用现有 iconAsset / SF，不塞 design PNG

---

## 0. 一句话目标

把 Design 包里的 **token + 组件卡 + 全屏** 收敛成 Archer 生产 UI 的唯一视觉真源：主窗口、Skills、Sessions、Bridge、终端 pane 头，全部可对照 HTML 验收；**不重做业务逻辑**，不破坏 glass 全局基线与 `aver-light`。  
**Out of product（2026-07-22）**：`usage-dashboard.html` / Usage 窗 — **不实现、不恢复**（`10d952b` 已删面板；采集层 `Usage/` 仅供 Sessions token 等只读用）。

---

## 1. 设计包清单（真源）

| 分组 | 文件 | 对应生产落点 |
|------|------|--------------|
| **Foundations** | `styles.css`, `colors.html`, `typography.html`, `spacing-grid.html`, `shape-glass.html` | `Theme.swift`, `DESIGN.md` |
| **Components** | `bracket-button.html`, `status-indicators.html`, `terminal-pane.html`, `ansi-contrast.html` | `BracketButton` / 状态点 / pane 头 / 主题 ANSI |
| **Showcase** | `interface.html` (1440×900) | **主窗口** `ContentView` + Sidebar + TabBar + PaneTree + FilePanel |
| **Screens** | `skills-dashboard.html` | `SkillsView`（独立窗/面板） |
| | `usage-dashboard.html` | ❌ **取消** — 不实现 Usage 窗 |
| | `sessions.html` | Sessions 列表（可能新屏或 Dashboard 增强） |
| | `bridge.html` + `bridge-spec.html` | ✅ 主窗 bar + **Agent Bridge 窗**（roster+composer） |
| | `cockpit-views.html` | 视图切换动效参考（Terminal / Skills / Usage） |
| **Docs** | `HANDOFF.md` | 历史：@label / driven-by / bridge bar（部分已在 Cockpit stub） |

**不要**用 `CockpitView.swift`（⌘⇧K 演示窗、假数据）当真源——那是 6 月底按 HANDOFF 文字做的 **dashboard 偏离版**。真源是 `interface.html` 的 **workspace-switcher 三栏主窗**。

---

## 2. 现状差距（证据级）

### 2.1 Token：大部分已对齐

| Design token | 值 | 生产 `Theme` / `DESIGN.md` |
|--------------|-----|---------------------------|
| `--primary` | `#EFEFF1` | ✅ `chromeForeground` / DESIGN |
| `--secondary` | `#9E9EA0` | ✅ `chromeMuted` |
| `--neutral` | `#282C34` | ✅ terminal surface 系 |
| hairline/hover/active | `.07 / .07 / .15` | ✅ |
| running/attention/failure | `#69B0D6 / #E8B068 / #E86666` | ✅ activity* |
| git insert/delete | `#73C780 / #E86666` | ✅ |
| glass opacity | `0.72` | ✅ **全局基线，禁止改默认值** |
| Onest + JetBrains Mono | — | ✅ 已绑定 |

**结论**：Foundations 不是「重写 Theme」，是 **审计 + 补缺**（surface-2、圆角 18 仅用于独立浮层窗、密度刻度表文档化）。

### 2.2 主窗 `interface.html` vs 生产 ContentView

| 维度 | Design | 生产（约） | Gap |
|------|--------|------------|-----|
| 布局 | 左 230 / 中 flex / 右 300 + resizer | 侧栏+中栏+文件树（已有 resizable） | **中**：节奏/行高/标题字阶对齐 |
| 侧栏头 | 「Archer」+ plus | Workspaces 区 | 标题层级 |
| Workspace 行 | 专属 logo + path + 8px status dot | 多为 SF Symbol / agent 色 | **图标与密度** |
| 拖放 | workspace → tabbar/panes | 有限 | 可选 P2 |
| Tab 栏 | mono 11.5 / active fill / split 钮 | `TabBarView` | 视觉对齐 |
| Pane 头 | icon + name + **@label** + 6px pdot + driven-by | ✅ Tab `@label` + `←@`；pane driven 描边 | **已落地 2026-07-22** |
| Bridge bar | 中栏底常驻可折叠 | ✅ `BridgeActivityBar(store:)` + 指挥台 | **已落地** |
| Status chips | 版本 / 代理 IP | 状态栏有 load/git 等 | 字段对齐可选 |
| 右栏 | 3 列 folder grid | `FilePanelView` 树/网格 | 网格态视觉对齐 |
| 壁纸 | 夜色径向渐变 + 浮窗 18px 圆角 | NSVisualEffect 真玻璃 | **不抄假壁纸**；真 vibrancy 优先 |

### 2.3 Skills / Usage / Sessions / Bridge

| 屏 | Design 特征 | 生产 | Gap |
|----|-------------|------|-----|
| Skills | 大数字 stats、panel 分区、Discover 搜索、mini 按钮、更新 badge | `SkillsView` ~2k 行，功能全 | **信息架构与密度**，非重写逻辑 |
| Usage | agent chip 条、三 stat… | 面板已删 `10d952b` | **不恢复** |
| Sessions | 状态机表 + j/k 快捷键 + 筛选侧栏 | 无对等「会话表」屏 | **新屏或 Dashboard 子集**（P1） |
| Bridge | roster + 事件 log + verb composer | `LogPanelView` 列表 | 主窗 bridgebar + Log 窗视觉升级 |

### 2.4 已知历史分叉（避免再犯）

`Desktop/Archer-Cockpit-改动文档.md` §6：Hermes 实现的是 **多 pane dashboard**，Design 是 **workspace switcher + 单会话多 pane**。  
整包重构时：**主窗以 `interface.html` 为准**；`CockpitView` 要么删除/并入主窗，要么标为 experimental 不占验收。

---

## 3. 原则与红线

### 原则

1. **Design HTML = 视觉契约**；生产 Swift = 行为真源（store / PTY / skills 逻辑）。  
2. **Token 先、屏后**：任何屏改动前完成 Theme 对照表（PR0）。  
3. **Edit over Write**：SkillsView 2k 行禁止整文件重写；按区域补丁。  
4. **真数据**：禁止为对齐视觉重新引入 fake usage / fake bridge events（STATE 已踩坑）。  
5. **一 PR 一屏或一 token 层**，便于 review 与回滚。

### 红线（CLAUDE.md / STATE）

| 红线 | 说明 |
|------|------|
| 不改 `Theme.glassOpacity` / `chromeBackgroundBlur` / `chromeBackgroundSaturate` 全局默认 | 新观感用 per-theme override |
| 不破坏 `aver-light` 象牙白 | 暗色 design 不能反向污染 light theme |
| 不引入 WebKit 壳加载 HTML 当主 UI | 原生 SwiftUI 重实现 |
| 不改 glass 参数「为了更像假壁纸」 | 假 radial wallpaper 仅预览用 |
| agentDefs 单一派生 | 图标/label 从 template 解析 |
| 不混 Memory/SleepGuard/SSH WIP | 视觉 PR 独立 |

---

## 4. 分阶段实施（建议 6 个 PR）

### PR0 · Token & Foundations 契约（0.5–1d）

**目标**：Design `styles.css` ↔ `Theme.swift` ↔ `DESIGN.md` 三方一致表。

- [x] 写 `docs/design-tokens-matrix.md`：token 名 / CSS 值 / Swift 符号 / 是否一致  
- [x] `surface-2` 记为 doc-only；space1–5 / glass 决策入矩阵  
- [x] `shape-glass`：主窗 = 真 vibrancy；不抄 HTML 假壁纸  
- [x] **不**整包入仓（判定：Downloads 为真源）  
- [ ] **验收**：`swift test`（与本切片 UI 一并）

### PR1 · 主窗 Chrome：Sidebar + Tab + Pane 头（2–3d）

**目标**：打开 Archer 主窗，肉眼对照 `interface.html` 左/中上 70% 像。

- [ ] Sidebar：标题层级、Workspaces 段标、行高 10/26、path mono 10、status 8px dot  
- [ ] Agent 图标：优先 asset / 现有 iconAsset；缺则 SF Symbol 降级；Hermes 用设计 `ref/hermes-icon.png`（需授权进 bundle）  
- [ ] TabBar：active 态 `chromeActive` + hairline；split 按钮尺寸  
- [ ] **Pane 头**：`@displayAgent.id` + 6px color dot；可选 `drivenBy`（若 session 模型有 driver，否则 P1.5）  
- [ ] 右栏 File grid：与 `files-grid` 间距/label 字号对齐（树模式保留）  
- [ ] **验收**：截图并排 `interface.html`（浏览器）vs 主窗；无功能回归；`swift test` 绿  

**不做本 PR**：Bridge bar、Skills 大改、Sessions 新屏。

### PR2 · 主窗 Bridge 活动条 + 真事件（1–2d）

**目标**：中栏底 `bridgebar` 接 `BridgeEventLog.shared`，形态同 `interface.html`。

- [ ] 抽出可复用 `BridgeActivityBar`（SwiftUI）  
- [ ] 默认收起：`BRIDGE` + 最近一条；展开 max-height ~140  
- [ ] verb 着色：read muted / type running / keys attention  
- [ ] 与独立 `LogPanelView` 共用数据源；Log 窗可视觉跟 `bridge.html` 升级（可同 PR 或 PR2b）  
- [ ] **连带（推荐同 PR 或紧随）**：`docs/bridge-handoff-project.md` 的 `handoff` wire——否则 bar 仍只有 type 无 open  
- [ ] **验收**：`archer-bridge type` 后 bar 出现事件；无 pane 时 list 仍正确  

### PR3 · Skills Dashboard 视觉对齐（2–3d）

**目标**：`skills-dashboard.html` 的 hierarchy，保留现网安装/更新/relay。

- [ ] 顶栏：title + sub + 动作 btn（检查更新 badge）  
- [ ] Stats 条：大数字 tabular（端点数/更新数/… **真实字段**，禁 fake trigger）  
- [ ] Panel 分区头 uppercase mono tracking  
- [ ] Row：dot 状态 / name / repo muted / mini 按钮 prim|done  
- [ ] Discover 搜索行与 install-mode 分段控件  
- [ ] **验收**：功能路径手测安装/更新；视觉对照 HTML；单测相关不破  

### PR4 · Usage Dashboard — **CANCELLED（2026-07-22）**

产品判定：不需要 Usage 窗。`UsageView` / `UsagePanelController` 已在 `10d952b` 删除。  
design 卡 `usage-dashboard.html` 仅作历史参考，**禁止**再接回 Archer 菜单/侧栏。  
`Sources/ArcherKit/Usage/` 采集/定价库可保留（Sessions token 等），不提供独立窗。

### PR5 · Sessions 屏 + Cockpit 收敛（2–3d，可拆）

**目标**：`sessions.html` 状态表；消灭/降级假数据 Cockpit。

- [ ] 新 `SessionsPanel`（或 Dashboard 页）：状态 / 会话 / 进度 / token  
- [ ] 状态机映射生产 activity（running/attention/idle…）— 不硬抄 torrent-tui 全套  
- [ ] 筛选侧栏 + 搜索；快捷键 j/k 可选 P5.1  
- [ ] `CockpitView`：改为薄包装进真实 store **或** 移除菜单入口并文档说明  
- [ ] **验收**：会话数 = 真 tab；无硬编码路径列表  

### PR6 · 组件库与收尾（1–2d）

- [ ] `BracketButton` 对照 `bracket-button.html`  
- [ ] 全局 status / git 指示对照 `status-indicators.html`  
- [ ] `terminal-pane.html` 细节扫尾  
- [ ] `ansi-contrast.html`：主题 ANSI 安全对照（设置页或文档）  
- [ ] `cockpit-views.html`：Terminal↔Skills↔Usage 切换动效（0.2s easeInOut，尊重 reduced motion）  
- [ ] 更新 `DESIGN.md` 组件段 + CHANGELOG 用户向说明  
- [ ] 更新 `STATE.md` §1/§5  
- [ ] 可选：设计包入仓 `design/0357fb47/`（只读参考，不跑）

---

## 5. 工作量与依赖

```
PR0 tokens
  │
  ├─► PR1 主窗 chrome ──────────► PR2 bridge bar ──┬──► PR6 组件收尾
  │                                                 │
  ├─► PR3 Skills ──────────────────────────────────┤
  │                                                 │
  └─► PR4 Usage ───────────────────────────────────┤
                                                    │
              PR5 Sessions + Cockpit 收敛 ──────────┘

bridge-handoff（写路径）建议贴 PR2，commit 可独立
```

| PR | 估时 | 风险 |
|----|------|------|
| 0 | 0.5–1d | 低 |
| 1 | 2–3d | 中（触 Sidebar/Tab/Pane 面广） |
| 2 | 1–2d | 中（生命周期 + 真事件） |
| 3 | 2–3d | 中（Skills 巨文件） |
| 4 | 1–2d | 低–中 |
| 5 | 2–3d | 中–高（新屏） |
| 6 | 1–2d | 低 |
| **合计** | **~10–16 工作日** | 可并行 3/4 与 1 后期 |

---

## 6. 验收总清单（整包 Done）

| # | 项 | 方法 |
|---|-----|------|
| 1 | Token 矩阵 100% 映射 | 文档 + Theme 抽检 |
| 2 | 主窗并排 `interface.html` | 截图 diff（允许 vibrancy 差异） |
| 3 | Pane `@label` 可被 bridge list 对上 | live `archer-bridge list` |
| 4 | Bridge bar 真事件 | type/keys 后 UI 更新 |
| 5 | Skills/Usage 无假数据 | 代码 grep + 空态手测 |
| 6 | `swift build` + `swift test` 全绿 | CI / 本地输出贴会话 |
| 7 | light theme / aver-light 未坏 | 切换主题截图 |
| 8 | Glass 三全局参数未改 | git diff Theme.swift |

---

## 7. 明确不做（本整包）

- 用 WKWebView 整页嵌 HTML 设计  
- 抄 design 的假夜色壁纸替代 NSVisualEffect  
- 为 Sessions 引入远程后端  
- 自动跨 agent 编排（handoff 仅显式 API/GUI）  
- 改 agent CLI 本体  
- 一次巨型 PR 混合 SSH / Memory / SleepGuard  

---

## 8. 启动顺序（批准后）

1. **冻结设计源**：确认 `~/Downloads/archer-old-0357fb47` 是否最新；若 Claude Design 有更新，请再导出覆盖。  
2. 执行 **PR0**（只文档 + 最小 Theme 补缺）。  
3. 截图基线：主窗 / Skills / Usage 各一张 `before/`。  
4. PR1 → PR2 → PR3/4 并行 → PR5 → PR6。  
5. 每 PR：`swift test` + 对应屏 after 截图。  

### 启动句（实现会话）

```bash
cd /Users/mac/Developer/archer
# 读：
#   docs/design-system-refactor-plan.md
#   ~/Downloads/archer-old-0357fb47/interface.html + styles.css
#   Sources/ArcherKit/App/Theme.swift
# 执行：仅 PR0（token 矩阵 + DESIGN 同步），禁止动 Skills/Usage 业务逻辑
```

---

## 8.5 Skill map · 怎么打开「它」

> 快速索引：Design HTML 预览 / 生产面板 / 该用哪个 agent skill。

### A. 打开 Design 预览（视觉真源）

根目录：`~/Downloads/archer-old-0357fb47/`

```bash
DS=~/Downloads/archer-old-0357fb47
open "$DS/interface.html"           # 主窗 Showcase
open "$DS/skills-dashboard.html"    # Skills
open "$DS/usage-dashboard.html"     # Usage
open "$DS/sessions.html"            # Sessions
open "$DS/bridge.html"              # Bridge 交互
open "$DS/bridge-spec.html"         # Bridge 架构
open "$DS/colors.html"              # Tokens
open "$DS/typography.html"
open "$DS/spacing-grid.html"
open "$DS/shape-glass.html"
open "$DS/bracket-button.html"
open "$DS/status-indicators.html"
open "$DS/terminal-pane.html"
open "$DS/ansi-contrast.html"
open "$DS/cockpit-views.html"       # Terminal/Skills/Usage 切换
```

一键全开（可选）：

```bash
open ~/Downloads/archer-old-0357fb47/{interface,skills-dashboard,usage-dashboard,sessions,bridge}.html
```

云端（需已登录 Claude）：  
https://claude.ai/design/p/0357fb47-396a-4a92-a05a-e52c955c35ca

### B. 打开生产 Archer 对应入口

| Design 屏 | 生产打开方式 | 代码入口 |
|-----------|--------------|----------|
| `interface.html` | 启动 `Archer.app` 主窗 | `ContentView` + `SidebarView` + `PaneTreeView` |
| `skills-dashboard.html` | 侧栏底 **Skills** / 菜单 | `SkillsPanelWindowController.show()` → `SkillsView` |
| `usage-dashboard.html` | ❌ 不实现 | 产品取消 |
| `sessions.html` | Window → **Sessions**（若有） | `SessionsWindowController` |
| `bridge.html` | Window → **Log** / Bridge 日志 | `LogPanelWindowController.show()` → `LogPanelView` |
| Cockpit 旧演示 | ⌘⇧K Window → Cockpit | `CockpitPanelWindowController`（假数据，勿当真源） |

侧栏导航（生产）：

```
SidebarView → Skills 行 → SkillsPanelWindowController.show()
SidebarView → Usage 行 → （Usage 面板）
```

### C. Agent skill 映射（做重构时 load 谁）

| 任务 | Skill（优先） | 何时用 |
|------|---------------|--------|
| Archer 主栈 / Theme / glass | `archer-development` | 任何 `Sources/ArcherKit` 改动 |
| 主窗打不开 / 无 UI | `archer-troubleshooting` | 启动失败 |
| 按 Design 做 HTML 原型迭代 | `claude-design` | 只改 design 包、不进 Swift |
| Design → Aver 同步（**非**本项目） | `aver-design-sync` | 仅 `aver-design-system` 仓 |
| SwiftUI 质量 / 性能 | `swiftui-expert-skill` / `swiftui-pro` | PR1+ pane/sidebar |
| 反 AI-slop UI | `impeccable` / `swiftui-design` | 视觉扫尾 PR6 |
| Bridge handoff 实现 | （本仓 plan）+ `archer-development` | `docs/bridge-handoff-project.md` |
| 提交 | `git-commit` | 用户明确要求 commit 时 |

**不要**用：`aver-design-sync` 推 Archer 设计（pin 的是 Aver 项目 id，不是 `0357fb47`）。

### D. Design 文件 → PR 切片

| 打开这个 HTML | 做这个 PR |
|---------------|-----------|
| `styles.css` + foundations/* | PR0 Token |
| `interface.html`（左中上） | PR1 主窗 chrome |
| `interface.html` bridgebar + `bridge.html` | PR2 Bridge bar |
| `skills-dashboard.html` | PR3 Skills |
| `usage-dashboard.html` | ~~PR4~~ 取消 |
| `sessions.html` + `cockpit-views.html` | PR5 Sessions / Cockpit |
| components/* | PR6 组件库 |

---

## 9. 待你拍板（实现前）

| # | 问题 | 建议默认 |
|---|------|----------|
| 1 | 设计包是否入仓 `design/0357fb47/`？ | **是**，只读参考 |
| 2 | `CockpitView`（⌘⇧K）去留？ | **PR5 删除或改真数据包装** |
| 3 | Sessions 独立窗 vs 侧栏入口？ | **独立面板窗**（对齐 Skills/Usage） |
| 4 | Bridge handoff wire 并进 PR2？ | **是**（否则 bar 仍缺 open） |
| 5 | Hermes 图标授权进 app bundle？ | 用设计 `ref/hermes-icon.png` 或现 asset |

拍板 1–5 后即可从 PR0 开工。本文件为执行契约；冲突时 **repo 生产行为 > 假数据 HTML stub**，**视觉以 design HTML 为准**。
