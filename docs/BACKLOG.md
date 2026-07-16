# Archer Backlog

> **交叉核对（2026-07-16）**：git 已落地多项曾被标「未实现」的条目；文档曾漂移。  
> 下列 **真实待办** 已剔除陈旧项。细节仍在各节；冲突时以 git + `STATE.md` 为准。

## 真实待办（2026-07-16 核对）

### A. 真正未做（仅 SDD / 残余 backlog）

| # | 条目 | 节 | 状态 |
|---|------|-----|------|
| 1 | ~~worktree 残余~~ | §worktree | **①② 均已落地**（合并回主树 + 跨 worktree diff 汇总） |
| 2 | 边缘活动辉光（EdgeGlow 借鉴） | §边缘活动辉光 | 待最小 SDD + 实现 |
| 3 | workspace-template（`.archer-workspace.yml`） | §tmux-ide | 仅 SDD |
| 4 | 并行任务结果聚合（`parallelTaskGroup`） | §orbiteditor 思路 A | 仅 SDD（思路 B 已落地 `770194b`） |
| 5 | agent-interop-layer（`AgentSessionProvider`） | §lemma 思路 A | 仅 SDD（showagent 桥 `ebb8d97` 已落地） |
| 6 | kooky：filetree git diff badges；ssh-workspace | §kooky | 仅 SDD（Recent folders `1790455` 已落地） |

### B. 可选增强（未排期）

| # | 条目 | 节 |
|---|------|-----|
| 8 | yibie star 筛选（`isStarred` + 筛选） | §yibie |
| 9 | codeflow God Object 拆文件（6 个 >1300 行） | §codeflow |

### C. 文档曾陈旧、git 已落地（本节仅作勘误索引）

| 条目 | 提交 | 说明 |
|------|------|------|
| session-recorder（terminal-control） | `4ba0020` | opt-in `.termctrl` 录制 |
| unified-local-listener（cmux） | `47043b6` | UnifiedListener 合并 Bridge+Hook |
| memory 面板（claude-mem 思路） | `6f6e683` | A-mem 链接图面板 |
| agent 自动检测 sniffer（muxy ①） | `5d7b8bf` / `eca968a` | opt-in basename 嗅探 |
| skills 反向注入 harness（muxy ②） | `SkillsInjector` + `9210b60` | symlink relay 批量导出，不覆盖已有安装 |

---

## worktree-per-agent 会话隔离（大部分已实现）
- 来源：双竞品信号（stablyai/orca 与 jamesrochabrun/AgentHub 各自独立做了 worktree 管理，2026-07-06 调研）+ 自身事故（STATE.md §4，2026-07-03 两会话共用工作树导致 commit 污染）。
- **已实现**（先于本条目存在，2026-07-06 侦察修正——旧记录误标"未实现"）：`WorktreeManager`（全部 git worktree 写操作）、sidebar 创建/adopt（`CreateWorktreeSheet`）、右键 Parallel Task（N worktree 各跑一个 agent + prompt）、关闭确认链（`isLastTabInWorktree` → `requestCloseWorkspace` → remove + `deleteBranchIfMerged`）。
- **2026-07-06 新增**：`+` 菜单 agent 行尾 branch 副按钮，一键"在新 worktree 中打开该 agent"（`openTabInNewWorktree`，自动分支名 `archer/<agent>-<rand>`，非 git 仓库不显示按钮）。
- **已落地（2026-07-16）① 关闭 worktree「合并回主树」**：`ConfirmRemoveWorktreeSheet` 三 disposition（keep / merge / delete）；`WorktreeManager.merge` + `currentBranch`；`WorkspaceStore.mergeWorktreeIntoParent` 在主树 HEAD 上 `git merge --no-edit`，成功后再 `worktree remove --force` + `branch -d`；冲突/detached 则报错且不删目录。单测：WorktreeManager merge + WorkspaceStore merge 路径。
- **已落地（2026-07-16）② 跨 worktree diff 汇总**：`WorktreeDiffMember` / `WorktreeDiffSummary`；`DiffModel` 多根 refresh + `focus(rootURL:)`；`DiffPanelView` 顶部 WORKTREES 概览（M/A/D 角标 chip）；`WorkspaceStore.worktreeFamilyMembers`；`ContentView` 注入 family。单根时隐藏概览，行为与旧版一致。单测：`DiffModelTests` family overview + store family members。
- **残余（worktree）**：无（A.1 闭环完成）。
- 设计红线：默认行为不变；worktree 目录放 repo 同级（沿用现有约定）；不做 AgentHub 式 GitHub PR/issue 集成（超出座舱边界）。

