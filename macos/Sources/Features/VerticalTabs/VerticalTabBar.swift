import SwiftUI

/// A collapsible vertical tab bar sidebar showing project-grouped terminal sessions.
struct VerticalTabBar: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var notificationManager: NotificationManager
    let onSelectTab: (UUID) -> Void
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onGoToNotificationTab: (UUID) -> Void

    @State private var hoveredTabId: UUID?
    @State private var collapsedProjects: Set<String> = []

    private let collapsedWidth: CGFloat = 40
    private let expandedWidth: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            tabList
            Divider()
            bottomBar
        }
        .frame(width: tabManager.isCollapsed ? collapsedWidth : expandedWidth)
        .clipped()
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    // MARK: - Tab List

    private var tabList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                if tabManager.isCollapsed {
                    collapsedTabList
                } else {
                    expandedProjectList
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var collapsedTabList: some View {
        ForEach(tabManager.tabs) { tab in
            VerticalTabItem(
                tab: tab,
                isActive: tab.id == tabManager.activeTabId,
                isCollapsed: true,
                isHovered: hoveredTabId == tab.id,
                onSelect: { onSelectTab(tab.id) },
                onClose: { onCloseTab(tab.id) }
            )
            .onHover { isHovering in
                hoveredTabId = isHovering ? tab.id : nil
            }
        }
    }

    private var expandedProjectList: some View {
        ForEach(tabManager.projectGroups, id: \.projectName) { group in
            VStack(spacing: 0) {
                projectHeader(group)
                if !collapsedProjects.contains(group.projectName) {
                    ForEach(group.tabs) { tab in
                        VerticalTabItem(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTabId,
                            isCollapsed: false,
                            isHovered: hoveredTabId == tab.id,
                            onSelect: { onSelectTab(tab.id) },
                            onClose: { onCloseTab(tab.id) }
                        )
                        .onHover { isHovering in
                            hoveredTabId = isHovering ? tab.id : nil
                        }
                        .contextMenu {
                            VerticalTabContextMenu(
                                tab: tab,
                                tabManager: tabManager,
                                onCloseTab: onCloseTab
                            )
                        }
                        .padding(.leading, 8)
                    }
                }
            }
        }
    }

    private func projectHeader(_ group: TabManager.ProjectGroup) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if collapsedProjects.contains(group.projectName) {
                    collapsedProjects.remove(group.projectName)
                } else {
                    collapsedProjects.insert(group.projectName)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsedProjects.contains(group.projectName)
                      ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(group.projectName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(group.tabs.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Group {
            if tabManager.isCollapsed {
                collapsedBottomBar
            } else {
                expandedBottomBar
            }
        }
    }

    private var collapsedBottomBar: some View {
        VStack(spacing: 4) {
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("New tab")

            notificationBell

            Button(action: { tabManager.toggleCollapsed() }) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("Expand sidebar")
        }
        .padding(.vertical, 6)
    }

    private var expandedBottomBar: some View {
        HStack(spacing: 6) {
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("New tab")

            notificationBell

            Spacer()

            Button(action: { tabManager.toggleCollapsed() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("Collapse sidebar")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var notificationBell: some View {
        Button(action: { notificationManager.togglePanel() }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: notificationManager.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(notificationManager.unreadCount > 0 ? .yellow : .primary)

                if notificationManager.unreadCount > 0 {
                    Text("\(min(notificationManager.unreadCount, 99))")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.red))
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .help("Notifications")
        .popover(isPresented: $notificationManager.isPanelVisible, arrowEdge: .trailing) {
            NotificationPanel(
                notificationManager: notificationManager,
                onGoToTab: { tabId in
                    notificationManager.isPanelVisible = false
                    onGoToNotificationTab(tabId)
                }
            )
        }
    }
}
