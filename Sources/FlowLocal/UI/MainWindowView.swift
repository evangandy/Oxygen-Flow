import Charts
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var controller: DictationController
    @State private var section: Section = .dashboard

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case history = "History"
        case insights = "Insights"
        case settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .dashboard: return "waveform"
            case .history: return "text.bubble"
            case .insights: return "chart.bar.xaxis"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(190)
            .safeAreaInset(edge: .top) { brandHeader }
        } detail: {
            switch section {
            case .dashboard: DashboardView(controller: controller)
            case .history: HistoryView()
            case .insights: InsightsView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .tint(Cobalt.blue)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            CobaltMark(size: 28)
            Text("Cobalt Flow").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var store = TranscriptionStore.shared

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                statusHero
                LazyVGrid(columns: cols, spacing: 12) {
                    StatCard(value: "\(store.todayWordCount)", label: "Words today")
                    StatCard(value: store.averageWPM > 0 ? "\(Int(store.averageWPM))" : "—", label: "Avg words / min")
                    StatCard(value: "\(store.streakDays)", label: "Day streak")
                    StatCard(value: timeSaved, label: "Time saved")
                }
            }
            .padding(28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dashboard")
    }

    private var timeSaved: String {
        let mins = store.timeSavedMinutes
        if mins < 1 { return "—" }
        if mins < 60 { return "\(Int(mins))m" }
        return String(format: "%.1fh", mins / 60)
    }

    private var statusHero: some View {
        VStack(spacing: 16) {
            Image(systemName: controller.state == .listening ? "waveform" : "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(controller.state == .listening ? Color.red : Cobalt.blue)
                .symbolEffect(.pulse, isActive: controller.state == .listening)
                .frame(height: 60)

            Text(statusTitle).font(.title2).fontWeight(.semibold)
            Text(statusSubtitle)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { controller.toggle() }) {
                Text(controller.state == .listening ? "Stop Dictation" : "Start Dictation")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.state == .listening ? .red : Cobalt.blue)
            .controlSize(.large)
            .disabled(!controller.isReady && controller.state == .idle)

            if let err = controller.lastError {
                VStack(spacing: 6) {
                    Text("⚠︎ \(err)").foregroundStyle(.red).font(.caption)
                    Button("Grant Accessibility & Retry") {
                        HotkeyManager.requestAccessibilityPermission()
                        controller.retryHotkey()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var statusTitle: String {
        switch controller.state {
        case .idle: return controller.isReady ? "Ready to Dictate" : "Loading Model…"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .cleaning: return "Formatting"
        case .copied: return "Copied to Clipboard"
        case .error: return "Error"
        }
    }

    private var statusSubtitle: String {
        switch controller.state {
        case .idle: return controller.isReady ? "Press \(AppSettings.shared.hotkeyDisplayString) anywhere to start." : "Warming up Whisper in memory."
        case .listening: return "Speak now. Press \(AppSettings.shared.hotkeyDisplayString) when you're done."
        case .transcribing: return "Converting your speech to text…"
        case .cleaning: return "Applying grammar, punctuation, and formatting…"
        case .copied: return "No text field was focused — press ⌘V to paste."
        case .error(let m): return m
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject private var store = TranscriptionStore.shared
    @State private var selection: TranscriptionEntry.ID?

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView("No dictations yet",
                    systemImage: "text.bubble",
                    description: Text("Your dictations will appear here — every one is saved locally."))
            } else {
                List(store.entries, selection: $selection) { entry in
                    HistoryRow(entry: entry).tag(entry.id)
                }
            }
        }
        .navigationTitle("History")
        .inspector(isPresented: .constant(selection != nil)) {
            if let entry = store.entries.first(where: { $0.id == selection }) {
                HistoryDetail(entry: entry)
            } else {
                Text("Select a dictation").foregroundStyle(.secondary)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.cleanedTranscript).lineLimit(2)
            HStack(spacing: 8) {
                Text(entry.timestamp, format: .relative(presentation: .named))
                if let app = entry.appName { Text("· \(app)") }
                Text("· \(entry.wordCount)w")
                Text("· \(Int(entry.wordsPerMinute)) wpm")
                if entry.delivery == .copied {
                    Image(systemName: "doc.on.clipboard").help("Copied to clipboard")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct HistoryDetail: View {
    let entry: TranscriptionEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.headline)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.cleanedTranscript, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .controlSize(.small)
                }

                HStack(spacing: 14) {
                    metric("\(entry.wordCount)", "words")
                    metric("\(Int(entry.wordsPerMinute))", "wpm")
                    metric(String(format: "%.0fs", entry.audioDurationSeconds), "spoken")
                    if let app = entry.appName { metric(app, "app") }
                }
                .font(.caption)

                transcriptBlock("Cleaned output", entry.cleanedTranscript)
                transcriptBlock("Raw transcript", entry.rawTranscript)
            }
            .padding(18)
        }
        .frame(minWidth: 280)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).fontWeight(.semibold)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func transcriptBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text.isEmpty ? "—" : text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Insights

struct InsightsView: View {
    @ObservedObject private var store = TranscriptionStore.shared

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: cols, spacing: 12) {
                    StatCard(value: "\(store.totalWords)", label: "Total words")
                    StatCard(value: "\(store.totalDictations)", label: "Dictations")
                    StatCard(value: String(format: "%.0f", store.totalAudioMinutes), label: "Minutes spoken")
                    StatCard(value: "\(Int(store.averageTrimRatio * 100))%", label: "Filler trimmed")
                }

                GroupBox("Last 14 days") {
                    Chart(store.lastDays(14)) { day in
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Words", day.words))
                            .foregroundStyle(Cobalt.blue)
                    }
                    .frame(height: 180)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                            AxisGridLine(); AxisValueLabel(format: .dateTime.day())
                        }
                    }
                    .padding(.top, 4)
                }

                if !store.topApps().isEmpty {
                    GroupBox("Where you dictate most") {
                        VStack(spacing: 6) {
                            ForEach(store.topApps(), id: \.app) { item in
                                HStack {
                                    Text(item.app)
                                    Spacer()
                                    Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Smarter insights are coming", systemImage: "sparkles")
                            .font(.headline)
                        Text("Because your whole history can grow to 100k+ words — far more than a local model can read at once — Cobalt Flow will build insights incrementally: each dictation gets a one-line AI summary the moment it's saved (a few hundred milliseconds, in the background), and those summaries roll up into themes. Nothing is ever batched or uploaded.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .navigationTitle("Insights")
    }
}
