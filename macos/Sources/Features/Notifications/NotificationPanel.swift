import SwiftUI

/// A dropdown panel showing recent notifications with actions.
struct NotificationPanel: View {
    @ObservedObject var notificationManager: NotificationManager
    let onGoToTab: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if notificationManager.notifications.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .frame(width: 320, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.headline)

            Spacer()

            if !notificationManager.notifications.isEmpty {
                Button("Clear All") {
                    notificationManager.clearAll()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No notifications")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Notification List

    private var notificationList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(notificationManager.notifications) { event in
                    NotificationRow(event: event) {
                        onGoToTab(event.tabId)
                        notificationManager.markAsRead(id: event.id)
                    }
                    Divider().padding(.leading, 44)
                }
            }
        }
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let event: NotificationManager.NotificationEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                notificationIcon
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(event.title)
                            .font(.system(size: 12, weight: event.isRead ? .regular : .semibold))
                            .lineLimit(1)

                        Spacer()

                        Text(event.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !event.body.isEmpty {
                        Text(event.body)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(event.isRead ? Color.clear : Color.accentColor.opacity(0.05))
    }

    @ViewBuilder
    private var notificationIcon: some View {
        switch event.type {
        case .bell:
            Image(systemName: "bell.fill")
                .foregroundStyle(.yellow)
        case .commandComplete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .commandError:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .desktopNotification:
            Image(systemName: "message.fill")
                .foregroundStyle(.blue)
        case .attention:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}
