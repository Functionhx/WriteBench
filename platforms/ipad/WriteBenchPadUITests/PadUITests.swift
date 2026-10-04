import XCTest

final class PadUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
    }
    private func openPage(_ title: String) {
        if !app.staticTexts[title].firstMatch.isHittable {
            let sidebar = app.buttons["Show Sidebar"]
            if sidebar.exists { sidebar.tap() }
        }
        app.staticTexts[title].firstMatch.tap()
    }
    func testWhitespaceKeyboardAndSubmissionPause() {
        let answer = app.textViews["answer-editor"]
        XCTAssertTrue(answer.waitForExistence(timeout: 15)); answer.tap()
        answer.typeText("Notice\n\tBody    text\nUniversity Library")
        XCTAssertTrue((answer.value as? String ?? "").contains("\n    Body    text"))
        app.buttons["开始 / 继续"].tap()
        XCTAssertTrue(app.buttons["暂停"].exists)
        app.buttons["收起键盘"].tap()
        app.buttons["submit"].tap(); app.buttons["快速评阅 · 1 位评审"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["开始 / 继续"].exists)
        let first = app.staticTexts["elapsed"].label
        sleep(2)
        XCTAssertEqual(app.staticTexts["elapsed"].label, first)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "iPad-writing-landscape"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testLibrarySelectsFullPrompt() {
        openPage("题库")
        let row = app.descendants(matching: .any).matching(identifier: "bank-question").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["use-question"].waitForExistence(timeout: 5))
        app.buttons["use-question"].tap()
        let question = app.textViews["question-editor"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertGreaterThan((question.value as? String ?? "").count, 100)
    }
    func testHandwritingCanvasAndClearConfirmation() {
        app.segmentedControls.buttons["手写纸"].tap()
        let canvas = app.descendants(matching: .any).matching(identifier: "handwriting-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let first = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25))
        let second = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.35))
        first.press(forDuration: 0.1, thenDragTo: second)
        XCTAssertTrue(app.buttons["识别并校对手写"].isEnabled)
        app.buttons["清空"].tap(); XCTAssertTrue(app.buttons["清空笔迹"].waitForExistence(timeout: 3)); app.buttons["清空笔迹"].tap()
        XCTAssertFalse(app.buttons["识别并校对手写"].isEnabled)
    }
    func testOCRRequiresReviewBeforeFillingQuestion() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ocr-review-testing"]; app.launch()
        let confirm = app.buttons["确认填入"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(confirm.isEnabled)
        let toggle = app.switches["我已对照原图核对所有页面"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue((app.textViews["question-editor"].value as? String ?? "").contains("Dear Alex"))
    }
    func testBackgroundPausesTimerAndKeepsDraft() {
        let editor = app.textViews["answer-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Draft survives background")
        app.buttons["收起键盘"].tap(); app.buttons["开始 / 继续"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["开始 / 继续"].waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("Draft survives background"))
    }
    func testPortraitNavigationAndSettings() {
        XCUIDevice.shared.orientation = .portrait
        openPage("设置")
        XCTAssertTrue(app.secureTextFields["api-key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["导出备份到文件"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "iPad-settings-portrait"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
