#!/usr/bin/env swift
// archer-bridge — CLI client for the Archer BridgeServer.
//
// Usage:
//   archer-bridge list
//   archer-bridge read <label> [lines]
//   archer-bridge type <label> <text>
//   archer-bridge keys <label> <key> [key…]
//   archer-bridge sync
//   archer-bridge agents
//   archer-bridge handoff <agent> [--prompt <text>|--stdin] [--strict]
//   archer-bridge open <agent> [--strict]
//
// Wire: connects to ~/.archer/bridge.sock, sends one JSON line, prints response.

import Darwin
import Foundation

let socketPath = (NSHomeDirectory() as NSString)
    .appendingPathComponent(".archer/bridge.sock")

/// Accept `codex` or `@codex` — bridge addresses are @labels in the product.
func stripAt(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("@") { s = String(s.dropFirst()) }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

func send(_ payload: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
        fputs("archer-bridge: JSON encode failed\n", stderr); exit(1)
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { fputs("archer-bridge: socket() failed\n", stderr); exit(1) }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
        fputs("archer-bridge: socket path too long\n", stderr); exit(1)
    }
    withUnsafeMutableBytes(of: &addr.sun_path) { dst in
        pathBytes.withUnsafeBufferPointer { src in
            dst.baseAddress?.copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
    }
    guard connected == 0 else {
        fputs("archer-bridge: cannot connect to \(socketPath) — is Archer running?\n", stderr)
        exit(1)
    }

    data.withUnsafeBytes { ptr in _ = Darwin.write(fd, ptr.baseAddress!, ptr.count) }

    var buf = [UInt8](repeating: 0, count: 65536)
    let n = buf.withUnsafeMutableBufferPointer { Darwin.read(fd, $0.baseAddress, $0.count) }
    guard n > 0 else { exit(0) }

    let response = Data(bytes: buf, count: n)
    if let dict = try? JSONSerialization.jsonObject(with: response) as? [String: Any] {
        if let text = dict["text"] as? String {
            print(text, terminator: "")
        } else if let labels = dict["labels"] as? [String] {
            labels.forEach { print($0) }
        } else if let agents = dict["agents"] as? [[String: Any]] {
            for a in agents {
                let id = a["id"] as? String ?? "?"
                let name = a["name"] as? String ?? id
                print("\(id)\t\(name)")
            }
        } else if let ok = dict["ok"] as? Bool, ok {
            if let count = dict["count"] as? Int {
                print("synced \(count) pane(s)")
            } else if let label = dict["label"] as? String {
                let agent = dict["agent"] as? String ?? label
                let sid = dict["sessionId"] as? String ?? ""
                print("opened @\(label) (agent=\(agent)\(sid.isEmpty ? "" : " session=\(sid)"))")
            }
        } else if let err = dict["error"] as? String {
            fputs("error: \(err)\n", stderr); exit(1)
        }
    } else {
        print(String(data: response, encoding: .utf8) ?? "")
    }
}

/// Parse `handoff|open <agent> [--prompt …|--stdin] [--strict]`.
func parseHandoffArgs(_ rest: [String], allowPrompt: Bool) -> (agent: String, prompt: String?, strict: Bool) {
    guard let agent = rest.first else {
        fputs("usage: archer-bridge handoff <agent> [--prompt <text>|--stdin] [--strict]\n", stderr)
        exit(1)
    }
    var prompt: String?
    var strict = false
    var i = 1
    while i < rest.count {
        let a = rest[i]
        if a == "--strict" {
            strict = true
            i += 1
        } else if a == "--stdin", allowPrompt {
            prompt = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
            i += 1
        } else if a == "--prompt", allowPrompt {
            i += 1
            guard i < rest.count else {
                fputs("archer-bridge: --prompt needs a value\n", stderr); exit(1)
            }
            prompt = rest[i]
            i += 1
        } else if a.hasPrefix("--prompt="), allowPrompt {
            prompt = String(a.dropFirst("--prompt=".count))
            i += 1
        } else if allowPrompt, !a.hasPrefix("-"), prompt == nil {
            // Positional remainder joins as prompt: handoff hermes do the thing
            prompt = rest[i...].joined(separator: " ")
            break
        } else {
            fputs("archer-bridge: unexpected argument '\(a)'\n", stderr); exit(1)
        }
    }
    return (agent, prompt, strict)
}

let args = CommandLine.arguments.dropFirst()
guard let cmd = args.first else {
    print("""
    archer-bridge — Archer cross-pane agent bridge

    Commands:
      list                       List @labels (codex, codex-2, …)
      read <@label> [lines]      Read last N lines (default 20); @ optional
      type <@label> <text>       Inject text as keystrokes
      keys <@label> <key>…       Named keys (Enter, Tab, ctrl+c, …)
      sync                       Re-sync pane labels from active workspace
      agents                     List launchable agents (id + name)
      handoff <@agent> [prompt]  Open agent tab; optional prompt / --prompt / --stdin
      open <@agent>              Same as handoff without a prompt

    Labels accept with or without @ (e.g. codex and @codex).
    """)
    exit(0)
}

switch cmd {
case "list":
    send(["cmd": "list"])

case "sync":
    send(["cmd": "sync"])

case "agents":
    send(["cmd": "agents"])

case "read":
    guard let label = args.dropFirst().first else {
        fputs("usage: archer-bridge read <@label> [lines]\n", stderr); exit(1)
    }
    let lines = args.dropFirst(2).first.flatMap(Int.init) ?? 20
    send(["cmd": "read", "label": stripAt(label), "lines": lines])

case "type":
    let rest = Array(args.dropFirst())
    guard rest.count >= 2 else {
        fputs("usage: archer-bridge type <@label> <text>\n", stderr); exit(1)
    }
    send(["cmd": "type", "label": stripAt(rest[0]), "text": rest[1]])

case "keys":
    let rest = Array(args.dropFirst())
    guard rest.count >= 2 else {
        fputs("usage: archer-bridge keys <@label> <key> [key…]\n", stderr); exit(1)
    }
    send(["cmd": "keys", "label": stripAt(rest[0]), "keys": Array(rest.dropFirst())])

case "handoff":
    let parsed = parseHandoffArgs(Array(args.dropFirst()), allowPrompt: true)
    var payload: [String: Any] = [
        "cmd": "handoff",
        "agent": stripAt(parsed.agent),
        "strict": parsed.strict,
    ]
    if let p = parsed.prompt { payload["prompt"] = p }
    send(payload)

case "open":
    let parsed = parseHandoffArgs(Array(args.dropFirst()), allowPrompt: false)
    send(["cmd": "open", "agent": stripAt(parsed.agent), "strict": parsed.strict])

default:
    fputs("archer-bridge: unknown command '\(cmd)'\n", stderr); exit(1)
}
