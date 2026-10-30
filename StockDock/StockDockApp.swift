import SwiftUI

@main
struct StockDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if MCPServer.requested { StockDockTools.server().run() }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
