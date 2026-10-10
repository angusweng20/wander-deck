import XCTest
@testable import WanderCore

/// 測試時不碰使用者真正的 Application Support
func useTempSupportDir() {
    if ProcessInfo.processInfo.environment["WANDER_SUPPORT_DIR"] == nil {
        setenv("WANDER_SUPPORT_DIR", Fixtures.tempDir("support").path, 1)
    }
}

final class DeckTests: XCTestCase {
    override class func setUp() { useTempSupportDir() }

    /// 用 DeckMaker 從零做一份：依地點分好的主題、水彩風格、自動拍立得
    func testMakeDeckEndToEnd() async throws {
        let src = Fixtures.tempDir("src")
        for i in 0..<3 { Fixtures.photo(src.appendingPathComponent("k\(i).jpg"), date: "2026:11:02 1\(i):00:00", offset: "+09:00", lat: 35, lon: 135.7) }
        for i in 0..<5 { Fixtures.photo(src.appendingPathComponent("t\(i).jpg"), w: 600, h: 900, date: "2026:11:04 1\(i):00:00", offset: "+09:00", lat: 35.6, lon: 139.6) }
        let items = MetadataReader.scan([src])
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let groups = await Grouping.byPlace(items, lookup: GroupingTests.FakeLookup())
        let style = StyleLibrary.all().first { $0.id == "watercolor" }
        XCTAssertNotNil(style)
        let out = Fixtures.tempDir("out")
        let spec = DeckSpec(title: "京都・秋日", subtitle: "五天四夜", parentFolder: out, groups: groups, items: byID, style: style)
        let deck = try await DeckMaker.make(spec) { _ in }

        let fm = FileManager.default
        for f in [DeckMaker.htmlName, DeckMaker.openName, DeckMaker.updateName, "_wander/build.py", "_style/style.json", "deck.json"] {
            XCTAssertTrue(fm.fileExists(atPath: deck.appendingPathComponent(f).path), f)
        }
        XCTAssertTrue(fm.isExecutableFile(atPath: deck.appendingPathComponent(DeckMaker.updateName).path))
        let data = try Fixtures.loadDataJS(deck)
        let topics = data["topics"] as! [[String: Any]]
        XCTAssertEqual(topics.map { $0["name"] as! String }, ["京都市", "東京"])
        XCTAssertEqual((topics[0]["items"] as! [Any]).count, 3)
        XCTAssertEqual(topics[0]["layout"] as? String, "wall")       // 3 張：自動用展示牆
        XCTAssertNil(topics[1]["layout"])                             // 5 張：一般照片牆
        XCTAssertEqual(data["css"] as? String, "_style/style.css")
        let intro = (data["intro"] as! [[String: Any]])[0]
        XCTAssertEqual((intro["title"] as! [String: Any])["text"] as? String, "京都・秋日")
        XCTAssertEqual(((intro["texts"] as! [[String: Any]])[0])["text"] as? String, "五天四夜")
        let cards = intro["cards"] as! [[String: Any]]
        XCTAssertEqual(cards.map { $0["caption"] as! String }, ["京都市", "東京"])
        XCTAssertTrue((cards[0]["photo"] as! String).hasPrefix("_wander/large/"))
        // 原始照片沒被動到
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: src.path).count, 8)

        // 同一份簡報用 Python 版 build.py 產生，結果要一樣
        if Fixtures.hasPython {
            let py = Fixtures.tempDir("py")
            try fm.removeItem(at: py)
            try fm.copyItem(at: deck, to: py)
            try? fm.removeItem(at: py.appendingPathComponent("_wander/data.js"))
            let (code, log) = Fixtures.run("/usr/bin/python3", ["_wander/build.py"], cwd: py)
            XCTAssertEqual(code, 0, log)
            let pyData = try Fixtures.loadDataJS(py)
            XCTAssertEqual(Self.shape(pyData), Self.shape(data))
        }
    }

    /// 比對結構（照片長寬比只看到小數點後兩位）
    static func shape(_ v: Any) -> String {
        if let d = v as? [String: Any] { return "{" + d.keys.sorted().map { "\($0):\(shape(d[$0]!))" }.joined(separator: ",") + "}" }
        if let a = v as? [Any] { return "[" + a.map(shape).joined(separator: ",") + "]" }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return String(format: "%.2f", n.doubleValue) }
        if v is NSNull { return "null" }
        return "\(v)"
    }

    func testBuilderWarnsAboutMissingFolders() throws {
        let deck = Fixtures.tempDir("warn")
        try DeckMaker.installEngine(into: deck)
        Fixtures.photo(deck.appendingPathComponent("01 海/a.jpg"))
        try #"{"title":"x","topics":{"order":["不存在"],"walls":["海"]}}"#.write(to: deck.appendingPathComponent("deck.json"), atomically: true, encoding: .utf8)
        let b = DeckBuilder(deck: deck)
        try b.run()
        XCTAssertTrue(b.warnings.contains { $0.contains("不存在") })
        XCTAssertTrue(b.warnings.contains { $0.contains("「海」") })
        XCTAssertEqual(DeckBuilder.displayName("03 京都"), "京都")
        XCTAssertEqual(DeckBuilder.displayName("1.海邊"), "海邊")
    }
}

