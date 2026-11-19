import Foundation

struct ChatSummary: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let runStatus: String?
    let pinned: Bool?
    let archived: Bool?
    let projectId: String?
    var createdAt: String? = nil
    var lastMessageSent: String? = nil
    var pendingApproval: ApprovalMarker?
    var pendingQuestion: QuestionMarker?

    struct ApprovalMarker: Decodable, Hashable { let id: String }
    struct QuestionMarker: Decodable, Hashable { let questionId: String }
}

struct MetisRun: Decodable {
    let id: String
    let messageId: String?
    let status: String

    var active: Bool {
        ["queued", "running", "switching", "waiting_input", "waiting_for_user"].contains(status)
    }
}

struct MetisEvent {
    struct Payload: Decodable {
        let text: String?
        let status: String?
        let message: String?
        let chatId: String?
    }

    let id: Int?
    let name: String
    let data: Data

    var payload: Payload? { try? JSONDecoder().decode(Payload.self, from: data) }
}

struct SSEParser {
    private var line: [UInt8] = []
    private var name = "message"
    private var id: Int?
    private var data = ""
    private var dataBytes = 0
    private var previousCR = false

    mutating func receive(_ byte: UInt8) throws -> MetisEvent? {
        defer { previousCR = byte == 13 }
        if byte == 10 && previousCR { return nil }
        if byte != 10 && byte != 13 {
            guard line.count < 1_048_576 else { throw MetisError.unexpectedResponse }
            line.append(byte)
            return nil
        }
        if line.isEmpty {
            defer { name = "message"; id = nil; data = ""; dataBytes = 0 }
            guard dataBytes > 0 else { return nil }
            return MetisEvent(id: id, name: name, data: Data(data.dropLast().utf8))
        }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        let separator = text.firstIndex(of: ":") ?? text.endIndex
        let field = text[..<separator]
        var value = separator == text.endIndex ? text[text.endIndex...] : text[text.index(after: separator)...]
        if value.first == " " { value = value.dropFirst() }
        switch field {
        case "id": id = Int(value)
        case "event": name = String(value)
        case "data":
            dataBytes += value.utf8.count + 1
            guard dataBytes <= 1_048_576 else { throw MetisError.unexpectedResponse }
            data.append(contentsOf: value)
            data.append("\n")
        default: break
        }
        return nil
    }
}

struct ChatMessage: Decodable, Identifiable {
    struct Tool: Decodable, Identifiable {
        let id: String
        let name: String
        let status: String
        let detail: String?
        let input: String?
        let result: String?
        let inputUrl: String?
        let resultUrl: String?
    }
    struct Part: Decodable {
        let type: String
        let content: String?
        let tool: Tool?

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            type = try fields.decode(String.self, forKey: .type)
            content = try? fields.decode(String.self, forKey: .content)
            tool = type == "tool" ? try? Tool(from: decoder) : nil
        }

        private enum CodingKeys: CodingKey { case type, content }
    }

    struct Attachment: Decodable, Identifiable {
        let id: String
        let name: String
        let storedName: String
    }
    let id: String
    let role: String
    let content: String
    let historyPosition: Int?
    let contentUrl: String?
    let errorMessage: String?
    let attachments: [Attachment]?
    let thinking: String?
    let tools: [Tool]?
    let parts: [Part]?
    let eventsUrl: String?

    var toolActivity: [Tool] { parts?.compactMap(\.tool) ?? tools ?? [] }

    var reasoning: String {
        let segments = parts?.compactMap { $0.type == "thinking" ? $0.content : nil } ?? []
        return segments.isEmpty ? thinking ?? "" : segments.joined(separator: "\n\n")
    }
}

struct MetisApproval: Decodable, Identifiable {
    struct File: Decodable { let path: String; let status: String }
    let approvalId: String
    let version: Int
    let title: String
    let command: String?
    let files: [File]?
    var id: String { approvalId }
}

