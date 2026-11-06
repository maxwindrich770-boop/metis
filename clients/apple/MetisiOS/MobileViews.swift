import LocalAuthentication
import Security
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers
import QuickLook

// Native counterparts of the neutral light/dark tokens in app/globals.css.
// Keep provider and model metadata out of this presentation layer.
enum MetisTheme {
    static let background = neutral(light: 0.980, dark: 0.025)
    static let surface = neutral(light: 1.000, dark: 0.047)
    static let secondary = neutral(light: 0.961, dark: 0.079)
    static let ink = neutral(light: 0.090, dark: 0.980)
    static let muted = neutral(light: 0.420, dark: 0.650)
    static let border = neutral(light: 0.860, dark: 0.220)
    static let primary = neutral(light: 0.145, dark: 0.898)
    static let onPrimary = neutral(light: 0.980, dark: 0.145)
    static let corner: CGFloat = 14

    private static func neutral(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }
}

struct MetisWordmark: View {
    var width: CGFloat = 64

    var body: some View {
        Image("MetisWordmark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: width, height: width * 904.859 / 2138.473)
            .foregroundStyle(MetisTheme.ink)
            .accessibilityLabel("Metis")
    }
}

struct MetisPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(MetisTheme.onPrimary)
            .background(MetisTheme.primary, in: RoundedRectangle(cornerRadius: MetisTheme.corner))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

struct MetisIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct MetisField<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(MetisTheme.muted)
                    .accessibilityHidden(true)
                content
                    .font(.body)
                    .frame(minHeight: 52)
            }
            .padding(.horizontal, 16)
            .background(MetisTheme.surface, in: RoundedRectangle(cornerRadius: MetisTheme.corner))
            .overlay {
                RoundedRectangle(cornerRadius: MetisTheme.corner)
                    .strokeBorder(MetisTheme.border, lineWidth: 1)
            }
        }
    }
}

struct MetisNotice: View {
    let text: String
    var accessibilityID = ""

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(accessibilityID)
        } icon: {
            Image(systemName: "info.circle").accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(MetisTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MetisTheme.secondary, in: RoundedRectangle(cornerRadius: MetisTheme.corner))
    }
}

struct MetisChatRow: View {
    let chat: ChatSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: chat.pinned == true ? "pin" : "bubble.left")
                .font(.body)
                .foregroundStyle(MetisTheme.muted)
                .frame(width: 40, height: 40)
                .background(MetisTheme.secondary, in: RoundedRectangle(cornerRadius: MetisTheme.corner))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(chat.title.isEmpty ? String(localized: "Untitled chat") : chat.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(MetisTheme.ink)
                    .lineLimit(2)
                if chat.pendingApproval != nil {
                    Label("Approval required", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(MetisTheme.muted)
                } else if chat.pendingQuestion != nil {
                    Label("Agent question", systemImage: "questionmark.bubble")
                        .font(.caption).foregroundStyle(MetisTheme.muted)
                } else if let status = chat.runStatus, status != "idle" {
                    Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption).foregroundStyle(MetisTheme.muted)
                } else if let date = lastActivity {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption).foregroundStyle(MetisTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chat.archived == true {
                Image(systemName: "archivebox").foregroundStyle(MetisTheme.muted)
                    .accessibilityLabel("Archived")
            }
        }
        .padding(.vertical, 8)
    }

    static func accessibilityStatus(for chat: ChatSummary) -> String {
        var values: [String] = []
        if chat.pinned == true { values.append(String(localized: "Pinned")) }
        if chat.archived == true { values.append(String(localized: "Archived")) }
        if chat.pendingApproval != nil { values.append(String(localized: "Approval required")) }
        if chat.pendingQuestion != nil { values.append(String(localized: "Agent question")) }
        if let status = chat.runStatus, status != "idle" {
            values.append(status.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        return values.joined(separator: ", ")
    }

    private var lastActivity: Date? {
        guard let value = chat.lastMessageSent ?? chat.createdAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

extension View {
    func metisScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(MetisTheme.background)
            .toolbarBackground(MetisTheme.background, for: .navigationBar, .tabBar)
            .toolbarBackground(.visible, for: .navigationBar, .tabBar)
    }
}

struct ChatMarkdown: View {
    private enum Block {
        case prose(String)
        case code(String, language: String)
    }

    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let content):
                    Text((try? AttributedString(markdown: content,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content))
                case .code(let content, let language):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if !language.isEmpty { Text(verbatim: language).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Copy code", systemImage: "doc.on.doc") {
                                UIPasteboard.general.setItems(
                                    [[UTType.plainText.identifier: content]], options: [.localOnly: true]
                                )
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        ScrollView(.horizontal) {
                            Text(verbatim: content).font(.system(.footnote, design: .monospaced))
                        }
                    }
                    .padding(12)
                    .background(MetisTheme.secondary, in: RoundedRectangle(cornerRadius: MetisTheme.corner))
                }
            }
        }
        .font(.body)
        .lineSpacing(4)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return .systemAction }
            return .discarded
        })
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var lines: [String] = []
        var fence: String?
        var language = ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let closing = fence {
                if trimmed == closing {
                    result.append(.code(lines.joined(separator: "\n"), language: language))
                    lines.removeAll(keepingCapacity: true)
                    fence = nil
                } else { lines.append(line) }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if !lines.isEmpty { result.append(.prose(lines.joined(separator: "\n"))) }
                lines.removeAll(keepingCapacity: true)
                fence = String(trimmed.prefix(3))
                language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else { lines.append(line) }
        }
        if !lines.isEmpty {
            let trailing = lines.joined(separator: "\n")
            result.append(fence == nil ? .prose(trailing) : .code(trailing, language: language))
        }
        return result
    }
}

