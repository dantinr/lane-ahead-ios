import Foundation

struct SearchScope: Equatable, Sendable {
    var keyword: String
    var city: String
    var explicit: Bool
    static func resolve(_ query: String, defaultCity: String) throws -> SearchScope {
        let query = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !query.isEmpty else { throw SearchError.message("请输入地点名称或地址") }
        var match: (name: String, prefix: String)?
        for city in CityIndex.names {
            let short = city.hasSuffix("市") ? String(city.dropLast()) : city
            let prefix = query.hasPrefix(city) ? city : (query == short || query.hasPrefix(short + " ")) ? short : ""
            if !prefix.isEmpty && prefix.count > (match?.prefix.count ?? 0) { match = (city, prefix) }
        }
        if let match {
            let keyword = String(query.dropFirst(match.prefix.count)).trimmingCharacters(in: .whitespaces)
            return SearchScope(keyword: keyword.isEmpty ? match.name : keyword, city: match.name, explicit: true)
        }
        let city = defaultCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { throw SearchError.message("尚未识别当前城市，请填写搜索范围或在关键词前加城市") }
        return SearchScope(keyword: query, city: city, explicit: false)
    }
}

enum SearchError: LocalizedError { case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct SearchOutcome: Sendable {
    var places: [Place]
    var city: String
    var explicit: Bool
    var fallback = false
    var checked = 0
    var matched = false
    var warning = ""
}

enum SearchLogic {
    static func normalized(_ value: String) -> String { value.lowercased().filter { !$0.isWhitespace } }
    static func knownCity(_ value: String) -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return CityIndex.names.first { $0 == name || ($0.hasSuffix("市") && String($0.dropLast()) == name) } ?? ""
    }
    static func city(of trip: Trip) -> String {
        let known = knownCity(trip.city)
        if !known.isEmpty { return known }
        let address = trip.address.replacingOccurrences(
            of: "^(?:[^省]{2,6}省|内蒙古自治区|广西壮族自治区|西藏自治区|宁夏回族自治区|新疆维吾尔自治区)\\s*",
            with: "", options: .regularExpression)
        return CityIndex.names.first { address.hasPrefix($0) } ?? ""
    }
    static func visitedCities(_ trips: [Trip]) -> [String] {
        var seen = Set<String>()
        return trips.filter { $0.valid && $0.status == .arrived }.sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
            .compactMap { record in
                let city = city(of: record)
                return !city.isEmpty && seen.insert(city).inserted ? city : nil
            }
    }
    static func frequent(_ trips: [Trip]) -> [FrequentPlace] {
        var places: [String: FrequentPlace] = [:]
        var seen = Set<UUID>()
        for trip in trips where trip.valid && trip.status == .arrived && trip.endedAt != nil && seen.insert(trip.id).inserted {
            let city = city(of: trip)
            let key = [normalized(trip.destination), city, normalized(trip.address)].joined(separator: "\u{001F}")
            var value = places[key] ?? FrequentPlace(id: key, name: trip.destination, city: city, address: trip.address,
                visits: 0, lastArrival: .distantPast)
            value.visits += 1
            if trip.endedAt! > value.lastArrival {
                value.name = trip.destination; value.address = trip.address; value.lastArrival = trip.endedAt!
            }
            places[key] = value
        }
        return Array(places.values.sorted {
            $0.visits != $1.visits ? $0.visits > $1.visits : $0.lastArrival != $1.lastArrival ?
                $0.lastArrival > $1.lastArrival : $0.id < $1.id
        }.prefix(5))
    }
    static func match(_ name: String, _ query: String) -> Int {
        let name = normalized(name), query = normalized(query)
        guard !query.isEmpty else { return 0 }
        return name == query ? 2 : name.contains(query) ? 1 : 0
    }
    static func rank(_ places: [Place], keyword: String, previous: Set<String>) -> [Place] {
        places.enumerated().sorted { a, b in
            let am = match(a.element.name, keyword), bm = match(b.element.name, keyword)
            if am != bm { return am > bm }
            let av = previous.contains(normalized(a.element.name)), bv = previous.contains(normalized(b.element.name))
            if av != bv { return av }
            return a.offset < b.offset
        }.map(\.element)
    }

    @MainActor
    static func search(query: String, city: String, automatic: Bool, trips: [Trip],
        request: (String, String) async throws -> [Place], onFallback: (String) -> Void = { _ in }) async throws -> SearchOutcome {
        try Task.checkCancellation()
        let scope = try SearchScope.resolve(query, defaultCity: city)
        let previous = Set(trips.filter { $0.status == .arrived }.map { normalized($0.destination) })
        let places = try await request(scope.keyword, scope.city)
        try Task.checkCancellation()
        var result = SearchOutcome(places: rank(places, keyword: scope.keyword, previous: previous), city: scope.city,
            explicit: scope.explicit, matched: places.contains { match($0.name, scope.keyword) > 0 })
        guard automatic && !scope.explicit && !result.matched else { return result }
        for otherCity in visitedCities(trips) where otherCity != (knownCity(scope.city).isEmpty ? scope.city : knownCity(scope.city)) {
            try Task.checkCancellation(); onFallback(otherCity)
            let matches: [Place]
            do { matches = try await request(scope.keyword, otherCity) }
            catch {
                try Task.checkCancellation()
                if result.places.isEmpty { throw error }
                result.warning = "去过城市查询未完成，以下保留已有结果"; return result
            }
            try Task.checkCancellation()
            result.checked += 1
            let matched = matches.contains { match($0.name, scope.keyword) > 0 }
            if matched || (result.places.isEmpty && !matches.isEmpty) {
                result.places = rank(matches, keyword: scope.keyword, previous: previous)
                result.city = otherCity; result.fallback = true; result.matched = matched
                if matched { return result }
            }
        }
        return result
    }
}
