import Foundation

// [archer] ExecutionRouter — distilled from github.com/AgwaB/pi-workflow's
// `execution-router` skill. Pi's router decides whether a task deserves
// multi-agent/workflow complexity or should stay single-agent. Archer already
// classifies agents by `AgentRole` (architect/implementer/general); this
// module adds the *task-side* decision: given a task's shape, recommend a
// execution mode and (optionally) which role lane fits.
//
// Design: pure logic, no UI, no runtime side effects. The UI layer (command
// palette / sheet) calls `ExecutionRouter.recommend(_:)` and shows the memo.
// Archer NEVER coerces routing — the user decides; this is an advisory.

enum ExecutionMode: String, CustomStringConvertible {
    case single // one agent, one pass
    case singlePlus // single agent + a targeted verifier/subagent
    case parallel // fan-out across agents (e.g. multi-file review)
    case workflow // orchestrated multi-stage (future: DAG board)

    var description: String {
        switch self {
        case .single: return "单 Agent 直跑"
        case .singlePlus: return "单 Agent + 验证器"
        case .parallel: return "并行多 Agent"
        case .workflow: return "工作流编排"
        }
    }
}

struct RoutingMemo {
    let mode: ExecutionMode
    let preferredRole: AgentRole
    let confidence: String // high / medium / low
    let scoreBreakdown: String // human-readable scores
    let why: String
    let controls: String // validation plan / guardrails

    var summary: String {
        "建议：\(mode.description) · 角色：\(preferredRole) · 置信：\(confidence)\n\(why)\n评分：\n\(scoreBreakdown)\n护栏：\(controls)"
    }
}

enum ExecutionRouter {
    /// Cheap, objective anchors Pi's router uses to calibrate scores.
    /// We approximate with a few signals derivable from the task text + a
    /// small context bundle the caller may pass.
    struct TaskContext {
        let text: String
        /// Caller-provided hints (e.g. from a workspace scan). Nil = infer
        /// from text only.
        var changedFileCount: Int?
        var domainCount: Int?
        var hasTests: Bool?
        var readOnly: Bool? // pure research/review vs mutating
        var explicitMode: String? // user already chose; we just validate

        init(_ text: String) {
            self.text = text
        }
    }

    // MARK: - Public API

    /// Recommend an execution mode + role for a task. Pure; returns a memo.
    static func recommend(_ ctx: TaskContext) -> RoutingMemo {
        let t = ctx.text.lowercased()

        // --- infer cheap signals from text when not provided ---
        let files = ctx.changedFileCount
            ?? (t.contains("diff") || t.contains("改动") || t.contains("变更") ? 6 : 1)
        let domains = ctx.domainCount
            ?? (t.contains("多模块") || t.contains("跨模块") || t.contains("全仓") ? 3 : 1)
        let readOnly = ctx.readOnly
            ?? (t.contains("审查") || t.contains("review") || t.contains("研究")
                || t.contains("总结") || t.contains("调研") || t.contains("检索"))

        // --- score ledger (Pi's shape: single/10, workflow-fit/6,
        //     multi-benefit/18, multi-penalty/18) ---
        let singleSuff = scoreSingleSufficiency(files: files, domains: domains, readOnly: readOnly, t: t)
        let wfFit = scoreWorkflowFit(t)
        let benefit = scoreMultiBenefit(files: files, domains: domains, readOnly: readOnly, t: t)
        let penalty = scoreMultiPenalty(files: files, domains: domains, t: t)

        // --- decision ---
        let mode: ExecutionMode
        let role: AgentRole
        let confidence: String

        if let forced = ctx.explicitMode {
            // user already chose; we still surface a sanity memo
            mode = ExecutionMode(rawValue: forced) ?? .single
            role = preferredRole(for: t, readOnly: readOnly)
            confidence = "high (用户指定)"
        } else if benefit - penalty <= 0 && singleSuff >= 7 {
            mode = .single
            role = .general
            confidence = singleSuff >= 8 ? "high" : "medium"
        } else if benefit - penalty > 0 && files <= 10 {
            mode = .singlePlus
            role = readOnly ? .architect : .implementer
            confidence = "medium"
        } else if benefit - penalty > 6 {
            mode = readOnly ? .parallel : .workflow
            role = .architect
            confidence = "medium"
        } else {
            mode = .single
            role = .general
            confidence = "low"
        }

        let why = explain(mode: mode, files: files, domains: domains, readOnly: readOnly, t: t)
        let controls = controlPlan(mode: mode, readOnly: readOnly)

        let breakdown = """
        • single sufficiency /10 : \(singleSuff)
        • workflow fit /6       : \(wfFit)
        • multi-agent benefit /18: \(benefit)
        • multi-agent penalty /18: \(penalty)
        • net (benefit-penalty)  : \(benefit - penalty)
        """

        return RoutingMemo(
            mode: mode,
            preferredRole: role,
            confidence: confidence,
            scoreBreakdown: breakdown,
            why: why,
            controls: controls
        )
    }

