import Foundation

class ClaudeSession: AgentSession {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineBuffer = ""
    private var currentResponseText = ""
    private var pendingMessages: [String] = []
    private(set) var isRunning = false
    private(set) var isBusy = false
    private static var binaryPath: String?

    /// Session settings: no auto-allows; every built-in tool and MCP call must prompt in-app.
    private static let strictPermissionSettings =
        #"{"permissions":{"defaultMode":"default","allow":[],"ask":["Bash","Read","Edit","Write","Glob","Grep","WebFetch","WebSearch","Task","TaskCreate","TaskGet","TaskList","TaskOutput","TaskStop","TaskUpdate","AskUserQuestion","NotebookEdit","Skill","EnterPlanMode","ExitPlanMode","EnterWorktree","ExitWorktree","CronCreate","CronDelete","CronList","Monitor","PushNotification","ScheduleWakeup","ToolSearch","mcp__*"]},"disableBypassPermissionsMode":"disable"}"#

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onPermissionRequest: ((AgentPermissionRequest) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    var history: [AgentMessage] = []

    // MARK: - Process Lifecycle

    func start() {
        if let cached = Self.binaryPath {
            launchProcess(binaryPath: cached)
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "claude", fallbackPaths: [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]) { [weak self] path in
            guard let self = self, let binaryPath = path else {
                let msg = "Claude CLI not found.\n\n\(ClaudeAgent.installInstructions)"
                self?.onError?(msg)
                self?.history.append(AgentMessage(role: .error, text: msg))
                return
            }
            Self.binaryPath = binaryPath
            self.launchProcess(binaryPath: binaryPath)
        }
    }

    private func launchProcess(binaryPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--permission-mode", "default",
            "--permission-prompt-tool", "stdio",
            "--settings", Self.strictPermissionSettings,
        ]
        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        proc.environment = ShellEnvironment.processEnvironment()

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isBusy = false
                self?.onProcessExit?()
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.processOutput(text)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.onError?(text)
                }
            }
        }

        do {
            try proc.run()
            process = proc
            inputPipe = inPipe
            outputPipe = outPipe
            errorPipe = errPipe
            isRunning = true
            let pending = pendingMessages
            pendingMessages = []
            for msg in pending {
                writeMessage(msg, to: inPipe)
            }
        } catch {
            let msg = "Failed to launch Claude CLI.\n\n\(ClaudeAgent.installInstructions)\n\nError: \(error.localizedDescription)"
            onError?(msg)
            history.append(AgentMessage(role: .error, text: msg))
        }
    }

    func send(message: String) {
        guard isRunning, let pipe = inputPipe else {
            pendingMessages.append(message)
            return
        }
        writeMessage(message, to: pipe)
    }

    private func writeMessage(_ message: String, to pipe: Pipe) {
        isBusy = true
        currentResponseText = ""
        history.append(AgentMessage(role: .user, text: message))

        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": message
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        let line = jsonStr + "\n"
        pipe.fileHandleForWriting.write(line.data(using: .utf8)!)
    }

    func terminate() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        isRunning = false
        isBusy = false
        pendingMessages.removeAll()
    }

    // MARK: - NDJSON Parsing

    private func processOutput(_ text: String) {
        lineBuffer += text
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            if !line.isEmpty {
                parseLine(line)
            }
        }
    }

    private func parseLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String ?? ""

        switch type {
        case "system":
            let subtype = json["subtype"] as? String ?? ""
            if subtype == "init" {
                onSessionReady?()
            }

        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "text", let text = block["text"] as? String {
                        currentResponseText += text
                        onText?(text)
                    } else if blockType == "tool_use" {
                        let toolName = block["name"] as? String ?? "Tool"
                        let input = block["input"] as? [String: Any] ?? [:]
                        let summary = formatToolSummary(toolName: toolName, input: input)
                        history.append(AgentMessage(role: .toolUse, text: "\(toolName): \(summary)"))
                        onToolUse?(toolName, input)
                    }
                }
            }

        case "user":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_result" {
                        let isError = block["is_error"] as? Bool ?? false
                        var summary = ""
                        if let resultInfo = json["tool_use_result"] as? [String: Any] {
                            if let text = resultInfo["type"] as? String, text == "text" {
                                if let file = resultInfo["file"] as? [String: Any],
                                   let path = file["filePath"] as? String {
                                    let lines = file["totalLines"] as? Int ?? 0
                                    summary = "\(path) (\(lines) lines)"
                                }
                            }
                        } else if let resultStr = json["tool_use_result"] as? String {
                            summary = String(resultStr.prefix(80))
                        }
                        if summary.isEmpty {
                            if let contentStr = block["content"] as? String {
                                summary = String(contentStr.prefix(80))
                            }
                        }
                        history.append(AgentMessage(role: .toolResult, text: isError ? "ERROR: \(summary)" : summary))
                        onToolResult?(summary, isError)
                    }
                }
            }

        case "result":
            isBusy = false
            let finalText: String
            if let result = json["result"] as? String, !result.isEmpty {
                finalText = result
            } else if !currentResponseText.isEmpty {
                finalText = currentResponseText
            } else {
                finalText = ""
            }
            if !finalText.isEmpty {
                history.append(AgentMessage(role: .assistant, text: finalText))
            }
            currentResponseText = ""
            onTurnComplete?()

        case "control_request", "sdk_control_request":
            handleControlRequest(json)

        default:
            break
        }
    }

    private func handleControlRequest(_ json: [String: Any]) {
        guard let request = json["request"] as? [String: Any] else { return }
        let subtype = request["subtype"] as? String ?? ""
        guard subtype == "can_use_tool" || subtype == "permission" else { return }

        let requestId = (json["request_id"] as? String) ?? (request["request_id"] as? String) ?? ""
        guard !requestId.isEmpty else { return }

        let toolName = (request["tool_name"] as? String) ?? "Tool"
        let toolInput = (request["input"] as? [String: Any])
            ?? (request["tool_input"] as? [String: Any])
            ?? [:]
        let detail = Self.formatPermissionDetail(toolName: toolName, input: toolInput)

        let respond: (Bool) -> Void = { [weak self] allowed in
            self?.respondToPermission(allowed: allowed, requestId: requestId, toolInput: toolInput)
        }

        if let onPermissionRequest {
            onPermissionRequest(AgentPermissionRequest(toolName: toolName, detail: detail, respond: respond))
        } else {
            respond(false)
        }
    }

    private func respondToPermission(allowed: Bool, requestId: String, toolInput: [String: Any]) {
        guard let pipe = inputPipe else { return }

        let responseBody: [String: Any]
        if allowed {
            responseBody = ["behavior": "allow", "updatedInput": toolInput]
        } else {
            responseBody = ["behavior": "deny", "message": "Denied by user"]
        }

        let payload: [String: Any] = [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestId,
                "response": responseBody
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        pipe.fileHandleForWriting.write((jsonStr + "\n").data(using: .utf8)!)
    }

    private static func formatPermissionDetail(toolName: String, input: [String: Any]) -> String {
        var lines: [String] = []

        func appendLine(_ label: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            lines.append("\(label): \(trimmed)")
        }

        func appendBlock(_ label: String, _ value: String, limit: Int = 1500) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if trimmed.count <= limit {
                lines.append("\(label):\n\(trimmed)")
            } else {
                let preview = String(trimmed.prefix(limit))
                lines.append("\(label):\n\(preview)\n… (\(trimmed.count - limit) more characters)")
            }
        }

        func warnIfSensitive(path: String?) {
            guard let path, isSensitivePath(path) else { return }
            lines.insert("⚠ Sensitive path — review carefully", at: 0)
        }

        switch toolName {
        case "Bash":
            appendBlock("Command", input["command"] as? String ?? "", limit: 4000)
            if let desc = input["description"] as? String { appendLine("Description", desc) }

        case "Read":
            let path = input["file_path"] as? String ?? ""
            warnIfSensitive(path: path)
            appendLine("Path", path)
            if let offset = input["offset"] { appendLine("Offset", "\(offset)") }
            if let limit = input["limit"] { appendLine("Limit", "\(limit)") }

        case "Write":
            let path = input["file_path"] as? String ?? ""
            warnIfSensitive(path: path)
            appendLine("Path", path)
            appendBlock("Content", input["content"] as? String ?? "")

        case "Edit":
            let path = input["file_path"] as? String ?? ""
            warnIfSensitive(path: path)
            appendLine("Path", path)
            appendBlock("Replace", input["old_string"] as? String ?? "")
            appendBlock("With", input["new_string"] as? String ?? "")

        case "Glob":
            appendLine("Pattern", input["pattern"] as? String ?? "")
            appendLine("Path", input["path"] as? String ?? "")

        case "Grep":
            appendLine("Pattern", input["pattern"] as? String ?? "")
            appendLine("Path", input["path"] as? String ?? input["file_path"] as? String ?? "")

        case "WebFetch", "WebSearch":
            appendLine("URL", input["url"] as? String ?? "")
            if let prompt = input["prompt"] as? String { appendLine("Prompt", prompt) }

        default:
            let priorityKeys = ["command", "url", "file_path", "path", "pattern", "content",
                                "old_string", "new_string", "description", "query"]
            var shown = Set<String>()
            for key in priorityKeys {
                if let value = input[key] as? String {
                    if key == "file_path" || key == "path" { warnIfSensitive(path: value) }
                    if ["content", "old_string", "new_string", "command"].contains(key) {
                        appendBlock(key, value, limit: key == "command" ? 4000 : 1500)
                    } else {
                        appendLine(key, value)
                    }
                    shown.insert(key)
                }
            }
            for key in input.keys.sorted() where !shown.contains(key) {
                if let value = input[key] as? String {
                    appendLine(key, value)
                } else if let value = input[key] {
                    appendLine(key, String(describing: value))
                }
            }
        }

        if lines.isEmpty { return "(no details provided)" }
        return lines.joined(separator: "\n\n")
    }

    private static func isSensitivePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let markers = ["/.ssh/", "/.aws/", "/.gnupg/", "/.env", "id_rsa", "id_ed25519",
                       "credentials", "secrets", "keychain", "/.netrc"]
        return markers.contains { lower.contains($0) }
    }

    private func formatToolSummary(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return input["command"] as? String ?? ""
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Edit", "Write":
            return input["file_path"] as? String ?? ""
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        default:
            if let desc = input["description"] as? String { return desc }
            return input.keys.sorted().prefix(3).joined(separator: ", ")
        }
    }
}
