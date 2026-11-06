import AVFoundation
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ComposerDraft {
    let text: String
    let id = UUID().uuidString
}

struct ChatDetail: View {
    let chat: ChatSummary
    let client: MetisAPI
    let syncRevision: Int
    @Binding var draft: ComposerDraft?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onUnauthorized: () -> Void
    @State private var history = ChatHistoryWindow()
    @State private var latestETag: String?
    @State private var busy = false
    @State private var hasLoaded = false
    @State private var notice: String?
    @State private var title: String?
    @State private var attachmentDraftID = UUID().uuidString
    @State private var sending = false
    @State private var cancelling = false
    @State private var runningID: String?
    @State private var interruptedID: String?
    @State private var streamCursor = 0
    @State private var streamAttempt = 0
    @State private var foregroundReady = false
    @State private var streamText = ""
    @State private var streamMessageID: String?
    @State private var streamStatus: String?
    @State private var needsReconnect = false
    @State private var terminalRevision = 0
    @State private var terminalPending = false
    @State private var terminalNotice: String?
    @State private var question: MetisQuestion?
    @State private var shownQuestion: MetisQuestion?
    @State private var pendingApproval = false
    @State private var shownApproval: MetisApproval?
    @State private var models: [MetisModel] = []
    @State private var selectedModel: String?
    @State private var chatModel: String?
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var files: [DraftAttachment] = []
    @State private var draftPreview: URL?
    @State private var download: DownloadedAttachment?
    @State private var downloadedFileToClean: DownloadedAttachment?
    @State private var downloadBusy = false
    @State private var scrollRevision = 0

    init(chat: ChatSummary, client: MetisAPI, syncRevision: Int, draft: Binding<ComposerDraft?>,
         onUnauthorized: @escaping () -> Void) {
        self.chat = chat
        self.client = client
        self.syncRevision = syncRevision
        self._draft = draft
        self.onUnauthorized = onUnauthorized
    }

    var body: some View {
        ScrollViewReader { scroll in
            transcript
                .onChange(of: scrollRevision) { _, _ in
                    if reduceMotion { scroll.scrollTo("chat-end", anchor: .bottom) }
                    else { withAnimation(.easeOut(duration: 0.18)) { scroll.scrollTo("chat-end", anchor: .bottom) } }
                }
        }
    }

