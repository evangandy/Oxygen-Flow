import SwiftUI

/// Voice-triggered macros: say the trigger phrase as your entire dictation and Oxygen Flow
/// pastes the expansion verbatim instead of running cleanup — e.g. trigger "my email signature",
/// expansion the actual signature block. Mirrors Wispr Flow's snippets feature.
struct SnippetsView: View {
    @ObservedObject private var store = SnippetStore.shared

    @State private var newTrigger = ""
    @State private var newExpansion = ""

    var body: some View {
        FlowPage(title: "Snippets") {
            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "Add a snippet")
                FlowCard {
                    TextField("Trigger phrase (say this exactly)", text: $newTrigger)
                        .flowFieldStyle()
                    TextField("Expansion text to paste", text: $newExpansion, axis: .vertical)
                        .flowFieldStyle()
                        .lineLimit(3...6)
                    HStack {
                        Spacer()
                        Button("Add") { addEntry() }
                            .buttonStyle(FlowProminentButtonStyle())
                            .disabled(newTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                                      || newExpansion.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("When your entire dictation matches a trigger phrase (case and trailing punctuation ignored), Oxygen Flow pastes the expansion instead of the cleaned-up transcript. Good for signatures, addresses, or boilerplate you say often.")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                FlowSectionLabel(title: "\(store.entries.count) snippet\(store.entries.count == 1 ? "" : "s")")
                FlowCard {
                    if store.entries.isEmpty {
                        Text("No snippets yet. Try a trigger like \u{201C}my email signature\u{201D} with your signature block as the expansion.")
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

    private func entryRow(_ entry: SnippetEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\u{201C}\(entry.trigger)\u{201D}").fontWeight(.medium).foregroundStyle(Palette.textPrimary)
                Text(entry.expansion).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
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
        if store.add(trigger: newTrigger, expansion: newExpansion) {
            newTrigger = ""
            newExpansion = ""
        }
    }
}
