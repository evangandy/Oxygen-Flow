import Foundation

/// A single transcription record.
struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let rawTranscript: String
    let cleanedTranscript: String
    let audioDurationSeconds: Double
    let wordCount: Int
    let wordsPerMinute: Double

    init(raw: String, cleaned: String, audioDuration: Double) {
        self.id = UUID()
        self.timestamp = Date()
        self.rawTranscript = raw
        self.cleanedTranscript = cleaned
        self.audioDurationSeconds = audioDuration
        let words = cleaned.split(separator: " ").count
        self.wordCount = words
        self.wordsPerMinute = audioDuration > 0 ? Double(words) / (audioDuration / 60.0) : 0
    }
}

/// Persists every transcription to disk as JSON. Thread-safe, append-only.
final class TranscriptionStore: ObservableObject {
    static let shared = TranscriptionStore()

    @Published private(set) var entries: [TranscriptionEntry] = []

    private let storageDir: URL
    private let indexFile: URL
    private let queue = DispatchQueue(label: "flowlocal.transcription-store")

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("FlowLocal/history", isDirectory: true)
        indexFile = storageDir.appendingPathComponent("transcriptions.json")

        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadEntries()
    }

    /// Add a new transcription and persist to disk.
    func add(raw: String, cleaned: String, audioDuration: Double) {
        let entry = TranscriptionEntry(raw: raw, cleaned: cleaned, audioDuration: audioDuration)
        queue.sync {
            entries.append(entry)
            saveEntries()
        }
        NSLog("[FlowLocal] Saved transcription: %d words, %.0f WPM", entry.wordCount, entry.wordsPerMinute)
    }

    // MARK: - Insights

    var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    var totalDictations: Int {
        entries.count
    }

    var totalAudioMinutes: Double {
        entries.reduce(0.0) { $0 + $1.audioDurationSeconds } / 60.0
    }

    var averageWPM: Double {
        let totalSeconds = entries.reduce(0.0) { $0 + $1.audioDurationSeconds }
        guard totalSeconds > 0 else { return 0 }
        return Double(totalWords) / (totalSeconds / 60.0)
    }

    var todayWordCount: Int {
        let cal = Calendar.current
        return entries
            .filter { cal.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.wordCount }
    }

    var thisWeekWordCount: Int {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        return entries
            .filter { $0.timestamp >= weekAgo }
            .reduce(0) { $0 + $1.wordCount }
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: indexFile.path) else { return }
        do {
            let data = try Data(contentsOf: indexFile)
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
            NSLog("[FlowLocal] Loaded %d transcription entries", entries.count)
        } catch {
            NSLog("[FlowLocal] Failed to load transcription history: %@", error.localizedDescription)
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
            NSLog("[FlowLocal] Failed to save transcription history: %@", error.localizedDescription)
        }
    }
}