## 边缘活动辉光（borrow from EdgeGlow）
- 来源：github.com/vector4wang/EdgeGlow（macOS 菜单栏，屏幕边缘 marquee 辉光示意 AI agent 活动）。
- 借鉴点：复用 archer 已有的 Claude Stop/Notification/turn hook 信号 + activity 三态色，做一圈克制的窗口/屏幕边缘辉光，作为提示音之外的余光视觉确认。
- 技术：Swift/AppKit CAShapeLayer + CVDisplayLink 驱动 lineDashPhase，四层 neon；零依赖，可直接移植。
- 设计红线：EdgeGlow 默认彩虹霓虹，与 archer brutalist-minimal（低对比/零阴影/克制）冲突。archer 版必须单色、窄、克制、可关，用 activity token 色（running #69B0D6 / attention #E8B068 / failure #E86666），绝不彩虹。
- 状态：**未实现**（2026-07-16 核对仍属真实待办 A.2）。待写最小 SDD 后落地：复用 Claude Stop/Notification hook + activity 三态色；`CAShapeLayer` 边缘辉光；单色窄条可关。

## claude-mem 参考（github.com/thedotmack/claude-mem）
- 它是什么：Claude Code 跨会话自动记忆（5 hook 捕获→AI 压缩→下次注入，SQLite+Chroma+:37777 web viewer）。
- ① archer memory 面板（archer 范围）：其 worker+SQLite+web viewer 架构曾作蓝本。
  - **已落地（2026-07-09，`6f6e683`）**：`Sidebar/MemoryGraph.swift` + `SidebarView.MemoryBankSection`——本地 `[[wikilink]]` / `#tag` 链接图（前向/反向、枢纽排序、标签聚类、孤立分组），`+` 生成原子 memo 模板；**不自动改写文件、不引入 LLM**（人工高信噪策展）。测试 `MemoryGraphTests` ×7。详见 `STATE.md` §1。
  - **不抄 / 不做**：claude-mem 的 worker + SQLite + Chroma + :37777 web viewer 自动全量捕获（与策展哲学冲突）。
- ② 个人工作流可控试用（非 archer）：与 hsueh 现有手动 MEMORY.md / claude-handoff 重叠且哲学冲突。如试，read-only 评估捕获质量，勿直接替换手动流程，勿两套记忆并行打架。
- 状态（①）：**已落地** `6f6e683`（2026-07-16 文档回填）。

## tmux-ide 参考（github.com/wavyrai/tmux-ide · v2.7.0，525★）
- 它是什么：用 `ide.yml` 把任意项目变成 tmux 驱动的"终端 IDE"——声明式布局编排（orchestrator）+ 持久化 daemon + task 系统 + web dashboard。跨平台 CLI（bun/Node 栈），无原生 GUI。
- 竞品判定：**部分竞品，非直接竞品**。重叠仅在"多终端/多 agent 会话编排 + worktree 隔离"；错位在平台（它 tmux+web，archer 是 macOS 原生 Swift/AppKit）与核心卖点（它卖 yaml 复现开发环境，archer 卖跨 agent 座舱 + 成本/记忆/技能治理）。用户不会二选一。
- **可抄（仅思路，不抄代码）**：声明式工作区模板 `ide.yml` 的"一键复现会话布局"思路。Archer 当前缺此能力——每次新项目需手动开 worktree、加 pane、选 agent。tmux-ide 的 ts/bun 代码与 Archer 的 Swift 栈完全不重叠，**不能直接移植代码**，只能用 Swift 原生重写概念。
- **不抄**：tmux 编排内核、bun daemon、web dashboard（archer 已有 ghostty 引擎 + AppKit 窗口体系，重复造无意义）；它的 CLAUDE.md/AGENTS.md 生成（archer 是座舱，不替 agent 写指令文件）。
- 最小 SDD（功能点 `workspace-template`）：
  - 配置：`~/Developer/<repo>/.archer-workspace.yml`，声明 `name` / `worktree`(from branch) / `panes[]`{ agent, cwd, command } / `layout`。
  - 解析：Swift 原生 YAML——优先引 Yams(SPM 依赖)；或手写最小键值解析器（字段少，零依赖更贴合工程边界）。
  - 落点：`WorkspaceStore` 新方法 `applyTemplate(_:)` → 复用现有 `WorktreeManager`（开/ adopt worktree）+ `openTabInNewWorktree`（挂 agent tab）+ `PaneNode` 构建 pane 树。保持默认行为不变（无模板时照旧手动）。
  - 触发：仓库 `+` 菜单或命令面板"Apply workspace template"，读仓库根 `.archer-workspace.yml`。
  - 红线：不引入 tmux/bun/dashboard 任何依赖；模板只描述布局，不执行 agent 指令生成；并行会话隔离规则沿用 §4（一个工作树只容一个 agent 会话）。

