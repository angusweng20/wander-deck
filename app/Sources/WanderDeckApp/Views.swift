import AppKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import WanderCore

extension Color {
    /// 水彩風格的藍灰色
    static let brand = Color(red: 0.23, green: 0.42, blue: 0.60)
}

// MARK: 整個視窗

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.step != .welcome { StepHeader().padding(.vertical, 12) ; Divider() }
            if let up = model.update {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text(L10n.t("update.available", up.version))
                    Button(L10n.t("update.get")) { NSWorkspace.shared.open(up.url) }
                }
                .font(.callout).padding(6).frame(maxWidth: .infinity).background(Color.brand.opacity(0.12))
            }
            Group {
                switch model.step {
                case .welcome: WelcomeView()
                case .pick: PickView()
                case .sort: SortView()
                case .theme: ThemeView()
                case .make: MakeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay { if let busy = model.busy, model.step != .make { BusyOverlay(message: busy, progress: model.progress) } }
        .alert(L10n.t("error.title"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .frame(minWidth: 960, minHeight: 660)
        .id(model.language)
        .onAppear { DebugSnapshots.attach(model) }
        .tint(Color.brand)
    }
}

struct StepHeader: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 18) {
            ForEach([Step.pick, .sort, .theme, .make], id: \.self) { s in
                let n = s.rawValue
                HStack(spacing: 6) {
                    Text("\(n)").font(.caption.bold()).frame(width: 20, height: 20)
                        .background(Circle().fill(model.step.rawValue >= n ? Color.brand : Color.secondary.opacity(0.25)))
                        .foregroundStyle(model.step.rawValue >= n ? .white : .secondary)
                    Text(L10n.t("step.\(n)")).foregroundStyle(model.step == s ? .primary : .secondary)
                }
                if s != .make { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }
}

struct BusyOverlay: View {
    let message: String
    let progress: Double?
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                if let progress { ProgressView(value: progress).frame(width: 260) } else { ProgressView() }
                Text(message)
                Button(L10n.t("btn.cancel")) { model.cancelWork() }
            }
            .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct BottomBar<Trailing: View>: View {
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            if let back { Button(L10n.t("btn.back"), action: back) }
            Spacer()
            trailing
        }
        .padding(14)
        .background(.bar)
    }
}

// MARK: 歡迎＋登入

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "photo.stack").font(.system(size: 54)).foregroundStyle(Color.brand)
            Text(L10n.t("app.name")).font(.system(size: 40, weight: .semibold, design: .serif))
            Text(L10n.t("app.tagline")).font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.t("welcome.ai.title"), systemImage: "sparkles").font(.headline)
                Text(L10n.t("welcome.ai.body")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    switch model.login {
                    case .checking: ProgressView().controlSize(.small); Text(L10n.t("welcome.checking"))
                    case .signingIn:
                        ProgressView().controlSize(.small); Text(L10n.t("welcome.signingIn"))
                    case .signedIn(let shared):
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text(L10n.t(shared ? "welcome.signedInShared" : "welcome.signedIn"))
                    case .signedOut:
                        Button { model.signIn() } label: { Label(L10n.t("welcome.signin"), systemImage: "person.crop.circle") }
                            .controlSize(.large)
                    case .noPi:
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(L10n.t("welcome.noPi"))
                    case .piBlocked:
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(L10n.t("welcome.piBlocked")).fixedSize(horizontal: false, vertical: true)
                        Button(L10n.t("welcome.retry")) { Task { await model.refreshLogin() } }
                    }
                }
            }
            .padding(18).frame(maxWidth: 560, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 14) {
                Button {
                    model.step = .pick
                } label: { Text(L10n.t("btn.start")).frame(minWidth: 140) }
                    .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                if case .signedOut = model.login {
                    Button(L10n.t("welcome.skip")) { model.useAI = false; model.step = .pick }.buttonStyle(.link)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                Text(L10n.t("welcome.privacy"))
                Text(L10n.t("welcome.gatekeeper"))
            }
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 620)
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 30)
    }
}

