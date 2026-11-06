import XCTest

final class LaneAheadUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testDemoPreviewSwitchAndUnknownData() {
        let app = XCUIApplication(); app.launch()
        let demo = app.buttons["home.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10)); demo.tap()
        XCTAssertTrue(app.staticTexts["车道演示"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["虚构演示"].firstMatch.exists)
        app.buttons["3 个"].tap(); XCTAssertTrue(app.buttons["2 个"].exists)
        let missing = app.switches["演示缺少车道数据"]
        if !missing.isHittable { app.swipeUp() }
        missing.tap()
        XCTAssertTrue(app.staticTexts["暂无车道数据"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "lane-preview-demo"; shot.lifetime = .keepAlways; add(shot)
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
