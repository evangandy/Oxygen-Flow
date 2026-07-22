import SwiftUI
import AppKit

/// Strictly monochrome: black, white, and one off-white. No decorative brand color anywhere —
/// no orange, no lavender, no blue. Applied consistently across every screen via `FlowCard` /
/// `FlowSectionLabel` below, so the whole app shares one visual language instead of the chip
/// being styled and the rest staying default macOS chrome.
enum Palette {
    static let vastInk = Color(red: 0x1a/255, green: 0x1a/255, blue: 0x1a/255)      // near-black
    static let charcoal = Color(red: 0x22/255, green: 0x22/255, blue: 0x22/255)
    static let fog = Color(red: 0x8a/255, green: 0x8a/255, blue: 0x86/255)          // neutral gray, no color cast
    static let offWhite = Color(red: 0xf5/255, green: 0xf5/255, blue: 0xf2/255)     // barely-there warm gray, not cream/yellow
    static let hairline = Color(red: 0xe2/255, green: 0xe2/255, blue: 0xdf/255)

    /// The single "accent" is near-black itself — interactive elements are black-on-white, not a
    /// colored highlight. No orange, no lavender, no blue anywhere in the app.
    static let accent = vastInk
    static let danger = Color(red: 120/255, green: 40/255, blue: 40/255)            // muted, desaturated — functional only, not decorative

    // Chip: small dark glass capsule, white text/icons.
    static let chipBG = vastInk
    static let chipFG = Color.white

    // Whole-app surfaces — adapt to light/dark so the app still respects system appearance.
    static let windowBackground = Color(light: offWhite, dark: vastInk)
    static let sidebarBackground = Color(light: Color(red: 0xef/255, green: 0xef/255, blue: 0xec/255), dark: Color(red: 0x14/255, green: 0x14/255, blue: 0x14/255))
    static let surface = Color(light: .white, dark: charcoal)
    static let surfaceBorder = Color(light: hairline, dark: .white.opacity(0.08))
    static let textPrimary = Color(light: vastInk, dark: .white)
    static let textSecondary = fog
}

extension Color {
    /// A dynamic color that resolves to `light` or `dark` based on the current appearance —
    /// SwiftUI's `Color` has no built-in light/dark initializer outside asset catalogs.
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }))
    }
}

/// Layout tokens shared by every screen's cards, matching Wispr's "soft corners, generous
/// spacing" language, scaled down from their web card sizes to fit a compact native window.
enum Metrics {
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 18
}

/// A rounded, softly-bordered container used in place of default `Form`/`List` sections —
/// the one repeating structural element that makes every screen read as one product instead of
/// the chip being styled and the rest staying stock macOS chrome.
struct FlowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: { content })
            .padding(Metrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.surfaceBorder, lineWidth: 1)
            )
    }
}

/// A small uppercase, tracked label above a card group — Wispr's editorial-ish section labeling,
/// rendered in the native system font (not an imported serif) to stay a proper native control.
struct FlowSectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.textSecondary)
    }
}

/// A small rounded pill badge — Wispr's "full-pill" tag style — used for delivery method, app
/// names, and similar short metadata instead of plain inline text.
struct FlowBadge: View {
    let text: String
    var tinted: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tinted ? Color.white : Palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tinted ? AnyShapeStyle(Palette.vastInk) : AnyShapeStyle(Palette.surfaceBorder.opacity(0.6)))
            )
    }
}

extension View {
    /// A rounded, hairline-bordered text field matching the card language — used in place of
    /// the default `.roundedBorder` style throughout so inputs read as this app's own controls.
    func flowFieldStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(Palette.windowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(Palette.surfaceBorder, lineWidth: 1)
            )
            .foregroundStyle(Palette.textPrimary)
    }
}

/// Lets the offscreen `Snapshot` renderer disable `FlowPage`'s `ScrollView` — `ImageRenderer`
/// renders `ScrollView` content as blank without a real window/scroll-view geometry pass, which
/// is a rendering-harness limitation, not something a real window hits. Defaults to normal
/// scrolling behavior for the actual app.
private struct FlowPageScrollDisabledKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var flowPageScrollDisabled: Bool {
        get { self[FlowPageScrollDisabledKey.self] }
        set { self[FlowPageScrollDisabledKey.self] = newValue }
    }
}

/// The standard page chrome every screen uses: page title, optional trailing accessory, and a
/// scrollable column of `FlowCard`s on the shared window background.
struct FlowPage<Content: View>: View {
    let title: String
    @Environment(\.flowPageScrollDisabled) private var scrollDisabled
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if scrollDisabled {
                pageContent
            } else {
                ScrollView { pageContent }
            }
        }
        .background(Palette.windowBackground)
        .scrollContentBackground(.hidden)
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 4)
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
