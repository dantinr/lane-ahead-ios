import Foundation

struct Vector3: Equatable, Sendable {
    var x = 0.0, y = 0.0, z = 0.0
    static let zero = Vector3()
    var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    var length: Double { sqrt(dot(self)) }
    func dot(_ b: Vector3) -> Double { x * b.x + y * b.y + z * b.z }
    func scaled(_ a: Double) -> Vector3 { Vector3(x: x * a, y: y * a, z: z * a) }
    func adding(_ b: Vector3) -> Vector3 { Vector3(x: x + b.x, y: y + b.y, z: z + b.z) }
    func minus(_ b: Vector3) -> Vector3 { adding(b.scaled(-1)) }
    func cross(_ b: Vector3) -> Vector3 { Vector3(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }
    func horizontal(up: Vector3) -> Vector3 { minus(up.scaled(dot(up))) }
}

struct GState: Sendable {
    var available = true, running = false, calibrated = false, calibrating = false, valid = false
    var status = "固定手机，停车后校准"
    var longitudinal = 0.0, lateral = 0.0, total = 0.0
    var peakAcceleration = 0.0, peakBraking = 0.0, peakLateral = 0.0, peakTotal = 0.0
    var calibrationProgress = 0.0
}

final class DrivingGEngine {
    private(set) var state = GState()
    private var gravity = Vector3.zero, bias = Vector3.zero, sum = Vector3.zero, gravitySum = Vector3.zero
    private var forward = Vector3.zero, right = Vector3.zero, calibrationGravity = Vector3.zero
    private var up: Vector3?
    private var gravityAt = 0.0, sampleAt = 0.0, calibrationAt = 0.0, squares = 0.0
    private var samples = 0
    private var filteredForward = 0.0, filteredRight = 0.0
    func activate(resetPeaks: Bool) {
        pause(up == nil ? "固定手机，停车后校准" : "等待传感器更新")
        state.available = true; state.running = true
        if resetPeaks { self.resetPeaks() }
    }
    func pause(_ status: String) {
        state.valid = false; state.running = false; state.calibrating = false; state.status = status
        gravityAt = 0; sampleAt = 0; filteredForward = 0; filteredRight = 0; resetSamples()
    }
    func unavailable() { pause("传感器不可用"); state.available = false }
    func resetPeaks() { state.peakAcceleration = 0; state.peakBraking = 0; state.peakLateral = 0; state.peakTotal = 0 }
    func calibrate() {
        guard state.running && state.available else { return }
        up = nil; state.calibrated = false; state.valid = false; state.calibrating = true
        state.status = "保持静止约 2 秒"; resetSamples()
    }
    private func resetSamples() {
        sum = .zero; gravitySum = .zero; squares = 0; samples = 0; calibrationAt = 0; state.calibrationProgress = 0
    }
    // Input gravity points UP in device axes. The CoreMotion adapter negates
    // CMDeviceMotion.gravity (which points DOWN) before calling this method.
    func updateGravity(_ value: Vector3, at now: Double) {
        guard state.running, now.isFinite, now > gravityAt, value.finite, (7...12).contains(value.length) else { return }
        gravity = value; gravityAt = now
        if let up, value.scaled(1 / value.length).dot(up) < cos(.pi / 12) {
            self.up = nil; state.calibrated = false; state.valid = false; state.status = "姿态变化较大，请停车重新校准"
        }
    }
    func sample(_ value: Vector3, at now: Double) {
        guard state.running, now.isFinite, now > sampleAt else { return }
        let gap = sampleAt > 0 ? now - sampleAt : 0.02
        sampleAt = now
        guard value.finite, gravityAt > 0, (0...0.2).contains(now - gravityAt) else {
            state.valid = false; filteredForward = 0; filteredRight = 0; resetSamples()
            state.status = "传感器数据暂不可用"; return
        }
        if gap > 0.5 { filteredForward = 0; filteredRight = 0; resetSamples() }
        if state.calibrating { calibrationSample(value, at: now); return }
        guard up != nil else { state.valid = false; return }
        let linear = value.minus(bias)
        let alpha = 1 - exp(-min(gap, 0.05) / 0.15)
        filteredForward += alpha * (linear.dot(forward) / 9.80665 - filteredForward)
        filteredRight += alpha * (linear.dot(right) / 9.80665 - filteredRight)
        state.longitudinal = abs(filteredForward) < 0.008 ? 0 : filteredForward
        state.lateral = abs(filteredRight) < 0.008 ? 0 : filteredRight
        state.total = hypot(filteredForward, filteredRight)
        state.peakAcceleration = max(state.peakAcceleration, filteredForward)
        state.peakBraking = max(state.peakBraking, -filteredForward)
        state.peakLateral = max(state.peakLateral, abs(filteredRight)); state.peakTotal = max(state.peakTotal, state.total)
        state.valid = true; state.status = "水平 G 值 · 仅供参考"
    }
    private func calibrationSample(_ value: Vector3, at now: Double) {
        let unit = gravity.scaled(1 / gravity.length)
        if value.length > 0.35 || (samples > 0 && unit.dot(calibrationGravity) < cos(.pi / 60)) {
            resetSamples(); state.status = "检测到移动，请保持静止"; return
        }
        if samples == 0 { calibrationAt = now; calibrationGravity = unit }
        sum = sum.adding(value); gravitySum = gravitySum.adding(gravity)
        squares += value.dot(value); samples += 1
        state.calibrationProgress = min(1, (now - calibrationAt) / 2)
        guard now - calibrationAt >= 2, samples >= 40 else { return }
        let bias = sum.scaled(1 / Double(samples))
        guard squares / Double(samples) - bias.dot(bias) <= 0.02 else {
            resetSamples(); state.status = "振动较大，请停车后重试"; return
        }
        let up = gravitySum.scaled(1 / gravitySum.length)
        let projected = Vector3(x: 0, y: 0, z: -1).horizontal(up: up)
        guard projected.length >= 0.5 else {
            state.calibrating = false; resetSamples(); state.status = "手机勿平放，屏幕朝向车尾后重试"; return
        }
        self.up = up; forward = projected.scaled(1 / projected.length); right = forward.cross(up)
        self.bias = bias; filteredForward = 0; filteredRight = 0
        state.calibrated = true; state.calibrating = false; state.valid = true; state.calibrationProgress = 1
        state.longitudinal = 0; state.lateral = 0; state.total = 0; state.status = "校准完成 · 水平 G 值"
    }
    func tick(_ now: Double) {
        if state.running && (sampleAt == 0 || now - sampleAt > 0.5 || gravityAt == 0 || now - gravityAt > 0.5) {
            state.valid = false; filteredForward = 0; filteredRight = 0; resetSamples(); state.status = "等待传感器更新"
        }
    }
}

struct CompassState: Sendable {
    var valid = false
    var heading = 0.0, rotation = 0.0
    var direction = "", reference = "", status = "等待磁场数据"
}
final class CompassEngine {
    private(set) var state = CompassState()
    private var filtered = 0.0, sampleAt = 0.0
    private var mounted = false
    private func degrees(_ x: Double) -> Double { (x.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
    func invalidate(_ message: String = "方向数据已过期") { state.valid = false; state.status = message }
    func sample(magnetic: Vector3, up: Vector3, accuracy: Int, at now: Double) {
        guard now.isFinite, now > sampleAt else { return }
        let gap = sampleAt > 0 ? now - sampleAt : 0.05; sampleAt = now
        guard up.finite, (7...12).contains(up.length), magnetic.finite,
              (1...3).contains(accuracy), (10...100).contains(magnetic.length) else {
            invalidate("磁场不可靠，请远离磁铁并画 8 字校准"); return
        }
        let unitUp = up.scaled(1 / up.length)
        let north = magnetic.horizontal(up: unitUp)
        guard north.length >= 5 else { invalidate("水平磁场过弱，请调整位置"); return }
        let unitNorth = north.scaled(1 / north.length), east = north.scaled(1 / north.length).cross(unitUp)
        let screen = Vector3(x: 0, y: 0, z: -1).horizontal(up: unitUp)
        let nextMounted = screen.length > 0.75 ? true : screen.length < 0.55 ? false : mounted
        let forward = nextMounted ? screen : Vector3(x: 0, y: 1, z: 0).horizontal(up: unitUp)
        guard forward.length >= 0.4 else { invalidate("请调整手机姿态"); return }
        let heading = degrees(atan2(forward.dot(east), forward.dot(unitNorth)) * 180 / .pi)
        if !state.valid || gap > 0.5 || nextMounted != mounted { filtered = heading }
        else { filtered += (degrees(heading - filtered + 180) - 180) * (1 - exp(-min(gap, 0.1) / 0.18)) }
        mounted = nextMounted; state.heading = degrees(filtered); state.rotation = -filtered
        state.direction = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"][Int((state.heading + 22.5) / 45) % 8]
        state.reference = mounted ? "屏幕朝向车尾时，按车头方向" : "平放时，按手机顶端方向"
        state.status = accuracy == 1 ? "磁北 · 精度较低，可画 8 字校准" : "磁北 · 远离磁吸支架与金属干扰"
        state.valid = true
    }
    func tick(_ now: Double) { if now - sampleAt > 0.5 { invalidate() } }
}

struct LevelState: Sendable {
    var valid = false, level = false
    var roll = 0.0, pitch = 0.0, tilt = 0.0, bubbleX = 0.0, bubbleY = 0.0
    var status = "请将手机屏幕朝上"
}
final class LevelEngine {
    private(set) var state = LevelState()
    private var filtered = Vector3.zero, sampleAt = 0.0
    func invalidate(_ message: String = "姿态数据已过期") { state.valid = false; state.level = false; state.status = message }
    func sample(up: Vector3, at now: Double) {
        guard now.isFinite, now > sampleAt else { return }
        let gap = sampleAt > 0 ? now - sampleAt : 0.05; sampleAt = now
        guard up.finite, (7...12).contains(up.length), up.z >= 0 else { invalidate("请将手机屏幕朝上并保持稳定"); return }
        let unit = up.scaled(1 / up.length)
        if !state.valid || gap > 0.5 { filtered = unit }
        else { filtered = filtered.adding(unit.minus(filtered).scaled(1 - exp(-min(gap, 0.1) / 0.15))) }
        let v = filtered.scaled(1 / filtered.length), z = max(0, min(1, filtered.z / filtered.length))
        state.roll = atan2(v.x, hypot(v.y, z)) * 180 / .pi
        state.pitch = atan2(v.y, hypot(v.x, z)) * 180 / .pi; state.tilt = acos(z) * 180 / .pi
        let horizontal = hypot(v.x, v.y), travel = min(1, state.tilt / 15)
        state.bubbleX = horizontal > 0 ? v.x / horizontal * travel : 0
        state.bubbleY = horizontal > 0 ? -v.y / horizontal * travel : 0
        state.level = state.tilt <= 1; state.valid = true
        state.status = state.level ? "接近水平（总倾角 ≤ 1°）" : "气泡移向较高的一侧"
    }
    func tick(_ now: Double) { if now - sampleAt > 0.5 { invalidate() } }
}

enum CarSpin {
    static func rpm(speed: Double) -> Double { speed.isFinite && speed >= 2 ? min(30, speed / 4) : 0 }
    static func frame(angle: Double) -> Int { Int((angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 5) % 72 }
}
