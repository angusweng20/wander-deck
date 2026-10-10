import Foundation

/// 在背景啟動 Pi（pi --mode rpc），送一段文字和幾張圖，等它回答。
/// Pi 只拿來「看圖回答」：工具、技能、外掛、專案設定檔全部關掉，它碰不到使用者的檔案。
public final class PiClient: @unchecked Sendable {
    public static let provider = "openai-codex"
    /// ChatGPT 訂閱登入時不能用 mini 小模型（第 0 階段實測），用 gpt-5.5
    public static let model = "gpt-5.5"

    let executable: URL
    /// nil＝用 Pi 預設的 ~/.pi/agent（使用者自己已經用 Pi 登入過）
    public let agentDir: URL?

    public init(executable: URL, agentDir: URL?) {
        self.executable = executable
        self.agentDir = agentDir
    }

    /// App 內附的 Pi；開發時退而求其次用電腦上裝的
    public static func findExecutable() -> URL? {
        var candidates = [Paths.resources.deletingLastPathComponent().appendingPathComponent("Helpers/pi/pi"),
                          Paths.resources.appendingPathComponent("pi/pi")]
        if let env = ProcessInfo.processInfo.environment["WANDER_PI"] { candidates.insert(URL(fileURLWithPath: env), at: 0) }
        candidates += ["/opt/homebrew/bin/pi", "/usr/local/bin/pi"].map { URL(fileURLWithPath: $0) }
        candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/pi"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let agentDir { env["PI_CODING_AGENT_DIR"] = agentDir.path } else { env.removeValue(forKey: "PI_CODING_AGENT_DIR") }
        env["PI_SKIP_VERSION_CHECK"] = "1"
        env["PI_TELEMETRY"] = "0"
        env["PI_PROGRAM_STATUS"] = "0"
        return env
    }

    /// 這個設定資料夾有沒有可用的 ChatGPT 登入（不會印出任何金鑰）
    public func isLoggedIn() -> Bool {
        let p = Process()
        p.executableURL = executable
        p.arguments = ["auth", "check", "--provider", Self.provider]
        p.environment = environment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return false }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return p.terminationStatus == 0 && out.lowercased().contains("ready")
    }

    public enum Health { case ok, missing, blocked }

    /// Pi 能不能跑？從網路下載的 App，Mac 有可能另外擋住裡面的 Pi（會被系統直接結束）
    public static func health() -> Health {
        guard let exe = findExecutable() else { return .missing }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["--version"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return .blocked }
        p.waitUntilExit()
        return p.terminationReason == .uncaughtSignal || p.terminationStatus != 0 ? .blocked : .ok
    }

    /// 先看 App 自己的登入；沒有的話，看使用者是不是已經用 Pi 登入過 ChatGPT
    public static func resolve() -> PiClient? {
        guard let exe = findExecutable() else { return nil }
        let own = PiClient(executable: exe, agentDir: Paths.piAgentDir)
        if own.isLoggedIn() { return own }
        let shared = PiClient(executable: exe, agentDir: nil)
        if shared.isLoggedIn() { return shared }
        return nil
    }

    /// 送出問題＋圖片，回傳 AI 的文字回答
    public func ask(_ text: String, images: [Data], timeout: TimeInterval = 240) async throws -> String {
        let p = Process()
        p.executableURL = executable
        p.arguments = ["--mode", "rpc", "--provider", Self.provider, "--model", Self.model, "--thinking", "low",
                       "--no-tools", "--no-session", "--no-context-files", "--no-skills", "--no-extensions",
                       "--no-prompt-templates", "--no-themes"]
        p.environment = environment()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("wander-pi", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        p.currentDirectoryURL = work
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        try p.run()

        final class State: @unchecked Sendable {
            var buffer = Data()
            var answer: String?
            var error: String?
            var finished = false
            let lock = NSLock()
        }
        let state = State()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            @Sendable func finish() {
                state.lock.lock()
                if state.finished { state.lock.unlock(); return }
                state.finished = true
                state.lock.unlock()
                output.fileHandleForReading.readabilityHandler = nil
                try? input.fileHandleForWriting.close()
                if p.isRunning { p.terminate() }
                if let a = state.answer, !a.isEmpty { cont.resume(returning: a) }
                else { cont.resume(throwing: WanderError(L10n.t("err.aiFailed", state.error ?? "—"))) }
            }
            output.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                if chunk.isEmpty { finish(); return }
                state.lock.lock()
                state.buffer.append(chunk)
                var lines: [Data] = []
                while let nl = state.buffer.firstIndex(of: 0x0A) {
                    lines.append(state.buffer[state.buffer.startIndex..<nl])
                    state.buffer.removeSubrange(state.buffer.startIndex...nl)
                }
                state.lock.unlock()
                for line in lines {
                    guard let ev = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    switch ev["type"] as? String {
                    case "response":
                        if ev["success"] as? Bool == false { state.error = ev["error"] as? String ?? "rejected"; finish() }
                    case "message_end":
                        if let m = ev["message"] as? [String: Any], m["role"] as? String == "assistant" {
                            if let err = m["errorMessage"] as? String, !err.isEmpty { state.error = err }
                            let text = (m["content"] as? [[String: Any]] ?? [])
                                .filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
                            if !text.isEmpty { state.answer = text }
                        }
                    case "agent_settled":
                        finish()
                    case "agent_end":   // 後面可能還有自動重試；等一下，沒有新動靜就收工
                        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { finish() }
                    default: break
                    }
                }
            }
            p.terminationHandler = { _ in
                if state.error == nil {
                    let e = String(decoding: errors.fileHandleForReading.availableData, as: UTF8.self)
                    if !e.isEmpty { state.error = String(e.suffix(300)) }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { finish() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if state.error == nil { state.error = "timeout" }
                finish()
            }
            let cmd: [String: Any] = [
                "id": "wd-1", "type": "prompt", "message": text,
                "images": images.map { ["type": "image", "mimeType": "image/jpeg", "data": $0.base64EncodedString()] },
            ]
            do {
                var data = try JSONSerialization.data(withJSONObject: cmd)
                data.append(0x0A)
                try input.fileHandleForWriting.write(contentsOf: data)
            } catch {
                state.error = error.localizedDescription
                finish()
            }
        }
    }

    /// 從 AI 的回答裡挖出第一個 JSON 物件
    public static func extractJSON(_ text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
    }
}
