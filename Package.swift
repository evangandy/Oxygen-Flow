// swift-tools-version:5.9
import PackageDescription

// FlowLocal links against the prebuilt whisper.cpp static libraries in
// vendor/whisper.cpp/build (built once with Metal embedded). See scripts/build_whisper.sh.
let whisperBuild = "vendor/whisper.cpp/build"

let package = Package(
    name: "FlowLocal",
    platforms: [.macOS(.v14)],
    targets: [
        // Header-only C interop module exposing whisper.h / ggml.h to Swift.
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "FlowLocal",
            dependencies: ["CWhisper"],
            path: "Sources/FlowLocal",
            linkerSettings: [
                .unsafeFlags([
                    "-L\(whisperBuild)/src",
                    "-L\(whisperBuild)/ggml/src",
                    "-L\(whisperBuild)/ggml/src/ggml-metal",
                    "-L\(whisperBuild)/ggml/src/ggml-blas",
                    "-lwhisper",
                    "-lggml",
                    "-lggml-base",
                    "-lggml-cpu",
                    "-lggml-metal",
                    "-lggml-blas",
                    "-lc++",
                ]),
                .linkedFramework("Foundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ]
)
