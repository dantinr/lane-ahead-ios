import XCTest

final class LaneAheadUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testCurrentStripAndTwoUpcomingSlots() {
        let app = XCUIApplication(); app.launch()
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["home.demo"].exists)
        XCTAssertFalse(app.staticTexts["体验前方车道"].exists)
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "home"; home.lifetime = .keepAlways; add(home)
        settings.tap()
        app.buttons["settings.demo"].tap()
        XCTAssertTrue(app.staticTexts["车道演示"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["虚构演示"].firstMatch.exists)
        let current = app.descendants(matching: .any)["lane.hint.current"]
        let next = app.descendants(matching: .any)["lane.hint.2"]
        let later = app.descendants(matching: .any)["lane.hint.3"]
        XCTAssertTrue(current.exists); XCTAssertTrue(next.exists); XCTAssertTrue(later.exists)
        XCTAssertLessThan(current.frame.maxY, next.frame.minY)
        XCTAssertLessThan(next.frame.maxY, later.frame.minY)
        XCTAssertEqual(next.frame.midX, later.frame.midX, accuracy: 1)
        XCTAssertTrue((next.value as? String ?? "").contains("760 米"))
        XCTAssertTrue((later.value as? String ?? "").contains("1.2 公里"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "lane-preview-demo"; shot.lifetime = .keepAlways; add(shot)
        let missing = app.switches["演示缺少车道数据"]
        // Move the whole control above the floating tab bar before tapping.
        app.swipeUp()
        missing.tap()
        XCTAssertTrue((next.value as? String ?? "").contains("暂无车道数据"))
        XCTAssertFalse((later.value as? String ?? "").contains("暂无车道数据"))
        app.buttons["下一引导点"].tap()
        XCTAssertTrue((next.value as? String ?? "").contains("青禾街"))
        XCTAssertTrue((later.value as? String ?? "").contains("星河路"))
    }
    @MainActor func testToolsAndLocalHistoryAreAvailableWithoutMapKey() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["驾驶工具"].tap()
        XCTAssertTrue(app.staticTexts["驾驶 G 值"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tools.calibrate"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "driving-tools"; shot.lifetime = .keepAlways; add(shot)
        app.tabBars.buttons["我的"].tap()
        app.buttons["my.trips"].tap()
        XCTAssertTrue(app.staticTexts["还没有导航历史"].waitForExistence(timeout: 5))
    }
}
