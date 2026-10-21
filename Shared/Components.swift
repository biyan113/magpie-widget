import SwiftUI
import Charts

struct QuotaCard: View {
    let quota: Quota
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 12) {
            HStack {
                Image(systemName: quota.kind == "balance" ? "creditcard" : "sparkles").foregroundStyle(.mint)
                Text(quota.title).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if quota.error != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("提供商暂不可用，可能显示缓存数据") }
            }
            if !compact, let plan = quota.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
            if let balance = quota.balance { Text(balance).font(compact ? .subheadline : .title2).monospacedDigit() }
            ForEach(Array((quota.windows ?? []).prefix(compact ? 2 : 20).enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(window.name).lineLimit(1)
                        Spacer(minLength: 2)
                        if window.unlimited == true { Text("无限制") }
                        else if let remaining = window.remainingPercent { Text("剩余 \(remaining, specifier: "%.0f")%").monospacedDigit() }
                        else { Text("未获取") }
                    }.font(.caption)
                    if let remaining = window.remainingPercent {
                        ProgressView(value: min(100, max(0, remaining)), total: 100).tint(remaining < 15 ? .orange : .mint)
                    }
                    if !compact, let display = window.display { Text(display).font(.caption).foregroundStyle(.secondary) }
                    if let reset = window.resetsAt {
                        Text("重置于 \(reset.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if (quota.windows ?? []).isEmpty && quota.balance == nil { Text(quota.measurementState).font(.caption).foregroundStyle(.secondary) }
            if let date = quota.asOf ?? quota.readAt, !compact {
                HStack { Text("源数据 \(date.formatted(date: .abbreviated, time: .shortened))"); if quota.readDeferred == true { Text("· 延后读取") } }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct UsageChart: View {
    let points: [UsagePoint]
    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("时间", point.time), y: .value("Token", point.tokens))
                .foregroundStyle(LinearGradient(colors: [.mint.opacity(0.35), .mint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("时间", point.time), y: .value("Token", point.tokens)).foregroundStyle(.mint).lineStyle(.init(lineWidth: 2))
        }.chartYAxis { AxisMarks(position: .leading) }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .accessibilityLabel("Token 用量趋势，\(points.count) 个时间段")
    }
}
struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
    }
}
