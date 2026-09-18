import Foundation
import UserNotifications

/// Står for det ene svar, der ligger på hjemme- og låseskærmen ad gangen.
/// Når et nyt svar kommer, fjernes det forrige fra skærmen — men det er gemt
/// i historikken, inden det sker.
@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    /// Identifikator på den notifikation, der ligger på skærmen lige nu.
    private(set) var currentIdentifier: String?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorisation() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    var authorisationStatus: UNAuthorizationStatus {
        get async { await center.notificationSettings().authorizationStatus }
    }

    /// Lægger et svar på skærmen og rydder det forrige væk.
    /// - Parameter timeSensitive: bryder igennem Fokus og lyser skærmen op.
    func present(_ reply: ReplyRecord, timeSensitive: Bool) async {
        await retireCurrent()

        let content = UNMutableNotificationContent()
        content.title = reply.topic
        content.body = reply.body
        content.sound = nil
        content.threadIdentifier = "dansksvar.svar"
        content.categoryIdentifier = "dansksvar.svar"
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        content.relevanceScore = 1.0
        content.userInfo = ["replyID": reply.id.uuidString]

        let identifier = "dansksvar.svar.\(reply.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
            currentIdentifier = identifier
        } catch {
            currentIdentifier = nil
        }
    }

    /// Fjerner det aktuelle svar fra skærmen uden at røre historikken.
    func retireCurrent() async {
        guard let identifier = currentIdentifier else { return }
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        currentIdentifier = nil
    }

    func clearAll() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        currentIdentifier = nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Uden det her ville svaret ikke blive vist, mens appen er åben.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
