import SwiftUI
import ServiceManagement

struct DashboardView: View {
    @EnvironmentObject var sync: DataSyncService
    @State private var period = "today"
    @State private var dimension = "agents"
    var usage: Usage? { sync.snapshot.usage[period] }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Magpie", systemImage: "bird.fill").font(.system(size: 25, weight: .semibold)).padding(.horizontal, 16).padding(.top, 24)
                List(selection: $sync.screen) {
                    Label("概览", systemImage: "square.grid.2x2").tag("overview")
                    Label("用量分析", systemImage: "chart.xyaxis.line").tag("usage")
                    Label("桌面小组件", systemImage: "rectangle.3.group").tag("widgets")
                    Label("设置与诊断", systemImage: "gearshape").tag("settings")
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label(sync.snapshot.status, systemImage: sync.snapshot.issue == nil ? "circle.fill" : "wifi.slash").foregroundStyle(sync.snapshot.issue == nil ? .mint : .orange)
                    if let version = sync.snapshot.version { Text("Magpie \(version)").foregroundStyle(.secondary) }
                }.font(.caption).padding(20)
            }.navigationSplitViewColumnWidth(min: 185, ideal: 210)
        } detail: {
            Group {
                if sync.screen == "settings" { SettingsView() }
                else if sync.screen == "widgets" {
                    Form { WidgetSettingsSections() }.formStyle(.grouped).navigationTitle("小组件展示设置")
                }
                else { dashboard }
            }.toolbar {
                ToolbarItem {
                    HStack {
                        if sync.syncing { ProgressView().controlSize(.small) }
                        Button { Task { await sync.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(sync.syncing).help("读取 Magpie 并请求刷新桌面小组件")
                    }
                }
            }
        }.frame(minWidth: 780, minHeight: 580)
    }
    var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sync.screen == "usage" ? "用量分析" : "你的 AI，一目了然。") .font(.system(size: 30, weight: .bold))
                        Text("额度、调用与趋势，留在你的 Mac 上。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("时间范围", selection: $period) { Text("今日").tag("today"); Text("7 日").tag("week"); Text("30 日").tag("month") }.labelsHidden().frame(width: 115)
                }
                if let issue = sync.snapshot.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)) }
                if let issue = sync.storageIssue { Text(issue).foregroundStyle(.orange) }
                HStack(spacing: 12) {
                    MetricTile(title: "估算费用 · USD", value: Display.money(usage?.cost), symbol: "dollarsign.circle")
                    MetricTile(title: "Token · 输入 + 输出", value: Display.number(usage?.tokens), symbol: "square.stack.3d.up")
                    MetricTile(title: "请求", value: Display.number(usage?.calls), symbol: "arrow.up.arrow.down")
                }
                if sync.screen == "overview" {
                    Text("订阅与额度").font(.title3.bold())
                    if sync.snapshot.quotas.isEmpty {
                        ContentUnavailableView("尚无额度数据", systemImage: "sparkles", description: Text("启动 Magpie 并添加订阅，然后点击刷新。"))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .top)], alignment: .leading, spacing: 14) {
                            ForEach(sync.snapshot.quotas) { q in
                                QuotaCard(quota: q).padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
                                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("调用趋势").font(.title3.bold())
                    if let points = usage?.series, !points.isEmpty { UsageChart(points: points).frame(height: 180) }
                    else { Text("此时间范围暂无趋势数据").foregroundStyle(.secondary).frame(height: 120) }
                }.padding(20).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
                HStack {
                    Text("用量分布").font(.title3.bold()); Spacer()
                    Picker("维度", selection: $dimension) { Text("Agent").tag("agents"); Text("模型").tag("models"); Text("供应商").tag("providers") }.pickerStyle(.segmented).frame(width: 270)
                }
                let groups = dimension == "agents" ? usage?.agents ?? [] : dimension == "models" ? usage?.models ?? [] : usage?.providers ?? []
                ForEach(Array(groups.enumerated()), id: \.offset) { _, row in
                    HStack {
                        VStack(alignment: .leading) { Text(row.name ?? row.id).fontWeight(.medium); if let sub = row.sub { Text(sub).font(.caption).foregroundStyle(.secondary) } }
                        Spacer(); Text("\(Display.number(row.calls)) 次").foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
                        Text(Display.money(row.cost)).monospacedDigit().frame(width: 100, alignment: .trailing)
                    }.padding(.vertical, 6)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("费用为 Magpie 按有效价格计算或调用方上报的金额，不等于订阅账单；\(usage?.unpriced ?? 0) 次请求缺少定价。")
                    Text("仅统计 Magpie 已记录、导入或接收上报的调用。统计日界线与时间桶沿用 Gateway 所在时区；图表时间按本机时区显示。缓存 Token 单独计量，不加入输入 + 输出总量。")
                    if let date = sync.snapshot.updatedAt { Text("最近完整同步：\(date.formatted(date: .abbreviated, time: .standard))") }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.navigationTitle(sync.screen == "usage" ? "用量分析" : "概览")
    }
    var widgetHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("把额度留在桌面", systemImage: "rectangle.3.group.fill").font(.largeTitle.bold())
            Text("在桌面右键 → 编辑小组件 → 搜索 Magpie Widget。")
            Text("小号：单订阅额度、重置时间、费用或 Token。\n中号：最多三个订阅的额度窗口。\n大号：订阅额度、用量曲线与 Agent 排行。")
            Text("右键小组件 → 编辑小组件，可选择订阅、指标和时间范围。多个订阅可以单独选择；不选择时显示全部订阅的前几项。")
            Text("保持主应用运行以自动同步。桌面更新时间由 WidgetKit 决定，刷新按钮会打开应用并同步。关闭窗口后菜单栏仍会继续运行。")
                .foregroundStyle(.secondary)
            Text("所有小组件共用设置中的一个 Gateway 数据源。")
            Spacer()
        }.padding(36)
    }
}
struct SettingsView: View {
    @EnvironmentObject var sync: DataSyncService
    @State private var endpoint = ""
    @State private var interval = 60.0
    @State private var token = ""
    @State private var message: String?
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("menuQuota") private var menuQuota = ""
    @State private var login = SMAppService.mainApp.status == .enabled
    var body: some View {
        Form {
            Section("Gateway 连接") {
                TextField("地址", text: $endpoint)
                SecureField("远程网关密钥（Keychain）", text: $token)
                Button("检测本机端口") { endpoint = Endpoint.detect(); token = GatewayKeychain.load(endpoint: endpoint) ?? "" }
                Picker("同步间隔", selection: $interval) { Text("30 秒").tag(30.0); Text("60 秒").tag(60.0); Text("2 分钟").tag(120.0); Text("5 分钟").tag(300.0) }
                Button("保存并连接") {
                    do { try sync.configure(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines), interval: interval, token: token); message = "设置已保存。" }
                    catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
                if let message { Text(message).font(.caption) }
            }
            WidgetSettingsSections()
            Section("外观与启动") {
                Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Toggle("显示菜单栏", isOn: $showMenuBar)
                Picker("菜单栏额度", selection: $menuQuota) { Text("第一个订阅").tag(""); ForEach(sync.snapshot.quotas) { Text($0.title).tag($0.id) } }
                Toggle("登录时启动", isOn: $login).onChange(of: login) { _, enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { message = "登录项设置失败：\(error.localizedDescription)"; login = SMAppService.mainApp.status == .enabled }
                }
            }
            Section("连接诊断") {
                LabeledContent("状态", value: sync.snapshot.status)
                LabeledContent("Magpie 版本", value: sync.snapshot.version ?? "未连接")
                LabeledContent("App Group", value: SnapshotStore.groupID)
                if let at = sync.snapshot.attemptedAt { LabeledContent("最近尝试", value: at.formatted()) }
                if let at = sync.snapshot.quotaUpdatedAt { LabeledContent("额度读取", value: at.formatted()) }
                if let at = sync.snapshot.usageUpdatedAt { LabeledContent("统计读取", value: at.formatted()) }
                if let issue = sync.snapshot.issue { Text(issue).foregroundStyle(.orange) }
                if let issue = sync.storageIssue { Text(issue).foregroundStyle(.orange) }
            }
            Section("隐私与刷新") {
                Text("只发送 GET 请求，不修改 Magpie 配置、路由或凭证。不读取提供商凭证。共享快照仅保留展示字段，不保存网关密钥、请求正文或会话文本。")
                Text("本机自动检测只读取 settings.json 中的 port。远程地址必须明确填写并使用 HTTPS。失败后指数退避，最长 15 分钟；可随时手动重试。WidgetKit 不保证每分钟刷新。")
            }.font(.caption)
        }.formStyle(.grouped).frame(minWidth: 520, minHeight: 520)
            .onAppear { endpoint = sync.endpoint; interval = sync.interval; token = GatewayKeychain.load(endpoint: endpoint) ?? "" }
            .onChange(of: endpoint) { _, value in token = GatewayKeychain.load(endpoint: value) ?? "" }
    }
}
