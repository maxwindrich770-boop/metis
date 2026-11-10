import XCTest

final class MetisUITests: XCTestCase {
    private struct NoticeMetrics: Decodable {
        let count: Int
        let safeTop: Double
        let safeLeft: Double
        let safeRight: Double
        let minTop: Double?
        let minLeft: Double?
        let maxRight: Double?
        let width: Double
    }

    @MainActor
    func testNotificationsClearTheSafeAreaAndSettingsShowBuildVersion() throws {
        let app = launch(additionalArguments: [
            "-metis.app-lock-fixture", "unavailable", "-metis.app-lock-reset"
        ])
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        let fixture = web.links["Open notification safe-area fixture"]
        reveal(fixture, in: app)
        fixture.tap()
        let show = web.buttons["Show notification samples"]
        XCTAssertTrue(show.waitForExistence(timeout: 10), app.debugDescription)
        show.tap()
        try assertNoticesClearSafeArea(in: app, web: web, portrait: true)
        capture(app, named: "build14-real-sonner-synthetic-notices-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(in: app)
        try assertNoticesClearSafeArea(in: app, web: web, portrait: false)
        capture(app, named: "build14-real-sonner-synthetic-notices-landscape")
        web.buttons["Dismiss notification samples"].tap()
        XCUIDevice.shared.orientation = .portrait
        let fallback = app.buttons["metis.appControlsFallback"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 5))
        fallback.tap()
        let settings = app.buttons["metis.iPhoneSettings"]
        revealInControls(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["iPhone settings"].waitForExistence(timeout: 10))
        let version = app.descendants(matching: .any)["metis.appVersion"].firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        XCTAssertEqual(version.value as? String, "0.1.16 Developer Beta")
        capture(app, named: "build14-version-in-native-settings")
    }

