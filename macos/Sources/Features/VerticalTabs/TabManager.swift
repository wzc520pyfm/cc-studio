import AppKit
import Combine
import GhosttyKit
import SwiftUI

/// Manages the collection of tabs within a single window.
/// Each tab owns its own SplitTree of terminal surfaces.
class TabManager: ObservableObject {
    /// A single tab entry within the tab manager.
    struct Tab: Identifiable, Equatable {
        let id: UUID
        var title: String
        var icon: String
        var pwd: String
        var projectPath: String
        var notificationCount: Int
        var isFlashing: Bool
        var surfaceTree: SplitTree<Ghostty.SurfaceView>
        var focusedSurface: Ghostty.SurfaceView?

        init(surfaceTree: SplitTree<Ghostty.SurfaceView>, title: String = "Terminal") {
            self.id = UUID()
            self.title = title
            self.icon = "terminal"
            self.pwd = ""
            self.projectPath = ""
            self.notificationCount = 0
            self.isFlashing = false
            self.surfaceTree = surfaceTree
            self.focusedSurface = surfaceTree.first
        }

        var projectName: String {
            if projectPath.isEmpty {
                return pwd.isEmpty ? "Terminal" : (pwd as NSString).lastPathComponent
            }
            return (projectPath as NSString).lastPathComponent
        }

        static func == (lhs: Tab, rhs: Tab) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// A group of tabs sharing the same project directory.
    struct ProjectGroup: Equatable {
        let projectName: String
        let projectPath: String
        var tabs: [Tab]
    }

    @Published var tabs: [Tab] = []
    @Published var activeTabId: UUID?
    @Published var isCollapsed: Bool = false

    var activeTab: Tab? {
        guard let id = activeTabId else { return tabs.first }
        return tabs.first(where: { $0.id == id })
    }

    var activeTabIndex: Int? {
        guard let id = activeTabId else { return tabs.isEmpty ? nil : 0 }
        return tabs.firstIndex(where: { $0.id == id })
    }

    /// Tabs grouped by project directory, preserving insertion order.
    var projectGroups: [ProjectGroup] {
        var groups: [String: ProjectGroup] = [:]
        var order: [String] = []
        for tab in tabs {
            let key = tab.projectPath.isEmpty ? (tab.pwd.isEmpty ? "~" : tab.pwd) : tab.projectPath
            let name = tab.projectName
            if groups[key] != nil {
                groups[key]!.tabs.append(tab)
            } else {
                groups[key] = ProjectGroup(projectName: name, projectPath: key, tabs: [tab])
                order.append(key)
            }
        }
        return order.compactMap { groups[$0] }
    }

    // MARK: - Tab Operations

    func addTab(_ tab: Tab) {
        tabs.append(tab)
        activeTabId = tab.id
    }

    func insertTab(_ tab: Tab, after existingId: UUID) {
        if let index = tabs.firstIndex(where: { $0.id == existingId }) {
            tabs.insert(tab, at: min(index + 1, tabs.count))
        } else {
            tabs.append(tab)
        }
        activeTabId = tab.id
    }

    func removeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = activeTabId == id
        tabs.remove(at: index)

        if wasActive && !tabs.isEmpty {
            let newIndex = min(index, tabs.count - 1)
            activeTabId = tabs[newIndex].id
        } else if tabs.isEmpty {
            activeTabId = nil
        }
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        clearNotifications(for: id)
    }

    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let tab = tabs[index]
        activeTabId = tab.id
        clearNotifications(for: tab.id)
    }

    func selectNextTab() {
        guard let currentIndex = activeTabIndex, !tabs.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        selectTab(at: nextIndex)
    }

    func selectPreviousTab() {
        guard let currentIndex = activeTabIndex, !tabs.isEmpty else { return }
        let prevIndex = (currentIndex - 1 + tabs.count) % tabs.count
        selectTab(at: prevIndex)
    }

    func moveTab(id: UUID, to newIndex: Int) {
        guard let oldIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(newIndex, tabs.count - 1))
        guard oldIndex != clamped else { return }
        let tab = tabs.remove(at: oldIndex)
        tabs.insert(tab, at: clamped)
    }

    func updateTab(id: UUID, mutate: (inout Tab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tabs[index])
    }

    // MARK: - Tab Lookup

    func tab(for surfaceView: Ghostty.SurfaceView) -> Tab? {
        tabs.first(where: { $0.surfaceTree.contains(surfaceView) })
    }

    func tabIndex(for surfaceView: Ghostty.SurfaceView) -> Int? {
        tabs.firstIndex(where: { $0.surfaceTree.contains(surfaceView) })
    }

    // MARK: - Notifications

    func addNotification(for tabId: UUID) {
        guard activeTabId != tabId else { return }
        updateTab(id: tabId) { tab in
            tab.notificationCount += 1
            tab.isFlashing = true
        }
    }

    func clearNotifications(for tabId: UUID) {
        updateTab(id: tabId) { tab in
            tab.notificationCount = 0
            tab.isFlashing = false
        }
    }

    // MARK: - Close Operations

    func closeTab(id: UUID) {
        removeTab(id: id)
    }

    func closeOtherTabs(except id: UUID) {
        tabs.removeAll(where: { $0.id != id })
        activeTabId = id
    }

    func closeTabsToTheRight(of id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.removeSubrange((index + 1)...)
        if let activeId = activeTabId, !tabs.contains(where: { $0.id == activeId }) {
            activeTabId = id
        }
    }

    // MARK: - Sidebar

    func toggleCollapsed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isCollapsed.toggle()
        }
    }
}