final class StyleTests: XCTestCase {
    override class func setUp() { useTempSupportDir() }

    func testBundledStylesAreValid() {
        let packs = StyleLibrary.all()
        XCTAssertEqual(Set(packs.map(\.id)).isSuperset(of: ["watercolor", "ukiyoe", "classic"]), true)
        for p in packs where p.isBuiltIn { XCTAssertEqual(StyleLibrary.problems(in: p.folder), [], p.id) }
        XCTAssertEqual(StyleLibrary.best(forCountry: "JP", in: packs)?.id, "ukiyoe")
        XCTAssertEqual(StyleLibrary.best(forCountry: "FR", in: packs)?.id, "watercolor")
        XCTAssertEqual(StyleLibrary.best(forCountry: nil, in: packs)?.id, "watercolor")
    }

    func testExportImportRoundTrip() throws {
        let pack = StyleLibrary.all().first { $0.id == "classic" }!
        let file = Fixtures.tempDir("export").appendingPathComponent("classic.wdstyle")
        try StyleLibrary.export(pack, to: file)
        let imported = try StyleLibrary.importPack(file)
        XCTAssertEqual(imported.id, "classic")
        XCTAssertFalse(imported.isBuiltIn)
        XCTAssertTrue(imported.folder.path.hasPrefix(Paths.userStyles.path))
    }

    /// 別人做的風格包：有程式檔或路徑跳出資料夾，一律擋下
    func testRejectsUnsafePacks() throws {
        guard Fixtures.hasPython else { throw XCTSkip("需要 python3 來做惡意 zip") }
        let dir = Fixtures.tempDir("evil")
        let script = """
        import zipfile, sys
        meta = '{"format":"wander-style/1","id":"evil","name":"x","version":"1.0.0","author":"x","license":"CC-BY-4.0","credits":"CREDITS.md"}'
        with zipfile.ZipFile(sys.argv[1], 'w') as z:
            z.writestr('evil/style.json', meta); z.writestr('evil/CREDITS.md', 'x'); z.writestr('evil/hack.js', 'alert(1)')
        with zipfile.ZipFile(sys.argv[2], 'w') as z:
            z.writestr('evil/style.json', meta); z.writestr('evil/CREDITS.md', 'x'); z.writestr('../../escape.png', 'x')
        """
        try script.write(to: dir.appendingPathComponent("mk.py"), atomically: true, encoding: .utf8)
        let js = dir.appendingPathComponent("js.wdstyle"), up = dir.appendingPathComponent("up.wdstyle")
        Fixtures.run("/usr/bin/python3", [dir.appendingPathComponent("mk.py").path, js.path, up.path])
        XCTAssertThrowsError(try StyleLibrary.importPack(js))
        XCTAssertThrowsError(try StyleLibrary.importPack(up))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Paths.userStyles.appendingPathComponent("evil").path))
    }
}

final class LoginTests: XCTestCase {
    func testCallbackServerOnlyAcceptsMatchingState() async throws {
        let port: UInt16 = 18455
        let server = try CallbackServer(port: port)
        defer { server.close() }
        let wait = Task { try await server.waitForCode(state: "good", timeout: 10) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let bad = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/auth/callback?code=x&state=bad")!)
        XCTAssertEqual((bad.1 as? HTTPURLResponse)?.statusCode, 400)
        let good = try await URLSession.shared.data(from: URL(string: "http://localhost:\(port)/auth/callback?code=abc123&state=good")!)
        XCTAssertEqual((good.1 as? HTTPURLResponse)?.statusCode, 200)
        let code = try await wait.value
        XCTAssertEqual(code, "abc123")
    }

    func testAccountIDFromToken() {
        let payload = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct_42"}}"#
        let b64 = Data(payload.utf8).base64URL
        XCTAssertEqual(ChatGPTLogin.accountID(fromJWT: "h.\(b64).s"), "acct_42")
        XCTAssertNil(ChatGPTLogin.accountID(fromJWT: "nope"))
    }
}
