import SwiftUI
import AppKit

/// Design tokens for the StockDock desktop window — the "private banking" light
/// editorial system: warm paper ground, white card stock, one sober emerald,
/// generous whitespace, immaculate numeric typography. The window is pinned to
/// the light appearance; dark branches are kept only as a safety net for sheets
/// that may inherit the system appearance.
enum DS {
    // MARK: Surfaces
    /// Window/detail ground — warm paper.
    static let ground = dynamic(light: NSColor(red: 0.984, green: 0.980, blue: 0.969, alpha: 1),
                                dark: NSColor(white: 0.09, alpha: 1))
    /// Sidebar flat tint — a hair darker than the ground.
    static let sidebarBG = dynamic(light: NSColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1),
                                   dark: NSColor(white: 0.11, alpha: 1))
    /// Card stock.
    static let card = dynamic(light: .white, dark: NSColor(white: 0.13, alpha: 1))
    /// Inset wells, chart placeholders, thumbnails.
    static let cardAlt = dynamic(light: NSColor(red: 0.961, green: 0.949, blue: 0.925, alpha: 1),
                                 dark: NSColor(white: 0.17, alpha: 1))
    /// Borders and dividers — warm, near-invisible.
    static let hairline = Color(red: 0.102, green: 0.090, blue: 0.059).opacity(0.07)

    // MARK: Ink
    /// Warm near-black for display text.
    static let ink = dynamic(light: NSColor(red: 0.110, green: 0.102, blue: 0.082, alpha: 1),
                             dark: NSColor(white: 0.94, alpha: 1))
    /// Warm secondary gray (instead of the blue-ish system secondary).
    static let inkSecondary = Color(red: 0.431, green: 0.416, blue: 0.376)
    /// Captions, placeholders, timestamps.
    static let inkTertiary = Color(red: 0.608, green: 0.588, blue: 0.541)

    // MARK: Accents
    /// Brand emerald — selection, links, the mark.
    static let brand = Color(red: 0.110, green: 0.451, blue: 0.369)
    /// Gains — sober emerald.
    static let up = Color(red: 0.129, green: 0.522, blue: 0.400)
    /// Losses — muted terracotta.
    static let down = Color(red: 0.761, green: 0.290, blue: 0.267)
    static let upSoft = up.opacity(0.10)
    static let downSoft = down.opacity(0.10)
    /// The one reserved luxury accent: FEATURED label and concentration warnings.
    static let gold = Color(red: 0.722, green: 0.573, blue: 0.247)

    /// Categorical palette for allocation / series — muted, magazine-like.
    static let palette: [Color] = [
        Color(red: 0.13, green: 0.45, blue: 0.37),
        Color(red: 0.72, green: 0.58, blue: 0.36),
        Color(red: 0.35, green: 0.46, blue: 0.62),
        Color(red: 0.55, green: 0.42, blue: 0.55),
        Color(red: 0.76, green: 0.44, blue: 0.36),
        Color(red: 0.40, green: 0.58, blue: 0.55),
        Color(red: 0.62, green: 0.55, blue: 0.42),
        Color(red: 0.50, green: 0.52, blue: 0.56),
    ]

    static func pnlColor(_ v: Double) -> Color { v >= 0 ? up : down }

    // MARK: Type scale (Inter everywhere; tracking applied at call sites on ≥24pt)
    /// Hero value only. Pair with `.tracking(-0.5)`.
    static let display = Font.inter(44, weight: .bold, relativeTo: .largeTitle).monospacedDigit()
    /// Page titles, holding symbol. Pair with `.tracking(-0.3)`.
    static let titleXL = Font.inter(24, weight: .bold, relativeTo: .title)
    /// Card feature headlines.
    static let title = Font.inter(17, weight: .semibold, relativeTo: .title3)
    static let body = Font.inter(13, relativeTo: .body)
    static let bodyStrong = Font.inter(13, weight: .semibold, relativeTo: .body)
    /// Table numbers.
    static let figure = Font.inter(13, weight: .medium, relativeTo: .body).monospacedDigit()
    /// Stat tile values.
    static let figureLG = Font.inter(22, weight: .semibold, relativeTo: .title2).monospacedDigit()
    static let caption = Font.inter(11, relativeTo: .caption)
    /// Uppercase section labels. Pair with `.tracking(0.8)`.
    static let label = Font.inter(10.5, weight: .semibold, relativeTo: .caption2)
    /// Timestamps, chips — the smallest legible size in the app.
    static let micro = Font.inter(9.5, weight: .medium, relativeTo: .caption2)

    // MARK: Metrics
    /// Page gutter around detail content.
    static let gutter: CGFloat = 32
    /// Gap between cards.
    static let gap: CGFloat = 20
    /// Card internal padding.
    static let pad: CGFloat = 20
    /// Detail content max width.
    static let contentMaxWidth: CGFloat = 1120
    /// Clearance under the transparent titlebar (traffic lights).
    static let titlebarClearance: CGFloat = 52

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: .init(name: nil) { $0.isDarkMode ? dark : light })
    }
}

