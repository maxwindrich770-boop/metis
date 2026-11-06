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
        XCTAssertTrue(app.buttons["metis.appMenu"].exists)
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
    private func launch(nativeInterface: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-metisServer", ""]
        if nativeInterface { app.launchArguments.append("-metis.native-interface") }
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
