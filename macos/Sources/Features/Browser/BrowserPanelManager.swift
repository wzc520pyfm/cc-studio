import AppKit
import Combine

/// Manages browser panels that live alongside terminal splits.
/// Each panel has its own BrowserPaneView and can be positioned
/// relative to the terminal split area.
class BrowserPanelManager: ObservableObject {
    enum PanelPosition {
        case right
        case bottom
    }

    struct Panel: Identifiable, Equatable {
        let id: UUID
        let browserView: BrowserPaneView
        var position: PanelPosition

        static func == (lhs: Panel, rhs: Panel) -> Bool {
            lhs.id == rhs.id
        }
    }

    @Published var panels: [Panel] = []
    @Published var activePanelId: UUID?
    @Published var splitRatio: CGFloat = 0.5

    var hasRightPanel: Bool {
        panels.contains { $0.position == .right }
    }

    var hasBottomPanel: Bool {
        panels.contains { $0.position == .bottom }
    }

    var rightPanels: [Panel] {
        panels.filter { $0.position == .right }
    }

    var bottomPanels: [Panel] {
        panels.filter { $0.position == .bottom }
    }

    func addPanel(url: URL? = nil, position: PanelPosition = .right) -> Panel {
        let browserView = BrowserPaneView(url: url)
        let panel = Panel(
            id: UUID(),
            browserView: browserView,
            position: position
        )
        panels.append(panel)
        activePanelId = panel.id
        return panel
    }

    func removePanel(id: UUID) {
        panels.removeAll { $0.id == id }
        if activePanelId == id {
            activePanelId = panels.last?.id
        }
    }

    func removeAllPanels() {
        panels.removeAll()
        activePanelId = nil
    }
}
