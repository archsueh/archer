# STATE · Archer

> 项目工作记忆。五段对应 5 阶段记忆(Fail→Investigate→Verify→Distill→Consult)。
> **两条纪律**:①**走前必写**——每次会话结束更新本文件(试了什么/过了什么/败了什么/新规则);不写则下次从零。②**开局必读**——新会话先读本文件 + CLAUDE.md,再动手;别凭记忆重推已验证过的事实。
> 与 `~/.claude` 全局 memory 的分工:本文件是**项目级、随仓库走**;全局 memory 是**跨项目习惯/偏好**。事实以本文件为准,过期即改。
>
> Verified date: 2026-07-16 · BACKLOG 已与 git 交叉核对 · 当前分支见 §5

---

## 1. Verified facts(stage 3 — 停止猜测)

已实地核实(`2026-07-02`),别再猜:

- **构建**:`swift build` / `swift test` / `swift run`;清缓存 `rm -rf .build`(SwiftPM,非 Xcode 工程为主)。
- **主模块**:`Sources/ArcherKit/` 下 App / Bridge / Cockpit / Dashboard / Diff / EdgeGlow / Resize / Sessions / Settings / Sidebar / Terminal / Usage / Utilities 等。
- **Bridge(P0/P1 已落地并在跑)**:`Sources/ArcherKit/Bridge/` = PaneRegistry.swift + BridgeServer.swift + BridgeEventLog.swift + LogPanelView.swift。运行时 socket:`~/.archer/bridge.sock`(存在=服务活着)。
- **Skills(独立,2026-07-03 起不依赖 CC Switch)**:安装注册表 `~/.archer/skills.json`(JSON `InstalledSkill` 数组;cc-switch.db 读写、「管理」按钮、`import SQLite3` 已全部移除)。搜索源 `https://skills.sh/api/search`。「发现技能」原生安装(GitHub Contents API 递归下载,`resolveGitHubToken`:env → `gh auth token`,认证 5000 req/hr;匿名仅 60/hr 极易耗尽——2026-07-03 「安装拉不起来」的根因就是匿名限流,不是死链)。「检查更新」已实现:按 upstream repo 去重查 `commits?per_page=1`,commit 时间 > max(installedAt, updatedAt) 即标橙。⚠️ skills.sh 的 skillId ≠ 仓库目录名(例:市场名 vercel-react-best-practices → 实际 `skills/react-best-practices`),featured/安装 id 必须用仓库路径。扫描本地 agent skills 目录 + 健康检查 + 跨端去重 + symlink 继电器不变。
  - **[2026-07-11 修复] 更新卡死 + 无进度反馈**:根因是 `URLSession.shared.data(for:)` **零超时**——GitHub API 实测单次 5.6s(带 auth),递归下载一技能十几~几十次请求,任一网络波动即永久挂起 → 更新 `Task` 卡死 = 用户看到"无法更新" + 无限转圈无倒计时。修复:`SkillsView.apiSession`(30s 请求超时 + `waitsForConnectivity`)、`makeAPIRequest` helper、所有 GitHub 调用(检查更新/搜索/递归下载/master 回退/文件下载)换用并加 `timeoutInterval=30`;文件下载改 `bytes(for:)` 流式以接入字节进度;`updatesView` 顶部加 `updateProgressBanner`(N/M 已完成进度条 + 每秒刷新的 ETA 倒计时),Hermes 更新加"更新中…"文案。编译 0 错、`swift test` 531/0。v1.0.7 已部署。
