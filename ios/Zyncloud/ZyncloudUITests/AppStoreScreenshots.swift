import XCTest

/// Walks the app and saves one PNG per screen for the App Store product page.
///
/// Not part of the `Zyncloud` scheme on purpose: it talks to the real server with whatever login
/// the simulator's keychain holds, so it must never run in CI. Run it through the `Screenshots`
/// scheme on a simulator that is already signed in:
///
/// ```
/// xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100
/// TEST_RUNNER_SCREENSHOT_DIR=/some/dir xcodebuild test -project Zyncloud.xcodeproj \
///   -scheme Screenshots -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
/// ```
///
/// Each shot is also attached to the test result, so the directory is optional.
///
/// On a simulator that is not signed in yet, also pass `TEST_RUNNER_SCREENSHOT_EMAIL` and
/// `TEST_RUNNER_SCREENSHOT_PASSWORD`; the test signs in through the welcome screen first.
final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var shotNumber = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testCaptureProductPageScreens() {
        signInIfNeeded()
        dismissSystemAlert()
        let albumsTab = tab("Albums")
        XCTAssertTrue(albumsTab.waitForExistence(timeout: 20), "Not signed in? No Albums tab.")
        dismissSystemAlert()
        settle(4)
        shoot("albums")

        let firstAlbum = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(firstAlbum.waitForExistence(timeout: 10))
        firstAlbum.tap()
        settle(4)
        shoot("album-grid")

        chooseFromAlbumMenu("By Day & Place")
        settle(3)
        shoot("album-days")

        chooseFromAlbumMenu("Map")
        settle(12)
        shoot("album-map")

        chooseFromAlbumMenu("Grid")
        settle(2)
        tapGridPhoto(1)
        settle(5)
        shoot("photo")
        app.swipeDown(velocity: .fast)
        settle(2)

        chooseFromAlbumMenu("Present")
        settle(5)
        shoot("present")
        dismissPresentation()

        app.buttons["BackButton"].tap()
        settle(1)
        tab("Options").tap()
        settle(3)
        shoot("options")
    }

    // MARK: - Helpers

    @MainActor
    private func chooseFromAlbumMenu(_ title: String) {
        let menu = app.buttons["Album actions"]
        guard menu.waitForExistence(timeout: 5) else {
            XCTFail("No album menu for \(title)")
            return
        }
        menu.tap()
        let item = app.buttons[title]
        guard item.waitForExistence(timeout: 5) else {
            XCTFail("No menu item \(title)")
            dump("menu-\(title)")
            return
        }
        item.tap()
    }

    @MainActor
    private func dismissPresentation() {
        for label in ["Close", "Done", "xmark", "Exit"] where app.buttons[label].exists {
            app.buttons[label].tap()
            settle(1)
            return
        }
        app.swipeDown(velocity: .fast)
        settle(1)
    }

    @MainActor
    private func signInIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        let signIn = app.buttons["SIGN IN"].firstMatch
        guard signIn.waitForExistence(timeout: 8),
              let email = env["SCREENSHOT_EMAIL"], let password = env["SCREENSHOT_PASSWORD"]
        else { return }
        signIn.tap()
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["Sign In"].tap()
        settle(5)
    }

    /// First launch asks for notifications. That prompt belongs to SpringBoard, not the app, so
    /// `app.alerts` never sees it.
    @MainActor
    private func dismissSystemAlert() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            alert.buttons["Allow"].tap()
            settle(1)
        }
    }

    /// A tab bar on iPhone; on iPad the same tabs are buttons in a strip at the top.
    @MainActor
    private func tab(_ name: String) -> XCUIElement {
        let barButton = app.tabBars.buttons[name]
        return barButton.exists ? barButton : app.buttons[name].firstMatch
    }

    /// Taps the grid photo at `index` by position: the grid's images are wider than their
    /// clipped cells, so the element's own centre can land on the neighbour.
    @MainActor
    private func tapGridPhoto(_ index: Int) {
        let image = app.scrollViews.images.element(boundBy: index)
        guard image.waitForExistence(timeout: 5) else {
            XCTFail("No grid photo \(index)")
            return
        }
        let columns = max(1, Int((app.frame.width / max(image.frame.height, 1)).rounded(.down)))
        let cell = app.frame.width / CGFloat(columns)
        let x = cell * (CGFloat(index % columns) + 0.5)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: image.frame.midY))
            .tap()
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func shoot(_ name: String) {
        shotNumber += 1
        let fileName = String(format: "%02d-%@", shotNumber, name)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(fileName).png")
            try? png.write(to: url)
            try? app.debugDescription.write(
                to: url.deletingPathExtension().appendingPathExtension("txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    }

    @MainActor
    private func dump(_ name: String) {
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? app.debugDescription.write(
                to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    }
}
