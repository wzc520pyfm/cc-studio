import SwiftUI
import AppKit

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
/// with a draggable divider between them.
struct BrowserSplitContainer<Content: View>: View {
    let content: Content
    @ObservedObject var panelManager: BrowserPanelManager
    let onClosePanel: (UUID) -> Void

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
        if panelManager.panels.isEmpty {
            content
        } else {
            GeometryReader { geo in
                let rightPanels = panelManager.rightPanels
                let bottomPanels = panelManager.bottomPanels

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
        let leftWidth = max(100, min(totalWidth - 100, totalWidth * panelManager.splitRatio))
        let rightWidth = max(0, totalWidth - leftWidth - handleWidth)

        return HStack(spacing: 0) {
            content
                .frame(width: leftWidth)

            SplitResizeHandle(
                isHorizontal: true,
                onDrag: { delta in
                    if ratioAtDragStart == nil {
                        ratioAtDragStart = panelManager.splitRatio
                    }
                    if let start = ratioAtDragStart {
                        let newRatio = start + delta / totalWidth
                        panelManager.splitRatio = max(0.15, min(0.85, newRatio))
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
        let topHeight = max(100, min(totalHeight - 100, totalHeight * panelManager.splitRatio))
        let bottomHeight = max(0, totalHeight - topHeight - handleHeight)

        return VStack(spacing: 0) {
            content
                .frame(height: topHeight)

            SplitResizeHandle(
                isHorizontal: false,
                onDrag: { delta in
                    if ratioAtDragStart == nil {
                        ratioAtDragStart = panelManager.splitRatio
                    }
                    if let start = ratioAtDragStart {
                        let newRatio = start + delta / totalHeight
                        panelManager.splitRatio = max(0.15, min(0.85, newRatio))
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
                VStack(spacing: 0) {
                    browserTabBar(panel: panel)
                    BrowserPanelView(browserView: panel.browserView)
                }
                .opacity(panel.id == (panelManager.activePanelId ?? panels.first?.id) ? 1 : 0)
            }
        }
    }

    private func browserTabBar(panel: BrowserPanelManager.Panel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Browser")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                onClosePanel(panel.id)
            } label: {
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
    }
}
