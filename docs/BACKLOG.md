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