## orbiteditor 参考（github.com/ashish200729/orbiteditor · v0.1.1，14★）
- 它是什么：开源 Cursor AI 替代品（Electron/CEF 系，VS Code 衍生：有 `.vscode`/`.cursor/rules`/`.devcontainer`，用原生 `WebContentsView` 做内嵌浏览器）。对标 Cursor，不是对标 Archer。
- 竞品判定：**非 Archer 竞品**（它是 AI 代码编辑器，Archer 是终端 agent 座舱，形态/栈/核心价值全错位）。但有两个可借鉴思路：
- **可抄思路 A · subagent 编排（结果聚合）**：orbiteditor 的 subagent framework 把大任务拆给多个子 agent 并行后回收结果。Archer 已有 `openTabInNewWorktree`（右键 Parallel Task 并发 N 个 worktree 各跑一个 agent），但**只并发不聚合**——缺结果回收/汇总表达。落点：`WorkspaceStore` 加 `parallelTaskGroup` 概念，并行任务结束后在 Dashboard 汇总各 worktree 的最后状态/退出码/产物 diff。
- **可抄思路 B · 项目规则自动注入**：orbiteditor 的 `.cursor/rules` 是"项目根规则文件，AI 自动加载"。Archer 有 Skills + AgentTemplate，但缺"项目根自动发现规则文件"一环。
- **不抄**：编辑器内核、文件树、内嵌浏览器（WebContentsView）、diff 视图（Archer 不编辑代码，只跑终端）；它的 TS/Electron 代码栈（与 Swift 不重叠）。
- 已执行（2026-07-09）：思路 B 做成**只读发现 + 侧边栏展示**，不越界——`Sources/ArcherKit/Sidebar/ProjectRulesSection.swift` 扫描当前 workspace 根的 `.archer/rules/*.md`，在侧边栏 Tool 区列出，点击复制 `@路径` 供你手动引用；**不改 agent 启动环境、不自动注入 system prompt**（守 STATE §4 隔离边界 + 人工高信噪策展哲学）。思路 A（结果聚合）仅记 SDD，未实现。

## lemma-platform 参考（github.com/lemma-work/lemma-platform · 267★，Python monorepo）
- 它是什么：开源「人类与 AI agent 协作工作台」——Python/FastAPI 后端 + Next.js 前端 + Python CLI（daemon 跑 claude-code/codex/opencode）+ agentbox 容器沙箱 + OpenAPI 生成 SDK。核心模块：agent（多 harness 抽象）、agent_surfaces（Slack/Teams/Telegram/WhatsApp/Gmail/Outlook 多平台入口+回写）、pod/subagent/workflow（编排）、approval gating（human-in-loop）。
- 竞品判定：**非 Archer 竞品**（它是云端多租户 server 平台，Archer 是单机 macOS 原生 Swift 座舱）。形态/栈/核心价值全错位，代码零可移植（Python↔Swift）。但 harness 抽象与 Archer 多 agent 模板、showagent 整合、SkillsView 有同源思路，可借。
- **可抄思路 A · harness 统一抽象层**：lemma 用统一接口封装 claude-code/codex/opencode（daemon 层 `claude_code.py` 等）。Archer 已有 `AgentTemplate`（多 agent），但缺「统一会话/转换层」——刚做的 showagent 整合是雏形。落点：深化成 Archer 的「agent 互操作层」，统一各 agent 会话的列举/转换/恢复，而非各模板各自为政。
- **可抄思路 B · subagent/workflow 编排**：Archer 目前平铺 tab，缺 pod/workflow 式组合编排（一个单元组合多个 agent + DAG）。可参考不照搬。
- **可抄思路 C · approval gating（human-in-loop）**：Archer 的 CommandPalette 激活即执行，缺「危险操作先确认」门控。lemma 的 approval session 模型可借鉴（已落 `## Engineering Guardrails` 部分覆盖：git push/删文件需确认）。
- **可抄思路 D · skills 市场化元数据**：Archer SkillsView 已有 discover/install，可比照 lemma 的 `skill_loader` 做更细的 frontmatter/触发统计。
- **不抄**：agentbox 容器沙箱（Docker/Podman/K8s）、surfaces（Slack/邮件/IM 多端）、OpenAPI 微服务架构、K8s 编排——与 Archer 本地桌面单用户定位冲突，且引入远端依赖违背「本地优先」。
- 最小 SDD（功能点 `agent-interop-layer`，思路 A 深化）：
  - 目标：把 showagent 整合从「单一二进制桥接」升级为「Archer 原生 agent 会话总线」——统一列举本地所有 agent（Claude/Codex/Gemini/Opencode/Hermes）的会话，支持跨 agent 检索/转换/恢复。
  - 落点：`ShowAgentBridge` 抽成 `AgentSessionProvider` 协议，各 agent 实现自己的 `listSessions()/convert()/resume()`；CommandPalette 与 Dashboard 共用同一数据源，替代现在散落的 `AgentTemplate` + `UsageCollector` + showagent 三套。
  - 红线：不引入 Python/服务端；纯 Swift 重写 lemma 思路；不改各 agent 本体；本地优先。
