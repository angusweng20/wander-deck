import Foundation
import WanderCore

// 漫遊簡報命令列工具（App 裡也有一份，更新簡報.command 會用它）。
//   wander build <簡報資料夾> [--check]
//   wander scan <照片或資料夾...>              讀拍攝時間和地點
//   wander group place|date <照片或資料夾...>   試分類

setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    用法：
      wander build <簡報資料夾> [--check]
      wander scan <照片或資料夾...>
      wander group place|date <照片或資料夾...>
      wander make --title 標題 [--by place|date|ai] [--style id] [--ai] --out <放簡報的資料夾> <照片或資料夾...>
      wander login-status
      wander style check|import|export ...
    """)
    exit(1)
}

/// 跑非同步工作，同時讓主執行緒的 RunLoop 轉著（Apple 地圖查詢的回呼會回到主執行緒）
func runAsync(_ body: @escaping @Sendable () async throws -> Void) {
    final class Flag: @unchecked Sendable { var done = false }
    let flag = Flag()
    Task.detached {
        do { try await body() } catch { print("錯誤：\(error.localizedDescription)"); exit(1) }
        flag.done = true
    }
    while !flag.done { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
}

func printGroups(_ groups: [PhotoGroup], _ indent: String = "") {
    for g in groups {
        print("\(indent)\(g.name)（\(g.count)）" + (g.countryCode.map { " [\($0)]" } ?? ""))
        printGroups(g.children, indent + "  ")
    }
}

guard let cmd = args.first else { usage() }
switch cmd {
case "build":
    guard args.count >= 2 else { usage() }
    let check = args.contains("--check")
    let b = DeckBuilder(deck: URL(fileURLWithPath: args[1]))
    var last = -1
    b.progress = { done, total in
        let pct = total > 0 ? done * 100 / total : 100
        if pct / 10 != last / 10 { print("  \(done)/\(total)"); last = pct }
    }
    do {
        try b.run(checkOnly: check)
        b.summary.forEach { print($0) }
        b.warnings.forEach { print("⚠️  " + $0) }
        print(check ? "檢查完成。" : "完成：簡報已更新。")
        exit(check && !b.warnings.isEmpty ? 1 : 0)
    } catch {
        print("錯誤：\(error.localizedDescription)")
        exit(1)
    }
case "scan":
    let items = MetadataReader.scan(args.dropFirst().map { URL(fileURLWithPath: $0) })
    let f = ISO8601DateFormatter()
    for it in items {
        let loc = it.location.map { String(format: "%.4f,%.4f", $0.lat, $0.lon) } ?? "-"
        print("\(it.filename)\t\(it.date.map { f.string(from: $0) } ?? "-")\t\(it.utcOffset.map(String.init) ?? "-")\t\(loc)")
    }
case "group":
    guard args.count >= 3, ["place", "date"].contains(args[1]) else { usage() }
    let items = MetadataReader.scan(args.dropFirst(2).map { URL(fileURLWithPath: $0) })
    if args[1] == "date" {
        printGroups(Grouping.byDate(items))
    } else {
        runAsync {
            let groups = await Grouping.byPlace(items, lookup: AppleGeocoder()) { d, t in print("  查地名 \(d)/\(t)") }
            printGroups(groups)
            print("主要國家：\(Grouping.dominantCountry(groups) ?? "-")")
        }
    }
case "login-status":
    if let exe = PiClient.findExecutable() {
        print("Pi：\(exe.path)")
        print("App 自己的登入：\(PiClient(executable: exe, agentDir: Paths.piAgentDir).isLoggedIn() ? "有" : "沒有")")
        print("Pi 預設登入：\(PiClient(executable: exe, agentDir: nil).isLoggedIn() ? "有" : "沒有")")
    } else {
        print(L10n.t("err.noPi"))
    }
case "make":
    var title = "", by = "place", styleID: String?, out: URL?, useAI = false, paths: [URL] = []
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--title": title = args[i + 1]; i += 2
        case "--by": by = args[i + 1]; i += 2
        case "--style": styleID = args[i + 1]; i += 2
        case "--out": out = URL(fileURLWithPath: args[i + 1]); i += 2
        case "--ai": useAI = true; i += 1
        default: paths.append(URL(fileURLWithPath: args[i])); i += 1
        }
    }
    guard let out, !paths.isEmpty else { usage() }
    let (by0, styleID0, useAI0, paths0, title0) = (by, styleID, useAI, paths, title)
    runAsync {
        let (by, styleID, useAI, paths) = (by0, styleID0, useAI0, paths0)
        var title = title0
        let items = MetadataReader.scan(paths)
        print("照片：\(items.count) 個檔案")
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let ai: AIService? = (useAI || by == "ai") ? PiClient.resolve().map { pi in
            AIService(pi: pi) { item, px in item.fileURL.flatMap { ImageTools.aiThumbnail($0, maxPixel: px) } }
        } : nil
        if (useAI || by == "ai") && ai == nil { print(L10n.t("err.notLoggedIn")); exit(1) }
        var groups: [PhotoGroup]
        switch by {
        case "date": groups = Grouping.byDate(items)
        case "ai":
            let themes = try await ai!.proposeThemes(items)
            print("AI 想的主題：\(themes.joined(separator: "、"))")
            groups = try await ai!.assign(items, to: themes) { d, t in print("  分類 \(d)/\(t)") }
        default: groups = await Grouping.byPlace(items, lookup: AppleGeocoder())
        }
        var subtitle = L10n.t("subtitle.default")
        if let ai {
            let naming = try await ai.nameGroups(groups, items: byID)
            func rename(_ g: inout PhotoGroup) {
                if let n = naming.names[g.id] { g.name = n }
                for j in g.children.indices { rename(&g.children[j]) }
            }
            for j in groups.indices { rename(&groups[j]) }
            if title.isEmpty { title = naming.title }
            if !naming.subtitle.isEmpty { subtitle = naming.subtitle }
            print("AI 標題：\(naming.title)／\(naming.subtitle)")
        }
        printGroups(groups)
        let packs = StyleLibrary.all()
        let style = styleID.flatMap { id in packs.first { $0.id == id } }
            ?? StyleLibrary.best(forCountry: Grouping.dominantCountry(groups), in: packs)
        print("風格：\(style?.id ?? "-")")
        let spec = DeckSpec(title: title, subtitle: subtitle, parentFolder: out, groups: groups, items: byID, style: style)
        final class Last: @unchecked Sendable { var msg = "" }
        let last = Last()
        let deck = try await DeckMaker.make(spec) { p in
            let head = String(p.message.prefix(4))
            if head != last.msg { print("  " + p.message); last.msg = head }
        }
        print("完成：\(deck.path)")
    }
case "style":
    guard args.count >= 3 else { usage() }
    do {
        switch args[1] {
        case "check":
            let issues = StyleLibrary.problems(in: URL(fileURLWithPath: args[2]))
            print(issues.isEmpty ? "✅ 合格" : issues.map { "❌ " + $0 }.joined(separator: "\n"))
        case "import":
            let p = try StyleLibrary.importPack(URL(fileURLWithPath: args[2]))
            print("已匯入：\(p.id) → \(p.folder.path)")
        case "export":
            guard args.count >= 4, let p = StyleLibrary.all().first(where: { $0.id == args[2] }) else { usage() }
            try StyleLibrary.export(p, to: URL(fileURLWithPath: args[3]))
            print("已匯出：\(args[3])")
        default: usage()
        }
    } catch { print("錯誤：\(error.localizedDescription)"); exit(1) }
case "dev-fixture":
    // 測試用：把一批圖片複製一份，寫上假的拍攝時間和 GPS（京都、大阪、東京、台北），不碰原圖
    guard args.count == 3 else { usage() }
    let src = MetadataReader.scan([URL(fileURLWithPath: args[1])]).filter { $0.kind == .photo }
    let dest = URL(fileURLWithPath: args[2])
    try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let spots: [(String, Double, Double, String, Int)] = [
        ("Kyoto", 35.0116, 135.7681, "2026:11:02", 9), ("Osaka", 34.6687, 135.5013, "2026:11:03", 9),
        ("Tokyo", 35.6764, 139.6500, "2026:11:04", 9), ("Taipei", 25.0330, 121.5654, "2026:11:06", 8),
    ]
    for (i, it) in src.enumerated() {
        let spot = spots[i * spots.count / max(src.count, 1)]
        let noGPS = i % 7 == 3          // 有幾張故意不給 GPS，測「用前後照片推位置」
        let noDate = i == src.count - 1 // 最後一張什麼都沒有
        WriteFixture.write(it.fileURL!, to: dest.appendingPathComponent(String(format: "IMG_%04d.jpg", i + 1)),
                           date: noDate ? nil : "\(spot.3) \(String(format: "%02d", 10 + i % 8)):1\(i % 10):00",
                           offset: spot.4 == 9 ? "+09:00" : "+08:00",
                           lat: noGPS || noDate ? nil : spot.1 + Double(i % 5) * 0.004, lon: noGPS || noDate ? nil : spot.2 + Double(i % 3) * 0.004)
    }
    print("已產生 \(src.count) 張測試照片：\(dest.path)")
default:
    usage()
}
