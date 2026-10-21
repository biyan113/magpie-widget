import SwiftUI
import WidgetKit
import Security
import ServiceManagement

struct GatewayKeychain {
    static let service = "net.bytenote.MagpieWidget.gateway"
    static func load(endpoint: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: endpoint, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, endpoint: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: endpoint]
        if value.isEmpty { let status = SecItemDelete(q as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }; return }
        let data = Data(value.utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(add as CFDictionary, nil)
            guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        } else if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

@MainActor final class DataSyncService: ObservableObject {
    @Published var snapshot: Snapshot
    @Published var syncing = false
    @Published var storageIssue: String?
    @Published var screen = "overview"
    @Published var endpoint: String
    @Published var interval: Double
    @Published var widgetPreferences: WidgetPreferences {
        didSet {
            do { try WidgetPreferencesStore().save(widgetPreferences); WidgetCenter.shared.reloadAllTimelines() }
            catch { storageIssue = "无法保存小组件设置，请检查 App Group 配置。" }
        }
    }
    private var loop: Task<Void, Never>?
    private var failures = 0
    let store = SnapshotStore()
    init() {
        snapshot = store.load()
        widgetPreferences = WidgetPreferencesStore().load()
        endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? Endpoint.detect()
        interval = max(30, UserDefaults.standard.double(forKey: "interval") == 0 ? 60 : UserDefaults.standard.double(forKey: "interval"))
    }
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                let delay = min(900, interval * pow(2, Double(min(failures, 4))))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }
    func configure(endpoint: String, interval: Double, token: String) throws {
        _ = try Endpoint.validate(endpoint)
        try GatewayKeychain.save(token, endpoint: endpoint)
        self.endpoint = endpoint; self.interval = max(30, interval)
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        UserDefaults.standard.set(self.interval, forKey: "interval")
        // Do not show one gateway's data under a different endpoint.
        if snapshot.endpoint != endpoint { snapshot = Snapshot(); snapshot.endpoint = endpoint; persist() }
        failures = 0
        Task { await refresh() }
    }
    func refresh() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let requestedEndpoint = endpoint
        var next = snapshot.endpoint == requestedEndpoint ? snapshot : Snapshot()
        next.endpoint = requestedEndpoint; next.attemptedAt = Date()
        do {
            let client = try MagpieClient(endpoint: requestedEndpoint, token: GatewayKeychain.load(endpoint: requestedEndpoint))
            next.version = try await client.hello().version
            var issues: [String] = []
            do { next.quotas = try await client.quotas(); next.quotaUpdatedAt = Date() }
            catch { issues.append("额度：\(safeError(error))") }
            var usageSucceeded = true
            for period in ["today", "week", "month"] {
                do { next.usage[period] = try await client.usage(period) }
                catch { usageSucceeded = false; issues.append("\(period)：\(safeError(error))") }
            }
            if usageSucceeded { next.usageUpdatedAt = Date() }
            if issues.isEmpty { next.updatedAt = Date(); next.issue = nil; failures = 0 }
            else { next.issue = issues.joined(separator: "\n"); failures += 1 }
        } catch { next.issue = safeError(error); failures += 1 }
        guard endpoint == requestedEndpoint else { Task { await refresh() }; return }
        snapshot = next; persist()
    }
    private func safeError(_ error: Error) -> String {
        if let e = error as? GatewayError { return e.localizedDescription }
        if error is DecodingError { return "响应格式不兼容，保留上次有效数据。" }
        if let e = error as? URLError { return "网络连接失败（\(e.code.rawValue)），请确认 Magpie 正在运行。" }
        return "读取失败，保留上次有效数据。"
    }
    private func persist() {
        do { try store.save(snapshot); storageIssue = nil }
        catch { storageIssue = "无法写入 App Group。请检查签名团队和共享容器配置。" }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

@main struct MagpieWidgetApp: App {
    @StateObject private var sync = DataSyncService()
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        Window("Magpie Widget", id: "dashboard") {
            DashboardView().environmentObject(sync)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .task { sync.start() }
                .onOpenURL { url in
                    guard url.scheme == "magpiewidget" else { return }
                    sync.screen = url.host == "usage" ? "usage" : url.host == "settings" ? "settings" : "overview"
                    if url.host == "refresh" { Task { await sync.refresh() } }
                }
        }.defaultSize(width: 1030, height: 740)
        Settings { SettingsView().environmentObject(sync) }
        MenuBarExtra(isInserted: $showMenuBar) { MenuPanel().environmentObject(sync) } label: {
            Label(menuTitle, systemImage: "bird.fill")
        }.menuBarExtraStyle(.window)
    }
    private var menuTitle: String {
        let selected = UserDefaults.standard.string(forKey: "menuQuota") ?? ""
        let q = sync.snapshot.quotas.first { selected.isEmpty || $0.id == selected }
        if let remaining = q?.windows?.first?.remainingPercent { return "\(Int(remaining))%" }
        return "Magpie"
    }
}
struct MenuPanel: View {
    @EnvironmentObject var sync: DataSyncService
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Magpie Widget", systemImage: "bird.fill").font(.headline)
            Text(sync.snapshot.status).foregroundStyle(.secondary)
            ForEach(Array(sync.snapshot.quotas.prefix(3))) { QuotaCard(quota: $0, compact: true) }
            if let date = sync.snapshot.updatedAt { Text("同步于 \(date.formatted(date: .omitted, time: .shortened))").font(.caption) }
            HStack {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await sync.refresh() } }.disabled(sync.syncing)
                Button("打开概览") { sync.screen = "overview"; openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
            }
            HStack {
                Button("设置") { sync.screen = "settings"; openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }.font(.caption)
        }.padding(18).frame(width: 330)
    }
}
