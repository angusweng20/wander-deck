import AppKit
import SwiftUI
import WanderCore

/// 開發測試用：設了環境變數 WANDER_SNAPSHOT_DIR 才會啟動，一般使用者不會碰到。
/// 每 2 秒把 App 自己的視窗畫成 PNG（不需要螢幕錄影權限），讓 AI 檢查畫面。
/// WANDER_DEMO=<照片資料夾> 會自動載入照片；WANDER_DEMO_STEP=sort|theme|make 直接跳到那一步。
enum DebugSnapshots {
    @MainActor static func startIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["WANDER_SNAPSHOT_DIR"] else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                for (i, w) in NSApp.windows.enumerated() where w.isVisible {
                    guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("window\(i).png"))
                }
            }
        }
    }

    @MainActor static func attach(_ model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        if env["WANDER_SNAPSHOT_DIR"] != nil, let demo = env["WANDER_DEMO"] {
            model.step = .pick
            model.addFiles([URL(fileURLWithPath: demo)])
            if let step = env["WANDER_DEMO_STEP"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    switch step {
                    case "sort", "theme", "make":
                        model.step = .sort
                        model.enterSort()
                        if step != "sort" {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                                model.step = .theme
                                if step == "make" {
                                    model.title = "測試簡報"
                                    if let out = env["WANDER_DEMO_OUT"] { model.saveFolder = URL(fileURLWithPath: out) }
                                    model.make()
                                }
                            }
                        }
                    default: break
                    }
                }
            }
        }
    }
}
