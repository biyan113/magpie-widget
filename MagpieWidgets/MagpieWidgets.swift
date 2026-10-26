import SwiftUI
import WidgetKit
import AppIntents
import Charts

struct SubscriptionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "订阅"
    static var defaultQuery = SubscriptionQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct SubscriptionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SubscriptionEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [SubscriptionEntity] { all() }
    private func all() -> [SubscriptionEntity] { SnapshotStore().load().quotas.map { .init(id: $0.id, name: $0.title + ($0.plan.map { " · " + $0 } ?? "")) } }
}
enum WidgetMetric: String, AppEnum {
    case remaining, used, reset, cost, tokens
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "指标"
    static var caseDisplayRepresentations: [WidgetMetric: DisplayRepresentation] = [.remaining: "剩余额度", .used: "已用额度", .reset: "重置时间", .cost: "估算费用", .tokens: "Token"]
}
enum WidgetPeriod: String, AppEnum {
    case today, week, month
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "时间范围"
    static var caseDisplayRepresentations: [WidgetPeriod: DisplayRepresentation] = [.today: "今日", .week: "7 日", .month: "30 日"]
    var label: String { self == .today ? "今日" : self == .week ? "7 日" : "30 日" }
}
struct ConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Magpie 小组件"
    static var description = IntentDescription("展示当前 Gateway 的额度快照。点击小号组件中的订阅名，可轮换已选订阅。")
    @Parameter(title: "跟随主应用设置", default: true) var followsAppSettings: Bool
    @Parameter(title: "订阅（不选则显示全部）") var subscriptions: [SubscriptionEntity]?
    @Parameter(title: "小号指标", default: .remaining) var metric: WidgetMetric
    @Parameter(title: "时间范围", default: .today) var period: WidgetPeriod
    var selectionKey: String { "selection." + (subscriptions?.map(\.id).sorted().joined(separator: ";") ?? "all") }
}
struct CycleSubscriptionIntent: AppIntent {
    static var title: LocalizedStringResource = "切换订阅"
    static var openAppWhenRun = false
    @Parameter(title: "选择组") var selectionKey: String
    @Parameter(title: "订阅数") var count: Int
    init() {}
    init(key: String, count: Int) { selectionKey = key; self.count = count }
    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: SnapshotStore.groupID)
        let current = defaults?.integer(forKey: selectionKey) ?? 0
        defaults?.set((current + 1) % max(1, count), forKey: selectionKey)
        WidgetCenter.shared.reloadTimelines(ofKind: DesktopWidget.kind)
        return .result()
    }
}
struct Entry: TimelineEntry {
    var date: Date
    var snapshot: Snapshot
    var configuration: ConfigurationIntent
    var selectedIndex = 0
    var preferences = WidgetPreferences()
}
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: Snapshot(), configuration: ConfigurationIntent()) }
    func snapshot(for configuration: ConfigurationIntent, in context: Context) async -> Entry { makeEntry(configuration) }
    func timeline(for configuration: ConfigurationIntent, in context: Context) async -> Timeline<Entry> {
        let current = makeEntry(configuration)
        return Timeline(entries: [current], policy: .after(current.date.addingTimeInterval(DesktopWidget.timelineInterval)))
    }
    private func makeEntry(_ configuration: ConfigurationIntent) -> Entry {
        Entry(date: Date(), snapshot: SnapshotStore().load(), configuration: configuration,
              selectedIndex: UserDefaults(suiteName: SnapshotStore.groupID)?.integer(forKey: configuration.selectionKey) ?? 0,
              preferences: WidgetPreferencesStore().load())
    }
}
private enum WidgetText {
    static func clock(_ date: Date) -> String { date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
    static func reset(_ date: Date) -> String { date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
    static func remaining(_ window: QuotaWindow?) -> String {
        guard let window else { return "—" }
        if window.unlimited == true { return "无限制" }
        return window.remainingPercent.map { String(format: "%.0f%%", $0) } ?? "—"
    }
}
struct WidgetContent: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry
    var preferences: WidgetPreferences { entry.configuration.followsAppSettings ? entry.preferences : WidgetPreferences() }
    var metric: WidgetMetric { entry.configuration.followsAppSettings ? WidgetMetric(rawValue: preferences.metric) ?? .remaining : entry.configuration.metric }
    var period: WidgetPeriod { entry.configuration.followsAppSettings ? WidgetPeriod(rawValue: preferences.period) ?? .today : entry.configuration.period }
    var quotas: [Quota] {
        let ids = entry.configuration.followsAppSettings ? preferences.providerIDs : entry.configuration.subscriptions?.map(\.id) ?? []
        return entry.snapshot.quotas.filter { ids.isEmpty || ids.contains($0.id) }
    }
    var selectedQuota: Quota? { quotas.isEmpty ? nil : quotas[max(0, entry.selectedIndex) % quotas.count] }
    var usage: Usage? { entry.snapshot.usage[period.rawValue] }
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            HStack {
                Label("MAGPIE", systemImage: "bird.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Link(destination: URL(string: "magpiewidget://refresh")!) { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                    .accessibilityLabel("打开应用并刷新")
            }
            if family == .systemSmall { small }
            else {
                if preferences.showQuotas {
                    if quotas.isEmpty {
                        Text("暂无订阅额度").font(.headline)
                        Text("在应用中选择订阅").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: family == .systemLarge ? 10 : 6) {
                            ForEach(Array(quotas.prefix(min(3, max(1, preferences.quotaCount))))) { q in
                                WidgetQuotaRow(quota: q, spacious: family == .systemLarge, preferences: preferences)
                            }
                        }
                    }
                }
                if family == .systemLarge { analytics }
                Spacer(minLength: 0)
            }
            if family == .systemSmall { smallFooter }
            else if preferences.showSync { footer }
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        .widgetURL(URL(string: "magpiewidget://\(metric == .cost || metric == .tokens ? "usage" : "overview")"))
    }
    @ViewBuilder var small: some View {
        if metric == .cost || metric == .tokens {
            Text(period.label).font(.caption).foregroundStyle(.secondary)
            Text(metric == .cost ? Display.money(usage?.cost) : Display.number(usage?.tokens))
                .font(.system(size: 30, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            Text(metric == .cost ? "估算费用 · USD" : "Token · 输入 + 输出").font(.caption2).foregroundStyle(.secondary)
        } else if let q = selectedQuota {
            Button(intent: CycleSubscriptionIntent(key: entry.configuration.selectionKey, count: quotas.count)) {
                HStack(spacing: 3) {
                    Text(q.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if quotas.count > 1 { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(quotas.count < 2).accessibilityLabel("\(q.title)，切换到下一个订阅")
            if let window = q.windows?.first {
                if metric == .reset {
                    Text(window.resetsAt.map(WidgetText.reset) ?? "未提供时间").font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.7)
                } else {
                    let value = metric == .used ? window.used.map { String(format: "%.0f%%", $0) } ?? "—" : WidgetText.remaining(window)
                    Text(value).font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
            } else { Text(q.balance ?? q.measurementState).font(.headline).lineLimit(2).minimumScaleFactor(0.7) }
            if q.error != nil { Text("提供商暂不可用").font(.system(size: 9)).foregroundStyle(.orange) }
        } else { Text("等待 Magpie").font(.headline); Text("打开应用连接网关").font(.caption).foregroundStyle(.secondary) }
        Spacer(minLength: 0)
    }
    var analytics: some View {
        VStack(alignment: .leading, spacing: 10) {
            if preferences.showQuotas && (preferences.showCost || preferences.showTokens || preferences.showChart || preferences.showRequests || preferences.showAgents) { Divider().opacity(0.5) }
            if preferences.showCost || preferences.showTokens {
                HStack(alignment: .firstTextBaseline) {
                    if preferences.showCost {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Display.money(usage?.cost)).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("\(period.label)估算费用").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if preferences.showTokens {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(Display.number(usage?.tokens)).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("输入 + 输出 Token").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if preferences.showChart, let points = usage?.series, !points.isEmpty {
                Chart(points) { point in
                    let amount = preferences.chartMetric == "cost" ? point.cost ?? 0 : Double(point.tokens)
                    AreaMark(x: .value("时间", point.time), y: .value("用量", amount)).foregroundStyle(.mint.opacity(0.1))
                    LineMark(x: .value("时间", point.time), y: .value("用量", amount)).foregroundStyle(.mint).lineStyle(.init(lineWidth: 1.5))
                }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 42).accessibilityLabel(preferences.chartMetric == "cost" ? "费用趋势" : "Token 用量趋势")
            }
            if preferences.showRequests || preferences.showAgents {
                HStack {
                    if preferences.showRequests { Text("\(Display.number(usage?.calls)) 次请求") }
                    Spacer()
                    if preferences.showAgents, let agent = usage?.agents?.first { Text("\(agent.name ?? agent.id) · \(Display.number(agent.calls)) 次").lineLimit(1) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    var smallFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if preferences.showWindowName, metric != .cost, metric != .tokens,
               let window = selectedQuota?.windows?.first {
                Text("\(window.name) · \(metric == .used ? "已用" : metric == .reset ? "重置" : "剩余")")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            if preferences.showSync { footer.fixedSize(horizontal: true, vertical: false) }
        }
    }
    var footer: some View {
        HStack(spacing: 4) {
            Circle().fill(entry.snapshot.issue != nil || entry.snapshot.stale(at: entry.date) ? Color.orange : Color.mint).frame(width: 4, height: 4)
            if let date = entry.snapshot.updatedAt {
                Text("同步于 \(WidgetText.clock(date))")
                if entry.snapshot.issue != nil { Text("· 离线") }
                else if entry.snapshot.stale(at: entry.date) { Text("· 已过期") }
            } else { Text(entry.snapshot.issue == nil ? "等待同步" : "连接异常") }
        }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
}
struct WidgetQuotaRow: View {
    let quota: Quota
    let spacious: Bool
    let preferences: WidgetPreferences
    private var window: QuotaWindow? { quota.windows?.first }
    var body: some View {
        VStack(spacing: spacious ? 4 : 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(quota.title).font(.system(size: spacious ? 13 : 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(quota.balance ?? WidgetText.remaining(window)).font(.system(size: spacious ? 17 : 13, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
            }
            HStack(spacing: 4) {
                if preferences.showWindowName {
                    Text(window?.name ?? quota.measurementState).lineLimit(1)
                    if (quota.windows?.count ?? 0) > 1 { Text("+\((quota.windows?.count ?? 0) - 1)") }
                }
                Spacer(minLength: 0)
                if quota.error != nil { Text("暂不可用").foregroundStyle(.orange) }
                else if preferences.showReset, let reset = window?.resetsAt { Text("\(WidgetText.reset(reset)) 重置").lineLimit(1) }
            }.font(.system(size: spacious ? 9 : 8)).foregroundStyle(.secondary)
            if let remaining = window?.remainingPercent {
                GeometryReader { g in
                    Capsule().fill(.primary.opacity(0.07))
                    Capsule().fill(remaining < 15 ? Color.orange : Color.mint).frame(width: g.size.width * min(100, max(0, remaining)) / 100)
                }.frame(height: 2)
            }
        }.accessibilityElement(children: .combine)
    }
}
struct MagpieDesktopWidget: Widget {
    let kind = DesktopWidget.kind
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: Provider()) { WidgetContent(entry: $0) }
            .configurationDisplayName("Magpie Widget")
            .description("订阅额度、用量与趋势。点击小号组件的订阅名切换；更多窗口在主应用查看。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
@main struct MagpieWidgetBundle: WidgetBundle { var body: some Widget { MagpieDesktopWidget() } }

#Preview(as: .systemMedium) { MagpieDesktopWidget() } timeline: {
    Entry(date: Date(), snapshot: Snapshot(), configuration: ConfigurationIntent())
}
#Preview(as: .systemSmall) { MagpieDesktopWidget() } timeline: {
    Entry(date: Date(), snapshot: Snapshot(), configuration: ConfigurationIntent())
}
#Preview(as: .systemLarge) { MagpieDesktopWidget() } timeline: {
    Entry(date: Date(), snapshot: Snapshot(), configuration: ConfigurationIntent())
}
