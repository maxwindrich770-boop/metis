import Foundation
import Combine
import LocalAuthentication

enum MetisBiometry: Equatable {
    case faceID, touchID, unavailable

    var settingsTitle: String {
        switch self {
        case .faceID: return String(localized: "Protect Metis with Face ID")
        case .touchID: return String(localized: "Protect Metis with Touch ID")
        case .unavailable: return String(localized: "Biometric app lock")
        }
    }

    var unlockTitle: String {
        switch self {
        case .faceID: return String(localized: "Unlock with Face ID")
        case .touchID: return String(localized: "Unlock with Touch ID")
        case .unavailable: return String(localized: "Unlock Metis")
        }
    }

    var symbol: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .unavailable: return "lock"
        }
    }
}

struct MetisBiometryAvailability: Equatable {
    let kind: MetisBiometry
    let canUseBiometrics: Bool
}

@MainActor
protocol MetisAppLockAuthenticating: AnyObject {
    func availability() -> MetisBiometryAvailability
    func authenticate(reason: String, requireBiometrics: Bool) async throws -> Bool
    func cancel()
}

@MainActor
final class MetisDeviceOwnerAuthentication: MetisAppLockAuthenticating {
    private var context: LAContext?

    func availability() -> MetisBiometryAvailability {
        let probe = LAContext()
        let usable = probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        // biometryType is meaningful only after canEvaluatePolicy has run.
        let kind: MetisBiometry
        switch probe.biometryType {
        case .faceID: kind = .faceID
        case .touchID: kind = .touchID
        default: kind = .unavailable
        }
        return .init(kind: kind, canUseBiometrics: usable)
    }

    func authenticate(reason: String, requireBiometrics: Bool) async throws -> Bool {
        let request = LAContext()
        request.localizedCancelTitle = String(localized: "Cancel")
        context = request
        defer { if context === request { context = nil } }
        let policy: LAPolicy = requireBiometrics ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        var error: NSError?
        guard request.canEvaluatePolicy(policy, error: &error) else {
            throw error ?? NSError(domain: LAError.errorDomain, code: LAError.biometryNotAvailable.rawValue)
        }
        return try await request.evaluatePolicy(policy, localizedReason: reason)
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }
}

/// Local UI protection. Sessions, drafts and provider settings stay owned by their
/// existing stores. Authentication results from a previous background cycle expire.
@MainActor
final class MetisAppLock: ObservableObject {
    static let preferenceKey = "metisAppLockEnabled"
    @Published private(set) var enabled: Bool
    @Published private(set) var locked: Bool
    @Published private(set) var active = false
    @Published private(set) var authenticating = false
    @Published private(set) var availability: MetisBiometryAvailability
    @Published private(set) var message: String?
    var presentationChanged: (() -> Void)?

    private let defaults: UserDefaults
    private let authentication: MetisAppLockAuthenticating
    private var generation = 0
    private var automaticUnlockPending: Bool

    var covered: Bool { enabled && (locked || !active) }

    init(defaults: UserDefaults = .standard, authentication: MetisAppLockAuthenticating? = nil) {
        let service = authentication ?? MetisDeviceOwnerAuthentication()
        let initiallyEnabled = defaults.bool(forKey: Self.preferenceKey)
        self.defaults = defaults
        self.authentication = service
        enabled = initiallyEnabled
        locked = initiallyEnabled
        automaticUnlockPending = initiallyEnabled
        availability = service.availability()
    }

    func refreshAvailability() {
        let current = authentication.availability()
        if availability != current { availability = current }
    }

    func becomeActive() {
        if !active { active = true }
        refreshAvailability()
        presentationChanged?()
    }

    func resignActive() {
        active = false
        presentationChanged?()
    }

    func enterBackground() {
        active = false
        generation &+= 1
        authentication.cancel()
        authenticating = false
        message = nil
        locked = enabled
        automaticUnlockPending = enabled
        presentationChanged?()
    }

    func unlockAutomaticallyIfNeeded() async {
        guard enabled, locked, active, automaticUnlockPending, !authenticating else { return }
        automaticUnlockPending = false
        await unlock()
    }

    func unlock() async {
        guard enabled, locked, active, !authenticating else { return }
        automaticUnlockPending = false
        guard await authenticate(requireBiometrics: false,
                                 reason: String(localized: "Unlock your Metis workspace.")) else { return }
        locked = false
        presentationChanged?()
    }

