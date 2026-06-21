# archer

[![License](https://img.shields.io/github/license/archsueh/archer?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/archsueh/archer?style=flat-square)](https://github.com/archsueh/archer/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-007AFF?style=flat-square)](https://github.com/archsueh/archer/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/archsueh/archer/total?style=flat-square)](https://github.com/archsueh/archer/releases)
[![Stars](https://img.shields.io/github/stars/archsueh/archer?style=flat-square)](https://github.com/archsueh/archer/stargazers)

> *专为 AI coding 优化的极简 macOS 终端。*

🇨🇳 中文  ·  🇬🇧 [English](README.md)  ·  🇯🇵 [日本語](README_JA.md)

![archer](img/screenshot-1.png)

专为 AI coding 优化的极简 macOS 终端。支持侧边栏 workspace 管理、水平 / 垂直分屏、一键启动 agent、实时查看 agent 状态，也能在 pane 底部直接看到 Git、Node、Python 等工作区状态。开源，MIT 许可；不需要账号，不做遥测，应用状态都留在本机。GPU 渲染基于 [libghostty](https://github.com/ghostty-org/ghostty)。

**[下载最新版](https://github.com/archsueh/archer/releases/latest)**  ·  [更新日志](CHANGELOG.md)

---

## 功能

**垂直 tab、分屏、多窗口。** 侧边栏管理所有 workspace，三档宽度可切换（`⌘⌃S`）。每个 pane 都有独立 tab 栏和当前 tab，用 tab 栏右侧两个按钮或 ⌘D / ⌘⇧D 就能向右 / 向下分屏。⌘R 重命名 tab、⌘⇧R 重命名 workspace。`⌘⇧N` 打开新窗口。tab 可以拖动排序、跨 pane 移动，也能拖进另一个窗口 —— 实时会话整体带过去，scrollback 和正在跑的进程都在。重启后状态自动恢复，每个打开的窗口都会还原。把任意文件夹打开成新 workspace:从 Finder 拖到 sidebar,或者按 ⌘O。按 `⌘⇧E` 把当前 pane 放大占满 workspace 再按一次还原 —— 其他 pane 滑出视野但进程还在跑。

![左侧竖直 tab，一个 pane 分成四块](img/screenshot-2.png)

**一键启动各种 agent。** Claude Code · Codex · Gemini CLI · OpenCode · Amp · Cursor CLI · Copilot CLI · Grok Build · Antigravity CLI · Kimi Code · Pi · Kiro CLI。`+` 菜单里选一个,agent 会在第一个 prompt 出现前启动。Claude 对话还会跨 archer 重启自动 resume,关掉 tab 再打开能从离开的地方接上。

**Git worktree。** 右键任意 git workspace → "Create Worktree…",在新 branch 上(或 checkout 已有 branch)起一个 worktree。Worktree 在 sidebar 里缩进显示在源 repo 下面,有自己的 tab + agent —— 让 Claude 在 feature branch 上跑活,不打扰 main 上正在跑的进程。命令行 `git worktree add` 建的 worktree,下次启动 archer 也会自动出现在 sidebar。

**右键选中 → "Ask <agent>"。** 在 terminal 里选中一段 error / 日志 / 文件路径,右键挑任意 agent,新 tab 一打开,selection 已经作为第一条 prompt 发出去了,直接开始回答 —— 不用 ⌘C / ⌘V 来回切。

**快速打开(⌘P)。** 一个浮动面板模糊搜索所有 window 的 workspaces、tabs、agents、Terminal presets。输入关键字筛选,↑↓ 选,Enter 跳过去或者新开一个。⌘P 或顶部 chrome 上的 search pill 都能触发。

**输入顺手。** 在 zsh 提示行点哪儿光标就跳哪儿(不用按 modifier,跟 ghostty.app 一致)。从 Finder 把文件或文件夹拖到任意 pane,绝对路径会自动 escape 后插到光标位置。

**Prompt composer (⌘L)。** pane 底部升起一个聊天式输入框，让你安心写长的、多行的 prompt——不会手一抖回车就发出去。回车发给当前 agent（或 shell），Shift+回车换行，Esc 取消并保留草稿。⌘L 或 pane 底部状态栏的 compose 按钮打开。

**Agent 状态实时展示。** 侧边栏圆点显示每个 agent 的状态：运行中（蓝）、等待你处理（琥珀）、空闲（无色）。上一条命令非零退出时，tab 和 workspace 会同步显示红点；悬停可看到 `exit N · 12.4s`。Claude Code 和 Pi 会话还会在 pane 底部状态栏显示 agent 当前正在跑的工具（Bash / Edit / Read 等）和已运行的时间——点击 pill 看完整历史；失败的工具调用立刻变红。可在 Settings → Status Bar 里按 agent 单独开关这个 pill。

**通知。** 你没在看的某个 tab 里 agent 开始等你处理、或那里命令失败时，archer 会发一条 macOS 系统通知——每一类都能在 Settings → Notifications 里单独开关。顶栏还有个铃铛（⇧⌘I），把这些提醒跨窗口收进一个收件箱——谁在等你、什么失败了、什么跑完了——有没读的就亮红点。点一条直接跳到对应 tab；切到那个 tab，它的提醒会自己清掉。

![跨窗口收集的通知中心](img/screenshot-3.png)

**Agent 面板。** 顶栏有个开关（三种折叠状态，跟左边栏一样）能拉出右侧边栏，把所有窗口里的 agent 一次性列出来，按谁最需要你排序：等你处理、失败、运行中、空闲。点任意一行直接跳到对应 tab；折叠模式会收成一条带状态色圆点的窄图标栏。

**工作区状态和环境一眼可见。** pane 底部状态栏显示 Git 分支 + diff（`N files +X −Y`）、Python venv、Node 版本、当前生效的代理（`https_proxy` / `http_proxy` / `all_proxy`），以及 SSH 到远程机器时登录的 `user@host`（在 Settings → SSH 里开启）。Agent 用 Bash 切分支也好,你在别的终端改了 git 状态也好,这里都会自动刷新。Node 版本和 Git 分支点一下就能切,代理点开能看完整 `name=value` 并复制。

**SwiftUI 原生开发，简约风格。** Onest + JetBrains Mono 字体。自定义 About 面板、带快捷键提示的原生菜单,中日韩 IME 输入完整支持。

**可配置。** Settings 面板（`⌘,`）可以调主题、字体、光标、默认新 tab 行为、Terminal 预设、agents 和 pane 底部状态栏。切换主题时整个窗口会一起立即换色，也支持 themes 目录里的自定义 Ghostty 主题。

**默认本地。** 不需要账号，不做遥测，没有云同步。archer 的状态都留在本机。

**基于 libghostty。** 使用和 ghostty 同源的 GPU 终端渲染引擎。

## 安装

从 [Releases](https://github.com/archsueh/archer/releases) 下载最新的 `.dmg`，打开后把 `Archer.app` 拖进 `Applications` 文件夹。

**第一次启动会被 Gatekeeper 拦下来**，因为当前构建是 adhoc 签名（还没有 Apple Developer ID；公开分发签名和公证会等有真实用户后再做）。你会看到 *"Archer cannot be opened because Apple cannot check it for malicious software"* 或者 *"is damaged and cannot be opened"* 这两类报错。下面三种方法任选一个即可：

<details>
<summary><b>方法 A —— 走系统设置 <i>(推荐)</i></b></summary>

1. 先双击一次 `Archer.app`，macOS 会弹警告，把警告窗口关掉。
2. 打开 **系统设置 → 隐私与安全性**，往下翻到 **安全性** 这一段。
3. 看到 *"Archer was blocked to protect your Mac"* 后，点旁边的 **Open Anyway**，输入密码。
4. 再双击一次 `Archer.app`，这次会有 **Open** 按钮，点它即可。
</details>

<details>
<summary><b>方法 B —— 终端一行命令</b></summary>

```sh
xattr -d com.apple.quarantine /Applications/Archer.app
```
</details>

<details>
<summary><b>方法 C —— 连 "Open Anyway" 按钮都没有</b></summary>

新版 Sequoia 有时会对 adhoc 签名的 app 完全不显示 "Open Anyway" 按钮。这种情况下可以先把旧版的 "Anywhere" 选项打开，再回去走方法 A：

```sh
sudo spctl --global-disable      # macOS 15+；老系统用 --master-disable
# 系统设置 → 隐私与安全性 → "Allow applications from" 选 Anywhere
# 双击 Archer.app，这次应该可以启动
sudo spctl --global-enable       # Archer 跑过一次之后，立刻把 Gatekeeper 打开
```

注意：这是**系统级开关**。关着的时候，macOS 会允许任何未签名 app 启动。Archer 跑过一次就把它重新打开；系统会单独记住已经信任过 Archer，以后不会再拦。
</details>

macOS **只拦第一次启动**。之后从 Spotlight、Dock、Finder 启动都跟普通 app 一样。

## 从源码构建

需要 Xcode 26+ 和 macOS 14+（Sonoma，`@Observable` 的最低系统要求）。

```sh
./scripts/setup-libghostty.sh        # 一次性：把预编译的 libghostty xcframework 下到 Vendor/
swift build
swift run                            # 开发模式直接跑
swift test                           # 383 个单测

./scripts/build-app.sh               # 产出 dist/Archer.app
./scripts/build-dmg.sh --build       # 产出 dist/Archer-vX.Y.Z.dmg
```

`Vendor/` 和 `dist/` 都在 `.gitignore` 里。libghostty 的 setup 脚本可以反复跑；SHA 没变时会直接跳过。

## Star 趋势

[![Star History Chart](https://api.star-history.com/svg?repos=archsueh/archer&type=Date)](https://star-history.com/#archsueh/archer&Date)

## 许可证

MIT —— 见 [LICENSE](LICENSE)。打包进来的第三方资源保留各自的许可证，详见 [NOTICE.md](NOTICE.md)。
