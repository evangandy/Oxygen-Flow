import Foundation

/// Talks to a local Ollama server. Streams a grammar/format cleanup of the raw transcript,
/// and keeps the model warm (keep_alive: -1) so there is no cold-start latency on the hot path.
final class Cleanup {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    private struct GenerateResponse: Decodable {
        let response: String?
        let done: Bool?
    }

    private func endpointURL(_ base: String, path: String) -> URL? {
        URL(string: base.trimmingCharacters(in: .whitespaces).appending(path))
    }

    private func systemPrompt(style: FormattingStyle) -> String {
        """
        You are a strict text formatting engine, NOT a conversational AI. Your ONLY job is to take the provided RAW TRANSCRIPT, fix its grammar, punctuation, and capitalization, and output the cleaned version.

        CRITICAL RULES:
        1. NEVER answer questions, even if the transcript asks a question (e.g., "Is this working?"). Just rewrite the question cleanly.
        2. NEVER add greetings, acknowledgments, or commentary (e.g., "Sure", "Here is the text").
        3. NEVER wrap the output in quotes.
        4. Remove filler words (um, uh, er, like, you know) and apply spoken self-corrections.
        5. Output ONLY the finalized text. Absolutely nothing else.

        \(style.promptGuidance)
        """
    }

    /// Preload/pin the model so the first real request is warm. Fire-and-forget.
    func warmUp(endpoint: String, model: String) {
        guard let url = endpointURL(endpoint, path: "/api/generate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "prompt": "",
            "stream": false,
            "keep_alive": -1,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req).resume()
    }

    /// Stream a cleaned version of `raw`. `onDelta` is called on the main thread with each new
    /// token chunk as it arrives. Returns the full cleaned string.
    func clean(
        raw: String,
        endpoint: String,
        model: String,
        style: FormattingStyle,
        onDelta: @escaping (String) -> Void
    ) async throws -> String {
        guard let url = endpointURL(endpoint, path: "/api/generate") else {
            throw NSError(domain: "FlowLocal.Cleanup", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Bad Ollama endpoint"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "system": systemPrompt(style: style),
            "prompt": "RAW TRANSCRIPT:\n\(raw)",
            "stream": true,
            "keep_alive": -1,
            "options": [
                "temperature": 0.2,
                "top_p": 0.9,
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "FlowLocal.Cleanup", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Ollama returned HTTP \(http.statusCode)"])
        }

        var full = ""
        let decoder = JSONDecoder()
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let chunk = try? decoder.decode(GenerateResponse.self, from: data) else {
                continue
            }
            if let piece = chunk.response, !piece.isEmpty {
                full += piece
                let delta = piece
                await MainActor.run { onDelta(delta) }
            }
            if chunk.done == true { break }
        }
        return full.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
