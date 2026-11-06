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
        let app = launch()
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
        let transcript = app.collectionViews.firstMatch
        let earlier = app.buttons["Load earlier messages"]
        scrollToEarlier(earlier, in: transcript)
        earlier.tap()
        scrollToEarlier(app.staticTexts["Nachricht 16 🌱"], in: transcript)
        scrollToEarlier(earlier, in: transcript)
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
        scrollToEarlier(firstMessage, in: transcript)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        XCTAssertTrue(element.isHittable, "Earlier message or page control could not be reached")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-metisServer", ""]
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