struct MetisQuestion: Decodable, Identifiable {
    struct Scalar: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let item = try decoder.singleValueContainer()
            if let text = try? item.decode(String.self) { value = text }
            else if let bool = try? item.decode(Bool.self) { value = String(bool) }
            else if let number = try? item.decode(Double.self) { value = String(number) }
            else if let list = try? item.decode([String].self), let data = try? JSONEncoder().encode(list) {
                value = String(decoding: data, as: UTF8.self)
            } else { value = "" }
        }
    }
    struct Field: Decodable, Identifiable {
        struct Option: Decodable { let label: String; let value: Scalar? }
        struct Condition: Decodable { let key: String; let equals: Scalar }
        let id: String
        let key: String?
        let question: String
        let description: String?
        let type: String?
        let options: [Option]?
        let showWhen: Condition?
        let defaultValue: Scalar?
        let min: Double?
        let max: Double?
        let step: Double?
        enum CodingKeys: String, CodingKey {
            case id, key, question, description, type, options, showWhen, min, max, step
            case defaultValue = "default"
        }
    }
    let questionId: String
    let version: Int?
    let title: String?
    let description: String?
    let status: String?
    let questions: [Field]
    var id: String { questionId }
}

struct MetisNotification: Decodable, Identifiable {
    let id: String
    let title: String
    let body: String
    let chatId: String?
    let readAt: String?
}

struct MetisProject: Decodable, Identifiable {
    let id: String
    let name: String
    let mode: String?
}

struct MetisProjectAgent: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String?
    let chatId: String
}

struct MetisUpload: Decodable, Identifiable {
    let id: String
    let name: String
    let offset: Int
    let complete: Bool
}

struct ChatPage: Decodable {
    struct Chat: Decodable {
        let id: String
        let messages: [ChatMessage]
        let title: String
        let runStatus: String?
        let modelId: String?
        let modelParams: [ModelSelection]?
        let pendingQuestion: MetisQuestion?
        let pendingApproval: PendingApproval?

        struct PendingApproval: Decodable { let id: String }
    }

    let chat: Chat
    let hasEarlierMessages: Bool
    let nextMessageBefore: Int
    let pageRevision: Int?
}

struct ChatHistoryWindow {
    private(set) var messages: [ChatMessage] = []
    private(set) var nextBefore: Int?
    private var latestStart = 0
    private var revision: Int?

    var includesEarlierPages: Bool { (nextBefore ?? 0) < latestStart }

    mutating func replaceLatest(with page: ChatPage) {
        let latest = page.chat.messages
        // Keep the contiguous prefix only if its boundary still identifies the
        // same message at the same server position after the refresh.
        if includesEarlierPages,
           let first = latest.first, let position = first.historyPosition,
           let boundary = messages.firstIndex(where: { $0.id == first.id && $0.historyPosition == position }),
           boundary > 0 {
            messages = Array(messages[..<boundary]) + latest
        } else {
            messages = latest
            nextBefore = page.hasEarlierMessages ? page.nextMessageBefore : nil
        }
        latestStart = page.nextMessageBefore
        revision = page.pageRevision
    }

    mutating func prepend(_ page: ChatPage) -> Bool {
        guard let nextBefore, page.nextMessageBefore < nextBefore, revision == page.pageRevision else { return false }
        let existing = Set(messages.map(\.id))
        messages = page.chat.messages.filter { !existing.contains($0.id) } + messages
        self.nextBefore = page.hasEarlierMessages ? page.nextMessageBefore : nil
        return true
    }
}

enum MetisError: LocalizedError {
    case invalidServer
    case unauthorized
    case unexpectedResponse
    case noModel
    case unavailableModel
    case questionFields([String: String])
    case http(Int, retryAfter: Int?)

    var errorDescription: String? {
        switch self {
        case .invalidServer:
            return "Enter the HTTPS address of a Metis server, without a path or credentials."
        case .unauthorized:
            return "Your session is no longer valid. Sign in again."
        case .unexpectedResponse:
            return "This server did not return a compatible Metis response."
        case .noModel:
            return "No model is available. Configure a provider in Metis."
        case .unavailableModel:
            return String(localized: "The selected model is no longer available. Choose another model.")
        case .questionFields:
            return "Check the highlighted answers."
        case .http(429, let seconds):
            if let seconds { return "Too many attempts. Try again in \(seconds) seconds." }
            return "Too many attempts. Try again later."
        case .http(404, _):
            return "This chat or server endpoint is unavailable."
        case .http(409, _):
            return "The server state changed. Refresh and try again."
        case .http(503, _):
            return "The server is temporarily unavailable. Try again shortly."
        case .http(let status, _):
            return "The request failed (HTTP \(status))."
        }
    }
}

struct ServerAddress {
    let url: URL

