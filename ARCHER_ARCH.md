# ARCHER — 架构文档

## 目标

在 archer 终端骨架 + 文件树基础上，补齐"下载 → 分类 → 改动可视化"闭环，形成专为 vibe coding / AI agent 设计的轻量驾驶舱。

## 仓库

- GitHub: `archsueh/archer`
- Base: `archsueh/archer` v0.26.x
- 技术栈: Swift 6 / SwiftUI / libghostty / Metal

## 模块

| 模块 | 现状 | 问题 |
|---|---|---|
| 终端 + 分屏 | ✅ 完整 | 无 |
| 侧边栏 + workspace | ✅ 完整 | 无 |
| 文件树 | ✅ 基础 | 只有树，没有内容感知 |
| Agent 状态面板 | ✅ 完整 | 无 |
| Claude usage strip | ✅ 已有 | 无 |
| Diff / 改动可视化 | ❌ 缺失 | **P1** |
| Fanbox 下载器 | ❌ 缺失 | **P2** |
| 自动分类 | ❌ 缺失 | **P3** |
