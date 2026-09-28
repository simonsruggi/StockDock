import SwiftUI

/// Shared column widths so the header lines up with every row.
/// File-scope `private` = visible to both `WatchlistWideView` and `WatchRowView`.
enum WCol {
    static let symbol: CGFloat = 128
    static let price: CGFloat = 104
    static let ext: CGFloat = 116
    static let trend: CGFloat = 56
    static let range: CGFloat = 100
    static let spacing: CGFloat = 12
}
