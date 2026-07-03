# STATE · Archer

> 项目工作记忆。五段对应 5 阶段记忆(Fail→Investigate→Verify→Distill→Consult)。
> **两条纪律**:①**走前必写**——每次会话结束更新本文件(试了什么/过了什么/败了什么/新规则);不写则下次从零。②**开局必读**——新会话先读本文件 + CLAUDE.md,再动手;别凭记忆重推已验证过的事实。
> 与 `~/.claude` 全局 memory 的分工:本文件是**项目级、随仓库走**;全局 memory 是**跨项目习惯/偏好**。事实以本文件为准,过期即改。
>
> Verified date: 2026-07-03 · HEAD `b97c0a6`

---

## 1. Verified facts(stage 3 — 停止猜测)

已实地核实(`2026-07-02`),别再猜:

- **构建**:`swift build` / `swift test` / `swift run`;清缓存 `rm -rf .build`(SwiftPM,非 Xcode 工程为主)。
- **主模块**:`Sources/ArcherKit/` 下 App / Bridge / Cockpit / Dashboard / Diff / EdgeGlow / Resize / Sessions / Settings / Sidebar / Terminal / Usage / Utilities 等。
- **Bridge(P0/P1 已落地并在跑)**:`Sources/ArcherKit/Bridge/` = PaneRegistry.swift + BridgeServer.swift + BridgeEventLog.swift + LogPanelView.swift。运行时 socket:`~/.archer/bridge.sock`(存在=服务活着)。
- **Skills / CC Switch**:`~/.cc-switch/cc-switch.db`(SQLite,`skills` 表)。搜索源 `https://skills.sh/api/search`。Archer Skills 面板「发现技能」支持**原生安装**（直接写 ~/.claude/skills + ~/.agents/skills 等），解析 GitHub 结构下载 SKILL.md（含子文件）。更新/高级管理仍可委托 CC Switch.app。扫描本地所有 agent skills 目录 + 健康检查 + 跨端去重 + symlink 继电器。
- **Glass 全局基线(不可被 per-theme 覆盖)**:`Theme.glassOpacity` / `chromeBackgroundBlur` / `chromeBackgroundSaturate`(见 `Theme.swift`)。`aver-light` 象牙白 `#FDF9F4` 是外观基准。
- **知识循环(你自建,在跑)**:`scripts/knowledge-loop/kl.py`(ingest→detect→propose→approve→re-verify)+ `com.hsueh.knowledge-loop.plist`;manifest 在 `~/Documents/Notes/Knowledge/.knowledge-loop/manifest.yaml`,含 proposals/ queue/ snapshots/;最近扫描 2026-07-02 08:30(`scan.log`)。

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

当前工作树未提交(HEAD `b97c0a6` 之后):

- **`Sidebar/SkillsView.swift`(未提交,+41/-2)**:给技能安装失败加 UI 错误横幅(替掉静默 `print`)+ GitHub API 友好错误(403 限流 / 404 路径)。自洽完整,可作独立 commit `fix(skills): surface install errors`。**待用户确认是否提交**(非本人所写)。
- **`.grok/`、`.xcodebuildmcp/`、`.playwright-mcp/`**:工具产物目录,建议入 `.gitignore`(待确认)。
- **未提交的项目记忆/文档**:`STATE.md` 本身、`docs/usage-tokenscope-plan.md`(tokenscope 集成方案,见该文件)——应提交使其随仓库走。
- **遗留清理**:`~/.archer/mlx-server.log` 是已下线本地模型的残留,可删。

**tokenscope 集成(未开工)**:方案见 `docs/usage-tokenscope-plan.md`。Stage 0(清 Dashboard)已完成;下一步 Stage 1 = `PricingProvider`(models.dev 动态定价 + 收敛 `UsageCollector.swift:1277` 与 `UsageView.swift:1146` 两处 drift 定价)。

_(此处只列当前未决项;修完即移到 §1 或 §4。)_

---

## 4. Lessons learned(stage 4 蒸馏)

- 新增 agent 时最大的坑不是加,是"加漏"——多处硬编码不同步。宁可先搜清所有引用点再动。
- 窗口/面板类改动"编译通过 ≠ 行为正确";AppKit 生命周期约束不显式,必须走 §2 checklist。
- **memory 会过期**:2026-06-29 的 memory 声称 ArrowRouter/2999/Chat 面板"已建/存在",到 2026-07-02 全已下线。→ 对任何"某路径/服务存在"的断言,动手前用 `ls`/`lsof` 现验,别信旧记录。这份 STATE.md 的存在意义就是收敛这种 drift。

---

## 5. Last session(stage 5 — resume,别 restart)

**2026-07-03** · HEAD `b97c0a6 feat(skills): implement native in-app skill installation and update from skills.sh`。

自 2026-07-02 起:Sessions Dashboard **已提交**(并入 `b97c0a6`,含 `SessionDashboardTests`)、skills 原生安装已提交。

**本次会话(Stage 0 收尾)已验证**:① `swift test` = **483 tests / 0 failures**(基线绿);② `SessionsWindowController` 按 §2 NSWindow 三条复核**通过**(`isReleasedWhenClosed=false`、关窗 cancel refresh Task、主窗口 `AppDelegate.handleWindowWillClose:245` 用通用 `NSApp.windows` 扫覆盖它——无僵尸态);③ 发现 STATE.md §3/§5 曾严重落后于 repo(Dashboard 早已提交),已按"repo wins"修正——再次印证 §4 的 drift 教训。

**Next**:① 处理 §3 未决项(`SkillsView.swift` 是否提交、gitignore、提交 STATE.md/plan);② 开工 **tokenscope Stage 1 `PricingProvider`**(见 `docs/usage-tokenscope-plan.md`)。
