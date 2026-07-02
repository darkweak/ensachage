import SwiftUI

/// The journal browser window: a list of unlock events on the left, the selected
/// event's detail (including the captured photo) on the right.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var selection: LogEntry.ID?

    var body: some View {
        NavigationSplitView {
            HistorySidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            detail
        }
        .navigationTitle("Ensachage 🍏")
        .navigationSubtitle(model.isMonitoring ? "Surveillance active" : "Surveillance arrêtée")
        .toolbar {
            ToolbarItem(placement: .status) {
                Label(model.isMonitoring ? "Surveillance active" : "Surveillance arrêtée",
                      systemImage: model.isMonitoring ? "shield.lefthalf.filled" : "shield.slash")
                    .foregroundStyle(model.isMonitoring ? .green : .secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Photo de test", systemImage: "camera") {
                    model.captureTest()
                }
            }
            ToolbarItem {
                Button("Réglages", systemImage: "gearshape") {
                    openSettings()
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if !model.cameraAuthorized {
                cameraBanner
            }
        }
    }

    private var cameraBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.badge.ellipsis")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Caméra non autorisée").font(.headline)
                Text("Sans accès caméra, aucune photo ne sera prise lors des échecs de déverrouillage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Autoriser") {
                Task { _ = await model.requestCameraAccess() }
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection,
           let entry = model.history.entries.first(where: { $0.id == id }) {
            LogDetailView(entry: entry)
        } else {
            ContentUnavailableView(
                "Aucune entrée sélectionnée",
                systemImage: "list.bullet.rectangle",
                description: Text("Sélectionnez une ligne du journal pour afficher les détails et la photo.")
            )
        }
    }
}