extension NSAppearance {
    fileprivate var isDarkMode: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// The window ground: warm paper with a whisper of brand emerald in one corner.
struct AppBackground: View {
    var body: some View {
        ZStack {
            DS.ground
            RadialGradient(colors: [DS.brand.opacity(0.045), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Elevation

extension View {
    /// The card surface with the app's 3-level elevation: E1 resting (soft dual
    /// shadow) or E2 lifted (`elevated: true`, for hover on clickable cards).
    /// Never add extra `.shadow` after this — it would blur the border overlay.
    func premiumCard(cornerRadius: CGFloat = 16, elevated: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(elevated ? 0.08 : 0.05),
                            radius: elevated ? 24 : 18, x: 0, y: elevated ? 10 : 8)
                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.18), value: elevated)
    }
}

// MARK: - Card

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

/// Uppercase, tracked, muted — the quiet label above a card's content.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(DS.label)
            .foregroundStyle(DS.inkSecondary)
            .tracking(0.8)
            .textCase(.uppercase)
    }
}

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

/// A top overlay that dissolves scrolled content under the transparent titlebar.
struct ScrollEdgeFade: View {
    var height: CGFloat = 64
    var body: some View {
        LinearGradient(colors: [Color(nsColor: .init(name: nil) { _ in
            NSColor(red: 0.984, green: 0.980, blue: 0.969, alpha: 1) }), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .allowsHitTesting(false)
    }
}

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

extension View {
    /// The shared content column: gutter padding, bottom padding, centered
    /// max-width. Apply to the root VStack inside a page's ScrollView.
    func pageColumn() -> some View {
        self
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, DS.gutter)
            .frame(maxWidth: DS.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let label: String
    let value: String
    var caption: String? = nil
    var captionTint: Color = DS.inkTertiary
    var valueTint: Color = DS.ink
    var help: String? = nil
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(label)
            Text(value)
                .font(DS.figureLG)
                .foregroundStyle(valueTint)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.45, dampingFraction: 0.9), value: value)
                .lineLimit(1).minimumScaleFactor(0.6)
            // Always reserve the caption line so every tile is the same height.
            Text(caption ?? " ")
                .font(.inter(10.5, relativeTo: .caption2).monospacedDigit())
                .foregroundStyle(captionTint)
                .opacity(caption == nil ? 0 : 1)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(cornerRadius: 12, elevated: hover)
        .scaleEffect(hover ? 1.012 : 1)
        .animation(.easeOut(duration: 0.16), value: hover)
        .onHover { hover = $0 }
        .help(help ?? label)
    }
}

// MARK: - Change pill

struct ChangePill: View {
    let value: Double
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text(text).font(.inter(11.5, weight: .semibold, relativeTo: .caption).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(DS.pnlColor(value))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(value >= 0 ? DS.upSoft : DS.downSoft))
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: text)
    }
}

/// Shared outline tag (SHORT, leverage, …) — 9.5pt, the app's smallest size.
struct Tag: View {
    let text: String
    var color: Color = DS.brand
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(DS.micro)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(color.opacity(0.45), lineWidth: 1))
    }
}

