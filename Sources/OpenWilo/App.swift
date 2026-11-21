import OpenWiloCore
import SwiftUI

@main
struct OpenWiloApp: App {
    @StateObject private var workspace = Workspace()

    var body: some Scene {
        Window("OpenWilo", id: "workspace") {
            Dashboard(workspace: workspace)
                .environment(\.locale, L10n.locale)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("打开会话…"), action: workspace.openSession)
                    .keyboardShortcut("o")
                    .disabled(workspace.busy || workspace.continuous)
                Button(L10n.text("保存会话…"), action: workspace.saveSession)
                    .keyboardShortcut("s")
                    .disabled(workspace.networks.isEmpty)
            }
        }
    }
}
