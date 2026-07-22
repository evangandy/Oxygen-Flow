import SwiftUI

/// The personal dictionary tab. Lets the user teach Oxygen Flow names, acronyms, and jargon it
/// wouldn't otherwise get right — both how to *hear* them (fed to whisper as vocabulary bias) and
/// what they *mean* (fed to the cleanup model as a glossary), e.g. "10-K" → "SEC annual report
/// filing" so a follow-up like "what are the main sections of a 10-K" is understood correctly
/// instead of being mangled or treated as nonsense.
struct DictionaryView: View {
    @ObservedObject private var store = DictionaryStore.shared

    @State private var newTerm = ""
    @State private var newNote = ""

    var body: some View {
        FlowPage(title: "Dictionary") {
            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "Add a word")
                FlowCard {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 8) {
                            TextField("Term or name (e.g. \"10-K\")", text: $newTerm)
                                .flowFieldStyle()
                                .onSubmit(addEntry)
                            TextField("Optional note — what it means or context (e.g. \"SEC annual report filing\")", text: $newNote)
                                .flowFieldStyle()
                                .onSubmit(addEntry)
                        }
                        Button("Add") { addEntry() }
                            .buttonStyle(FlowProminentButtonStyle())
                            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("The term is used to bias speech-to-text toward the exact spelling. The note (optional) is given to the cleanup model as context, so it understands domain jargon instead of guessing or \u{201C}correcting\u{201D} it away.")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "\(store.entries.count) word\(store.entries.count == 1 ? "" : "s")")
                FlowCard {
                    if store.entries.isEmpty {
                        Text("No words yet. Add names, acronyms, or jargon you say often — proper nouns, product names, financial or technical terms.")
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                    } else {
                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().overlay(Palette.surfaceBorder) }
                            entryRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: DictionaryEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.term).fontWeight(.medium).foregroundStyle(Palette.textPrimary)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            Button {
                store.delete(entry)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func addEntry() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        if store.add(term: term, note: newNote) {
            newTerm = ""
            newNote = ""
        }
    }
}