// MARK: 挑照片

struct PickView: View {
    @EnvironmentObject var model: AppModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(L10n.t("pick.title")).font(.title2.weight(.semibold))
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: nil, selectionBehavior: .ordered,
                                 matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                        Label(L10n.t("pick.photos"), systemImage: "photo.on.rectangle.angled")
                    }
                    .controlSize(.large).buttonStyle(.borderedProminent)
                    Button { chooseFolder() } label: { Label(L10n.t("pick.folder"), systemImage: "folder") }
                        .controlSize(.large)
                }
                Text(L10n.t("pick.drop")).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 18)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                    ForEach(model.items) { item in
                        Thumbnail(item: item)
                            .contextMenu { Button(L10n.t("pick.remove")) { model.remove([item.id]) } }
                    }
                }
                .padding(16)
            }
            .background(targeted ? Color.brand.opacity(0.08) : Color.clear)
            .dropDestination(for: URL.self) { urls, _ in model.addFiles(urls); return true } isTargeted: { targeted = $0 }

            BottomBar(back: { model.step = .welcome }) {
                Text(L10n.t("pick.count", model.photoCount, model.videoCount)).foregroundStyle(.secondary)
                if !model.items.isEmpty { Button(L10n.t("pick.clear")) { model.clearAll() } }
                Button(L10n.t("btn.next")) { model.step = .sort; model.enterSort() }
                    .buttonStyle(.borderedProminent).disabled(model.items.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: pickerItems) { _, new in
            let ids = new.compactMap(\.itemIdentifier)
            pickerItems = []
            model.addFromPhotos(ids)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .movie, .folder]
        if panel.runModal() == .OK { model.addFiles(panel.urls) }
    }
}

// MARK: 分類

struct SortView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("", selection: $model.mode) {
                    ForEach(SortMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 520).labelsHidden()
                .onChange(of: model.mode) { _, _ in model.regroup() }
                Text(model.mode.help).font(.callout).foregroundStyle(.secondary)
                if model.mode == .ai {
                    HStack {
                        TextField(L10n.t("sort.ai.placeholder"), text: $model.aiThemes).frame(maxWidth: 380)
                        Button(L10n.t("sort.ai.run")) { model.runAISort() }.disabled(!model.aiReady)
                    }
                    if !model.aiReady { Text(L10n.t("sort.ai.need")).font(.caption).foregroundStyle(.orange) }
                }
            }
            .padding(14)
            Divider()
            HSplitView {
                GroupList().frame(minWidth: 230, idealWidth: 260, maxWidth: 360)
                GroupPhotos().frame(minWidth: 420)
            }
            BottomBar(back: { model.step = .pick }) {
                Button(L10n.t("btn.next")) { model.step = .theme }
                    .buttonStyle(.borderedProminent).disabled(model.groups.allSatisfy { $0.count == 0 })
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct GroupList: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedGroup) {
                ForEach(model.flatGroups, id: \.0.id) { pair in
                    GroupRow(group: pair.0, depth: pair.1).tag(pair.0.id)
                }
            }
            HStack {
                Button { model.addGroup() } label: { Label(L10n.t("sort.newGroup"), systemImage: "plus") }
                Spacer()
                if let id = model.selectedGroup {
                    Button { model.deleteGroup(id) } label: { Image(systemName: "trash") }.help(L10n.t("sort.deleteGroup"))
                }
            }
            .buttonStyle(.borderless).padding(8)
        }
    }
}

struct GroupRow: View {
    @EnvironmentObject var model: AppModel
    let group: PhotoGroup
    let depth: Int
    @State private var name = ""
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.children.isEmpty ? "folder" : "folder.fill").foregroundStyle(.secondary)
            TextField("", text: $name, onCommit: { model.rename(group.id, to: name) })
                .textFieldStyle(.plain)
                .onAppear { name = group.name }
                .onChange(of: group.name) { _, n in name = n }
                .onChange(of: name) { _, n in model.rename(group.id, to: n) }
            Spacer()
            Text("\(group.count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.vertical, 2)
        .background(targeted ? Color.brand.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .dropDestination(for: String.self) { ids, _ in
            let moving = ids.contains(where: model.selection.contains) ? Array(model.selection) : ids
            model.move(moving, to: group.id)
            return true
        } isTargeted: { targeted = $0 }
    }
}

