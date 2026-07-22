import Foundation

/// A user-defined word or phrase Oxygen Flow should recognize exactly, with an optional note
/// giving the cleanup model context about what it means (e.g. "10-K" → "SEC annual report
/// filing"). Terms feed Whisper's `initial_prompt` (biases the STT decoder toward the right
/// spelling) and notes feed the Ollama cleanup system prompt (so the model understands jargon
/// it would otherwise guess at or "correct" away).
struct DictionaryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var term: String
    var note: String

    init(id: UUID = UUID(), term: String, note: String = "") {
        self.id = id
        self.term = term
        self.note = note
    }
}

/// Persists the personal dictionary to disk as JSON, alongside dictation history.
@MainActor
final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()

    @Published private(set) var entries: [DictionaryEntry] = []

    private let file: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FlowLocal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("dictionary.json")
        load()
    }

    @discardableResult
    func add(term: String, note: String = "") -> Bool {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return false }
        guard !entries.contains(where: { $0.term.caseInsensitiveCompare(trimmedTerm) == .orderedSame }) else { return false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.append(DictionaryEntry(term: trimmedTerm, note: trimmedNote))
        save()
        return true
    }

    func update(_ entry: DictionaryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        save()
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func delete(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Comma-separated vocabulary handed to whisper's `initial_prompt` to bias decoding toward
    /// these exact terms. Capped so the prompt stays cheap relative to the audio context window.
    var whisperVocabulary: String {
        let terms = entries.map(\.term).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return "" }
        return terms.prefix(100).joined(separator: ", ")
    }

    /// A glossary block injected into the cleanup system prompt so the model recognizes domain
    /// terms/names it has no other way of knowing (e.g. that "10-K" is an SEC filing, not a typo
    /// for "10 K" or "ten kay"), without ever explaining or defining them in its output.
    var cleanupGlossary: String? {
        guard !entries.isEmpty else { return nil }
        let lines = entries.map { entry -> String in
            entry.note.isEmpty ? "- \(entry.term)" : "- \(entry.term): \(entry.note)"
        }
        return """
        PERSONAL DICTIONARY: the speaker regularly uses these exact terms/names. Always spell and \
        capitalize them exactly as shown here, never "correct" or expand them, and use the notes \
        only to understand what the speaker means in context — never explain, define, or restate \
        a term's meaning in your output.
        \(lines.joined(separator: "\n"))
        """
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        entries = (try? JSONDecoder().decode([DictionaryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
