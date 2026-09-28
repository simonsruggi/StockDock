import SwiftUI

/// One custom watchlist row: hover tint, click-to-open, right-click actions.
struct WatchRowView<Menu: View>: View {
    let row: WatchlistWideView.WatchRow
    let showExtended: Bool
    let extendedSession: Bool
    let percentDecimals: Int
    let valueDecimals: Int
    let onOpen: () -> Void
    @ViewBuilder let menu: () -> Menu
    @State private var hover = false

    /// What the Name column shows: the company name, prefixed with the real
    /// ticker when the user renamed the symbol.
    private var nameColumn: String {
        let base = row.name.isEmpty ? "—" : row.name
        return row.alias.isEmpty ? base : "\(row.symbol) · \(base)"
    }

    /// Price decimals honoring the manual override (Auto = smart per #10).
    private func priceDec(_ price: Double) -> Int {
        valueDecimals >= 0 ? valueDecimals : StorageService.priceDecimals(symbol: row.symbol, price: price)
    }

    /// A price stacked over its own % move (same baseline, so they always agree).
    /// `emphasised` = the live session: the price goes ink-dark and the % becomes
    /// a coloured pill. Otherwise both dim so the active session reads first.
    @ViewBuilder
    private func pairedCell(price: Double, pct: Double?, label: String?, emphasised: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(StorageService.currencySymbol(for: row.currency))\(StorageService.formatNumber(price, decimals: priceDec(price)))")
                .font(DS.figure)
                .foregroundStyle(emphasised ? DS.ink : DS.inkTertiary)
                .contentTransition(.numericText())
            if let pct {
                HStack(spacing: 4) {
                    if let label, !label.isEmpty {
                        Text(LocalizedStringKey(label)).font(DS.micro).foregroundStyle(DS.inkTertiary)
                    }
                    if emphasised {
                        ChangePill(value: pct, text: String(format: "%+.\(percentDecimals)f%%", pct))
                    } else {
                        Text(String(format: "%+.\(percentDecimals)f%%", pct))
                            .font(DS.micro).foregroundStyle(DS.pnlColor(pct).opacity(0.55))
                    }
                }
            }
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: WCol.spacing) {
                // Symbol + chip
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.brand.opacity(0.10))
                        .frame(width: 28, height: 28)
                        .overlay(Text(row.symbol.prefix(2))
                            .font(.inter(9.5, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(DS.brand))
                    Text(row.alias.isEmpty ? row.symbol : row.alias)
                        .font(DS.figure).foregroundStyle(DS.ink).lineLimit(1)
                }
                .frame(width: WCol.symbol, alignment: .leading)

                // Name — prefixed with the real ticker when a custom name is set,
                // so renaming never hides what the row actually tracks.
                Text(nameColumn)
                    .font(DS.body).foregroundStyle(DS.inkSecondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Regular price + today's % move. Emphasised when the regular
                // session is the live one; dims to context during extended hours.
                Group {
                    if row.loaded {
                        pairedCell(price: row.price, pct: row.changePercent,
                                   label: nil, emphasised: !extendedSession)
                    } else {
                        DSSpinner(size: 12)
                    }
                }
                .frame(width: WCol.price, alignment: .trailing)

                // After-hours price + its pre/post % move. Only shown when the
                // Extended Hours setting is on; emphasised during extended hours
                // so the live move reads first.
                if showExtended {
                    Group {
                        if let ext = row.extPrice {
                            pairedCell(price: ext, pct: row.extChangePercent,
                                       label: row.extLabel, emphasised: extendedSession)
                        } else {
                            Text("—").font(DS.figure).foregroundStyle(DS.inkTertiary)
                        }
                    }
                    .frame(width: WCol.ext, alignment: .trailing)
                }

                // Trend sparkline
                Sparkline(symbol: row.symbol).frame(width: WCol.trend)

                // 52-week range
                Group {
                    if let q = row.quote, let pos = q.fiftyTwoWeekPosition {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.cardAlt).frame(height: 5)
                                Circle().fill(.white)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().strokeBorder(DS.brand, lineWidth: 1.5))
                                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 0.5)
                                    .offset(x: CGFloat(pos) * (geo.size.width - 9))
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 12)
                    } else {
                        Text("—").foregroundStyle(DS.inkTertiary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: WCol.range)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(hover ? DS.cardAlt.opacity(0.6) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu { menu() }
    }
}
