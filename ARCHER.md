# Archer

> 驾驶多个 coding agent 的原生 macOS 终端 hub —— 一间"控制室"。基于 [archer](https://github.com/archsueh/archer)（libghostty 终端内核）+ 活文件面板 + usage 常驻监控 + 玻璃通透皮肤。

品牌名 **Archer**（船的舵手室＝控制室）。仓 `archsueh/archer`。

---

## 命名与模块边界（重要）

- **品牌/app/仓名 = Archer**。
- **SwiftPM 内部模块继续叫 `Archer` 不改**。改内部 product 名会让对上游的 diff 爆炸，直接砸掉下面的 re-pull 维护策略。Archer 是外壳，Archer 是引擎。

## Fork 与维护策略

- 本仓是**独立仓**（`isFork=false`），不是 GitHub fork，无 fork 链接要解。
- 上游 `archsueh/archer` 更新频繁。维护模型：**重新拉上游 → 跟本地 diff → 重放补强 → upload**。
- 为让每次 diff 干净可重放：
  - 自定义功能**尽量进新文件**（不碰上游文件就不会冲突）。
  - 必须改上游文件时，**改动最小化 + 注释标记** `// [archer]`，方便重放时 grep 定位。
  - 本文件是**改动清单（delta manifest）**：每加一个功能，登记它动了哪些上游文件。

### Delta 清单（对上游 archer 的改动）

| 功能 | 新文件 | 改的上游文件（标记 `// [archer]`）|
|---|---|---|
| P1 文件面板 | `Sidebar/FileTreeModel.swift`、`Sidebar/DirectoryWatcher.swift`、（扩 `Sidebar/SidebarFileTree.swift`）| `Sidebar/SidebarView.swift`（接线）|
| P2 玻璃 | （主题逻辑文件）| `App/ArcherWindowController.swift` 或 `App/Theme.swift`（设窗口材质）|
| P3 usage strip | `Sidebar/UsageStrip.swift`（lift TokenChecker 逻辑）| 顶层布局接线点 |

---

## 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0** | 构建闸门：`scripts/setup-libghostty.sh` 拉 GhosttyKit.xcframework + `swift build` 绿色基线 | 进行中 |
| **P1** | 活文件面板：**拖拽移动 + 与 macOS 文件系统对齐** | 待 P0 |
| **P2** | 玻璃皮肤（低优先，纯主题）：把 `archer-vibrancy-injector` 的 HUD 材质逻辑落进源码，退役注入器 | 待 |
| **P3** | usage 顶栏 strip：lift `token-checker-multi`(TokenChecker) 读 `~/.claude/usage.db` 的逻辑；顶栏不好塞退路为独立 hub window。参考 `Supersynergy/agimon` | 待 |

玻璃只是皮肤，不是核心；核心是 agent 终端 + 文件面板 + usage。

---

## P1 规格（当前阶段）

### 现状
`Sidebar/SidebarFileTree.swift` 已是未跟踪 WIP：只读递归树、懒加载、点击粘路径到活动 pane。两个缺陷挡住"对齐"：① per-row `@State children` 加载一次永不失效 → 外部改了就 stale；② 没拖拽移动；③ 没接进 `SidebarView`。

### 用户故事
- **US-1（写对齐）**：在文件树里把文件/文件夹拖到另一个文件夹行上 → `FileManager.moveItem` 在磁盘上真移动进该目录 → 树立即反映新位置。
- **US-2（读对齐）**：磁盘被外部改动（Finder 移动/增删）→ 树反映真实当前状态，不走 stale 快照。

### 验收（Given-When-Then）
- Given 树展开了 `A/` 和 `B/`，When 把 `A/x.txt` 拖到 `B/` 行，Then `x.txt` 物理位于 `B/`、`A/` 不再有它、两个目录行都刷新。
- Given `B/` 已有同名 `x.txt`，When 拖入，Then 落点改名为 `x 2.txt`（不静默覆盖）。
- Given 树展开 `A/`，When 在 Finder 里往 `A/` 丢一个文件，Then 树在该目录出现该文件（无需手动刷新）。

### 本期不做（明确排除）
重命名、删除、从外部拖入落盘（不做 ingest）、从树拖出到 Finder。

### 实现计划
1. **`FileTreeModel`（新）**：`ObservableObject`，按 URL 持有树展开/children 状态。取代 per-row `@State`——协调式移动（从 A 删、往 B 加）和外部刷新都需要集中状态。
2. **拖拽**：行加 `.onDrag`（给 fileURL 的 `NSItemProvider`）；文件夹行加 `.onDrop(of: [.fileURL])` → `FileManager.moveItem` + 同名冲突改名 + 刷新 src/dest。
3. **`DirectoryWatcher`（新）**：复刻 `Sessions/GitWatcher.swift` 的 `DispatchSourceFileSystemObject`(kqueue)，监听已展开目录，外部变更触发刷新 = 对齐。
4. **接线**：`SidebarFileTreeList` 接进 `SidebarView`（最小改动 + `// [archer]` 标记）。

### 测试（TDD，archer 有现成测试套件）
- `FileTreeModelTests`：移动进目录、同名冲突改名、移动后 src/dest children 正确。
- watcher：外部新建文件后模型收到刷新。

---

## 构建

```bash
bash scripts/setup-libghostty.sh   # 拉 GhosttyKit.xcframework（未提交，首次必跑）
swift build
swift test
```
