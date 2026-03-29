import AppKit
import WebKit
import Combine

/// A browser pane that wraps WKWebView for embedding in split layouts.
/// Provides URL bar, navigation controls, and page state.
class BrowserPaneView: NSView, ObservableObject {
    private(set) var webView: WKWebView!
    private var urlBarView: BrowserURLBarView?

    @Published var currentURL: URL?
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var urlBarText: String = ""

    private var observations: [NSKeyValueObservation] = []

    // MARK: - Initialization

    init(url: URL? = nil) {
        super.init(frame: .zero)

        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        addSubview(webView)

        let urlBar = BrowserURLBarView(browser: self)
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(urlBar)
        self.urlBarView = urlBar

        NSLayoutConstraint.activate([
            urlBar.topAnchor.constraint(equalTo: topAnchor),
            urlBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            urlBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            urlBar.heightAnchor.constraint(equalToConstant: 36),

            webView.topAnchor.constraint(equalTo: urlBar.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        setupObservations()

        if let url {
            navigate(to: url)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        observations.removeAll()
    }

    // MARK: - Navigation

    func navigate(to url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
        currentURL = url
        urlBarText = url.absoluteString
    }

    func navigateToString(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            navigate(to: url)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            if let url = URL(string: "https://\(trimmed)") {
                navigate(to: url)
            }
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            if let url = URL(string: "https://www.google.com/search?q=\(query)") {
                navigate(to: url)
            }
        }
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
    }

    // MARK: - Observations

    private func setupObservations() {
        observations.append(webView.observe(\.title) { [weak self] webView, _ in
            self?.pageTitle = webView.title ?? ""
        })

        observations.append(webView.observe(\.url) { [weak self] webView, _ in
            self?.currentURL = webView.url
            self?.urlBarText = webView.url?.absoluteString ?? ""
        })

        observations.append(webView.observe(\.isLoading) { [weak self] webView, _ in
            self?.isLoading = webView.isLoading
        })

        observations.append(webView.observe(\.canGoBack) { [weak self] webView, _ in
            self?.canGoBack = webView.canGoBack
        })

        observations.append(webView.observe(\.canGoForward) { [weak self] webView, _ in
            self?.canGoForward = webView.canGoForward
        })
    }
}

// MARK: - WKNavigationDelegate

extension BrowserPaneView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        pageTitle = webView.title ?? ""
        currentURL = webView.url
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}

// MARK: - URL Bar View

class BrowserURLBarView: NSView {
    private weak var browser: BrowserPaneView?
    private var urlField: NSTextField!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var observations: [NSKeyValueObservation] = []
    private var cancellables = Set<AnyCancellable>()

    init(browser: BrowserPaneView) {
        self.browser = browser
        super.init(frame: .zero)
        setupUI()
        bindState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        observations.removeAll()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        backButton = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
                              target: self, action: #selector(goBack))
        backButton.bezelStyle = .accessoryBarAction
        backButton.isBordered = false

        forwardButton = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")!,
                                  target: self, action: #selector(goForward))
        forwardButton.bezelStyle = .accessoryBarAction
        forwardButton.isBordered = false

        reloadButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")!,
                                target: self, action: #selector(reloadPage))
        reloadButton.bezelStyle = .accessoryBarAction
        reloadButton.isBordered = false

        urlField = NSTextField()
        urlField.placeholderString = "Enter URL or search..."
        urlField.font = .systemFont(ofSize: 13)
        urlField.bezelStyle = .roundedBezel
        urlField.target = self
        urlField.action = #selector(urlFieldAction)

        let stackView = NSStackView(views: [backButton, forwardButton, reloadButton, urlField])
        stackView.orientation = .horizontal
        stackView.spacing = 4
        stackView.edgeInsets = .init(top: 4, left: 8, bottom: 4, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        urlField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func bindState() {
        guard let browser else { return }
        browser.$canGoBack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.backButton.isEnabled = $0 }
            .store(in: &cancellables)
        browser.$canGoForward
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.forwardButton.isEnabled = $0 }
            .store(in: &cancellables)
        browser.$urlBarText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.urlField.stringValue = $0 }
            .store(in: &cancellables)
    }

    @objc private func goBack() { browser?.goBack() }
    @objc private func goForward() { browser?.goForward() }
    @objc private func reloadPage() { browser?.reload() }

    @objc private func urlFieldAction() {
        browser?.navigateToString(urlField.stringValue)
    }
}
