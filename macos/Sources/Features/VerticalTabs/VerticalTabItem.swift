import SwiftUI

/// A single row in the vertical tab bar, displaying tab info with notification indicators.
struct VerticalTabItem: View {
    let tab: TabManager.Tab
    let isActive: Bool
    let isCollapsed: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var flashOpacity: Double = 0

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                tabIcon
                if !isCollapsed {
                    tabInfo
                    Spacer(minLength: 0)
                    trailingContent
                }
            }
            .padding(.horizontal, isCollapsed ? 0 : 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .frame(height: isCollapsed ? 36 : 40)
            .background(tabBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onChange(of: tab.isFlashing) { flashing in
            if flashing {
                startFlashAnimation()
            } else {
                flashOpacity = 0
            }
        }
    }

    // MARK: - Icon

    private var tabIcon: some View {
        ZStack {
            Image(systemName: tab.icon == "terminal" ? "terminal" : "globe")
                .font(.system(size: isCollapsed ? 14 : 12))
                .foregroundStyle(isActive ? .primary : .secondary)

            if tab.notificationCount > 0 && isCollapsed {
                NotificationDot()
                    .offset(x: 8, y: -8)
            }
        }
        .frame(width: isCollapsed ? 28 : 20)
    }

    // MARK: - Tab Info

    private var tabInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if !tab.pwd.isEmpty {
                Text(tab.pwd)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Trailing Content

    private var trailingContent: some View {
        HStack(spacing: 4) {
            if tab.notificationCount > 0 {
                NotificationBadge(count: tab.notificationCount)
            }

            if isHovered || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Background

    private var tabBackground: some View {
        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
            } else if isHovered {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
            }

            if flashOpacity > 0 {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(flashOpacity))
            }
        }
    }

    // MARK: - Flash Animation

    private func startFlashAnimation() {
        withAnimation(.easeInOut(duration: 0.4).repeatCount(3, autoreverses: true)) {
            flashOpacity = 0.3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.3)) {
                flashOpacity = tab.isFlashing ? 0.1 : 0
            }
        }
    }
}

// MARK: - Notification Dot (collapsed mode)

struct NotificationDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Notification Badge

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor))
            .fixedSize()
    }
}
