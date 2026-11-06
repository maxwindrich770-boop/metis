import Foundation
import LocalAuthentication

@MainActor
private final class AuthenticationFixture: MetisAppLockAuthenticating {
    enum Result { case accept, reject, cancel, deferred }
    var capability = MetisBiometryAvailability(kind: .faceID, canUseBiometrics: true)
    var next: Result = .accept
    var policies: [Bool] = []
    var continuation: CheckedContinuation<Bool, Error>?
    var cancelled = 0

    func availability() -> MetisBiometryAvailability { capability }
    func authenticate(reason: String, requireBiometrics: Bool) async throws -> Bool {
        policies.append(requireBiometrics)
        switch next {
        case .accept: return true
        case .reject: return false
        case .cancel: throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue)
        case .deferred:
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }
    // Deliberately retain a pending callback to exercise late-success races.
    func cancel() { cancelled += 1 }
    func complete() { continuation?.resume(returning: true); continuation = nil }
}

@main
struct AppLockSmoke {
    @MainActor static func main() async {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ description: String) {
            precondition(value(), description)
            checks += 1
        }
        let suite = "metis-applock-smoke-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        for kind in [MetisBiometry.faceID, .touchID] {
            defaults.removeObject(forKey: MetisAppLock.preferenceKey)
            let auth = AuthenticationFixture()
            auth.capability = .init(kind: kind, canUseBiometrics: true)
            let lock = MetisAppLock(defaults: defaults, authentication: auth)
            lock.becomeActive()
            expect(!lock.covered && !lock.enabled, "Opt-in must start off")
            expect(lock.availability.kind == kind, "Use discovered modality")
            expect(kind.settingsTitle.contains(kind == .faceID ? "Face ID" : "Touch ID"), "One matching title")
            expect(!kind.settingsTitle.contains(kind == .faceID ? "Touch ID" : "Face ID"), "No wrong modality")
            await lock.changeEnabled(to: true)
            expect(lock.enabled && !lock.locked, "Successful setup enables without locking the current session")
            expect(defaults.bool(forKey: MetisAppLock.preferenceKey), "Preference persists")
            expect(auth.policies == [true], "Enrollment requires biometrics")
            lock.resignActive()
            expect(lock.covered && !lock.locked, "Inactive app is covered for snapshots")
            lock.becomeActive()
            expect(!lock.covered, "System-dialog inactivity must not cause a new lock")
            expect(auth.policies.count == 1, "No repeated authentication for a system dialog")
            lock.enterBackground()
            expect(lock.locked && lock.covered, "Background must lock and cover")
            lock.becomeActive()
            auth.next = .cancel
            await lock.unlockAutomaticallyIfNeeded()
            expect(lock.locked && lock.covered && !lock.authenticating, "Cancel keeps all content hidden")
            let attempts = auth.policies.count
            await lock.unlockAutomaticallyIfNeeded()
            expect(auth.policies.count == attempts, "Cancel must not start an authentication loop")
            auth.next = .accept
            await lock.unlock()
            expect(!lock.locked && !lock.covered, "Owner authentication unlocks")
            expect(auth.policies.last == false, "Unlock permits system passcode fallback")
            auth.next = .reject
            await lock.changeEnabled(to: false)
            expect(lock.enabled, "Failed disable keeps protection enabled")
            auth.next = .accept
            await lock.changeEnabled(to: false)
            expect(!lock.enabled && !defaults.bool(forKey: MetisAppLock.preferenceKey), "Disabling is authenticated")
            lock.enterBackground()
            expect(!lock.covered, "Disabled feature has no privacy window")
        }

        defaults.set(true, forKey: MetisAppLock.preferenceKey)
        let auth = AuthenticationFixture()
        let restored = MetisAppLock(defaults: defaults, authentication: auth)
        expect(restored.locked && restored.covered, "Relaunch starts covered before activation")
        restored.becomeActive()
        auth.next = .deferred
        let lateUnlock = Task { await restored.unlock() }
        while auth.continuation == nil { await Task.yield() }
        restored.enterBackground()
        restored.becomeActive()
        auth.complete()
        await lateUnlock.value
        expect(restored.locked && restored.enabled, "An old success cannot unlock a later foreground session")
        expect(!restored.authenticating, "Background cancels the pending state")

        let dialogAuth = AuthenticationFixture()
        dialogAuth.next = .deferred
        let dialogLock = MetisAppLock(defaults: defaults, authentication: dialogAuth)
        dialogLock.becomeActive()
        let systemDialog = Task { await dialogLock.unlock() }
        while dialogAuth.continuation == nil { await Task.yield() }
        dialogLock.resignActive()
        expect(dialogLock.authenticating && dialogLock.covered, "The system biometric dialog keeps privacy coverage without cancelling")
        dialogAuth.complete()
        await systemDialog.value
        expect(!dialogLock.locked && dialogLock.covered, "Accepted biometrics stay covered until the app is active again")
        dialogLock.becomeActive()
        await dialogLock.unlockAutomaticallyIfNeeded()
        expect(!dialogLock.covered, "Returning from the authentication dialog reveals only the unlocked app")
        expect(dialogAuth.policies.count == 1, "The authentication dialog must not cause a prompt loop")

        defaults.set(false, forKey: MetisAppLock.preferenceKey)
        let setupAuth = AuthenticationFixture()
        setupAuth.next = .deferred
        let setup = MetisAppLock(defaults: defaults, authentication: setupAuth)
        setup.becomeActive()
        let lateEnable = Task { await setup.changeEnabled(to: true) }
        while setupAuth.continuation == nil { await Task.yield() }
        setup.enterBackground()
        setupAuth.complete()
        await lateEnable.value
        expect(!setup.enabled && !defaults.bool(forKey: MetisAppLock.preferenceKey), "Background cancels setup without changing preference")

        defaults.set(true, forKey: MetisAppLock.preferenceKey)
        let disableAuth = AuthenticationFixture()
        let disabling = MetisAppLock(defaults: defaults, authentication: disableAuth)
        disabling.becomeActive()
        await disabling.unlock()
        disableAuth.next = .deferred
        let lateDisable = Task { await disabling.changeEnabled(to: false) }
        while disableAuth.continuation == nil { await Task.yield() }
        disabling.enterBackground()
        disableAuth.complete()
        await lateDisable.value
        expect(disabling.enabled && disabling.locked && defaults.bool(forKey: MetisAppLock.preferenceKey),
               "A stale disable result must never remove protection")

        defaults.set(false, forKey: MetisAppLock.preferenceKey)
        let unavailableAuth = AuthenticationFixture()
        unavailableAuth.capability = .init(kind: .unavailable, canUseBiometrics: false)
        let unavailable = MetisAppLock(defaults: defaults, authentication: unavailableAuth)
        unavailable.becomeActive()
        await unavailable.changeEnabled(to: true)
        expect(!unavailable.enabled && unavailableAuth.policies.isEmpty, "No fabricated biometrics on unsupported devices")

        defaults.set(true, forKey: MetisAppLock.preferenceKey)
        let recovery = MetisAppLock(defaults: defaults, authentication: unavailableAuth)
        recovery.becomeActive()
        await recovery.unlock()
        expect(!recovery.locked && unavailableAuth.policies.last == false, "Owner passcode can recover when biometrics disappear")
        await recovery.changeEnabled(to: false)
        expect(!recovery.enabled, "Owner can disable after biometric availability changes")

        print("App lock state smoke passed (\(checks) checks)")
    }
}
