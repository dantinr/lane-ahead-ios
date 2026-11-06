import XCTest
@testable import LaneAheadCore

final class MotionTests: XCTestCase {
    func calibrated() -> DrivingGEngine {
        let engine = DrivingGEngine(); engine.activate(resetPeaks: true); engine.calibrate()
        for i in 0...105 {
            let time = 1 + Double(i) * 0.02
            engine.updateGravity(Vector3(x: 0, y: 9.80665, z: 0), at: time); engine.sample(.zero, at: time)
        }
        return engine
    }
    func testStationaryCalibrationAndKnownAcceleration() {
        let engine = calibrated(); XCTAssertTrue(engine.state.calibrated)
        for i in 1...100 {
            let time = 3.1 + Double(i) * 0.02
            engine.updateGravity(Vector3(x: 0, y: 9.80665, z: 0), at: time)
            engine.sample(Vector3(x: 0.3 * 9.80665, y: 0, z: -0.4 * 9.80665), at: time)
        }
        XCTAssertEqual(engine.state.longitudinal, 0.4, accuracy: 0.001)
        XCTAssertEqual(engine.state.lateral, 0.3, accuracy: 0.001); XCTAssertEqual(engine.state.total, 0.5, accuracy: 0.001)
    }
    func testFlatPhoneRefusesDrivingCalibration() {
        let engine = DrivingGEngine(); engine.activate(resetPeaks: true); engine.calibrate()
        for i in 0...105 {
            let time = 1 + Double(i) * 0.02
            engine.updateGravity(Vector3(x: 0, y: 0, z: 9.80665), at: time); engine.sample(.zero, at: time)
        }
        XCTAssertFalse(engine.state.calibrated)
    }
    func testMovementPreventsStationaryCalibration() {
        let engine = DrivingGEngine(); engine.activate(resetPeaks: true); engine.calibrate()
        for i in 0...105 {
            let time = 1 + Double(i) * 0.02
            engine.updateGravity(Vector3(x: 0, y: 9.80665, z: 0), at: time)
            engine.sample(Vector3(x: 1, y: 0, z: 0), at: time)
        }
        XCTAssertFalse(engine.state.calibrated)
    }
    func testStaleAndTiltedPoseInvalidateG() {
        let engine = calibrated(); engine.tick(4); XCTAssertFalse(engine.state.valid)
        engine.updateGravity(Vector3(x: 9.80665, y: 0, z: 0), at: 5)
        XCTAssertFalse(engine.state.calibrated)
    }
    func testPauseRetainsCalibrationAndPeaks() {
        let engine = calibrated(); engine.pause("后台"); engine.activate(resetPeaks: false)
        XCTAssertTrue(engine.state.calibrated); XCTAssertFalse(engine.state.valid)
    }
    func testCompassNorthAndShortestWrap() {
        let engine = CompassEngine(), up = Vector3(x: 0, y: 0, z: 9.80665)
        engine.sample(magnetic: Vector3(x: 0, y: 50, z: 0), up: up, accuracy: 3, at: 1)
        XCTAssertEqual(engine.state.heading, 0, accuracy: 0.01)
        func field(_ h: Double) -> Vector3 { Vector3(x: -sin(h * .pi / 180) * 50, y: cos(h * .pi / 180) * 50, z: 0) }
        let wrap = CompassEngine(); wrap.sample(magnetic: field(350), up: up, accuracy: 3, at: 1)
        let before = wrap.state.rotation
        wrap.sample(magnetic: field(10), up: up, accuracy: 3, at: 1.05)
        XCTAssertLessThan(abs(wrap.state.rotation - before), 20)
    }
    func testCompassBadAccuracyAndFieldRemoved() {
        let engine = CompassEngine()
        engine.sample(magnetic: Vector3(x: 0, y: 50, z: 0), up: Vector3(x: 0,y: 0,z: 9.8), accuracy: 0, at: 1)
        XCTAssertFalse(engine.state.valid)
        engine.sample(magnetic: Vector3(x: 0, y: 200, z: 0), up: Vector3(x: 0,y: 0,z: 9.8), accuracy: 3, at: 2)
        XCTAssertFalse(engine.state.valid)
    }
    func testLevelFlatTiltAndBubbleClamp() {
        let engine = LevelEngine(); engine.sample(up: Vector3(x: 0,y: 0,z: 9.80665), at: 1)
        XCTAssertTrue(engine.state.level); XCTAssertEqual(engine.state.tilt, 0, accuracy: 0.01)
        engine.sample(up: Vector3(x: 9.80665 / sqrt(2),y: 0,z: 9.80665 / sqrt(2)), at: 2)
        XCTAssertEqual(engine.state.tilt, 45, accuracy: 0.01); XCTAssertEqual(engine.state.bubbleX, 1, accuracy: 0.01)
    }
    func testFaceDownAndStaleLevelRemoved() {
        let engine = LevelEngine(); engine.sample(up: Vector3(x: 0,y: 0,z: -9.80665), at: 1)
        XCTAssertFalse(engine.state.valid)
        engine.sample(up: Vector3(x: 0,y: 0,z: 9.80665), at: 2); engine.tick(3); XCTAssertFalse(engine.state.valid)
    }
    func testCarRPMAndFrames() {
        XCTAssertEqual(CarSpin.rpm(speed: 1), 0); XCTAssertEqual(CarSpin.rpm(speed: 30), 7.5)
        XCTAssertEqual(CarSpin.rpm(speed: 120), 30); XCTAssertEqual(CarSpin.rpm(speed: 300), 30)
        XCTAssertEqual(CarSpin.rpm(speed: .nan), 0); XCTAssertEqual(CarSpin.frame(angle: 360), 0)
    }
}
