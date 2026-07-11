import SwiftUI

/// The only styling in the app: black-and-white with a single accent — a Bahama teal.
/// Used for the window tint, the Insights chart, and the floating chip. Everything else is
/// plain, default Mac SwiftUI.
enum Palette {
    static let accent = Color(red: 20/255, green: 180/255, blue: 200/255) // Bahama teal ~#14B4C8
    static let danger = Color(red: 178/255, green: 59/255, blue: 59/255)

    // Chip: white capsule, black text, faint rule.
    static let chipBG = Color.white
    static let chipFG = Color.black
    static let chipRule = Color.black.opacity(0.10)
}
