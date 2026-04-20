import SwiftUI
import UniformTypeIdentifiers

/// A single operation within the split tree.
///
/// Rather than binding the split tree (which is immutable), any mutable operations are
/// exposed via this enum to the embedder to handle.
enum TerminalSplitOperation {
    case resize(Resize)
    case drop(Drop)
    case attachBrowser(AttachBrowser)

    struct Resize {
        let node: SplitTree<Ghostty.SurfaceView>.Node
        let ratio: Double
    }

    struct Drop {
        /// The surface being dragged.
        let payload: Ghostty.SurfaceView

        /// The surface it was dragged onto
        let destination: Ghostty.SurfaceView

        /// The zone it was dropped to determine how to split the destination.
        let zone: TerminalSplitDropZone
    }

    struct AttachBrowser {
        /// The browser panel ID being dragged.
        let panelId: UUID

        /// The terminal surface it was dropped onto.
        let destination: Ghostty.SurfaceView

        /// Which side of the destination to attach to.
        let zone: TerminalSplitDropZone
    }
}

struct TerminalSplitTreeView: View {
    let tree: SplitTree<Ghostty.SurfaceView>
    let browserPanelManager: BrowserPanelManager
    let onCloseBrowserPanel: (UUID) -> Void
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            TerminalSplitSubtreeView(
                node: node,
                isRoot: node == tree.root,
                browserPanelManager: browserPanelManager,
                onCloseBrowserPanel: onCloseBrowserPanel,
                action: action)
            // This is necessary because we can't rely on SwiftUI's implicit
            // structural identity to detect changes to this view. Due to
            // the tree structure of splits it could result in bad behaviors.
            // See: https://github.com/ghostty-org/ghostty/issues/7546
            .id(node.structuralIdentity)
        }
    }
}

private struct TerminalSplitSubtreeView: View {
    @EnvironmentObject var ghostty: Ghostty.App

    let node: SplitTree<Ghostty.SurfaceView>.Node
    var isRoot: Bool = false
    let browserPanelManager: BrowserPanelManager
    let onCloseBrowserPanel: (UUID) -> Void
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        switch node {
        case .leaf(let leafView):
            TerminalSplitLeaf(
                surfaceView: leafView,
                isSplit: !isRoot,
                browserPanelManager: browserPanelManager,
                onCloseBrowserPanel: onCloseBrowserPanel,
                action: action)

        case .split(let split):
            let splitViewDirection: SplitViewDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            SplitView(
                splitViewDirection,
                .init(get: {
                    CGFloat(split.ratio)
                }, set: {
                    action(.resize(.init(node: node, ratio: $0)))
                }),
                dividerColor: ghostty.config.splitDividerColor,
                resizeIncrements: .init(width: 1, height: 1),
                left: {
                    TerminalSplitSubtreeView(
                        node: split.left,
                        browserPanelManager: browserPanelManager,
                        onCloseBrowserPanel: onCloseBrowserPanel,
                        action: action)
                },
                right: {
                    TerminalSplitSubtreeView(
                        node: split.right,
                        browserPanelManager: browserPanelManager,
                        onCloseBrowserPanel: onCloseBrowserPanel,
                        action: action)
                },
                onEqualize: {
                    guard let surface = node.leftmostLeaf().surface else { return }
                    ghostty.splitEqualize(surface: surface)
                }
            )
        }
    }
}

private struct TerminalSplitLeaf: View {
    let surfaceView: Ghostty.SurfaceView
    let isSplit: Bool
    @ObservedObject var browserPanelManager: BrowserPanelManager
    let onCloseBrowserPanel: (UUID) -> Void
    let action: (TerminalSplitOperation) -> Void

    @State private var dropState: DropState = .idle
    @State private var isSelfDragging: Bool = false

