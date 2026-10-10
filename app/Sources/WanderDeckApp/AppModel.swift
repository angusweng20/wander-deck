import AppKit
import Photos
import SwiftUI
import WanderCore

enum Step: Int, CaseIterable { case welcome, pick, sort, theme, make }

enum SortMode: String, CaseIterable, Identifiable {
    case place, date, manual, ai
    var id: String { rawValue }
    var label: String { L10n.t("sort.\(rawValue)") }
    var help: String { L10n.t("sort.\(rawValue).help") }
}

enum LoginState: Equatable { case checking, signedIn(shared: Bool), signedOut, signingIn, noPi, piBlocked }

@MainActor
final class AppModel: ObservableObject {
    @Published var step: Step = .welcome
    @Published var language: String = UserDefaults.standard.string(forKey: L10n.languageKey) ?? "system"
    @Published var login: LoginState = .checking
    @Published var useAI = true

    @Published var items: [PhotoItem] = []
    @Published var groups: [PhotoGroup] = []
    @Published var mode: SortMode = .place
    @Published var aiThemes = ""
    @Published var selectedGroup: UUID?
    @Published var selection: Set<String> = []

    @Published var title = ""
    @Published var subtitle = ""
    @Published var styleAuto = true
    @Published var styleID = StyleLibrary.defaultID
    @Published var styles: [StylePack] = StyleLibrary.all()
    @Published var music: URL?
    @Published var qrImage: URL?
    @Published var qrHandle = ""
    @Published var saveFolder: URL = Paths.defaultDecksFolder

    @Published var busy: String?
    @Published var progress: Double?
    @Published var error: String?
    @Published var notice: String?
    @Published var resultDeck: URL?
    @Published var update: Updates.Release?

    private(set) var itemsByID: [String: PhotoItem] = [:]
    private var pi: PiClient?
    private var groupedFor: (SortMode, Int)?
    private var work: Task<Void, Never>?

    init() {
        Task { await refreshLogin() }
        Task { update = await Updates.latest() }
    }

    // MARK: 語言

    func setLanguage(_ value: String) {
        language = value
        if value == "system" { UserDefaults.standard.removeObject(forKey: L10n.languageKey) }
        else { UserDefaults.standard.set(value, forKey: L10n.languageKey) }
        styles = StyleLibrary.all()
        objectWillChange.send()
    }

    // MARK: 登入

    func refreshLogin() async {
        login = .checking
        let found: (PiClient?, PiClient.Health) = await Task.detached {
            let h = PiClient.health()
            return (h == .ok ? PiClient.resolve() : nil, h)
        }.value
        switch found.1 {
        case .missing: login = .noPi; pi = nil; useAI = false; return
        case .blocked: login = .piBlocked; pi = nil; useAI = false; return
        case .ok: break
        }
        pi = found.0
        if let p = found.0 { login = .signedIn(shared: p.agentDir == nil) } else { login = .signedOut }
    }

    var aiReady: Bool { if case .signedIn = login { return useAI } else { return false } }

    func signIn() {
        login = .signingIn
        Task {
            do {
                try await ChatGPTLogin.login { url in
                    Task { @MainActor in NSWorkspace.shared.open(url) }
                }
                useAI = true
            } catch {
                self.error = error.localizedDescription
            }
            await refreshLogin()
        }
    }

    func signOut() {
        ChatGPTLogin.logout()
        Task { await refreshLogin() }
    }

    // MARK: 挑照片

    var photoCount: Int { items.filter { $0.kind == .photo }.count }
    var videoCount: Int { items.filter { $0.kind == .video }.count }

