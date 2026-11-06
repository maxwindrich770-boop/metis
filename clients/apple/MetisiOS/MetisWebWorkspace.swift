import Foundation

/// Navigation rules do not depend on WebKit, so the same boundary can be smoke tested.
enum MetisWebPolicy {
    static func isSameOrigin(_ url: URL, server: URL) -> Bool {
        guard url.user == nil, url.password == nil,
              let scheme = url.scheme?.lowercased(),
              let serverScheme = server.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              scheme == serverScheme,
              let host = url.host?.lowercased(), host == server.host?.lowercased() else { return false }
        return effectivePort(url) == effectivePort(server)
    }

    static func isFirstPartyBlob(_ url: URL, server: URL) -> Bool {
        guard url.scheme?.lowercased() == "blob",
              let origin = URL(string: String(url.absoluteString.dropFirst(5))) else { return false }
        return isSameOrigin(origin, server: server)
    }

    static func permitsSubframe(_ url: URL, server: URL, firstPartySource: Bool) -> Bool {
        if isSameOrigin(url, server: server) { return true }
        guard firstPartySource else { return false }
        return isFirstPartyBlob(url, server: server)
            || url.scheme?.lowercased() == "data"
            || url.absoluteString == "about:blank"
    }

    static func isExternalLink(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host, !host.isEmpty else { return false }
        return ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    }

    static func isLoginURL(_ url: URL) -> Bool {
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return ["login", "signin", "sign-in", "auth", "api/auth"].contains(path)
    }

    static func safeDownloadName(_ suggested: String) -> String {
        let last = suggested.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? ""
        let safeScalars = last.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
                && !(0x202A...0x202E).contains($0.value)
                && !(0x2066...0x2069).contains($0.value)
        }
        let name = String(String.UnicodeScalarView(safeScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var bounded = ""
        var bytes = 0
        for character in name {
            let length = String(character).utf8.count
            if bytes + length > 180 { break }
            bounded.append(character)
            bytes += length
        }
        return bounded.isEmpty ? "Download" : bounded
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil)
    }
}

#if canImport(WebKit) && canImport(UIKit)
import Combine
import UIKit
import WebKit

private final class MetisWebCookieObserver: NSObject, WKHTTPCookieStoreObserver {
    weak var owner: MetisWebWorkspace?

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in self?.owner?.cookieStoreChanged() }
    }
}

private final class MetisAppControlsBridge: NSObject, WKScriptMessageHandler {
    weak var owner: MetisWebWorkspace?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in self?.owner?.receiveAppControls(message) }
    }
}

@MainActor
final class MetisWebWorkspace: NSObject, ObservableObject {
    let webView: WKWebView
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var appControlsAvailable = false
    @Published var appControlsRequested = false
    @Published var externalURL: URL?
    @Published var externalConfirmationURL: URL?
    @Published var sharedFile: URL? {
        didSet {
            if oldValue != sharedFile, let oldValue { removeOwnedFile(oldValue) }
        }
    }

    private struct Download {
        let task: WKDownload
        var file: URL?
    }

    private let client: MetisAPI
    private let server: URL?
    private let unauthorized: () -> Void
    private let sessionChanged: () -> Void
    private let cookieObserver = MetisWebCookieObserver()
    private let appControlsBridge = MetisAppControlsBridge()
    private var observations: [NSKeyValueObservation] = []
    private var downloads: [ObjectIdentifier: Download] = [:]
    private var ownedFiles: [URL: URL] = [:]
    private var lastSessionCookie: HTTPCookie?
    private var lastMainURL: URL?
    private var pendingChatURL: URL?
    private var cookieTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var generation = 0
    private var cookieRead = 0
    private var sessionRevision = 0
    private var starting = false
    private var started = false
    private var invalidated = false
    private var authorizationLost = false
    private weak var activeDialog: UIAlertController?
    private var cancelDialog: (() -> Void)?

