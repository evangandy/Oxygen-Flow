import Foundation

/// How the dictated text was delivered to the user.
enum DeliveryMode: String, Codable {
    case pasted     // injected at the cursor via Cmd+V
    case copied     // no editable field focused; placed on the clipboard
}

/// A single transcription record.
struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let rawTranscript: String
    let cleanedTranscript: String
    let audioDurationSeconds: Double
    let wordCount: Int
    let wordsPerMinute: Double

    // Added in v2 — optional so older history JSON still decodes.
    var appName: String?
    var delivery: DeliveryMode?
    /// Reserved for a future rolling LLM summary (see Insights view).
    var gist: String?

    init(raw: String, cleaned: String, audioDuration: Double,
         appName: String? = nil, delivery: DeliveryMode? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.rawTranscript = raw
        self.cleanedTranscript = cleaned
        self.audioDurationSeconds = audioDuration
        let words = cleaned.split { $0 == " " || $0 == "\n" }.count
        self.wordCount = words
        self.wordsPerMinute = audioDuration > 0 ? Double(words) / (audioDuration / 60.0) : 0
        self.appName = appName
        self.delivery = delivery
    }

    var rawWordCount: Int {
        rawTranscript.split { $0 == " " || $0 == "\n" }.count
    }
}

/// One day's rolled-up word count, for the activity chart.
struct DailyWordCount: Identifiable {
    let id = UUID()
    let date: Date
    let words: Int
}

/// Persists every transcription to disk as JSON. Thread-safe, append-only.
@MainActor
final class TranscriptionStore: ObservableObject {
    static let shared = TranscriptionStore()

    @Published private(set) var entries: [TranscriptionEntry] = []

    private let storageDir: URL
    private let indexFile: URL

    /// Assumed typing speed (WPM) used to estimate time saved vs. typing.
    private let typingWPM = 40.0

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("FlowLocal/history", isDirectory: true)
        indexFile = storageDir.appendingPathComponent("transcriptions.json")

        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadEntries()
    }

    /// Add a new transcription and persist to disk. Newest entries are kept at the front.
    func add(raw: String, cleaned: String, audioDuration: Double,
             appName: String?, delivery: DeliveryMode) {
        let entry = TranscriptionEntry(raw: raw, cleaned: cleaned, audioDuration: audioDuration,
                                       appName: appName, delivery: delivery)
        entries.insert(entry, at: 0)
        saveEntries()
        NSLog("[Cobalt] Saved dictation: %d words, %.0f WPM (%@)", entry.wordCount, entry.wordsPerMinute, delivery.rawValue)
    }

    func delete(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    func clearAll() {
        entries.removeAll()
        saveEntries()
    }

    // MARK: - Aggregate insights

    var totalWords: Int { entries.reduce(0) { $0 + $1.wordCount } }
    var totalDictations: Int { entries.count }
    var totalAudioMinutes: Double { entries.reduce(0.0) { $0 + $1.audioDurationSeconds } / 60.0 }

    var averageWPM: Double {
        let totalSeconds = entries.reduce(0.0) { $0 + $1.audioDurationSeconds }
        guard totalSeconds > 0 else { return 0 }
        return Double(totalWords) / (totalSeconds / 60.0)
    }

    var todayWordCount: Int {
        let cal = Calendar.current
        return entries.filter { cal.isDateInToday($0.timestamp) }.reduce(0) { $0 + $1.wordCount }
    }

    var thisWeekWordCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return entries.filter { $0.timestamp >= weekAgo }.reduce(0) { $0 + $1.wordCount }
    }

    /// Minutes saved vs. typing the same words by hand at `typingWPM`.
    var timeSavedMinutes: Double {
        let typingMinutes = Double(totalWords) / typingWPM
        return max(0, typingMinutes - totalAudioMinutes)
    }

    /// Consecutive days ending today (or yesterday) with at least one dictation.
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.timestamp) })
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day), days.contains(yesterday)
            else { return 0 }
            day = yesterday
        }
        while days.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Word counts for the last `days` calendar days (oldest → newest), for the activity chart.
    func lastDays(_ days: Int) -> [DailyWordCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var buckets: [Date: Int] = [:]
        for e in entries {
            let d = cal.startOfDay(for: e.timestamp)
            buckets[d, default: 0] += e.wordCount
        }
        return (0..<days).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            return DailyWordCount(date: d, words: buckets[d] ?? 0)
        }
    }

    /// Apps you dictate into most, most-used first.
    func topApps(limit: Int = 5) -> [(app: String, count: Int)] {
        var counts: [String: Int] = [:]
        for e in entries {
            guard let app = e.appName, !app.isEmpty else { continue }
            counts[app, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// Average share of words the cleanup step trimmed (filler removal), 0...1.
    var averageTrimRatio: Double {
        let usable = entries.filter { $0.rawWordCount > 0 }
        guard !usable.isEmpty else { return 0 }
        let ratios = usable.map { e -> Double in
            let trimmed = max(0, e.rawWordCount - e.wordCount)
            return Double(trimmed) / Double(e.rawWordCount)
        }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: indexFile.path) else { return }
        do {
            let data = try Data(contentsOf: indexFile)
            var loaded = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
            // Ensure newest-first regardless of how the file was written historically.
            loaded.sort { $0.timestamp > $1.timestamp }
            entries = loaded
            NSLog("[Cobalt] Loaded %d dictation entries", entries.count)
        } catch {
            NSLog("[Cobalt] Failed to load history: %@", error.localizedDescription)
        }
    }

    private func saveEntries() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: indexFile, options: .atomic)
        } catch {
            NSLog("[Cobalt] Failed to save history: %@", error.localizedDescription)
        }
    }
}
