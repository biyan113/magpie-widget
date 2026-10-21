import Foundation

public enum Wire {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: value) { return date }
            f.formatOptions = [.withInternetDateTime]
            guard let date = f.date(from: value) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid timestamp")) }
            return date
        }
        return d
    }
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

public struct QuotaWindow: Codable, Equatable {
    public var name: String
    public var used: Double?
    public var remaining: Double?
    public var unlimited: Bool?
    public var resetsAt: Date?
    public var display: String?
    public var amount: Double?
    public var limit: Double?
    public var unit: String?
    public var pool: String?
    public var remainingPercent: Double? {
        guard unlimited != true else { return nil }
        return remaining ?? used.map { max(0, 100 - $0) }
    }
}
public struct Quota: Codable, Identifiable, Equatable {
    public var provider: String
    public var name: String
    public var kind: String?
    public var user: String?
    public var alias: String?
    public var plan: String?
    public var from: String?
    public var windows: [QuotaWindow]?
    public var balance: String?
    public var error: String?
    public var readAt: Date?
    public var asOf: Date?
    public var readDeferred: Bool?
    public var id: String { [from ?? "", provider, kind ?? "", user ?? ""].joined(separator: "|") }
    public var title: String { (alias?.isEmpty == false ? alias : nil) ?? name }
    public var measurementState: String {
        if error != nil { return "提供商暂不可用" }
        if balance != nil || !(windows ?? []).isEmpty { return "已获取" }
        return kind == "balance" ? "不支持或尚未提供余额" : "尚未获取额度"
    }
}
public struct QuotaEnvelope: Decodable { public var data: [Quota] }
public struct Usage: Codable {
    public var period: String
    public var since: Date?
    public var calls: Int?
    public var input: Int?
    public var output: Int?
    public var cache_read: Int?
    public var cache_write: Int?
    public var cost: Double?
    public var unpriced: Int?
    public var series: [UsagePoint]?
    public var agents: [UsageGroup]?
    public var models: [UsageGroup]?
    public var tokens: Int? { guard let input, let output else { return nil }; return input + output }
    // Each model belongs to exactly one provider. Never add this to agent totals.
    public var providers: [UsageGroup] {
        Dictionary(grouping: models ?? [], by: { $0.provider ?? "unknown" }).map { key, rows in
            UsageGroup(id: key, name: rows.first?.sub ?? key, provider: key,
                       calls: rows.reduce(0) { $0 + ($1.calls ?? 0) }, input: rows.reduce(0) { $0 + ($1.input ?? 0) },
                       output: rows.reduce(0) { $0 + ($1.output ?? 0) }, cost: rows.reduce(0) { $0 + ($1.cost ?? 0) })
        }.sorted { ($0.calls ?? 0) > ($1.calls ?? 0) }
    }
}
public struct UsagePoint: Codable, Identifiable {
    public var label: String
    public var time: Date
    public var input: Int?
    public var output: Int?
    public var cost: Double?
    public var id: Date { time }
    public var tokens: Int { (input ?? 0) + (output ?? 0) }
}
public struct UsageGroup: Codable, Identifiable {
    public var id: String
    public var name: String?
    public var provider: String?
    public var sub: String?
    public var calls: Int?
    public var input: Int?
    public var output: Int?
    public var cost: Double?
}
public struct Snapshot: Codable {
    public var schema = 1
    public var updatedAt: Date?
    public var attemptedAt: Date?
    public var quotaUpdatedAt: Date?
    public var usageUpdatedAt: Date?
    public var endpoint = ""
    public var version: String?
    public var issue: String?
    public var quotas: [Quota] = []
    public var usage: [String: Usage] = [:]
    public init() {}
    public func stale(at date: Date = Date()) -> Bool { updatedAt.map { date.timeIntervalSince($0) > 180 } ?? true }
    public var status: String { issue != nil ? "离线 / 同步异常" : updatedAt == nil ? "等待同步" : stale() ? "数据已过期" : "已同步" }
}
public enum Display {
    public static func number(_ n: Int?) -> String { n.map { $0.formatted(.number.notation(.compactName)) } ?? "—" }
    public static func money(_ n: Double?) -> String { n.map { $0.formatted(.currency(code: "USD")) } ?? "—" }
}