/// The StockDock brand mark: the official app icon (the one shipped in the last
/// release), used everywhere. Falls back to a designed emerald mark only if the
/// icon can't be loaded (should never happen in the bundled app).
struct BrandMark: View {
    var size: CGFloat = 28

    /// Loaded once from the app's bundled icon (works in dev and release).
    private static let appIcon: NSImage? = {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let sys = NSApp.applicationIconImage
        return (sys?.size.width ?? 0) > 0 ? sys : nil
    }()

    var body: some View {
        Group {
            if let icon = Self.appIcon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                fallbackMark
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }

    private var fallbackMark: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [DS.up, DS.brand, Color(red: 0.08, green: 0.33, blue: 0.30)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white))
    }
}

/// The app's segmented range picker (1M / 3M / 6M / …): a white pill sliding
/// inside a warm capsule, with real hit targets. Shared by every chart so
/// period switching looks and feels the same everywhere.
struct SegmentedRangePicker<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Namespace private var ns

    private func help(_ label: String) -> String {
        switch label {
        case "24H": return "Last 24 hours"
        case "7D": return "Last 7 days"
        case "1M": return "Last month"
        case "1Y": return "Last year"
        case "All": return "All available history"
        default: return label
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.inter(10, weight: .semibold, relativeTo: .caption2))
                        .foregroundStyle(selection == option ? DS.ink : DS.inkTertiary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background {
                            if selection == option {
                                Capsule().fill(DS.card)
                                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "segSelection", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(help(label(option)))
            }
        }
        .padding(3)
        .background(Capsule().fill(DS.cardAlt))
    }
}

/// A faint decorative market-curve stroked in hairline — used behind empty chart
/// states so the placeholder evokes the chart to come.
struct DecorativeCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0, y: h * 0.62))
        p.addCurve(to: CGPoint(x: w * 0.34, y: h * 0.48),
                   control1: CGPoint(x: w * 0.12, y: h * 0.70),
                   control2: CGPoint(x: w * 0.24, y: h * 0.38))
        p.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.55),
                   control1: CGPoint(x: w * 0.46, y: h * 0.60),
                   control2: CGPoint(x: w * 0.57, y: h * 0.66))
        p.addCurve(to: CGPoint(x: w, y: h * 0.30),
                   control1: CGPoint(x: w * 0.80, y: h * 0.42),
                   control2: CGPoint(x: w * 0.91, y: h * 0.34))
        return p
    }
}

/// Floating value tooltip shown when hovering a chart line.
struct ChartTooltip: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(DS.micro).foregroundStyle(DS.inkTertiary)
            Text(value).font(.inter(12, weight: .semibold, relativeTo: .body).monospacedDigit()).foregroundStyle(tint)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.card)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.hairline))
        .fixedSize()
    }
}

/// Nearest point (by date) to a target — for chart hover snapping.
func nearestByDate<T>(_ items: [T], to target: Date, date: (T) -> Date) -> T? {
    items.min { abs(date($0).timeIntervalSince(target)) < abs(date($1).timeIntervalSince(target)) }
}

/// Ghost refresh control whose glyph rotates while a refresh is in flight —
/// never a spinner overlay.
struct RefreshButton: View {
    let isLoading: Bool
    let action: () -> Void
    @State private var spinning = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.inkSecondary)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                           value: spinning)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onChange(of: isLoading) { _, loading in spinning = loading }
        .help("Refresh quotes")
    }
}

// MARK: - DS dropdown menu (replaces the plain gray native Menu)

/// One row in a `DSMenu`.
struct DSMenuAction: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var destructive: Bool = false
    var action: () -> Void
}

