import Foundation

// Entry point. `--selftest <wav>` runs the whisper+Ollama pipeline headlessly and prints
// timings (no GUI/permissions needed); otherwise launch the normal menu-bar app.
if CommandLine.arguments.contains("--selftest") {
    let wav = CommandLine.arguments.last ?? ""
    SelfTest.run(wavPath: wav)
} else if let idx = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let outDir = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/oxygenflow-snapshots"
    MainActor.assumeIsolated {
        Snapshot.run(outDir: outDir)
    }
} else {
    FlowLocalApp.main()
}