    init(_ input: String) throws {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/" else {
            throw MetisError.invalidServer
        }
        #if DEBUG && (targetEnvironment(simulator) || os(macOS))
        let allowsLocalHTTP = scheme == "http" && host == "localhost"
        #else
        let allowsLocalHTTP = false
        #endif
        guard scheme == "https" || allowsLocalHTTP else { throw MetisError.invalidServer }
        parts.scheme = scheme
        parts.path = ""
        guard let url = parts.url else { throw MetisError.invalidServer }
        self.url = url
    }
}

struct StoredMetisSession: Codable {
    let origin: String
    let cookie: String
    let expiresAt: Date
    var revocationTicket: String?
    var pushEvents: [String]?
    var watchEnabled: Bool?
    var webModelPreferences: [String: String]?
}

struct PendingMetisLogout: Codable, Identifiable {
    let origin: String
    let ticket: String
    let expiresAt: Date
    var id: String { ticket }
}

struct MetisRegisteredDevice: Decodable, Identifiable {
    let id: String
    let environment: String
    let expiresAt: Int64
    let events: [String]
}

// Redirects can resend the password body (307/308). Use the configured origin directly.
private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// URLSession's async APIs create their underlying tasks after suspension. Closing
// admission and cancelling the Swift work first keeps that creation from racing
// invalidateAndCancel(), which can raise an Objective-C exception on Apple OSes.
private final class MetisSessionLifetime: @unchecked Sendable {
    let session: URLSession
    private let lock = NSLock()
    private var closed = false
    private var pending: [UUID: @Sendable () -> Void] = [:]

    init(_ session: URLSession) {
        self.session = session
    }

    func run<Result: Sendable>(
        _ operation: @escaping @Sendable (URLSession) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        let id = UUID()
        let work = try lock.withLock {
            guard !closed else { throw CancellationError() }
            let work = Task { [session] in
                try Task.checkCancellation()
                do {
                    let result = try await operation(session)
                    try Task.checkCancellation()
                    return result
                } catch {
                    try Task.checkCancellation()
                    throw error
                }
            }
            pending[id] = { work.cancel() }
            return work
        }
        defer { finished(id) }

        return try await withTaskCancellationHandler {
            let result = try await work.value
            try Task.checkCancellation()
            guard lock.withLock({ !closed }) else { throw CancellationError() }
            return result
        } onCancel: {
            work.cancel()
        }
    }

    func close() {
        let cancellations: [@Sendable () -> Void]? = lock.withLock {
            guard !closed else { return nil }
            closed = true
            return Array(pending.values)
        }
        guard let cancellations else { return }
        for cancel in cancellations { cancel() }
        if cancellations.isEmpty { session.invalidateAndCancel() }
    }

    private func finished(_ id: UUID) {
        let invalidate = lock.withLock {
            pending.removeValue(forKey: id)
            return closed && pending.isEmpty
        }
        if invalidate { session.invalidateAndCancel() }
    }
}

final class MetisAPI: Sendable {
    private struct Credentials: Encodable {
        let username: String
        let password: String
    }

    private struct Acknowledgement: Decodable { let ok: Bool }
    private struct ChatList: Decodable { let chats: [ChatSummary] }
    private struct CreatedChat: Decodable { let chat: ChatSummary }
    private struct RunList: Decodable { let jobs: [MetisRun] }
    private struct Submission: Encodable {
        let chatId: String
        let messageId: String
        let message: String
        let modelId: String?
        let uploadIds: [String]?
        let modelParams: [ModelSelection]?
    }
    private struct AcceptedRun: Decodable { let jobId: String; let status: String }
    private struct EventPage: Decodable {
        struct Event: Decodable { let id: Int }
        let events: [Event]
    }
    private struct MobileCapabilities: Decodable { let version: Int; let apns: Bool }
    private struct DeviceList: Decodable { let devices: [MetisRegisteredDevice] }
    private struct Profile: Decodable { let username: String }
    private struct AccountProfileEnvelope: Decodable {
        struct AccountProfile: Decodable { let displayName: String }
        let profile: AccountProfile
    }
    private struct NotificationChat: Decodable { let chatId: String }
    private struct Inbox: Decodable { let notifications: [MetisNotification] }
    private struct ApprovalResponse: Decodable { let approval: MetisApproval? }
    private struct ModelList: Decodable { let models: [MetisModel]; let defaultModelId: String? }
    private struct ProjectList: Decodable { let projects: [MetisProject] }
    private struct AgentList: Decodable { let agents: [MetisProjectAgent] }
    private struct Decision: Encodable { let approvalId: String; let version: Int; let decision: String }
    private struct Answer: Encodable { let questionId: String; let version: Int; let values: [String: String] }
    private struct FieldErrors: Decodable { let fieldErrors: [String: String]? }

