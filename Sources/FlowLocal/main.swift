import Foundation

// Entry point. `--selftest <wav>` runs the whisper+Ollama pipeline headlessly and prints
// timings (no GUI/permissions needed); otherwise launch the normal menu-bar app.
if CommandLine.arguments.contains("--selftest") {
    let wav = CommandLine.arguments.last ?? ""
    SelfTest.run(wavPath: wav)
} else {
    FlowLocalApp.main()
}
