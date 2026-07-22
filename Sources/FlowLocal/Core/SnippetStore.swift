import Foundation

/// A voice-triggered canned-text macro — say the trigger phrase and Oxygen Flow delivers the
/// expansion verbatim instead of running it through cleanup (e.g. trigger "my email signature",
/// expansion your actual signature block). Mirrors Wispr Flow's snippets/macros feature.
struct SnippetEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var trigger: String
    var expansion: String

    init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

/// Persists snippets to disk as JSON, alongside the personal dictionary.
@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published private(set) var entries: [SnippetEntry] = []

    private let file: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FlowLocal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("snippets.json")
        load()
    }

    @discardableResult
    func add(trigger: String, expansion: String) -> Bool {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrigger.isEmpty, !trimmedExpansion.isEmpty else { return false }
        guard !entries.contains(where: { SnippetStore.normalize($0.trigger) == SnippetStore.normalize(trimmedTrigger) }) else {
            return false
        }
        entries.append(SnippetEntry(trigger: trimmedTrigger, expansion: trimmedExpansion))
        save()
        return true
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func delete(_ entry: SnippetEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Returns the expansion text if `text` (the whole dictated utterance, after voice-command
    /// processing) matches a snippet trigger phrase exactly, ignoring case/trailing punctuation.
    func match(_ text: String) -> String? {
        let normalized = SnippetStore.normalize(text)
        guard !normalized.isEmpty else { return nil }
        return entries.first { SnippetStore.normalize($0.trigger) == normalized }?.expansion
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,"))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        entries = (try? JSONDecoder().decode([SnippetEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