    // MARK: - Scoring

    private static func scoreSingleSufficiency(files: Int, domains: Int, readOnly _: Bool, t _: String) -> Int {
        // 0-3 files / 1 domain => 9-10 (single is enough)
        if files <= 3 && domains <= 1 { return 10 }
        if files <= 10 && domains <= 3 { return 8 }
        if files <= 10 { return 7 }
        if files <= 20 { return 5 }
        return 3
    }

    private static func scoreWorkflowFit(_ t: String) -> Int {
        // does a known workflow shape apply?
        if t.contains("发布") || t.contains("release") || t.contains("准入")
            || t.contains("评价") || t.contains("汇总")
        {
            return 6 // repetitive, document-driven -> workflow fits
        }
        if t.contains("审查") || t.contains("review") || t.contains("研究") || t.contains("总结") {
            return 5
        }
        return 2
    }

    private static func scoreMultiBenefit(files: Int, domains: Int, readOnly: Bool, t: String) -> Int {
        // benefit rises with breadth/recall need
        var b = 0
        if files >= 11 { b += 8 }
        else if files >= 4 { b += 4 }
        if domains >= 4 { b += 6 }
        else if domains >= 2 { b += 3 }
        if readOnly { b += 4 } // reviews/research benefit from parallel readers
        if t.contains("多视角") || t.contains("对照") || t.contains("跨") { b += 4 }
        return min(b, 18)
    }

    private static func scoreMultiPenalty(files: Int, domains: Int, t: String) -> Int {
        // penalty: coupling, unclear ownership, single-domain coherence need
        var p = 0
        if files >= 11 && domains <= 1 { p += 8 } // one domain, many files => just use single
        if t.contains("原子") || t.contains("一致性") || t.contains("联动") { p += 6 }
        if domains <= 1 && files <= 10 { p += 4 }
        // small task: overhead not worth it
        if files <= 3 { p += 6 }
        return min(p, 18)
    }

    // MARK: - Helpers

    private static func preferredRole(for t: String, readOnly: Bool) -> AgentRole {
        if readOnly { return .architect }
        if t.contains("实现") || t.contains("写") || t.contains("修") || t.contains("改") {
            return .implementer
        }
        return .general
    }

    private static func explain(mode: ExecutionMode, files: Int, domains: Int, readOnly: Bool, t _: String) -> String {
        switch mode {
        case .single:
            return "任务规模小（≈\(files) 文件 / \(domains) 域），单 Agent 直跑即可，工作流协调成本不划算。"
        case .singlePlus:
            return "中等规模且\(readOnly ? "只读" : "有改动")，先用单 Agent 推进，收尾加一个验证/复核环节更稳。"
        case .parallel:
            return "跨多域/多视角且只读，并行多个 Agent 分别读不同部分再汇总，召回更全。"
        case .workflow:
            return "改动面大、需分阶段校验，走编排（规划→分派→汇总→验证）比裸并行更可控。"
        }
    }

    private static func controlPlan(mode: ExecutionMode, readOnly: Bool) -> String {
        switch mode {
        case .single:
            return "直接发起；完成后自检编译/测试。"
        case .singlePlus:
            return readOnly
                ? "单 Agent 出报告；另起一个验证 Agent 核对事实与引用。"
                : "单 Agent 改完；跑测试/编译确认无回归再收尾。"
        case .parallel:
            return "各 Agent 只读各自分片；汇总阶段去重 + 一致性对齐，禁止并行写同一文件。"
        case .workflow:
            return "阶段间设校验门槛（编译/测试绿灯才进下一阶段）；写操作走受管工作区，不直接动 live 目录。"
        }
    }
}
