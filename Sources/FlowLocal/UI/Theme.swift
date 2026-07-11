import SwiftUI

/// Minimal tokens. The only brand color is the cobalt blue; everything else in the app uses
/// plain default SwiftUI styling. (The floating chip reuses a few of these for its look.)
enum Cobalt {
    static let blue = Color(red: 31/255, green: 43/255, blue: 224/255)          // #1f2be0
    // Chip-only tokens (kept because the chip design uses them).
    static let paper = Color(red: 240/255, green: 235/255, blue: 222/255)       // #f0ebde
    static let ink = blue
    static let inkMuted = Color(red: 85/255, green: 96/255, blue: 229/255)      // #5560e5
    static let danger = Color(red: 178/255, green: 59/255, blue: 59/255)        // #b23b3b
    static let rule = blue.opacity(0.22)

    /// Icon gradient — depth around the brand blue #1f2be0.
    static let gradient = LinearGradient(
        colors: [Color(red: 54/255, green: 68/255, blue: 238/255),
                 Color(red: 20/255, green: 26/255, blue: 156/255)],
        startPoint: .top, endPoint: .bottom
    )
}

/// A single chevron ">".
struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let apex = rect.minX + w * 0.66
        let armW = w * 0.42
        let halfH = h * 0.30
        p.move(to: CGPoint(x: apex - armW, y: rect.midY - halfH))
        p.addLine(to: CGPoint(x: apex, y: rect.midY))
        p.addLine(to: CGPoint(x: apex - armW, y: rect.midY + halfH))
        return p
    }
}

/// The Oxygen Flow app mark: blue squircle + a single white chevron.
struct CobaltMark: View {
    var size: CGFloat = 40

    var body: some View {
        ChevronShape()
            .stroke(style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
            .foregroundStyle(.white)
            .padding(size * 0.26)
            .frame(width: size, height: size)
            .background(Cobalt.gradient)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
    }
}

/// A plain stat tile — boring default SwiftUI.
struct StatCard: View {
    let value: String
    let label: String
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2).fontWeight(.semibold)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
