import SwiftUI

/// Shared page header: big Inter title + optional caption + trailing actions.
struct PageHeader<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var trailing: Trailing

    init(_ title: String, caption: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.caption = caption
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(DS.titleXL).tracking(-0.3).foregroundStyle(DS.ink)
                if let caption {
                    Text(LocalizedStringKey(caption)).font(DS.caption).foregroundStyle(DS.inkTertiary)
                }
            }
            Spacer()
            trailing
        }
    }
}