struct AttachmentPreview: View {
    let url: URL
    @State private var preview: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text(url.lastPathComponent)
            Button("Preview", systemImage: "doc.text.magnifyingglass") { preview = url }
            ShareLink(item: url)
        }
        .padding()
        .quickLookPreview($preview)
    }
}

enum MobilePushKind: String, CaseIterable, Identifiable {
    case done, error, question, approval
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .done: return "Completed runs"
        case .error: return "Run failures"
        case .question: return "Agent questions"
        case .approval: return "Approval requests"
        }
    }
}

enum MobilePushAvailability {
    // The isolated Personal Team project deliberately removes APNs entitlements.
    // Absence of this marker makes no claim about the actual signed profile.
    static var buildExplanation: String? {
        guard Bundle.main.object(forInfoDictionaryKey: "MetisPushUnavailableReason") as? String == "personal-team" else { return nil }
        return String(localized: "This iPhone test build has no Apple push entitlement. Push alerts require a build signed with a push-enabled provisioning profile. iPhone Settings cannot enable push for this build.")
    }

    static var missingBackendExplanation: String {
        String(localized: "This Metis server does not yet provide the mobile push API. A server update is required before this app can enable push alerts.")
    }

    struct UnsupportedBuild: LocalizedError {
        var errorDescription: String? { MobilePushAvailability.buildExplanation }
    }
}

struct PushSettingsView: View {
    @Binding var events: Set<MobilePushKind>
    let enabled: Bool
    let busy: Bool
    let status: String?
    var client: MetisAPI? = nil
    let change: () -> Void
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var explanation = MobilePushAvailability.buildExplanation
    @State private var checking = true
    @State private var canEnable = false
    @State private var permissionDenied = false
    @State private var canRetry = false

