import SwiftUI

/// Results grouped by section; the keyboard selection scrolls into view and
/// hovering moves it, so mouse and keyboard never disagree.
struct SearchResultsList: View {
    @ObservedObject var model: UniversalSearchModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(SearchItem.Section.allCases, id: \.self) { section in
                        let rows = model.items.enumerated().filter { $0.element.section == section }
                        if !rows.isEmpty {
                            SettingSubheader(section.title)
                                .padding(.horizontal, 8)
                            ForEach(rows, id: \.element.id) { index, item in
                                SearchResultRow(item: item, selected: index == model.selectedIndex) {
                                    model.activate(item)
                                }
                                .id(item.id)
                                .onHover { if $0 { model.selectedIndex = index } }
                            }
                        }
                    }
                    if model.items.isEmpty && !model.isSearchingMarket {
                        emptyState
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selectedIndex) { _, _ in
                if let id = model.selected?.id { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(DS.inkTertiary)
            Text("No results").font(DS.bodyStrong).foregroundStyle(DS.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
