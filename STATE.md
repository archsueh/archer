# STATE · Archer

> 项目工作记忆。五段对应 5 阶段记忆(Fail→Investigate→Verify→Distill→Consult)。
> **两条纪律**:①**走前必写**——每次会话结束更新本文件(试了什么/过了什么/败了什么/新规则);不写则下次从零。②**开局必读**——新会话先读本文件 + CLAUDE.md,再动手;别凭记忆重推已验证过的事实。
> 与 `~/.claude` 全局 memory 的分工:本文件是**项目级、随仓库走**;全局 memory 是**跨项目习惯/偏好**。事实以本文件为准,过期即改。
>
> Verified date: 2026-07-10 · HEAD `535 green baseline`（本文件随下一提交入库）

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

**Heartbeat L1 scaffold (2026-07-11)**: `loop/` 已入库骨架——`guardrails/verify.sh`（Gate: quick=`swift build` / full=`swift test --parallel`）、`loop.sh`（quiet/actionable tick）、seat prompts、`contract.md`、standing-goal 模板。已手跑验证: quiet exit 0；`--gate-only` PASS (build)。**无** cron / auto Installer / trust ledger（L2+）。用法见 `loop/README.md`；全局对照 skill `agentic-os-workflows`。

当前(HEAD `6a47419`,分支 `refactor/usage-parsers`,领先 main 8 commit):

- **分支未推送**:`refactor/usage-parsers` + `chore/usage-tokenscope-stage0` 合计 8 commit,待 merge/push。
- **UsageParser 协议化已完成** (commit `805406f`): protocol + 4 parser 文件 + collect() 循环化,501 test 全绿。
- ~~Gemini 实现~~ **2026-07-10 已回退**:`GeminiParser.swift`(含 `UsageRecordSource.nativeGemini`、`SessionLiveUsageSource.gemini`、UsageView 的 antigravity 分支)全部删除。原因:本机只有 Archer wrapper 与 Antigravity CLI,无原版 gemini-cli 真实数据;`~/.gemini/antigravity-cli/conversation_summaries.db` 探测保留为"发现存在但不收集"。`Tests/ArcherKitTests/GeminiParserTests.swift` 一并移除。Stage 2 heatmap 接入:`YearHeatmapView`(53×7 GitHub 式网格,读 `UsageStats.yearlyTokens` 轻量日聚合字典,窗口 365 天)。`UsageViewModel.collectYearlyTokens()` 走 Claude/Hermes SQLite GROUP BY day + Grok jsonl,仅存 day→sum。535 tests / 0 failures。

**tokenscope 集成**:Stage 1 `PricingProvider` **已提交**(`9dc0bc9`,实现+测试)。Stage 2 `UsageParser` 协议化 **已完成**。余下:heatmap/donut 视图、MCP/Skill 成本归因(见 `docs/usage-tokenscope-plan.md`)。

**Session live cost (P1a+P1b+P1c, 未提交)**: 状态条 session $ pill — Claude/Grok/Codex/Gemini。P1c:`SessionLiveUsageMonitor` 文件 watch(DispatchSource)+200ms debounce, 日志未就绪时最多重试 30s；`SessionLiveUsagePaths` 解析 watch 路径；append 时只 parse 被监视文件。余下:Pi/omp usage parser；Gemini conversationId hook 镜像。

_(此处只列当前未决项;修完即移到 §1 或 §4。)_

---

## 4. Lessons learned(stage 4 蒸馏)

- 新增 agent 时最大的坑不是加,是"加漏"——多处硬编码不同步。宁可先搜清所有引用点再动。
- 窗口/面板类改动"编译通过 ≠ 行为正确";AppKit 生命周期约束不显式,必须走 §2 checklist。
- **memory 会过期**:2026-06-29 的 memory 声称 ArrowRouter/2999/Chat 面板"已建/存在",到 2026-07-02 全已下线。→ 对任何"某路径/服务存在"的断言,动手前用 `ls`/`lsof` 现验,别信旧记录。这份 STATE.md 的存在意义就是收敛这种 drift。
- **一个工作树只容一个 agent 会话**:2026-07-03 两个会话("已中断"实未死的 `agy --continue` + 新会话)在同一工作树竞争提交——pre-commit hook 的 `git add -u` 会把对方在途改动静默卷进自己的 commit(产物 `c85f514`,后被拆分重写)。→ ①"会话中断"要用 `ps`/`lsof` 现验,别信直觉;②开工前确认没有别的 agent 持有该工作树;③拆分提交时,hook 会 `git add -u`,必须先把无关改动 stash 走。

---

## 5. Last session(stage 5 — resume,别 restart)

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