    init(
        surfaceView: Ghostty.SurfaceView,
        isSplit: Bool,
        browserPanelManager: BrowserPanelManager,
        onCloseBrowserPanel: @escaping (UUID) -> Void,
        action: @escaping (TerminalSplitOperation) -> Void
    ) {
        self.surfaceView = surfaceView
        self.isSplit = isSplit
        self.browserPanelManager = browserPanelManager
        self.onCloseBrowserPanel = onCloseBrowserPanel
        self.action = action
    }

    var body: some View {
        AttachedBrowserWrapper(
            surfaceView: surfaceView,
            browserPanelManager: browserPanelManager,
            onCloseBrowserPanel: onCloseBrowserPanel
        ) {
            terminalContent
        }
    }

    private var terminalContent: some View {
        GeometryReader { geometry in
            Ghostty.InspectableSurface(
                surfaceView: surfaceView,
                isSplit: isSplit)
            .background {
                // If we're dragging ourself, we hide the entire drop zone. This makes
                // it so that a released drop animates back to its source properly
                // so it is a proper invalid drop zone.
                if !isSelfDragging {
                    Color.clear
                        .onDrop(of: [.ghosttySurfaceId, .ghosttyBrowserPanelId], delegate: SplitDropDelegate(
                            dropState: $dropState,
                            viewSize: geometry.size,
                            destinationSurface: surfaceView,
                            action: action
                        ))
                }
            }
            .overlay {
                if !isSelfDragging, case .dropping(let zone) = dropState {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(Ghostty.DraggingSurfaceKey.self) { value in
                isSelfDragging = value == surfaceView.id
                if isSelfDragging {
                    dropState = .idle
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Terminal pane")
        }
    }

    private enum DropState: Equatable {
        case idle
        case dropping(TerminalSplitDropZone)
    }

    private struct SplitDropDelegate: DropDelegate {
        @Binding var dropState: DropState
        let viewSize: CGSize
        let destinationSurface: Ghostty.SurfaceView
        let action: (TerminalSplitOperation) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.ghosttySurfaceId, .ghosttyBrowserPanelId])
        }

        func dropEntered(info: DropInfo) {
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            // For some reason dropUpdated is sent after performDrop is called
            // and we don't want to reset our drop zone to show it so we have
            // to guard on the state here.
            guard case .dropping = dropState else { return DropProposal(operation: .forbidden) }
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            dropState = .idle
        }

        func performDrop(info: DropInfo) -> Bool {
            let zone = TerminalSplitDropZone.calculate(at: info.location, in: viewSize)
            dropState = .idle

            // First check for browser panel drops
            let browserProviders = info.itemProviders(for: [.ghosttyBrowserPanelId])
            if let provider = browserProviders.first {
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.ghosttyBrowserPanelId.identifier) { [weak destinationSurface] data, _ in
                    guard let data, data.count == 16 else { return }
                    let uuid = data.withUnsafeBytes { $0.load(as: UUID.self) }
                    DispatchQueue.main.async {
                        guard let destinationSurface else { return }
                        action(.attachBrowser(.init(panelId: uuid, destination: destinationSurface, zone: zone)))
                    }
                }
                return true
            }

            // Otherwise handle terminal surface drops
            let providers = info.itemProviders(for: [.ghosttySurfaceId])
            guard let provider = providers.first else { return false }

            _ = provider.loadTransferable(type: Ghostty.SurfaceView.self) { [weak destinationSurface] result in
                switch result {
                case .success(let sourceSurface):
                    DispatchQueue.main.async {
                        // Don't allow dropping on self
                        guard let destinationSurface else { return }
                        guard sourceSurface !== destinationSurface else { return }
                        action(.drop(.init(payload: sourceSurface, destination: destinationSurface, zone: zone)))
                    }

                case .failure:
                    break
                }
            }

            return true
        }
    }
}

