import AppKit
import Combine

/// Manages browser panels that live alongside terminal splits.
/// Each panel has its own BrowserPaneView and is attached to a specific
/// terminal surface on one of four zones (left/right/top/bottom),
/// matching how terminal splits work.
class BrowserPanelManager: ObservableObject {
    /// Where a browser panel is positioned. Container positions are
    /// relative to the entire terminal area; attached positions are
    /// relative to a specific terminal surface.
    enum PanelPosition: Equatable {
        case container(ContainerSide)
        case attached(surfaceId: UUID, side: AttachSide)

        enum ContainerSide: Equatable {
            case right
            case bottom
        }

        enum AttachSide: Equatable {
            case left
            case right
            case top
            case bottom
        }
    }

    struct Panel: Identifiable, Equatable {
        let id: UUID
        let browserView: BrowserPaneView
        var position: PanelPosition
        var ratio: CGFloat = 0.5

        static func == (lhs: Panel, rhs: Panel) -> Bool {
            lhs.id == rhs.id && lhs.position == rhs.position && lhs.ratio == rhs.ratio
        }
    }

    @Published var panels: [Panel] = []
    @Published var activePanelId: UUID?

    var containerRightPanels: [Panel] {
        panels.filter {
            if case .container(.right) = $0.position { return true }
            return false
        }
    }

    var containerBottomPanels: [Panel] {
        panels.filter {
            if case .container(.bottom) = $0.position { return true }
            return false
        }
    }

    func attachedPanels(for surfaceId: UUID, side: PanelPosition.AttachSide) -> [Panel] {
        panels.filter {
            if case .attached(let sid, let s) = $0.position, sid == surfaceId, s == side {
                return true
            }
            return false
        }
    }

    func attachedPanels(for surfaceId: UUID) -> [Panel] {
        panels.filter {
            if case .attached(let sid, _) = $0.position, sid == surfaceId { return true }
            return false
        }
    }

    func addPanel(url: URL? = nil, position: PanelPosition = .container(.right)) -> Panel {
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

    func movePanel(id: UUID, to position: PanelPosition) {
        guard let index = panels.firstIndex(where: { $0.id == id }) else { return }
        panels[index].position = position
        objectWillChange.send()
    }

    func moveAllPanels(to position: PanelPosition) {
        for i in panels.indices {
            panels[i].position = position
        }
        objectWillChange.send()
    }

    func updateRatio(id: UUID, ratio: CGFloat) {
        guard let index = panels.firstIndex(where: { $0.id == id }) else { return }
        panels[index].ratio = max(0.15, min(0.85, ratio))
    }
}
