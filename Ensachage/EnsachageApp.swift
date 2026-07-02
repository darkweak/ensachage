import SwiftUI

/// Owns the shared `AppModel`. Marked `@MainActor` because `AppModel`'s
/// initializer is main-actor isolated.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show/hide the Dock icon as windows open and close.
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [model] _ in
                model.refreshDockVisibility()
            }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [model] _ in
            // Defer until after the window is actually gone before re-checking.
            DispatchQueue.main.async { model.refreshDockVisibility() }
        }
    }
}

@main
struct EnsachageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var model: AppModel { delegate.model }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }

        Window("Journal — Ensachage 🍏", id: "journal") {
            MainView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 460)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 620)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// The menu bar icon. Its `task` is the app's launch hook (the label view is
/// instantiated immediately at launch, unlike the lazily-built menu content).
private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.isMonitoring ? "lock.shield.fill" : "lock.shield")
            .task {
                await model.bootstrap()
                if model.openJournalAtLaunch {
                    openWindow(id: "journal")
                    NSApplication.shared.activate()
                }
            }
    }
}
