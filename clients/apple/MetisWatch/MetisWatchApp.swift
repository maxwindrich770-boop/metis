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
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let online = session.isReachable
        let active = session.receivedApplicationContext["sessionActive"] as? Bool
        Task { @MainActor in
            reachable = online
            sessionAvailable = active
            sessionRevision &+= 1
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let online = session.isReachable
        Task { @MainActor in reachable = online }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
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

    func send(chat: WatchChat, text: String, messageID: String) async throws {
        let result = try await call(["action": "prompt", "chatId": chat.id, "text": text, "messageId": messageID])
        guard result["jobId"] as? String != nil else { throw RelayError.unavailable }
    }

    func open(chat: WatchChat) async throws {
        let result = try await call(["action": "open", "chatId": chat.id])
        guard result["opened"] as? Bool == true else { throw RelayError.unavailable }
    }

    private func call(_ message: [String: String]) async throws -> [String: Any] {
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
                Section("Chats") {
                    ForEach(chats.filter { !$0.needsAttention }) { chat in chatLink(chat) }
                    Button("New chat", systemImage: "square.and.pencil") { Task { await create() } }
                        .disabled(creating || !relay.reachable || relay.sessionAvailable == false)
                }
                if let lastSync { Text(lastSync, style: .time).font(.caption).foregroundStyle(.secondary) }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
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
            TextField("Prompt", text: $draft)
                .onChange(of: draft) { _ in if !busy { messageID = UUID().uuidString } }
                .disabled(busy)
            Button("Send", systemImage: "arrow.up.circle") { confirmation = true }
                .disabled(busy || !relay.reachable || pending?.approvalID != nil || pending?.question != nil ||
                          draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2_000)
            Button("Open on iPhone", systemImage: "iphone") {
                Task {
                    do { try await relay.open(chat: chat); notice = "Open Metis on your iPhone." }
                    catch { notice = error.localizedDescription }
                }
            }
            .disabled(!relay.reachable)
        }
        .navigationTitle(chat.title)
        .task { if chat.needsAttention { await loadPending() } }
        .confirmationDialog("Send to \(chat.title)?", isPresented: $confirmation, titleVisibility: .visible) {
            Button("Send prompt") { Task { await send() } }
        }
        .confirmationDialog("Deny this request?", isPresented: $confirmDeny, titleVisibility: .visible) {
            Button("Deny approval", role: .destructive) { Task { await deny() } }
        }
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
            try await relay.send(chat: chat, text: draft, messageID: messageID)
            draft = ""
            messageID = UUID().uuidString
            notice = "Accepted by Metis."
        } catch { notice = error.localizedDescription }
    }
}