    func changeEnabled(to requested: Bool) async {
        guard requested != enabled, active, !authenticating else { return }
        refreshAvailability()
        if requested && !availability.canUseBiometrics {
            message = String(localized: "Set up and allow biometrics in iPhone Settings first.")
            return
        }
        let reason = requested ? String(localized: "Enable protection for your Metis workspace.")
                               : String(localized: "Turn off protection for your Metis workspace.")
        guard await authenticate(requireBiometrics: requested, reason: reason) else { return }
        enabled = requested
        defaults.set(requested, forKey: Self.preferenceKey)
        locked = false
        automaticUnlockPending = false
        presentationChanged?()
    }

    private func authenticate(requireBiometrics: Bool, reason: String) async -> Bool {
        generation &+= 1
        let attempt = generation
        authenticating = true
        message = nil
        defer {
            if generation == attempt { authenticating = false }
        }
        do {
            let accepted = try await authentication.authenticate(reason: reason, requireBiometrics: requireBiometrics)
            guard generation == attempt, accepted, !Task.isCancelled else { return false }
            return true
        } catch {
            guard generation == attempt else { return false }
            let code = (error as NSError).code
            let cancelled = (error as NSError).domain == LAError.errorDomain &&
                [LAError.userCancel.rawValue, LAError.systemCancel.rawValue, LAError.appCancel.rawValue].contains(code)
            if !cancelled {
                message = String(localized: "Authentication could not be completed. Try again or use your iPhone passcode.")
            }
            return false
        }
    }
}

#if canImport(UIKit)
import UIKit
import SwiftUI

extension MetisAppLock {
    #if DEBUG && targetEnvironment(simulator)
    var syntheticDiagnostic: String {
        (authentication as? SyntheticAppLockAuthentication)?.diagnostic ?? "Real authentication"
    }
    #endif

    static func forApplication() -> MetisAppLock {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-metis.app-lock-fixture"),
           arguments.indices.contains(index + 1) {
            let kind: MetisBiometry
            switch arguments[index + 1] {
            case "faceID": kind = .faceID
            case "touchID": kind = .touchID
            default: kind = .unavailable
            }
            if arguments.contains("-metis.app-lock-reset") {
                UserDefaults.standard.removeObject(forKey: preferenceKey)
            }
            return MetisAppLock(authentication: SyntheticAppLockAuthentication(kind: kind))
        }
        #endif
        return MetisAppLock()
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit fixture for native UI lifecycle tests, never compiled for a phone.
/// Its visibly labelled prompt must not be mistaken for an Apple biometric test.
@MainActor
private final class SyntheticAppLockAuthentication: MetisAppLockAuthenticating {
    let kind: MetisBiometry
    private(set) var diagnostic = "Not requested"
    private var pending: CheckedContinuation<Bool, Error>?
    private weak var alert: UIAlertController?

    init(kind: MetisBiometry) { self.kind = kind }
    func availability() -> MetisBiometryAvailability {
        .init(kind: kind, canUseBiometrics: kind != .unavailable)
    }
    func authenticate(reason: String, requireBiometrics: Bool) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard var presenter = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else {
                diagnostic = "No key-window presenter in " + String(scenes.count) + " scenes"
                continuation.resume(returning: false)
                return
            }
            diagnostic = "Presenting synthetic confirmation"
            while let presented = presenter.presentedViewController { presenter = presented }
            let prompt = UIAlertController(title: "SYNTHETIC biometric verification",
                                           message: "Simulator fixture only. " + reason, preferredStyle: .alert)
            pending = continuation
            alert = prompt
            prompt.addAction(UIAlertAction(title: "Approve synthetic authentication", style: .default) { [weak self] _ in self?.finish(true) })
            prompt.addAction(UIAlertAction(title: "Cancel synthetic authentication", style: .cancel) { [weak self] _ in self?.finish(false) })
            presenter.present(prompt, animated: false)
        }
    }
    func cancel() {
        alert?.dismiss(animated: false)
        finish(false)
    }
    private func finish(_ accepted: Bool) {
        let reply = pending
        pending = nil
        alert = nil
        reply?.resume(returning: accepted)
    }
}
#endif

/// A scene window covers SwiftUI sheets and Safari/share presentations as well as
/// the Web workspace. It is shown synchronously before app-switcher snapshots.
struct MetisAppLockWindow: UIViewRepresentable {
    let lock: MetisAppLock

