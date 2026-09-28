import SwiftUI

struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: title == nil ? 0 : 14) {
            if let title { SectionLabel(title) }
            content
        }
        .padding(DS.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard()
    }
}
