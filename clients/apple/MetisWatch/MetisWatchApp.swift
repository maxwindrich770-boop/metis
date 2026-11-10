import SwiftUI
import WatchConnectivity

@main
struct MetisWatchApp: App {
    @StateObject private var relay = PhoneConnection()

    var body: some Scene {
        WindowGroup { WatchChats(relay: relay) }
    }
}

private struct WatchChat: Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    let needsAttention: Bool

    init?(_ row: [String: String]) {
        guard let id = row["id"], let title = row["title"], let status = row["status"] else { return nil }
        self.id = id
        self.title = title
        self.status = status
        needsAttention = row["attention"] == "yes"
    }
}

private struct WatchPending {
    let approvalID: String?
    let approvalTitle: String?
    let version: String?
    let question: String?
}

private enum RelayError: LocalizedError {
    case unavailable
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "iPhone unavailable. Open Metis on your iPhone."
        case .rejected(let reason): return reason
        }
    }
}

@MainActor
private final class PhoneConnection: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var reachable = false
    @Published private(set) var sessionAvailable: Bool?
    @Published private(set) var sessionRevision = 0

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["METIS_WATCH_FIXTURE"] == "1" {
            reachable = true
            sessionAvailable = true
        }
        #endif
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["METIS_WATCH_FIXTURE"] == "1" { return }
        #endif
        let online = session.isReachable
        let active = session.receivedApplicationContext["sessionActive"] as? Bool
        Task { @MainActor in
            reachable = online
            sessionAvailable = active
            sessionRevision &+= 1
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["METIS_WATCH_FIXTURE"] == "1" { return }
        #endif
        let online = session.isReachable
        Task { @MainActor in reachable = online }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["METIS_WATCH_FIXTURE"] == "1" { return }
        #endif
        let active = applicationContext["sessionActive"] as? Bool
        Task { @MainActor in sessionAvailable = active; sessionRevision &+= 1 }
    }

    func chats() async throws -> [WatchChat] {
        let result = try await call(["action": "chats"])
        guard let rows = result["chats"] as? [[String: String]] else { throw RelayError.unavailable }
        return rows.compactMap(WatchChat.init)
    }

    func createChat() async throws -> WatchChat {
        let result = try await call(["action": "create"])
        guard let row = result["chat"] as? [String: String], let chat = WatchChat(row) else { throw RelayError.unavailable }
        return chat
    }

    func pending(chat: WatchChat) async throws -> WatchPending {
        let result = try await call(["action": "pending", "chatId": chat.id])
        guard let row = result["pending"] as? [String: String] else { throw RelayError.unavailable }
        return WatchPending(approvalID: row["approvalId"], approvalTitle: row["approvalTitle"],
                            version: row["version"], question: row["question"])
    }

    func deny(chat: WatchChat, pending: WatchPending) async throws {
        guard let approvalID = pending.approvalID, let version = pending.version else { throw RelayError.unavailable }
        let result = try await call(["action": "deny", "chatId": chat.id, "approvalId": approvalID, "version": version])
        guard result["denied"] as? Bool == true else { throw RelayError.unavailable }
    }

    func configuration(chat: WatchChat) async throws -> WatchConfiguration {
        var models: [MetisModel] = []
        var offset = 0
        var selected: String?
        var selections: [ModelSelection] = []
        repeat {
            let result = try await call(["action": "configuration", "chatId": chat.id, "offset": String(offset)])
            guard let data = result["configuration"] as? Data else { throw RelayError.unavailable }
            let page = try JSONDecoder().decode(WatchConfiguration.self, from: data)
            models.append(contentsOf: page.models)
            selected = page.modelID
            selections = page.selections
            guard let next = page.nextOffset else { break }
            guard next > offset, !Task.isCancelled else { throw RelayError.unavailable }
            offset = next
        } while true
        return WatchConfiguration(models: models, modelID: selected, selections: selections, nextOffset: nil)
    }

    func transcript(chat: WatchChat) async throws -> WatchTranscript {
        let result = try await call(["action": "transcript", "chatId": chat.id])
        guard let data = result["transcript"] as? Data else { throw RelayError.unavailable }
        return try JSONDecoder().decode(WatchTranscript.self, from: data)
    }

    func send(chat: WatchChat, text: String, messageID: String, modelID: String, selections: [ModelSelection]) async throws {
        let result = try await call(["action": "prompt", "chatId": chat.id, "text": text, "messageId": messageID,
                                     "modelId": modelID, "modelParams": try JSONEncoder().encode(selections)])
        guard result["jobId"] as? String != nil else { throw RelayError.unavailable }
    }

    func open(chat: WatchChat) async throws {
        let result = try await call(["action": "open", "chatId": chat.id])
        guard result["opened"] as? Bool == true else { throw RelayError.unavailable }
    }

    private func call(_ message: [String: Any]) async throws -> [String: Any] {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["METIS_WATCH_FIXTURE"] == "1" {
            return try WatchPreviewFixture.reply(message)
        }
        #endif
        guard WCSession.default.isReachable, sessionAvailable != false else { throw RelayError.unavailable }
        let revision = sessionRevision
        let result: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            WCSession.default.sendMessage(message, replyHandler: { response in
                if let error = response["error"] as? String { continuation.resume(throwing: RelayError.rejected(error)) }
                else { continuation.resume(returning: response) }
            }, errorHandler: { _ in continuation.resume(throwing: RelayError.unavailable) })
        }
        guard revision == sessionRevision, sessionAvailable != false, !Task.isCancelled else {
            throw RelayError.unavailable
        }
        return result
    }
}

