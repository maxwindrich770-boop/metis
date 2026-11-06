import Foundation

private struct SmokeFailure: Error {
    let step: String
}

private func check(_ condition: Bool, _ step: String) throws {
    guard condition else { throw SmokeFailure(step: step) }
}

@main
struct Smoke {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Swift smoke test failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        try verifyEventFraming()
        let input = CommandLine.arguments.dropFirst().first ?? "http://localhost:43100"
        let address = try ServerAddress(input)
        guard address.url.scheme == "http", address.url.host == "localhost" else {
            throw SmokeFailure(step: "Smoke test requires the loopback fixture")
        }
        for invalid in ["http://metis.example", "https://user:secret@metis.example", "https://metis.example/path"] {
            do {
                _ = try ServerAddress(invalid)
                throw SmokeFailure(step: "Unsafe server address was accepted")
            } catch MetisError.invalidServer {}
        }

        let alice = MetisAPI(address: address)
        let bob = MetisAPI(address: address)
        let password = "apple-fixture-only"
        do {
            _ = try await alice.signIn(username: "metis-apple-fixture-redirect", password: password)
            throw SmokeFailure(step: "A credential-bearing redirect was followed")
        } catch MetisError.http(307, _) {}
        do {
            _ = try await alice.signIn(username: "metis-apple-fixture-alice", password: "wrong")
            throw SmokeFailure(step: "Invalid credentials were accepted")
        } catch MetisError.unauthorized {}
        let aliceChats = try await alice.signIn(username: "metis-apple-fixture-alice", password: password)
        let bobChats = try await bob.signIn(username: "metis-apple-fixture-bob", password: password)
        try check(aliceChats.map(\.title) == ["Fixture chat"], "Alice's chat list")
        try check(bobChats.map(\.title) == ["Other user's chat"], "Bob's chat list")
        try check(try await alice.profileName() == "metis-apple-fixture-alice", "Authenticated account profile")
        try check(try await alice.chats() == aliceChats, "Second sign-in changed first client's session")

        let chatID = aliceChats[0].id
        let first = try await alice.chatPage(id: chatID)
        guard let recent = first.page, let etag = first.etag else { throw SmokeFailure(step: "Missing chat page or validator") }
        let unchanged = try await alice.chatPage(id: chatID, ifNoneMatch: etag)
        try check(unchanged.page == nil && unchanged.etag == etag, "Unchanged chat page did not return 304")
        var history = ChatHistoryWindow()
        history.replaceLatest(with: recent)
        var pages = 1
        while let before = history.nextBefore {
            let earlier = try await alice.chat(id: chatID, before: before)
            try check(history.prepend(earlier), "A valid earlier page was rejected")
            pages += 1
        }
        let contents = (1...75).map { "Nachricht \($0) 🌱" }
        try check(pages >= 3 && history.messages.map(\.content) == contents, "Chronological history without gaps")
        do {
            _ = try await bob.chat(id: chatID)
            throw SmokeFailure(step: "Bob can read Alice's chat")
        } catch MetisError.http(404, _) {}