    init(client: MetisAPI, unauthorized: @escaping () -> Void, sessionChanged: @escaping () -> Void = {}) {
        self.client = client
        self.server = URL(string: client.origin)
        self.unauthorized = unauthorized
        self.sessionChanged = sessionChanged
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        // The UIKit keyboard guide owns keyboard avoidance. The page's viewport-fit=cover and
        // safe-area CSS own home-indicator clearance, without an extra native inset.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        installAppPresentation()
        cookieObserver.owner = self
        configuration.websiteDataStore.httpCookieStore.add(cookieObserver)
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in
                    guard let self, !self.invalidated else { return }
                    self.isLoading = value
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? 0
                Task { @MainActor [weak self] in
                    guard let self, !self.invalidated else { return }
                    self.progress = value
                }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in
                    guard let self, !self.invalidated else { return }
                    self.canGoBack = value
                }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in
                    guard let self, !self.invalidated else { return }
                    self.canGoForward = value
                }
            },
        ]
    }

    private func installAppPresentation() {
        guard let data = try? JSONEncoder().encode(client.origin),
              let literal = String(data: data, encoding: .utf8),
              let labelData = try? JSONEncoder().encode(String(localized: "iPhone controls")),
              let labelLiteral = String(data: labelData, encoding: .utf8) else { return }
        // Presentation code is app-owned and first-party only. It never reads
        // cookies, credentials, model parameters or chat content.
        let source = """
        (() => {
          if (window.top !== window || location.origin !== new URL(\(literal)).origin) return;
          const metisAppControlsLabel = \(labelLiteral);
          \(MetisAppWebPresentation.userScript)
        })();
        """
        let controller = webView.configuration.userContentController
        appControlsBridge.owner = self
        controller.add(appControlsBridge, name: "metisAppControls")
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    fileprivate func receiveAppControls(_ message: WKScriptMessage) {
        guard !invalidated, started, !authorizationLost,
              message.name == "metisAppControls", let action = message.body as? String,
              message.webView === webView, message.frameInfo.isMainFrame,
              trusted(message.frameInfo.securityOrigin), let server,
              let frameURL = message.frameInfo.request.url,
              MetisWebPolicy.isSameOrigin(frameURL, server: server) else { return }
        switch action {
        case "controls-available":
            appControlsAvailable = true
        case "controls-unavailable":
            appControlsAvailable = false
        case "menu":
            guard externalURL == nil, externalConfirmationURL == nil, sharedFile == nil,
                  activeDialog == nil else { return }
            // This bridge only requests a native sheet. Every action still requires
            // a separate explicit button press in that sheet.
            appControlsRequested = true
        default:
            break
        }
    }

    func start() async {
        guard !invalidated, !started, !starting else { return }
        starting = true
        let current = generation
        defer { if current == generation { starting = false } }
        guard let server, MetisWebPolicy.isSameOrigin(server, server: server) else {
            errorMessage = String(localized: "The saved server address is invalid.")
            return
        }
        guard let cookie = client.webSessionCookie() else {
            loseAuthorization()
            return
        }
        isLoading = true
        errorMessage = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
        guard !Task.isCancelled, !invalidated, current == generation else {
            if !invalidated { isLoading = false }
            return
        }
        lastSessionCookie = cookie
        started = true
        load(pendingChatURL ?? server)
        pendingChatURL = nil
        validateAuthorization()
    }

    func retry() {
        guard !invalidated else { return }
        errorMessage = nil
        if started, let url = lastMainURL ?? server {
            load(url)
            validateAuthorization()
        } else {
            startTask?.cancel()
            startTask = Task { [weak self] in await self?.start() }
        }
    }

    func back() {
        guard !invalidated, webView.canGoBack else { return }
        errorMessage = nil
        webView.goBack()
    }

    func forward() {
        guard !invalidated, webView.canGoForward else { return }
        errorMessage = nil
        webView.goForward()
    }

    func approveExternalNavigation() {
        defer { externalConfirmationURL = nil }
        guard !invalidated, let url = externalConfirmationURL, let server,
              MetisWebPolicy.isExternalLink(url), !MetisWebPolicy.isSameOrigin(url, server: server) else { return }
        externalURL = url
    }

    func cancelExternalNavigation() {
        externalConfirmationURL = nil
    }

    func openChat(id: String) {
        guard !invalidated, !id.isEmpty, let server,
              var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return }
        components.path = "/"
        // The canonical Web router reads the chat ID from ?c=.
        components.queryItems = [URLQueryItem(name: "c", value: id)]
        guard let url = components.url else { return }
        if started { load(url) } else { pendingChatURL = url }
    }

    func invalidate() async {
        guard !invalidated else { return }
        invalidated = true
        generation += 1
        cookieRead += 1
        startTask?.cancel()
        cookieTask?.cancel()
        authorizationTask?.cancel()
        cookieObserver.owner = nil
        appControlsBridge.owner = nil
        appControlsAvailable = false
        appControlsRequested = false
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "metisAppControls")
        webView.configuration.userContentController.removeAllUserScripts()
        let store = webView.configuration.websiteDataStore
        store.httpCookieStore.remove(cookieObserver)
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        let dialog = activeDialog
        cancelDialog?()
        dialog?.dismiss(animated: false)
        activeDialog = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        for download in downloads.values { download.task.cancel { _ in } }
        downloads.removeAll()
        sharedFile = nil
        for folder in Set(ownedFiles.values) { try? FileManager.default.removeItem(at: folder) }
        ownedFiles.removeAll()
        externalURL = nil
        externalConfirmationURL = nil
        lastSessionCookie = nil
        pendingChatURL = nil
        lastMainURL = nil
        started = false
        starting = false
        isLoading = false
        progress = 0
        canGoBack = false
        canGoForward = false
        // This store is unique to this workspace; clearing it cannot affect another account.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
    }

    /// Reconcile a native request with a Web cookie rotation before treating its 401 as current.
    func refreshSessionCookie() async -> Bool {
        if let cookieTask { await cookieTask.value }
        return await synchronizeCookie()
    }

    fileprivate func cookieStoreChanged() {
        guard started, !invalidated else { return }
        cookieTask?.cancel()
        cookieTask = Task { [weak self] in _ = await self?.synchronizeCookie() }
    }

    private func synchronizeCookie() async -> Bool {
        guard started, !invalidated, let server else { return false }
        cookieRead += 1
        let read = cookieRead
        let current = generation
        let cookies = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
        guard !Task.isCancelled, !invalidated, generation == current, cookieRead == read else { return false }
        guard let cookie = cookies.first(where: {
            $0.name == "ai_chat_auth" && $0.domain.lowercased() == server.host?.lowercased() && $0.path == "/"
        }) else {
            loseAuthorization()
            return false
        }
        do {
            // Validate even an unchanged token: expiry and cookie restrictions still apply.
            try client.updateWebSessionCookie(cookie)
            guard cookie.value != lastSessionCookie?.value || cookie.expiresDate != lastSessionCookie?.expiresDate else { return true }
            lastSessionCookie = cookie
            sessionRevision += 1
            sessionChanged()
            return true
        } catch {
            loseAuthorization()
            return false
        }
    }

    private func validateAuthorization() {
        guard started, !invalidated else { return }
        authorizationTask?.cancel()
        let current = generation
        authorizationTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<2 {
                guard await self.synchronizeCookie(),
                      !Task.isCancelled, !self.invalidated, self.generation == current else { return }
                let revision = self.sessionRevision
                do {
                    _ = try await self.client.chats()
                    return
                } catch MetisError.unauthorized {
                    guard !Task.isCancelled, !self.invalidated, self.generation == current,
                          await self.synchronizeCookie() else { return }
                    // A response for the previous token must not revoke the replacement session.
                    if self.sessionRevision != revision { continue }
                    self.loseAuthorization()
                    return
                } catch {
                    // A network error does not revoke the account session.
                    return
                }
            }
        }
    }

    private func loseAuthorization() {
        guard !authorizationLost, !invalidated else { return }
        authorizationLost = true
        webView.stopLoading()
        isLoading = false
        unauthorized()
        Task { [weak self] in await self?.invalidate() }
    }

    private func load(_ url: URL) {
        guard !invalidated, let server, MetisWebPolicy.isSameOrigin(url, server: server) else { return }
        errorMessage = nil
        progress = 0
        isLoading = true
        lastMainURL = url
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    private func trusted(_ origin: WKSecurityOrigin) -> Bool {
        guard let server else { return false }
        let scheme = origin.protocol.lowercased()
        let port = origin.port == 0 ? (scheme == "https" ? 443 : 80) : origin.port
        let serverPort = server.port ?? (server.scheme?.lowercased() == "https" ? 443 : 80)
        return scheme == server.scheme?.lowercased()
            && origin.host.lowercased() == server.host?.lowercased() && port == serverPort
    }

    private func openExternal(_ action: WKNavigationAction) -> Bool {
        guard trusted(action.sourceFrame.securityOrigin), let url = action.request.url,
              MetisWebPolicy.isExternalLink(url) else { return false }
        if action.navigationType == .linkActivated {
            externalConfirmationURL = nil
            externalURL = url
            return true
        }
        // Some first-party setup buttons use window.open rather than an anchor.
        // Ask the native user before opening such a popup; redirects still stay blocked.
        if action.navigationType == .other, action.targetFrame == nil {
            externalConfirmationURL = url
            return true
        }
        return false
    }

    private func register(_ download: WKDownload) {
        guard !invalidated else { download.cancel { _ in }; return }
        guard downloads[ObjectIdentifier(download)] == nil else { return }
        downloads[ObjectIdentifier(download)] = Download(task: download)
        download.delegate = self
    }

    private func removeOwnedFile(_ file: URL) {
        guard let folder = ownedFiles.removeValue(forKey: file) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    private func navigationFailed(_ error: Error) {
        guard !invalidated, (error as NSError).code != NSURLErrorCancelled else { return }
        isLoading = false
        errorMessage = String(localized: "The Metis workspace could not load. Check your connection and try again.")
    }

    private func presentDialog(_ dialog: UIAlertController, cancel: @escaping () -> Void) -> Bool {
        guard !invalidated, activeDialog == nil, var presenter = webView.window?.rootViewController else { return false }
        while let next = presenter.presentedViewController { presenter = next }
        guard !presenter.isBeingDismissed, !(presenter is UIAlertController) else { return false }
        activeDialog = dialog
        cancelDialog = cancel
        presenter.present(dialog, animated: true)
        return true
    }

    private func dialogFinished(_ dialog: UIAlertController) {
        guard activeDialog === dialog else { return }
        activeDialog = nil
        cancelDialog = nil
    }
}

extension MetisWebWorkspace: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !invalidated, let url = action.request.url, let server else { decisionHandler(.cancel); return }
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        let sameOrigin = MetisWebPolicy.isSameOrigin(url, server: server)
        if sameOrigin && mainFrame && MetisWebPolicy.isLoginURL(url) {
            decisionHandler(.cancel)
            loseAuthorization()
            return
        }
        if sameOrigin || (!mainFrame && MetisWebPolicy.permitsSubframe(url, server: server,
                                                                      firstPartySource: trusted(action.sourceFrame.securityOrigin))) {
            if action.shouldPerformDownload { decisionHandler(.download); return }
            if action.targetFrame == nil {
                decisionHandler(.cancel)
                load(url)
            } else {
                decisionHandler(.allow)
            }
            return
        }
        // Blob downloads created by the first-party page retain its origin.
        if action.shouldPerformDownload, trusted(action.sourceFrame.securityOrigin),
           MetisWebPolicy.isFirstPartyBlob(url, server: server) {
            decisionHandler(.download)
            return
        }
        if mainFrame { _ = openExternal(action) }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard !invalidated, let server, let url = response.response.url,
              MetisWebPolicy.isSameOrigin(url, server: server) || MetisWebPolicy.isFirstPartyBlob(url, server: server)
                || (!response.isForMainFrame && (url.scheme?.lowercased() == "data" || url.absoluteString == "about:blank")) else {
            decisionHandler(.cancel)
            return
        }
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
            if http.statusCode == 401 {
                decisionHandler(.cancel)
                loseAuthorization()
                return
            }
            if http.statusCode >= 400 {
                decisionHandler(.cancel)
                lastMainURL = url
                isLoading = false
                errorMessage = String(localized: "The Metis workspace could not load. Check your connection and try again.")
                return
            }
        }
        let attachment = (response.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().hasPrefix("attachment") == true
        decisionHandler(!response.canShowMIMEType || attachment ? .download : .allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !invalidated else { return }
        errorMessage = nil
        isLoading = true
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard !invalidated else { return }
        // A new document must advertise its own entry point. Provisional
        // downloads and cancelled navigations leave the current page intact.
        appControlsAvailable = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !invalidated else { return }
        isLoading = false
        progress = 1
        if let url = webView.url, let server, MetisWebPolicy.isSameOrigin(url, server: server) { lastMainURL = url }
        validateAuthorization()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !invalidated else { return }
        isLoading = false
        errorMessage = String(localized: "The Metis workspace closed unexpectedly. Reload to continue.")
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { register(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { register(download) }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(!invalidated && challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}

extension MetisWebWorkspace: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !invalidated, action.targetFrame == nil, let url = action.request.url, let server else { return nil }
        if MetisWebPolicy.isSameOrigin(url, server: server) { load(url) } else { _ = openExternal(action) }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(!invalidated && trusted(origin) && trusted(frame.securityOrigin) ? .prompt : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard trusted(frame.securityOrigin) else { completionHandler(); return }
        let dialog = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        var resolved = false
        let finish = { [weak self, weak dialog] in
            guard !resolved else { return }
            resolved = true
            if let dialog { self?.dialogFinished(dialog) }
            completionHandler()
        }
        dialog.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in finish() })
        if !presentDialog(dialog, cancel: finish) { finish() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard trusted(frame.securityOrigin) else { completionHandler(false); return }
        let dialog = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        var resolved = false
        let finish: (Bool) -> Void = { [weak self, weak dialog] value in
            guard !resolved else { return }
            resolved = true
            if let dialog { self?.dialogFinished(dialog) }
            completionHandler(value)
        }
        dialog.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in finish(false) })
        dialog.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in finish(true) })
        if !presentDialog(dialog, cancel: { finish(false) }) { finish(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard trusted(frame.securityOrigin) else { completionHandler(nil); return }
        let dialog = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        dialog.addTextField { $0.text = defaultText }
        var resolved = false
        let finish: (String?) -> Void = { [weak self, weak dialog] value in
            guard !resolved else { return }
            resolved = true
            if let dialog { self?.dialogFinished(dialog) }
            completionHandler(value)
        }
        dialog.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in finish(nil) })
        dialog.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak dialog] _ in finish(dialog?.textFields?.first?.text) })
        if !presentDialog(dialog, cancel: { finish(nil) }) { finish(nil) }
    }
}

extension MetisWebWorkspace: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let key = ObjectIdentifier(download)
        guard !invalidated, var entry = downloads[key], let server, let source = response.url,
              MetisWebPolicy.isSameOrigin(source, server: server) || MetisWebPolicy.isFirstPartyBlob(source, server: server) else {
            completionHandler(nil)
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MetisDownload-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            let file = folder.appendingPathComponent(MetisWebPolicy.safeDownloadName(suggestedFilename), isDirectory: false)
            entry.file = file
            downloads[key] = entry
            ownedFiles[file] = folder
            completionHandler(file)
        } catch {
            errorMessage = String(localized: "The downloaded file could not be saved.")
            completionHandler(nil)
        }
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        guard !invalidated, downloads[ObjectIdentifier(download)] != nil, let server, let url = request.url,
              MetisWebPolicy.isSameOrigin(url, server: server) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(!invalidated && challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let entry = downloads.removeValue(forKey: ObjectIdentifier(download)), let file = entry.file else { return }
        guard !invalidated else { removeOwnedFile(file); return }
        sharedFile = file
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let entry = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        if let file = entry.file { removeOwnedFile(file) }
        guard !invalidated, (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = String(localized: "The file could not be downloaded. Try again.")
    }
}
#endif
