import AppIntents
import SwiftUI

@MainActor
final class MetisIntentInbox: ObservableObject {
    struct Draft: Identifiable {
        let id = UUID()
        let text: String
    }

    static let shared = MetisIntentInbox()
    @Published var draft: Draft?
    @Published var activityRequest: UUID?
    var statusClient: MetisAPI?
}

struct DraftMetisPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Draft a Metis prompt"
    static var description = IntentDescription("Review the text and choose a Metis chat before sending.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Prompt") var prompt: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 16_000 else {
            return .result(dialog: "Enter a prompt between 1 and 16,000 characters.")
        }
        MetisIntentInbox.shared.draft = .init(text: text)
        return .result(dialog: "Review your prompt in Metis.")
    }
}

struct OpenMetisActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Metis activity"
    static var description = IntentDescription("Show run updates, questions and approvals in Metis.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor func perform() async throws -> some IntentResult {
        MetisIntentInbox.shared.activityRequest = UUID()
        return .result()
    }
}

struct MetisRunStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Metis run status"
    static var description = IntentDescription("Count active runs and chats waiting for input.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let client = MetisIntentInbox.shared.statusClient else {
            return .result(dialog: "Sign in to Metis to check your runs.")
        }
        do {
            let chats = try await client.chats()
            guard MetisIntentInbox.shared.statusClient === client else {
                return .result(dialog: "The Metis account changed. Try again.")
            }
            let active = chats.filter { ["queued", "running", "switching"].contains($0.runStatus ?? "") }.count
            let waiting = chats.filter { ["waiting_input", "waiting_for_user"].contains($0.runStatus ?? "") }.count
            return .result(dialog: "Active runs: \(active). Waiting for input: \(waiting).")
        } catch {
            return .result(dialog: "Metis could not load the run status.")
        }
    }
}

struct MetisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DraftMetisPromptIntent(), phrases: ["Draft a prompt in \(.applicationName)"],
                    shortTitle: "Draft a Prompt", systemImageName: "square.and.pencil")
        AppShortcut(intent: OpenMetisActivityIntent(), phrases: ["Show activity in \(.applicationName)"],
                    shortTitle: "Open Activity", systemImageName: "bell")
        AppShortcut(intent: MetisRunStatusIntent(), phrases: ["Check runs in \(.applicationName)"],
                    shortTitle: "Run Status", systemImageName: "waveform.path")
    }
}

struct ShortcutDraftView: View {
    let draft: MetisIntentInbox.Draft
    let chats: [ChatSummary]
    let open: (ChatSummary, String) -> Void
    let create: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") { Text(verbatim: draft.text).textSelection(.enabled) }
                Section("Destination") {
                    Picker("Chat", selection: $selection) {
                        Text("New chat").tag(nil as String?)
                        ForEach(chats) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Button("Open draft") {
                        dismiss()
                        if let chat = chats.first(where: { $0.id == selection }) { open(chat, draft.text) }
                        else { create(draft.text) }
                    }
                }
            }
            .navigationTitle("Review shared prompt")
            .toolbar { Button("Discard") { dismiss() } }
        }
    }
}
