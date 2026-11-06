import SwiftUI
import Combine
import CoreLocation

@MainActor
final class AppModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var consent = UserDefaults.standard.bool(forKey: "locationConsent")
    @Published private(set) var ready = false
    @Published var message = ""
    @Published private(set) var locationStatus = "等待定位授权"
    @Published private(set) var city = ""
    @Published private(set) var origin: Coordinate?
    @Published var destination: Place?
    @Published private(set) var snapshot = LocalSnapshot()
    @Published private(set) var storageError = ""
    @Published var showNavigation = false
    @Published private(set) var navigation: LANavigationBridge?
    @Published private(set) var routes: [RouteChoice] = []
    @Published private(set) var selectedRoute: Int?
    @Published private(set) var planning = false
    @Published private(set) var starting = false
    @Published private(set) var navigating = false
    @Published private(set) var arrived = false
    @Published private(set) var preview: [PreviewRow] = []
    @Published private(set) var liveLanes: [Lane] = []
    @Published private(set) var previewStatus = "等待导航"
    @Published private(set) var diagnostics = Diagnostics()
    @Published private(set) var remaining = 0.0
    @Published private(set) var seconds = 0.0
    @Published private(set) var speed = 0.0
    @Published private(set) var plannedFromSpecifiedOrigin = false
    @Published var previewCount = 3 { didSet { publish() } }
    let motion = MotionService()
    let repository: LocalRepository
    private(set) var map: LAMapBridge?
    private let permissions = CLLocationManager()
    private var engine = LaneEngine()
    private var key = ""
    private var homeVisible = true
    private var foreground = true
    private var generation = 0
    private var cityTask: Task<Void, Never>?
    private var cityGeneration = 0
    private var cityAttempted = false
    private var timer: Timer?
    private var timeout: Task<Void, Never>?
    private var trip: Trip?
    private var pending: [LaneMutation] = []
    private var saving = false
    private var lastDiagnosticSave = Date.distantPast
    private var writeRetry: Task<Void, Never>?
    private var writeFailures = 0
    private var originReceivedAt = Date.distantPast
    private var desiredDestination: Place?

    var hasKey: Bool { key.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil }
    var canSearch: Bool { ready }
    var canNavigate: Bool {
        ready && origin != nil && Date().timeIntervalSince(originReceivedAt) <= 120 && destination != nil &&
        [.authorizedAlways, .authorizedWhenInUse].contains(permissions.authorizationStatus) && permissions.accuracyAuthorization == .fullAccuracy
    }
    var platformMessage: String {
        !hasKey ? "地图服务尚未配置，先体验车道演示与驾驶工具。" : !LAPlatform.isSupported() ?
            "真实地图和导航请在 iPhone 上运行，模拟器可体验演示和本地功能。" : "同意定位后，从当前位置开始导航。"
    }

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LaneAhead", isDirectory: true)
        repository = LocalRepository(directory: base)
        if let url = Bundle.main.url(forResource: "MapKeys", withExtension: "plist"),
           let data = try? Data(contentsOf: url), let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
            key = values["AMapIOSKey"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        super.init()
        permissions.delegate = self
        Task { await refresh() }
    }

    func refresh() async {
        snapshot = await repository.snapshot()
        if !navigating { diagnostics = snapshot.diagnostics }
    }
    func agree() {
        consent = true; UserDefaults.standard.set(true, forKey: "locationConsent"); initializeMap()
    }
    func initializeMap() {
        guard foreground else { return }
        guard consent, hasKey, LAPlatform.isSupported() else { locationStatus = platformMessage; return }
        switch permissions.authorizationStatus {
        case .notDetermined: permissions.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard permissions.accuracyAuthorization == .fullAccuracy else {
                map?.setActive(false); origin = nil; city = ""; cancelCity()
                engine.suspend("定位精度不足，暂停车道采集", at: Date())
                locationStatus = "请在系统设置中开启精确位置，导航需要可靠定位"; return
            }
            guard CLLocationManager.locationServicesEnabled() else { locationStatus = "系统定位已关闭"; return }
            if !ready {
                LAPlatform.configure(key: key)
                let map = LAMapBridge()
                map.eventHandler = { [weak self] event, values in
                    Task { @MainActor in self?.mapEvent(event, values) }
                }
                self.map = map; ready = true
            }
            map?.setActive(homeVisible && foreground); locationStatus = "正在定位当前位置…"
        default: locationStatus = "位置权限未开启，请在 iPhone 设置中允许精确位置"
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }
    private func authorizationChanged() {
        if [.authorizedAlways, .authorizedWhenInUse].contains(permissions.authorizationStatus) { initializeMap() }
        else if permissions.authorizationStatus != .notDetermined {
            map?.setActive(false); origin = nil; city = ""; cancelCity(); cityAttempted = false
            engine.suspend("位置权限未开启，暂停车道采集", at: Date())
            locationStatus = "位置权限未开启，请前往系统设置"
        }
    }
    func homeVisibility(_ value: Bool) {
        homeVisible = value; map?.setActive(value && foreground && ready)
        if !value { cancelCity() }
    }
    func recenter() {
        cancelCity(); city = ""; origin = nil; cityAttempted = false
        initializeMap(); map?.recenter()
    }
    func select(_ place: Place) {
        guard place.coordinate.valid else { return }
        destination = place; map?.select(latitude: place.latitude, longitude: place.longitude, name: place.name)
    }
    private func cancelCity() { cityGeneration += 1; cityTask?.cancel(); cityTask = nil }
    private func mapEvent(_ event: String, _ values: [String: Any]) {
        guard homeVisible && foreground else { return }
        if event == "error" { locationStatus = values["message"] as? String ?? "定位失败"; return }
        guard event == "located", let lat = values["latitude"] as? Double, let lon = values["longitude"] as? Double else { return }
        let point = Coordinate(latitude: lat, longitude: lon)
        guard point.valid else { return }
        origin = point; originReceivedAt = Date(); locationStatus = "已定位到当前位置"
        guard city.isEmpty && !cityAttempted else { return }
        cityAttempted = true
        resolveCity(point)
    }
    func resolveCity(_ point: Coordinate? = nil) {
        guard point != nil || Date().timeIntervalSince(originReceivedAt) <= 120 else { return }
        guard ready, let point = point ?? origin else { return }
        cancelCity(); let request = cityGeneration
        cityTask = Task {
            do {
                let value = try await AMapQueries.city(at: point)
                guard !Task.isCancelled, request == cityGeneration else { return }; city = value
            } catch {
                if !Task.isCancelled && request == cityGeneration { message = "未能识别当前城市，可在搜索范围中手动填写" }
            }
        }
    }

    func plan(from start: Place? = nil) {
        guard ready, let destination, destination.coordinate.valid else { message = "请先选择有效目的地"; return }
        if start == nil && !canNavigate { message = "请先重新定位，取得当前位置后再规划"; return }
        closeNavigation()
        generation += 1; let session = generation
        desiredDestination = destination
        plannedFromSpecifiedOrigin = start != nil
        engine = LaneEngine(); engine.begin(history: snapshot.lanes, at: Date())
        routes = []; selectedRoute = nil; arrived = false; planning = true; starting = false; trip = nil
        preview = []; liveLanes = []; message = "正在规划路线…"; showNavigation = true; homeVisibility(false)
        let bridge = LANavigationBridge()
        navigation = bridge
        bridge.eventHandler = { [weak self] event, values in
            Task { @MainActor in
                guard let self, self.generation == session else { return }
                self.navigationEvent(event, values)
            }
        }
        let beginning: [String: Any]? = start.map { ["latitude": $0.latitude, "longitude": $0.longitude] }
        if !bridge.plan(latitude: destination.latitude, longitude: destination.longitude, start: beginning) {
            planning = false; message = "暂时无法规划，请检查位置及地图服务配置"; return
        }
        timeout = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, generation == session, planning else { return }
            planning = false; message = "规划超时，请退出后重试"; bridge.finish()
        }
    }

    func chooseRoute(_ id: Int) {
        guard !navigating, !starting, navigation?.selectRoute(id) == true else { return }
        selectedRoute = id
    }
    func startNavigation() {
        guard !plannedFromSpecifiedOrigin, !planning, !starting, !navigating, selectedRoute != nil, foreground else { return }
        guard let selectedRoute, navigation?.selectRoute(selectedRoute) == true else {
            message = "无法确认所选路线，请返回重新规划"; return
        }
        starting = true; message = "正在启动 GPS 导航…"
        guard navigation?.start() == true else { starting = false; message = "未能启动导航，请返回重试"; return }
        let session = generation
        timeout?.cancel()
        timeout = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, generation == session, starting else { return }
            starting = false; message = "导航启动超时，请退出后重试"; navigation?.finish()
        }
    }
    private func decode<T: Decodable>(_ object: Any?, as type: T.Type) -> T? {
        guard let object, let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func navigationEvent(_ event: String, _ values: [String: Any]) {
        let now = Date()
        switch event {
        case "routes":
            planning = false; timeout?.cancel()
            if !navigating {
                routes = decode(values["routes"], as: [RouteChoice].self) ?? []
                message = routes.isEmpty ? "未取得有效路线，请退出后重试" : "选择路线后开始导航"
                if let first = routes.first { chooseRoute(first.id) }
            }
        case "route":
            guard let id = values["routeID"] as? String,
                let segments = decode(values["segments"], as: [RouteSegment].self) else {
                engine.suspend("路线数据不可用，暂停车道提示", at: now); break
            }
            engine.setRoute(id, points: RouteAdapter.points(segments), at: now)
        case "started":
            guard !navigating, let destination = desiredDestination else { return }
            timeout?.cancel(); starting = false; navigating = true
            let distance = routes.first { $0.id == selectedRoute }?.meters ?? 0
            let record = Trip(destination: String(destination.name.prefix(240)), address: String(destination.address.prefix(500)),
                city: String(destination.city.prefix(80)), startedAt: now, plannedMeters: distance)
            trip = record; storeTrip(record)
            motion.start("navigation"); UIApplication.shared.isIdleTimerDisabled = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.publish(); self?.flushLanes(); self?.persistDiagnostics() }
            }
            message = "GPS 导航中"
        case "progress":
            guard navigating && foreground else { return }
            engine.progress(route: values["routeID"] as? String ?? "", step: values["step"] as? Int ?? -1,
                remaining: values["remaining"] as? Double ?? -1, at: now, realtime: true)
            remaining = values["routeRemaining"] as? Double ?? 0; seconds = values["seconds"] as? Double ?? 0
            speed = values["speed"] as? Double ?? 0
        case "lanes":
            guard navigating && foreground else { return }
            engine.receive(LaneDecoder.decode(background: values["background"] as? String ?? "",
                selection: values["selection"] as? String ?? ""), at: now)
            pending += engine.drainMutations(); flushLanes()
        case "blockedLane": engine.blockedCallback(at: now)
        case "hide": engine.hide(at: now)
        case "suspended": engine.suspend(values["message"] as? String ?? "等待路线更新", at: now)
        case "arrived":
            arrived = true; finishTrip(.arrived); stopTelemetry(); message = "已到达目的地"
        case "stopped": finishTrip(.ended); stopTelemetry(); message = "导航已结束"
        case "close": closeNavigation()
        case "error":
            planning = false; starting = false; timeout?.cancel()
            message = values["message"] as? String ?? "导航服务异常"
            engine.suspend("导航服务异常，暂停采集", at: now)
            if navigating { finishTrip(.failed); stopTelemetry() }
        default: break
        }
        publish()
    }
    func publish() {
        let state = engine.preview(count: previewCount, at: Date())
        preview = state.rows; liveLanes = state.live; previewStatus = state.status; diagnostics = engine.diagnostics
    }
    private func flushLanes() {
        guard !pending.isEmpty, !saving else { return }
        let batch = pending; pending = []; saving = true
        let writer = engine
        Task {
            var succeeded = false
            var canRetry = true
            do {
                try await repository.apply(batch); writer.persisted(true, at: Date()); storageError = ""
                succeeded = true; writeFailures = 0
                await refresh()
            } catch {
                pending = batch + pending; writer.persisted(false, at: Date()); storageError = error.localizedDescription
                writeFailures += 1
                if case LocalDataError.damaged = error { canRetry = false }
            }
            saving = false
            if writer === engine { publish() }
            if succeeded && !pending.isEmpty { flushLanes() }
            else if canRetry && !pending.isEmpty && writeFailures <= 3 {
                writeRetry?.cancel()
                writeRetry = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }; flushLanes()
                }
            }
        }
    }
    private func persistDiagnostics(force: Bool = false) {
        guard engine.diagnostics.startedAt != nil, force || Date().timeIntervalSince(lastDiagnosticSave) >= 5 else { return }
        lastDiagnosticSave = Date(); let data = engine.diagnostics
        Task {
            do { try await repository.saveDiagnostics(data) }
            catch { storageError = error.localizedDescription }
        }
    }
    private func storeTrip(_ record: Trip) {
        Task {
            do { try await repository.putTrip(record); await refresh() }
            catch { storageError = error.localizedDescription }
        }
    }
    private func finishTrip(_ status: TripStatus) {
        guard var record = trip else { return }
        record.finish(status, at: Date()); trip = record; storeTrip(record)
    }
    private func stopTelemetry() {
        navigating = false; starting = false; timer?.invalidate(); timer = nil
        motion.stop("navigation"); UIApplication.shared.isIdleTimerDisabled = false
        engine.finish(at: Date()); flushLanes(); persistDiagnostics(force: true)
    }
    func closeNavigation() {
        finishTrip(.ended); stopTelemetry(); timeout?.cancel(); timeout = nil
        generation += 1; navigation?.finish(); navigation = nil
        showNavigation = false; planning = false; routes = []; selectedRoute = nil
    }
    func setForeground(_ active: Bool) {
        foreground = active; motion.setForeground(active); navigation?.setForeground(active)
        map?.setActive(active && homeVisible && ready)
        if !active {
            cancelCity(); engine.suspend("后台暂停车道采集，返回后等待新定位", at: Date()); persistDiagnostics(force: true)
        } else {
            if consent && !ready { initializeMap() }
            if ready && homeVisible && city.isEmpty { resolveCity() }
            flushLanes()
        }
        publish()
    }
    func clear(_ kind: String) async {
        do {
            try await repository.clear(kind); storageError = ""
            if kind == "lanes" { pending = []; writeRetry?.cancel(); writeFailures = 0 }
            await refresh()
        } catch { storageError = error.localizedDescription }
    }
    func removeTrip(_ id: UUID) async {
        do { try await repository.removeTrip(id); await refresh() } catch { storageError = error.localizedDescription }
    }
    func removeSearch(_ query: String) async {
        do { try await repository.removeSearch(query); await refresh() } catch { storageError = error.localizedDescription }
    }
    func rememberSearch(_ query: String) async {
        do { try await repository.remember(query); await refresh() } catch { storageError = error.localizedDescription }
    }
}
