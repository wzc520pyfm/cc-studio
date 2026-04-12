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

/// A container that shows browser panels alongside terminal content,
/// with a draggable divider between them.
struct BrowserSplitContainer<Content: View>: View {
    let content: Content
    @ObservedObject var panelManager: BrowserPanelManager
    let onClosePanel: (UUID) -> Void

    @State private var dragOffset: CGFloat = 0

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
        let ratio = panelManager.splitRatio
        let totalWidth = geo.size.width
        let leftWidth = totalWidth * ratio
        let dividerWidth: CGFloat = 4

        return HStack(spacing: 0) {
            content
                .frame(width: max(leftWidth + dragOffset, 100))

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: dividerWidth)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let newRatio = (leftWidth + value.translation.width) / totalWidth
                            panelManager.splitRatio = max(0.15, min(0.85, newRatio))
                            dragOffset = 0
                        }
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            browserStack(panels: rightPanels)
                .frame(maxWidth: .infinity)
        }
    }

    private func verticalSplit(geo: GeometryProxy, bottomPanels: [BrowserPanelManager.Panel]) -> some View {
        let ratio = panelManager.splitRatio
        let totalHeight = geo.size.height
        let topHeight = totalHeight * ratio
        let dividerHeight: CGFloat = 4

        return VStack(spacing: 0) {
            content
                .frame(height: max(topHeight + dragOffset, 100))

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: dividerHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
                            let newRatio = (topHeight + value.translation.height) / totalHeight
                            panelManager.splitRatio = max(0.15, min(0.85, newRatio))
                            dragOffset = 0
                        }
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            browserStack(panels: bottomPanels)
                .frame(maxHeight: .infinity)
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