    private let address: ServerAddress
    private let lifetime: MetisSessionLifetime
    private var cookies: HTTPCookieStorage? { lifetime.session.configuration.httpCookieStorage }

    init(address: ServerAddress, restore: StoredMetisSession? = nil) {
        self.address = address
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 31 * 60
        if let restore, restore.origin == address.url.absoluteString, restore.expiresAt > Date(),
           let host = address.url.host {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: "ai_chat_auth", .value: restore.cookie, .domain: host,
                .path: "/", .expires: restore.expiresAt, .originURL: address.url,
                HTTPCookiePropertyKey(rawValue: "HttpOnly"): "TRUE",
            ]
            if address.url.scheme == "https" { properties[.secure] = "TRUE" }
            if let cookie = HTTPCookie(properties: properties) { configuration.httpCookieStorage?.setCookie(cookie) }
        }
        lifetime = MetisSessionLifetime(URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil))
    }

    deinit {
        lifetime.close()
    }

    func invalidate() {
        lifetime.close()
    }

    // Share only the validated first-party session, never page scripts or URLs.
    func webSessionCookie() -> HTTPCookie? {
        cookies?.cookies(for: address.url)?.first(where: validWebSessionCookie)
    }

    func updateWebSessionCookie(_ cookie: HTTPCookie) throws {
        guard validWebSessionCookie(cookie) else { throw MetisError.unauthorized }
        cookies?.setCookie(cookie)
    }

    private func validWebSessionCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain
        guard let host = address.url.host, domain.caseInsensitiveCompare(host) == .orderedSame,
              cookie.name == "ai_chat_auth", cookie.path == "/", cookie.isHTTPOnly,
              !cookie.value.isEmpty, let expires = cookie.expiresDate, expires > Date(),
              address.url.scheme != "https" || cookie.isSecure else { return false }
        return true
    }

    func sessionRecord() -> StoredMetisSession? {
        guard let cookie = cookies?.cookies(for: address.url)?.first(where: {
            $0.name == "ai_chat_auth" && $0.path == "/" && (address.url.scheme != "https" || $0.isSecure)
        }), let expires = cookie.expiresDate, expires > Date() else { return nil }
        return StoredMetisSession(origin: address.url.absoluteString, cookie: cookie.value, expiresAt: expires)
    }

    func enrollLogoutTicket(_ ticket: String) async throws {
        let body = try JSONEncoder().encode(["ticket": ticket])
        let _: Acknowledgement = try await request(["mobile", "session"], method: "POST", body: body)
    }

    func redeemLogoutTicket(_ ticket: String) async throws {
        let body = try JSONEncoder().encode(["ticket": ticket])
        let _: Acknowledgement = try await request(["mobile", "session"], method: "DELETE", body: body)
    }

    var origin: String { address.url.absoluteString }

    func profileName() async throws -> String {
        do {
            let profile: Profile = try await request(["mobile", "session"])
            return profile.username
        } catch MetisError.http(404, _) {
            // The canonical Web account API also serves servers without the
            // optional native mobile endpoints. Never fabricate an account name.
            let result: AccountProfileEnvelope = try await request(["profile"])
            guard !result.profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MetisError.unexpectedResponse
            }
            return result.profile.displayName
        }
    }

    func pushDevices() async throws -> [MetisRegisteredDevice] {
        let result: DeviceList = try await request(["mobile", "devices"])
        return result.devices
    }

    func signIn(username: String, password: String) async throws -> [ChatSummary] {
        let body = try JSONEncoder().encode(Credentials(username: username, password: password))
        let response: Acknowledgement = try await request(["auth"], method: "POST", body: body)
        guard response.ok else { throw MetisError.unexpectedResponse }
        // A successful POST alone does not establish that the cookie was accepted.
        do {
            return try await chats()
        } catch {
            try? await signOut()
            throw error
        }
    }

    func signOut() async throws {
        let response: Acknowledgement = try await request(["auth"], method: "DELETE")
        guard response.ok else { throw MetisError.unexpectedResponse }
    }

    func chats(includeArchived: Bool = false, ids: Set<String>? = nil) async throws -> [ChatSummary] {
        var query = includeArchived ? [URLQueryItem(name: "includeArchived", value: "true")] : []
        query += (ids ?? []).sorted().map { URLQueryItem(name: "id", value: $0) }
        let response: ChatList = try await request(["chats"], query: query)
        guard let ids else { return response.chats }
        return response.chats.filter { ids.contains($0.id) }
    }

    func createChat() async throws -> ChatSummary {
        let response: CreatedChat = try await request(["chats"], method: "POST", body: Data("{}".utf8))
        return response.chat
    }

    func setChat(_ id: String, pinned: Bool? = nil, archived: Bool? = nil) async throws {
        guard validPathPart(id) else { throw MetisError.unexpectedResponse }
        var patch: [String: Bool] = [:]
        patch["pinned"] = pinned
        patch["archived"] = archived
        let _: CreatedChat = try await request(["chats", id], method: "PATCH", body: JSONEncoder().encode(patch))
    }

    func pushSupported() async throws -> Bool {
        let result: MobileCapabilities = try await request(["mobile", "capabilities"])
        guard result.version == 1 else { throw MetisError.unexpectedResponse }
        return result.apns
    }

    func registerPush(installationID: String, token: String, topic: String, environment: String, events: [String]) async throws {
        struct Registration: Encodable {
            let installationId: String
            let token: String
            let topic: String
            let environment: String
            let events: [String]
        }
        let body = try JSONEncoder().encode(Registration(installationId: installationID, token: token, topic: topic, environment: environment, events: events))
        let _: Acknowledgement = try await request(["mobile", "devices"], method: "POST", body: body)
    }

    func revokePush(installationID: String) async throws {
        let body = try JSONEncoder().encode(["installationId": installationID])
        let _: Acknowledgement = try await request(["mobile", "devices"], method: "DELETE", body: body)
    }

    func notificationChat(id: String) async throws -> String {
        guard validPathPart(id) else { throw MetisError.unexpectedResponse }
        let result: NotificationChat = try await request(["mobile", "notifications", id])
        return result.chatId
    }

    func notifications() async throws -> [MetisNotification] {
        let result: Inbox = try await request(["notifications", "inbox"])
        return result.notifications
    }

    func markRead(_ id: String) async throws {
        let body = try JSONEncoder().encode(["ids": [id]])
        let _: Acknowledgement = try await request(["notifications", "inbox"], method: "POST", body: body)
    }

    func approval(chatID: String) async throws -> MetisApproval? {
        let result: ApprovalResponse = try await request(["mobile", "approvals"], query: [URLQueryItem(name: "chatId", value: chatID)])
        return result.approval
    }

    func decide(_ approval: MetisApproval, allow: Bool) async throws {
        let body = try JSONEncoder().encode(Decision(approvalId: approval.id, version: approval.version, decision: allow ? "allow" : "deny"))
        let _: Acknowledgement = try await request(["mobile", "approvals"], method: "POST", body: body)
    }

    func answer(_ question: MetisQuestion, values: [String: String]) async throws {
        guard let version = question.version else { throw MetisError.unexpectedResponse }
        let body = try JSONEncoder().encode(Answer(questionId: question.id, version: version, values: values))
        let _: Acknowledgement = try await request(["chat", "answer"], method: "POST", body: body)
    }

    func models() async throws -> [MetisModel] {
        let result: ModelList = try await request(["models"])
        return result.models
    }

    func modelForSend(chatModel: String?) async throws -> String {
        let catalog: ModelList = try await request(["models"])
        if let chatModel, !chatModel.isEmpty {
            if let exact = catalog.models.first(where: { $0.id == chatModel }) { return exact.id }
            // Match the server's account routing only through its explicit aliases.
            let aliases = catalog.models.filter { $0.legacyIds?.contains(chatModel) == true }
            guard aliases.count == 1 else { throw MetisError.unavailableModel }
            return aliases[0].id
        }
        guard let id = catalog.defaultModelId, catalog.models.contains(where: { $0.id == id }) else {
            throw MetisError.noModel
        }
        return id
    }

    func projects() async throws -> [MetisProject] {
        let result: ProjectList = try await request(["projects"])
        return result.projects
    }

    func agents(projectID: String) async throws -> [MetisProjectAgent] {
        guard validPathPart(projectID) else { throw MetisError.unexpectedResponse }
        let result: AgentList = try await request(["projects", projectID, "agents"])
        return result.agents
    }

    func upload(file: URL, mimeType: String) async throws -> MetisUpload {
        struct FileInfo: Encodable { let name: String; let mimeType: String; let size: Int }
        struct CompletedUpload: Decodable { let id: String; let name: String; let size: Int }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw MetisError.unexpectedResponse }
        let info = FileInfo(name: file.lastPathComponent, mimeType: mimeType, size: size)
        let start: MetisUpload = try await request(["file-uploads"], method: "POST", body: JSONEncoder().encode(info))
        guard UUID(uuidString: start.id) != nil else { throw MetisError.unexpectedResponse }
        let path = ["file-uploads", start.id]
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var offset = 0
            while offset < size {
                try Task.checkCancellation()
                guard let bytes = try handle.read(upToCount: min(512 * 1024, size - offset)), !bytes.isEmpty else {
                    throw MetisError.unexpectedResponse
                }
                let result: MetisUpload = try await request(path, method: "PUT", body: bytes,
                    headers: ["Content-Type": "application/octet-stream", "Upload-Offset": String(offset)])
                offset += bytes.count
                guard result.offset == offset else { throw MetisError.unexpectedResponse }
            }
            let result: CompletedUpload = try await request(path, method: "POST")
            guard result.id == start.id, result.size == size else { throw MetisError.unexpectedResponse }
            return MetisUpload(id: result.id, name: result.name, offset: result.size, complete: true)
        } catch {
            // A detached cleanup still runs if the transfer task was cancelled.
            _ = await Task.detached { try? await self.deleteUpload(start.id) }.value
            throw error
        }
    }

    func deleteUpload(_ id: String) async throws {
        guard UUID(uuidString: id) != nil else { throw MetisError.unexpectedResponse }
        struct Deleted: Decodable { let deleted: Bool }
        let _: Deleted = try await request(["file-uploads", id], method: "DELETE")
    }

    func download(chatID: String, attachment: ChatMessage.Attachment) async throws -> URL {
        guard validPathPart(chatID), validPathPart(attachment.storedName) else { throw MetisError.unexpectedResponse }
        let url = try endpoint(["uploads", chatID, attachment.storedName], query: [])
        let (file, response) = try await lifetime.run { try await $0.download(from: url) }
        try Self.validate(response)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = validPathPart(attachment.name) ? attachment.name : "Attachment"
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }

    func send(chatID: String, message: String, messageID: String, modelID: String? = nil, uploadIDs: [String]? = nil, modelParams: [ModelSelection]? = nil) async throws -> MetisRun {
        let body = try JSONEncoder().encode(Submission(chatId: chatID, messageId: messageID, message: message, modelId: modelID, uploadIds: uploadIDs, modelParams: modelParams))
        let response: AcceptedRun = try await request(["chat"], method: "POST", body: body)
        return MetisRun(id: response.jobId, messageId: messageID, status: response.status)
    }

    func jobs(chatID: String) async throws -> [MetisRun] {
        let result: RunList = try await request(["runs"], query: [URLQueryItem(name: "chatId", value: chatID)])
        return result.jobs
    }

    func cancel(chatID: String) async throws {
        let body = try JSONEncoder().encode(["chatId": chatID])
        let _: Acknowledgement = try await request(["chat", "cancel"], method: "POST", body: body)
    }

    func resume(chatID: String, jobID: String) async throws -> Int {
        var cursor = 0
        while true {
            let query = runQuery(chatID: chatID, jobID: jobID, after: cursor)
            let page: EventPage = try await request(["runs"], query: query)
            guard let last = page.events.last?.id, last > cursor else { break }
            cursor = last
            if page.events.count < 500 { break }
        }
        let body = try JSONEncoder().encode(["chatId": chatID, "jobId": jobID])
        let _: Acknowledgement = try await request(["chat", "resume"], method: "POST", body: body)
        return cursor
    }

    private func runQuery(chatID: String, jobID: String, after: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "chatId", value: chatID), URLQueryItem(name: "jobId", value: jobID),
         URLQueryItem(name: "events", value: "1"), URLQueryItem(name: "after", value: String(after))]
    }

    func observeRun(
        chatID: String, jobID: String, after: Int, receive: @escaping @MainActor @Sendable (MetisEvent) -> Bool
    ) async throws {
        let query = runQuery(chatID: chatID, jobID: jobID, after: after) + [URLQueryItem(name: "stream", value: "1")]
        try await observe(["runs"], query: query, receive: receive)
    }

    func observeChats(after: Int, receive: @escaping @MainActor @Sendable (MetisEvent) -> Bool) async throws {
        try await observe(["chats", "events"], query: [URLQueryItem(name: "after", value: String(after))], receive: receive)
    }

    private func observe(
        _ path: [String], query: [URLQueryItem], receive: @escaping @MainActor @Sendable (MetisEvent) -> Bool
    ) async throws {
        var request = URLRequest(url: try endpoint(path, query: query), timeoutInterval: 45)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        try await lifetime.run { [request] session in
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            try Self.validate(response)
            guard response.mimeType == "text/event-stream" else { throw MetisError.unexpectedResponse }
            var parser = SSEParser()
            for try await byte in bytes {
                guard let event = try parser.receive(byte) else { continue }
                try Task.checkCancellation()
                if event.name == "auth-expired" { throw MetisError.unauthorized }
                if await !receive(event) { return }
            }
        }
    }

    func chat(id: String, before: Int? = nil) async throws -> ChatPage {
        guard let page = try await chatPage(id: id, before: before).page else {
            throw MetisError.unexpectedResponse
        }
        return page
    }

    func chatPage(id: String, before: Int? = nil, ifNoneMatch: String? = nil) async throws -> (page: ChatPage?, etag: String?) {
        guard validPathPart(id) else {
            throw MetisError.unexpectedResponse
        }
        var query = [URLQueryItem(name: "messageLimit", value: "30")]
        if let before { query.append(URLQueryItem(name: "messageBefore", value: String(before))) }
        let headers = ifNoneMatch.map { ["If-None-Match": $0] } ?? [:]
        func fetchPage() async throws -> (Data, HTTPURLResponse) {
            let (data, response) = try await responseData(["chats", id], query: query, headers: headers)
            if response.statusCode != 304 || ifNoneMatch == nil { try Self.validate(response) }
            return (data, response)
        }
        let result: (Data, HTTPURLResponse)
        do {
            result = try await fetchPage()
        } catch MetisError.http(503, let retryAfter) {
            try await Task.sleep(for: .seconds(max(1, min(3, retryAfter ?? 1))))
            result = try await fetchPage()
        }
        let etag = result.1.value(forHTTPHeaderField: "ETag")
        if result.1.statusCode == 304 { return (nil, etag ?? ifNoneMatch) }
        let page: ChatPage = try decode(result.0)
        guard page.chat.id == id,
              page.nextMessageBefore >= 0,
              !page.hasEarlierMessages || page.nextMessageBefore > 0,
              before.map({ page.nextMessageBefore < $0 }) ?? true else {
            throw MetisError.unexpectedResponse
        }
        return (page, etag)
    }

    private func request<Response: Decodable>(
        _ path: [String], method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Response {
        let (data, response) = try await responseData(path, method: method, query: query, body: body, headers: headers)
        if path == ["chat", "answer"], response.statusCode == 400 {
            if let errors = (try? JSONDecoder().decode(FieldErrors.self, from: data))?.fieldErrors, !errors.isEmpty {
                throw MetisError.questionFields(errors)
            }
        }
        try Self.validate(response)
        return try decode(data)
    }

    private func responseData(
        _ path: [String], method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try endpoint(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await lifetime.run { [request] in try await $0.data(for: request) }
        guard let http = response as? HTTPURLResponse else { throw MetisError.unexpectedResponse }
        return (data, http)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw MetisError.unexpectedResponse
        }
    }

    private func validPathPart(_ input: String) -> Bool {
        !input.isEmpty && input != "." && !input.contains("..") && !input.contains("/") && !input.contains("\\")
    }

    private func endpoint(_ path: [String], query: [URLQueryItem]) throws -> URL {
        let endpoint = path.reduce(address.url.appendingPathComponent("api")) { $0.appendingPathComponent($1) }
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw MetisError.unexpectedResponse
        }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw MetisError.unexpectedResponse }
        return url
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw MetisError.unexpectedResponse }
        if http.statusCode == 401 { throw MetisError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw MetisError.http(http.statusCode, retryAfter: retryAfter)
        }
    }
}