    var body: some View {
        NavigationStack {
            Form {
                if checking && explanation == nil {
                    ProgressView("Checking push availability…")
                }
                if let explanation {
                    Section {
                        MetisNotice(text: explanation, accessibilityID: "metis.pushAvailability")
                        if permissionDenied {
                            Button("Open iPhone Settings", action: openSettings)
                        }
                        if canRetry {
                            Button("Try again") { Task { await loadAvailability() } }
                                .disabled(checking || busy)
                        }
                    }
                }
                Section("Alert types") {
                    ForEach(MobilePushKind.allCases) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { events.contains(kind) },
                            set: { if $0 { events.insert(kind) } else { events.remove(kind) } }
                        ))
                    }
                }
                .disabled(busy || (!enabled && !canEnable))
                if let status { Text(LocalizedStringKey(status)).font(.footnote) }
                if busy { ProgressView("Updating push registration…") }
                if enabled {
                    Button("Save alert filters", action: save).disabled(busy)
                }
                Button(enabled ? "Disable push alerts" : "Enable push alerts", action: change)
                    .disabled(busy || (!enabled && (checking || !canEnable)))
                    .accessibilityIdentifier("metis.changePush")
            }
            .metisScreen()
            .navigationTitle("Push alerts")
            .toolbar { Button("Done") { dismiss() } }
            .task { await loadAvailability() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadAvailability() } }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    @MainActor
    private func loadAvailability() async {
        checking = true
        canEnable = false
        canRetry = false
        permissionDenied = false
        defer { checking = false }
        if let buildExplanation = MobilePushAvailability.buildExplanation {
            explanation = buildExplanation
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled else { return }
        if settings.authorizationStatus == .denied {
            permissionDenied = true
            explanation = String(localized: "Notifications are turned off for Metis in iPhone Settings. Allow notifications there, then return to enable push alerts.")
            return
        }
        guard let client else {
            explanation = String(localized: "Push support could not be checked. Check your connection and try again.")
            canRetry = true
            return
        }
        do {
            let supported = try await client.pushSupported()
            guard !Task.isCancelled else { return }
            canEnable = supported
            explanation = supported ? nil : String(localized: "Apple push delivery is not configured on this Metis server. The server operator must configure it before you can enable push alerts.")
        } catch MetisError.http(404, _) {
            explanation = MobilePushAvailability.missingBackendExplanation
        } catch MetisError.unauthorized {
            explanation = String(localized: "Your session is no longer valid. Sign in again.")
        } catch MetisError.unexpectedResponse {
            explanation = String(localized: "The server returned an unknown push capability response. Check that the app and server are up to date, then try again.")
            canRetry = true
        } catch {
            guard !Task.isCancelled else { return }
            explanation = String(localized: "Push support could not be checked. Check your connection and try again.")
            canRetry = true
        }
    }
}

private struct ConnectionSettingsSurface: ViewModifier {
    let glass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if glass {
            content
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content.metisScreen()
        }
    }
}

