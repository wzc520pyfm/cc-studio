import AppKit
import Combine

/// Aggregates and manages notifications across all terminal surfaces and tabs.
/// Tracks bell, desktop notification, and command completion events.
class NotificationManager: ObservableObject {
    /// A single notification event.
    struct NotificationEvent: Identifiable {
        let id: UUID
        let tabId: UUID
        let type: NotificationType
        let title: String
        let body: String
        let timestamp: Date
        var isRead: Bool

        init(tabId: UUID, type: NotificationType, title: String, body: String = "") {
            self.id = UUID()
            self.tabId = tabId
            self.type = type
            self.title = title
            self.body = body
            self.timestamp = Date()
            self.isRead = false
        }
    }

    enum NotificationType {
        case bell
        case commandComplete
        case commandError
        case desktopNotification
        case attention
    }

    @Published var notifications: [NotificationEvent] = []
    @Published var isPanelVisible: Bool = false

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    // MARK: - Adding Notifications

    func addNotification(
        tabId: UUID,
        type: NotificationType,
        title: String,
        body: String = ""
    ) {
        let event = NotificationEvent(
            tabId: tabId,
            type: type,
            title: title,
            body: body
        )
        notifications.insert(event, at: 0)

        if notifications.count > 100 {
            notifications = Array(notifications.prefix(100))
        }
    }

    func addBell(tabId: UUID, surfaceTitle: String) {
        addNotification(
            tabId: tabId,
            type: .bell,
            title: "Bell",
            body: surfaceTitle
        )
    }

    func addCommandComplete(tabId: UUID, surfaceTitle: String, exitCode: Int32? = nil) {
        let type: NotificationType = (exitCode ?? 0) == 0 ? .commandComplete : .commandError
        let statusText = exitCode.map { $0 == 0 ? "completed" : "failed (exit \($0))" } ?? "completed"
        addNotification(
            tabId: tabId,
            type: type,
            title: "Command \(statusText)",
            body: surfaceTitle
        )
    }

    func addDesktopNotification(tabId: UUID, title: String, body: String) {
        addNotification(
            tabId: tabId,
            type: .desktopNotification,
            title: title,
            body: body
        )
    }

    // MARK: - Reading/Clearing

    func markAsRead(id: UUID) {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
        }
    }

    func markAllAsRead(for tabId: UUID) {
        for index in notifications.indices where notifications[index].tabId == tabId {
            notifications[index].isRead = true
        }
    }

    func clearAll() {
        notifications.removeAll()
    }

    func clearNotifications(for tabId: UUID) {
        markAllAsRead(for: tabId)
    }

    // MARK: - Queries

    func unreadCount(for tabId: UUID) -> Int {
        notifications.filter { $0.tabId == tabId && !$0.isRead }.count
    }

    func notifications(for tabId: UUID) -> [NotificationEvent] {
        notifications.filter { $0.tabId == tabId }
    }

    func hasUnread(for tabId: UUID) -> Bool {
        notifications.contains { $0.tabId == tabId && !$0.isRead }
    }

    // MARK: - Panel

    func togglePanel() {
        isPanelVisible.toggle()
    }
}