- 状态：仅记 SDD，未实现。


## yibie/skills-manager 参考（github.com/yibie/skills-manager · 原生 macOS app，公开仓库）
- 它是什么：原生 macOS app，统一管理跨 agent（Claude Code/Cursor/Codex/Gemini CLI/Qwen Code/Roo/Continue/OpenHands…）的 skill——发现（skills.sh + 社区源）、安装（单/多 agent）、测试（内置 LLM sandbox）、管理（更新/删除/收藏）、实时监控各 agent skills 目录、翻译技能描述。
- 竞品判定：**直接竞品**（同赛道同平台，原生 macOS skill 管理器）。但栈不同（TS/React/Node，Archer 是纯 Swift/Foundation），**只抄建模哲学，不抄代码**。
- **核心印证（2026-07-10）**：其 `Skill` 数据模型**完全没有 triggerCount / 使用次数 / 最后触发**字段——活跃/管理维度是纯安装态：`isInstalled` / `compatibleAgents`（跨 agent 分布）/ `isStarred` / `version` + 各 agent skillsDir 实时扫描（monitor in real time）。这反证 Archer 原 `seedTriggerInfo`(hash 伪造"45 天触发")是错误设计，已据此改为真实 `endpointCount`(跨端副本数) + `lastModified`(mtime)。
- **可抄思路**：① 跨 agent 安装态聚合（哪些 agent 装了同一 skill）→ Archer 已有 `agentPresence`/`endpointCount`，对齐；② 收藏（star）概念 → Archer 可加 `isStarred` 字段 + 筛选；③ 内置 LLM sandbox 测试 skill → 超出 Archer 座舱边界（Archer 不执行 skill 逻辑，只管理文件），不抄。
- **不抄**：TS/React 代码栈、其 AgentRegistry 的 agent 列表（Archer 用 `agentDefs` 单一派生，见 STATE §2）、其插件缓存（`.claude/plugins/cache`）扫描逻辑（Swift 已原生覆盖）。
- 状态：Archer 已落地对齐项（真实端点数/修改时间），无新增代码待做；star 筛选为可选增强，未排期。

## terminal-control 参考（github.com/kitlangton/terminal-control · 实际归属，anomalyco 为组织跳转；Rust CLI `termctrl`，292★，2026-07-11 仍在更新）
- 它是什么：给 agent 用的「终端应用驱动器」——用真实 PTY 驱动 TUI/curses/OpenTUI 应用，确定性读「可见屏幕状态」、发精确键盘输入、显式 wait、录时间线+命名标记、导出带剪辑的 MP4。MIT 许可，依赖极少（portable-pty / vt100 / resvg / clap）。工程纪律硬：cargo test + clippy -D warnings + cargo fmt --check + changeset + 三套 JSON schema（frame-v1 / recording-entry-v1 / video-edit-v1，全 `deny_unknown_fields`）。
- 竞品判定：**非 Archer 竞品，互补**。形态/栈/核心价值错位——termctrl 是单一终端驱动器（CLI），Archer 是多 agent 座舱（macOS 原生 Swift/ghostty）。Archer 已有 ghostty 提供 PTY+渲染，终端底层不缺。termctrl 的独特增量是**录制格式 + 标记剪辑工作流 + 确定性回放导出**，不是 PTY 本身。
- 真实架构（已读源码确认）：
  - 录制 `recording.rs` `Writer`：PTY 原始字节 + `at_ms` 时间戳 + `marker` 写进 `.termctrl` JSON Lines，`entry` 分 `output/input/resize/marker`，input 带 `origin`(client/host)，文件权限 `0o600`。
  - 回放 `replay()`：原始字节喂 `vt100` 解析器重建屏幕，帧变化才存一帧 → 确定性，不靠像素抓取。
  - 渲染 `render.rs`：每帧 `Frame` → 自建 SVG（**硬编码 JetBrains Mono + 固定深色**）→ `resvg` 出 PNG。
  - 剪辑 `video-edit-v1`：用**命名标记**选片段（非时间码），带 `speed`/`hold_ms`/`caption`。
  - 编码：`video()` 只 `read()` 文件、不 spawn PTY → 纯消费者；ffmpeg 按 fps 拼 PNG 成 MP4（`yuv420p +faststart`）。
