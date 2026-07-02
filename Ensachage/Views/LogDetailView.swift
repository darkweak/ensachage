import SwiftUI

/// Detail of a single journal entry, including the captured photo when present.
struct LogDetailView: View {
    @Environment(AppModel.self) private var model
    let entry: LogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heading
                shareActions
                Divider()
                photoSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Détail")
    }

    /// Send the entry (photo + summary) to the owner via AirDrop, Mail, etc.
    private var shareActions: some View {
        HStack(spacing: 12) {
            if let url = model.history.imageURL(for: entry) {
                ShareLink(
                    "Partager (AirDrop, Mail…)",
                    item: url,
                    subject: Text("Ensachage 🍏 — \(entry.outcome.title)"),
                    message: Text(model.shareSummary(for: entry))
                )
            } else {
                ShareLink(
                    "Partager (AirDrop, Mail…)",
                    item: model.shareSummary(for: entry)
                )
            }

            Button("Envoyer au propriétaire", systemImage: "envelope") {
                model.emailToOwner(for: entry)
            }
            .disabled(model.settings.ownerEmail.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(model.settings.ownerEmail.isEmpty
                  ? "Définissez l'adresse du propriétaire dans Réglages."
                  : "Envoyer un e-mail à \(model.settings.ownerEmail)")
        }
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.outcome.detailIcon)
                .font(.largeTitle)
                .foregroundStyle(entry.outcome.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.outcome.title)
                    .font(.title2.bold())
                Text(entry.date, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute().second())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        if let url = model.history.imageURL(for: entry), let image = NSImage(contentsOf: url) {
            Text("Photo capturée").font(.headline)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.separator)
                )
        } else if entry.outcome == .success {
            Label("Aucune photo (déverrouillage réussi).", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            ContentUnavailableView(
                "Aucune photo disponible",
                systemImage: "camera.badge.ellipsis",
                description: Text("La caméra n'était pas autorisée ou indisponible au moment de la tentative.")
            )
            .frame(height: 240)
        }
    }
}
