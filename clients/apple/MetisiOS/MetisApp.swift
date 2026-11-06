import SwiftUI

@main
struct MetisApp: App {
    @UIApplicationDelegateAdaptor(MetisAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup { RootView(push: appDelegate, watch: appDelegate.watch) }
    }
}

private struct RootView: View {
    private enum Destination { case chats, activity, projects, settings }

    @ObservedObject var push: MetisAppDelegate
    @ObservedObject var watch: WatchRelay
    @ObservedObject private var intentInbox = MetisIntentInbox.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("metisServer") private var savedServer = ""
    private let installationID = InstallationIdentity.current
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var client: MetisAPI?
    @State private var chats: [ChatSummary] = []
    @State private var navigation: [ChatSummary] = []
    @State private var search = ""
    @State private var includeArchived = false
    @State private var chatCursor = 0
    @State private var chatRevision = 0
    @State private var changedChats: Set<String> = []
    @State private var needsChatSnapshot = false
    @State private var busy = false
    @State private var notice: String?
    @State private var destination = Destination.chats
    @State private var pushRequested = false
    @State private var pushRegistered = false
    @State private var pushBusy = false
    @State private var pushSettings = false
    @State private var pushEvents = Set(MobilePushKind.allCases)
    @State private var watchEnabled = false
    @State private var shortcutDraft: MetisIntentInbox.Draft?
    @State private var composerDrafts: [String: ComposerDraft] = [:]
    @State private var restoreAttempted = false
    @State private var canRetrySession = false
    @State private var flushingLogouts = false

