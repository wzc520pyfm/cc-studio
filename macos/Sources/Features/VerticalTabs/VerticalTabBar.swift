import SwiftUI

/// A collapsible vertical tab bar sidebar for managing multiple terminal/browser tabs.
struct VerticalTabBar: View {
    @ObservedObject var tabManager: TabManager
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void

    @State private var hoveredTabId: UUID?

    private let collapsedWidth: CGFloat = 40
    private let expandedWidth: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            tabList
            Divider()
            bottomBar
        }
        .frame(width: tabManager.isCollapsed ? collapsedWidth : expandedWidth)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .animation(.easeInOut(duration: 0.2), value: tabManager.isCollapsed)
    }

    // MARK: - Tab List

    private var tabList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 1) {
                ForEach(tabManager.tabs) { tab in
                    VerticalTabItem(
                        tab: tab,
                        isActive: tab.id == tabManager.activeTabId,
                        isCollapsed: tabManager.isCollapsed,
                        isHovered: hoveredTabId == tab.id,
                        onSelect: { tabManager.selectTab(id: tab.id) },
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
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())

            if !tabManager.isCollapsed {
                Spacer()

                Text("\(tabManager.tabs.count) tab\(tabManager.tabs.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { tabManager.toggleCollapsed() }) {
                Image(systemName: tabManager.isCollapsed ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help(tabManager.isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