/// Wraps terminal content with browser panels attached to its surface ID.
/// Renders attached browsers as horizontal/vertical splits around the content
/// using AppKit-backed resize handles for smooth dragging.
private struct AttachedBrowserWrapper<Content: View>: View {
    let surfaceView: Ghostty.SurfaceView
    @ObservedObject var browserPanelManager: BrowserPanelManager
    let onCloseBrowserPanel: (UUID) -> Void
    let content: Content

    @State private var ratioAtDragStart: CGFloat?

    init(
        surfaceView: Ghostty.SurfaceView,
        browserPanelManager: BrowserPanelManager,
        onCloseBrowserPanel: @escaping (UUID) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.surfaceView = surfaceView
        self.browserPanelManager = browserPanelManager
        self.onCloseBrowserPanel = onCloseBrowserPanel
        self.content = content()
    }

    var body: some View {
        let leftPanel = browserPanelManager.attachedPanels(for: surfaceView.id, side: .left).first
        let rightPanel = browserPanelManager.attachedPanels(for: surfaceView.id, side: .right).first
        let topPanel = browserPanelManager.attachedPanels(for: surfaceView.id, side: .top).first
        let bottomPanel = browserPanelManager.attachedPanels(for: surfaceView.id, side: .bottom).first

        verticalWrap(top: topPanel, bottom: bottomPanel) {
            horizontalWrap(left: leftPanel, right: rightPanel) {
                content
            }
        }
    }

