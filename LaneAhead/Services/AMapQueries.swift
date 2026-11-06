import Foundation

@MainActor
private final class QueryHandle {
    let query = LAPlaceQuery()
    var timeout: Timer?
    var continuation: CheckedContinuation<[[String: Any]], Error>?
    func complete(_ results: [[String: Any]]?, _ message: String?) {
        timeout?.invalidate(); timeout = nil
        guard let continuation else { return }
        self.continuation = nil
        if let message { continuation.resume(throwing: SearchError.message(message)) }
        else { continuation.resume(returning: results ?? []) }
    }
}

@MainActor
enum AMapQueries {
    private static func run(_ start: (LAPlaceQuery, @escaping @Sendable ([[String: Any]]?, String?) -> Void) -> Void) async throws -> [[String: Any]] {
        try Task.checkCancellation()
        let handle = QueryHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                handle.continuation = continuation
                let completion: @Sendable ([[String: Any]]?, String?) -> Void = { results, message in
                    Task { @MainActor in handle.complete(results, message) }
                }
                handle.timeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { _ in
                    Task { @MainActor in handle.query.cancel() }
                }
                start(handle.query, completion)
            }
        } onCancel: {
            Task { @MainActor in handle.query.cancel() }
        }
    }
    static func search(keyword: String, city: String) async throws -> [Place] {
        let values = try await run { query, completion in query.search(keyword: keyword, city: city, completion: completion) }
        let data = try JSONSerialization.data(withJSONObject: values)
        return try JSONDecoder().decode([Place].self, from: data).filter { $0.coordinate.valid }
    }
    static func city(at coordinate: Coordinate) async throws -> String {
        let values = try await run { query, completion in
            query.reverse(latitude: coordinate.latitude, longitude: coordinate.longitude, completion: completion)
        }
        guard let city = values.first?["city"] as? String, !city.isEmpty else {
            throw SearchError.message("尚未识别城市，请手动填写搜索范围")
        }
        return city
    }
}
