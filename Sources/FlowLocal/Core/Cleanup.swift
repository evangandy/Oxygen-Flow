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

    private func systemPrompt(style: FormattingStyle, context: AppContext) -> String {
        var prompt = """
        You are a minimal text cleanup engine, NOT a conversational AI. You receive a raw speech-to-text transcript. Your job is to make the smallest changes necessary to produce clean, readable text.

        RULES:
        1. Fix capitalization, punctuation, and basic grammar only.
        2. Remove filler words: um, uh, er, like (when used as filler), you know, I mean, so (when used as a verbal tic at the start of sentences), kind of (when used as filler), right, basically, actually (when used as filler).
        3. Apply spoken self-corrections (e.g. "send it to John, no wait, to Jane" → "send it to Jane").
        4. Do NOT rewrite, rephrase, or polish the speaker's words. Keep their original wording.
        5. Do NOT answer questions or add any commentary.
        6. Do NOT wrap output in quotes.
        7. Output ONLY the cleaned text.

        \(style.promptGuidance)
        """
        if let guidance = context.promptGuidance {
            prompt += "\n\n" + guidance
        }
        return prompt
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    /// Fetch the list of models installed in the local Ollama server (from `/api/tags`).
    /// Returns model names sorted alphabetically, or throws if Ollama is unreachable.
    func listModels(endpoint: String) async throws -> [String] {
        guard let url = endpointURL(endpoint, path: "/api/tags") else {
            throw NSError(domain: "FlowLocal.Cleanup", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Bad Ollama endpoint"])
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "FlowLocal.Cleanup", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Ollama returned HTTP \(http.statusCode)"])
        }
        let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
        return tags.models.map(\.name).sorted()
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
        context: AppContext = .general,
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
            "system": systemPrompt(style: style, context: context),
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