- **Glass 全局基线(不可被 per-theme 覆盖)**:`Theme.glassOpacity` / `chromeBackgroundBlur` / `chromeBackgroundSaturate`(见 `Theme.swift`)。`aver-light` 象牙白 `#FDF9F4` 是外观基准。
- **知识循环(你自建,在跑)**:`scripts/knowledge-loop/kl.py`(ingest→detect→propose→approve→re-verify)+ `com.hsueh.knowledge-loop.plist`;manifest 在 `~/Documents/Notes/Knowledge/.knowledge-loop/manifest.yaml`,含 proposals/ queue/ snapshots/;最近扫描 2026-07-02 08:30(`scan.log`)。已入 `.gitignore`(本地运维,不入库)。
- **更新器 = Sparkle 2.9.4**(`2b7d20a`):`SPUUpdater` + 自定义 `ArcherUpdateUserDriver`/`UpdateFlowController`(保 glass 样式);仅手动检查(`SUEnableAutomaticChecks=false`),feed URL 由 `build-app.sh` 注入 Info.plist。旧 `UpdateChecker.swift`(GitHub releases API)已删。
- **定价 = PricingProvider**(`9dc0bc9`):`Usage/PricingProvider.swift` 单一定价源(models.dev 动态 + 内置兜底),`UsageCollector`/`UsageView` 两处硬编码定价表已收敛。
- **Memory 面板 A-mem 化(2026-07-09)**:`Sidebar/MemoryGraph.swift`(纯 Swift/Foundation,零依赖) + `SidebarView.MemoryBankSection` 重写。取代原傻瓜文件列表:解析 `[[wikilink]]`(支持 `[[T|alias]]`)与 `#tag`(先剥 ``` / `` 代码块),建前向/反向链接网络,按连接度(枢纽)排序、标签聚类、孤立项分组;`+` 按钮生成含 `[[ ]]` 占位与 `#记忆` 槽的原子 memo 模板,点击任意行复制 `[[标题]]` 供手动连网。**不自动改写文件、不引入 LLM**——贴合"人工高信噪策展 > 自动全量捕获"哲学。测试 `MemoryGraphTests` ×7 全绿;全量 529/0。memo 目录 `~/Library/Application Support/Archer/memory/claude/<branch>/`(原目录,内容为空时不显示)。
- **项目规则发现(2026-07-09,借 orbiteditor `.cursor/rules` 思路)**:`Sidebar/ProjectRulesSection.swift` 只读扫描当前 workspace 根的 `.archer/rules/*.md`,在侧边栏 Tool 区列出,点击复制 `@<绝对路径>` 供手动引用到 prompt。**不自动注入 agent system prompt、不改 agent 启动环境**——守 STATE §4 隔离边界 + 人工策展哲学。测试 `ProjectRulesSectionTests` ×3 全绿;全量 535/0。
- **本地发布产物**:`./scripts/build-app.sh` → `dist/Archer.app` v1.0.7(adhoc 签名),已覆盖 `/Applications/Archer.app`(quarantine 已清);`dist/Archer-v1.0.7.dmg`(10M)。
- **Skills/Usage 假数据闭环修复(2026-07-10)**:Skills 面板原 `seedTriggerInfo`(用 `name.hashValue % 6` 伪造"45 天触发/活跃数")已删;改为真实信号——`endpointCount`(跨端副本数,group pass 填 `max(1, presence.count)`)、`lastModified`(SKILL.md 真实 mtime)、`isSymlink`(relay 检测);`calculateStats` 活跃数=近 45 天 mtime 修改;表头/排序/行内/状态色"触发"→"端点数/修改时间"。Usage 面板 Claude 栏原写死假值(`getUsagePercentages` 返回 68/41、`resetsAt==nil` 显示"重置 14:30 · 1h 12m"/"重置 周一 09:00 · 3 天后")已改:`usage==nil` 返回可选 nil → Claude 面板显示"未连接 Anthropic 用量"空态 + `viewModel.error` 真实原因;`resetsAt==nil` 显示"重置时间未知"。实测 `~/.claude/skills` 210 个、skills.sh API 200、ai-workflow tree 200(安装/relay/更新闭环本来就通);`~/.claude/usage.db` 不存在 → Claude 栏走未连接态(符合预期)。Hermes/Grok 栏数据源(state.db/unified.jsonl)本就真实,仅修"基于最近 of API 会话统计"→"基于本地 state.db 会话统计"措辞。参考 yibie/skills-manager(原生 macOS 竞品,其 `Skill` 模型无 trigger 概念,只有 `isInstalled`/`compatibleAgents`,印证方向)。全量 535/0。

**已下线 / 不存在(别再引用旧 memory)**:
- ❌ ArrowRouter 本地路由整套已拆:`~/.archer/arrow-router/router.py`、`com.archer.arrow-router.plist`、端口 2999 **均已不存在**。本地模型(Qwen3/mlx)方向已关闭(`~/.archer/mlx-server.log` 是遗留日志)。
- ❌ `Sources/ArcherKit/Chat/ChatPanelView.swift` 已移除,`Chat/` 目录当前为空(Quick Chat 面板已拆/重构)。

---

## 2. General rules(stage 4 — 重推前先查)

从 git `fix`/`revert` 历史蒸馏的反复踩坑,动相关代码前先读对应条:

- **agentDefs 单一派生**:所有 agent 相关的枚举/列表/路径必须从 `agentDefs` 派生。增删 agent 后,全仓搜硬编码 agent key(`"claude"`/`"hermes"`/`"grok"` 等字符串),逐一换成 `agentDefs.first(where:)` 或循环。历史上 scan paths / filterBar / filteredSkills switch / agentPresence fallback 各自独立维护导致 drift。
- **Glass 基线只读**:加新主题只允许 per-theme override,**绝不改** `glassOpacity`/`chromeBackgroundBlur`/`chromeBackgroundSaturate` 三个全局值。改 `Theme.swift` 前先确认没碰这三个。
- **`--resume` 两层 guard**:任何 resume 改动同时查两层——① Wrapper 层:session 文件存在才传 flag;② Agent 启动层:收到 flag 二次确认文件有效,无效则 silently drop。
- **NSWindow 生命周期**:新增 NSWindowController 立即定:①`isReleasedWhenClosed`(面板 false 保活,主窗口默认 true);②是否在 `windowControllers` 里,不在则需在 `handleWindowWillClose` 补 cascade-close。
- **面板 = 独立窗口时清理导航残留**:把 in-app screen 提升为独立 NSWindow 后,删掉 View 里所有"回父容器"的调用(`store.activeScreen`/`dismiss`/`presentationMode`——面板持孤立 store,这些形同虚设),改用 `window.close()`。最后一个主窗口关闭时,面板不在 `windowControllers` → AppKit 不触发退出 → 僵尸态;修复靠 `handleWindowWillClose` 里遍历 `NSApp.windows` cascade-close,**别用** `NSApp.terminate(nil)`(太暴力)。
- **Skills mutation 必落盘**:对 SkillItem 的修复/中继/删除,操作后必须同步磁盘文件,不能只改 `@State private var skills`。

**AI Collaboration & Memory Patterns (solidified from user memory exports 2026-07)**:
- **Evidence-only reviews**: Apply "老规矩" three-phase protocol adapted to code/spec/docs: (1) Logic/structure analysis, (2) Revision check against sources, (3) Formal decisive report. Only cite clear textual/artifact evidence; no speculative padding.
- **Project memory files**: Maintain CLAUDE.md / STATE.md / DESIGN.md as living artifacts. On every nontrivial handoff or new session, surface key models/decisions/progress explicitly. Cross-AI validation (Claude/Gemini/Grok/Hermes) is the norm—treat outputs as candidates until verified.
- **Full artifacts rule**: Any generated code, script, prompt, or config delivered must be complete + runnable + accompanied by changelog or usage notes. Confirm framework + boundaries first for taxonomy/file-org/system tasks.
- **Memory update discipline**: Periodically run "memory update review" passes (as done in export history) to distill new rules, deprecate drift, and keep this file + CLAUDE.md authoritative. Global habits live in ~/.claude or equivalent; project facts here.

**File Organization Taxonomy (reusable pattern from export)**:
Documents by year/project; code → `~/Developer/`; Pictures → `~/Pictures/` by shoot date + EXIF (Camera vs Graphics routing). Use whitelists, project markers for bundling, and read-only scans before moves. See extracted rules in conversation history for the full tree.

---

## 3. Open failures / 进行中(stage 1→2)

**真实产品 backlog（2026-07-16 核对，详 `docs/BACKLOG.md` 文首表）**:  
A 未做= EdgeGlow + workspace-template + parallelTaskGroup + agent-interop-layer + kooky(diff badges/ssh)。  
A 本会话落地= worktree ①合并回主树 + ②跨 worktree Diff 汇总；UnifiedListener 单测硬化。  
B 可选= yibie star / God Object 拆分。  
C 已落地勿重做= session-recorder `4ba0020`、UnifiedListener `47043b6`、MemoryGraph `6f6e683`、sniffer `5d7b8bf/eca968a`、SkillsInjector `9210b60`。

**Heartbeat L1（已入库 `d531d31`）**: `loop/` 骨架齐——Gate / tick / seats / contract / standing-goal 模板。手跑: quiet=0、`--gate-only` PASS。**未做** L2+（cron / trust.tsv / goals 日验 / auto Installer）。

**WIP 勿卷**:分支 `archer/worktree-one-click` 上 `ParallelTaskSheet.swift` 有无关 WIP（Delegation Brief），与 Heartbeat/handoff 无关。

**Usage 线**:面板/session cost pills 已在 `10d952b` 移除；tokenscope 余 heatmap/donut/成本归因若还要做，先确认产品是否还要 Usage 视图。

_(此处只列当前未决项;修完即移到 §1 或 §4。)_

---

## 4. Lessons learned(stage 4 蒸馏)

- 新增 agent 时最大的坑不是加,是"加漏"——多处硬编码不同步。宁可先搜清所有引用点再动。
- 窗口/面板类改动"编译通过 ≠ 行为正确";AppKit 生命周期约束不显式,必须走 §2 checklist。
- **memory 会过期**:2026-06-29 的 memory 声称 ArrowRouter/2999/Chat 面板"已建/存在",到 2026-07-02 全已下线。→ 对任何"某路径/服务存在"的断言,动手前用 `ls`/`lsof` 现验,别信旧记录。这份 STATE.md 的存在意义就是收敛这种 drift。
- **一个工作树只容一个 agent 会话**:2026-07-03 两个会话("已中断"实未死的 `agy --continue` + 新会话)在同一工作树竞争提交——pre-commit hook 的 `git add -u` 会把对方在途改动静默卷进自己的 commit(产物 `c85f514`,后被拆分重写)。→ ①"会话中断"要用 `ps`/`lsof` 现验,别信直觉;②开工前确认没有别的 agent 持有该工作树;③拆分提交时,hook 会 `git add -u`,必须先把无关改动 stash 走。
- **Agentic OS 三原则**(2026-07-11 蒸馏):Laws not tips；Nothing grades its own homework（Planner/Worker/Verifier/Gate 分离，Gate=bash）；Goals graduate（完成→日验 invariant）。Fable 不当 24h Worker；Verifier 必须 fresh context。
- **autoskills（midudev）不需要整包**(2026-07-11):你已有 Archer Skills + 大量本地 skill；其价值仅「策展 registry + hash lock」可借鉴。别往 Archer 根 `npx autoskills -y`。CC BY-NC。
- **Meng 落地页 skill ≠ archviz 主干**:只嫁接核校层（字距/真图/伪影/readiness），不替换网格与三套视觉语言。

---

## 5. Last session(stage 5 — resume,别 restart)

**2026-07-16 · worktree A.1 闭环 + UnifiedListener 单测（Grok）**

- **分支**:`main`（领先 origin 视 `git status`）。
- **文档**:`3b8eaeb` BACKLOG 回填。
- **A.1①** `42660ab` merge into main tree on close。
- **UnifiedListener** `851bbc3` 可测化 + 4 测绿。
- **A.1② 跨 worktree Diff 汇总**（本切片）:
  - `DiffModel` multi-root `summaries` + `focus`
  - `DiffPanelView` WORKTREES 概览
  - `WorkspaceStore.worktreeFamilyMembers` + ContentView 注入
  - `DiffModelTests` 5 绿（含 family overview）
- **Next**:A.2 EdgeGlow / A.3 template / A.4 parallel 聚合；worktree 线可停。

**2026-07-12 · 会话收尾日志（Grok · 重启前写）**

- **分支**:`archer/worktree-one-click`（相对 origin 视情况；本会话入库 commit 见下）。
- **本会话做了什么**:
  1. **调研** [MengToFrontend](https://github.com/Kappaemme-git/MengToFrontend)= Codex 落地页 anti-slop skill，不是完整前端 app。
  2. **archviz-layout 优化**（仓 `~/Developer/archviz-layout`）:加 **Meng-style Board Polish** + Pre-Flight A/B；同步 `skills-master` / cc-switch；commit `765b221`。
  3. **Agentic OS / Fable 5 九图**:源 [JOJO 清晰版 01–03](https://x.com/zouyanjian/status/2075444045036519836) + Avid 长文机制；全局 skill `~/.agents/skills/agentic-os-workflows/`（SKILL + HARNESS-GAP + assets 01–03）；笔记 `~/Documents/Notes/AI/Agentic-OS-Fable5-Workflows.md`。04–09 为文字重建（无公开高清）。
  4. **Archer `loop/` L1**:commit **`d531d31`** — `verify.sh` / `loop.sh` / seats / contract；quiet+gate-only 已手跑 PASS。
  5. **autoskills**:结论=你不特别需要（见 §4）。
  6. 同分支上另有 **`ba24bc1`** hand off 菜单（他会话/已提交）；`ParallelTaskSheet` 仍可能有未提交 WIP。
- **验证**:`./loop/loop.sh` exit 0；`./loop/loop.sh --gate-only` swift build PASS。未跑全量 `swift test`（gate full）。
- **未推送**:loop 与 handoff 相关 commit 是否已 push 以 `git status` 为准；本文件 STATE 若未 commit 则下次先 `git status`。
- **Next（重启后优先序）**:
  1. 读本 §5 + `loop/README.md`；需要时 `./loop/loop.sh --status`。
  2. L2 任选：真实 work-order 跑 actionable 路径 / goals 日验脚本 / trust.tsv——**别**一上来 cron auto。
  3. 勿混 `ParallelTaskSheet` WIP。
  4. archviz 成图任务强制 Board readiness 输出块。

**2026-07-12 · 右键"Hand off to…"跨-agent 交接（分支 `archer/worktree-one-click`；后已 commit `ba24bc1`）**

- **先纠正一个过时计划**:plan `~/reports/polished-growing-cupcake.md` 的 **A(worktree 一键隔离)整块早已完工并提交**(`5571e22 feat(sessions): one-click agent tab in fresh worktree`)——`openTabInNewWorktree(source:template:)` @ `WorkspaceStore.swift:368` + `+` 弹窗 hover 副按钮 @ `TabBarView.swift:138-163` + `OpenTabInNewWorktreeTests.swift` 三件套齐。别再照 plan A 重建。plan 的 C(Usage)也已作废(见全局 memory `ref-facet-competitors`:opentab 竞品占位 + 用户已在最新版剔除 Usage 整块)。
- **本次实做(计划外的新功能,非 plan)**:侧栏工作区右键菜单加"Hand off to…"区——列所有非-shell 编程 agent,点选 = 在**该工作区同 cwd** 开一个新 agent tab(换 agent、**不续会话**:跨 agent 无共享 conversationId)。为多-CLI 用户提供"在工作区 Y 干活时从侧栏甩 Grok 到工作区 X"的路径。后端零缺口(复用 `addTab(in:template:)`),纯加菜单入口。
  - 改动:`SidebarWorkspaceRow.swift` 加 `onHandoff:` 回调 + `handoffTargets`(=`visibleOrdered.filter{!$0.isShell}`)+ 菜单区(禁用行当小标题 + agent 行);`SidebarView.swift` 三处构造点(565/848/915)接 `{ activate; store.addTab(in:ws, template:$0) }`。
  - 验证:`swift build` 干净;`swift test` **522/0**。未加单测(逻辑仅一个过滤器,底座 visibleOrdered/addTab 已有覆盖;剩为 view 接线)。
  - **已 commit** `ba24bc1`。工作区或仍有**无关 WIP**:`ParallelTaskSheet.swift` 的 Delegation Brief——勿与 loop/handoff 混提。
  - 语义决策存档:用户在"同-CLI 换模型 vs 跨-agent 交接"里选了**跨-agent**。同-CLI 换模型(resume+`--model`,`role`.reviewer/.implementer 已是代码概念,是 Oracle 成本路由的 GUI 出口)留作**未来可做**,未实现。

**2026-07-11 · 旁线 handoff（云南美育 PPT，非 Archer 主线）**

- 工作目录：`~/Documents/Notes/教学-云南美育培训0709/`；完整日志：`SESSION-LOG-2026-07-10.md`（重启先读此文件）。
- 已改 `ppt/index.html`：①自习 03/12 脚注 →《认知觉醒》元认知/对模糊零容忍；②END 金句末条 → 恢复信条「审美的边界……承认渺小」；主课 L1638 信条未动。
- 规则：信条句禁止「优化」成「语言的边界」；书抬维度、不替换血肉；五步=元认知闭环。
- Archer 主线未推进；Next 仍见下方 Archer 条目。若下一会话做美育课 → 读 Notes 日志；若做 Archer → 忽略本条，接 07-10 Usage 切片。

**2026-07-09** · HEAD `6c79bd0`,分支 `main`。P1a–P1c session live cost(未 commit)。

- P1a/P1b: multi-agent $ pill + PricingProvider fold。
- P1c: `SessionLiveUsageMonitor` + `SessionLiveUsagePaths`;pill 取消 5s 轮询,改 file watch;watch 回调单文件 parse。
- 验收:`SessionLiveUsageTests` 15 + StatusBar 3 绿。
- Next:提交本切片;tokenscope heatmap/donut;可选 Pi usage / Gemini conversationId hook。

**2026-07-03** · HEAD `e7b5f36`,分支 `chore/usage-tokenscope-stage0`(领先 main 6 commit,未推送)。

- 发生并发会话竞争(见 §4 新规则):旧会话的一锅端 commit `c85f514` 已被拆分重写为 `9dc0bc9 feat(usage): PricingProvider`(混入 droid.png 图标,hook 所为,无害)+ `2b7d20a feat(update): Sparkle 2.9.4` + `7ca06c2 fix(skills): GitHub token`。竞争的收束:旧会话赶在被终止前提交了 `e7b5f36`(SkillsView 独立化完整版),此后所有并发会话已停,由单会话完成校验与本文件收尾。
- `swift test`:**491 tests / 0 failures**(绿,每个 commit 均经 pre-commit hook 全量验证)。
- v1.0.6 已本地构建并部署(见 §1 "本地发布产物")。

**2026-07-03(续,Skills 独立化落地)**

- SkillsView 去 CC-Switch 化**已完成并提交**(非 stash 版,完整版直接改于工作树):`~/.archer/skills.json` 注册表、checkForUpdates(repo 级 commit 时间对比)、featured 死链修复(react-best-practices)、「管理」→「检查更新」按钮。`swift test` 491/0。
- 重新打包 v1.0.6 并覆盖 /Applications(此前部署的包不含本重构)。
- stash `inflight-skillsview-refactor` 已过时,可 drop(见 §3)。

**2026-07-06 · UsageParser 协议化 + Gemini 调研**

- 分支 `refactor/usage-parsers`(基于 `chore/usage-tokenscope-stage0`,2 commit 领先):
  - `805406f` refactor(usage): extract UsageParser protocol, split collectors to Parsers/
  - `6a47419` feat(usage): add nativeGemini source + agent probe, backlog for protobuf parser
- **UsageParser protocol**: `sourceLabel` + `collect(cache:livePaths:modifiedSince:)`, 4 个 native parser(Codex/ClaudeCode/Grok/Hermes) 各自文件在 `Usage/Parsers/`;ccSwitch 不进 protocol(签名/角色不同);`collect()` 循环化;共享工具暴露为 internal
- **Gemini**: 调研确认 CLI 不落纯文本 token(全在 protobuf blob),降级为 `docs/BACKLOG-gemini-parser.md`;预埋 `nativeGemini` enum + UsageView 探测(检查 `~/.gemini/antigravity-cli/conversation_summaries.db`)
- `swift test`: **501 tests / 0 failures**(含新增 WorktreeManagerTests ×10),零测试文件改动

**2026-07-06(续)· 三工作流收官(竞品调研落地)**

- 三分支全部 ff-merge 回 main(共 4 commit,`swift test` 505/0):
  - `4972b97` feat(skills): ai-workflow 第二发现源(SkillSourceId 枚举、install 前缀参数化、Trees API 168 技能、SkillSourceTests ×7)
  - `5571e22` feat(sessions): `+` 菜单 agent 行 branch 副按钮一键开 worktree tab(`openTabInNewWorktree`,OpenTabInNewWorktreeTests ×3)
  - `805406f`+`6a47419`(另一会话) + 本会话 GeminiParser commit
- **又一次并发会话竞争**(§4 规则第三次应验):本会话按计划做 C 时发现另一会话已在同一分支完成协议化拆分并提交。处置:废弃本会话的重复文件,改为在对方协议上追加。
- **推翻对方 Gemini 结论**:`6a47419` 说"CLI 不落纯文本 token"——调研对象错了(看的是 antigravity-cli/ 的 protobuf DB)。原版 gemini-cli 落纯 JSON(`~/.gemini/tmp/<hash>/chats/session-*.json`,agentsview gemini.go+fixture 为证)。`GeminiParser` 已实现注册,`docs/BACKLOG-gemini-parser.md` 已更正为 Antigravity 条目。
- 工作树残留(未提交,非本会话所有,勿卷入 commit):`scripts/git-pre-commit.sh`(agent 会话跳过全量测试的修改)+ ShellIntegration readlink-f(从 stash 恢复,stash@{0} 本体保留未 drop,由用户决定去留)。

**Next**:① push main(领先 origin 6 commit);② 手动验证三功能(Skills 面板切 ai-workflow 源装一个技能 / git 仓库 `+` 菜单开 worktree tab / 装了 gemini CLI 的机器看 Usage);③ 处置 stash@{0} 与 pre-commit 脚本改动。
- `scripts/git-pre-commit.sh` 有 agent-session 检测(非本次改动,未被提交)

**Next**:① merge/push 本分支;② tokenscope 余下(heatmap/donut、成本归因);③ release 流程(DMG + Sparkle appcast 生成与签名);④ Gemini parser 等 protobuf schema 公开后解锁;⑤ 其余 8 agent(Aider/Cursor/Windsurf/Copilot/Cline/Augment/Qwen/Goose)调研。

**2026-07-10 · 修复 `swift test` fall + 接入 heatmap**
- 根因:`GeminiParser.swift` 被 staged 删除(enum 用例 `nativeGemini`、`SessionLiveUsageSource.gemini`、UsageView antigravity 分支同步清理),但 `Tests/ArcherKitTests/GeminiParserTests.swift` 与 `SessionLiveUsageTests.testToolLabelMapsSupportedAgents` 仍引用 → `swift build` 过、`swift test` 编译失败("always fall")。
- 处置:删 `GeminiParserTests.swift`;`testToolLabelMapsSupportedAgents` 的 `.gemini` 断言改为 `XCTAssertNil`(Gemini usage 已 drop)。
- Stage 2 heatmap 收口:`YearHeatmapView` 此前已建但未接入 → `UsageView.body` 加 `heatmapPanel`,数据来自 `UsageViewModel.collectYearlyTokens()`(365 天轻量日聚合,Claude/Hermes SQLite + Grok jsonl,仅 day→sum 驻内存)。
- `swift test`:**531 tests / 0 failures**(绿)。
- Next:提交本切片(Usage Gemini 回退 + heatmap 接入 + 测试修正);donut 视图与 MCP/Skill 归因(Stage 3)仍待做;release 流程待跑。