struct ConnectionSettingsView: View {
    let client: MetisAPI
    let installationID: String
    @ObservedObject var appLock: MetisAppLock
    @Binding var watchEnabled: Bool
    let pushEnabled: Bool
    let showPush: () -> Void
    let signOut: () -> Void
    let busy: Bool
    let status: String?
    let didRemoveCurrentDevice: () -> Void
    let unauthorized: () -> Void
    var title: LocalizedStringKey = "Settings"
    var close: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @State private var account: String?
    @State private var devices: [MetisRegisteredDevice] = []
    @State private var error: String?
    @State private var devicesLoaded = false
    @State private var accountError: String?
    @State private var devicesError: String?
    @State private var deleting: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Server", value: client.origin)
                    if let account {
                        LabeledContent("Account", value: account)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Account"))
                            .accessibilityValue(Text(verbatim: account))
                            .accessibilityIdentifier("metis.accountName")
                    }
                    if let accountError { Text(accountError).font(.footnote) }
                    LabeledContent("Version", value: version)
                }
                Section("Push devices") {
                    if let devicesError { Text(devicesError).font(.footnote) }
                    if devicesLoaded && devices.isEmpty { Text("No registered devices") }
                    ForEach(devices) { device in
                        VStack(alignment: .leading) {
                            Text(isCurrent(device) ? "This iPhone" : "Other iPhone")
                            let expires = Date(timeIntervalSince1970: Double(device.expiresAt) / 1_000)
                            Text(expires, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                            Button("Remove push registration", role: .destructive) {
                                Task { await remove(device) }
                            }
                            .disabled(deleting != nil)
                        }
                    }
                }
                MetisAppLockSettings(lock: appLock)
                Section("Privacy and permissions") {
                    Toggle("Allow Apple Watch access", isOn: $watchEnabled)
                    Button(action: showPush) {
                        LabeledContent("Push alerts", value: pushStatus)
                    }
                    if let explanation = MobilePushAvailability.buildExplanation {
                        Text(explanation).font(.footnote)
                    }
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    ShareLink(item: "Metis Apple \(version)\niOS \(UIDevice.current.systemVersion)\nPush: \(pushEnabled)\nWatch: \(watchEnabled)") {
                        Label("Share diagnostics", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Sign out", role: .destructive, action: signOut).disabled(busy)
                if let error { Text(error).font(.footnote) }
                if let status { Text(status).font(.footnote) }
            }
            .modifier(ConnectionSettingsSurface(glass: close != nil))
            .navigationTitle(title)
            .toolbar {
                if let close {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: close)
                            .accessibilityIdentifier("metis.iPhoneSettingsDone")
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var pushStatus: String {
        if MobilePushAvailability.buildExplanation != nil { return String(localized: "Requires a push-enabled build") }
        return pushEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
    }

    private func isCurrent(_ device: MetisRegisteredDevice) -> Bool {
        device.id.caseInsensitiveCompare(installationID) == .orderedSame
    }

    private func load() async {
        do {
            account = try await client.profileName()
            accountError = nil
        } catch MetisError.unauthorized { unauthorized(); return }
        catch MetisError.http(404, _) {
            accountError = String(localized: "This server does not provide account details to the app. Your account settings are available in the Metis workspace.")
        } catch { if !Task.isCancelled { accountError = message(for: error) } }
        guard !Task.isCancelled else { return }
        do {
            devices = try await client.pushDevices()
            devicesLoaded = true
            devicesError = nil
        } catch MetisError.unauthorized { unauthorized() }
        catch MetisError.http(404, _) {
            devicesError = String(localized: "This Metis server does not yet support push device management.")
        } catch { if !Task.isCancelled { devicesError = message(for: error) } }
    }

    private func remove(_ device: MetisRegisteredDevice) async {
        guard deleting == nil else { return }
        deleting = device.id
        defer { deleting = nil }
        do {
            try await client.revokePush(installationID: device.id)
            devices.removeAll { $0.id == device.id }
            if isCurrent(device) { didRemoveCurrentDevice() }
        } catch MetisError.unauthorized { unauthorized() }
        catch { self.error = message(for: error) }
    }
}

enum InstallationIdentity {
    static let current: String = {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "Metis",
            kSecAttrAccount as String: "push-installation",
        ]
        var query = item
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let id = String(data: data, encoding: .utf8),
           UUID(uuidString: id) != nil { return id }
        let id = UUID().uuidString
        var create = item
        create[kSecValueData as String] = Data(id.utf8)
        create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(create as CFDictionary, nil)
        return id
    }()
}

@MainActor
enum MetisSessionVault {
    private struct State: Codable {
        var active: StoredMetisSession?
        var pending: [PendingMetisLogout] = []
    }

    private static var key: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "Metis",
         kSecAttrAccount as String: "account-session"]
    }

    static var active: StoredMetisSession? { read().active }
    static var pending: [PendingMetisLogout] { read().pending.filter { $0.expiresAt > Date() } }

    static func replace(_ session: StoredMetisSession) {
        var state = read()
        if state.active?.cookie != session.cookie { enqueue(state.active, in: &state) }
        state.active = session
        if !save(state) { SecItemDelete(key as CFDictionary) }
    }

    static func close() -> Bool {
        var state = read()
        enqueue(state.active, in: &state)
        state.active = nil
        if save(state) { return true }
        SecItemDelete(key as CFDictionary)
        return false
    }

    static func removePending(_ id: String) {
        var state = read()
        state.pending.removeAll { $0.id == id || $0.expiresAt <= Date() }
        _ = save(state)
    }

    static func setPreferences(pushEvents: [String]?, watchEnabled: Bool) {
        var state = read()
        guard state.active != nil else { return }
        state.active?.pushEvents = pushEvents
        state.active?.watchEnabled = watchEnabled
        _ = save(state)
    }

    @discardableResult
    static func setWebModelPreferences(_ preferences: [String: String], origin: String, cookie: String) -> Bool {
        guard let checked = MetisWebPreferencePolicy.sanitized(preferences) else { return false }
        var state = read()
        guard state.active?.origin == origin, state.active?.cookie == cookie else { return false }
        state.active?.webModelPreferences = checked
        return save(state)
    }

    private static func enqueue(_ session: StoredMetisSession?, in state: inout State) {
        guard let session, session.expiresAt > Date(), let ticket = session.revocationTicket,
              !state.pending.contains(where: { $0.ticket == ticket }) else { return }
        state.pending = state.pending.filter { $0.expiresAt > Date() }
        state.pending.append(PendingMetisLogout(origin: session.origin, ticket: ticket, expiresAt: session.expiresAt))
    }

    private static func read() -> State {
        var query = key
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let state = try? JSONDecoder().decode(State.self, from: data) { return state }
        return State()
    }

    private static func save(_ state: State) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }
        let attributes = [kSecValueData as String: data]
        let updated = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var item = key
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

