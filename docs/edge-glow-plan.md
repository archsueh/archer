# Plan · 边缘活动辉光（Edge Activity Glow）

> 阶段：Plan（实现计划）· 对应规格 `docs/edge-glow-spec.md`
> 决策已锁：屏边 + 默认低亮度开 + 范围默认全部屏 + P3 接 start/stop hook

## A. 架构决策（与理由）
1. **独立 overlay 窗，不画进主窗**。每块 `NSScreen` 一个透明、`ignoresMouseEvents` 的 `NSWindow`（`.screenSaver`/高 window level，`collectionBehavior` 含 `.canJoinAllSpaces`/`.stationary`），只画边框。理由：辉光要在 archer 失焦/后台时仍可见，画进主窗做不到；overlay 与业务 UI 解耦，零侵入。
2. **复用既有 HookEvent 分发入口**（提示音同一处，`AppDelegate` 的 completed/attention 分支）。理由：不改 hook 协议，事件→辉光与事件→提示音并列，状态一致。
3. **颜色只取 Theme.activity***。理由：守 brutalist-minimal，禁新色/彩虹（spec 非目标）。
4. **CAShapeLayer 描边；P3 marquee 用 CVDisplayLink 驱动 lineDashPhase**。理由：单属性 60fps、~0% CPU（EdgeGlow 已验证），零依赖。
5. **分两个 PR**：PR1 = P1+P2（MVP，仅用现有离散事件）；PR2 = P3（接通 start hook 拿持续运行态 + marquee）。理由：MVP 不依赖新信号源，可独立交付与验收。

## B. 状态机
```
idle
 ├─ (.turn 完成)        → donePulse(running 色, 淡入淡出≤0.6s) → idle
 ├─ (.attention)        → holdAttention(attention 色, 常亮)   → (主窗聚焦/确认) → idle
 ├─ (failure)           → holdFailure(failure 色, 常亮)       → (主窗聚焦) → idle
 └─ (start hook, PR2)   → running(running 色, marquee 慢流)   → (stop/.turn) → idle
```
- 优先级：failure > attention > running > donePulse（高优先态覆盖低优先态的可视表现）。
- 清除条件：`NSWindow.didBecomeKeyNotification` / `NSApplication.didBecomeActiveNotification` 熄灭 hold 态。

## C. 文件变更清单
新增 `Sources/ArcherKit/EdgeGlow/`：
- `EdgeGlowState.swift` — enum 状态 + `color(for:) -> NSColor`（取 Theme.activity*）+ 动画参数；纯逻辑，可单测。
- `EdgeGlowOverlayWindow.swift` — 透明点击穿透 NSWindow 子类 + CAShapeLayer 边框图层；`render(state:brightness:width:)`。
- `EdgeGlowController.swift` — 持有 per-screen overlay（监听 `NSApplication.didChangeScreenParametersNotification` 处理热插拔）；对外 `handle(event:)`、`setRunning(_:)`（PR2）、`clearHolds()`；读 Settings。

编辑：
- `Sources/ArcherKit/App/AppDelegate.swift` — 在现有 HookEvent completed/attention 分支旁，调用 `edgeGlow.handle(event:)`；订阅 didBecomeKey/didBecomeActive 调 `clearHolds()`。（PR2 再加 start/stop 分支 → `setRunning`）
- 设置存储（Theme/Settings 所在文件，落地前确认确切路径）— 新增 `edgeGlowEnabled=true`、`edgeGlowScope=.all`、`edgeGlowBrightness`(低默认)、`edgeGlowWidth`(窄默认)。
- 设置 UI — 最小项：开关 + 范围(当前屏/全部屏) + 亮度/宽度，复用通知设置区块。
- `DESIGN.md` — Components 增 `edge-glow` 条目：说明取 activity 三态色、0 角、窄描边、低亮度（保持文档=真相源一致）。

新增测试：
- `Tests/.../EdgeGlowStateTests.swift` — 事件→颜色映射（turn→running、attention→attention、failure→failure）；优先级覆盖；关闭开关 `handle` 为 no-op。

## D. 测试策略
- **单元**：EdgeGlowState 的事件→色/优先级/开关 no-op（纯函数，必测）。
- **手动验收**（对 spec §4）：后台触发 turn 看脉冲一次自动熄；attention 常亮、聚焦后熄；failure 常亮至聚焦；关开关零辉光且提示音不受影响；多屏全亮、热插拔不崩；overlay 不挡鼠标（点击穿透）。
- `swift build` + `swift test` 全绿。

## E. 依赖与风险
- **全屏 app/Spaces 覆盖**：overlay 在他人全屏下可能被遮或行为异常 → collectionBehavior 调参，必要时降级为"仅当前屏"。
- **CVDisplayLink 生命周期**（PR2）：启停与屏幕热插拔要干净释放，防泄漏/野指针。
- **点击穿透正确性**：`ignoresMouseEvents=true` + 高 level，验证不抢焦点、不挡操作。
- **性能**：PR1 无持续动画几乎零开销；PR2 marquee 控制在单 lineDashPhase 更新。
- **start hook 接通**（PR2 前置）：需在 Claude Code hook 配置里加 start 事件并在 archer 侧解析；未接通则 P3 不动。

## F. Traceability（计划 → 规格）
| 规格条目 | 计划落点 |
|---|---|
| P1 离散脉冲 | 状态机 donePulse + AppDelegate .turn 分支（PR1） |
| P2 保持确认 | holdAttention/holdFailure + didBecomeKey 清除（PR1） |
| P3 运行跑马灯 | running 态 + start/stop hook + CVDisplayLink（PR2） |
| 仅三态色/不彩虹 | EdgeGlowState.color 取 Theme.activity*；单测约束 |
| 可关/默认低亮开 | Settings edgeGlowEnabled=true + brightness 低默认 |
| 多屏 | EdgeGlowController per-screen + 热插拔订阅 |

## G. 实施顺序
1. PR1：EdgeGlowState（+单测）→ OverlayWindow → Controller → 接 AppDelegate(turn/attention/failure) + 清除订阅 → Settings 最小项 + UI → DESIGN.md → 手动验收 P1/P2。
2. PR2：接通 Claude Code start hook → AppDelegate setRunning → CVDisplayLink marquee → 验收 P3。