    var body: some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if client == nil { await restoreSession() }
            await flushLogouts()
        }
    }

    @ViewBuilder private var content: some View {
        if let client {
            TabView(selection: $destination) {
                chatList(client)
                    .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                    .tag(Destination.chats)
                ActivityView(client: client, chats: chats, openChat: { id in Task { await openChat(id, client: client) } },
                             unauthorized: { expire(client) })
                    .tabItem { Label("Activity", systemImage: "bell") }
                    .badge(chats.filter { $0.pendingApproval != nil || $0.pendingQuestion != nil }.count)
                    .tag(Destination.activity)
                ProjectsView(client: client, openChat: { id in Task { await openChat(id, client: client) } },
                             unauthorized: { expire(client) })
                    .tabItem { Label("Projects", systemImage: "folder") }
                    .tag(Destination.projects)
                ConnectionSettingsView(client: client, installationID: installationID,
                                       watchEnabled: $watchEnabled, pushEnabled: pushRegistered,
                                       showPush: { pushSettings = true },
                                       signOut: { Task { await signOut(client) } }, busy: busy,
                                       status: notice) {
                    pushRequested = false
                    pushRegistered = false
                    saveSessionPreferences()
                } unauthorized: { expire(client) }
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(Destination.settings)
            }
            .task(id: intentInbox.draft?.id) {
                if let draft = intentInbox.draft {
                    shortcutDraft = draft
                    intentInbox.draft = nil
                }
            }
            .task(id: intentInbox.activityRequest) {
                if intentInbox.activityRequest != nil {
                    destination = .activity
                    intentInbox.activityRequest = nil
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                if shortcutDraft == nil, let text = SharedPrompt.take() {
                    shortcutDraft = .init(text: text)
                }
                await refresh(client)
                if !Task.isCancelled { await syncChats(client) }
            }
            .onChange(of: watchEnabled) { _, enabled in
                watch.enabled = enabled
                saveSessionPreferences()
            }
            .task(id: watch.openChatID) {
                guard let id = watch.openChatID else { return }
                defer { if watch.openChatID == id { watch.openChatID = nil } }
                await openChat(id, client: client)
            }
            .task(id: pushRequested ? push.token : nil) {
                if pushRequested, let token = push.token { await registerPush(client, token: token) }
            }
            .onChange(of: push.registrationFailed) { _, failed in
                if failed && pushRequested {
                    pushRequested = false
                    notice = "This build could not register for Apple push notifications."
                }
            }
            .task(id: push.notificationID) {
                guard let id = push.notificationID else { return }
                defer { if push.notificationID == id { push.notificationID = nil } }
                do { await openChat(try await client.notificationChat(id: id), client: client) }
                catch MetisError.unauthorized { expire(client) }
                catch { if !Task.isCancelled { notice = message(for: error) } }
            }
            .sheet(isPresented: $pushSettings) {
                PushSettingsView(events: $pushEvents, enabled: pushRequested, busy: pushBusy, status: notice) {
                    Task { await changePush(client) }
                } save: {
                    if let token = push.token { Task { await registerPush(client, token: token) } }
                }
            }
            .sheet(item: $shortcutDraft) { draft in
                ShortcutDraftView(draft: draft, chats: chats) { chat, text in
                    let combined = composerDrafts[chat.id].map { $0.text + "\n\n" + text } ?? text
                    composerDrafts[chat.id] = ComposerDraft(text: combined)
                    destination = .chats
                    navigation = [chat]
                } create: { text in
                    Task { await newChat(client, draft: text) }
                }
            }
            .task(id: includeArchived) { await refresh(client) }
            .task(id: chatRevision) {
                guard scenePhase == .active, chatRevision > 0 else { return }
                let revision = chatRevision
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                guard scenePhase == .active else { return }
                await refreshChanges(client, revision: revision)
            }
        } else {
            signInForm
        }
    }

    private func chatList(_ client: MetisAPI) -> some View {
        NavigationStack(path: $navigation) {
            List(chats.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { chat in
                NavigationLink(value: chat) {
                    HStack {
                        if chat.pinned == true { Image(systemName: "pin.fill").accessibilityLabel("Pinned") }
                        Text(chat.title.isEmpty ? "Untitled chat" : chat.title)
                        Spacer()
                        if chat.archived == true { Image(systemName: "archivebox").accessibilityLabel("Archived") }
                        if let status = chat.runStatus, status != "idle" {
                            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu {
                    Button(chat.pinned == true ? "Unpin" : "Pin") {
                        Task { await update(client, chat: chat, pinned: chat.pinned != true) }
                    }
                    Button(chat.archived == true ? "Restore" : "Archive") {
                        Task { await update(client, chat: chat, archived: chat.archived != true) }
                    }
                }
            }
            .overlay {
                if chats.isEmpty {
                    ContentUnavailableView("No chats", systemImage: "bubble.left.and.bubble.right")
                } else if !search.isEmpty && !chats.contains(where: { $0.title.localizedCaseInsensitiveContains(search) }) {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search)
            .navigationTitle("Chats")
            .navigationDestination(for: ChatSummary.self) { chat in
                ChatDetail(chat: chat, client: client, draft: Binding(
                    get: { composerDrafts[chat.id] },
                    set: { if self.client === client { composerDrafts[chat.id] = $0 } }
                )) {
                    guard self.client === client else { return }
                    clearSession(notice: MetisError.unauthorized.localizedDescription)
                }
            }
            .refreshable { await refresh(client) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New chat", systemImage: "square.and.pencil") { Task { await newChat(client) } }
                        .disabled(busy)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Filter chats", systemImage: "line.3.horizontal.decrease.circle") {
                        Toggle("Show archived chats", isOn: $includeArchived)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { status }
        }
    }

    private var signInForm: some View {
        NavigationStack {
            Form {
                Section("Connect to Metis") {
                    TextField("https://metis.example.com", text: $server)
                        .accessibilityIdentifier("metis.server")
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .accessibilityIdentifier("metis.username")
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .accessibilityIdentifier("metis.password")
                        .textContentType(.password)
                    Button("Sign in") { Task { await signIn() } }
                        .accessibilityIdentifier("metis.signIn")
                        .disabled(busy || server.isEmpty || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    if canRetrySession {
                        Button("Retry saved session") { Task { await restoreSession() } }
                    }
                }
                status
            }
            .disabled(busy)
            .navigationTitle("Metis")
            .onAppear { if server.isEmpty { server = savedServer } }
        }
    }

    @ViewBuilder private var status: some View {
        if busy {
            ProgressView().padding()
        }
        if let notice {
            Text(notice).font(.footnote).padding()
        }
    }

    private func signIn() async {
        guard !busy else { return }
        busy = true
        notice = nil
        defer {
            password = ""
            busy = false
        }
        do {
            let address = try ServerAddress(server)
            let candidate = MetisAPI(address: address)
            let authenticatedChats = try await candidate.signIn(username: username, password: password)
            let stored = await persist(candidate)
            savedServer = address.url.absoluteString
            connect(candidate, chats: authenticatedChats, stored: stored)
            Task { await flushLogouts() }
        } catch MetisError.unauthorized {
            notice = "Sign-in failed. Check your credentials and server session settings."
        } catch {
            notice = message(for: error)
        }
    }

    private func persist(_ candidate: MetisAPI) async -> StoredMetisSession? {
        guard var stored = candidate.sessionRecord() else {
            _ = MetisSessionVault.close()
            return nil
        }
        let ticket = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        do {
            try await candidate.enrollLogoutTicket(ticket)
            stored.revocationTicket = ticket
        } catch {}
        MetisSessionVault.replace(stored)
        return stored
    }

    private func restoreSession() async {
        guard !restoreAttempted, !busy, client == nil, UIApplication.shared.isProtectedDataAvailable else { return }
        restoreAttempted = true
        canRetrySession = false
        guard let stored = MetisSessionVault.active, stored.origin == savedServer,
              let address = try? ServerAddress(stored.origin) else { return }
        guard stored.expiresAt > Date() else {
            _ = MetisSessionVault.close()
            notice = MetisError.unauthorized.localizedDescription
            return
        }
        busy = true
        defer { busy = false }
        let candidate = MetisAPI(address: address, restore: stored)
        do {
            let authenticatedChats = try await candidate.chats()
            guard !Task.isCancelled, client == nil else { restoreAttempted = false; return }
            notice = nil
            connect(candidate, chats: authenticatedChats, stored: stored)
            if stored.pushEvents != nil {
                let renewed = await push.renewPush()
                guard client === candidate else { return }
                if renewed { pushRequested = true; pushRegistered = true }
                else {
                    try? await candidate.revokePush(installationID: installationID)
                    saveSessionPreferences()
                }
            }
        } catch MetisError.unauthorized {
            _ = MetisSessionVault.close()
            notice = MetisError.unauthorized.localizedDescription
        } catch {
            restoreAttempted = false
            if !Task.isCancelled {
                canRetrySession = true
                notice = message(for: error)
            }
        }
    }

    private func connect(_ candidate: MetisAPI, chats: [ChatSummary], stored: StoredMetisSession?) {
        self.chats = chats
        client = candidate
        intentInbox.statusClient = candidate
        watch.client = candidate
        watchEnabled = stored?.watchEnabled ?? false
        watch.enabled = watchEnabled
        if let events = stored?.pushEvents { pushEvents = Set(events.compactMap(MobilePushKind.init(rawValue:))) }
    }

    private func saveSessionPreferences() {
        MetisSessionVault.setPreferences(pushEvents: pushRegistered ? pushEvents.map(\.rawValue).sorted() : nil,
                                         watchEnabled: watchEnabled)
    }

    private func flushLogouts() async {
        guard !flushingLogouts else { return }
        flushingLogouts = true
        defer { flushingLogouts = false }
        for pending in MetisSessionVault.pending {
            guard !Task.isCancelled, let address = try? ServerAddress(pending.origin) else { continue }
            let temporary = MetisAPI(address: address)
            do {
                try await temporary.redeemLogoutTicket(pending.ticket)
                MetisSessionVault.removePending(pending.id)
            } catch {}
        }
    }

    private func refresh(_ current: MetisAPI) async {
        let archived = includeArchived
        let revision = chatRevision
        do {
            let updated = try await current.chats(includeArchived: archived)
            guard client === current, !Task.isCancelled, archived == includeArchived,
                  revision == chatRevision else { return }
            chats = updated
            notice = nil
        } catch {
            guard client === current, !Task.isCancelled else { return }
            if case MetisError.unauthorized = error {
                clearSession(notice: error.localizedDescription)
            } else {
                notice = message(for: error)
            }
        }
    }

    private func refreshChanges(_ current: MetisAPI, revision: Int) async {
        let archived = includeArchived
        let ids = changedChats
        let full = needsChatSnapshot || ids.count > 100
        guard full || !ids.isEmpty else { return }
        do {
            let updated = try await current.chats(includeArchived: archived, ids: full ? nil : ids)
            guard client === current, !Task.isCancelled, archived == includeArchived, revision == chatRevision else { return }
            if full {
                chats = updated
            } else {
                let unchanged = chats.filter { !ids.contains($0.id) }
                chats = (unchanged + updated).sorted {
                    if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
                    return ($0.lastMessageSent ?? $0.createdAt ?? "") > ($1.lastMessageSent ?? $1.createdAt ?? "")
                }
            }
            changedChats.removeAll()
            needsChatSnapshot = false
            notice = nil
        } catch MetisError.unauthorized {
            if !Task.isCancelled { expire(current) }
        } catch {
            if client === current, !Task.isCancelled { notice = message(for: error) }
        }
    }

    private func newChat(_ current: MetisAPI, draft: String? = nil) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let chat = try await current.createChat()
            guard client === current else { return }
            if !chats.contains(where: { $0.id == chat.id }) { chats.insert(chat, at: 0) }
            if let draft { composerDrafts[chat.id] = ComposerDraft(text: draft) }
            destination = .chats
            navigation.append(chat)
        } catch MetisError.unauthorized {
            clearSession(notice: MetisError.unauthorized.localizedDescription)
        } catch {
            notice = message(for: error)
        }
    }

    private func update(_ current: MetisAPI, chat: ChatSummary, pinned: Bool? = nil, archived: Bool? = nil) async {
        do {
            try await current.setChat(chat.id, pinned: pinned, archived: archived)
            await refresh(current)
        } catch MetisError.unauthorized { expire(current) }
        catch { notice = message(for: error) }
    }

    private func openChat(_ id: String, client current: MetisAPI) async {
        do {
            let detail = try await current.chat(id: id).chat
            guard client === current, !Task.isCancelled else { return }
            destination = .chats
            navigation = [ChatSummary(id: id, title: detail.title, runStatus: detail.runStatus, pinned: nil, archived: nil, projectId: nil)]
        } catch MetisError.unauthorized { expire(current) }
        catch { if !Task.isCancelled { notice = message(for: error) } }
    }

    private func expire(_ current: MetisAPI) {
        guard client === current else { return }
        clearSession(notice: MetisError.unauthorized.localizedDescription)
    }

    private func changePush(_ current: MetisAPI) async {
        guard !pushBusy else { return }
        pushBusy = true
        defer { pushBusy = false }
        do {
            if pushRequested {
                try await current.revokePush(installationID: installationID)
                pushRequested = false
                pushRegistered = false
                saveSessionPreferences()
                notice = "Push alerts disabled for this account."
            } else {
                guard try await current.pushSupported() else {
                    notice = "Apple push notifications are unavailable on this server."
                    return
                }
                guard try await push.requestPush() else {
                    notice = "Allow notifications in iPhone Settings first."
                    return
                }
                if client === current { pushRequested = true }
            }
        } catch MetisError.unauthorized { expire(current) }
        catch { notice = message(for: error) }
    }

    private func registerPush(_ current: MetisAPI, token: String) async {
        guard !pushBusy, let topic = Bundle.main.bundleIdentifier else { return }
        pushBusy = true
        defer { pushBusy = false }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await current.registerPush(installationID: installationID, token: token, topic: topic, environment: environment,
                                           events: pushEvents.map(\.rawValue).sorted())
            guard client === current, pushRequested else {
                try? await current.revokePush(installationID: installationID)
                return
            }
            pushRegistered = true
            saveSessionPreferences()
            notice = "Push alerts enabled."
        } catch MetisError.unauthorized { expire(current) }
        catch {
            if client === current, pushRequested, !Task.isCancelled {
                pushRequested = false
                notice = message(for: error)
            }
        }
    }

    private func syncChats(_ current: MetisAPI) async {
        var delay = 1
        while !Task.isCancelled, client === current {
            do {
                try await current.observeChats(after: chatCursor) { event in
                    guard client === current, !Task.isCancelled else { return false }
                    if let id = event.id { chatCursor = max(id, chatCursor) }
                    if event.name == "chat" {
                        if let id = event.payload?.chatId { changedChats.insert(id) }
                        else { needsChatSnapshot = true }
                        chatRevision &+= 1
                    } else if event.name == "ready" {
                        needsChatSnapshot = true
                        chatRevision &+= 1
                    }
                    delay = 1
                    return true
                }
            } catch MetisError.unauthorized {
                if client === current { clearSession(notice: MetisError.unauthorized.localizedDescription) }
                return
            } catch {}
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            delay = min(delay * 2, 30)
        }
    }

    private func signOut(_ current: MetisAPI) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let stored = MetisSessionVault.active
        let queued = MetisSessionVault.close()
        clearSession(invalidate: false)
        defer { current.invalidate() }
        do {
            try await current.signOut()
            if let ticket = stored?.revocationTicket { MetisSessionVault.removePending(ticket) }
        } catch {
            if queued && stored?.revocationTicket != nil {
                notice = "Signed out on this device. Metis will revoke the old session when it can reach the server."
            } else {
                notice = "Signed out on this device. The server did not confirm revocation."
            }
        }
    }

    private func clearSession(notice: String? = nil, invalidate: Bool = true) {
        if invalidate {
            _ = MetisSessionVault.close()
            client?.invalidate()
        }
        client = nil
        intentInbox.statusClient = nil
        watch.client = nil
        watch.enabled = false
        watchEnabled = false
        shortcutDraft = nil
        composerDrafts = [:]
        chats = []
        navigation = []
        chatCursor = 0
        chatRevision = 0
        changedChats = []
        needsChatSnapshot = false
        search = ""
        includeArchived = false
        destination = .chats
        pushRequested = false
        pushRegistered = false
        pushSettings = false
        canRetrySession = false
        pushEvents = Set(MobilePushKind.allCases)
        username = ""
        password = ""
        self.notice = notice
    }
}

func message(for error: Error) -> String {
    if let network = error as? URLError {
        switch network.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "Connection lost. Reconnect to your network and try again."
        case .timedOut:
            return "Metis did not respond in time. Try again."
        default: break
        }
    }
    guard let error = error as? MetisError else {
        return "Could not connect. Check the server address, connection and TLS certificate."
    }
    return error.localizedDescription
}
