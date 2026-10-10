import CryptoKit
import Darwin
import Foundation

/// 用 ChatGPT 帳號登入（跟 Pi、Codex 一樣的 OpenAI 官方登入流程：瀏覽器登入＋PKCE）。
/// 拿到的登入資料只寫進 App 自己的 Pi 設定資料夾（Paths.piAgentDir/auth.json，權限 600），
/// 之後由 Pi 自己負責更新。App 不會把它傳到任何其他地方。
public enum ChatGPTLogin {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authorizeURL = "https://auth.openai.com/oauth/authorize"
    static let tokenURL = "https://auth.openai.com/oauth/token"
    static let redirectURI = "http://localhost:1455/auth/callback"
    static let port: UInt16 = 1455

    public static func login(agentDir: URL = Paths.piAgentDir, timeout: TimeInterval = 300,
                             openBrowser: @escaping @Sendable (URL) -> Void) async throws {
        let verifier = randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomHex(16)
        var c = URLComponents(string: authorizeURL)!
        c.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI), .init(name: "scope", value: "openid profile email offline_access"),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state), .init(name: "id_token_add_organizations", value: "true"),
            .init(name: "codex_cli_simplified_flow", value: "true"), .init(name: "originator", value: "pi"),
        ]
        let server = try CallbackServer(port: port)
        defer { server.close() }
        openBrowser(c.url!)
        let code = try await server.waitForCode(state: state, timeout: timeout)
        let cred = try await exchange(code: code, verifier: verifier)
        try save(cred, agentDir: agentDir)
    }

    public static func logout(agentDir: URL = Paths.piAgentDir) {
        let file = agentDir.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: file),
              var all = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        all.removeValue(forKey: PiClient.provider)
        if let out = try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted]) {
            try? out.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    static func exchange(code: String, verifier: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [.init(name: "grant_type", value: "authorization_code"), .init(name: "client_id", value: clientID),
                           .init(name: "code", value: code), .init(name: "code_verifier", value: verifier),
                           .init(name: "redirect_uri", value: redirectURI)]
        req.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue else {
            throw WanderError(L10n.t("err.loginFailed", "token (\((resp as? HTTPURLResponse)?.statusCode ?? 0))"))
        }
        guard let account = accountID(fromJWT: access) else { throw WanderError(L10n.t("err.loginFailed", "account")) }
        return ["type": "oauth", "access": access, "refresh": refresh,
                "expires": Int64((Date().timeIntervalSince1970 + expiresIn) * 1000), "accountId": account]
    }

    static func accountID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let auth = payload["https://api.openai.com/auth"] as? [String: Any],
              let id = auth["chatgpt_account_id"] as? String, !id.isEmpty else { return nil }
        return id
    }

    static func save(_ cred: [String: Any], agentDir: URL) throws {
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let file = agentDir.appendingPathComponent("auth.json")
        var all: [String: Any] = [:]
        if let data = try? Data(contentsOf: file), let old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            all = old
        }
        all[PiClient.provider] = cred
        let out = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted])
        let tmp = agentDir.appendingPathComponent(".auth-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: tmp.path, contents: out, attributes: [.posixPermissions: 0o600])
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func randomBytes(_ n: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return b
    }
    static func randomURLSafe(_ n: Int) -> String { Data(randomBytes(n)).base64URL }
    static func randomHex(_ n: Int) -> String { randomBytes(n).map { String(format: "%02x", $0) }.joined() }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// 只在本機（127.0.0.1 和 ::1）聽 1455 埠，等瀏覽器把登入結果送回來
public final class CallbackServer: @unchecked Sendable {
    private var fds: [Int32] = []

    init(port: UInt16) throws {
        if let fd = Self.listen4(port) { fds.append(fd) }
        if let fd = Self.listen6(port) { fds.append(fd) }
        if fds.isEmpty { throw WanderError(L10n.t("err.loginPort")) }
    }

    func close() { fds.forEach { Darwin.close($0) }; fds = [] }

    static func listen4(_ port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0, Darwin.listen(fd, 8) == 0 else { Darwin.close(fd); return nil }
        return fd
    }

    static func listen6(_ port: UInt16) -> Int32? {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_loopback
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
        guard ok == 0, Darwin.listen(fd, 8) == 0 else { Darwin.close(fd); return nil }
        return fd
    }

    func waitForCode(state: String, timeout: TimeInterval) async throws -> String {
        let fds = self.fds
        return try await withCheckedThrowingContinuation { cont in
            Thread.detachNewThread {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    var polls = fds.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
                    let r = poll(&polls, nfds_t(polls.count), 500)
                    if r < 0 { break }
                    for p in polls where p.revents & Int16(POLLIN) != 0 {
                        let client = accept(p.fd, nil, nil)
                        guard client >= 0 else { continue }
                        if let code = Self.handle(client, state: state) {
                            cont.resume(returning: code)
                            return
                        }
                    }
                }
                cont.resume(throwing: WanderError(L10n.t("err.loginTimeout")))
            }
        }
    }

    /// 讀一個 HTTP 請求；是正確的登入回呼就回傳 code
    static func handle(_ fd: Int32, state: String) -> String? {
        defer { Darwin.close(fd) }
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = recv(fd, &buf, buf.count, 0)
        guard n > 0 else { return nil }
        let req = String(decoding: buf[0..<n], as: UTF8.self)
        let line = req.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = line.split(separator: " ")
        var code: String?
        var message = L10n.isEnglish ? "Sign-in failed. Please go back to Wander Deck and try again." : "登入失敗，請回到漫遊簡報再試一次。"
        if parts.count >= 2, let comps = URLComponents(string: "http://localhost" + parts[1]), comps.path == "/auth/callback" {
            let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if q["state"] == state, let c = q["code"], !c.isEmpty {
                code = c
                message = L10n.isEnglish ? "Signed in. You can close this tab and go back to Wander Deck."
                                         : "登入完成！可以關掉這個分頁，回到漫遊簡報。"
            }
        }
        let html = """
        <!doctype html><meta charset="utf-8"><title>Wander Deck</title>
        <body style="font-family:-apple-system,sans-serif;display:grid;place-items:center;height:90vh;background:#f6f2ea;color:#3d4b5c">
        <div style="font-size:22px">\(message)</div></body>
        """
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(code == nil ? "400 Bad Request" : "200 OK")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        out.withUnsafeBytes { _ = send(fd, $0.baseAddress, out.count, 0) }
        return code
    }
}