    @MainActor
    private func assertNoticesClearSafeArea(in app: XCUIApplication, web: XCUIElement, portrait: Bool) throws {
        web.buttons["Measure notification position"].tap()
        let metrics = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Notice geometry: {")).firstMatch
        XCTAssertTrue(metrics.waitForExistence(timeout: 5), app.debugDescription)
        // Read after Sonner has mounted all cards and completed its transition.
        let mounted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let data = metrics.label.dropFirst("Notice geometry: ".count).data(using: .utf8),
                  let value = try? JSONDecoder().decode(NoticeMetrics.self, from: data) else { return false }
            return value.count == 3 && value.minTop != nil && (portrait ? value.width < 600 : value.width > 600)
        }, object: metrics)
        XCTAssertEqual(XCTWaiter.wait(for: [mounted], timeout: 8), .completed)
        let data = try XCTUnwrap(metrics.label.dropFirst("Notice geometry: ".count).data(using: .utf8))
        let value = try JSONDecoder().decode(NoticeMetrics.self, from: data)
        if portrait { XCTAssertGreaterThan(value.safeTop, 0) }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(value.minTop), value.safeTop + 8)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(value.minLeft), value.safeLeft)
        XCTAssertLessThanOrEqual(try XCTUnwrap(value.maxRight), value.width - value.safeRight)
    }

    @MainActor
    func testInsecureServerIsRejected() {
        let app = launch()
        signIn(app, server: "http://example.invalid")
        XCTAssertTrue(app.staticTexts["Enter the HTTPS address of a Metis server, without a path or credentials."]
            .waitForExistence(timeout: 5))
    }

    @MainActor
    func testLoginAndStreamFromFixture() async throws {
        let app = launch(nativeInterface: true)
        capture(app, named: "01-login-light")
        signIn(app, server: "http://localhost:43100")
        let chat = app.buttons["Fixture chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 15))
        let skipPasswordSave = app.sheets["Save Password?"].buttons["Not Now"]
        for _ in 0..<3 {
            guard skipPasswordSave.waitForExistence(timeout: 3) else { break }
            skipPasswordSave.tap()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: chat)
        let chatReady = await XCTWaiter.fulfillment(of: [ready], timeout: 10)
        XCTAssertEqual(chatReady, .completed, app.debugDescription)
        capture(app, named: "02-chat-list")
        chat.tap()
        let send = app.buttons["metis.send"]
        let composer = app.descendants(matching: .any)["metis.message"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10), app.debugDescription)
        composer.tap()
        composer.typeText("Hello from the iPhone simulator")
        XCTAssertEqual(composer.value as? String, "Hello from the iPhone simulator")
        app.navigationBars["Fixture chat"].buttons.firstMatch.tap()
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        chat.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Hello from the iPhone simulator")
        try await setFixtureSessionState("external-message")
        XCTAssertTrue(app.staticTexts["Message sent from another client 🌱"].waitForExistence(timeout: 10),
                      "An open chat must refresh changes from another client without navigation or a foreground switch")
        XCTAssertEqual(composer.value as? String, "Hello from the iPhone simulator",
                       "An external chat update must preserve the unsent draft")
        let transcript = app.collectionViews.firstMatch
        let earlier = app.buttons["Load earlier messages"]
        scrollToEarlier(earlier, in: transcript)
        let firstEarlierReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: earlier)
        let firstEarlierResult = await XCTWaiter.fulfillment(of: [firstEarlierReady], timeout: 15)
        XCTAssertEqual(firstEarlierResult, .completed, app.debugDescription)
        earlier.tap()
        scrollToEarlier(app.staticTexts["Nachricht 17 🌱"], in: transcript)
        scrollToEarlier(earlier, in: transcript)
        let secondEarlierReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: earlier)
        let secondEarlierResult = await XCTWaiter.fulfillment(of: [secondEarlierReady], timeout: 15)
        XCTAssertEqual(secondEarlierResult, .completed, app.debugDescription)
        earlier.tap()
        let firstMessage = app.staticTexts["Nachricht 1 🌱"]
        scrollToEarlier(firstMessage, in: transcript)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: send)
        let sendReady = await XCTWaiter.fulfillment(of: [enabled], timeout: 5)
        XCTAssertEqual(sendReady, .completed)
        XCTAssertTrue(send.isEnabled && send.isHittable)
        send.tap()
        XCTAssertTrue(app.staticTexts["metis.chatNotice"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(composer.value as? String, "Hello from the iPhone simulator")
        send.tap()
        let partial = app.staticTexts.matching(identifier: "metis.streamText")
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT label CONTAINS %@", "Live fixture", "Final response"))
            .firstMatch
        XCTAssertTrue(partial.waitForExistence(timeout: 15), app.debugDescription)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["Fixture chat"].waitForExistence(timeout: 5))
        let answer = "Live fixture streamed before the run completed. Final response 🌱"
        let streamedAnswer = app.staticTexts.matching(identifier: "metis.streamText")
            .matching(NSPredicate(format: "label == %@", answer)).firstMatch
        XCTAssertTrue(streamedAnswer.waitForExistence(timeout: 20), app.debugDescription)
        let savedAnswer = app.staticTexts.matching(NSPredicate(format: "label == %@ AND identifier != %@", answer, "metis.streamText"))
            .firstMatch
        XCTAssertTrue(savedAnswer.waitForExistence(timeout: 10),
                      "Visible labels: \(app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))")
        XCTAssertTrue(app.staticTexts["Hello from the iPhone simulator"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Hello from the iPhone simulator").count, 1)
        capture(app, named: "03-conversation-and-composer")
        scrollToEarlier(firstMessage, in: transcript)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-metis.native-interface"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Fixture chat"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        let account = app.descendants(matching: .any)["metis.accountName"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(account.value as? String, "metis-apple-fixture-alice")
        capture(app, named: "04-settings")
        app.tabBars.buttons["Chats"].tap()
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fixture chat"].waitForExistence(timeout: 5))

        app.terminate()
        try await setFixtureSessionState("offline")
        app.launch()
        let retry = app.buttons["Retry saved session"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Fixture chat"].exists)
        try await setFixtureSessionState("online")
        retry.tap()
        XCTAssertTrue(app.staticTexts["Fixture chat"].waitForExistence(timeout: 10))

        try await setFixtureSessionState("revoke")
        XCTAssertTrue(app.staticTexts["Your session is no longer valid. Sign in again."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Fixture chat"].exists)
        XCTAssertFalse(app.staticTexts["Fixture post-revocation signal"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["metis.signIn"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        XCTAssertFalse(app.staticTexts["Fixture chat"].exists)
    }

    @MainActor
    func testSignInRemainsUsableWithAccessibilityTextAndKeyboard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-metisServer", "",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let address = app.textFields["metis.server"]
        XCTAssertTrue(address.waitForExistence(timeout: 8))
        address.tap()
        address.typeText("https://example.invalid")
        let username = app.textFields["metis.username"]
        reveal(username, in: app)
        username.tap()
        username.typeText("metis-apple-fixture-alice")
        let password = app.secureTextFields["metis.password"]
        reveal(password, in: app)
        password.tap()
        password.typeText("apple-fixture-only")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let keyboardReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: keyboard)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardReady], timeout: 5), .completed,
                       "The software keyboard must become visible and interactive")
        capture(app, named: "05-login-accessibility-keyboard")
        let signIn = app.buttons["metis.signIn"]
        reveal(signIn, in: app)
        XCTAssertGreaterThanOrEqual(signIn.frame.height, 44)
        XCTAssertTrue(signIn.isEnabled)
        capture(app, named: "05b-login-accessibility-submit")
        XCUIDevice.shared.orientation = .landscapeLeft
        reveal(signIn, in: app)
        XCTAssertTrue(signIn.isHittable)
        capture(app, named: "06-login-landscape-accessibility")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testWatchAccessOptInSurvivesRestart() {
        let app = launch(nativeInterface: true)
        signIn(app, server: "http://localhost:43100")
        XCTAssertTrue(app.buttons["Fixture chat"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        let watchAccess = app.switches["Allow Apple Watch access"]
        XCTAssertTrue(watchAccess.waitForExistence(timeout: 5))
        reveal(watchAccess, in: app)
        XCTAssertEqual(watchAccess.value as? String, "0")
        capture(app, named: "07a-watch-access-before-opt-in")
        watchAccess.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: watchAccess)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, app.debugDescription)
        capture(app, named: "07b-watch-access-enabled")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-metis.native-interface"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Fixture chat"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(watchAccess.waitForExistence(timeout: 5))
        reveal(watchAccess, in: app)
        XCTAssertEqual(watchAccess.value as? String, "1")
        capture(app, named: "07-watch-access-opt-in-restored")
    }

    @MainActor
    func testAuthenticatedWebWorkspacePersistsChangesAndLogsOut() {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        web.buttons["Save a chat from the web fixture"].tap()
        let savedChat = web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Saved from web fixture")).firstMatch
        XCTAssertTrue(savedChat.waitForExistence(timeout: 10), app.debugDescription)

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let restoredWeb = authenticatedWebWorkspace(in: app)
        XCTAssertTrue(restoredWeb.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Saved from web fixture"))
            .firstMatch.waitForExistence(timeout: 10),
                      "A real cookie-protected web action must survive a full app restart")
        signOutFromWebFixture(in: app, web: restoredWeb)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["metis.signIn"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Retry saved session"].exists)
        XCTAssertFalse(app.webViews["metis.webWorkspace"].exists)
    }

    @MainActor
    func testSyntheticWebModelPreferencesSurviveRestartRotationAndAccountIsolation() throws {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        var web = openSyntheticModelPreferenceFixture(in: app)
        web.buttons["Store synthetic model preferences"].tap()
        let written = try syntheticModelPreferences(in: web).current
        XCTAssertNotNil(written.model)
        XCTAssertNotNil(written.parameters)
        XCTAssertNotNil(written.unrelated, "The probe also writes a draft outside the native allowlist")
        web = restartIntoSyntheticModelPreferences(in: app)
        try assertSyntheticPreferences(in: web, match: written)
        web.links["Return to authenticated web workspace fixture"].tap()
        web = authenticatedWebWorkspace(in: app)
        let rotate = web.buttons["Rotate the web session"]
        reveal(rotate, in: app)
        rotate.tap()
        XCTAssertTrue(web.staticTexts["Session rotated in web fixture"].waitForExistence(timeout: 15))
        web = restartIntoSyntheticModelPreferences(in: app)
        try assertSyntheticPreferences(in: web, match: written)
        web.links["Return to authenticated web workspace fixture"].tap()
        signOutFromWebFixture(in: app, web: authenticatedWebWorkspace(in: app))
        for username in ["metis-apple-fixture-bob", "metis-apple-fixture-alice"] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-metisServer", ""]
            app.launch()
            signIn(app, server: "http://localhost:43100", username: username)
            web = openSyntheticModelPreferenceFixture(in: app)
            try assertSyntheticPreferencesAreEmpty(in: web)
            web.links["Return to authenticated web workspace fixture"].tap()
            signOutFromWebFixture(in: app, web: authenticatedWebWorkspace(in: app))
        }
    }

    @MainActor
    func testSyntheticWebModelPreferenceRemovalAndClearSurviveRestart() throws {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        var web = openSyntheticModelPreferenceFixture(in: app)
        web.buttons["Store synthetic model preferences"].tap()
        let written = try syntheticModelPreferences(in: web).current
        web.buttons["Remove synthetic model selection"].tap()
        XCTAssertNil(try syntheticModelPreferences(in: web).current.model)
        web = restartIntoSyntheticModelPreferences(in: app)
        let removed = try syntheticModelPreferences(in: web)
        XCTAssertNil(removed.atScriptStart.model)
        XCTAssertNil(removed.current.model)
        XCTAssertEqual(removed.atScriptStart.parameters, written.parameters)
        XCTAssertNil(removed.current.unrelated)
        web.buttons["Clear synthetic local storage"].tap()
        web = restartIntoSyntheticModelPreferences(in: app)
        try assertSyntheticPreferencesAreEmpty(in: web)
        web.links["Return to authenticated web workspace fixture"].tap()
        signOutFromWebFixture(in: app, web: authenticatedWebWorkspace(in: app))
    }

    @MainActor
    func testAccountDetailsUseCanonicalProfileWhenMobileSessionEndpointIsUnavailable() async throws {
        try await setFixtureSessionState("profile-fallback")
        addTeardownBlock { try await self.setFixtureSessionState("profile-mobile") }
        let app = launch(nativeInterface: true)
        signIn(app, server: "http://localhost:43100")
        XCTAssertTrue(app.buttons["Fixture chat"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        let account = app.descendants(matching: .any)["metis.accountName"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(account.value as? String, "metis-apple-fixture-alice",
                       "A missing optional mobile endpoint must use the authenticated canonical profile")
        let (data, response) = try await URLSession.shared.data(from: fixtureControlURL())
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        struct ProfileControl: Decodable { let fallbackProfileReads: Int }
        XCTAssertGreaterThan(try JSONDecoder().decode(ProfileControl.self, from: data).fallbackProfileReads, 0)
        capture(app, named: "native-account-canonical-profile-with-mobile-endpoint-unavailable")
    }

    @MainActor
    func testUnavailablePushExplainsRestrictionWithoutSendingUserToSettings() {
        let app = launch(nativeInterface: true)
        signIn(app, server: "http://localhost:43100")
        XCTAssertTrue(app.buttons["Fixture chat"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        let push = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Push alerts")).firstMatch
        reveal(push, in: app)
        push.tap()
        XCTAssertTrue(app.navigationBars["Push alerts"].waitForExistence(timeout: 5))
        let explanation = app.descendants(matching: .any)["metis.pushAvailability"].firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(explanation.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let enable = app.buttons["metis.changePush"]
        reveal(enable, in: app)
        XCTAssertFalse(enable.isEnabled, "Unavailable build or backend push support must keep registration disabled")
        XCTAssertFalse(app.buttons["Open iPhone Settings"].isHittable,
                       "A build or server restriction cannot be repaired in iPhone notification settings")
        // The Personal Team variant uses the same flow and must explain the
        // missing signing entitlement explicitly when that build marker is set.
        if explanation.label.contains("test build") {
            XCTAssertTrue(explanation.label.contains("push-enabled provisioning profile"))
            XCTAssertTrue(explanation.label.contains("iPhone Settings cannot enable push"))
        }
        capture(app, named: "push-unavailable-build-or-backend-explanation")
    }

    @MainActor
    func testSameOriginSubframeCannotPersistModelPreferences() throws {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app)
        let showProbe = web.buttons["Show same-origin subframe probe"]
        revealSyntheticControl(showProbe, in: web)
        showProbe.tap()
        let send = web.buttons["Post model preferences from same-origin subframe"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        revealSyntheticControl(send, in: web)
        send.tap()
        XCTAssertTrue(web.staticTexts["Same-origin subframe posted model preferences"].waitForExistence(timeout: 5),
                      "The real same-origin subframe must post a valid-shaped payload to the native handler")
        let restored = restartIntoSyntheticModelPreferences(in: app)
        try assertSyntheticPreferencesAreEmpty(in: restored)
        restored.links["Return to authenticated web workspace fixture"].tap()
        signOutFromWebFixture(in: app, web: authenticatedWebWorkspace(in: app))
    }

    @MainActor
    func testSavedWebSessionShowsNeutralLaunchUntilServerVerificationFinishes() async throws {
        try await resetFixtureSessionVerification()
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        _ = authenticatedWebWorkspace(in: app)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        try await setFixtureSessionState("hold-session")
        app.launch()
        try await assertNeutralSavedSessionVerification(in: app)
        capture(app, named: "saved-session-neutral-launch-before-server-verification")

        try await setFixtureSessionState("release-session")
        _ = authenticatedWebWorkspace(in: app)
        XCTAssertFalse(app.descendants(matching: .any)["metis.sessionRestoring"].firstMatch.exists)
        XCTAssertFalse(app.buttons["metis.signIn"].exists)

        // A failed network verification keeps the saved account behind Retry.
        // The login form must remain absent until the user chooses another account.
        app.terminate()
        try await setFixtureSessionState("offline")
        app.launch()
        let retry = app.buttons["Retry saved session"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["metis.signIn"].exists)
        XCTAssertFalse(app.secureTextFields["metis.password"].exists)
        XCTAssertFalse(app.webViews["metis.webWorkspace"].exists)
        try await setFixtureSessionState("online")
        retry.tap()
        let recoveredWeb = authenticatedWebWorkspace(in: app)
        signOutFromWebFixture(in: app, web: recoveredWeb)
    }

    @MainActor
    func testRevokedSavedWebSessionShowsLoginOnlyAfterServerVerification() async throws {
        try await resetFixtureSessionVerification()
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        _ = authenticatedWebWorkspace(in: app)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        try await setFixtureSessionState("hold-session")
        try await setFixtureSessionState("revoke")
        app.launch()
        try await assertNeutralSavedSessionVerification(in: app)

        try await setFixtureSessionState("release-session")
        XCTAssertTrue(app.buttons["metis.signIn"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.textFields["metis.server"].exists)
        XCTAssertFalse(app.webViews["metis.webWorkspace"].exists,
                       "A locally saved cookie must not bypass the server's revocation check")
        XCTAssertFalse(app.buttons["Retry saved session"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["metis.sessionRestoring"].firstMatch.exists)
        capture(app, named: "revoked-saved-session-sign-in-after-verification")
    }

    @MainActor
    func testWebSessionRotationSurvivesRestart() {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        let rotate = web.buttons["Rotate the web session"]
        reveal(rotate, in: app)
        rotate.tap()
        XCTAssertTrue(web.staticTexts["Session rotated in web fixture"].waitForExistence(timeout: 15),
                      "The real auth route must replace the HttpOnly cookie and revoke the original session")

        // Re-entering the foreground also checks the native client's adopted
        // cookie before terminating; the old cookie is already invalid.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(web.staticTexts["HttpOnly cookie verified"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let restoredWeb = authenticatedWebWorkspace(in: app)
        XCTAssertFalse(app.buttons["Retry saved session"].exists)
        signOutFromWebFixture(in: app, web: restoredWeb)
    }

    @MainActor
    func testWebDownloadAndExternalWindowKeepTheAuthenticatedWorkspace() {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        let download = web.links["Download the public web fixture"]
        reveal(download, in: app)
        download.tap()
        let share = app.descendants(matching: .any)["ActivityListView"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 15), app.debugDescription)
        let filename = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "metis-web-fixture")).firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 8),
                      "The native share controller must receive the downloaded public fixture file")
        let closeShare = app.buttons["Close"].firstMatch
        XCTAssertTrue(closeShare.waitForExistence(timeout: 5), app.debugDescription)
        closeShare.tap()
        let shareClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: share)
        XCTAssertEqual(XCTWaiter.wait(for: [shareClosed], timeout: 8), .completed)

        let external = web.links["Open the external fixture in a new window"]
        reveal(external, in: app)
        external.tap()
        let closeBrowser = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Close")).firstMatch
        XCTAssertTrue(closeBrowser.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["External fixture opened without a Metis cookie"]
            .waitForExistence(timeout: 15),
                      "A user-activated target=_blank link must open externally without the Metis cookie")
        closeBrowser.tap()
        let browserClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: closeBrowser)
        XCTAssertEqual(XCTWaiter.wait(for: [browserClosed], timeout: 8), .completed)
        XCTAssertTrue(web.waitForExistence(timeout: 5))
        XCTAssertTrue(web.staticTexts["HttpOnly cookie verified"].exists)
        signOutFromWebFixture(in: app, web: web)
    }

    @MainActor
    func testScriptedWebSetupWindowRequiresNativeConfirmation() {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        let getAPIKey = web.buttons["Get an API key from the web fixture"]
        reveal(getAPIKey, in: app)
        getAPIKey.tap()
        let openInBrowser = app.buttons["Open in browser"].firstMatch
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(openInBrowser.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(cancel.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Close")).firstMatch.exists,
                       "A scripted setup popup must wait for native confirmation")
        cancel.tap()
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: openInBrowser)
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 8), .completed)
        XCTAssertTrue(web.exists)
        XCTAssertFalse(app.staticTexts["External fixture opened without a Metis cookie"].exists)

        getAPIKey.tap()
        XCTAssertTrue(openInBrowser.waitForExistence(timeout: 10), app.debugDescription)
        openInBrowser.tap()
        let closeBrowser = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Close")).firstMatch
        XCTAssertTrue(closeBrowser.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["External fixture opened without a Metis cookie"]
            .waitForExistence(timeout: 15),
                      "Approving the setup popup must open the provider page without the Metis cookie")
        closeBrowser.tap()
        let browserClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: closeBrowser)
        XCTAssertEqual(XCTWaiter.wait(for: [browserClosed], timeout: 8), .completed)
        XCTAssertTrue(web.waitForExistence(timeout: 5))
        signOutFromWebFixture(in: app, web: web)
    }

    @MainActor
    func testSyntheticSidebarPaintsFromWindowTopAndInsetsControlsBelowStatusBar() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app)
        web.buttons["Open sidebar"].tap()
        XCTAssertTrue(web.buttons["Close sidebar"].waitForExistence(timeout: 5))
        let metrics = try freshViewportMetrics(in: app, web: web, measureButton: "Measure sidebar geometry")
        let geometry = try XCTUnwrap(observedWindowGeometry(in: app))
        // WebKit's env() reports the OS safe area even when this runtime does
        // not expose the status bar in the app's accessibility snapshot.
        let safeContentTop = geometry.web.minY + CGFloat(metrics.safeAreaTop)
        XCTAssertGreaterThan(metrics.safeAreaTop, 0)
        if let nativeStatusBarBottom = geometry.statusBarBottom {
            XCTAssertGreaterThanOrEqual(safeContentTop, nativeStatusBarBottom - 1)
        }
        XCTAssertEqual(geometry.window.minY, 0, accuracy: 1)
        XCTAssertEqual(geometry.web.minY, geometry.window.minY, accuracy: 1)
        XCTAssertEqual(geometry.web.minY + CGFloat(metrics.sidebarTop), geometry.window.minY, accuracy: 1,
                       "The sidebar material must paint behind the status bar from the screen's top edge")
        XCTAssertEqual(metrics.sidebarHeight, metrics.height, accuracy: 2)
        XCTAssertEqual(metrics.shellHeight, metrics.height, accuracy: 2,
                       "A safe top inset must not increase the root's border-box height")
        XCTAssertGreaterThanOrEqual(CGFloat(metrics.sidebarBrandTop) + geometry.web.minY, safeContentTop - 1)
        XCTAssertGreaterThanOrEqual(CGFloat(metrics.sidebarCloseTop) + geometry.web.minY, safeContentTop - 1)
        XCTAssertGreaterThanOrEqual(web.links["Metis"].frame.minY, safeContentTop - 1)
        XCTAssertGreaterThanOrEqual(web.buttons["Close sidebar"].frame.minY, safeContentTop - 1)
        XCTAssertTrue(web.links["Metis"].isHittable)
        XCTAssertTrue(web.buttons["Close sidebar"].isHittable)
        capture(app, named: "synthetic-fixture-not-design-sidebar-full-height-safe-controls")
    }

    @MainActor
    func testSyntheticKeyboardTransitionKeepsHeaderAndTranscriptSteady() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app)
        let headerControl = web.buttons["Open sidebar"]
        let before = headerControl.frame
        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        composer.tap()
        let inputVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let geometry = self.observedWindowGeometry(in: app) else { return false }
            return geometry.availableBottom < geometry.window.maxY - 1
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [inputVisible], timeout: 5), .completed,
                       "A real onscreen input surface, including the system accessory, must resize the viewport")
        let prefix = "Synthetic keyboard transition: "
        let report = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        let data = try XCTUnwrap(String(report.label.dropFirst(prefix.count)).data(using: .utf8))
        let transition = try JSONDecoder().decode(SyntheticKeyboardTransition.self, from: data)
        XCTAssertGreaterThanOrEqual(transition.frames, 12)
        XCTAssertGreaterThanOrEqual(transition.duration, 700)
        XCTAssertGreaterThan(transition.dockOffsetAttempts, 1,
                             "The probe must repeatedly reproduce the web's transient keyboard-offset writes")
        XCTAssertLessThanOrEqual(transition.headerTopRange, 2)
        XCTAssertLessThanOrEqual(transition.headerBottomRange, 2)
        XCTAssertLessThanOrEqual(transition.transcriptScrollRange, 2)
        XCTAssertLessThanOrEqual(transition.documentScrollRange, 2)
        XCTAssertLessThanOrEqual(transition.maxShellHeightError, 2)
        XCTAssertEqual(headerControl.frame.minY, before.minY, accuracy: 2)
        XCTAssertEqual(headerControl.frame.maxY, before.maxY, accuracy: 2)
        let metrics = try freshViewportMetrics(in: app, web: web)
        XCTAssertEqual(metrics.composerDockBottom, 0, accuracy: 1,
                       "The native-sized viewport must not subtract a second web keyboard offset")
        try assertSyntheticViewportGeometry(in: app, web: web)
        capture(app, named: "synthetic-fixture-not-design-keyboard-transition-steady-header")
        let attachment = XCTAttachment(string: report.label)
        attachment.name = "synthetic-keyboard-transition-frame-ranges"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSyntheticKeyboardDismissalKeepsChatSteadyAcrossWebAndSystemDismissal() throws {
        try assertSyntheticKeyboardDismissal(centeredEmptyState: false)
    }

    @MainActor
    func testSyntheticKeyboardDismissalKeepsCenteredEmptyStateSteady() throws {
        try assertSyntheticKeyboardDismissal(centeredEmptyState: true)
    }

    @MainActor
    func testSyntheticEmptyComposerFlowKeepsGreetingStableThroughKeyboardCycles() throws {
        try assertSyntheticKeyboardDismissal(centeredEmptyState: false, productionEmptyState: true)
    }

    @MainActor
    func testSyntheticTallComposerKeepsTranscriptSteadyAcrossKeyboardTransitions() throws {
        try assertSyntheticKeyboardDismissal(centeredEmptyState: false, tallComposer: true)
    }

    @MainActor
    func testSyntheticEmptyComposerKeepsGreetingClearWithLargeInputOcclusion() throws {
        try assertSyntheticKeyboardDismissal(centeredEmptyState: false, productionEmptyState: true,
                                              largeInputOcclusion: true)
    }

    @MainActor
    private func assertSyntheticKeyboardDismissal(centeredEmptyState: Bool, productionEmptyState: Bool = false,
                                                  tallComposer: Bool = false, largeInputOcclusion: Bool = false) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(additionalArguments: largeInputOcclusion ? ["-metis.synthetic-input-occlusion"] : [])
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app, centeredEmptyState: centeredEmptyState,
                                               productionEmptyState: productionEmptyState, tallComposer: tallComposer,
                                               largeEmptyComposer: largeInputOcclusion)
        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        let header = web.buttons["Open sidebar"]
        let closedHeader = header.frame
        var previousRevision = 0
        var previousOpeningRevision = 0
        let greeting = web.staticTexts[productionEmptyState
            ? "Synthetic empty chat greeting" : "Synthetic centered empty state"]
        let closedGreetingY = centeredEmptyState || productionEmptyState ? greeting.frame.midY : nil
        let closedMetrics = try viewportMetrics(in: web)
        let closedGreetingGap = try (productionEmptyState ? XCTUnwrap(closedMetrics.greetingComposerGap) : nil)
        if let closedGreetingGap { XCTAssertGreaterThan(closedGreetingGap, 0) }
        let expectedDraft = tallComposer
            ? "Tall composer line one\nLine two stays put\nLine three stays put\nLine four stays put"
            : "Draft stays through repeated keyboard dismissal"
        let anchor = web.staticTexts["Synthetic transcript anchor row"]
        if tallComposer { try scrollSyntheticTranscriptToBottom(in: app, web: web) }
        let closedAnchorY = tallComposer ? anchor.frame.minY : nil
        let closedDockHeight = try (tallComposer ? viewportMetrics(in: web).composerDockHeight : nil)
        if tallComposer {
            let metrics = try viewportMetrics(in: web)
            XCTAssertTrue(metrics.tallComposer)
            XCTAssertGreaterThan(try XCTUnwrap(metrics.transcriptPaddingBottom), 172,
                                 "The real composerHeight + 40 padding branch must exceed the minimum threshold")
        }

        for (index, kind) in ["blur", "system-done", "blur"].enumerated() {
            composer.tap()
            if index == 0 { composer.typeText(expectedDraft) }
            let inputVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let geometry = self.observedWindowGeometry(in: app) else { return false }
                return geometry.availableBottom < geometry.window.maxY - 1
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [inputVisible], timeout: 5), .completed,
                           "Every cycle must show a real system input surface before dismissal")
            XCTAssertEqual(composer.value as? String, expectedDraft)
            if largeInputOcclusion {
                let occlusion = app.descendants(matching: .any)["metis.syntheticInputOcclusion"].firstMatch
                XCTAssertTrue(occlusion.waitForExistence(timeout: 5), "This is an explicit synthetic occlusion panel, not a software-keyboard visibility claim")
                let geometry = try XCTUnwrap(observedWindowGeometry(in: app))
                XCTAssertGreaterThanOrEqual(geometry.window.maxY - geometry.availableBottom, 300,
                                             "The regression must exercise a full-keyboard-sized reduction, not only the system accessory")
                XCTAssertEqual(geometry.web.maxY, geometry.availableBottom, accuracy: 2)
                let focusedMetrics = try viewportMetrics(in: web)
                XCTAssertGreaterThan(closedMetrics.composerTop - focusedMetrics.composerTop,
                                     try XCTUnwrap(closedGreetingGap) + 2,
                                     "The editor must move far enough that the old dock-only shift would cross the fixed greeting")
            }
            let openingPrefix = "Synthetic keyboard transition: "
            let openingReport = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", openingPrefix)).firstMatch
            XCTAssertTrue(openingReport.waitForExistence(timeout: 5))
            let openingSampled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let data = String(openingReport.label.dropFirst(openingPrefix.count)).data(using: .utf8),
                      let measured = try? JSONDecoder().decode(SyntheticKeyboardTransition.self, from: data)
                else { return false }
                return measured.revision > previousOpeningRevision
            }, object: openingReport)
            XCTAssertEqual(XCTWaiter.wait(for: [openingSampled], timeout: 5), .completed)
            let openingData = try XCTUnwrap(String(openingReport.label.dropFirst(openingPrefix.count)).data(using: .utf8))
            let opening = try JSONDecoder().decode(SyntheticKeyboardTransition.self, from: openingData)
            previousOpeningRevision = opening.revision
            XCTAssertLessThanOrEqual(opening.headerTopRange, 2)
            XCTAssertLessThanOrEqual(opening.transcriptScrollRange, 2)
            XCTAssertLessThanOrEqual(opening.documentScrollRange, 2)
            XCTAssertLessThanOrEqual(opening.maxShellHeightError, 2)
            if let closedGreetingGap {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(opening.minGreetingComposerGap), closedGreetingGap - 2,
                                             "The editor must stay below the greeting throughout input presentation")
                XCTAssertLessThanOrEqual(try XCTUnwrap(opening.greetingComposerGapRange), 2)
                XCTAssertLessThanOrEqual(try XCTUnwrap(opening.maxGreetingComposerShiftError), 2,
                                        "The greeting and editor must move by the same amount")
                XCTAssertGreaterThanOrEqual(composer.frame.minY, greeting.frame.maxY - 1)
            } else if let closedGreetingY {
                XCTAssertLessThanOrEqual(try XCTUnwrap(opening.emptyCenterYRange), 2,
                                        "The separate absolute centered-background fixture remains stationary")
                XCTAssertEqual(greeting.frame.midY, closedGreetingY, accuracy: 2)
            }
            if let closedAnchorY, let closedDockHeight {
                XCTAssertLessThanOrEqual(try XCTUnwrap(opening.transcriptAnchorTopRange), 2,
                                        "The measured composer must not repin the visible transcript on opening")
                XCTAssertLessThanOrEqual(opening.dockHeightRange, 2)
                XCTAssertEqual(anchor.frame.minY, closedAnchorY, accuracy: 2)
                XCTAssertEqual(try viewportMetrics(in: web).composerDockHeight, closedDockHeight, accuracy: 2)
            }
            if productionEmptyState {
                let metrics = try viewportMetrics(in: web)
                XCTAssertTrue(metrics.productionEmptyState)
                XCTAssertTrue(metrics.composerServerFixed,
                              "The fixture must reproduce the server's focused fixed-position class")
                XCTAssertEqual(metrics.composerPosition, "relative",
                               "Native app styling must preserve the empty dock's normal-flow footprint")
                try assertSyntheticEmptyComposerClearance(in: app, web: web)
            }
            let openingAttachment = XCTAttachment(string: openingReport.label)
            openingAttachment.name = "synthetic-keyboard-opening-\(index)-\(kind)"
            openingAttachment.lifetime = .keepAlways
            add(openingAttachment)
            capture(app, named: "synthetic-fixture-keyboard-cycle-\(index)-before-\(kind)")

            if kind == "system-done" {
                let arm = web.buttons["Arm native Done dismissal probe"]
                XCTAssertTrue(arm.isHittable, app.debugDescription)
                arm.tap()
                let done = app.toolbars.buttons["Done"].firstMatch
                XCTAssertTrue(done.waitForExistence(timeout: 5),
                              "This cycle requires the real system input accessory's Done button")
                XCTAssertTrue(done.isHittable, app.debugDescription)
                done.tap()
            } else {
                let dismiss = web.buttons["Blur composer and dismiss keyboard"]
                XCTAssertTrue(dismiss.isHittable, app.debugDescription)
                dismiss.tap()
            }
            let prefix = "Synthetic keyboard dismissal: "
            let report = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(report.waitForExistence(timeout: 5))
            let sampled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let data = String(report.label.dropFirst(prefix.count)).data(using: .utf8),
                      let measured = try? JSONDecoder().decode(SyntheticKeyboardDismissal.self, from: data)
                else { return false }
                return measured.revision > previousRevision && measured.kind == kind
            }, object: report)
            XCTAssertEqual(XCTWaiter.wait(for: [sampled], timeout: 5), .completed)
            let data = try XCTUnwrap(String(report.label.dropFirst(prefix.count)).data(using: .utf8))
            let transition = try JSONDecoder().decode(SyntheticKeyboardDismissal.self, from: data)
            previousRevision = transition.revision

            // DOM ranges complement the native layer/video check; they do not
            // substitute for it, because WebKit can animate its entire surface.
            XCTAssertGreaterThanOrEqual(transition.frames, 18)
            XCTAssertGreaterThanOrEqual(transition.duration, 900)
            XCTAssertGreaterThan(transition.offsetWrites, 1)
            XCTAssertLessThanOrEqual(transition.headerTopRange, 2)
            XCTAssertLessThanOrEqual(transition.headerBottomRange, 2)
            XCTAssertLessThanOrEqual(transition.transcriptScrollRange, 2)
            XCTAssertLessThanOrEqual(transition.documentScrollRange, 2)
            XCTAssertLessThanOrEqual(transition.composerCenterXRange, 2)
            XCTAssertLessThanOrEqual(transition.viewportScaleRange, 0.001)
            XCTAssertLessThanOrEqual(transition.maxDockBottom, 1,
                                    "Late closing-offset writes must not lift the dock after blur")
            if let closedGreetingGap {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(transition.minGreetingComposerGap), closedGreetingGap - 2,
                                             "The editor must not pass in front of the greeting while input closes")
                XCTAssertLessThanOrEqual(try XCTUnwrap(transition.greetingComposerGapRange), 2)
                XCTAssertLessThanOrEqual(try XCTUnwrap(transition.maxGreetingComposerShiftError), 2)
            } else if centeredEmptyState {
                XCTAssertLessThanOrEqual(try XCTUnwrap(transition.emptyCenterYRange), 2,
                                        "The separate absolute centered-background fixture remains stationary")
            }
            if let closedAnchorY, let closedDockHeight {
                XCTAssertLessThanOrEqual(try XCTUnwrap(transition.transcriptAnchorTopRange), 2,
                                        "Closing input must preserve the visible row despite the real ResizeObserver padding path")
                XCTAssertLessThanOrEqual(transition.dockHeightRange, 2)
                XCTAssertEqual(anchor.frame.minY, closedAnchorY, accuracy: 2)
                let metrics = try viewportMetrics(in: web)
                XCTAssertEqual(metrics.composerDockHeight, closedDockHeight, accuracy: 2)
                XCTAssertLessThanOrEqual(metrics.transcriptBottomDistance, 2)
            }
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let geometry = self.observedWindowGeometry(in: app) else { return false }
                return geometry.availableBottom >= geometry.window.maxY - 1
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed,
                           "The input surface must actually leave the window after dismissal")
            XCTAssertEqual(header.frame.minY, closedHeader.minY, accuracy: 2)
            XCTAssertEqual(composer.value as? String, expectedDraft)
            if let closedGreetingY { XCTAssertEqual(greeting.frame.midY, closedGreetingY, accuracy: 2) }
            if productionEmptyState {
                let metrics = try viewportMetrics(in: web)
                XCTAssertEqual(metrics.composerPosition, "relative")
                XCTAssertFalse(metrics.composerServerFixed,
                               "Every new cycle performs a real blur; readonly-retained focus is covered separately")
                try assertSyntheticEmptyComposerClearance(in: app, web: web)
            }
            let attachment = XCTAttachment(string: report.label)
            attachment.name = "synthetic-keyboard-dismissal-\(index)-\(kind)"
            attachment.lifetime = .keepAlways
            add(attachment)
            capture(app, named: "synthetic-fixture-keyboard-cycle-\(index)-after-\(kind)")
        }
    }

    @MainActor
    func testSyntheticViewportFixtureFillsWindowWithFocusedAndDismissedKeyboard() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app)
        try assertSyntheticViewportGeometry(in: app, web: web)
        capture(app, named: "synthetic-fixture-not-design-viewport-portrait")
        try assertSyntheticWorkspaceClearance(in: app, web: web)

        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Retained focus viewport draft")
        XCTAssertTrue(web.staticTexts["Composer retains focus"].waitForExistence(timeout: 5),
                      "The probe must focus the actual web textarea")
        // A focused DOM field does not prove that a software keyboard is onscreen.
        // Geometry uses its actual intersection with the app window in every state.
        try assertSyntheticViewportGeometry(in: app, web: web)
        capture(app, named: "synthetic-fixture-not-design-viewport-focused-observed-keyboard")

        web.buttons["Dismiss keyboard, keep composer focus"].tap()
        let retainedFocus = web.staticTexts["Composer retains focus after keyboard dismissal"]
        if !retainedFocus.waitForExistence(timeout: 5) {
            captureFixtureDiagnostics(in: app, web: web, named: "synthetic-fixture-retained-focus-failure")
        }
        XCTAssertTrue(retainedFocus.exists, app.debugDescription)
        let keyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.observedWindowGeometry(in: app)?.keyboard.isEmpty == true
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 8), .completed,
                       "The fixture must dismiss the software keyboard without blurring its web field")
        XCTAssertEqual(composer.value as? String, "Retained focus viewport draft")
        try assertSyntheticViewportGeometry(in: app, web: web)
        capture(app, named: "synthetic-fixture-not-design-viewport-dismissed-retained-focus")

        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(in: app)
        XCTAssertTrue(web.staticTexts["Composer retains focus after keyboard dismissal"].exists)
        XCTAssertEqual(composer.value as? String, "Retained focus viewport draft")
        try assertSyntheticViewportGeometry(in: app, web: web)
        capture(app, named: "synthetic-fixture-not-design-viewport-landscape-retained-focus")
        try assertSyntheticWorkspaceClearance(in: app, web: web)
    }

    @MainActor
    func testSyntheticTextareaComposerKeepsScaleAndCenterWhenFocused() throws {
        try assertSyntheticComposerPreservesScaleAndCenter(contentEditable: false)
    }

    @MainActor
    func testSyntheticContenteditableComposerKeepsScaleAndCenterWhenFocused() throws {
        try assertSyntheticComposerPreservesScaleAndCenter(contentEditable: true)
    }

    @MainActor
    private func assertSyntheticComposerPreservesScaleAndCenter(contentEditable: Bool) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app, contentEditableComposer: contentEditable)
        let initial = try freshViewportMetrics(in: app, web: web)
        XCTAssertEqual(initial.composerContentEditable, contentEditable,
                       "Exercise the requested real editable element at the production-like 15px baseline")
        XCTAssertGreaterThanOrEqual(initial.composerFontSize, 16,
                                    "The app must raise the synthetic 15px baseline above iOS's focus-zoom threshold")
        XCTAssertEqual(initial.composerCenterX, initial.width / 2, accuracy: 2)

        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        composer.tap()
        composer.typeText("Focus must preserve the centered composer")
        XCTAssertTrue(web.staticTexts["Composer retains focus"].waitForExistence(timeout: 5))
        let focused = try freshViewportMetrics(in: app, web: web)
        XCTAssertTrue(focused.focused)
        XCTAssertGreaterThanOrEqual(focused.composerFontSize, 16)
        XCTAssertEqual(focused.viewportScale, initial.viewportScale, accuracy: 0.01,
                       "A trusted focus must not trigger WebKit autozoom; no user zoom gesture occurs here")
        XCTAssertEqual(focused.viewportOffsetLeft, initial.viewportOffsetLeft, accuracy: 2,
                       "Focusing the composer must not pan the page sideways")
        XCTAssertEqual(focused.composerCenterX, focused.width / 2, accuracy: 2)
        capture(app, named: "synthetic-fixture-not-design-\(contentEditable ? "contenteditable" : "textarea")-focused-scale-and-center")
    }

    @MainActor
    func testSyntheticViewportStillAllowsDeliberatePinchZoom() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app)
        let initial = try freshViewportMetrics(in: app, web: web)
        web.pinch(withScale: 1.3, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let metrics = try? self.viewportMetrics(in: web) else { return false }
            return metrics.viewportScale > initial.viewportScale + 0.05
        }, object: web)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed,
                       "Preventing focus autozoom must preserve deliberate user pinch zoom")
        capture(app, named: "synthetic-fixture-not-design-deliberate-pinch-zoom")
    }

    @MainActor
    func testSidebarIPhoneControlsPreserveWebDraftAndOpenSettingsWithAccessibilityText() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(additionalArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app)
        let pageInstance = syntheticPageInstance(in: web).label
        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        composer.tap()
        composer.typeText("Draft survives native controls and settings")
        web.buttons["Dismiss keyboard, keep composer focus"].tap()
        let retainedFocus = web.staticTexts["Composer retains focus after keyboard dismissal"]
        if !retainedFocus.waitForExistence(timeout: 5) {
            captureFixtureDiagnostics(in: app, web: web, named: "synthetic-fixture-retained-focus-failure")
        }
        XCTAssertTrue(retainedFocus.exists, app.debugDescription)

        openIPhoneControls(in: app, web: web)
        assertNativeControlsHaveMinimumHitAreas(in: app)
        capture(app, named: "synthetic-fixture-not-design-controls-accessibility-portrait")
        closeIPhoneControls(in: app)
        XCTAssertEqual(syntheticPageInstance(in: web).label, pageInstance,
                       "Closing native controls must retain the existing web page")
        XCTAssertEqual(composer.value as? String, "Draft survives native controls and settings")

        openIPhoneControls(in: app, web: web)
        let settings = app.buttons["metis.iPhoneSettings"]
        revealInControls(settings, in: app)
        settings.tap()
        let settingsNavigation = app.navigationBars["iPhone settings"]
        XCTAssertTrue(settingsNavigation.waitForExistence(timeout: 10),
                      "The controls sheet must finish dismissing before native settings opens")
        XCTAssertTrue(app.descendants(matching: .any)["metis.accountName"].firstMatch.waitForExistence(timeout: 5))
        capture(app, named: "synthetic-fixture-not-design-native-settings-accessibility")
        let done = app.buttons["metis.iPhoneSettingsDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(done.isHittable, app.debugDescription)
        done.tap()
        let settingsClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: settingsNavigation)
        XCTAssertEqual(XCTWaiter.wait(for: [settingsClosed], timeout: 8), .completed)
        XCTAssertEqual(syntheticPageInstance(in: web).label, pageInstance)
        XCTAssertEqual(composer.value as? String, "Draft survives native controls and settings")

        web.buttons["Close sidebar"].tap()
        let checkSession = web.buttons["Check viewport fixture session"]
        revealSyntheticControl(checkSession, in: web)
        checkSession.tap()
        XCTAssertTrue(web.staticTexts["Authenticated viewport fixture session"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["metis.signIn"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(in: app)
        openIPhoneControls(in: app, web: web)
        assertNativeControlsHaveMinimumHitAreas(in: app)
        capture(app, named: "synthetic-fixture-not-design-controls-accessibility-landscape")
        closeIPhoneControls(in: app)
        XCTAssertEqual(syntheticPageInstance(in: web).label, pageInstance)
        XCTAssertEqual(composer.value as? String, "Draft survives native controls and settings")
    }

    @MainActor
    func testSyntheticFaceIDAppLockCoversSettingsPreservesDraftAndRestoresLocked() throws {
        let app = launch(additionalArguments: ["-metis.app-lock-fixture", "faceID", "-metis.app-lock-reset"])
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app)
        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        composer.tap()
        composer.typeText("Draft protected across app lock")
        web.buttons["Dismiss keyboard, keep composer focus"].tap()
        openAppLockSettings(in: app, web: web)
        let toggle = app.switches["metis.appLock.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("Face ID"))
        XCTAssertFalse(toggle.label.contains("Touch ID"))
        toggle.switches.firstMatch.tap()
        respondToSyntheticAuthentication(in: app, accept: true)
        awaitAppLockToggle("1", in: app)

        XCUIDevice.shared.press(.home)
        app.activate()
        respondToSyntheticAuthentication(in: app, accept: false)
        XCTAssertTrue(app.staticTexts["metis.appLock.cover"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["iPhone settings"].isHittable,
                       "The cover must block a previously presented native settings sheet")
        XCTAssertFalse(composer.isHittable)
        capture(app, named: "synthetic-biometric-fixture-locked-settings-covered")
        app.buttons["metis.appLock.unlock"].tap()
        respondToSyntheticAuthentication(in: app, accept: true)
        XCTAssertTrue(app.navigationBars["iPhone settings"].waitForExistence(timeout: 5))
        awaitAppLockToggle("1", in: app)
        app.buttons["metis.iPhoneSettingsDone"].tap()
        XCTAssertEqual(composer.value as? String, "Draft protected across app lock")

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-metis.app-lock-fixture", "faceID"]
        app.launch()
        respondToSyntheticAuthentication(in: app, accept: false)
        XCTAssertTrue(app.staticTexts["metis.appLock.cover"].waitForExistence(timeout: 5),
                      "A persisted lock must cover the app on a fresh process launch")
        app.buttons["metis.appLock.unlock"].tap()
        respondToSyntheticAuthentication(in: app, accept: true)
        let restoredWeb = authenticatedWebWorkspace(in: app)
        openAppLockSettings(in: app, web: restoredWeb)
        awaitAppLockToggle("1", in: app)
        app.switches["metis.appLock.toggle"].switches.firstMatch.tap()
        respondToSyntheticAuthentication(in: app, accept: false)
        awaitAppLockToggle("1", in: app)
        app.switches["metis.appLock.toggle"].switches.firstMatch.tap()
        respondToSyntheticAuthentication(in: app, accept: true)
        awaitAppLockToggle("0", in: app)
        capture(app, named: "synthetic-biometric-fixture-face-id-setting")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["iPhone settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["metis.appLock.cover"].exists)
    }

    @MainActor
    func testSyntheticTouchIDAppLockSettingsUseOnlyTouchID() {
        let app = launch(additionalArguments: ["-metis.app-lock-fixture", "touchID", "-metis.app-lock-reset"])
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        openAppLockSettings(in: app, web: web)
        let toggle = app.switches["metis.appLock.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("Touch ID"))
        XCTAssertFalse(toggle.label.contains("Face ID"))
        capture(app, named: "synthetic-biometric-fixture-touch-id-setting")
    }

    @MainActor
    func testSyntheticAppLockWithoutBiometricsShowsUnavailable() {
        let app = launch(additionalArguments: ["-metis.app-lock-fixture", "unavailable", "-metis.app-lock-reset"])
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        openAppLockSettings(in: app, web: web)
        XCTAssertTrue(app.descendants(matching: .any)["metis.appLock.unavailable"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["metis.appLock.toggle"].exists)
    }

    @MainActor
    private func openAppLockSettings(in app: XCUIApplication, web: XCUIElement) {
        let fallback = app.buttons["metis.appControlsFallback"]
        if fallback.waitForExistence(timeout: 2) { fallback.tap() }
        else { openIPhoneControls(in: app, web: web) }
        let settings = app.buttons["metis.iPhoneSettings"]
        revealInControls(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["iPhone settings"].waitForExistence(timeout: 10))
        let section = app.switches["metis.appLock.toggle"]
        if section.waitForExistence(timeout: 2), !section.isHittable {
            app.swipeUp()
        }
    }

    @MainActor
    private func respondToSyntheticAuthentication(in app: XCUIApplication, accept: Bool) {
        let prompt = app.alerts["SYNTHETIC biometric verification"]
        guard prompt.waitForExistence(timeout: 10) else {
            capture(app, named: "synthetic-app-lock-authentication-missing")
            XCTFail("Missing explicitly simulated authentication: " + app.debugDescription)
            return
        }
        prompt.buttons[accept ? "Approve synthetic authentication" : "Cancel synthetic authentication"].tap()
    }

    @MainActor
    private func awaitAppLockToggle(_ value: String, in app: XCUIApplication) {
        let toggle = app.switches["metis.appLock.toggle"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }

    @MainActor
    func testIPhoneControlsRemainReachableWithoutSidebar() {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        let fallback = app.buttons["metis.appControlsFallback"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 5),
                      "A successful same-origin page without sidebar must keep native controls reachable")
        XCTAssertTrue(fallback.isHittable)
        XCTAssertGreaterThanOrEqual(fallback.frame.width, 44)
        XCTAssertGreaterThanOrEqual(fallback.frame.height, 44)
        fallback.tap()
        XCTAssertTrue(appControlsSheet(in: app).waitForExistence(timeout: 5))
        capture(app, named: "native-liquid-glass-controls-standard-text-synthetic-background")
        closeIPhoneControls(in: app)

        _ = openSyntheticViewportFixture(in: app)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: fallback)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed,
                       "The canonical sidebar entry replaces the fallback without permanent native chrome")
        openIPhoneControls(in: app, web: web)
        closeIPhoneControls(in: app)
    }

    @MainActor
    func testSameOriginSubframeCannotOpenIPhoneControls() {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = openSyntheticViewportFixture(in: app)
        let showProbe = web.buttons["Show same-origin subframe probe"]
        revealSyntheticControl(showProbe, in: web)
        showProbe.tap()
        let subframeRequest = web.buttons["Request iPhone controls from same-origin subframe"]
        XCTAssertTrue(subframeRequest.waitForExistence(timeout: 10))
        revealSyntheticControl(subframeRequest, in: web)
        subframeRequest.tap()
        let subframePosted = web.staticTexts["Same-origin subframe sent menu"]
        XCTAssertTrue(subframePosted.waitForExistence(timeout: 5),
                      "The real same-origin child frame must successfully post to the exposed native handler")
        XCTAssertFalse(appControlsSheet(in: app).waitForExistence(timeout: 2),
                       "A same-origin subframe must not open native app controls")
        XCTAssertFalse(app.navigationBars["iPhone settings"].exists)

        // The same handler must still accept the explicit main-frame sidebar action.
        openIPhoneControls(in: app, web: web)
        XCTAssertTrue(app.buttons["metis.iPhoneSettings"].waitForExistence(timeout: 5))
        closeIPhoneControls(in: app)
        XCTAssertTrue(web.staticTexts["Authenticated viewport fixture session"].exists)
    }

    private struct SyntheticKeyboardTransition: Decodable {
        let transcriptAnchorTopRange: Double?
        let dockHeightRange: Double
        let revision: Int
        let emptyCenterYRange: Double?
        let minGreetingComposerGap: Double?
        let greetingComposerGapRange: Double?
        let maxGreetingComposerShiftError: Double?
        let frames: Int
        let duration: Double
        let headerTopRange: Double
        let headerBottomRange: Double
        let transcriptScrollRange: Double
        let documentScrollRange: Double
        let maxShellHeightError: Double
        let dockOffsetAttempts: Int
    }

    private struct SyntheticKeyboardDismissal: Decodable {
        let transcriptAnchorTopRange: Double?
        let dockHeightRange: Double
        let revision: Int
        let kind: String
        let frames: Int
        let duration: Double
        let offsetWrites: Int
        let headerTopRange: Double
        let headerBottomRange: Double
        let transcriptScrollRange: Double
        let documentScrollRange: Double
        let composerCenterXRange: Double
        let maxDockBottom: Double
        let viewportScaleRange: Double
        let emptyCenterYRange: Double?
        let minGreetingComposerGap: Double?
        let greetingComposerGapRange: Double?
        let maxGreetingComposerShiftError: Double?
    }

    private struct SyntheticViewportMetrics: Decodable {
        let revision: Int
        let measurementRevision: Int
        let width: Double
        let height: Double
        let safeAreaBottom: Double
        let safeAreaTop: Double
        let shellHeight: Double
        let headerTop: Double
        let sidebarTop: Double
        let sidebarHeight: Double
        let sidebarBrandTop: Double
        let sidebarCloseTop: Double
        let composerDockBottom: Double
        let composerPosition: String
        let composerServerFixed: Bool
        let productionEmptyState: Bool
        let tallComposer: Bool
        let composerDockHeight: Double
        let transcriptPaddingBottom: Double?
        let transcriptBottomDistance: Double
        let transcriptAnchorTop: Double?
        let emptyCenterY: Double?
        let greetingBottom: Double?
        let composerTop: Double
        let greetingComposerGap: Double?
        let composerBottom: Double
        let composerCenterX: Double
        let composerFontSize: Double
        let composerContentEditable: Bool
        let viewportScale: Double
        let viewportOffsetLeft: Double
        let focused: Bool
        let workspaceOpen: Bool
        let workspacePaddingBottom: Double
        let workspaceControlBottom: Double
    }

    @MainActor
    private func viewportMetricsReport(in web: XCUIElement) -> XCUIElement {
        web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic viewport metrics: ")).firstMatch
    }

    @MainActor
    private func viewportMetrics(in web: XCUIElement) throws -> SyntheticViewportMetrics {
        let prefix = "Synthetic viewport metrics: "
        let report = viewportMetricsReport(in: web)
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        let data = try XCTUnwrap(String(report.label.dropFirst(prefix.count)).data(using: .utf8))
        return try JSONDecoder().decode(SyntheticViewportMetrics.self, from: data)
    }

    @MainActor
    private func freshViewportMetrics(in app: XCUIApplication, web: XCUIElement,
                                      measureButton: String = "Measure viewport geometry") throws -> SyntheticViewportMetrics {
        let previous = try viewportMetrics(in: web).measurementRevision
        let measure = web.buttons[measureButton]
        XCTAssertTrue(measure.waitForExistence(timeout: 5))
        XCTAssertTrue(measure.isHittable, app.debugDescription)
        measure.tap()
        let sampled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let metrics = try? self.viewportMetrics(in: web) else { return false }
            return metrics.measurementRevision > previous
        }, object: web)
        if XCTWaiter.wait(for: [sampled], timeout: 5) != .completed {
            captureFixtureDiagnostics(in: app, web: web, named: "synthetic-fixture-fresh-measurement-failure")
            XCTFail("The fixture must explicitly remeasure CSS safe-area geometry after the window settles")
        }
        return try viewportMetrics(in: web)
    }

    @MainActor
    private func captureFixtureDiagnostics(in app: XCUIApplication, web: XCUIElement, named name: String) {
        capture(app, named: name)
        let report = viewportMetricsReport(in: web)
        let focus = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Composer ")).firstMatch
        let attachment = XCTAttachment(string: "\(report.exists ? report.label : "No viewport report")\n\(focus.exists ? focus.label : "No focus report")\n\(app.debugDescription)")
        attachment.name = name + "-accessibility-and-presentation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct SyntheticModelPreferenceValues: Decodable {
        let model: String?
        let parameters: String?
        let unrelated: String?
    }

    private struct SyntheticModelPreferenceReport: Decodable {
        let atScriptStart: SyntheticModelPreferenceValues
        let current: SyntheticModelPreferenceValues
    }

    @MainActor
    private func syntheticModelPreferences(in web: XCUIElement) throws -> SyntheticModelPreferenceReport {
        let prefix = "Synthetic model preference storage: "
        let report = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        let data = try XCTUnwrap(String(report.label.dropFirst(prefix.count)).data(using: .utf8))
        return try JSONDecoder().decode(SyntheticModelPreferenceReport.self, from: data)
    }

    @MainActor
    private func openSyntheticModelPreferenceFixture(in app: XCUIApplication) -> XCUIElement {
        let web = authenticatedWebWorkspace(in: app)
        let open = web.links["Open synthetic model preference storage fixture"]
        reveal(open, in: app)
        open.tap()
        XCTAssertTrue(web.staticTexts["SYNTHETIC model preference storage probe"].waitForExistence(timeout: 10))
        return web
    }

    @MainActor
    private func restartIntoSyntheticModelPreferences(in app: XCUIApplication) -> XCUIElement {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return openSyntheticModelPreferenceFixture(in: app)
    }

    @MainActor
    private func assertSyntheticPreferences(in web: XCUIElement, match written: SyntheticModelPreferenceValues) throws {
        let restored = try syntheticModelPreferences(in: web)
        XCTAssertEqual(restored.atScriptStart.model, written.model,
                       "Native preference seeding must run before the page's first script")
        XCTAssertEqual(restored.atScriptStart.parameters, written.parameters)
        XCTAssertEqual(restored.current.model, written.model)
        XCTAssertEqual(restored.current.parameters, written.parameters)
        XCTAssertNil(restored.atScriptStart.unrelated)
        XCTAssertNil(restored.current.unrelated, "Unsent drafts must not be copied into the session vault")
    }

    @MainActor
    private func assertSyntheticPreferencesAreEmpty(in web: XCUIElement) throws {
        let report = try syntheticModelPreferences(in: web)
        for values in [report.atScriptStart, report.current] {
            XCTAssertNil(values.model)
            XCTAssertNil(values.parameters)
            XCTAssertNil(values.unrelated)
        }
    }

    @MainActor
    private func openSyntheticViewportFixture(in app: XCUIApplication, contentEditableComposer: Bool = false,
                                               centeredEmptyState: Bool = false, productionEmptyState: Bool = false,
                                               tallComposer: Bool = false, largeEmptyComposer: Bool = false) -> XCUIElement {
        let web = authenticatedWebWorkspace(in: app)
        let openFixture = web.links[largeEmptyComposer ? "Open synthetic large empty composer fixture"
            : (tallComposer ? "Open synthetic tall composer transcript fixture"
            : (productionEmptyState ? "Open synthetic empty composer flow fixture"
               : (centeredEmptyState ? "Open synthetic centered empty-state fixture"
                  : (contentEditableComposer ? "Open synthetic contenteditable composer fixture" : "Open synthetic viewport fixture"))))]
        reveal(openFixture, in: app)
        openFixture.tap()
        XCTAssertTrue(web.staticTexts["Synthetic viewport fixture"].waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts["Authenticated viewport fixture session"].waitForExistence(timeout: 10),
                      "The separate geometry fixture must remain protected by the real authenticated session")
        XCTAssertTrue(syntheticPageInstance(in: web).waitForExistence(timeout: 5))
        return web
    }

    @MainActor
    private func syntheticPageInstance(in web: XCUIElement) -> XCUIElement {
        web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic page instance: ")).firstMatch
    }

    @MainActor
    private func revealSyntheticControl(_ element: XCUIElement, in web: XCUIElement) {
        let transcript = web.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Synthetic scrolling transcript, main")).firstMatch
        for _ in 0..<8 {
            if element.isHittable { return }
            let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
            let visibleBottom = min(transcript.frame.maxY, composer.frame.minY)
            let visibleHeight = max(0, visibleBottom - transcript.frame.minY)
            let origin = transcript.coordinate(withNormalizedOffset: .zero)
            let upper = origin.withOffset(CGVector(dx: transcript.frame.width * 0.5, dy: visibleHeight * 0.25))
            let lower = origin.withOffset(CGVector(dx: transcript.frame.width * 0.5, dy: visibleHeight * 0.75))
            if element.frame.midY < transcript.frame.midY {
                upper.press(forDuration: 0.05, thenDragTo: lower)
            } else {
                lower.press(forDuration: 0.05, thenDragTo: upper)
            }
        }
        XCTAssertTrue(element.isHittable, web.debugDescription)
    }

    @MainActor
    private func scrollSyntheticTranscriptToBottom(in app: XCUIApplication, web: XCUIElement) throws {
        let transcript = web.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Synthetic scrolling transcript, main")).firstMatch
        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        for _ in 0..<16 {
            if try viewportMetrics(in: web).transcriptBottomDistance <= 2 { break }
            let visibleBottom = min(transcript.frame.maxY, composer.frame.minY)
            let visibleHeight = max(0, visibleBottom - transcript.frame.minY)
            XCTAssertGreaterThan(visibleHeight, 44, "A real visible transcript region is required for the reader drag")
            let origin = transcript.coordinate(withNormalizedOffset: .zero)
            let lower = origin.withOffset(CGVector(dx: transcript.frame.width * 0.5, dy: visibleHeight * 0.8))
            let upper = origin.withOffset(CGVector(dx: transcript.frame.width * 0.5, dy: visibleHeight * 0.2))
            lower.press(forDuration: 0.05, thenDragTo: upper)
        }
        XCTAssertLessThanOrEqual(try viewportMetrics(in: web).transcriptBottomDistance, 2,
                                 "The reader must actually reach the bottom before sticky-bottom behavior is tested")
        XCTAssertTrue(web.staticTexts["Synthetic transcript anchor row"].isHittable, app.debugDescription)
    }


    private struct UsageLayout: Decodable {
        let visibleValues: Int?
        let windowGaps: [Double]
        let width: Double
        let usage: Bool
        let left: Double?
        let right: Double?
        let cardWidth: Double?
        let titleCenter: Double?
        let align: String?
    }

    @MainActor
    func testUsagePopoverFillsPortraitAndRetainsLandscapeLayout() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = authenticatedWebWorkspace(in: app)
        let link = web.links["Open usage layout fixture"]
        reveal(link, in: app)
        link.tap()
        let usage = web.buttons["Synthetic provider usage: 60% left"]
        XCTAssertTrue(usage.waitForExistence(timeout: 10), app.debugDescription)
        usage.tap()
        let portrait = try usageLayout(in: web, portrait: true, usage: true)
        XCTAssertEqual(try XCTUnwrap(portrait.left), 8, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(portrait.right), portrait.width - 8, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(portrait.titleCenter), portrait.width / 2, accuracy: 2)
        XCTAssertEqual(portrait.align, "center")
        XCTAssertEqual(portrait.visibleValues, 2)
        XCTAssertEqual(portrait.windowGaps.count, 2)
        for gap in portrait.windowGaps { XCTAssertEqual(gap, 12, accuracy: 1) }
        capture(app, named: "usage-real-component-portrait-full-width")

        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(in: app)
        let landscape = try usageLayout(in: web, portrait: false, usage: true)
        XCTAssertEqual(try XCTUnwrap(landscape.cardWidth), 256, accuracy: 2)
        XCTAssertEqual(landscape.align, "start")
        XCTAssertEqual(landscape.visibleValues, 2)
        for gap in landscape.windowGaps { XCTAssertEqual(gap, 12, accuracy: 1) }
        capture(app, named: "usage-real-component-landscape-unchanged")

        XCUIDevice.shared.orientation = .portrait
        _ = try usageLayout(in: web, portrait: true, usage: true)
        usage.tap()
        web.buttons["Context: 100 of 1K effective input tokens used"].tap()
        let context = try usageLayout(in: web, portrait: true, usage: false)
        XCTAssertEqual(try XCTUnwrap(context.cardWidth), 256, accuracy: 2,
                       "Context and other tooltips must retain their existing size")
        capture(app, named: "context-tooltip-portrait-unchanged")
    }

    @MainActor
    private func usageLayout(in web: XCUIElement, portrait: Bool, usage: Bool) throws -> UsageLayout {
        let prefix = "Usage geometry: "
        let report = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix + "{")).firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard report.exists, let data = String(report.label.dropFirst(prefix.count)).data(using: .utf8),
                  let value = try? JSONDecoder().decode(UsageLayout.self, from: data),
                  let width = value.cardWidth else { return false }
            return value.usage == usage && (portrait ? value.width < 600 : value.width > 600)
                && (portrait && usage ? abs(width - value.width + 16) < 2 : abs(width - 256) < 2)
        }, object: web)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
        let data = try XCTUnwrap(String(report.label.dropFirst(prefix.count)).data(using: .utf8))
        return try JSONDecoder().decode(UsageLayout.self, from: data)
    }

    @MainActor
    func testSidebarSwipeDismissesOverChatRowsAndBackdropWithoutSelecting() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = try openSyntheticSidebarFixture(in: app)
        web.buttons["Open sidebar"].tap()
        let row = web.buttons["Fixture chat"]
        XCTAssertTrue(row.isHittable)
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        // Vertical movement and a short drag must not dismiss or select a row.
        start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -80)))
        XCTAssertTrue(try sidebarState(in: web).sidebarOpen)
        let shortStart = web.buttons["Expand synthetic project"].coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        shortStart.press(forDuration: 0.02, thenDragTo: shortStart.withOffset(CGVector(dx: -24, dy: 0)))
        XCTAssertTrue(try sidebarState(in: web).sidebarOpen)
        start.press(forDuration: 0.02, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        try awaitSwipeClose(in: web, count: 1)
        var state = try sidebarState(in: web)
        XCTAssertEqual(state.activeDestination, "New chat")
        XCTAssertEqual(state.selectionCount, 0)
        let motion = try XCTUnwrap(state.closeMotion)
        XCTAssertFalse(motion.hiddenBeforeOffscreen)
        if !motion.reducedMotion { XCTAssertGreaterThan(motion.visibleMovingFrames, 1) }
        capture(app, named: "sidebar-swipe-over-chat-row-closed")

        web.buttons["Open sidebar"].tap()
        let backdrop = web.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5))
        backdrop.press(forDuration: 0.02, thenDragTo: backdrop.withOffset(CGVector(dx: -110, dy: 0)))
        try awaitSwipeClose(in: web, count: 2)
        state = try sidebarState(in: web)
        XCTAssertEqual(state.selectionCount, 0)
        XCTAssertEqual(state.activeDestination, "New chat")
    }

    @MainActor
    private func awaitSwipeClose(in web: XCUIElement, count: Int) throws {
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = try? self.sidebarState(in: web) else { return false }
            return !value.sidebarOpen && value.closeCount == count && value.closeMotion?.revision == count
        }, object: web)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 6), .completed)
    }

    @MainActor
    func testSyntheticSidebarDestinationsCloseDrawerWithoutExtraTap() throws {
        let app = launch()
        signIn(app, server: "http://localhost:43100")
        let web = try openSyntheticSidebarFixture(in: app)
        var expectedCloses = 0
        for destination in ["Notebooks", "Automations", "New chat", "Fixture chat", "Fixture project"] {
            web.buttons["Open sidebar"].tap()
            XCTAssertTrue(try sidebarState(in: web).sidebarOpen)
            web.buttons[destination].tap()
            XCTAssertTrue(web.staticTexts["Synthetic destination: " + destination].waitForExistence(timeout: 5))
            expectedCloses += 1
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let state = try? self.sidebarState(in: web) else { return false }
                return !state.sidebarOpen && state.closeCount == expectedCloses && state.closeMotion?.revision == expectedCloses
            }, object: web)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed,
                           "The same destination gesture must select the page and close the mobile drawer")
            let motion = try XCTUnwrap(sidebarState(in: web).closeMotion)
            XCTAssertGreaterThan(motion.frames, 5)
            XCTAssertGreaterThan(motion.initial.right, motion.initial.width - 2)
            XCTAssertLessThanOrEqual(motion.final.right, 1)
            XCTAssertEqual(motion.final.visibility, "hidden")
            XCTAssertFalse(motion.hiddenBeforeOffscreen,
                           "The drawer must remain painted until its exit slide finishes")
            if !motion.reducedMotion {
                XCTAssertGreaterThan(motion.visibleMovingFrames, 1,
                                     "Observe visible intermediate positions, not just a closed endpoint")
            }
            let attachment = XCTAttachment(data: try JSONEncoder().encode(motion), uniformTypeIdentifier: "public.json")
            attachment.name = "sidebar-exit-motion-" + destination + "-" + String(expectedCloses)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        web.buttons["Open sidebar"].tap()
        web.buttons["Expand synthetic project"].tap()
        XCTAssertTrue(try sidebarState(in: web).projectExpanded)
        XCTAssertTrue(try sidebarState(in: web).sidebarOpen,
                      "A project-row expander is not a top-level destination")
        web.buttons["Programmatically select New chat"].tap()
        XCTAssertEqual(try sidebarState(in: web).activeDestination, "New chat")
        XCTAssertTrue(try sidebarState(in: web).sidebarOpen,
                      "Synthetic, untrusted navigation must not trigger the native drawer hook")
        web.buttons["Use synthetic agent destination"].tap()
        web.buttons["New agent"].tap()
        let agentClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? self.sidebarState(in: web).sidebarOpen) == false
        }, object: web)
        XCTAssertEqual(XCTWaiter.wait(for: [agentClosed], timeout: 5), .completed)
        expectedCloses += 1
        XCTAssertTrue(web.staticTexts["Synthetic new-agent dialog opened"].exists)
        web.buttons["Open sidebar"].tap()
        web.buttons["Cancelled destination"].tap()
        XCTAssertTrue(try sidebarState(in: web).sidebarOpen)
        web.descendants(matching: .any)["Chat actions"].firstMatch.tap()
        XCTAssertTrue(try sidebarState(in: web).sidebarOpen)
        web.buttons["Open account menu"].tap()
        XCTAssertTrue(try sidebarState(in: web).accountMenuOpen)
        XCTAssertTrue(try sidebarState(in: web).sidebarOpen,
                      "Account/settings controls must not close the sidebar")
        XCTAssertEqual(try sidebarState(in: web).closeCount, expectedCloses)
        capture(app, named: "synthetic-sidebar-destination-and-exclusion-checks")
    }

    @MainActor
    func testSyntheticSidebarSearchKeepsDrawerAndSettingsBehindInputSurface() throws {
        let app = launch(additionalArguments: ["-metis.synthetic-input-occlusion"])
        signIn(app, server: "http://localhost:43100")
        let web = try openSyntheticSidebarFixture(in: app)
        web.buttons["Open sidebar"].tap()
        web.buttons["Notebooks"].tap()
        XCTAssertTrue(web.staticTexts["Synthetic destination: Notebooks"].waitForExistence(timeout: 5))
        // Navigation auto-close is covered separately. Make the geometry setup
        // independent so this test can also reproduce the search bug on old builds.
        if try sidebarState(in: web).sidebarOpen { web.buttons["Close sidebar"].tap() }
        web.buttons["Open sidebar"].tap()
        let before = try sidebarState(in: web)
        let instance = before.pageInstance
        let geometryBefore = try XCTUnwrap(observedWindowGeometry(in: app))
        XCTAssertEqual(before.metrics.sidebarTop, 0, accuracy: 2)
        XCTAssertEqual(before.metrics.sidebarHeight, Double(geometryBefore.window.height), accuracy: 2)

        web.buttons["Search chats"].tap()
        let input = web.textFields["Search chats or commands"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("sidebar query")
        XCTAssertTrue(app.descendants(matching: .any)["metis.syntheticInputOcclusion"].firstMatch.waitForExistence(timeout: 5))
        let raised = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let g = self.observedWindowGeometry(in: app) else { return false }
            return g.window.maxY - g.availableBottom >= 300 && abs(g.web.maxY - g.availableBottom) <= 2
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [raised], timeout: 8), .completed,
                       "Use the actual labelled native test surface and WebKit frame, not an assumed keyboard height")
        let opened = try awaitSidebarSearchTransition("open", in: web)
        let current = try sidebarState(in: web, search: true)
        XCTAssertEqual(current.pageInstance, instance)
        XCTAssertEqual(current.activeDestination, "Notebooks")
        XCTAssertTrue(current.sidebarOpen, "Search must leave the drawer open")
        XCTAssertEqual(current.closeCount, before.closeCount)
        XCTAssertEqual(current.query, "sidebar query")
        XCTAssertGreaterThanOrEqual(current.metrics.searchFontSize, 16)
        XCTAssertEqual(current.metrics.viewportScale, before.metrics.viewportScale, accuracy: 0.001)
        assertSidebarLayout(current.metrics, matches: before.metrics)
        assertSidebarTransition(opened)

        let raisedGeometry = try XCTUnwrap(observedWindowGeometry(in: app))
        XCTAssertGreaterThan(current.metrics.settingsTop ?? 0, Double(raisedGeometry.availableBottom),
                             "The settings entry stays at its original bottom position, behind the keyboard")
        XCTAssertGreaterThan(current.metrics.accountTop, Double(raisedGeometry.availableBottom))
        XCTAssertFalse(web.buttons["Open account menu"].isHittable,
                       "The keyboard/clipped native viewport must cover the unchanged footer")
        capture(app, named: "synthetic-sidebar-search-footer-stays-behind-input")

        let done = app.toolbars.buttons["Done"].firstMatch
        XCTAssertTrue(done.exists && done.isHittable)
        done.tap()
        let closed = try awaitSidebarSearchTransition("close", in: web)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let g = self.observedWindowGeometry(in: app) else { return false }
            return g.availableBottom >= g.window.maxY - 1
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
        assertSidebarTransition(closed)
        let after = try sidebarState(in: web, search: true)
        assertSidebarLayout(after.metrics, matches: before.metrics)
        XCTAssertEqual(after.query, "sidebar query")
        XCTAssertTrue(after.sidebarOpen)
        web.buttons["Close search"].tap()
        XCTAssertTrue(try sidebarState(in: web).sidebarOpen)
        XCTAssertEqual(try sidebarState(in: web).closeCount, before.closeCount)

        // Reopen and reach the final result with actual scrolling while the
        // input surface is up: a fixed top must not trap the list's last row.
        web.buttons["Search chats"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        let secondRaised = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let g = self.observedWindowGeometry(in: app) else { return false }
            return g.window.maxY - g.availableBottom >= 300
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [secondRaised], timeout: 8), .completed)
        let last = web.buttons["Open synthetic last search result"]
        for _ in 0..<8 {
            let g = try XCTUnwrap(observedWindowGeometry(in: app))
            if last.isHittable && last.frame.maxY <= g.availableBottom + 2 { break }
            let state = try sidebarState(in: web, search: true)
            let top = state.metrics.resultsTop
            let bottom = min(top + state.metrics.resultsHeight, Double(g.availableBottom - g.web.minY))
            let visible = max(0, bottom - top)
            XCTAssertGreaterThan(visible, 40, "The search results must retain a usable visible scroll area")
            let origin = web.coordinate(withNormalizedOffset: .zero)
            let lower = origin.withOffset(CGVector(dx: g.web.width * 0.5, dy: CGFloat(top + visible * 0.8)))
            let upper = origin.withOffset(CGVector(dx: g.web.width * 0.5, dy: CGFloat(top + visible * 0.2)))
            lower.press(forDuration: 0.05, thenDragTo: upper)
        }
        let g = try XCTUnwrap(observedWindowGeometry(in: app))
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, g.availableBottom + 2)
        last.tap()
        XCTAssertTrue(web.staticTexts["Synthetic destination: Search result"].waitForExistence(timeout: 5))
        XCTAssertFalse(try sidebarState(in: web).sidebarOpen)
        capture(app, named: "synthetic-sidebar-last-search-result-reachable")
    }

    private struct SyntheticSidebarMetrics: Decodable {
        let sidebarTop: Double
        let sidebarHeight: Double
        let sidebarBottom: Double
        let footerTop: Double
        let footerBottom: Double
        let accountTop: Double
        let settingsTop: Double?
        let safeBottom: Double
        let windowHeight: Double
        let viewportHeight: Double
        let width: Double
        let documentScrollY: Double
        let viewportScale: Double
        let searchFontSize: Double
        let dialogTop: Double?
        let resultsTop: Double
        let resultsHeight: Double
    }

    private struct SyntheticSidebarTransition: Decodable {
        let revision: Int
        let phase: String
        let frames: Int
        let duration: Double
        let initial: SyntheticSidebarMetrics
        let final: SyntheticSidebarMetrics
        let sidebarTopRange: Double
        let sidebarHeightRange: Double
        let footerTopRange: Double
        let accountTopRange: Double
        let settingsTopRange: Double
        let documentScrollRange: Double
        let scaleRange: Double
        let dialogTopRange: Double
    }

    private struct SyntheticSidebarCloseMotion: Codable {
        struct Position: Codable {
            let right: Double
            let width: Double
            let visibility: String
        }
        let revision: Int
        let initial: Position
        let final: Position
        let frames: Int
        let reducedMotion: Bool
        let visibleMovingFrames: Int
        let hiddenBeforeOffscreen: Bool
    }

    private struct SyntheticSidebarState: Decodable {
        let pageInstance: String
        let activeDestination: String
        let sidebarOpen: Bool
        let closeCount: Int
        let selectionCount: Int
        let projectExpanded: Bool
        let agentMode: Bool
        let accountMenuOpen: Bool
        let searchOpen: Bool
        let query: String
        let authenticated: Bool
        let metrics: SyntheticSidebarMetrics
        let transition: SyntheticSidebarTransition?
        let closeMotion: SyntheticSidebarCloseMotion?
    }

    @MainActor
    private func openSyntheticSidebarFixture(in app: XCUIApplication) throws -> XCUIElement {
        let web = authenticatedWebWorkspace(in: app)
        let link = web.links["Open synthetic sidebar fixture"]
        reveal(link, in: app)
        link.tap()
        XCTAssertTrue(web.staticTexts["Authenticated sidebar fixture session"].waitForExistence(timeout: 10))
        XCTAssertTrue(try sidebarState(in: web).authenticated)
        return web
    }

    @MainActor
    private func sidebarState(in web: XCUIElement, search: Bool = false) throws -> SyntheticSidebarState {
        let prefix = search ? "Synthetic sidebar search state: " : "Synthetic sidebar state: "
        let report = web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(report.exists, "The fixture's explicit DOM geometry report must exist")
        let bytes = try XCTUnwrap(String(report.label.dropFirst(prefix.count)).data(using: .utf8))
        return try JSONDecoder().decode(SyntheticSidebarState.self, from: bytes)
    }

    @MainActor
    private func awaitSidebarSearchTransition(_ phase: String, in web: XCUIElement) throws -> SyntheticSidebarTransition {
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let state = try? self.sidebarState(in: web, search: true) else { return false }
            return state.transition?.phase == phase
        }, object: web)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed)
        return try XCTUnwrap(sidebarState(in: web, search: true).transition)
    }

    private func assertSidebarLayout(_ current: SyntheticSidebarMetrics, matches baseline: SyntheticSidebarMetrics,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(current.sidebarTop, baseline.sidebarTop, accuracy: 2, file: file, line: line)
        XCTAssertEqual(current.sidebarHeight, baseline.sidebarHeight, accuracy: 2, file: file, line: line)
        XCTAssertEqual(current.sidebarBottom, baseline.sidebarBottom, accuracy: 2, file: file, line: line)
        XCTAssertEqual(current.footerTop, baseline.footerTop, accuracy: 2, file: file, line: line)
        XCTAssertEqual(current.footerBottom, baseline.footerBottom, accuracy: 2, file: file, line: line)
        XCTAssertEqual(current.accountTop, baseline.accountTop, accuracy: 2, file: file, line: line)
        if let top = baseline.settingsTop {
            XCTAssertEqual(current.settingsTop ?? .nan, top, accuracy: 2, file: file, line: line)
        }
        XCTAssertEqual(current.documentScrollY, baseline.documentScrollY, accuracy: 2, file: file, line: line)
    }

    private func assertSidebarTransition(_ transition: SyntheticSidebarTransition,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(transition.frames, 18, file: file, line: line)
        XCTAssertGreaterThanOrEqual(transition.duration, 900, file: file, line: line)
        for range in [transition.sidebarTopRange, transition.sidebarHeightRange, transition.footerTopRange,
                      transition.accountTopRange, transition.settingsTopRange, transition.documentScrollRange] {
            XCTAssertLessThanOrEqual(range, 2, file: file, line: line)
        }
        XCTAssertLessThanOrEqual(transition.scaleRange, 0.001, file: file, line: line)
    }

    private struct ObservedWindowGeometry {
        let window: CGRect
        let web: CGRect
        let keyboard: CGRect
        let statusBarBottom: CGFloat?
        let availableBottom: CGFloat
    }

    @MainActor
    private func observedWindowGeometry(in app: XCUIApplication) -> ObservedWindowGeometry? {
        // One immutable public snapshot keeps keyboard-process element IDs
        // from becoming stale halfway through a rotation measurement.
        guard let snapshot = try? app.snapshot(),
              let window = snapshot.children.first(where: { $0.elementType == .window }) else { return nil }
        let windowFrame = window.frame
        var webFrame: CGRect?
        var keyboard = CGRect.zero
        var statusBarBottom: CGFloat?
        var inputSurfaces: [CGRect] = []
        func labels(in node: XCUIElementSnapshot) -> Set<String> {
            node.children.reduce(into: Set([node.label])) { $0.formUnion(labels(in: $1)) }
        }
        func visit(_ node: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot]) {
            if node.elementType == .webView && node.identifier == "metis.webWorkspace" && webFrame == nil {
                webFrame = node.frame
            }
            if node.elementType == .statusBar && !node.frame.isEmpty {
                statusBarBottom = max(statusBarBottom ?? node.frame.maxY, node.frame.maxY)
            }
            if node.identifier == "metis.syntheticInputOcclusion" {
                let intersection = windowFrame.intersection(node.frame)
                if !intersection.isNull && !intersection.isEmpty { inputSurfaces.append(intersection) }
            }
            if node.elementType == .keyboard {
                let intersection = windowFrame.intersection(node.frame)
                if !intersection.isNull && !intersection.isEmpty {
                    keyboard = intersection
                    inputSurfaces.append(intersection)
                }
            }
            if node.elementType == .toolbar {
                let names = labels(in: node)
                if names.contains("Done") && names.contains("Previous"),
                   let container = ancestors.reversed().first(where: {
                       $0.elementType == .other && $0.frame.contains(node.frame)
                           && abs($0.frame.maxY - windowFrame.maxY) <= 1
                   }) {
                    let intersection = windowFrame.intersection(container.frame)
                    if !intersection.isNull && !intersection.isEmpty { inputSurfaces.append(intersection) }
                }
            }
            for child in node.children { visit(child, ancestors: ancestors + [node]) }
        }
        visit(snapshot, ancestors: [])
        guard let webFrame else { return nil }
        return ObservedWindowGeometry(window: windowFrame, web: webFrame, keyboard: keyboard,
                                      statusBarBottom: statusBarBottom,
                                      availableBottom: inputSurfaces.map(\.minY).min() ?? windowFrame.maxY)
    }

    @MainActor
    private func assertSyntheticViewportGeometry(in app: XCUIApplication, web: XCUIElement,
                                                 file: StaticString = #filePath, line: UInt = #line) throws {
        var measured: ObservedWindowGeometry?
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let geometry = self.observedWindowGeometry(in: app),
                  abs(geometry.web.maxY - geometry.availableBottom) <= 2 else { return false }
            measured = geometry
            return true
        }, object: web)
        let settledResult = XCTWaiter.wait(for: [settled], timeout: 8)
        if settledResult != .completed {
            captureFixtureDiagnostics(in: app, web: web, named: "synthetic-fixture-viewport-frame-failure")
        }
        XCTAssertEqual(settledResult, .completed,
                       "WebKit must meet the window bottom or actual system input surface", file: file, line: line)
        let geometry = try XCTUnwrap(measured)
        XCTAssertEqual(geometry.web.minY, geometry.window.minY, accuracy: 1,
                       "WebKit must paint from the real window top behind the status bar", file: file, line: line)
        XCTAssertEqual(geometry.web.maxY, geometry.availableBottom, accuracy: 2, file: file, line: line)
        XCTAssertFalse(app.buttons["metis.appMenu"].exists, "No permanent native App bar is present", file: file, line: line)
        XCTAssertFalse(app.buttons["metis.workspaceReload"].exists, file: file, line: line)
        let metrics = try freshViewportMetrics(in: app, web: web)
        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        let clearance = CGFloat(max(4, metrics.safeAreaBottom))
        XCTAssertEqual(metrics.shellHeight, Double(geometry.window.height), accuracy: 2,
                       "The shell keeps the full native-window layout height while only WebKit is clipped above input", file: file, line: line)
        XCTAssertEqual(metrics.headerTop, metrics.safeAreaTop, accuracy: 2,
                       "In-flow header content must clear exactly one CSS status-bar inset", file: file, line: line)
        if let nativeStatusBarBottom = geometry.statusBarBottom {
            XCTAssertGreaterThanOrEqual(web.frame.minY + CGFloat(metrics.headerTop), nativeStatusBarBottom - 1,
                                        "Header controls must clear the observed native status bar", file: file, line: line)
        }
        if metrics.focused { XCTAssertEqual(metrics.composerDockBottom, 0, accuracy: 1, file: file, line: line) }
        XCTAssertEqual(web.frame.height, CGFloat(metrics.height), accuracy: 2,
                       "The page viewport must use the full WebKit height", file: file, line: line)
        XCTAssertEqual(web.frame.width, CGFloat(metrics.width), accuracy: 2, file: file, line: line)
        XCTAssertEqual(web.frame.maxY - composer.frame.maxY, clearance, accuracy: 2,
                       "Only the web footer's CSS home-indicator clearance belongs below its composer", file: file, line: line)
        XCTAssertEqual(CGFloat(metrics.height - metrics.composerBottom), clearance, accuracy: 2, file: file, line: line)
    }

    @MainActor
    private func assertSyntheticEmptyComposerClearance(in app: XCUIApplication, web: XCUIElement) throws {
        let geometry = try XCTUnwrap(observedWindowGeometry(in: app))
        let metrics = try viewportMetrics(in: web)
        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        let clearance = max(4, metrics.safeAreaBottom)
        XCTAssertEqual(metrics.shellHeight, Double(geometry.window.height), accuracy: 2)
        XCTAssertLessThanOrEqual(Double(web.frame.minY) + metrics.composerBottom,
                                 Double(geometry.availableBottom) - clearance + 2,
                                 "The empty dock may move upward only enough to clear the actual input surface")
        XCTAssertLessThanOrEqual(composer.frame.maxY, geometry.availableBottom - CGFloat(clearance) + 2)
        XCTAssertGreaterThanOrEqual(composer.frame.minY, geometry.statusBarBottom ?? geometry.window.minY)
        XCTAssertTrue(composer.isHittable, app.debugDescription)
    }

    @MainActor
    private func assertSyntheticWorkspaceClearance(in app: XCUIApplication, web: XCUIElement) throws {
        let open = web.buttons["Open synthetic workspace panel"]
        revealSyntheticControl(open, in: web)
        open.tap()
        let bottomControl = web.buttons["Synthetic workspace bottom control"]
        XCTAssertTrue(bottomControl.waitForExistence(timeout: 5))
        let metrics = try freshViewportMetrics(in: app, web: web, measureButton: "Measure workspace geometry")
        XCTAssertTrue(metrics.workspaceOpen)
        let geometry = try XCTUnwrap(observedWindowGeometry(in: app))
        XCTAssertEqual(geometry.web.maxY, geometry.availableBottom, accuracy: 2)
        XCTAssertEqual(metrics.workspacePaddingBottom, metrics.safeAreaBottom, accuracy: 2,
                       "The app presentation must provide CSS home-indicator clearance to the full-screen workspace panel")
        XCTAssertEqual(web.frame.maxY - bottomControl.frame.maxY, CGFloat(metrics.safeAreaBottom), accuracy: 2)
        XCTAssertEqual(metrics.height - metrics.workspaceControlBottom, metrics.safeAreaBottom, accuracy: 2)
        XCTAssertGreaterThanOrEqual(bottomControl.frame.height, 44)
        XCTAssertTrue(bottomControl.isHittable)
        capture(app, named: "synthetic-fixture-not-design-right-workspace-\(app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height ? "landscape" : "portrait")")
        web.buttons["Close synthetic workspace panel"].tap()
    }

    @MainActor
    private func waitForLandscape(in app: XCUIApplication) {
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
    }

    @MainActor
    private func appControlsSheet(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["metis.appControlsSheet"].firstMatch
    }

    @MainActor
    private func openIPhoneControls(in app: XCUIApplication, web: XCUIElement) {
        let closeSidebar = web.buttons["Close sidebar"]
        if !closeSidebar.isHittable { web.buttons["Open sidebar"].tap() }
        XCTAssertTrue(web.buttons["Open account menu"].waitForExistence(timeout: 5),
                      "Native controls must be reached beside the actual web account trigger")
        // WebKit exposes the real aria-haspopup=dialog HTML button as Other
        // on this runtime. Locate its accessible name, then verify its hit area
        // and that a real tap opens the native sheet.
        let controls = web.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "iPhone controls")).firstMatch
        capture(app, named: "synthetic-fixture-not-design-sidebar-before-controls-lookup")
        if !controls.waitForExistence(timeout: 5) {
            captureFixtureDiagnostics(in: app, web: web, named: "synthetic-fixture-controls-lookup-failure")
        }
        XCTAssertTrue(controls.exists, app.debugDescription)
        XCTAssertTrue(controls.isHittable)
        XCTAssertGreaterThanOrEqual(controls.frame.width, 44)
        XCTAssertGreaterThanOrEqual(controls.frame.height, 44)
        controls.tap()
        XCTAssertTrue(appControlsSheet(in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func revealInControls(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            appControlsSheet(in: app).swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    private func assertNativeControlsHaveMinimumHitAreas(in app: XCUIApplication) {
        for identifier in ["metis.appControlsClose", "metis.iPhoneSettings", "metis.workspaceBack", "metis.workspaceForward", "metis.workspaceReload"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            revealInControls(button, in: app)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, identifier)
        }
    }

    @MainActor
    private func closeIPhoneControls(in app: XCUIApplication) {
        let close = app.buttons["metis.appControlsClose"]
        for _ in 0..<8 {
            if close.isHittable { break }
            appControlsSheet(in: app).swipeDown()
        }
        XCTAssertTrue(close.isHittable)
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: appControlsSheet(in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
    }

    @MainActor
    private func authenticatedWebWorkspace(in app: XCUIApplication) -> XCUIElement {
        let web = app.webViews["metis.webWorkspace"].firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15), app.debugDescription)
        let skipPasswordSave = app.sheets["Save Password?"].buttons["Not Now"]
        for _ in 0..<3 {
            guard skipPasswordSave.waitForExistence(timeout: 1) else { break }
            skipPasswordSave.tap()
        }
        XCTAssertTrue(web.staticTexts["Authenticated web workspace fixture"].waitForExistence(timeout: 15),
                      "The fixture only serves this page after validating the real session cookie")
        XCTAssertTrue(web.staticTexts["HttpOnly cookie verified"].waitForExistence(timeout: 10),
                      "The web page must authenticate API requests without a script-readable session cookie")
        return web
    }

    @MainActor
    private func signOutFromWebFixture(in app: XCUIApplication, web: XCUIElement) {
        let logout = web.buttons["Sign out from the web fixture"]
        reveal(logout, in: app)
        logout.tap()
        XCTAssertTrue(app.buttons["metis.signIn"].waitForExistence(timeout: 15),
                      "Deleting the web cookie must return to the existing native sign-in screen")
        XCTAssertTrue(app.textFields["metis.server"].exists)
        XCTAssertFalse(app.webViews["metis.webWorkspace"].exists)
    }

    private struct FixtureVerificationState: Decodable {
        let holdSessionVerification: Bool
        let heldSessionRequests: Int
    }

    private func resetFixtureSessionVerification() async throws {
        try await setFixtureSessionState("release-session")
        try await setFixtureSessionState("online")
        addTeardownBlock {
            try await self.setFixtureSessionState("release-session")
            try await self.setFixtureSessionState("online")
        }
    }

    @MainActor
    private func assertNeutralSavedSessionVerification(in app: XCUIApplication) async throws {
        let restoring = app.descendants(matching: .any)["metis.sessionRestoring"].firstMatch
        XCTAssertTrue(restoring.waitForExistence(timeout: 5), app.debugDescription)
        var held = false
        for _ in 0..<40 {
            let (data, response) = try await URLSession.shared.data(from: fixtureControlURL())
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let state = try JSONDecoder().decode(FixtureVerificationState.self, from: data)
            held = state.holdSessionVerification && state.heldSessionRequests > 0
            if held { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(held, "Startup must actually reach the held cookie-verification request")
        XCTAssertTrue(restoring.exists)
        XCTAssertFalse(app.webViews["metis.webWorkspace"].exists,
                       "Authenticated web content must wait for the server response")
        let unexpectedLogin = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["metis.signIn"].exists || app.textFields["metis.server"].exists
                || app.secureTextFields["metis.password"].exists
        }, object: app)
        unexpectedLogin.isInverted = true
        let observed = await XCTWaiter.fulfillment(of: [unexpectedLogin], timeout: 2)
        XCTAssertEqual(observed, .completed,
                       "The sign-in form must stay absent while the saved session is being verified")
        XCTAssertTrue(restoring.exists)
    }

    private func fixtureControlURL(state: String? = nil) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 43100
        components.path = "/fixture-control"
        if let state { components.queryItems = [URLQueryItem(name: "state", value: state)] }
        return try XCTUnwrap(components.url)
    }

    private func setFixtureSessionState(_ state: String) async throws {
        var request = URLRequest(url: try fixtureControlURL(state: state), timeoutInterval: 5)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
    }

    @MainActor
    private func scrollToEarlier(_ element: XCUIElement, in transcript: XCUIElement) {
        for _ in 0..<12 {
            if element.isHittable { return }
            transcript.swipeDown()
        }
        if !element.isHittable {
            capture(XCUIApplication(), named: "paging-failure")
        }
        XCTAssertTrue(element.isHittable, "Earlier message or page control could not be reached: \(XCUIApplication().debugDescription)")
    }

    @MainActor
    private func launch(nativeInterface: Bool = false, additionalArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-metisServer", ""]
        if nativeInterface { app.launchArguments.append("-metis.native-interface") }
        app.launchArguments.append(contentsOf: additionalArguments)
        app.launch()
        return app
    }

    @MainActor
    private func signIn(_ app: XCUIApplication, server: String, username fixtureUsername: String = "metis-apple-fixture-alice") {
        let address = app.textFields["metis.server"]
        XCTAssertTrue(address.waitForExistence(timeout: 8))
        address.tap()
        address.typeText(server)
        let username = app.textFields["metis.username"]
        username.tap()
        username.typeText(fixtureUsername)
        let password = app.secureTextFields["metis.password"]
        password.tap()
        password.typeText("apple-fixture-only")
        app.buttons["metis.signIn"].tap()
    }
}