    @ViewBuilder
    private func horizontalWrap<C: View>(
        left: BrowserPanelManager.Panel?,
        right: BrowserPanelManager.Panel?,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        if left == nil && right == nil {
            content()
        } else {
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let handleWidth: CGFloat = 6
                let leftWidth: CGFloat = left.map { max(80, min(totalWidth - 80, totalWidth * $0.ratio)) } ?? 0
                let rightWidth: CGFloat = right.map { max(80, min(totalWidth - 80, totalWidth * $0.ratio)) } ?? 0
                let leftHandle: CGFloat = left == nil ? 0 : handleWidth
                let rightHandle: CGFloat = right == nil ? 0 : handleWidth
                let centerWidth = max(0, totalWidth - leftWidth - rightWidth - leftHandle - rightHandle)

                HStack(spacing: 0) {
                    if let left {
                        browserPane(left)
                            .frame(width: leftWidth)
                        browserResizeHandle(panelId: left.id, isHorizontal: true, totalSize: totalWidth, isReverse: false)
                            .frame(width: handleWidth)
                    }
                    content()
                        .frame(width: centerWidth)
                    if let right {
                        browserResizeHandle(panelId: right.id, isHorizontal: true, totalSize: totalWidth, isReverse: true)
                            .frame(width: handleWidth)
                        browserPane(right)
                            .frame(width: rightWidth)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func verticalWrap<C: View>(
        top: BrowserPanelManager.Panel?,
        bottom: BrowserPanelManager.Panel?,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        if top == nil && bottom == nil {
            content()
        } else {
            GeometryReader { geo in
                let totalHeight = geo.size.height
                let handleHeight: CGFloat = 6
                let topHeight: CGFloat = top.map { max(80, min(totalHeight - 80, totalHeight * $0.ratio)) } ?? 0
                let bottomHeight: CGFloat = bottom.map { max(80, min(totalHeight - 80, totalHeight * $0.ratio)) } ?? 0
                let topHandle: CGFloat = top == nil ? 0 : handleHeight
                let bottomHandle: CGFloat = bottom == nil ? 0 : handleHeight
                let centerHeight = max(0, totalHeight - topHeight - bottomHeight - topHandle - bottomHandle)

                VStack(spacing: 0) {
                    if let top {
                        browserPane(top)
                            .frame(height: topHeight)
                        browserResizeHandle(panelId: top.id, isHorizontal: false, totalSize: totalHeight, isReverse: false)
                            .frame(height: handleHeight)
                    }
                    content()
                        .frame(height: centerHeight)
                    if let bottom {
                        browserResizeHandle(panelId: bottom.id, isHorizontal: false, totalSize: totalHeight, isReverse: true)
                            .frame(height: handleHeight)
                        browserPane(bottom)
                            .frame(height: bottomHeight)
                    }
                }
            }
        }
    }

    private func browserPane(_ panel: BrowserPanelManager.Panel) -> some View {
        BrowserPanelChrome(
            panel: panel,
            panelManager: browserPanelManager,
            onClose: { onCloseBrowserPanel(panel.id) }
        )
    }

    private func browserResizeHandle(panelId: UUID, isHorizontal: Bool, totalSize: CGFloat, isReverse: Bool) -> some View {
        BrowserSplitResizeHandle(
            isHorizontal: isHorizontal,
            onDrag: { delta in
                guard let panel = browserPanelManager.panels.first(where: { $0.id == panelId }) else { return }
                if ratioAtDragStart == nil { ratioAtDragStart = panel.ratio }
                if let start = ratioAtDragStart {
                    let signedDelta = isReverse ? -delta : delta
                    let newRatio = start + signedDelta / totalSize
                    browserPanelManager.updateRatio(id: panelId, ratio: newRatio)
                }
            },
            onDragEnd: { ratioAtDragStart = nil }
        )
    }
}

/// AppKit-backed resize handle to avoid SwiftUI DragGesture jitter.
fileprivate struct BrowserSplitResizeHandle: NSViewRepresentable {
    let isHorizontal: Bool
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> BrowserSplitResizeNSView {
        let view = BrowserSplitResizeNSView()
        view.isHorizontal = isHorizontal
        view.onDrag = onDrag
        view.onDragEnd = onDragEnd
        return view
    }

    func updateNSView(_ nsView: BrowserSplitResizeNSView, context: Context) {
        nsView.isHorizontal = isHorizontal
        nsView.onDrag = onDrag
        nsView.onDragEnd = onDragEnd
    }
}

fileprivate class BrowserSplitResizeNSView: NSView {
    var isHorizontal: Bool = true
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    private var startPos: CGFloat = 0

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isHorizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        startPos = isHorizontal ? p.x : p.y
        onDrag?(0)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let cur = isHorizontal ? p.x : p.y
        let delta = cur - startPos
        onDrag?(isHorizontal ? delta : -delta)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}

enum TerminalSplitDropZone: String, Equatable {
    case top
    case bottom
    case left
    case right

    /// Determines which drop zone the cursor is in based on proximity to edges.
    ///
    /// Divides the view into four triangular regions by drawing diagonals from
    /// corner to corner. The drop zone is determined by which edge the cursor
    /// is closest to, creating natural triangular hit regions for each side.
    static func calculate(at point: CGPoint, in size: CGSize) -> TerminalSplitDropZone {
        let relX = point.x / size.width
        let relY = point.y / size.height

        let distToLeft = relX
        let distToRight = 1 - relX
        let distToTop = relY
        let distToBottom = 1 - relY

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        if minDist == distToLeft { return .left }
        if minDist == distToRight { return .right }
        if minDist == distToTop { return .top }
        return .bottom
    }

    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let overlayFill = Color.accentColor.opacity(0.15)
        let overlayBorder = Color.accentColor.opacity(0.6)
        let inset: CGFloat = 2

        switch self {
        case .top:
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(overlayFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(overlayBorder, lineWidth: 2)
                    )
                    .frame(height: geometry.size.height / 2)
                    .padding(inset)
                Spacer()
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(overlayFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(overlayBorder, lineWidth: 2)
                    )
                    .frame(height: geometry.size.height / 2)
                    .padding(inset)
            }
        case .left:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(overlayFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(overlayBorder, lineWidth: 2)
                    )
                    .frame(width: geometry.size.width / 2)
                    .padding(inset)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(overlayFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(overlayBorder, lineWidth: 2)
                    )
                    .frame(width: geometry.size.width / 2)
                    .padding(inset)
            }
        }
    }
}
