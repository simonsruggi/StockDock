import SwiftUI

/// A labelled field block: uppercase DS label above a control.
struct FieldBlock<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            content
        }
    }
}