struct DraftAttachment: Identifiable {
    let id = UUID()
    let url: URL
    let mimeType: String
    var temporary = false
    var uploadID: String?

    func clean() {
        if temporary { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
}

struct DownloadedAttachment: Identifiable {
    let id = UUID()
    let url: URL

    func clean() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

struct ImportedPhoto: Transferable {
    let url: URL
    let mimeType: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let file = received.file
            let type = UTType(filenameExtension: file.pathExtension)
            let destination = try location(name: file.lastPathComponent)
            do { try FileManager.default.copyItem(at: file, to: destination) }
            catch {
                try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                throw error
            }
            return ImportedPhoto(url: destination, mimeType: type?.preferredMIMEType ?? "application/octet-stream")
        }
    }

    static func copy(data: Data) throws -> URL {
        let destination = try location(name: "Camera.jpg")
        do { try data.write(to: destination, options: .completeFileProtection) }
        catch {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
            throw error
        }
        return destination
    }

    private static func location(name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        return folder.appendingPathComponent(name)
    }
}

struct CameraCapture: UIViewControllerRepresentable {
    let result: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(result: result) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let result: (UIImage?) -> Void
        init(result: @escaping (UIImage?) -> Void) { self.result = result }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { result(nil) }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            result(info[.originalImage] as? UIImage)
        }
    }
}

@MainActor
final class MetisAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    let watch = WatchRelay()
    @Published private(set) var token: String?
    @Published private(set) var registrationFailed = false
    @Published var notificationID: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let notifications = UNUserNotificationCenter.current()
        notifications.delegate = self
        let review = UNNotificationAction(identifier: "METIS_REVIEW", title: String(localized: "Open Metis"),
                                          options: [.foreground, .authenticationRequired])
        notifications.setNotificationCategories([
            UNNotificationCategory(identifier: "METIS_UPDATE", actions: [review], intentIdentifiers: [], options: [])
        ])
        watch.start()
        return true
    }

    func requestPush() async throws -> Bool {
        guard MobilePushAvailability.buildExplanation == nil else { throw MobilePushAvailability.UnsupportedBuild() }
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        if granted {
            registrationFailed = false
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    func renewPush() async -> Bool {
        guard MobilePushAvailability.buildExplanation == nil else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return false }
        registrationFailed = false
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        registrationFailed = false
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        token = nil
        registrationFailed = true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        if [UNNotificationDefaultActionIdentifier, "METIS_REVIEW"].contains(response.actionIdentifier),
           let id = response.notification.request.content.userInfo["notificationId"] as? String {
            await MainActor.run { notificationID = id }
        }
    }
}

struct ActivityView: View {
    let client: MetisAPI
    let chats: [ChatSummary]
    let openChat: (String) -> Void
    let unauthorized: () -> Void
    @State private var items: [MetisNotification] = []
    @State private var failure: String?
    @State private var loaded = false

