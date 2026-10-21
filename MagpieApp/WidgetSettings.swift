import SwiftUI

struct WidgetSettingsSections: View {
    @EnvironmentObject var sync: DataSyncService
    var body: some View {
        Section("小组件 · 默认显示") {
            Text("修改即保存，并请求刷新桌面小组件。默认所有小组件跟随这里的设置；系统可能延后显示更新。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("小号默认指标", selection: $sync.widgetPreferences.metric) {
                Text("剩余额度").tag("remaining"); Text("已用额度").tag("used"); Text("重置时间").tag("reset")
                Text("估算费用").tag("cost"); Text("Token").tag("tokens")
            }
            Picker("统计时间范围", selection: $sync.widgetPreferences.period) {
                Text("今日").tag("today"); Text("7 日").tag("week"); Text("30 日").tag("month")
            }
            Picker("中号 / 大号订阅数量", selection: $sync.widgetPreferences.quotaCount) {
                Text("1 个").tag(1); Text("2 个").tag(2); Text("3 个").tag(3)
            }
            Toggle("显示订阅额度", isOn: $sync.widgetPreferences.showQuotas)
            Toggle("显示额度窗口名称", isOn: $sync.widgetPreferences.showWindowName)
            Toggle("显示重置日期时间", isOn: $sync.widgetPreferences.showReset)
            Toggle("显示最后同步时间", isOn: $sync.widgetPreferences.showSync)
        }
        Section("小组件 · 大号信息") {
            Toggle("估算费用", isOn: $sync.widgetPreferences.showCost)
            Toggle("输入 + 输出 Token", isOn: $sync.widgetPreferences.showTokens)
            Toggle("用量趋势图", isOn: $sync.widgetPreferences.showChart)
            if sync.widgetPreferences.showChart {
                Picker("趋势指标", selection: $sync.widgetPreferences.chartMetric) { Text("Token").tag("tokens"); Text("估算费用").tag("cost") }
            }
            Toggle("请求总数", isOn: $sync.widgetPreferences.showRequests)
            Toggle("调用最多的 Agent", isOn: $sync.widgetPreferences.showAgents)
        }
        Section("小组件 · 订阅筛选") {
            Toggle("使用全部订阅", isOn: Binding(get: { sync.widgetPreferences.providerIDs.isEmpty }, set: { all in
                sync.widgetPreferences.providerIDs = all ? [] : sync.snapshot.quotas.map(\.id)
            }))
            Text("勾选需要展示的订阅。小号点击订阅名可在所选订阅之间切换；中号、大号按 Magpie 顺序展示。未单独选择时使用全部订阅。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(sync.snapshot.quotas) { quota in
                Toggle(isOn: Binding(get: {
                    sync.widgetPreferences.providerIDs.isEmpty || sync.widgetPreferences.providerIDs.contains(quota.id)
                }, set: { selected in
                    var ids = sync.widgetPreferences.providerIDs.isEmpty ? sync.snapshot.quotas.map(\.id) : sync.widgetPreferences.providerIDs
                    if selected { if !ids.contains(quota.id) { ids.append(quota.id) } }
                    else { ids.removeAll { $0 == quota.id } }
                    // An explicit nonmatching sentinel represents selecting none; [] means all.
                    ids.removeAll { $0 == "__none__" }
                    sync.widgetPreferences.providerIDs = ids.isEmpty ? ["__none__"] : ids
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quota.title)
                        if let plan = quota.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Button("恢复默认展示") { sync.widgetPreferences = WidgetPreferences() }
        }
    }
}