- **可抄（仅格式 + 工作流，不抄代码）**：
  - ① `.termctrl` 录制格式（引擎无关：ghostty 吐的就是标准 VT 字节）→ Archer 让 ghostty 顺手把 PTY 字节 + Cockpit 里用户点的「标记此刻」写成 `.termctrl`，零 PTY 冲突（termctrl 的 `video` 子命令不碰 PTY，只读文件）。
  - ② 命名标记剪辑工作流 → 用户跑 agent 操作 CLI 时打点，导出只含关键片段的 demo 视频（bug 复现 / 教学）。
- **不抄**：termctrl 的 `start/send/wait` PTY 驱动内核（与 ghostty 抢同一 PTY，冲突）；其硬编码字体/深色渲染（与 Archer 主题冲突，且不匹配 Theme.swift 配色）。
- **严格升级（可选，长期）**：借它的 `.termctrl` 格式 + 标记剪辑工作流，但**渲染层用 Archer 原生主题替代 resvg**——用 SwiftUI/Core Text 按 Theme.swift 字体和配色渲染同一份 `.termctrl`，让 demo 视频与 App 本身同款外观（termctrl 做不到）。混合集成路径：Archer(ghostty 录字节) → `.termctrl` → 导出处（短期 `termctrl video` 渲，长期 Swift 原生渲）。
- 最小 SDD（功能点 `session-recorder`）：
  - 配置：Archer 设置里「录制当前会话」开关 + 输出目录（`~/.archer/recordings/`）。
  - 录制：ghostty 增加字节旁路（tee PTY 输出 + 转发输入），按 `.termctrl` schema 写 `header/output/input/resize`；Cockpit 加「⚑ 标记」按钮写 `marker` 帧。
  - 导出：短期 shell 调 `termctrl video <file> --edit <clip.json>`（已装 `cargo install terminal-control` 即可用）；长期加 `RecordedSessionExporter` Swift 原生渲染（读 `.termctrl` → Core Text 绘帧 → AVFoundation 编码 MP4）。
  - 红线：不引入 termctrl 的 PTY 驱动；录制文件 `0o600`；不自动录（须用户显式开，防敏感终端内容落盘）。
- 状态：**已落地（2026-07-16 文档回填；实现提交 `4ba0020`）**。`SessionRecorder` / `TermctrlRecorder` / `RecorderStore`：设置开关（默认关）；`WorkspaceStore` 仅在启用时挂录制；Libghostty 旁路写 input + 标记；状态栏 marker；单测保证 schema-clean 导出。长期「Swift 原生按 Theme 渲染 MP4」仍属可选增强，未做。

## kooky 参考（github.com/iAmCorey/kooky · 544★，Swift monorepo）
- 它是什么：原生 macOS SwiftUI + libghostty 的「AI coding 终端」。README 描述与 Archer 一字不差（sidebar 工作区 / 分屏 / 一键 agent / per-agent 活动点 / live workspace state / libghostty 渲染 / 本地优先 / MIT）——是 Archer 的**同源直接 fork**（同栈同架构，v0.35 与 Archer v1.0.7 分头演进）。作者 iAmCorey 基于 archer 早期版本派生后各自发展。
- 竞品判定：**同源直接竞品（同栈，可代码移植）**。与 Kaku（Rust/WezTerm fork）、lemma（Python 平台）不同——kooky 与 Archer 共用 SwiftUI+libghostty 同一套代码形态，**可直接移植其 Swift 模块**，无需跨栈重写。按「抄」规则：借思路 + 原生同栈移植 + 不改其架构哲学。
- kooky v0.29–v0.35 增量盘点（对照 Archer 现状）：
  - ✅ **Recent project folders**（v0.35，issue #28）：`File → Open Recent` + ⌘P 最近项目入口。Archer 当前**完全缺失**（无 recent 列表），可直移植 `RecentFolders.swift` + palette/菜单接线。**已落地（2026-07-14）**。
  - ✅ **File-tree git diff badges + resizable sidebar**（v0.33）：Archer 已有 `SidebarFileTree.swift` 与 `PanelWidths.swift`（resizable 已有），仅缺逐文件 git 状态标。潜在可抄 `GitStatusFetcher` 标 M/A/D 角标（未实现，记 SDD）。
  - ✅ **SSH workspaces**（v0.34）：把远程主机当 workspace 开（不只状态显示）。Archer 现仅 Remote Login 状态位（`RemoteLoginMarker.swift`），无 SSH workspace 能力。跨栈但同 Swift，可参考 `sshRemoteHost` 模型（未实现，记 SDD）。
  - ⚠️ resizable sidebar / fish shell / vsync 120Hz：Archer 已有或引擎层已具备，**非缺口**。