    var body: some View {
        let pending = chats.filter { $0.pendingApproval != nil || $0.pendingQuestion != nil }
        NavigationStack {
            List {
                if let failure { Text(failure).font(.footnote) }
                if !pending.isEmpty {
                    Section("Needs attention") {
                        ForEach(pending) { chat in
                            Button { openChat(chat.id) } label: {
                                VStack(alignment: .leading) {
                                    Text(verbatim: chat.title)
                                    if chat.pendingApproval != nil { Text("Approval required").font(.footnote) }
                                    if chat.pendingQuestion != nil { Text("Agent question").font(.footnote) }
                                }
                            }
                        }
                    }
                }
                if loaded && items.isEmpty && pending.isEmpty {
                    ContentUnavailableView("No activity", systemImage: "bell")
                }
                ForEach(items) { item in
                    Button {
                        Task {
                            do {
                                try await client.markRead(item.id)
                                if let id = item.chatId { openChat(id) }
                                await load()
                            } catch MetisError.unauthorized { unauthorized() }
                            catch { failure = message(for: error) }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.title).fontWeight(item.readAt == nil ? .semibold : .regular)
                            Text(verbatim: item.body).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .metisScreen()
            .navigationTitle("Activity")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do { items = try await client.notifications(); loaded = true; failure = nil }
        catch MetisError.unauthorized { unauthorized() }
        catch { if !Task.isCancelled { failure = message(for: error) } }
    }
}

struct ProjectsView: View {
    let client: MetisAPI
    let openChat: (String) -> Void
    let unauthorized: () -> Void
    @State private var projects: [MetisProject] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).font(.footnote) }
                ForEach(projects) { project in
                    NavigationLink {
                        ProjectDetail(project: project, client: client, open: openChat, unauthorized: unauthorized)
                    } label: {
                        HStack {
                            Text(verbatim: project.name)
                            Spacer()
                            if let mode = project.mode { Text(mode.capitalized).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .metisScreen()
            .navigationTitle("Projects")
            .task {
                do { projects = try await client.projects() }
                catch MetisError.unauthorized { unauthorized() }
                catch { self.error = message(for: error) }
            }
        }
    }
}

private struct ProjectDetail: View {
    let project: MetisProject
    let client: MetisAPI
    let open: (String) -> Void
    let unauthorized: () -> Void
    @State private var chats: [ChatSummary] = []
    @State private var agents: [MetisProjectAgent] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).font(.footnote) }
            ForEach(agents) { agent in
                Button { open(agent.chatId) } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: agent.name)
                        if let status = agent.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            ForEach(chats) { chat in Button(chat.title) { open(chat.id) } }
        }
        .metisScreen()
        .navigationTitle(project.name)
        .task {
            do {
                if project.mode == "agents" { agents = try await client.agents(projectID: project.id) }
                else { chats = try await client.chats().filter { $0.projectId == project.id } }
            } catch MetisError.unauthorized { unauthorized() }
            catch { if !Task.isCancelled { self.error = message(for: error) } }
        }
    }
}
struct ApprovalView: View {
    let approval: MetisApproval
    let decide: (Bool) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Requested action") {
                    Text(verbatim: approval.title)
                    if let command = approval.command {
                        Text(verbatim: command).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    }
                    ForEach(Array((approval.files ?? []).enumerated()), id: \.offset) { _, file in
                        LabeledContent(file.status, value: file.path)
                    }
                }
                if let error { Text(error).font(.footnote) }
                Button("Allow once") { Task { await submit(true) } }.disabled(busy)
                Button("Deny", role: .destructive) { Task { await submit(false) } }.disabled(busy)
            }
            .navigationTitle("Review approval")
            .toolbar { Button("Close") { dismiss() }.disabled(busy) }
            .interactiveDismissDisabled(busy)
        }
    }

    private func submit(_ allow: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if allow {
            let context = LAContext()
            do {
                guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Approve this Metis action once.") else { return }
            } catch {
                self.error = "Biometric confirmation was unavailable or cancelled."
                return
            }
        }
        error = await decide(allow)
        if error == nil { dismiss() }
    }
}

