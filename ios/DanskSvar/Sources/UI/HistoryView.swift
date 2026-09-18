import SwiftUI

/// Alle svar, der har været vist — også dem, der er ryddet væk fra låseskærmen.
struct HistoryView: View {

    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            Group {
                if history.replies.isEmpty {
                    ContentUnavailableView(
                        "Ingen svar endnu",
                        systemImage: "text.bubble",
                        description: Text("Her samler de svar sig, som har været vist på din låseskærm.")
                    )
                } else {
                    List {
                        ForEach(history.sorted) { reply in
                            row(reply)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Historik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Færdig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ryd alt", role: .destructive) { confirmingDeleteAll = true }
                        .disabled(history.replies.isEmpty)
                }
            }
            .confirmationDialog(
                "Slet hele historikken?",
                isPresented: $confirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Slet alle svar", role: .destructive) { history.deleteAll() }
                Button("Fortryd", role: .cancel) {}
            } message: {
                Text("Alle gemte svar slettes fra din iPhone. Det kan ikke fortrydes.")
            }
        }
    }

    private func row(_ reply: ReplyRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(reply.topic).font(.headline)
                Spacer()
                Text(reply.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(reply.body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if reply.retiredAt != nil {
                    Label("Fjernet fra skærmen", systemImage: "checkmark.circle")
                } else {
                    Label("Vises nu", systemImage: "bell.badge")
                }
                if reply.source == .local {
                    Label(reply.source.danishLabel, systemImage: "wifi.slash")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        let sorted = history.sorted
        for index in offsets where index < sorted.count {
            history.delete(sorted[index].id)
        }
    }
}