    private var transcript: some View {
        List {
            if let nextBefore = history.nextBefore {
                Button("Load earlier messages") { Task { await load(before: nextBefore) } }
                    .disabled(busy)
            }
            if busy {
                ProgressView().frame(maxWidth: .infinity).padding(12)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            if notice != nil && !hasLoaded {
                Button("Try again") { Task { await load() } }.disabled(busy)
            }
            if hasLoaded && history.messages.isEmpty && runningID == nil {
                ContentUnavailableView {
                    MetisWordmark(width: 88)
                } description: {
                    Text("Start a conversation with Metis.")
                }
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(history.messages.filter { streamText.isEmpty || $0.id != streamMessageID }) { message in
                messageRow(message)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if !streamText.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Metis").font(.subheadline.weight(.semibold))
                    Text(verbatim: streamText)
                        .font(.body).lineSpacing(4)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("metis.streamText")
                }
                .foregroundStyle(MetisTheme.ink)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            if runningID != nil {
                HStack {
                    if !needsReconnect { ProgressView() }
                    Text(streamStatus ?? "Agent is working…").font(.footnote)
                    Spacer()
                    if needsReconnect {
                        Button("Reconnect") { streamAttempt &+= 1 }
                            .buttonStyle(.borderless).frame(minHeight: 44)
                    }
                    Button("Stop", role: .destructive) { Task { await stop() } }
                        .buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44).disabled(cancelling)
                }
            } else if terminalPending {
                if notice != nil {
                    Button("Refresh conversation") { Task { await load() } }
                        .disabled(busy)
                } else {
                    Label("Updating conversation…", systemImage: "arrow.clockwise").font(.footnote)
                }
            } else if let interruptedID {
                Button("Resume interrupted run") { Task { await resume(interruptedID) } }.disabled(sending)
            }
            Color.clear.frame(height: 1).listRowSeparator(.hidden).listRowBackground(Color.clear)
                .accessibilityHidden(true).id("chat-end")
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .metisScreen()
        .navigationTitle(title ?? (chat.title.isEmpty ? "Chat" : chat.title))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { foregroundReady = false }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await reload()
            if !Task.isCancelled { foregroundReady = true }
        }
        .task(id: SyncIdentity(revision: syncRevision, active: scenePhase == .active)) {
            guard scenePhase == .active, syncRevision > 0 else { return }
            // Coalesce changes and wait for pagination or a terminal refresh so
            // an event received during an in-flight load is not discarded.
            do {
                try await Task.sleep(for: .milliseconds(250))
                while busy { try await Task.sleep(for: .milliseconds(50)) }
            } catch { return }
            guard !Task.isCancelled else { return }
            await reload(preservingNotice: true)
        }
        .task(id: StreamIdentity(job: foregroundReady && scenePhase == .active ? runningID : nil,
                                 attempt: streamAttempt)) {
            if scenePhase == .active, foregroundReady, let runningID { await follow(runningID) }
        }
        .task(id: terminalRevision) {
            guard terminalPending else { return }
            await load()
        }
        .refreshable { await reload() }
        .safeAreaInset(edge: .bottom) { composer }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get().prefix(max(0, 10 - files.count)) {
                    let type = UTType(filenameExtension: url.pathExtension)
                    files.append(DraftAttachment(url: url, mimeType: type?.preferredMIMEType ?? "application/octet-stream"))
                }
                renewSubmissionID()
            } catch { notice = message(for: error) }
        }
        .task(id: photo) {
            guard let photo else { return }
            do {
                if let image = try await photo.loadTransferable(type: ImportedPhoto.self) {
                    if Task.isCancelled { try? FileManager.default.removeItem(at: image.url.deletingLastPathComponent()) }
                    else { stageImage(image.url, mimeType: image.mimeType) }
                }
            } catch { if !Task.isCancelled { notice = message(for: error) } }
        }
        .sheet(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                guard let data = image?.jpegData(compressionQuality: 0.85) else { return }
                do {
                    let file = try ImportedPhoto.copy(data: data)
                    stageImage(file, mimeType: "image/jpeg")
                } catch { notice = message(for: error) }
            }
            .ignoresSafeArea()
        }
        .quickLookPreview($draftPreview)
        .sheet(item: $shownApproval) { approval in
            ApprovalView(approval: approval) { allow in
                do {
                    try await client.decide(approval, allow: allow)
                    await load()
                    return nil
                } catch MetisError.unauthorized { onUnauthorized(); return "Sign in again." }
                catch { await load(); return message(for: error) }
            }
        }
        .sheet(item: $shownQuestion) { question in
            QuestionView(question: question) { values in
                do {
                    try await client.answer(question, values: values)
                    await load()
                } catch MetisError.unauthorized {
                    onUnauthorized()
                    throw MetisError.unauthorized
                }
            }
        }
        .sheet(item: $download, onDismiss: {
            downloadedFileToClean?.clean()
            downloadedFileToClean = nil
        }) { file in
            AttachmentPreview(url: file.url)
        }
        .onDisappear {
            foregroundReady = false
            guard !sending, !showCamera, shownApproval == nil, shownQuestion == nil,
                  download == nil, draftPreview == nil else { return }
            let abandoned = files
            files = []
            if !abandoned.isEmpty { renewSubmissionID() }
            for file in abandoned {
                file.clean()
                if let id = file.uploadID { Task { try? await client.deleteUpload(id) } }
            }
        }
    }


    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == "user" { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 10) {
                Text(message.role == "assistant" ? "Metis" : message.role.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MetisTheme.muted)
                if !message.content.isEmpty {
                    ChatMarkdown(text: message.content)
                }
                if let error = message.errorMessage, !error.isEmpty {
                    Label {
                        Text(verbatim: error)
                    } icon: {
                        Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    }
                    .font(.footnote)
                }
                if message.contentUrl != nil {
                    Text("Full message available in Metis on the web.").font(.footnote)
                } else if message.content.isEmpty && message.errorMessage?.isEmpty != false {
                    Text("No text.").foregroundStyle(MetisTheme.muted)
                }
                ForEach(message.attachments ?? []) { file in
                    Button(file.name, systemImage: "paperclip") {
                        Task { await openAttachment(file) }
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44, alignment: .leading)
                    .buttonStyle(.borderless)
                    .disabled(downloadBusy)
                }
                if !message.reasoning.isEmpty {
                    DisclosureGroup("Reasoning") {
                        Text(verbatim: message.reasoning)
                            .font(.subheadline).foregroundStyle(MetisTheme.muted)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 44)
                }
                ForEach(Array(message.toolActivity.enumerated()), id: \.offset) { _, tool in
                    DisclosureGroup {
                        if let detail = tool.detail { Text(verbatim: detail).textSelection(.enabled) }
                        if let input = tool.input { ChatMarkdown(text: input) }
                        if let result = tool.result { ChatMarkdown(text: result) }
                        if tool.inputUrl != nil || tool.resultUrl != nil {
                            Text("Full tool details are available in Metis on the web.").font(.footnote)
                        }
                    } label: {
                        Label {
                            LabeledContent(tool.name, value: tool.status.capitalized)
                        } icon: {
                            Image(systemName: "terminal").accessibilityHidden(true)
                        }
                        .font(.footnote).foregroundStyle(MetisTheme.muted)
                    }
                    .frame(minHeight: 44)
                }
                if message.eventsUrl != nil {
                    Text("Earlier tool activity is available in Metis on the web.").font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(message.role == "user" ? 14 : 0)
            .background(message.role == "user" ? MetisTheme.secondary : Color.clear,
                        in: RoundedRectangle(cornerRadius: MetisTheme.corner))
        }
        .font(.body)
        .foregroundStyle(MetisTheme.ink)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pendingApproval {
                Button("Review pending approval", systemImage: "lock.shield") {
                    Task { await reviewApproval() }
                }
                .font(.subheadline).frame(minHeight: 44)
            }
            if let question, question.status == nil || question.status == "waiting_for_user" {
                Button(question.title ?? "Answer agent question", systemImage: "questionmark.bubble") {
                    shownQuestion = question
                }
                .font(.subheadline).frame(minHeight: 44)
            }
            if let notice {
                MetisNotice(text: notice, accessibilityID: "metis.chatNotice")
            }
            if !files.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(files) { file in
                            HStack(spacing: 0) {
                                if file.temporary {
                                    Button("Preview", systemImage: "eye") { draftPreview = file.url }
                                        .labelStyle(.iconOnly)
                                        .frame(width: 44, height: 44)
                                }
                                Text(verbatim: file.url.lastPathComponent)
                                    .font(.caption).lineLimit(1)
                                    .frame(maxWidth: 160)
                                    .padding(.leading, file.temporary ? 0 : 12)
                                Button {
                                    remove(file)
                                } label: {
                                    Image(systemName: "xmark").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Remove attachment")
                                .accessibilityValue(file.url.lastPathComponent)
                            }
                            .background(MetisTheme.secondary, in: RoundedRectangle(cornerRadius: MetisTheme.corner))
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                TextField("Message Metis…", text: Binding(
                    get: { draft?.text ?? "" },
                    set: { text in
                        draft = text.isEmpty ? nil : ComposerDraft(text: text)
                        attachmentDraftID = UUID().uuidString
                    }
                ), axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Message")
                    .accessibilityIdentifier("metis.message")
                HStack(spacing: 8) {
                    Menu {
                        Button("Files", systemImage: "doc") { showFiles = true }
                        PhotosPicker(selection: $photo, matching: .images) { Label("Photos", systemImage: "photo") }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Camera", systemImage: "camera") { Task { await openCamera() } }
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Attach")
                    .disabled(files.count >= 10)

                    modelMenu
                    Spacer(minLength: 0)
                    Button {
                        Task { await send() }
                    } label: {
                        Group {
                            if sending { ProgressView().tint(MetisTheme.onPrimary) }
                            else { Image(systemName: "arrow.up").font(.body.weight(.semibold)) }
                        }
                        .frame(width: 44, height: 44)
                        .foregroundStyle(MetisTheme.onPrimary)
                        .background(MetisTheme.primary, in: Circle())
                        .opacity(canSend ? 1 : 0.4)
                        .contentShape(Circle())
                    }
                    .buttonStyle(MetisIconButtonStyle())
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("metis.send")
                    .disabled(!canSend)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .background(MetisTheme.surface, in: RoundedRectangle(cornerRadius: MetisTheme.corner))
            .overlay {
                RoundedRectangle(cornerRadius: MetisTheme.corner)
                    .strokeBorder(MetisTheme.border, lineWidth: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MetisTheme.background)
        .disabled(sending)
    }

    private var canSend: Bool {
        !sending && runningID == nil && !terminalPending && hasLoaded &&
        (!files.isEmpty || !(draft?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var modelMenu: some View {
        Menu {
            Button("Use chat default") { selectedModel = nil }
            if models.isEmpty { Button("Load models") { Task { await loadModels() } } }
            ForEach(models) { model in
                Button {
                    selectedModel = model.id
                } label: {
                    if selectedModel == model.id { Label(model.title, systemImage: "checkmark") }
                    else { Text(model.title) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu").accessibilityHidden(true)
                Text(modelLabel).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(MetisTheme.muted)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Model")
        .accessibilityValue(modelLabel)
        .disabled(sending || runningID != nil)
    }

    private var modelLabel: String {
        if let id = selectedModel ?? chatModel, let model = models.first(where: { $0.id == id }) {
            return model.title
        }
        return String(localized: "Model")
    }

    private struct SyncIdentity: Equatable {
        let revision: Int
        let active: Bool
    }

    private struct StreamIdentity: Equatable {
        let job: String?
        let attempt: Int
    }

    private func reload(preservingNotice: Bool = false) async {
        await load(clearNotice: !preservingNotice)
        guard !Task.isCancelled, runningID == nil, !sending, !terminalPending else { return }
        do {
            let jobs = try await client.jobs(chatID: chat.id)
            guard !Task.isCancelled, runningID == nil, !sending, !terminalPending else { return }
            if let active = jobs.first(where: \.active) {
                // A retained draft may be awaiting a manual retry after its
                // acknowledgement was lost. Keep that retry available with
                // the same message ID instead of adopting its run implicitly.
                if active.messageId == (draft?.id ?? attachmentDraftID) { return }
                begin(active.id, status: active.status)
            } else {
                interruptedID = jobs.first?.status == "interrupted" ? jobs.first?.id : nil
            }
        } catch MetisError.unauthorized {
            if !Task.isCancelled { onUnauthorized() }
        } catch {}
    }

    private func send() async {
        guard !sending, runningID == nil, !terminalPending else { return }
        let text = (draft?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !files.isEmpty else { return }
        sending = true
        notice = nil
        defer { sending = false }
        let id = draft?.id ?? attachmentDraftID
        do {
            let model = try await client.modelForSend(chatModel: selectedModel ?? chatModel)
            for index in files.indices where files[index].uploadID == nil {
                let file = files[index]
                let scoped = file.url.startAccessingSecurityScopedResource()
                defer { if scoped { file.url.stopAccessingSecurityScopedResource() } }
                files[index].uploadID = try await client.upload(file: file.url, mimeType: file.mimeType).id
            }
            let uploads = files.compactMap(\.uploadID)
            let run = try await client.send(chatID: chat.id, message: text, messageID: id, modelID: model,
                                            uploadIDs: uploads.isEmpty ? nil : uploads)
            for file in files { file.clean() }
            files = []
            if draft?.id == id { draft = nil }
            attachmentDraftID = UUID().uuidString
            await load()
            if run.active { begin(run.id, status: run.status) }
        } catch MetisError.unauthorized {
            onUnauthorized()
        } catch {
            notice = message(for: error)
        }
    }

    private func loadModels() async {
        do { models = try await client.models() }
        catch MetisError.unauthorized { onUnauthorized() }
        catch { notice = message(for: error) }
    }

    private func openCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showCamera = true
        case .notDetermined:
            showCamera = await AVCaptureDevice.requestAccess(for: .video)
            if !showCamera { notice = "Camera access is off. You can allow it in iPhone Settings." }
        case .denied, .restricted:
            notice = "Camera access is off. You can allow it in iPhone Settings."
        @unknown default:
            notice = "Camera access is unavailable."
        }
    }

    private func openAttachment(_ attachment: ChatMessage.Attachment) async {
        guard !downloadBusy, download == nil else { return }
        downloadBusy = true
        defer { downloadBusy = false }
        do {
            let file = DownloadedAttachment(url: try await client.download(chatID: chat.id, attachment: attachment))
            downloadedFileToClean = file
            download = file
        } catch MetisError.unauthorized { onUnauthorized() }
        catch { notice = message(for: error) }
    }

    private func stageImage(_ url: URL, mimeType: String) {
        guard !sending, files.count < 10 else { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); return }
        files.append(DraftAttachment(url: url, mimeType: mimeType, temporary: true))
        renewSubmissionID()
    }

    private func remove(_ file: DraftAttachment) {
        files.removeAll { $0.id == file.id }
        file.clean()
        renewSubmissionID()
        if let id = file.uploadID { Task { try? await client.deleteUpload(id) } }
    }

    private func renewSubmissionID() {
        if let text = draft?.text { draft = ComposerDraft(text: text) }
        attachmentDraftID = UUID().uuidString
    }

    private func reviewApproval() async {
        do {
            shownApproval = try await client.approval(chatID: chat.id)
            if shownApproval == nil { await load() }
        } catch MetisError.unauthorized { onUnauthorized() }
        catch { notice = message(for: error) }
    }

    private func begin(_ id: String, cursor: Int = 0, status: String? = nil) {
        interruptedID = nil
        streamCursor = cursor
        streamText = ""
        streamMessageID = nil
        streamStatus = status == "queued" ? "Queued" : nil
        needsReconnect = false
        runningID = id
        scrollRevision &+= 1
    }

    private func follow(_ jobID: String) async {
        needsReconnect = false
        var failures = 0
        while !Task.isCancelled, runningID == jobID {
            var terminal = false
            var failure: String?
            do {
                try await client.observeRun(chatID: chat.id, jobID: jobID, after: streamCursor) { event in
                    guard runningID == jobID, !Task.isCancelled else { return false }
                    if let id = event.id {
                        guard id > streamCursor else { return true }
                        streamCursor = id
                    }
                    failures = 0
                    switch event.name {
                    case "assistantId":
                        struct Assistant: Decodable { let messageId: String }
                        streamMessageID = (try? JSONDecoder().decode(Assistant.self, from: event.data))?.messageId
                    case "text":
                        let wasEmpty = streamText.isEmpty
                        streamText += event.payload?.text ?? ""
                        if wasEmpty && !streamText.isEmpty { scrollRevision &+= 1 }
                    case "text-reset": streamText = ""
                    case "question", "approval":
                        streamStatus = "Waiting for your input"
                        Task { await load() }
                    case "status":
                        let status = event.payload?.status
                        streamStatus = status == "reconnect" ? "Reconnecting…" : event.payload?.message
                        if status == "waiting_for_user" || status == "waiting_input" { Task { await load() } }
                    case "error": failure = event.payload?.message ?? "Run failed."; terminal = true
                    case "done": terminal = true
                    default: break
                    }
                    return !terminal
                }
            } catch MetisError.unauthorized {
                if !Task.isCancelled { onUnauthorized() }
                return
            } catch {}
            guard !Task.isCancelled, runningID == jobID else { return }
            if terminal {
                if failure != nil {
                    let jobs = try? await client.jobs(chatID: chat.id)
                    if jobs?.first?.id == jobID, jobs?.first?.status == "interrupted" {
                        interruptedID = jobID
                    }
                }
                guard !Task.isCancelled, runningID == jobID else { return }
                runningID = nil
                terminalPending = true
                terminalNotice = failure
                terminalRevision &+= 1
                return
            }
            failures += 1
            if failures > 5 {
                streamStatus = "Connection lost"
                needsReconnect = true
                return
            }
            streamStatus = "Reconnecting…"
            do { try await Task.sleep(for: .seconds(1 << (failures - 1))) }
            catch { return }
        }
    }

    private func stop() async {
        guard !cancelling else { return }
        cancelling = true
        defer { cancelling = false }
        do {
            try await client.cancel(chatID: chat.id)
            if runningID != nil {
                streamStatus = "Stopping…"
                if needsReconnect { streamAttempt &+= 1 }
            }
        } catch MetisError.unauthorized {
            onUnauthorized()
        } catch {
            notice = message(for: error)
        }
    }

    private func resume(_ jobID: String) async {
        guard !sending, runningID == nil else { return }
        sending = true
        defer { sending = false }
        do {
            let cursor = try await client.resume(chatID: chat.id, jobID: jobID)
            begin(jobID, cursor: cursor)
        } catch MetisError.unauthorized {
            onUnauthorized()
        } catch {
            notice = message(for: error)
        }
    }

    private func load(before: Int? = nil, clearNotice: Bool = true) async {
        guard !busy else { return }
        busy = true
        if clearNotice { notice = nil }
        defer { busy = false }
        let terminalAtStart = terminalRevision
        await fetchHistory(before: before)
        if !Task.isCancelled, terminalPending, before != nil || terminalRevision != terminalAtStart {
            await fetchHistory(before: nil)
        }
    }

    private func fetchHistory(before: Int?) async {
        let reconcileTerminal = before == nil && terminalPending
        do {
            var response = try await client.chatPage(id: chat.id, before: before, ifNoneMatch: before == nil ? latestETag : nil)
            guard !Task.isCancelled else { return }
            if before != nil {
                guard let page = response.page else { return }
                if history.prepend(page) { return }
                // A positional cursor is tied to the server's revision.
                response = try await client.chatPage(id: chat.id)
                guard !Task.isCancelled else { return }
            }
            if let latest = response.page {
                latestETag = response.etag
                title = latest.chat.title
                chatModel = latest.chat.modelId
                question = latest.chat.pendingQuestion
                pendingApproval = latest.chat.pendingApproval != nil
                history.replaceLatest(with: latest)
                if !history.includesEarlierPages { scrollRevision &+= 1 }
                hasLoaded = true
            }
            if reconcileTerminal {
                terminalPending = false
                streamText = ""
                streamMessageID = nil
                notice = terminalNotice
                terminalNotice = nil
            }
        } catch MetisError.unauthorized {
            if !Task.isCancelled { onUnauthorized() }
        } catch {
            if !Task.isCancelled { notice = message(for: error) }
        }
    }
}