struct GroupPhotos: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let g = model.group(model.selectedGroup)
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("sort.dragHint")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !model.selection.isEmpty {
                    Text(L10n.t("sort.selected", model.selection.count)).font(.caption)
                    Button(L10n.t("sort.deselect")) { model.selection = [] }
                } else if let g, !g.itemIDs.isEmpty {
                    Button(L10n.t("sort.select")) { model.selection = Set(g.itemIDs) }
                }
            }
            .buttonStyle(.borderless).padding(.horizontal, 14).padding(.vertical, 8)
            ScrollView {
                if let g, g.itemIDs.isEmpty, !g.children.isEmpty {
                    Text(L10n.t("sort.empty")).foregroundStyle(.secondary).padding(40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                    ForEach(g?.itemIDs ?? [], id: \.self) { id in
                        if let item = model.itemsByID[id] {
                            Thumbnail(item: item, selected: model.selection.contains(id))
                                .onTapGesture {
                                    if model.selection.contains(id) { model.selection.remove(id) } else { model.selection.insert(id) }
                                }
                                .draggable(id)
                                .contextMenu {
                                    Menu(L10n.t("sort.moveTo")) {
                                        ForEach(model.flatGroups.filter { $0.0.id != g?.id }, id: \.0.id) { pair in
                                            Button(String(repeating: "  ", count: pair.1) + pair.0.name) {
                                                let ids = model.selection.contains(id) ? Array(model.selection) : [id]
                                                model.move(ids, to: pair.0.id)
                                            }
                                        }
                                    }
                                    Button(L10n.t("pick.remove")) { model.remove([id]) }
                                }
                        }
                    }
                }
                .padding(14)
            }
        }
    }
}

// MARK: 設定

