import SwiftUI

@main
struct DanskSvarApp: App {

    @StateObject private var settings: AppSettings
    @StateObject private var history: HistoryStore
    @StateObject private var engine: ConversationEngine

    @MainActor
    init() {
        let settings = AppSettings()
        let history = HistoryStore()
        let notifications = NotificationCoordinator()

        _settings = StateObject(wrappedValue: settings)
        _history = StateObject(wrappedValue: history)
        _engine = StateObject(wrappedValue: ConversationEngine(
            settings: settings,
            history: history,
            notifications: notifications
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(engine)
                .environment(\.locale, Locale(identifier: "da_DK"))
        }
    }
}
