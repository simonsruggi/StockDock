import Foundation
import Sparkle

final class UpdaterViewModel: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    private let sparkleDelegate = SparkleDelegate()
    private var frequentCheck: Timer?

    /// Sparkle won't schedule checks closer than an hour apart, so a release
    /// reaches running apps within 30 minutes through a background check of our own.
    private static let frequentCheckInterval: TimeInterval = 1800

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    var isAvailable: Bool {
        controller != nil
    }

    init() {
        // Never in MCP mode: a background server must not check for updates or show Sparkle's window.
        if Bundle.main.infoDictionary?["SUFeedURL"] != nil, !MCPServer.requested {
            let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: sparkleDelegate, userDriverDelegate: nil)
            self.controller = c
        } else {
            self.controller = nil
        }
        guard let updater = controller?.updater else { return }
        frequentCheck = Timer.scheduledTimer(withTimeInterval: Self.frequentCheckInterval, repeats: true) { _ in
            guard updater.automaticallyChecksForUpdates, updater.canCheckForUpdates, !updater.sessionInProgress else { return }
            updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}
