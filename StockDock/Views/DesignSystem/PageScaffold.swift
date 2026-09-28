import SwiftUI

/// The single page layout every tab uses, so title position, column width,
/// gutters and background are identical across the app: a fixed PageHeader in
/// the titlebar-clearance zone, then the page content in the shared column.
struct PageScaffold<Content: View, Trailing: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, caption: String? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title, caption: caption) { trailing }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.titlebarClearance - 8)
                .padding(.bottom, 16)
                .frame(maxWidth: DS.contentMaxWidth + DS.gutter * 2)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppBackground())
    }
}
