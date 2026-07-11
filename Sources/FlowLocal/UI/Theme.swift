import SwiftUI

/// Minimal palette. Oxygen Flow is black-and-white with a single small accent — a Bahama teal.
/// Everything else uses plain default SwiftUI styling.
enum Palette {
    static let accent = Color(red: 20/255, green: 180/255, blue: 200/255) // Bahama teal ~#14B4C8
    static let danger = Color(red: 178/255, green: 59/255, blue: 59/255)

    // App icon: near-black squircle behind the teal chevron.
    static let iconGradient = LinearGradient(
        colors: [Color(white: 0.12), .black], startPoint: .top, endPoint: .bottom
    )

    // Chip: white capsule, black text, faint rule.
    static let chipBG = Color.white
    static let chipFG = Color.black
    static let chipRule = Color.black.opacity(0.10)
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

/// The Oxygen Flow app mark: near-black squircle + a single teal chevron.
struct AppMark: View {
    var size: CGFloat = 40

    var body: some View {
        ChevronShape()
            .stroke(style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Palette.accent)
            .padding(size * 0.26)
            .frame(width: size, height: size)
            .background(Palette.iconGradient)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
    }
}

/// A plain stat tile — boring default SwiftUI.
struct StatCard: View {
    let value: String
    let label: String

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
