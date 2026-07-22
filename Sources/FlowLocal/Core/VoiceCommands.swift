import Foundation

/// Lightweight in-line voice commands, applied to the raw transcript right after transcription
/// and before the dictionary/cleanup pass. Because dictation here is single-shot (record →
/// transcribe → deliver) rather than live/incremental like Wispr Flow's, these operate *within*
/// one recording: say something, say "scratch that", keep talking — the whole thing is still
/// delivered as one paste.
enum VoiceCommands {
    private static let scratchTriggers: Set<String> = [
        "scratch that", "scratch all that", "delete that", "undo that",
        "delete last sentence", "remove that", "strike that", "strike that last part",
    ]
    private static let newParagraphTriggers: Set<String> = ["new paragraph"]
    private static let newLineTriggers: Set<String> = ["new line"]
    /// Markdown-wrap the previous sentence — most editors Wispr Flow targets (Slack, Notion,
    /// GitHub, iMessage) render `**`/`*`/`` ` `` as real formatting, so this is a portable
    /// approximation of "bold this"/"italicize that" without needing a rich-text API per app.
    private static let boldTriggers: Set<String> = ["bold that", "make that bold", "bold it"]
    private static let italicTriggers: Set<String> = ["italicize that", "italics that", "make that italic", "italicize it"]

    // Internal sentinels so paragraph/line breaks survive the join step, converted to real
    // whitespace at the end. NUL-delimited so they can never collide with spoken text.
    private static let paragraphMarker = "\u{0}PARA\u{0}"
    private static let lineMarker = "\u{0}LINE\u{0}"

    /// Spoken punctuation names, applied as standalone-word replacements before sentence
    /// splitting (so "hello comma world" → "hello, world"). Longer phrases are listed first so
    /// e.g. "question mark" matches before a bare "question" would (which isn't a trigger anyway).
    private static let punctuationWords: [(String, String)] = [
        ("exclamation point", "!"), ("exclamation mark", "!"),
        ("question mark", "?"),
        ("full stop", "."),
        ("open parenthesis", "("), ("close parenthesis", ")"),
        ("period", "."),
        ("comma", ","),
        ("colon", ":"),
        ("semicolon", ";"),
    ]

    /// Apply "scratch that" / "new paragraph" / "new line" / spoken punctuation within `raw`,
    /// returning the edited transcript. Falls back to `raw` unchanged if it can't be tokenized
    /// into sentences.
    static func process(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        let raw = applyLiteralPunctuation(raw)

        var sentences: [String] = []
        raw.enumerateSubstrings(in: raw.startIndex..<raw.endIndex, options: [.bySentences]) { sub, _, _, _ in
            if let sub, !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append(sub)
            }
        }
        guard !sentences.isEmpty else { return raw }

        var kept: [String] = []
        for sentence in sentences {
            let normalized = normalize(sentence)
            if scratchTriggers.contains(normalized) {
                if !kept.isEmpty { kept.removeLast() }
                continue
            }
            if newParagraphTriggers.contains(normalized) {
                kept.append(paragraphMarker)
                continue
            }
            if newLineTriggers.contains(normalized) {
                kept.append(lineMarker)
                continue
            }
            if boldTriggers.contains(normalized) {
                if let last = kept.popLast() { kept.append("**\(last)**") }
                continue
            }
            if italicTriggers.contains(normalized) {
                if let last = kept.popLast() { kept.append("*\(last)*") }
                continue
            }
            kept.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !kept.isEmpty else { return "" }

        let joined = kept.joined(separator: " ")
        return joined
            .replacingOccurrences(of: " \(paragraphMarker) ", with: "\n\n")
            .replacingOccurrences(of: paragraphMarker, with: "\n\n")
            .replacingOccurrences(of: " \(lineMarker) ", with: "\n")
            .replacingOccurrences(of: lineMarker, with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip trailing punctuation and lowercase, for matching a sentence against a trigger set.
    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
    }

    /// Replace standalone spoken punctuation words ("comma", "period", ...) with their symbol,
    /// consuming the whitespace before them so e.g. "hello comma world" → "hello, world".
    private static func applyLiteralPunctuation(_ text: String) -> String {
        var result = text
        for (word, symbol) in punctuationWords {
            let pattern = "\\s*\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: symbol)
            )
        }
        return result
    }
}
