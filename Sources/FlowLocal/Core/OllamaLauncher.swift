import Foundation

/// Ensures a local Ollama server is running so cleanup works out of the box. On launch, if the
/// endpoint isn't reachable, this starts `ollama serve` in the background. (The app is not
/// sandboxed, so it may spawn processes.)
enum OllamaLauncher {
    private static let candidatePaths = [
        "/opt/homebrew/bin/ollama",  // Apple Silicon Homebrew
        "/usr/local/bin/ollama",     // Intel Homebrew
        "/usr/bin/ollama",
    ]

    /// Check the endpoint; if it's down, try to launch `ollama serve`. Fire-and-forget.
    static func ensureRunning(endpoint: String) {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces) + "/api/tags") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: req) { _, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                NSLog("[Oxygen] Ollama already running")
            } else {
                launch()
            }
        }.resume()
    }

    private static func launch() {
        guard let path = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            NSLog("[Oxygen] ollama binary not found — install it or start it manually")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            NSLog("[Oxygen] launched `ollama serve` (%@)", path)
        } catch {
            NSLog("[Oxygen] failed to launch ollama: %@", error.localizedDescription)
        }
    }
}
