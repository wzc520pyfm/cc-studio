import AppKit
import Combine
import GhosttyKit
import WebKit

/// A wrapper NSView that can host either a terminal surface or a browser pane.
/// This is the leaf type for the split tree, enabling heterogeneous split layouts
/// where terminals and browsers can coexist.
class PaneView: NSView, Identifiable, Codable {
    typealias ID = UUID

    let id: UUID

    enum Content {
        case terminal(Ghostty.SurfaceView)
        case browser(BrowserPaneView)
    }

    private(set) var content: Content

    // MARK: - Published Properties (forwarded from inner content)

    @Published var title: String = ""
    @Published var bell: Bool = false
    @Published var pwd: String = ""

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Convenience Accessors

    var surfaceView: Ghostty.SurfaceView? {
        if case .terminal(let sv) = content { return sv }
        return nil
    }

    var browserView: BrowserPaneView? {
        if case .browser(let bv) = content { return bv }
        return nil
    }

    var isTerminal: Bool {
        if case .terminal = content { return true }
        return false
    }

    var isBrowser: Bool {
        if case .browser = content { return true }
        return false
    }

    var surface: ghostty_surface_t? { surfaceView?.surface }

    var needsConfirmQuit: Bool { surfaceView?.needsConfirmQuit ?? false }

    var displayTitle: String {
        switch content {
        case .terminal(let sv): return sv.title
        case .browser(let bv): return bv.pageTitle.isEmpty ? "Browser" : bv.pageTitle
        }
    }

    var displayIcon: String {
        switch content {
        case .terminal: return "terminal"
        case .browser: return "globe"
        }
    }

    // MARK: - Initialization

    init(surfaceView: Ghostty.SurfaceView) {
        self.id = UUID()
        self.content = .terminal(surfaceView)
        super.init(frame: .zero)
        setupContent(surfaceView)
        bindTerminalProperties(surfaceView)
    }

    init(browserView: BrowserPaneView) {
        self.id = UUID()
        self.content = .browser(browserView)
        super.init(frame: .zero)
        setupContent(browserView)
        bindBrowserProperties(browserView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Content Management

    private func setupContent(_ childView: NSView) {
        childView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(childView)
        NSLayoutConstraint.activate([
            childView.topAnchor.constraint(equalTo: topAnchor),
            childView.bottomAnchor.constraint(equalTo: bottomAnchor),
            childView.leadingAnchor.constraint(equalTo: leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func bindTerminalProperties(_ sv: Ghostty.SurfaceView) {
        sv.$title
            .assign(to: &$title)
        sv.$bell
            .assign(to: &$bell)
    }

    private func bindBrowserProperties(_ bv: BrowserPaneView) {
        bv.$pageTitle
            .map { $0.isEmpty ? "Browser" : $0 }
            .assign(to: &$title)
    }

    // MARK: - Focus

    func focusDidChange(_ focused: Bool) {
        surfaceView?.focusDidChange(focused)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case contentType
        case url
    }

    private enum ContentType: String, Codable {
        case terminal
        case browser
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch content {
        case .terminal:
            try container.encode(ContentType.terminal, forKey: .contentType)
        case .browser(let bv):
            try container.encode(ContentType.browser, forKey: .contentType)
            try container.encode(bv.currentURL?.absoluteString, forKey: .url)
        }
    }

    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let contentType = try container.decode(ContentType.self, forKey: .contentType)
        switch contentType {
        case .terminal:
            fatalError("Terminal PaneViews cannot be decoded without a ghostty app reference")
        case .browser:
            let urlString = try container.decodeIfPresent(String.self, forKey: .url)
            let url = urlString.flatMap { URL(string: $0) }
            let bv = BrowserPaneView(url: url)
            self.init(browserView: bv)
        }
    }
}
