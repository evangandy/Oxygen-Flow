import Charts
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var controller: DictationController
    @State private var section: Section = .dashboard

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case history = "History"
        case insights = "Insights"
        case dictionary = "Dictionary"
        case snippets = "Snippets"
        case settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .dashboard: return "waveform"
            case .history: return "text.bubble"
            case .insights: return "chart.bar"
            case .dictionary: return "character.book.closed"
            case .snippets: return "text.badge.plus"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                // Let the system sidebar handle selected/unselected text color automatically —
                // it already picks a legible color against its own selection highlight.
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Palette.sidebarBackground)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch section {
            case .dashboard: DashboardView(controller: controller)
            case .history: HistoryView()
            case .insights: InsightsView()
            case .dictionary: DictionaryView()
            case .snippets: SnippetsView()
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
        FlowPage(title: "Dashboard") {
            FlowCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        FlowSectionLabel(title: "Status")
                        Text(statusTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Spacer()
                    Button(controller.state == .listening ? "Stop Dictation" : "Start Dictation") {
                        controller.toggle()
                    }
                    .buttonStyle(FlowProminentButtonStyle())
                    .disabled(!controller.isReady && controller.state == .idle)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "Today")
                FlowCard {
                    statRow("Words today", "\(store.todayWordCount)")
                    Divider().overlay(Palette.surfaceBorder)
                    statRow("Average words / min", store.averageWPM > 0 ? "\(Int(store.averageWPM))" : "—")
                    Divider().overlay(Palette.surfaceBorder)
                    statRow("Day streak", "\(store.streakDays)")
                    Divider().overlay(Palette.surfaceBorder)
                    statRow("Time saved", timeSaved)
                }
            }

            if let err = controller.lastError {
                VStack(alignment: .leading, spacing: 10) {
                    FlowSectionLabel(title: "Needs attention")
                    FlowCard {
                        Text(err).foregroundStyle(Palette.danger)
                        Button("Grant Accessibility & Retry") {
                            HotkeyManager.requestAccessibilityPermission()
                            controller.retryHotkey()
                        }
                        .buttonStyle(FlowProminentButtonStyle())
                    }
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Palette.textPrimary).fontWeight(.medium)
        }
        .font(.system(size: 13))
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
        case .rewriting: return "Rewriting selection"
        case .rewritten: return "Rewrote selection"
        case .error(let m): return m
        }
    }
}

/// A warm, rounded button matching the card language — replaces the default bordered-prominent
/// macOS button so primary actions read as part of the same product as the chip.
struct FlowProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Palette.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
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
                .background(Palette.windowBackground)
            } else {
                List(store.entries, selection: $selection) { entry in
                    HistoryRow(entry: entry).tag(entry.id)
                        .listRowBackground(Palette.windowBackground)
                }
                .scrollContentBackground(.hidden)
                .background(Palette.windowBackground)
            }
        }
        .navigationTitle("History")
        .inspector(isPresented: .constant(selection != nil)) {
            if let entry = store.entries.first(where: { $0.id == selection }) {
                HistoryDetail(entry: entry)
            } else {
                Text("Select a dictation").foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.cleanedTranscript).lineLimit(2).foregroundStyle(Palette.textPrimary)
            HStack(spacing: 6) {
                FlowBadge(text: entry.timestamp.formatted(.relative(presentation: .named)))
                if let app = entry.appName { FlowBadge(text: app, tinted: true) }
                FlowBadge(text: "\(entry.wordCount)w")
                FlowBadge(text: "\(Int(entry.wordsPerMinute)) wpm")
                if entry.delivery == .copied {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .help("Copied to clipboard")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryDetail: View {
    let entry: TranscriptionEntry

    var body: some View {
        FlowPage(title: "Dictation") {
            FlowCard {
                statRow("When", entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                statRow("Words", "\(entry.wordCount)")
                statRow("Words / min", "\(Int(entry.wordsPerMinute))")
                statRow("Spoken", String(format: "%.0fs", entry.audioDurationSeconds))
                if let app = entry.appName { statRow("App", app) }
            }

            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "Cleaned output")
                FlowCard {
                    Text(entry.cleanedTranscript.isEmpty ? "—" : entry.cleanedTranscript)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "Raw transcript")
                FlowCard {
                    Text(entry.rawTranscript.isEmpty ? "—" : entry.rawTranscript)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                }
            }

            Button("Copy cleaned text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.cleanedTranscript, forType: .string)
            }
            .buttonStyle(FlowProminentButtonStyle())
        }
        .frame(minWidth: 300)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Palette.textPrimary).fontWeight(.medium)
        }
        .font(.system(size: 13))
    }
}

// MARK: - Insights

struct InsightsView: View {
    @ObservedObject private var store = TranscriptionStore.shared

    var body: some View {
        FlowPage(title: "Insights") {
            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "Totals")
                FlowCard {
                    statRow("Total words", "\(store.totalWords)")
                    Divider().overlay(Palette.surfaceBorder)
                    statRow("Dictations", "\(store.totalDictations)")
                    Divider().overlay(Palette.surfaceBorder)
                    statRow("Minutes spoken", String(format: "%.0f", store.totalAudioMinutes))
                    Divider().overlay(Palette.surfaceBorder)
                    statRow("Filler trimmed", "\(Int(store.averageTrimRatio * 100))%")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "Last 14 days")
                FlowCard {
                    Chart(store.lastDays(14)) { day in
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Words", day.words))
                            .foregroundStyle(Palette.accent)
                            .cornerRadius(3)
                    }
                    .frame(height: 160)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                            AxisGridLine().foregroundStyle(Palette.surfaceBorder)
                            AxisValueLabel(format: .dateTime.day())
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(Palette.surfaceBorder)
                            AxisValueLabel().foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }

            if !store.topApps().isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    FlowSectionLabel(title: "Where you dictate most")
                    FlowCard {
                        ForEach(Array(store.topApps().enumerated()), id: \.element.app) { index, item in
                            if index > 0 { Divider().overlay(Palette.surfaceBorder) }
                            statRow(item.app, "\(item.count)")
                        }
                    }
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Palette.textPrimary).fontWeight(.medium)
        }
        .font(.system(size: 13))
    }
}
