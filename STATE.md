# STATE · Archer

> 项目工作记忆。五段对应 5 阶段记忆(Fail→Investigate→Verify→Distill→Consult)。
> **两条纪律**:①**走前必写**——每次会话结束更新本文件(试了什么/过了什么/败了什么/新规则);不写则下次从零。②**开局必读**——新会话先读本文件 + CLAUDE.md,再动手;别凭记忆重推已验证过的事实。
> 与 `~/.claude` 全局 memory 的分工:本文件是**项目级、随仓库走**;全局 memory 是**跨项目习惯/偏好**。事实以本文件为准,过期即改。
>
> Verified date: 2026-07-06 · HEAD `6a47419`（本文件随下一提交入库）

---

## 1. Verified facts(stage 3 — 停止猜测)

已实地核实(`2026-07-02`),别再猜:

- **构建**:`swift build` / `swift test` / `swift run`;清缓存 `rm -rf .build`(SwiftPM,非 Xcode 工程为主)。
- **主模块**:`Sources/ArcherKit/` 下 App / Bridge / Cockpit / Dashboard / Diff / EdgeGlow / Resize / Sessions / Settings / Sidebar / Terminal / Usage / Utilities 等。
- **Bridge(P0/P1 已落地并在跑)**:`Sources/ArcherKit/Bridge/` = PaneRegistry.swift + BridgeServer.swift + BridgeEventLog.swift + LogPanelView.swift。运行时 socket:`~/.archer/bridge.sock`(存在=服务活着)。
- **Skills(独立,2026-07-03 起不依赖 CC Switch)**:安装注册表 `~/.archer/skills.json`(JSON `InstalledSkill` 数组;cc-switch.db 读写、「管理」按钮、`import SQLite3` 已全部移除)。搜索源 `https://skills.sh/api/search`。「发现技能」原生安装(GitHub Contents API 递归下载,`resolveGitHubToken`:env → `gh auth token`,认证 5000 req/hr;匿名仅 60/hr 极易耗尽——2026-07-03 「安装拉不起来」的根因就是匿名限流,不是死链)。「检查更新」已实现:按 upstream repo 去重查 `commits?per_page=1`,commit 时间 > max(installedAt, updatedAt) 即标橙。⚠️ skills.sh 的 skillId ≠ 仓库目录名(例:市场名 vercel-react-best-practices → 实际 `skills/react-best-practices`),featured/安装 id 必须用仓库路径。扫描本地 agent skills 目录 + 健康检查 + 跨端去重 + symlink 继电器不变。
- **Glass 全局基线(不可被 per-theme 覆盖)**:`Theme.glassOpacity` / `chromeBackgroundBlur` / `chromeBackgroundSaturate`(见 `Theme.swift`)。`aver-light` 象牙白 `#FDF9F4` 是外观基准。
- **知识循环(你自建,在跑)**:`scripts/knowledge-loop/kl.py`(ingest→detect→propose→approve→re-verify)+ `com.hsueh.knowledge-loop.plist`;manifest 在 `~/Documents/Notes/Knowledge/.knowledge-loop/manifest.yaml`,含 proposals/ queue/ snapshots/;最近扫描 2026-07-02 08:30(`scan.log`)。已入 `.gitignore`(本地运维,不入库)。
- **更新器 = Sparkle 2.9.4**(`2b7d20a`):`SPUUpdater` + 自定义 `ArcherUpdateUserDriver`/`UpdateFlowController`(保 glass 样式);仅手动检查(`SUEnableAutomaticChecks=false`),feed URL 由 `build-app.sh` 注入 Info.plist。旧 `UpdateChecker.swift`(GitHub releases API)已删。
- **定价 = PricingProvider**(`9dc0bc9`):`Usage/PricingProvider.swift` 单一定价源(models.dev 动态 + 内置兜底),`UsageCollector`/`UsageView` 两处硬编码定价表已收敛。
- **本地发布产物**:`./scripts/build-app.sh` → `dist/Archer.app` v1.0.6(adhoc 签名),已覆盖 `/Applications/Archer.app`(quarantine 已清);`dist/Archer-v1.0.6.dmg`(10M)。

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

---

## 3. Open failures / 进行中(stage 1→2)

当前(HEAD `6a47419`,分支 `refactor/usage-parsers`,领先 main 8 commit):

- **分支未推送**:`refactor/usage-parsers` + `chore/usage-tokenscope-stage0` 合计 8 commit,待 merge/push。
- **UsageParser 协议化已完成** (commit `805406f`): protocol + 4 parser 文件 + collect() 循环化,501 test 全绿。
- **Gemini 调研完成** (commit `6a47419`): 确认 CLI 不落纯文本 token,降级为 BACKLOG。

**tokenscope 集成**:Stage 1 `PricingProvider` **已提交**(`9dc0bc9`,实现+测试)。Stage 2 `UsageParser` 协议化 **已完成**。余下:heatmap/donut 视图、MCP/Skill 成本归因(见 `docs/usage-tokenscope-plan.md`)。

_(此处只列当前未决项;修完即移到 §1 或 §4。)_

---

## 4. Lessons learned(stage 4 蒸馏)

- 新增 agent 时最大的坑不是加,是"加漏"——多处硬编码不同步。宁可先搜清所有引用点再动。
- 窗口/面板类改动"编译通过 ≠ 行为正确";AppKit 生命周期约束不显式,必须走 §2 checklist。
- **memory 会过期**:2026-06-29 的 memory 声称 ArrowRouter/2999/Chat 面板"已建/存在",到 2026-07-02 全已下线。→ 对任何"某路径/服务存在"的断言,动手前用 `ls`/`lsof` 现验,别信旧记录。这份 STATE.md 的存在意义就是收敛这种 drift。
- **一个工作树只容一个 agent 会话**:2026-07-03 两个会话("已中断"实未死的 `agy --continue` + 新会话)在同一工作树竞争提交——pre-commit hook 的 `git add -u` 会把对方在途改动静默卷进自己的 commit(产物 `c85f514`,后被拆分重写)。→ ①"会话中断"要用 `ps`/`lsof` 现验,别信直觉;②开工前确认没有别的 agent 持有该工作树;③拆分提交时,hook 会 `git add -u`,必须先把无关改动 stash 走。

---

## 5. Last session(stage 5 — resume,别 restart)

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
- `scripts/git-pre-commit.sh` 有 agent-session 检测(非本次改动,未被提交)

**Next**:① merge/push 本分支;② tokenscope 余下(heatmap/donut、成本归因);③ release 流程(DMG + Sparkle appcast 生成与签名);④ Gemini parser 等 protobuf schema 公开后解锁;⑤ 其余 8 agent(Aider/Cursor/Windsurf/Copilot/Cline/Augment/Qwen/Goose)调研。