- **已抄（2026-07-14）· Recent project folders（零越界安全子集）**：
  - 新增 `Sources/ArcherKit/App/RecentFolders.swift`：移植 kooky 的 `RecentFolders`（全局 LRU，cap 20，独立 `recent-folders.json`，排除 HOME，dead entry 显示态过滤）；`// [archer]` 标注。
  - `WorkspaceStore`：加 `noteRecentFolder` 注入回调（同 kooky 形状，测试默认 no-op）；`addWorkspace` 走完 spawn 后调 `noteRecentFolder(workspace.workingDirectory)`，Home 兜底由 `RecentFolders.note` 自身排除。
  - `CommandPalette`：`PaletteItemKind.openRecentFolder(path:)` + `PaletteIndex.build` 接 `recentFolders` 参数（过滤已开 workspace）+ `.match` 已支持；`AppDelegate.activate` 路由到 `activeStore.addWorkspace(workingDirectory:)`。
  - `AppDelegate`：`File` 菜单下加 `Open Recent` 子菜单（`OpenRecentMenuDelegate` 每开重建），`addWindow` 接线 `noteRecentFolder: { RecentFolders.shared.note($0) }`。
  - 测试：`Tests/ArcherKitTests/RecentFoldersTests.swift`（LRU/去重/cap/HOME 排除/持久化），移植 kooky 同款断言形状。
- **潜在可抄（仅 SDD，未实现）**：
  - `filetree-diff-badges`：在 `SidebarFileTree` 每行角标接 `GitStatusFetcher` 的 per-file status（M/A/D/U），复用 Archer 已有 `GitWatcher` 文件系统层刷新；不引入 kooky 的 kqueue fd 实现（Archer 已有等价）。
  - `ssh-workspace`：加 `Workspace.sshRemoteHost` + `addWorkspace(sshRemoteHost:)`，spawn 走 `ssh user@host` 而非本地 PTY cwd；状态位沿用 `RemoteLoginMarker`。红线：不引入 kooky 的 SSH 库依赖，纯 `ssh` CLI 封装。
- 红线：不改 kooky 架构哲学；仅移植 Archer 当前真空白的子集；不引入其新依赖（SSH 库、额外 watcher 框架）。
- 状态：Recent project folders 已落地 + 单测 + 编译验证；diff badges / ssh workspace 仅 SDD。

## muxy 参考（github.com/muxy-app/muxy · 1974★，SwiftPM monorepo）
- 它是什么：原生 macOS SwiftUI + libghostty 的「轻量、省内存终端」，2026-03 起步、2026-07-14 当天仍在更新。已上架 App Store + iOS/Android 伴侣应用 + 扩展市场；README 自述「轻量终端，带富扩展 API」。话题标签：amp/claude/codex/gemini/ghostty/macos/multiplexer/opencode/tmux/terminal。
- 竞品判定：**同源直接竞品，且是更高维度的发行版**。同 SwiftUI + libghostty 栈、MIT、本地优先，但体量远超 Archer/kooky——687 个 Swift 文件、~12 万行，架构已分化出 Archer 没有的子系统。不是「抄几个功能点」的级别，是「平台 vs 座舱」的错位（类似 lemma 之于 Archer，但同栈）。
- muxy 独有不（Archer 缺）的维度（按源码结构确认）：
  - **Extensions 运行时**（37 个测试文件围绕它）：WebView 扩展 + manifest + 权限/consent + 市场 + 命令执行桥。Archer 完全无此层——Archer 是「座舱」，muxy 是「平台 + 扩展生态」。
  - **AIAgentDetector / ForegroundProcessInspector**：自动嗅探前台跑的是哪个 agent（claude/codex…）。Archer 是手动 + hook 驱动，无主动检测。
  - **Mobile companion + remote-server（MuxyAPI）**：跨设备/远程驱动。Archer 是单机桌面。
  - **Skills 反向注入**：`muxy install-skills` 把 muxy-cli / muxy-extension 注入各 AI harness。Archer 的 SkillsView 是自建发现/安装，未做「反向注入到 agent harness」这种 CLI 集成。
- 可借（仅思路，不抄代码/不引入其扩展体系）：
  - ① **agent 自动检测**：**已落地** `5d7b8bf` / `eca968a`——opt-in 前台进程 sniffer（basename 匹配 + 侧边栏使用），不引入 muxy 扩展运行时。
  - ② **skills 反向注入 harness**：**已落地**——`Sources/ArcherKit/Sidebar/SkillsInjector.swift` + SkillsView「导出/注入」；`9210b60` 批量导出改为 **symlink relay（fill-missing）**，不覆盖已有安装、不 destructive copy。纯本地文件操作。
