import SwiftUI

/// The selectable journal list. Selecting a row drives the detail pane.
struct HistorySidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: LogEntry.ID?

    var body: some View {
        List(selection: $selection) {
            if model.history.entries.isEmpty {
                Text("Aucun événement enregistré.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.history.entries) { entry in
                    LogRow(entry: entry)
                        .tag(entry.id)
                }
            }
        }
        .navigationTitle("Journal")
    }
}

/// One journal row: outcome icon, label, timestamp, and a camera badge when a
/// photo is attached.
struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.outcome.rowIcon)
                .foregroundStyle(entry.outcome.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.outcome.title)
                Text(entry.date, format: .dateTime.day().month().year().hour().minute().second())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if entry.imageFileName != nil {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
