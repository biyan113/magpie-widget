import Foundation

public struct WidgetPreferences: Codable, Equatable {
    public var providerIDs: [String] = []
    public var quotaCount = 3
    public var metric = "remaining"
    public var period = "today"
    public var showQuotas = true
    public var showWindowName = true
    public var showReset = false
    public var showSync = true
    public var showCost = true
    public var showTokens = true
    public var showChart = true
    public var chartMetric = "tokens"
    public var showRequests = false
    public var showAgents = false
    public init() {}
}
public struct WidgetPreferencesStore {
    public let directory: URL?
    public init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SnapshotStore.groupID)) { self.directory = directory }
    public func load() -> WidgetPreferences {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("widget-preferences.json")),
              let value = try? JSONDecoder().decode(WidgetPreferences.self, from: data) else { return WidgetPreferences() }
        return value
    }
    public func save(_ preferences: WidgetPreferences) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: directory.appendingPathComponent("widget-preferences.json"), options: .atomic)
    }
}
