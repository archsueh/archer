# Archer Backlog

## worktree-per-agent 会话隔离（大部分已实现）
- 来源：双竞品信号（stablyai/orca 与 jamesrochabrun/AgentHub 各自独立做了 worktree 管理，2026-07-06 调研）+ 自身事故（STATE.md §4，2026-07-03 两会话共用工作树导致 commit 污染）。
- **已实现**（先于本条目存在，2026-07-06 侦察修正——旧记录误标"未实现"）：`WorktreeManager`（全部 git worktree 写操作）、sidebar 创建/adopt（`CreateWorktreeSheet`）、右键 Parallel Task（N worktree 各跑一个 agent + prompt）、关闭确认链（`isLastTabInWorktree` → `requestCloseWorkspace` → remove + `deleteBranchIfMerged`）。
- **2026-07-06 新增**：`+` 菜单 agent 行尾 branch 副按钮，一键"在新 worktree 中打开该 agent"（`openTabInNewWorktree`，自动分支名 `archer/<agent>-<rand>`，非 git 仓库不显示按钮）。
- **残余（真 backlog）**：① 关闭 worktree 时的"合并回主树"选项（现只有 删除/保留/取消）；② worktree diff 汇总视图（DiffPanel 已可指向单个 worktree，缺跨 worktree 总览）。
- 设计红线：默认行为不变；worktree 目录放 repo 同级（沿用现有约定）；不做 AgentHub 式 GitHub PR/issue 集成（超出座舱边界）。

## 边缘活动辉光（borrow from EdgeGlow）
- 来源：github.com/vector4wang/EdgeGlow（macOS 菜单栏，屏幕边缘 marquee 辉光示意 AI agent 活动）。
- 借鉴点：复用 archer 已有的 Claude Stop/Notification/turn hook 信号 + activity 三态色，做一圈克制的窗口/屏幕边缘辉光，作为提示音之外的余光视觉确认。
- 技术：Swift/AppKit CAShapeLayer + CVDisplayLink 驱动 lineDashPhase，四层 neon；零依赖，可直接移植。
- 设计红线：EdgeGlow 默认彩虹霓虹，与 archer brutalist-minimal（低对比/零阴影/克制）冲突。archer 版必须单色、窄、克制、可关，用 activity token 色（running #69B0D6 / attention #E8B068 / failure #E86666），绝不彩虹。
- 状态：待写最小 spec（SDD），未实现。

## claude-mem 参考（github.com/thedotmack/claude-mem）
- 它是什么：Claude Code 跨会话自动记忆（5 hook 捕获→AI 压缩→下次注入，SQLite+Chroma+:37777 web viewer）。
- ① archer memory 面板（archer 范围）：其 worker+SQLite+web viewer 架构可作 archer "agent 记忆/上下文面板"的蓝本，archer 已读 agent DB 做 Usage 仪表盘，加 memory 视图顺路。
- ② 个人工作流可控试用（非 archer）：与 hsueh 现有手动 MEMORY.md/memory 文件/claude-handoff 重叠且哲学冲突（自动全量捕获 vs 人工高信噪策展）。如试，read-only 评估捕获质量，勿直接替换手动流程，勿两套记忆并行打架。

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

## yibie/skills-manager 参考（github.com/yibie/skills-manager · 原生 macOS app，公开仓库）
- 它是什么：原生 macOS app，统一管理跨 agent（Claude Code/Cursor/Codex/Gemini CLI/Qwen Code/Roo/Continue/OpenHands…）的 skill——发现（skills.sh + 社区源）、安装（单/多 agent）、测试（内置 LLM sandbox）、管理（更新/删除/收藏）、实时监控各 agent skills 目录、翻译技能描述。
- 竞品判定：**直接竞品**（同赛道同平台，原生 macOS skill 管理器）。但栈不同（TS/React/Node，Archer 是纯 Swift/Foundation），**只抄建模哲学，不抄代码**。
- **核心印证（2026-07-10）**：其 `Skill` 数据模型**完全没有 triggerCount / 使用次数 / 最后触发**字段——活跃/管理维度是纯安装态：`isInstalled` / `compatibleAgents`（跨 agent 分布）/ `isStarred` / `version` + 各 agent skillsDir 实时扫描（monitor in real time）。这反证 Archer 原 `seedTriggerInfo`(hash 伪造"45 天触发")是错误设计，已据此改为真实 `endpointCount`(跨端副本数) + `lastModified`(mtime)。
- **可抄思路**：① 跨 agent 安装态聚合（哪些 agent 装了同一 skill）→ Archer 已有 `agentPresence`/`endpointCount`，对齐；② 收藏（star）概念 → Archer 可加 `isStarred` 字段 + 筛选；③ 内置 LLM sandbox 测试 skill → 超出 Archer 座舱边界（Archer 不执行 skill 逻辑，只管理文件），不抄。
- **不抄**：TS/React 代码栈、其 AgentRegistry 的 agent 列表（Archer 用 `agentDefs` 单一派生，见 STATE §2）、其插件缓存（`.claude/plugins/cache`）扫描逻辑（Swift 已原生覆盖）。
- 状态：Archer 已落地对齐项（真实端点数/修改时间），无新增代码待做；star 筛选为可选增强，未排期。
