import SwiftUI

/// Context menu for right-clicking on a vertical tab item.
struct VerticalTabContextMenu: View {
    let tab: TabManager.Tab
    @ObservedObject var tabManager: TabManager
    let onCloseTab: (UUID) -> Void

    var body: some View {
        Button("Close Tab") {
            onCloseTab(tab.id)
        }

        Button("Close Other Tabs") {
            tabManager.closeOtherTabs(except: tab.id)
        }
        .disabled(tabManager.tabs.count <= 1)

        Button("Close Tabs to the Right") {
            tabManager.closeTabsToTheRight(of: tab.id)
        }
        .disabled(isLastTab)

        Divider()

        if let index = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) {
            Button("Move Up") {
                tabManager.moveTab(id: tab.id, to: index - 1)
            }
            .disabled(index == 0)

            Button("Move Down") {
                tabManager.moveTab(id: tab.id, to: index + 1)
            }
            .disabled(index == tabManager.tabs.count - 1)
        }

        Divider()

        Button("Copy Working Directory") {
            if !tab.pwd.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.pwd, forType: .string)
            }
        }
        .disabled(tab.pwd.isEmpty)
    }

    private var isLastTab: Bool {
        guard let index = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else { return true }
        return index == tabManager.tabs.count - 1
    }
}
