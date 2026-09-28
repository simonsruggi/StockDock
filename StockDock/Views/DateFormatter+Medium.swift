import Foundation

extension DateFormatter {
    /// Medium date style ("12 Mar 2026"), shared by the holding views.
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}
