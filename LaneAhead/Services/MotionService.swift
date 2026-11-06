import Foundation
import CoreMotion
import Combine

@MainActor
final class MotionService: ObservableObject {
    @Published private(set) var g = GState()
    @Published private(set) var compass = CompassState()
    @Published private(set) var level = LevelState()
    private let manager = CMMotionManager()
    private var gEngine = DrivingGEngine()
    private var compassEngine = CompassEngine()
    private var levelEngine = LevelEngine()
    private var owners = Set<String>()
    private var foreground = true
    private var generation = 0
    private var tick: Timer?
    private var lastStamp = 0.0
    private var publishedAt = 0.0

    func start(_ owner: String) {
        guard owners.insert(owner).inserted else { return }
        gEngine.resetPeaks()
        if !manager.isDeviceMotionActive && foreground { subscribe() }
    }
    func stop(_ owner: String) {
        owners.remove(owner)
        if owners.isEmpty { release(); gEngine.pause("测量已结束"); publish() }
    }
    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        if value { if !owners.isEmpty { subscribe() } }
        else {
            release(); gEngine.pause("后台暂停测量"); compassEngine.invalidate("后台暂停指南针")
            levelEngine.invalidate("后台暂停水平仪"); publish()
        }
    }
    func calibrate() { gEngine.calibrate(); publish() }
    func resetPeaks() { gEngine.resetPeaks(); publish() }

    private func subscribe() {
        guard manager.isDeviceMotionAvailable else {
            gEngine.unavailable(); compassEngine.invalidate("此设备没有可用的磁场传感器")
            levelEngine.invalidate("此设备没有可用的重力传感器"); publish(); return
        }
        generation += 1
        let session = generation
        lastStamp = 0; publishedAt = 0; gEngine.activate(resetPeaks: false)
        manager.deviceMotionUpdateInterval = 0.02
        manager.showsDeviceMovementDisplay = true
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] sample, error in
            guard let self, self.generation == session, self.foreground, !self.owners.isEmpty else { return }
            guard let sample, error == nil else { self.gEngine.unavailable(); self.publish(); return }
            let stamp = sample.timestamp
            guard stamp.isFinite, stamp > self.lastStamp, abs(ProcessInfo.processInfo.systemUptime - stamp) < 0.5 else { return }
            self.lastStamp = stamp
            let gravity = Vector3(x: -sample.gravity.x * 9.80665, y: -sample.gravity.y * 9.80665, z: -sample.gravity.z * 9.80665)
            let linear = Vector3(x: sample.userAcceleration.x * 9.80665, y: sample.userAcceleration.y * 9.80665, z: sample.userAcceleration.z * 9.80665)
            self.gEngine.updateGravity(gravity, at: stamp); self.gEngine.sample(linear, at: stamp)
            if self.owners.contains("tools") {
                let field = sample.magneticField.field
                self.compassEngine.sample(magnetic: Vector3(x: field.x, y: field.y, z: field.z), up: gravity,
                    accuracy: Int(sample.magneticField.accuracy.rawValue) + 1, at: stamp)
                self.levelEngine.sample(up: gravity, at: stamp)
            }
            if stamp - self.publishedAt >= 0.1 { self.publishedAt = stamp; self.publish() }
        }
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == session else { return }
                let now = ProcessInfo.processInfo.systemUptime
                self.gEngine.tick(now); self.compassEngine.tick(now); self.levelEngine.tick(now); self.publish()
            }
        }
    }
    private func release() {
        generation += 1; manager.stopDeviceMotionUpdates(); tick?.invalidate(); tick = nil
    }
    private func publish() { g = gEngine.state; compass = compassEngine.state; level = levelEngine.state }
}