/// A design-system dropdown: a button that opens a DS-styled popover of rows
/// (Inter, emerald hover, red for destructive), instead of the native NSMenu.
struct DSMenu<Label: View>: View {
    var width: CGFloat = 210
    /// Sections are separated by a divider.
    let sections: [[DSMenuAction]]
    @ViewBuilder var label: () -> Label
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $show, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { si, section in
                        if si > 0 { Divider().overlay(DS.hairline).padding(.vertical, 3) }
                        ForEach(section) { item in
                            DSMenuRow(item: item) { show = false }
                        }
                    }
                }
                .padding(6)
                .frame(width: width)
            }
    }
}

private struct DSMenuRow: View {
    let item: DSMenuAction
    let dismiss: () -> Void
    @State private var hover = false

    var body: some View {
        Button { dismiss(); item.action() } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon).font(.system(size: 12)).frame(width: 16)
                Text(LocalizedStringKey(item.title)).font(.inter(12.5, relativeTo: .body))
                Spacer(minLength: 8)
            }
            .foregroundStyle(item.destructive ? DS.down : DS.ink)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? (item.destructive ? DS.down.opacity(0.10) : DS.brand.opacity(0.10)) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - DS picker (replaces the native popup-button Picker)

/// A design-system select: a pill showing the current value that opens a DS
/// popover of options with a checkmark on the selection.
struct DSPicker<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var width: CGFloat = 240
    @State private var show = false

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 7) {
                Text(LocalizedStringKey(currentLabel)).font(DS.body).foregroundStyle(DS.ink).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.inkTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.cardAlt))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(show ? DS.brand : DS.hairline, lineWidth: show ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(options, id: \.value) { opt in
                        DSPickerRow(label: opt.label, selected: opt.value == selection) {
                            selection = opt.value; show = false
                        }
                    }
                }
                .padding(6)
            }
            .frame(width: width)
            .frame(maxHeight: 320)
        }
    }
}

private struct DSPickerRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(label)).font(.inter(12.5, weight: selected ? .semibold : .regular, relativeTo: .body))
                    .foregroundStyle(DS.ink)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.brand) }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? DS.brand.opacity(0.10) : (selected ? DS.brand.opacity(0.06) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - DS toggle (replaces the native switch)

struct DSToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? DS.brand : DS.inkTertiary.opacity(0.28))
                .frame(width: 38, height: 22)
                .overlay(alignment: .leading) {
                    Circle().fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(2)
                        .offset(x: isOn ? 16 : 0)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DS slider (replaces the native slider)

struct DSSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var width: CGFloat = 160

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        // Clamp so a value persisted outside the current range can't push the
        // knob/fill off the track.
        return min(max(CGFloat((value - range.lowerBound) / span), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knob: CGFloat = 16
            let travel = max(w - knob, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(DS.inkTertiary.opacity(0.22)).frame(height: 4)
                Capsule().fill(DS.brand).frame(width: fraction * travel + knob / 2, height: 4)
                Circle().fill(.white)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(DS.brand, lineWidth: 2))
                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                    .offset(x: fraction * travel)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max((g.location.x - knob / 2) / travel, 0), 1)
                        let span = range.upperBound - range.lowerBound
                        let raw = range.lowerBound + Double(f) * span
                        let stepped = step > 0 ? (raw / step).rounded() * step : raw
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(width: width, height: 16)
    }
}

// MARK: - DS color well (replaces the native ColorPicker system panel)

/// A custom color well: a swatch that opens a DS popover with a
/// saturation/brightness field and a hue slider — no system color panel.
struct DSColorWell: View {
    @Binding var color: Color
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 40, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            HSBColorPicker(color: $color).padding(12).frame(width: 236)
        }
    }
}

private struct HSBColorPicker: View {
    @Binding var color: Color
    @State private var hue: Double = 0
    @State private var sat: Double = 1
    @State private var bri: Double = 1

