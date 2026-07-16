# Spec · 边缘活动辉光（Edge Activity Glow）

> 状态：P1/P2 **已实现**（`EdgeGlow/` + Settings + 单测）；P3 marquee 仍待
> 上游 backlog：`docs/BACKLOG.md`

## 1. 目标（一句话）
Agent 活动时在屏幕/窗口边缘给一圈**克制单色**辉光，作为 archer 提示音之外的**余光视觉确认**，复用现有 hook 信号与 activity 三态色，零新管线、零依赖、符合 brutalist-minimal。

## 2. 背景与约束
- archer 已接 Claude `Stop` / `Notification` / `turn` 等 HookEvent（提示音用）。本特性**复用这些既有信号**，不新建 HTTP server（EdgeGlow 的 /start /pulse /stop 不照搬）。
- 已有 activity token：running `#69B0D6`、attention `#E8B068`、failure `#E86666`。辉光颜色一律取自这三个，**不引入新色、绝不彩虹**。
- 设计语言 brutalist-minimal：低对比、零阴影、克制。辉光必须**窄、低亮度、可关、默认收敛**。

## 3. 用户故事（按优先级，可独立交付与测试）

### P1 — 离散脉冲辉光（MVP，先发）
作为离开 archer 窗口去做别的事的开发者，当一轮 agent 跑完或需要我处理时，我希望屏幕边缘**闪一下对应颜色**，让我用余光就知道状态，无需切回窗口。
- 独立测试：触发一次 `turn`/`Notification`，观察边缘是否按映射闪一次/亮起。
- 仅依赖既有离散事件，零新状态源。

### P2 — 持续显示与确认
作为需要明确"待我处理"的开发者，attention（要权限/要输入）时辉光**保持常亮**直到我聚焦窗口或处理完，failure 时**红色保持**直到我查看。
- 独立测试：触发 attention 后辉光持续；点回窗口后熄灭。

### P3 — 运行中跑马灯（后置，需新信号源）
作为盯长任务的开发者，agent **正在跑**时边缘有缓慢 marquee 流动，跑完即停。
- 前置依赖：archer 需有"agent 正在运行"的**持续状态源**（当前 hook 只有离散事件，没有 running 持续态）。此故事在该状态源就绪前不做。

## 4. 验收场景（Given-When-Then）
- Given 辉光开启且 archer 在后台，When 收到 `turn`（一轮完成），Then 屏幕边缘以 running 色脉冲一次（淡入淡出 ≤ 0.6s）后熄灭。
- Given 辉光开启，When 收到 `Notification`（attention），Then 边缘以 attention 色亮起并保持，直到窗口获得焦点或事件被确认，然后淡出。
- Given 某轮以失败结束，When 收到 failure 信号，Then 边缘以 failure 色保持，直到用户聚焦窗口。
- Given 辉光在设置中关闭，When 任意事件触发，Then 不出现任何辉光（提示音行为不受影响）。
- Given 多显示器，When 触发辉光，Then 仅在 archer 当前所在屏（或全部屏，依设置）显示。

## 5. 状态 → 颜色/动画映射
| 信号 | 颜色 token | 动画 | 持续 |
|---|---|---|---|
| turn（完成） | running #69B0D6 | 脉冲一次 | ≤0.6s 自动熄 |
| Notification（attention） | attention #E8B068 | 淡入保持 | 至聚焦/确认 |
| failure（失败） | failure #E86666 | 淡入保持 | 至聚焦 |
| 运行中（P3） | running #69B0D6 | marquee 慢流 | 至 turn/stop |

## 6. 技术方案（最小）
- 一个透明、点击穿透、`ignoresMouseEvents` 的 overlay `NSWindow`（level 高于普通窗），覆盖目标屏边缘，不挡操作。
- 边框用 `CAShapeLayer`（窄描边 + 轻 blur），颜色取 Theme.activity*；P3 的 marquee 用 `CVDisplayLink` 驱动 `lineDashPhase`，60fps，单属性更新。
- 接入点：现有 HookEvent 分发处（提示音同一入口），新增对 overlay 的调用；**不改 hook 协议本身**。
- 角半径 0（brutalist），无阴影；亮度/宽度走低默认值。

## 7. 设置（最小项）
- 开关（默认关或低调默认，见开放问题）
- 范围：当前屏 / 全部屏
- 宽度、亮度（克制区间，给窄范围）
- 复用通知设置的 enable/completed/attention 开关，不另起一套逻辑

## 8. 非目标（Non-goals）
- 不做彩虹/Apple Intelligence 等花哨主题。
- 不做独立 HTTP server / 菜单栏独立 app（archer 内建即可）。
- 不做 P3 运行态动画，直到持续状态源就绪。

## 9. 决策（已拍板 2026-06-22）
1. **屏边 + 默认低亮度开**：屏幕边缘为默认形态，开箱即开，低亮度收敛（呼应提示音"仪式感默认开"的取向）。窗边作为后续可选。
2. **范围默认：全部屏**（屏边余光价值最大化；低亮度保证不喧宾夺主，可在设置收窄到当前屏）。
3. **P3 running 态接 Claude Code start/stop hook 对**：通过 start hook 进入"运行中"、stop hook 退出，拿到持续运行态 → P3 marquee 可落地，不再阻塞，但仍排在 P1/P2 之后（需先接通 start hook，当前只接了 stop/notification）。

## 10. Done-when（MVP=P1+P2）
- P1、P2 全部验收场景可手动验证通过；
- 关闭开关后零辉光且不影响提示音；
- 多屏不崩、overlay 不挡鼠标；
- 颜色仅来自三态 token，无新色、无彩虹；
- 通过 `swift build` 与既有测试，新增最小单测覆盖事件→颜色映射。
