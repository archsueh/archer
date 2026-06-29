#!/usr/bin/env swift
// archer-bridge — CLI client for the Archer BridgeServer.
//
// Usage:
//   archer-bridge list
//   archer-bridge read <label> [lines]
//   archer-bridge type <label> <text>
//   archer-bridge keys <label> <key> [key…]
//   archer-bridge sync
//
// Wire: connects to ~/.archer/bridge.sock, sends one JSON line, prints response.

import Darwin
import Foundation

let socketPath = (NSHomeDirectory() as NSString)
    .appendingPathComponent(".archer/bridge.sock")

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
        // Pretty-print text separately so it renders newlines correctly.
        if let text = dict["text"] as? String {
            print(text, terminator: "")
        } else if let labels = dict["labels"] as? [String] {
            labels.forEach { print($0) }
        } else if let ok = dict["ok"] as? Bool, ok {
            // type / keys / sync — just confirm
            if let count = dict["count"] as? Int { print("synced \(count) pane(s)") }
        } else if let err = dict["error"] as? String {
            fputs("error: \(err)\n", stderr); exit(1)
        }
    } else {
        print(String(data: response, encoding: .utf8) ?? "")
    }
}

let args = CommandLine.arguments.dropFirst()
guard let cmd = args.first else {
    print("""
    archer-bridge — Archer cross-pane agent bridge

    Commands:
      list                       List all @labels (pane name → agent)
      read <label> [lines]       Read last N lines from pane (default 20)
      type <label> <text>        Inject text into pane as keystrokes
      keys <label> <key>…        Send named keys (Enter, Tab, ctrl+c, …)
      sync                       Re-sync pane labels from active workspace
    """)
    exit(0)
}

switch cmd {
case "list":
    send(["cmd": "list"])

case "sync":
    send(["cmd": "sync"])

case "read":
    guard let label = args.dropFirst().first else {
        fputs("usage: archer-bridge read <label> [lines]\n", stderr); exit(1)
    }
    let lines = args.dropFirst(2).first.flatMap(Int.init) ?? 20
    send(["cmd": "read", "label": label, "lines": lines])

case "type":
    let rest = Array(args.dropFirst())
    guard rest.count >= 2 else {
        fputs("usage: archer-bridge type <label> <text>\n", stderr); exit(1)
    }
    send(["cmd": "type", "label": rest[0], "text": rest[1]])

case "keys":
    let rest = Array(args.dropFirst())
    guard rest.count >= 2 else {
        fputs("usage: archer-bridge keys <label> <key> [key…]\n", stderr); exit(1)
    }
    send(["cmd": "keys", "label": rest[0], "keys": Array(rest.dropFirst())])

default:
    fputs("archer-bridge: unknown command '\(cmd)'\n", stderr); exit(1)
}