private struct WatchChats: View {
    @ObservedObject var relay: PhoneConnection
    @State private var chats: [WatchChat] = []
    @State private var notice: String?
    @State private var selectedChatID: String?
    @State private var lastSync: Date?
    @State private var creating = false

    var body: some View {
        // NavigationStack requires watchOS 9; this stack also supports watchOS 8.
        NavigationView {
            List {
                if let notice { Text(notice).font(.footnote) }
                let pending = chats.filter(\.needsAttention)
                if !pending.isEmpty {
                    Section("Needs attention") {
                        ForEach(pending) { chat in chatLink(chat) }
                    }
                }
                Section("Recent chats") {
                    if chats.isEmpty && notice == nil { Text("No chats yet. Create your first chat.").font(.footnote) }
                    ForEach(chats.filter { !$0.needsAttention }) { chat in chatLink(chat) }
                    Button { Task { await create() } } label: { Label("New chat", systemImage: "square.and.pencil") }
                        .disabled(creating || !relay.reachable || relay.sessionAvailable == false)
                }
                if let lastSync { Text(lastSync, style: .time).font(.caption).foregroundStyle(.secondary) }
                Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            .navigationTitle("Metis")
        }
        .task(id: "\(relay.reachable):\(relay.sessionRevision)") {
            if relay.reachable && relay.sessionAvailable != false { await refresh() }
            else {
                chats = []
                selectedChatID = nil
                notice = relay.sessionAvailable == false
                    ? "Sign in and enable Watch access in Metis on your iPhone."
                    : RelayError.unavailable.localizedDescription
            }
        }
        .onChange(of: relay.sessionRevision) { _ in
            chats = []
            selectedChatID = nil
            lastSync = nil
        }
    }

    private func chatLink(_ chat: WatchChat) -> some View {
        NavigationLink(destination: WatchPrompt(chat: chat, relay: relay),
                       tag: chat.id, selection: $selectedChatID) {
            VStack(alignment: .leading) {
                Text(chat.title)
                Text(chat.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption)
            }
        }
    }

    private func create() async {
        guard !creating else { return }
        creating = true
        defer { creating = false }
        do {
            let chat = try await relay.createChat()
            guard relay.reachable, relay.sessionAvailable != false else { return }
            if !chats.contains(where: { $0.id == chat.id }) { chats.insert(chat, at: 0) }
            selectedChatID = chat.id
        } catch { notice = error.localizedDescription }
    }

    private func refresh() async {
        do {
            let updated = try await relay.chats()
            guard relay.reachable, !Task.isCancelled else { return }
            chats = updated
            lastSync = Date()
            notice = nil
        } catch {
            if !Task.isCancelled { chats = []; selectedChatID = nil; notice = error.localizedDescription }
        }
    }
}

private struct WatchPrompt: View {
    let chat: WatchChat
    @ObservedObject var relay: PhoneConnection
    @State private var draft = ""
    @State private var messageID = UUID().uuidString
    @State private var busy = false
    @State private var confirmation = false
    @State private var notice: String?
    @State private var pending: WatchPending?
    @State private var confirmDeny = false
    @State private var models: [MetisModel] = []
    @State private var modelID = ""
    @State private var selections: [ModelSelection] = []
    @State private var transcript: WatchTranscript?
    @State private var loading = true
    @State private var refreshing = false
    private var model: MetisModel? { models.first { $0.id == modelID } }

