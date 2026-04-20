import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// SwiftUI wrapper that hosts a BrowserPaneView (AppKit) in SwiftUI.
struct BrowserPanelView: NSViewRepresentable {
    let browserView: BrowserPaneView

    func makeNSView(context: Context) -> BrowserPaneView {
        return browserView
    }

    func updateNSView(_ nsView: BrowserPaneView, context: Context) {}
}

// MARK: - AppKit-based resize handle for splits (no SwiftUI jitter)

private class SplitResizeNSView: NSView {
    var isHorizontal: Bool = true
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    private var startPos: CGFloat = 0

    override func resetCursorRects() {
        let cursor: NSCursor = isHorizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        let pos = NSEvent.mouseLocation
        startPos = isHorizontal ? pos.x : pos.y
        onDrag?(0)
    }

    override func mouseDragged(with event: NSEvent) {
        let pos = NSEvent.mouseLocation
        let current = isHorizontal ? pos.x : pos.y
        let delta = current - startPos
        let adjusted = isHorizontal ? delta : -delta
        onDrag?(adjusted)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}

private struct SplitResizeHandle: NSViewRepresentable {
    let isHorizontal: Bool
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> SplitResizeNSView {
        let view = SplitResizeNSView()
        view.isHorizontal = isHorizontal
        view.onDrag = onDrag
        view.onDragEnd = onDragEnd
        return view
    }

    func updateNSView(_ nsView: SplitResizeNSView, context: Context) {
        nsView.isHorizontal = isHorizontal
        nsView.onDrag = onDrag
        nsView.onDragEnd = onDragEnd
    }
}

/// A container that shows browser panels alongside terminal content,
/// with a draggable divider between them. Renders only browser panels with
/// `.container(.right)` or `.container(.bottom)` positions; attached panels
/// are rendered inside the terminal split tree by `TerminalSplitLeaf`.
struct BrowserSplitContainer<Content: View>: View {
    let content: Content
    @ObservedObject var panelManager: BrowserPanelManager
    let onClosePanel: (UUID) -> Void

    @State private var rightRatio: CGFloat = 0.5
    @State private var bottomRatio: CGFloat = 0.5
    @State private var ratioAtDragStart: CGFloat?

    init(
        panelManager: BrowserPanelManager,
        onClosePanel: @escaping (UUID) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.panelManager = panelManager
        self.onClosePanel = onClosePanel
        self.content = content()
    }

    var body: some View {
        let rightPanels = panelManager.containerRightPanels
        let bottomPanels = panelManager.containerBottomPanels

        if rightPanels.isEmpty && bottomPanels.isEmpty {
            content
        } else {
            GeometryReader { geo in
                if !rightPanels.isEmpty && bottomPanels.isEmpty {
                    horizontalSplit(geo: geo, rightPanels: rightPanels)
                } else if rightPanels.isEmpty && !bottomPanels.isEmpty {
                    verticalSplit(geo: geo, bottomPanels: bottomPanels)
                } else {
                    horizontalSplit(geo: geo, rightPanels: rightPanels)
                }
            }
        }
    }

    private func horizontalSplit(geo: GeometryProxy, rightPanels: [BrowserPanelManager.Panel]) -> some View {
        let totalWidth = geo.size.width
        let handleWidth: CGFloat = 6
        let leftWidth = max(100, min(totalWidth - 100, totalWidth * rightRatio))
        let rightWidth = max(0, totalWidth - leftWidth - handleWidth)

        return HStack(spacing: 0) {
            content
                .frame(width: leftWidth)

            SplitResizeHandle(
                isHorizontal: true,
                onDrag: { delta in
                    if ratioAtDragStart == nil {
                        ratioAtDragStart = rightRatio
                    }
                    if let start = ratioAtDragStart {
                        let newRatio = start + delta / totalWidth
                        rightRatio = max(0.15, min(0.85, newRatio))
                    }
                },
                onDragEnd: {
                    ratioAtDragStart = nil
                }
            )
            .frame(width: handleWidth)

            browserStack(panels: rightPanels)
                .frame(width: rightWidth)
        }
    }