- 不抄：Extensions WebView 运行时、移动伴侣、remote-server、市场后端——与 Archer 单机座舱定位冲突，且引入远端依赖违背「本地优先」。
- 红线：不引入 muxy 的 Extensions 体系或任何远端依赖。
- 状态（①②）：**已落地**（2026-07-16 文档回填）。

## cmux 参考（github.com/soheilhy/cmux · 2760★，Go · Apache-2.0）
- 它是什么：Go 的**服务端连接多路复用器（transport demultiplexer）**——一个 `net.Listener` 收所有连接，按「首字节 payload」嗅探协议，分流到多个虚拟 `net.Listener`，从而在同一端口上同时跑 gRPC / SSH / HTTPS / HTTP / Go RPC 等。核心 API：`m := cmux.New(l)` → `grpcL := m.Match(cmux.HTTP2HeaderField("content-type","application/grpc"))` / `httpL := m.Match(cmux.HTTP1Fast())` / `anyL := m.Match(cmux.Any())` → 各 listener 喂给对应协议 server。性能开销可忽略（只匹配连接最初几个字节，长连接无感知）。已知限制：TLS 下 `http.Request.TLS` 不置位（包了一层 lookahead conn，net/http 类型断言失败）；单连接只能归一种协议（gRPC 或 REST，不能既是）；Java gRPC client 需 `MatchWithWriters` 先发 SETTINGS 帧。
- 竞品判定：**非 Archer 竞品，纯模式参考**。错位在层级（cmux 是传输层库，Archer 是 macOS Swift 终端 app）+ 语言（Go ↔ Swift，零代码可移植）。但它解决的是「单监听器多协议分发」问题——Archer 当前已有 2 个独立本地 unix-socket 服务，正是该模式的雏形场景。
- Archer 现状对照（已确认源码）：
  - `Sources/ArcherKit/Bridge/BridgeServer.swift` — unix socket `bridge.sock`，JSON 单行 request/response（`{"cmd":"list"/"read"/"type"/"keys"/"sync"}`），给 `archer-bridge` CLI 用；用 `DispatchSourceRead` + fd 自管 accept。
  - `Sources/ArcherKit/Sessions/HookServer.swift` — unix socket `Application Support/Archer/socket`，agent hook（`ArcherHook` CLI）单行 JSON 事件（lifecycle / toolCall / conversationId），fork-per-event 写完即关。
  - Cockpit 是**应用内 SwiftUI 视图**（CockpitPanelController），非独立监听器——无 HTTP/WebSocket 端口。
  - 两个 socket 协议不同（有 `cmd` 字段 vs 无 `cmd` 的事件行），但都是「读首行 JSON → 按形状分发」，天然可用 cmux 式首帧匹配合二为一。
- **可借思路（仅模式 + matcher 分类，不抄代码）**：
  - ① **单监听器统一分发（unified-local-listener）**：把 BridgeServer + HookServer 合并到一个 unix socket / 一个 accept 循环，首帧 matcher 按 JSON 形状路由——`has("cmd")` → bridge 路径，`has("event"|"toolCall"|"conversationId")` → hook 路径，等价于 cmux 的 `Match(HTTP1Fast())` / `Match(Any())` 分类思想。收益：少一组 socket 生命周期/权限/重启协调，单一端口收敛（与 muxy 的「平台化多入口」形成对照——Archer 走反向收敛）。纯 Swift `DispatchSource` 即可实现，零新依赖。
  - ② **matcher 分类法作未来扩展蓝本**：若 Archer 后续要补 muxy 缺口（remote-server / 移动伴侣 / Web Cockpit API），cmux 的「首字节匹配 + fallback Any()」是「单端口多协议」的标准解法——届时一个 TCP listener 按 `HTTP1Fast()`(Web UI) / `HTTP2HeaderField`(未来 gRPC/streaming) / `Any()`(bridge 兼容) 分发，避免每加一种协议开一个端口。