    var body: some View {
        VStack(spacing: 12) {
            // Saturation (x) × brightness (y) field
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    Rectangle().fill(LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                                                    startPoint: .leading, endPoint: .trailing))
                    Rectangle().fill(LinearGradient(colors: [.clear, .black],
                                                    startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    Circle().stroke(.white, lineWidth: 2).shadow(radius: 1)
                        .frame(width: 14, height: 14)
                        .position(x: sat * w, y: (1 - bri) * h)
                )
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    guard w > 0, h > 0 else { return }
                    sat = min(max(g.location.x / w, 0), 1)
                    bri = 1 - min(max(g.location.y / h, 0), 1)
                    push()
                })
            }
            .frame(height: 130)

            // Hue slider
            GeometryReader { geo in
                let w = geo.size.width
                Capsule()
                    .fill(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6.0).map {
                        Color(hue: $0, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                    .overlay(
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(DS.hairline))
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                            .position(x: hue * (w - 16) + 8, y: 6)
                    )
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        guard w > 16 else { return }
                        hue = min(max((g.location.x - 8) / (w - 16), 0), 1)
                        push()
                    })
            }
            .frame(height: 16)
        }
        .onAppear(perform: pull)
    }

    private func push() { color = Color(hue: hue, saturation: sat, brightness: bri) }

    private func pull() {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h); sat = Double(s); bri = Double(b)
    }
}

// MARK: - DS spinner (replaces the native ProgressView)

struct DSSpinner: View {
    var size: CGFloat = 16
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(DS.brand, style: StrokeStyle(lineWidth: max(size * 0.14, 1.5), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

// MARK: - DS modal confirm (replaces the native .alert)

struct DSAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    var confirmTitle: String = "OK"
    var cancelTitle: String? = "Cancel"
    var destructive: Bool = false
    var onConfirm: () -> Void = {}

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.16).ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey(title)).font(.inter(15, weight: .semibold, relativeTo: .headline)).foregroundStyle(DS.ink)
                        Text(LocalizedStringKey(message)).font(DS.body).foregroundStyle(DS.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Spacer()
                            if let cancelTitle {
                                Button { isPresented = false } label: {
                                    Text(LocalizedStringKey(cancelTitle))
                                        .font(.inter(12.5, weight: .medium, relativeTo: .body)).foregroundStyle(DS.inkSecondary)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(Capsule().fill(DS.cardAlt))
                                }.buttonStyle(.plain)
                            }
                            Button { isPresented = false; onConfirm() } label: {
                                Text(LocalizedStringKey(confirmTitle))
                                    .font(.inter(12.5, weight: .semibold, relativeTo: .body)).foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(Capsule().fill(destructive ? DS.down : DS.brand))
                            }.buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .frame(width: 340)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DS.hairline))
                    .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .animation(.easeOut(duration: 0.16), value: isPresented)
            }
        }
    }
}

extension View {
    func dsAlert(_ isPresented: Binding<Bool>, title: String, message: String,
                 confirmTitle: String = "OK", cancelTitle: String? = "Cancel",
                 destructive: Bool = false, onConfirm: @escaping () -> Void = {}) -> some View {
        modifier(DSAlertModifier(isPresented: isPresented, title: title, message: message,
                                 confirmTitle: confirmTitle, cancelTitle: cancelTitle,
                                 destructive: destructive, onConfirm: onConfirm))
    }
}

// MARK: - Sidebar nav row

/// Premium sidebar entry: icon + title + optional trailing figure. The selection
/// pill slides between rows via `matchedGeometryEffect` when a namespace is given.
struct NavRow: View {
    let icon: String
    let title: String
    var trailing: String? = nil
    var trailingTint: Color = DS.inkTertiary
    var helpText: String? = nil
    let selected: Bool
    var namespace: Namespace.ID? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium)).frame(width: 18)
                    .foregroundStyle(selected ? DS.brand : DS.inkSecondary)
                Text(LocalizedStringKey(title))
                    .font(.inter(12.5, weight: selected ? .semibold : .regular, relativeTo: .body))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(.inter(10.5, weight: .medium, relativeTo: .caption2).monospacedDigit())
                        .foregroundStyle(trailingTint)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background {
                if selected {
                    selectionPill
                } else if hover {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(helpText ?? title)
    }

    @ViewBuilder private var selectionPill: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.brand.opacity(0.13))
        if let namespace {
            shape.matchedGeometryEffect(id: "navSelection", in: namespace)
        } else {
            shape
        }
    }
}