    private func verticalSplit(geo: GeometryProxy, bottomPanels: [BrowserPanelManager.Panel]) -> some View {
        let totalHeight = geo.size.height
        let handleHeight: CGFloat = 6
        let topHeight = max(100, min(totalHeight - 100, totalHeight * bottomRatio))
        let bottomHeight = max(0, totalHeight - topHeight - handleHeight)

        return VStack(spacing: 0) {
            content
                .frame(height: topHeight)

            SplitResizeHandle(
                isHorizontal: false,
                onDrag: { delta in
                    if ratioAtDragStart == nil {
                        ratioAtDragStart = bottomRatio
                    }
                    if let start = ratioAtDragStart {
                        let newRatio = start + delta / totalHeight
                        bottomRatio = max(0.15, min(0.85, newRatio))
                    }
                },
                onDragEnd: {
                    ratioAtDragStart = nil
                }
            )
            .frame(height: handleHeight)

            browserStack(panels: bottomPanels)
                .frame(height: bottomHeight)
        }
    }

    private func browserStack(panels: [BrowserPanelManager.Panel]) -> some View {
        ZStack {
            ForEach(panels) { panel in
                BrowserPanelChrome(
                    panel: panel,
                    panelManager: panelManager,
                    onClose: { onClosePanel(panel.id) }
                )
                .opacity(panel.id == (panelManager.activePanelId ?? panels.first?.id) ? 1 : 0)
            }
        }
    }
}

/// A single browser panel with its tab bar and grab handle.
/// Shared between container-level and attached rendering.
struct BrowserPanelChrome: View {
    let panel: BrowserPanelManager.Panel
    @ObservedObject var panelManager: BrowserPanelManager
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("Browser")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))

            ZStack(alignment: .top) {
                BrowserPanelView(browserView: panel.browserView)
                BrowserGrabHandle(panelManager: panelManager, panelId: panel.id)
            }
        }
    }
}

// MARK: - Browser Grab Handle (matches terminal SurfaceGrabHandle style)

struct BrowserGrabHandle: View {
    @ObservedObject var panelManager: BrowserPanelManager
    let panelId: UUID

    @State private var isHovering: Bool = false

    private let handleSize = CGSize(width: 80, height: 12)

    var body: some View {
        ZStack {
            BrowserGrabHandleNSViewWrapper(panelManager: panelManager, panelId: panelId, isHovering: $isHovering)
                .frame(width: handleSize.width, height: handleSize.height)
                .contentShape(Rectangle())

            if isHovering {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary.opacity(isHovering ? 0.8 : 0.3))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }
}

private class BrowserGrabHandleNSView: NSView, NSDraggingSource {
    private static let previewScale: CGFloat = 0.2
    var panelManager: BrowserPanelManager?
    var panelId: UUID?
    var onHoverChanged: ((Bool) -> Void)?
    private var isTracking = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isTracking ? .closedHand : .openHand)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard !isTracking, let panelId else { return }

        let pasteboardItem = NSPasteboardItem()
        let uuidData = withUnsafeBytes(of: panelId.uuid) { Data($0) }
        pasteboardItem.setData(uuidData, forType: .ghosttyBrowserPanelId)

        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)

        let dragSize = NSSize(width: 120, height: 80)
        let image = NSImage(size: dragSize)
        image.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: dragSize), xRadius: 8, yRadius: 8).fill()
        let icon = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        icon?.draw(in: NSRect(x: 46, y: 26, width: 28, height: 28))
        image.unlockFocus()

        let mouseLocation = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(
                origin: NSPoint(x: mouseLocation.x - dragSize.width / 2,
                                y: mouseLocation.y - dragSize.height / 2),
                size: dragSize),
            contents: image
        )

        isTracking = true
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        NSCursor.closedHand.set()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isTracking = false
    }
}

private struct BrowserGrabHandleNSViewWrapper: NSViewRepresentable {
    let panelManager: BrowserPanelManager
    let panelId: UUID
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> BrowserGrabHandleNSView {
        let view = BrowserGrabHandleNSView()
        view.panelManager = panelManager
        view.panelId = panelId
        view.onHoverChanged = { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        return view
    }

    func updateNSView(_ nsView: BrowserGrabHandleNSView, context: Context) {
        nsView.panelManager = panelManager
        nsView.panelId = panelId
        nsView.onHoverChanged = { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
