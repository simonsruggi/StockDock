import AppKit
import UniformTypeIdentifiers

/// Shared NSSavePanel/NSOpenPanel plumbing for portfolio export/import,
/// used by both `PortfolioListView` (menu-bar popover) and `PortfolioWindowView`
/// (full desktop window). The actual JSON encode/decode/merge logic lives in
/// `StorageService`; this only owns the panel configuration and presentation.
@MainActor
enum PortfolioIO {

    /// Presents an NSSavePanel and writes the exported JSON on confirm.
    ///
    /// - Parameter restoreActivationPolicy: when true, temporarily flips the app
    ///   to `.regular` so the panel can come to the front of a menu-bar
    ///   (accessory) app, then restores `.accessory` shortly after the panel
    ///   closes. Pass false when the caller's window already keeps the app
    ///   `.regular` for its own lifetime (e.g. the desktop portfolio window),
    ///   so this helper doesn't prematurely drop the app back to accessory
    ///   while that window is still open.
    static func exportAll(_ portfolios: [Portfolio], storageService: StorageService, restoreActivationPolicy: Bool) {
        guard let data = storageService.exportPortfolios(portfolios) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let name = portfolios.count == 1 ? portfolios[0].name : "StockDock Portfolios"
        panel.nameFieldStringValue = "\(name).json"
        panel.title = "Export Portfolios"
        if restoreActivationPolicy {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.begin { response in
            if restoreActivationPolicy {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Presents an NSOpenPanel and decodes the chosen file. The portfolios go to
    /// `onLoaded`, where the caller lets the user pick which ones to import;
    /// read/format errors go to `onAlert`.
    ///
    /// - Parameter fromPopover: the menu-bar popover stays open (and the app
    ///   stays menu-bar only, no Dock icon) while the panel floats above it, so
    ///   the selection sheet that follows appears in the popover itself.
    static func pickImportFile(_ storageService: StorageService, fromPopover: Bool,
                               onLoaded: @escaping ([Portfolio]) -> Void,
                               onAlert: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import Portfolios"
        let appDelegate = NSApp.delegate as? AppDelegate
        if fromPopover {
            appDelegate?.holdPopoverOpen(true)
            panel.level = .floating
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.begin { response in
            if fromPopover { appDelegate?.holdPopoverOpen(false) }
            guard response == .OK, let url = panel.url else { return }
            let data = try? Data(contentsOf: url)
            Task { @MainActor in
                if fromPopover {
                    appDelegate?.showPopoverIfHidden()
                    // Let the popover finish appearing before a sheet or alert attaches to it.
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                guard let data else {
                    onAlert("Could not read file.")
                    return
                }
                guard let imported = storageService.importPortfolios(from: data) else {
                    onAlert("Invalid file format.")
                    return
                }
                if imported.isEmpty {
                    onAlert("No portfolios found in file.")
                    return
                }
                onLoaded(imported)
            }
        }
        if fromPopover { panel.orderFrontRegardless() }
    }

    static func importedMessage(_ count: Int) -> String {
        "Imported \(count) portfolio\(count == 1 ? "" : "s")."
    }
}

/// The portfolios read from an import file, waiting for the user's selection.
struct ImportCandidates: Identifiable {
    let id = UUID()
    let portfolios: [Portfolio]
}
