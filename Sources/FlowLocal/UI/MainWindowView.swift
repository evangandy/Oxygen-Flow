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
            case .insights: return "chart.bar"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch section {
            case .dashboard: DashboardView(controller: controller)
            case .history: HistoryView()
            case .insights: InsightsView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .tint(Palette.accent)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var store = TranscriptionStore.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: statusTitle)
                Button(controller.state == .listening ? "Stop Dictation" : "Start Dictation") {
                    controller.toggle()
                }
                .disabled(!controller.isReady && controller.state == .idle)
            }

            Section("Today") {
                LabeledContent("Words today", value: "\(store.todayWordCount)")
                LabeledContent("Average words / min", value: store.averageWPM > 0 ? "\(Int(store.averageWPM))" : "—")
                LabeledContent("Day streak", value: "\(store.streakDays)")
                LabeledContent("Time saved", value: timeSaved)
            }

            if let err = controller.lastError {
                Section {
                    Text(err).foregroundStyle(.red)
                    Button("Grant Accessibility & Retry") {
                        HotkeyManager.requestAccessibilityPermission()
                        controller.retryHotkey()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dashboard")
    }

    private var timeSaved: String {
        let mins = store.timeSavedMinutes
        if mins < 1 { return "—" }
        if mins < 60 { return "\(Int(mins))m" }
        return String(format: "%.1fh", mins / 60)
    }

    private var statusTitle: String {
        switch controller.state {
        case .idle: return controller.isReady ? "Ready — \(AppSettings.shared.hotkeyDisplayString)" : "Loading model…"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .cleaning: return "Formatting"
        case .copied: return "Copied to clipboard"
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
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryDetail: View {
    let entry: TranscriptionEntry

    var body: some View {
        Form {
            Section {
                LabeledContent("When", value: entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Words", value: "\(entry.wordCount)")
                LabeledContent("Words / min", value: "\(Int(entry.wordsPerMinute))")
                LabeledContent("Spoken", value: String(format: "%.0fs", entry.audioDurationSeconds))
                if let app = entry.appName { LabeledContent("App", value: app) }
            }
            Section("Cleaned output") {
                Text(entry.cleanedTranscript.isEmpty ? "—" : entry.cleanedTranscript).textSelection(.enabled)
            }
            Section("Raw transcript") {
                Text(entry.rawTranscript.isEmpty ? "—" : entry.rawTranscript).textSelection(.enabled)
            }
            Section {
                Button("Copy cleaned text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.cleanedTranscript, forType: .string)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 260)
    }
}

// MARK: - Insights

struct InsightsView: View {
    @ObservedObject private var store = TranscriptionStore.shared

    var body: some View {
        Form {
            Section("Totals") {
                LabeledContent("Total words", value: "\(store.totalWords)")
                LabeledContent("Dictations", value: "\(store.totalDictations)")
                LabeledContent("Minutes spoken", value: String(format: "%.0f", store.totalAudioMinutes))
                LabeledContent("Filler trimmed", value: "\(Int(store.averageTrimRatio * 100))%")
            }

            Section("Last 14 days") {
                Chart(store.lastDays(14)) { day in
                    BarMark(x: .value("Day", day.date, unit: .day),
                            y: .value("Words", day.words))
                        .foregroundStyle(Palette.accent)
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisGridLine(); AxisValueLabel(format: .dateTime.day())
                    }
                }
            }

            if !store.topApps().isEmpty {
                Section("Where you dictate most") {
                    ForEach(store.topApps(), id: \.app) { item in
                        LabeledContent(item.app, value: "\(item.count)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Insights")
    }
}