- **不抄**：Go 实现（`cmux.New`/`Match` 源码）、其 TLS lookahead 包装导致的 `Request.TLS` 失效细节、Java gRPC SETTINGS 帧特例处理——这些是 Go net/http 生态问题，Swift/NIO 或 `Network.framework` 路径不同。
- 红线：纯 Swift 原生实现，不引入 Go 或任何第三方传输依赖；不改现有 `bridge.sock` / hook socket 的**对外线格式契约**（CLI 与 ArcherHook 已按此对接），合并只改 Archer 内部分发，外部二进制无感；若改契约须版本化（先读 `cmd` 字段再路由，旧 `{"event":...}` 行仍走 hook 路径，向后兼容）。
- 最小 SDD（功能点 `unified-local-listener`，仅思路①，落点确定后实现）：
  - 新增 `Sources/ArcherKit/Bridge/UnifiedListener.swift`：`start()` 建单 unix socket（路径沿用 `bridge.sock`，hook 路径软链/别名兼容），`acceptOne()` 读首行 → `route(_:)` 判定 JSON key 集合 → 分派 `bridgeHandler` / `hookHandler`（复用现有两个 handler 闭包）。
  - 路由判定（纯字段嗅探，等价 cmux matcher）：`if json["cmd"] != nil { bridge } else { hook }`。无需解析完整 JSON，首字段即可。
  - 权限/生命周期：沿用 BridgeServer 的 `0600` owner-only + `removeItem` 清理；HookServer 的 Application Support 路径改为连到同一 socket（或保留旧路径做符号链接兼容 `ArcherHook`）。
  - 默认行为不变：外部 `archer-bridge` / `ArcherHook` 调用方式零改动。
- 状态：**已实现（2026-07-16）**。新增 `Sources/ArcherKit/Bridge/UnifiedListener.swift`（单 unix socket + `DispatchSourceRead` accept + 首帧 `isBridgeFrame` 分类 → bridge/hook 双路）；`BridgeServer` 降级为纯 `handle(_:)` 请求处理器（去掉 socket 代码）；`HookServer` 降级为纯 `parseMessage` 解码命名空间（去掉 socket/start/stop，`@MainActor parseMessage` 保留）；`AppDelegate` 两个 server 合并为一个 `unifiedListener.start()/stop()`。外部契约零改动：`bridge.sock` 仍是主监听器，旧 hook 路径 `Application Support/Archer/socket` 改由 UnifiedListener 建**符号链接**指向 bridge socket（`ArcherHook` CLI 无需改）。新增 `Tests/ArcherKitTests/UnifiedListenerTests.swift`（`isBridgeFrame` 分类 + 真实 socket 往返：bridge 收 JSON 回包、hook 派发到 handler、symlink 校验）。编译通过 + 单测通过。与 muxy 参考 §「Mobile companion + remote-server」缺口互为补充（cmux 是该缺口落地时的传输层解法）。

## codeflow 架构体检（github.com/braedonsaunders/codeflow · 4417★，验证用）
- 用法：codeflow 是纯前端静态架构分析器（单 index.html + CDN），支持「本地文件夹分析」。本环境 browser 工具不可用（agent-browser 二进制缺失），故提取其真实 analyzer 块（与官方 golden test 同 `CODEFLOW_ANALYZER_*` 标记）+ METRICS 块（calcHealth），用 Node 无头跑在 `archer/Sources`，产出与网页 UI 同口径的报告。
- 结果（2026-07-14）：**HEALTH 66/100 · 评级 D**。
  - files 114 / functions 1012 / connections 530 / dead 25（deadPct 2.5%）/ avgCoupling 4.65 conn/file。
  - Issues：13 Large Files（God Object 簇）、41 High Complexity、19 Highly Coupled、16 Circular（启发式，Swift/AppKit 动态调用易误报）、5 Duplicate Names、25 Unused（误报率高：`load`/`save`/`in`/`fetch` 多经 objc/协议动态调用）。
  - **SECURITY 5 high**：已用真实密钥正则复核 Archer 源码——**无硬编码密钥**（sk-/AKIA/xox-/ghp_/私钥/ JWT 均无）。codeflow 的 high 是误报（按标识符名 `APIKey`/`token` 或 base64 形态串命中）。
- 真实可执行结论（剔除误报后）：
  - **主风险 = God Object 簇**：ArcherSettingsUI 2161 / SkillsView 2084 / WorkspaceStore 1807 / ShellIntegration 1673 / LibghosttyEngine 1506 / PaneTreeView 1330 / AppDelegate 1284 行。这几文件是改动/回归高发区，建议优先拆（如 AppDelegate 的菜单/窗口管理、WorkspaceStore 的 worktree/recorder 子职责）。
  - 耦合集中在 `AppDelegate`（fan-in 44）——NSApplicationDelegate hub，属合理，但可下沉协议。
  - 无循环依赖硬证据、无真实安全隐患、无真实死代码。
- 复跑脚本：`/tmp/codeflow-inspect/codeflow-health.mjs`（需在 `/tmp/codeflow-inspect/codeflow-main` 有 index.html）。
- 状态：仅体检，未改动架构；拆文件为可选后续。