    func makeCoordinator() -> Coordinator { Coordinator(lock: lock) }
    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Anchor, context: Context) {}

    final class Anchor: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) }
        }
    }

    @MainActor
    final class Coordinator {
        let lock: MetisAppLock
        private weak var contentWindow: UIWindow?
        private var shield: UIWindow?
        private var observers: [NSObjectProtocol] = []

        init(lock: MetisAppLock) {
            self.lock = lock
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.lock.resignActive() }
                },
                center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] notification in
                    MainActor.assumeIsolated {
                        guard let self, let scene = notification.object as? UIWindowScene,
                              scene === self.contentWindow?.windowScene else { return }
                        self.lock.resignActive()
                    }
                },
                center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if self.lock.enabled { self.contentWindow?.endEditing(true) }
                        self.lock.enterBackground()
                    }
                },
                center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.becameActive() }
                }
            ]
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }

        func attach(to window: UIWindow) {
            guard contentWindow !== window, let scene = window.windowScene else { return }
            contentWindow = window
            let cover = UIWindow(windowScene: scene)
            cover.windowLevel = .alert + 1
            cover.backgroundColor = .systemBackground
            let host = UIHostingController(rootView: MetisAppLockScreen(lock: lock))
            host.view.backgroundColor = .systemBackground
            host.view.accessibilityViewIsModal = true
            cover.rootViewController = host
            shield = cover
            lock.presentationChanged = { [weak self] in self?.updatePresentation() }
            if UIApplication.shared.applicationState == .active { becameActive() }
            else { updatePresentation() }
        }

        private func becameActive() {
            lock.becomeActive()
            Task { await lock.unlockAutomaticallyIfNeeded() }
        }

        private func updatePresentation() {
            guard let shield else { return }
            if lock.covered {
                if lock.locked { contentWindow?.endEditing(true) }
                shield.isHidden = false
                if lock.active && lock.locked { shield.makeKey() }
            } else {
                let restoreKey = shield.isKeyWindow
                shield.isHidden = true
                if restoreKey { contentWindow?.makeKey() }
            }
        }
    }
}

private struct MetisAppLockScreen: View {
    @ObservedObject var lock: MetisAppLock

    var body: some View {
        VStack(spacing: 24) {
            Image("MetisWordmark").resizable().scaledToFit().frame(width: 150, height: 44)
                .accessibilityHidden(true)
            Image(systemName: lock.availability.kind.symbol).font(.system(size: 44))
                .accessibilityHidden(true)
            Text("Metis is locked").font(.title2.bold())
                .accessibilityIdentifier("metis.appLock.cover")
            if lock.active {
                if let message = lock.message { Text(message).font(.footnote).multilineTextAlignment(.center) }
                Button { Task { await lock.unlock() } } label: {
                    Label(lock.availability.kind.unlockTitle, systemImage: lock.availability.kind.symbol)
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(lock.authenticating)
                .accessibilityIdentifier("metis.appLock.unlock")
                if lock.authenticating { ProgressView().accessibilityLabel(Text("Authenticating")) }
                Text("Your iPhone passcode can be used if needed.").font(.footnote)
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}

struct MetisAppLockSettings: View {
    @ObservedObject var lock: MetisAppLock

    var body: some View {
        Section {
            if lock.availability.kind != .unavailable || lock.enabled {
                Toggle(isOn: Binding(get: { lock.enabled }, set: { requested in
                    Task { await lock.changeEnabled(to: requested) }
                })) {
                    Label(lock.availability.kind.settingsTitle, systemImage: lock.availability.kind.symbol)
                }
                .disabled(lock.authenticating || (!lock.enabled && !lock.availability.canUseBiometrics))
                .accessibilityIdentifier("metis.appLock.toggle")
                if !lock.availability.canUseBiometrics {
                    Text("Set up and allow biometrics in iPhone Settings first.").font(.footnote)
                }
            } else {
                LabeledContent("Biometric app lock", value: String(localized: "Not available"))
                    .accessibilityIdentifier("metis.appLock.unavailable")
            }
            if let message = lock.message { Text(message).font(.footnote) }
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-metis.app-lock-fixture") {
                Text(verbatim: "SYNTHETIC lock state: active=\(lock.active), busy=\(lock.authenticating), \(lock.syntheticDiagnostic)")
                    .font(.caption2).accessibilityIdentifier("metis.appLock.syntheticState")
            }
            #endif
        } header: {
            Text("App protection")
        } footer: {
            Text("Metis locks when you leave the app. Your iPhone passcode can be used if needed.")
        }
        .onAppear { lock.refreshAvailability() }
    }
}
#endif