struct QuestionView: View {
    let question: MetisQuestion
    let answer: ([String: String]) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var error: String?
    @State private var fieldErrors: [String: String] = [:]
    @State private var customOptions: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if let description = question.description { Text(verbatim: description) }
                ForEach(Array(question.questions.enumerated()), id: \.element.id) { index, field in
                    let key = field.key ?? "question_\(index + 1)"
                    if field.showWhen.map({ values[$0.key] == $0.equals.value }) ?? true {
                        Section(field.question) {
                            if let description = field.description {
                                Text(verbatim: description).font(.footnote).foregroundStyle(.secondary)
                            }
                            input(field, key: key)
                            if let error = fieldErrors[key] { Text(error).font(.footnote).foregroundStyle(.red) }
                        }
                    }
                }
                if let error { Text(error).font(.footnote) }
                Button("Submit answer") {
                    Task {
                        guard !busy else { return }
                        busy = true
                        defer { busy = false }
                        error = nil
                        fieldErrors = [:]
                        do { try await answer(values); dismiss() }
                        catch MetisError.questionFields(let errors) {
                            fieldErrors = errors
                            self.error = MetisError.questionFields(errors).localizedDescription
                        } catch { self.error = message(for: error) }
                    }
                }
                .disabled(busy || question.version == nil)
            }
            .navigationTitle(question.title ?? "Agent question")
            .toolbar { Button("Close") { dismiss() }.disabled(busy) }
            .interactiveDismissDisabled(busy)
            .onAppear {
                for (index, field) in question.questions.enumerated() {
                    let key = field.key ?? "question_\(index + 1)"
                    if values[key] == nil {
                        values[key] = field.defaultValue?.value ?? (["checkbox", "toggle"].contains(field.type ?? "") ? "false" :
                            field.type == "slider" ? field.min.map(String.init(describing:)) ?? "" : "")
                    }
                }
            }
        }
    }

    @ViewBuilder private func input(_ field: MetisQuestion.Field, key: String) -> some View {
        let value = Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
        switch field.type {
        case "checkbox", "toggle":
            Toggle("Yes", isOn: Binding(get: { value.wrappedValue == "true" }, set: { value.wrappedValue = String($0) }))
        case "radio", "select":
            ForEach(Array((field.options ?? []).enumerated()), id: \.offset) { _, option in
                Button {
                    value.wrappedValue = option.value?.value ?? option.label
                } label: {
                    LabeledContent(option.label) {
                        if value.wrappedValue == (option.value?.value ?? option.label) { Image(systemName: "checkmark") }
                    }
                }
                .buttonStyle(.borderless)
            }
            TextField("Answer", text: value)
        case "multiselect":
            ForEach(Array((field.options ?? []).enumerated()), id: \.offset) { _, option in
                let optionValue = option.value?.value ?? option.label
                Toggle(option.label, isOn: Binding(
                    get: { selected(value.wrappedValue).contains(optionValue) },
                    set: { checked in
                        var options = selected(value.wrappedValue).filter { $0 != optionValue }
                        if checked { options.append(optionValue) }
                        if let encoded = try? JSONEncoder().encode(options) {
                            value.wrappedValue = String(decoding: encoded, as: UTF8.self)
                        }
                    }
                ))
            }
            let known = Set((field.options ?? []).map { $0.value?.value ?? $0.label })
            ForEach(selected(value.wrappedValue).filter { !known.contains($0) }, id: \.self) { item in
                Button(role: .destructive) { setSelected(selected(value.wrappedValue).filter { $0 != item }, value) } label: {
                    Label(item, systemImage: "minus.circle")
                }
            }
            let custom = Binding(get: { customOptions[key] ?? "" }, set: { customOptions[key] = $0 })
            TextField("Other answer", text: custom)
            Button("Add answer") {
                let item = custom.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !item.isEmpty, !selected(value.wrappedValue).contains(item) else { return }
                setSelected(selected(value.wrappedValue) + [item], value)
                custom.wrappedValue = ""
            }
        case "task_list":
            TextField("One step per line", text: Binding(
                get: { selected(value.wrappedValue).joined(separator: "\n") },
                set: { setSelected($0.components(separatedBy: "\n"), value) }
            ), axis: .vertical)
            .lineLimit(2...10)
        case "slider":
            if let min = field.min, let max = field.max, min < max {
                let current = Binding(get: { Swift.min(max, Swift.max(min, Double(value.wrappedValue) ?? min)) },
                                      set: { value.wrappedValue = String($0) })
                if let step = field.step, step > 0, step <= max - min {
                    Slider(value: current, in: min...max, step: step)
                } else {
                    Slider(value: current, in: min...max)
                }
                Text(current.wrappedValue, format: .number)
            } else {
                TextField("Number", text: value).keyboardType(.numbersAndPunctuation)
            }
        case "number":
            TextField("Number", text: value).keyboardType(.numbersAndPunctuation)
        default:
            TextField(field.type == "date" ? "YYYY-MM-DD" : field.type == "time" ? "HH:MM" : "Answer", text: value, axis: .vertical)
                .lineLimit(1...5)
        }
    }

    private func selected(_ text: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }

    private func setSelected(_ values: [String], _ binding: Binding<String>) {
        if let data = try? JSONEncoder().encode(values) { binding.wrappedValue = String(decoding: data, as: UTF8.self) }
    }
}
