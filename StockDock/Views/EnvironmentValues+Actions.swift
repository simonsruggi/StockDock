import SwiftUI

// Environment keys for navigation from child views
struct AddHoldingAction {
    let perform: (UUID) -> Void
}

struct EditHoldingAction {
    let perform: (UUID, Holding) -> Void
}

private struct AddHoldingActionKey: EnvironmentKey {
    static let defaultValue = AddHoldingAction { _ in }
}

private struct EditHoldingActionKey: EnvironmentKey {
    static let defaultValue = EditHoldingAction { _, _ in }
}

/// Injected by AppDelegate so the popover opens the desktop window by calling
/// AppDelegate directly — no fragile `NSApp.delegate as? AppDelegate` cast that
/// can silently fail in a SwiftUI app.
private struct OpenWindowActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {
        NSLog("[StockDock] Open tapped but no openWindowAction was injected")
    }
}

/// The per-portfolio actions (same as the sidebar right-click menu), injected by
/// AppDelegate/PortfolioWindowView so the Overview header can offer them too.
struct PortfolioActions {
    var addHolding: (UUID) -> Void = { _ in }
    var rename: (UUID, String) -> Void = { _, _ in }
    var notifications: (UUID, String) -> Void = { _, _ in }
    var export: (Portfolio) -> Void = { _ in }
    var delete: (UUID) -> Void = { _ in }
}

private struct PortfolioActionsKey: EnvironmentKey {
    static let defaultValue = PortfolioActions()
}

extension EnvironmentValues {
    var addHoldingAction: AddHoldingAction {
        get { self[AddHoldingActionKey.self] }
        set { self[AddHoldingActionKey.self] = newValue }
    }
    var editHoldingAction: EditHoldingAction {
        get { self[EditHoldingActionKey.self] }
        set { self[EditHoldingActionKey.self] = newValue }
    }
    var openWindowAction: () -> Void {
        get { self[OpenWindowActionKey.self] }
        set { self[OpenWindowActionKey.self] = newValue }
    }
    var portfolioActions: PortfolioActions {
        get { self[PortfolioActionsKey.self] }
        set { self[PortfolioActionsKey.self] = newValue }
    }
}
