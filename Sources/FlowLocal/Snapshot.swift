import AppKit
import SwiftUI

/// Headless visual verification: renders the app's actual SwiftUI views to PNG via
/// `ImageRenderer` (no screen capture, no Screen Recording permission needed — this renders the
/// real view tree offscreen) so the design pass can be checked pixel-by-pixel instead of only
/// reasoned about. Triggered by `--snapshot <outDir>`; writes PNGs and exits.
@MainActor
enum Snapshot {
    static func run(outDir: String) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let controller = DictationController() // not bootstrapped — no mic/model/hotkey side effects

        // ImageRenderer renders ScrollView content blank without a real window, so disable
        // FlowPage's ScrollView just for this offscreen pass (see flowPageScrollDisabled).
        render("\(outDir)/dashboard.png", DashboardView(controller: controller)
            .environment(\.flowPageScrollDisabled, true).frame(width: 700))
        render("\(outDir)/settings.png", SettingsView()
            .environment(\.flowPageScrollDisabled, true).frame(width: 560))
        render("\(outDir)/dictionary.png", DictionaryView()
            .environment(\.flowPageScrollDisabled, true).frame(width: 700))
        render("\(outDir)/snippets.png", SnippetsView()
            .environment(\.flowPageScrollDisabled, true).frame(width: 700))
        render("\(outDir)/insights.png", InsightsView()
            .environment(\.flowPageScrollDisabled, true).frame(width: 700))

        let presenter = ChipPresenter()
        for (name, state) in [
            ("chip-listening", DictationController.State.listening),
            ("chip-cleaning", .cleaning),
            ("chip-copied", .copied),
            ("chip-error", .error("No text selected")),
        ] {
            presenter.state = state
            render("\(outDir)/\(name).png",
                PillView(controller: controller, presenter: presenter)
                    .padding(40)
                    .background(Color(white: 0.5))
                    .frame(width: 360, height: 140)
            )
        }

        print("SNAPSHOT_DONE")
        exit(0)
    }

    private static func render<V: View>(_ path: String, _ view: V) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("FAILED to render \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
