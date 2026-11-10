import SwiftUI
import WatchConnectivity

@MainActor
final class WatchRelay: NSObject, ObservableObject, WCSessionDelegate {
    @Published var openChatID: String?
    var client: MetisAPI? {
        didSet { if oldValue !== client { publishSessionState() } }
    }
    var enabled = false {
        didSet { if oldValue != enabled { publishSessionState() } }
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func publishSessionState() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(["sessionActive": enabled && client != nil, "revision": UUID().uuidString])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in publishSessionState() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(
        _ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let action = message["action"] as? String
        let chatID = message["chatId"] as? String
        let text = message["text"] as? String
        let messageID = message["messageId"] as? String
        let approvalID = message["approvalId"] as? String
        let version = message["version"] as? String
        let offset = Int(message["offset"] as? String ?? "") ?? 0
        let selectedModel = message["modelId"] as? String
        let parameterData = message["modelParams"] as? Data
        Task { @MainActor in
            guard enabled, UIApplication.shared.isProtectedDataAvailable, let client else {
                replyHandler(["error": "Unlock iPhone and enable Watch access in Metis."])
                return
            }
            do {
                switch action {
                case "chats":
                    let chats = try await client.chats()
                    guard self.client === client, enabled else { break }
                    let pending = chats.filter { $0.pendingApproval != nil || $0.pendingQuestion != nil }
                    let other = chats.filter { $0.pendingApproval == nil && $0.pendingQuestion == nil }
                    replyHandler(["chats": (pending + other).prefix(50).map(chatSummary)])
                    return
                case "create":
                    let chat = try await client.createChat()
                    guard self.client === client, enabled else { break }
                    replyHandler(["chat": chatSummary(chat)])
                    return
                case "configuration":
                    guard let chatID else { break }
                    let chat = try await client.chat(id: chatID)
                    let models = try await client.models().sorted { $0.id < $1.id }
                    guard offset >= 0, offset <= models.count else { break }
                    let modelID = try? await client.modelForSend(chatModel: chat.chat.modelId)
                    let selections = models.first(where: { $0.id == modelID })?.selections(chat.chat.modelParams ?? []) ?? []
                    guard self.client === client, enabled, UIApplication.shared.isProtectedDataAvailable else { break }
                    var page: [MetisModel] = []
                    var next = offset
                    while next < models.count {
                        let candidate = page + [models[next]]
                        let data = try JSONEncoder().encode(candidate)
                        guard data.count < 48_000 else {
                            if page.isEmpty { throw MetisError.unexpectedResponse }
                            break
                        }
                        page = candidate
                        next += 1
                    }
                    replyHandler(["configuration": try JSONEncoder().encode(WatchConfiguration(models: page, modelID: modelID, selections: selections, nextOffset: next < models.count ? next : nil))])
                    return
                case "transcript":
                    guard let chatID else { break }
                    let page = try await client.chat(id: chatID)
                    let messages = page.chat.messages.suffix(12).map {
                        WatchTranscript.Message(id: $0.id, role: $0.role, content: String($0.content.prefix(1000)))
                    }
                    guard self.client === client, enabled, UIApplication.shared.isProtectedDataAvailable else { break }
                    replyHandler(["transcript": try JSONEncoder().encode(WatchTranscript(messages: messages, status: page.chat.runStatus ?? "idle"))])
                    return
                case "pending":
                    guard let chatID else { break }
                    let chat = try await client.chat(id: chatID)
                    let approval = chat.chat.pendingApproval == nil ? nil : try await client.approval(chatID: chatID)
                    guard self.client === client, enabled, UIApplication.shared.isProtectedDataAvailable else { break }
                    var details: [String: String] = [:]
                    if let approval {
                        details["approvalId"] = approval.id
                        details["approvalTitle"] = String(approval.title.prefix(180))
                        details["version"] = String(approval.version)
                    }
                    if let question = chat.chat.pendingQuestion, question.status == nil || question.status == "waiting_for_user" {
                        details["question"] = String((question.title ?? question.questions.first?.question ?? "Agent question").prefix(180))
                    }
                    replyHandler(["pending": details])
                    return
                case "deny":
                    guard let chatID, let approvalID, let version,
                          let approval = try await client.approval(chatID: chatID),
                          approval.id == approvalID, String(approval.version) == version else {
                        replyHandler(["error": "The approval changed. Refresh it before deciding."])
                        return
                    }
                    guard self.client === client, enabled, UIApplication.shared.isProtectedDataAvailable else { break }
                    try await client.decide(approval, allow: false)
                    guard self.client === client, enabled else { break }
                    replyHandler(["denied": true])
                    return
                case "prompt":
                    guard let chatID, let text, let messageID, UUID(uuidString: messageID) != nil,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          text.count <= 2_000 else { break }
                    let chat = try await client.chat(id: chatID)
                    let model = try await client.modelForSend(chatModel: selectedModel ?? chat.chat.modelId)
                    let catalog = try await client.models()
                    guard let contract = catalog.first(where: { $0.id == model }) else { throw MetisError.unavailableModel }
                    let selections = try parameterData.map { try JSONDecoder().decode([ModelSelection].self, from: $0) }
                        ?? contract.selections(chat.chat.modelParams ?? [])
                    try contract.validate(selections)
                    guard self.client === client, enabled, UIApplication.shared.isProtectedDataAvailable else { break }
                    let run = try await client.send(chatID: chatID, message: text, messageID: messageID, modelID: model, modelParams: selections)
                    guard self.client === client, enabled else { break }
                    replyHandler(["jobId": run.id, "status": run.status])
                    return
                case "open":
                    guard let chatID else { break }
                    _ = try await client.chat(id: chatID)
                    guard self.client === client, enabled else { break }
                    openChatID = chatID
                    replyHandler(["opened": true])
                    return
                default: break
                }
                replyHandler(["error": "The request is no longer available."])
            } catch {
                replyHandler(["error": "Metis could not complete the request. Check the iPhone and try again."])
            }
        }
    }

    private func chatSummary(_ chat: ChatSummary) -> [String: String] {
        [
            "id": chat.id,
            "title": String(chat.title.prefix(180)),
            "status": chat.runStatus ?? "idle",
            "attention": chat.pendingApproval != nil || chat.pendingQuestion != nil ? "yes" : "no",
        ]
    }
}