        try await verifyRunStream(client: alice, chatID: chatID)
        _ = try await alice.send(chatID: chatID, message: "History refresh", messageID: UUID().uuidString)
        try await alice.cancel(chatID: chatID)
        let refreshed = try await alice.chat(id: chatID)
        history.replaceLatest(with: refreshed)
        try check(history.nextBefore == nil && history.messages.map(\.content) == contents + ["History refresh"],
                  "Refreshing dropped or duplicated earlier pages")
        var stale = ChatHistoryWindow()
        stale.replaceLatest(with: recent)
        let fromNewRevision = try await alice.chat(id: chatID, before: recent.nextMessageBefore)
        try check(!stale.prepend(fromNewRevision), "A page from a changed history revision was merged")
        let created = try await alice.createChat()
        try check(try await alice.chats(ids: [created.id]).map(\.id) == [created.id], "Targeted chat refresh")
        try check(try await bob.chats(ids: [created.id]).isEmpty, "Targeted refresh leaked another account's chat")
        let outgoingID = UUID().uuidString
        let prompt = "Hello from the iPhone simulator"
        do {
            _ = try await alice.send(chatID: created.id, message: prompt, messageID: outgoingID)
            throw SmokeFailure(step: "Expected the server to drop the first submission response")
        } catch is URLError {
            // Foundation can surface a truncated acknowledgement as a transport error.
        } catch MetisError.unexpectedResponse {
            // It can also hand the incomplete response body to the JSON decoder.
        }
        let jobs = try await alice.jobs(chatID: created.id)
        try check(jobs.count == 1 && jobs[0].messageId == outgoingID, "Submission did not commit before the response was lost")
        let accepted = try await alice.send(chatID: created.id, message: prompt, messageID: outgoingID)
        try check(accepted.id == jobs[0].id, "Retry started a second job")
        try check(try await alice.jobs(chatID: created.id).count == 1, "Retry added another job")
        try await alice.cancel(chatID: created.id)
        let afterCancel = try await alice.send(chatID: created.id, message: prompt, messageID: outgoingID)
        try check(afterCancel.id == accepted.id && afterCancel.status == "cancelled", "Retry after terminal state changed the job")
        let createdPage = try await alice.chat(id: created.id)
        try check(createdPage.chat.messages.filter { $0.id == outgoingID }.count == 1, "Submission duplicated the message")
        try check(createdPage.chat.runStatus == "cancelled", "Retry overwrote the cancelled chat state")
        try await verifyAttachment(client: alice, chatID: created.id)
        try await verifyLiveRun(client: alice, chatID: created.id)
        guard let session = alice.sessionRecord() else { throw SmokeFailure(step: "The native cookie jar did not expose a resumable session") }
        let differentOrigin = try ServerAddress("http://localhost:1")
        try check(MetisAPI(address: differentOrigin, restore: session).sessionRecord() == nil, "Cookie copied to a different origin")
        let restored = MetisAPI(address: address, restore: session)
        try check(try await restored.chats().contains(where: { $0.id == created.id }), "Restored cookie did not authenticate")
        let ticket = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        try await restored.enrollLogoutTicket(ticket)
        let noCookie = MetisAPI(address: address)
        try await noCookie.redeemLogoutTicket(ticket)
        try await noCookie.redeemLogoutTicket(ticket)
        do {
            _ = try await alice.chats()
            throw SmokeFailure(step: "Logged-out session remains usable")
        } catch MetisError.unauthorized {}
        try check(try await bob.chats() == bobChats, "Alice's logout revoked Bob's session")
        try await bob.signOut()
        print("PASS: auth, session restore, detached logout, isolation, history, create, send, deduplication, cancel, SSE replay, chunked attachment and live worker stream")
    }

    @MainActor private static func verifyLiveRun(client: MetisAPI, chatID: String) async throws {
        let model = try await client.modelForSend(chatModel: nil)
        let run = try await client.send(chatID: chatID, message: "Run the local model", messageID: UUID().uuidString, modelID: model)
        var text = ""
        var cursor = 0
        var terminal: MetisEvent?
        try await client.observeRun(chatID: chatID, jobID: run.id, after: 0) { event in
            if let id = event.id { cursor = id }
            if event.name == "text" {
                text += event.payload?.text ?? ""
                return false
            }
            if event.name == "done" || event.name == "error" { terminal = event; return false }
            return true
        }
        try check(!text.isEmpty && cursor > 0 && terminal == nil,
                  "Worker did not send a replayable delta: \(terminal?.payload?.message ?? "no data")")
        let resumedAt = ContinuousClock.now
        try await client.observeRun(chatID: chatID, jobID: run.id, after: cursor) { event in
            if event.name == "text" { text += event.payload?.text ?? "" }
            if event.name == "done" || event.name == "error" { terminal = event; return false }
            return true
        }
        try check(terminal?.name == "done", "Worker did not complete: \(terminal?.payload?.message ?? "no terminal event")")
        try check(ContinuousClock.now - resumedAt > .seconds(1), "The first response text was buffered until completion")
        try check(text == "Live fixture streamed before the run completed. Final response 🌱", "Live worker text differed from fixture")
        let final = try await client.chat(id: chatID)
        try check(final.chat.messages.last?.content == text, "Final transcript did not match the stream")
    }
    private static func verifyAttachment(client: MetisAPI, chatID: String) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("metis-fixture-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data(repeating: 0x61, count: 600_000)
        try data.write(to: file)
        let uploaded = try await client.upload(file: file, mimeType: "text/plain")
        try check(uploaded.complete && uploaded.offset == data.count, "Chunked upload was incomplete")
        let messageID = UUID().uuidString
        _ = try await client.send(chatID: chatID, message: "", messageID: messageID, uploadIDs: [uploaded.id])
        let page = try await client.chat(id: chatID)
        guard let attachment = page.chat.messages.first(where: { $0.id == messageID })?.attachments?.first else {
            throw SmokeFailure(step: "Stored attachment was missing")
        }
        let downloaded = try await client.download(chatID: chatID, attachment: attachment)
        defer { try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent()) }
        try check(try Data(contentsOf: downloaded) == data, "Downloaded attachment differs from upload")
        try await client.cancel(chatID: chatID)
    }

    private static func verifyEventFraming() throws {
        let stream = ": keep-alive\r\n\r\nid: 9\r\nevent: text\r\ndata: {\"text\":\r\ndata: \"Grüße 🌱\"}\r\n\r\n"
        var parser = SSEParser()
        var frames: [MetisEvent] = []
        for byte in stream.utf8 {
            if let frame = try parser.receive(byte) { frames.append(frame) }
        }
        try check(frames.count == 1 && frames[0].id == 9 && frames[0].payload?.text == "Grüße 🌱",
                  "SSE must handle split Unicode, CRLF, keepalive and multi-line data")
    }
    @MainActor private static func verifyRunStream(client: MetisAPI, chatID: String) async throws {
        var first: MetisEvent?
        try await client.observeRun(chatID: chatID, jobID: "fixture-run", after: 0) { event in
            first = event
            return false
        }
        try check(first?.id == 1 && first?.payload?.text == "Grüße 🌱", "Incremental SSE with multibyte text")
        var replayed: [MetisEvent] = []
        try await client.observeRun(chatID: chatID, jobID: "fixture-run", after: first?.id ?? 0) { event in
            replayed.append(event)
            return true
        }
        try check(replayed.map(\.name) == ["text", "done"] && replayed.first?.id == 2, "SSE reconnect and terminal fallback")
    }
}
