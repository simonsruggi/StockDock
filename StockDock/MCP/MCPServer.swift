import Foundation

/// Minimal Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0).
/// Started with `--mcp` instead of the menu bar UI, so Claude, Cursor and other
/// MCP clients can read the app's data. Tools only read: nothing here changes app state.
struct MCPTool {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    let handler: ([String: Any]) throws -> Any
}

struct MCPToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

final class MCPServer {
    /// True when the process was launched as an MCP server: no UI, no updater.
    static let requested = CommandLine.arguments.contains("--mcp")

    private let name: String
    private let version: String
    private let instructions: String
    private let tools: [MCPTool]
    private static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    init(name: String, instructions: String, tools: [MCPTool]) {
        self.name = name
        self.version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        self.instructions = instructions
        self.tools = tools
    }

    /// Reads requests on a background thread and keeps the main thread free, so tools can
    /// wait for @MainActor and async code with `MCPServer.wait`.
    func run() -> Never {
        Thread.detachNewThread { [self] in
            while let line = readLine(strippingNewline: true) {
                guard !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8),
                      let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                    continue
                }
                handle(message)
            }
            exit(0)
        }
        dispatchMain()
    }

    /// Runs async main-actor work from a tool handler and blocks until it finishes.
    static func wait<T>(_ operation: @escaping @MainActor () async throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!
        Task { @MainActor in
            do { result = .success(try await operation()) } catch { result = .failure(error) }
            done.signal()
        }
        done.wait()
        return try result.get()
    }

    private func handle(_ message: [String: Any]) {
        let method = message["method"] as? String ?? ""
        // Notifications (no id) never get a response.
        guard let id = message["id"] else { return }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let protocolVersion = Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0]
            reply(id, [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": name, "version": version],
                "instructions": instructions,
            ])
        case "ping":
            reply(id, [String: Any]())
        case "tools/list":
            reply(id, ["tools": tools.map {
                [
                    "name": $0.name,
                    "description": $0.description,
                    "inputSchema": $0.inputSchema,
                    "annotations": ["readOnlyHint": true, "openWorldHint": false],
                ] as [String: Any]
            }])
        case "tools/call":
            let toolName = params["name"] as? String ?? ""
            guard let tool = tools.first(where: { $0.name == toolName }) else {
                fail(id, code: -32602, "Unknown tool: \(toolName)")
                return
            }
            do {
                let result = try tool.handler(params["arguments"] as? [String: Any] ?? [:])
                reply(id, ["content": [["type": "text", "text": Self.text(result)]], "isError": false])
            } catch {
                reply(id, ["content": [["type": "text", "text": "\(error)"]], "isError": true])
            }
        default:
            fail(id, code: -32601, "Method not found: \(method)")
        }
    }

    private static func text(_ value: Any) -> String {
        if let s = value as? String { return s }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8)
        else { return "\(value)" }
        return s
    }

    private func reply(_ id: Any, _ result: Any) {
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func fail(_ id: Any, code: Int, _ message: String) {
        send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
    }
}

extension Dictionary where Key == String, Value == Any {
    func int(_ key: String, default value: Int, range: ClosedRange<Int>) -> Int {
        let raw = (self[key] as? Int) ?? (self[key] as? Double).map { Int($0) } ?? value
        return Swift.min(Swift.max(raw, range.lowerBound), range.upperBound)
    }

    func string(_ key: String) -> String? {
        (self[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