struct ThemeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L10n.t("theme.title")).font(.title2.weight(.semibold))
                    Form {
                        TextField(L10n.t("theme.deckTitle"), text: $model.title, prompt: Text(L10n.t("deck.title.default")))
                        TextField(L10n.t("theme.subtitle"), text: $model.subtitle, prompt: Text(L10n.t("subtitle.default")))
                    }
                    Button { model.aiNaming() } label: { Label(L10n.t("theme.ai"), systemImage: "sparkles") }
                        .disabled(!model.aiReady)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("theme.topics")).font(.headline)
                        ForEach(model.flatGroups, id: \.0.id) { pair in
                            TopicNameField(group: pair.0, depth: pair.1)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t("theme.style")).font(.headline)
                        Toggle(L10n.t("theme.styleAuto"), isOn: $model.styleAuto)
                            .onChange(of: model.styleAuto) { _, on in if on { model.autoStyle() } }
                        ScrollView(.horizontal) {
                            HStack(spacing: 14) {
                                ForEach(model.styles) { s in
                                    StyleCard(style: s, selected: s.id == model.styleID)
                                        .onTapGesture { model.styleID = s.id; model.styleAuto = false }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t("theme.music")).font(.headline)
                        FilePickRow(url: $model.music, button: L10n.t("theme.music.pick"), types: [.audio, .mp3, .mpeg4Audio])
                        Text(L10n.t("theme.qr")).font(.headline).padding(.top, 6)
                        FilePickRow(url: $model.qrImage, button: L10n.t("theme.qr.pick"), types: [.png, .jpeg, .image])
                        if model.qrImage != nil {
                            TextField(L10n.t("theme.qr.handle"), text: $model.qrHandle).frame(maxWidth: 360)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("theme.save")).font(.headline)
                        HStack {
                            Text(model.saveFolder.path).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Button(L10n.t("theme.change")) {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let u = panel.url { model.saveFolder = u }
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            BottomBar(back: { model.step = .sort }) {
                Button(L10n.t("theme.make")) { model.make() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct TopicNameField: View {
    @EnvironmentObject var model: AppModel
    let group: PhotoGroup
    let depth: Int
    @State private var name = ""
    var body: some View {
        HStack {
            TextField("", text: $name).frame(maxWidth: 320)
                .onAppear { name = group.name }
                .onChange(of: group.name) { _, n in name = n }
                .onChange(of: name) { _, n in model.rename(group.id, to: n) }
            Text("\(group.count)").foregroundStyle(.secondary).font(.caption)
        }
        .padding(.leading, CGFloat(depth) * 20)
    }
}

struct StyleCard: View {
    let style: StylePack
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Rectangle().fill(Color.secondary.opacity(0.1))
                if let p = style.preview, let img = NSImage(contentsOf: p) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 124).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(style.name).font(.headline)
            Text(style.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                .frame(width: 220, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.brand : .clear, lineWidth: 3))
        .contentShape(Rectangle())
    }
}

struct FilePickRow: View {
    @Binding var url: URL?
    let button: String
    let types: [UTType]
    var body: some View {
        HStack {
            Button(button) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = types
                if panel.runModal() == .OK { url = panel.url }
            }
            if let url {
                Text(url.lastPathComponent).foregroundStyle(.secondary)
                Button { self.url = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
            } else {
                Text(L10n.t("theme.none")).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: 製作

struct MakeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if let deck = model.resultDeck {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text(L10n.t("make.done")).font(.title.weight(.semibold))
                Text(deck.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                HStack(spacing: 12) {
                    Button { model.openDeck() } label: { Label(L10n.t("make.open"), systemImage: "play.rectangle") }
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    Button { model.revealDeck() } label: { Label(L10n.t("make.reveal"), systemImage: "folder") }
                        .controlSize(.large)
                }
                Text(L10n.t("make.tip")).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: 520)
                    .multilineTextAlignment(.center)
                Button(L10n.t("make.again")) { model.startOver() }.buttonStyle(.link)
            } else {
                ProgressView(value: model.progress ?? 0).frame(width: 360)
                Text(model.busy ?? L10n.t("make.working"))
                Button(L10n.t("btn.cancel")) { model.cancelWork() }
            }
            Spacer()
        }
        .padding(30)
    }
}

// MARK: 設定視窗

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section(L10n.t("settings.language")) {
                Picker(L10n.t("settings.language"), selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
                    Text(L10n.t("settings.system")).tag("system")
                    Text("繁體中文").tag("zh")
                    Text("English").tag("en")
                }
                Text(L10n.t("settings.languageNote")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.t("settings.account")) {
                HStack {
                    switch model.login {
                    case .signedIn(let shared): Text(L10n.t(shared ? "welcome.signedInShared" : "welcome.signedIn"))
                    case .noPi: Text(L10n.t("welcome.noPi"))
                    case .piBlocked: Text(L10n.t("welcome.piBlocked"))
                    default: Text(L10n.t("err.notLoggedIn"))
                    }
                    Spacer()
                    if case .signedIn(false) = model.login { Button(L10n.t("settings.signout")) { model.signOut() } }
                    if case .signedOut = model.login { Button(L10n.t("welcome.signin")) { model.signIn() } }
                }
            }
            Section(L10n.t("settings.styles")) {
                ForEach(model.styles) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.name)
                            Text("\(s.id) \(s.version) · \(s.license) · \(s.author)\(s.isBuiltIn ? " · " + L10n.t("settings.builtIn") : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.t("settings.export")) {
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = "\(s.id)-\(s.version).wdstyle"
                            if panel.runModal() == .OK, let u = panel.url { model.exportStyle(s, to: u) }
                        }
                    }
                }
                HStack {
                    Button(L10n.t("settings.import")) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [UTType(filenameExtension: "wdstyle") ?? .zip, .zip]
                        if panel.runModal() == .OK, let u = panel.url { model.importStyle(u) }
                    }
                    Button(L10n.t("settings.openFolder")) { NSWorkspace.shared.open(Paths.userStyles) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
    }
}