    var body: some View {
        List {
            if let notice { Text(notice).font(.footnote) }
            if let title = pending?.approvalTitle {
                Section("Approval") {
                    Text(title)
                    Button("Deny approval", role: .destructive) { confirmDeny = true }
                        .disabled(busy || !relay.reachable)
                }
            }
            if let question = pending?.question {
                Section("Question") { Text(question) }
            }
            if loading { ProgressView("Loading chat") }
            if let transcript {
                NavigationLink(destination: WatchConversation(transcript: transcript)) {
                    Label("Conversation", systemImage: "text.bubble")
                }
                Text(transcript.status.replacingOccurrences(of: "_", with: " ")).font(.caption)
            }
            Section("Model") {
                if models.isEmpty && !loading { Text("No models available. Check providers on iPhone.").font(.footnote) }
                Picker("Model", selection: Binding(get: { modelID }, set: { value in
                    modelID = value
                    selections = model?.selections([]) ?? []
                    messageID = UUID().uuidString
                })) {
                    Text("Select model").tag("")
                    ForEach(models) { item in
                        Text(item.connectionLabel.map { item.title + " · " + $0 } ?? item.title).tag(item.id)
                    }
                }
                .disabled(busy || loading)
                if let model {
                    ForEach(model.parameters ?? []) { parameter in
                        if !parameter.values.isEmpty {
                            Picker(parameter.title, selection: parameterBinding(parameter)) {
                                Text("Provider default").tag("")
                                ForEach(parameter.values, id: \.value) { option in
                                    Text(option.displayName ?? option.value).tag(option.value)
                                }
                            }.disabled(busy)
                        }
                        if parameter.customNumber != nil {
                            TextField(parameter.title, text: parameterBinding(parameter))
                                .disabled(busy)
                            if let value = selections.first(where: { $0.id == parameter.id }),
                               !parameter.accepts(value.value) {
                                Text("Value outside the available model range.").font(.footnote)
                            }
                        }
                    }
                    if model.parameters?.isEmpty != false { Text("No model options available.").font(.footnote) }
                }
            }
            TextField("Prompt", text: $draft)
                .onChange(of: draft) { _ in if !busy { messageID = UUID().uuidString } }
                .disabled(busy)
            Button { confirmation = true } label: { Label("Send", systemImage: "arrow.up.circle") }
                .disabled(busy || loading || model == nil || (model.map { (try? $0.validate(selections)) == nil } ?? true) || !relay.reachable || relay.sessionAvailable == false || pending?.approvalID != nil || pending?.question != nil ||
                          draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2_000)
            Button {
                Task {
                    do { try await relay.open(chat: chat); notice = "Open Metis on your iPhone." }
                    catch { notice = error.localizedDescription }
                }
            }
            label: { Label("Open on iPhone", systemImage: "iphone") }
            .disabled(!relay.reachable)
            Button { Task { await refresh() } } label: { Label("Refresh chat", systemImage: "arrow.clockwise") }
                .disabled(busy || refreshing || !relay.reachable)
        }
        .navigationTitle(chat.title)
        .onChange(of: selections) { _ in if !busy { messageID = UUID().uuidString } }
        .task {
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                if !busy && relay.reachable && relay.sessionAvailable != false { await refreshConversation() }
            }
        }
        .confirmationDialog("Send to \(chat.title)?", isPresented: $confirmation, titleVisibility: .visible) {
            Button("Send prompt") { Task { await send() } }
        }
        .confirmationDialog("Deny this request?", isPresented: $confirmDeny, titleVisibility: .visible) {
            Button("Deny approval", role: .destructive) { Task { await deny() } }
        }
    }

    private func parameterBinding(_ parameter: ModelParameter) -> Binding<String> {
        Binding(get: { selections.first { $0.id == parameter.id }?.value ?? "" },
                set: { value in
                    selections.removeAll { $0.id == parameter.id }
                    if !value.isEmpty { selections.append(ModelSelection(id: parameter.id, value: value)) }
                })
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { loading = false; refreshing = false }
        do {
            let configuration = try await relay.configuration(chat: chat)
            models = configuration.models
            if model == nil {
                modelID = configuration.modelID ?? ""
                // SwiftUI's model-change callback runs after this task.
                selections = model?.selections(configuration.selections) ?? []
            } else {
                selections = model?.selections(selections) ?? []
            }
            await refreshConversation()
        } catch { notice = error.localizedDescription }
    }

    private func refreshConversation() async {
        do {
            transcript = try await relay.transcript(chat: chat)
            await loadPending()
        } catch { if !Task.isCancelled { notice = error.localizedDescription } }
    }

    private func loadPending() async {
        do { pending = try await relay.pending(chat: chat) }
        catch { if !Task.isCancelled { notice = error.localizedDescription } }
    }

    private func deny() async {
        guard !busy, let pending else { return }
        busy = true
        defer { busy = false }
        do {
            try await relay.deny(chat: chat, pending: pending)
            notice = "Denied on Metis."
            await loadPending()
        } catch {
            notice = error.localizedDescription
            await loadPending()
        }
    }

    private func send() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let model else { throw ModelContractError.changed }
            try model.validate(selections)
            try await relay.send(chat: chat, text: draft, messageID: messageID, modelID: modelID, selections: selections)
            draft = ""
            messageID = UUID().uuidString
            notice = "Accepted by Metis."
            await refreshConversation()
        } catch { notice = error.localizedDescription }
    }
}

private struct WatchConversation: View {
    let transcript: WatchTranscript
    var body: some View {
        List {
            if transcript.messages.isEmpty { Text("No messages yet.") }
            ForEach(transcript.messages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.role.capitalized).font(.caption).foregroundStyle(.secondary)
                    Text(message.content).font(.body)
                }
            }
        }
        .navigationTitle("Conversation")
    }
}
