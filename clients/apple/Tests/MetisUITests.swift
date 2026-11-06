import XCTest

final class MetisUITests: XCTestCase {
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
        web.buttons["Check viewport fixture session"].tap()
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

    private struct SyntheticViewportMetrics: Decodable {
        let revision: Int
        let measurementRevision: Int
        let width: Double
        let height: Double
        let safeAreaBottom: Double
        let composerBottom: Double
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

    @MainActor
    private func openSyntheticViewportFixture(in app: XCUIApplication) -> XCUIElement {
        let web = authenticatedWebWorkspace(in: app)
        let openFixture = web.links["Open synthetic viewport fixture"]
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

    private struct ObservedWindowGeometry {
        let window: CGRect
        let web: CGRect
        let keyboard: CGRect
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
        var inputSurfaces: [CGRect] = []
        func labels(in node: XCUIElementSnapshot) -> Set<String> {
            node.children.reduce(into: Set([node.label])) { $0.formUnion(labels(in: $1)) }
        }
        func visit(_ node: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot]) {
            if node.elementType == .webView && node.identifier == "metis.webWorkspace" && webFrame == nil {
                webFrame = node.frame
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
        XCTAssertEqual(geometry.web.maxY, geometry.availableBottom, accuracy: 2, file: file, line: line)
        XCTAssertFalse(app.buttons["metis.appMenu"].exists, "No permanent native App bar is present", file: file, line: line)
        XCTAssertFalse(app.buttons["metis.workspaceReload"].exists, file: file, line: line)
        let metrics = try freshViewportMetrics(in: app, web: web)
        let composer = web.descendants(matching: .any)["Synthetic viewport draft"].firstMatch
        let clearance = CGFloat(max(4, metrics.safeAreaBottom))
        XCTAssertEqual(web.frame.height, CGFloat(metrics.height), accuracy: 2,
                       "The page viewport must use the full WebKit height", file: file, line: line)
        XCTAssertEqual(web.frame.width, CGFloat(metrics.width), accuracy: 2, file: file, line: line)
        XCTAssertEqual(web.frame.maxY - composer.frame.maxY, clearance, accuracy: 2,
                       "Only the web footer's CSS home-indicator clearance belongs below its composer", file: file, line: line)
        XCTAssertEqual(CGFloat(metrics.height - metrics.composerBottom), clearance, accuracy: 2, file: file, line: line)
    }

    @MainActor
    private func assertSyntheticWorkspaceClearance(in app: XCUIApplication, web: XCUIElement) throws {
        let open = web.buttons["Open synthetic workspace panel"]
        reveal(open, in: app)
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

    private func setFixtureSessionState(_ state: String) async throws {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 43100
        components.path = "/fixture-control"
        components.queryItems = [URLQueryItem(name: "state", value: state)]
        var request = URLRequest(url: try XCTUnwrap(components.url), timeoutInterval: 5)
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
    private func signIn(_ app: XCUIApplication, server: String) {
        let address = app.textFields["metis.server"]
        XCTAssertTrue(address.waitForExistence(timeout: 8))
        address.tap()
        address.typeText(server)
        let username = app.textFields["metis.username"]
        username.tap()
        username.typeText("metis-apple-fixture-alice")
        let password = app.secureTextFields["metis.password"]
        password.tap()
        password.typeText("apple-fixture-only")
        app.buttons["metis.signIn"].tap()
    }
}