    func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        busy = L10n.t("pick.reading", 0, 0)
        Task {
            let found = await Task.detached {
                MetadataReader.scan(urls) { d, t in
                    Task { @MainActor in self.busy = L10n.t("pick.reading", d, t) }
                }
            }.value
            append(found)
            busy = nil
        }
    }

    func addFromPhotos(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        Task {
            guard await PhotosLibrary.requestAccess() else { error = L10n.t("pick.denied"); return }
            append(PhotosLibrary.items(for: identifiers))
        }
    }

    private func append(_ new: [PhotoItem]) {
        for it in new where itemsByID[it.id] == nil {
            itemsByID[it.id] = it
            items.append(it)
        }
        groupedFor = nil
    }

    func remove(_ ids: Set<String>) {
        items.removeAll { ids.contains($0.id) }
        ids.forEach { itemsByID.removeValue(forKey: $0) }
        groups = groups.map { removing(ids, from: $0) }
        selection.subtract(ids)
        groupedFor = nil
    }

    func clearAll() {
        items = []; itemsByID = [:]; groups = []; selection = []; groupedFor = nil
    }

    // MARK: 分類

    func enterSort() {
        if groupedFor?.0 != mode || groupedFor?.1 != items.count || groups.isEmpty { regroup() }
    }

    func regroup() {
        selection = []
        let list = items
        switch mode {
        case .date:
            setGroups(Grouping.byDate(list))
        case .manual:
            setGroups([PhotoGroup(name: L10n.t("unsorted"), itemIDs: list.map(\.id))])
        case .ai:
            setGroups([PhotoGroup(name: L10n.t("unsorted"), itemIDs: list.map(\.id))])
        case .place:
            busy = L10n.t("step.geocode", 0, 0)
            progress = 0
            work = Task {
                let groups = await Grouping.byPlace(list, lookup: AppleGeocoder()) { d, t in
                    Task { @MainActor in
                        self.busy = L10n.t("step.geocode", d, t)
                        self.progress = Double(d) / Double(max(t, 1))
                    }
                }
                setGroups(groups)
                busy = nil; progress = nil
            }
        }
        groupedFor = (mode, items.count)
    }

    private func setGroups(_ g: [PhotoGroup]) {
        groups = g
        selectedGroup = firstLeaf(g)?.id
        if styleAuto { autoStyle() }
    }

    func runAISort() {
        guard let pi, aiReady else { error = L10n.t("sort.ai.need"); return }
        let themes = aiThemes.split(whereSeparator: { ",，、\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let list = items
        let ai = makeAI(pi)
        busy = L10n.t("step.ai")
        progress = 0
        work = Task {
            do {
                let t = themes.isEmpty ? try await ai.proposeThemes(list) : themes
                let g = try await ai.assign(list, to: t) { d, total in
                    Task { @MainActor in self.progress = Double(d) / Double(max(total, 1)) }
                }
                setGroups(g)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            busy = nil; progress = nil
        }
    }

    func cancelWork() { work?.cancel(); busy = nil; progress = nil }

    nonisolated func makeAI(_ pi: PiClient) -> AIService {
        AIService(pi: pi) { item, px in
            if let url = item.fileURL { return ImageTools.aiThumbnail(url, maxPixel: px) }
            if let id = item.assetID { return await PhotosLibrary.thumbnailData(id, maxPixel: px) }
            return nil
        }
    }

    // 主題編輯

    func group(_ id: UUID?) -> PhotoGroup? {
        guard let id else { return nil }
        func find(_ list: [PhotoGroup]) -> PhotoGroup? {
            for g in list { if g.id == id { return g }; if let c = find(g.children) { return c } }
            return nil
        }
        return find(groups)
    }

    func firstLeaf(_ list: [PhotoGroup]) -> PhotoGroup? {
        for g in list { if g.children.isEmpty { return g }; if let c = firstLeaf(g.children) { return c } }
        return nil
    }

    private func edit(_ id: UUID, _ change: (inout PhotoGroup) -> Void) {
        func walk(_ list: inout [PhotoGroup]) -> Bool {
            for i in list.indices {
                if list[i].id == id { change(&list[i]); return true }
                if walk(&list[i].children) { return true }
            }
            return false
        }
        _ = walk(&groups)
    }

    private func removing(_ ids: Set<String>, from g: PhotoGroup) -> PhotoGroup {
        var g = g
        g.itemIDs.removeAll { ids.contains($0) }
        g.children = g.children.map { removing(ids, from: $0) }
        return g
    }

    func rename(_ id: UUID, to name: String) { edit(id) { $0.name = name } }

    func move(_ ids: [String], to target: UUID) {
        let set = Set(ids)
        groups = groups.map { removing(set, from: $0) }
        edit(target) { $0.itemIDs.append(contentsOf: ids.filter { !$0.isEmpty }) }
        selection = []
    }

    func addGroup() {
        let g = PhotoGroup(name: L10n.t("group", groups.count + 1))
        groups.append(g)
        selectedGroup = g.id
    }

    func deleteGroup(_ id: UUID) {
        guard let g = group(id) else { return }
        let orphans = g.allItemIDs
        func drop(_ list: [PhotoGroup]) -> [PhotoGroup] {
            list.filter { $0.id != id }.map { var c = $0; c.children = drop(c.children); return c }
        }
        groups = drop(groups)
        if !orphans.isEmpty {
            let unsorted = L10n.t("unsorted")
            if let idx = groups.firstIndex(where: { $0.name == unsorted }) {
                groups[idx].itemIDs.append(contentsOf: orphans)
            } else {
                groups.append(PhotoGroup(name: unsorted, itemIDs: orphans))
            }
        }
        if selectedGroup == id { selectedGroup = firstLeaf(groups)?.id }
    }

    /// 樹狀主題攤平成清單（畫面左邊用），帶縮排層級
    var flatGroups: [(PhotoGroup, Int)] {
        var out: [(PhotoGroup, Int)] = []
        func walk(_ list: [PhotoGroup], _ depth: Int) { for g in list { out.append((g, depth)); walk(g.children, depth + 1) } }
        walk(groups, 0)
        return out
    }

    // MARK: 設定

    func autoStyle() {
        if let p = StyleLibrary.best(forCountry: Grouping.dominantCountry(groups), in: styles) { styleID = p.id }
    }

    func aiNaming() {
        guard let pi, aiReady else { error = L10n.t("sort.ai.need"); return }
        let ai = makeAI(pi)
        let snapshot = groups, byID = itemsByID
        busy = L10n.t("theme.aiWorking")
        work = Task {
            do {
                let naming = try await ai.nameGroups(snapshot, items: byID)
                for (id, name) in naming.names { rename(id, to: name) }
                if !naming.title.isEmpty { title = naming.title }
                if !naming.subtitle.isEmpty { subtitle = naming.subtitle }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            busy = nil
        }
    }

    // MARK: 製作

    func make() {
        let style = styles.first { $0.id == styleID }
        var spec = DeckSpec(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            subtitle: subtitle.isEmpty ? L10n.t("subtitle.default") : subtitle,
                            parentFolder: saveFolder, groups: groups.filter { $0.count > 0 }, items: itemsByID, style: style)
        spec.music = music
        spec.qrImage = qrImage
        spec.qrHandle = qrHandle
        step = .make
        resultDeck = nil
        busy = L10n.t("make.working")
        progress = 0
        work = Task {
            do {
                let deck = try await DeckMaker.make(spec, exporter: { item, folder in
                    try await PhotosLibrary.export(item, to: folder)
                }) { p in
                    Task { @MainActor in self.busy = p.message; self.progress = p.fraction }
                }
                resultDeck = deck
            } catch is CancellationError {
                step = .theme
            } catch {
                self.error = error.localizedDescription
                step = .theme
            }
            busy = nil; progress = nil
        }
    }

    func openDeck() {
        guard let deck = resultDeck else { return }
        let html = deck.appendingPathComponent(DeckMaker.htmlName)
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        if FileManager.default.fileExists(atPath: chrome.path) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.createsNewApplicationInstance = true
            let profile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WanderDeck-Chrome").path
            cfg.arguments = ["--user-data-dir=\(profile)", "--autoplay-policy=no-user-gesture-required",
                             "--no-first-run", "--no-default-browser-check", "--start-fullscreen", html.absoluteString]
            NSWorkspace.shared.openApplication(at: chrome, configuration: cfg)
        } else {
            NSWorkspace.shared.open(html)
        }
    }

    func revealDeck() {
        if let deck = resultDeck { NSWorkspace.shared.activateFileViewerSelecting([deck]) }
    }

    func startOver() {
        clearAll()
        title = ""; subtitle = ""; music = nil; qrImage = nil; qrHandle = ""; resultDeck = nil
        step = .pick
    }

    // MARK: 風格包

    func importStyle(_ url: URL) {
        do {
            let p = try StyleLibrary.importPack(url)
            styles = StyleLibrary.all()
            notice = L10n.t("settings.imported", p.name)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportStyle(_ pack: StylePack, to url: URL) {
        do { try StyleLibrary.export(pack, to: url) } catch { self.error = error.localizedDescription }
    }
}
