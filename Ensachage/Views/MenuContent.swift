import SwiftUI

/// The dropdown shown from the menu bar icon.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.isMonitoring ? "Surveillance active" : "Surveillance arrêtée")

        let failures = model.history.entries.filter { $0.outcome == .failure }.count
        Text("\(failures) échec(s) enregistré(s)")

        Divider()

        Toggle("Surveiller l'écran de verrouillage", isOn: Binding(
            get: { model.isMonitoring },
            set: { model.setMonitoring($0) }
        ))

        Button("Ouvrir le journal…") {
            openWindow(id: "journal")
            NSApplication.shared.activate()
        }

        Button("Prendre une photo (test)") {
            model.captureTest()
        }

        Button("Réglages…") {
            openSettings()
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quitter Ensachage") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
