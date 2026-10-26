# Magpie Widget

详细见字节笔记本微信公众号。发布页：https://magpie-widget.bytenote.net/

原生 macOS 14+ AI 用量仪表盘与桌面小组件。SwiftUI、WidgetKit、App Intents、Swift Charts，无第三方运行时依赖。只读连接 [Magpie](https://github.com/yetone/magpie)，不修改路由、账户、Agent 或数据库。

## 使用

1. 启动 Magpie。
2. 打开已签名的 `MagpieWidget.app`。首次自动检测 `~/.config/magpie/settings.json` 中的 `port`，支持启动环境里的 `XDG_CONFIG_HOME`，否则使用 `http://127.0.0.1:3425`。
3. 在主应用确认额度和统计已同步。
4. 桌面右键 → 编辑小组件 → 搜索 **Magpie Widget**，添加小、中、大号。
5. 主应用侧栏 **桌面小组件**（或 **设置与诊断**中的小组件区域）控制展示内容。修改自动保存并请求系统刷新。

小组件设置支持：订阅筛选、显示数量、小号默认指标、今日/7日/30日、额度窗口名、重置日期、最后同步时间、费用、Token、趋势图、趋势指标、请求数、首位 Agent。默认关闭重置日期与排行，保持紧凑。

小号组件点击**订阅名右侧箭头**直接轮换所选订阅。右键组件 → 编辑小组件，可关闭“跟随主应用设置”，单独指定订阅、指标与时间范围。相同订阅选择组的小号组件共享当前轮换位置。

- 同步时间显示固定时刻，如 `同步于 22:17`，没有跳动的秒数。
- 中、大号每个订阅显示第一个原始额度窗口；`+N` 表示还有 N 个窗口，点开主应用查看全部窗口。不会将各窗口混成一个百分比。
- 大号默认是纵向额度列表、费用 / Token、无坐标轴的趋势线。
- 小组件刷新图标会打开现有主窗口并同步；不会新建一堆窗口。
- 所有组件默认共享主应用配置的**一个 Gateway**；暂不同时连接多个网关。
- 保持主应用运行才能定时同步。关闭窗口后菜单栏仍在；设置中可以关闭菜单栏或注册登录启动。
- 桌面小组件每 20 分钟向 WidgetKit 要一次新时间线，并读取这时的快照。这个间隔是每天 72 次的预算上限。主应用不再每分钟调用 `reloadAllTimelines`，否则预算会被耗尽，之后连这 20 分钟也不再刷新。点刷新或改小组件设置仍会立刻重载。桌面未激活时的单色/透明效果由 macOS 控制。

## 开发与构建

需要 Xcode 15+（本次验证 Xcode 27.1）、macOS 14+。仓库已包含真实 `.xcodeproj`，直接打开即可；修改 `project.yml` 后才需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 重新生成。

```sh
open MagpieWidget.xcodeproj

# 无需签名即可验证主应用和扩展编译
xcodebuild -project MagpieWidget.xcodeproj -scheme MagpieWidget \
  -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# 核心单元测试（不连接任何网关）
swift test

# 可选：使用自动检测的本机网关做只读集成测试
MAGPIE_LIVE_TEST=1 swift test
```

普通未签名构建只能验证编译，不能用来验收跨进程 App Group。不要把这种构建的“等待同步”当作网关故障。

### Apple Development 与 App Group

主应用与扩展必须使用**同一个 Apple 开发团队**和**完全一致的 App Group**。项目默认：

```text
APP_GROUP_IDENTIFIER = $(DEVELOPMENT_TEAM).net.bytenote.MagpieWidget
```

这是 macOS 的团队前缀共享容器命名方式；项目中不写入任何人的团队 ID。签名时填写你自己的十位 Team ID。当前实现主应用不启用 App Sandbox，以便自动读取 Magpie 的端口配置；Widget Extension 启用 App Sandbox，且没有网络权限。两者都启用 App Group。主应用启用 Hardened Runtime。

本地开发可使用已有 Apple Development 证书：

```sh
DEVELOPMENT_TEAM=YOURTEAMID bash Scripts/build-local.sh
```

或直接构建：

```sh
xcodebuild -project MagpieWidget.xcodeproj -scheme MagpieWidget \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' \
  DEVELOPMENT_TEAM=YOURTEAMID build

open build/Build/Products/Debug/MagpieWidget.app
```

如果组织使用已注册的 `group.*` 容器，请用 `APP_GROUP_IDENTIFIER=group.your.identifier` 覆盖，并为两个 bundle ID 配置对应的 provisioning profile。不能只改一端。构建会将同一变量展开到两个 entitlements 和两个 Info.plist 的 `SharedAppGroup`。

本地开发证书构建不能发给别人。正式分发用 Developer ID 签名、公证并装订：

```sh
xcrun notarytool store-credentials magpie-notary \
  --apple-id "$APPLE_ID" --team-id "$DEVELOPMENT_TEAM" --password "$APPLE_PASSWORD"
bash Scripts/release.sh
```

`Scripts/release.sh` 会打 Release、提交公证、把票据订进 app，替换 `~/Applications/MagpieWidget.app`，再调用 `Scripts/publish-r2.sh`。发布页和安装包上传到 R2 桶 `magpie-widget`，地址是 https://magpie-widget.bytenote.net/ 。密码只留在钥匙串配置 `magpie-notary` 里。只改页面时单独运行 `bash Scripts/publish-r2.sh`。

## 数据与安全

```text
Magpie Gateway
  → MagpieClient（GET、限时、禁止重定向）
  → Codable 展示模型 / 计算属性
  → DataSyncService（主应用，单次同步互斥）
  → App Group / snapshot.json（原子写入、schema=1）
  → WidgetKit AppIntentTimelineProvider（只读快照）
```

- 主应用默认每 60 秒把快照写入 App Group；支持 30/60/120/300 秒。失败指数退避，最多 15 分钟；手动刷新可直接重试。定时同步不调用 `reloadTimelines`。桌面画面由小组件自己的 20 分钟时间线更新。
- 每次请求 25 秒超时，资源总超时 30 秒。每次同步先验证 `/api/hello`。
- 额度与用量分开处理失败，保留各自最后有效数据；只有整轮成功才更新“最后完整同步时间”。诊断页另外展示额度/统计读取时间。
- 断线后保留缓存，标为离线；恢复后下一轮成功自动清除错误。超过 3 分钟无完整同步标为过期，包含应用退出后的情况。
- `snapshot.json` 原子写入，保留 `previous.json` 作为损坏回退；未知 schema 不当作当前格式解析。
- `widget-preferences.json` 是主应用写入的独立展示配置；小号切换仅写 App Group 内的展示偏好，不访问网络。
- 只解析和保存用到的字段。忽略 usage 响应中的日志路径、sessions、callerKeys 等不需要的信息，不下载请求正文。
- 不读取或记录提供商凭证。只解码 Magpie `settings.json` 的 `port`，不读取 providers/account 文件。
- 远程地址必须由用户明确设置并使用 HTTPS；网关 Bearer token 按 endpoint 存在 Keychain，不写入 App Group。拒绝 URL 内嵌凭证、查询参数和重定向。
- 快照包含额度、订阅标识和统计，仍是本地私人数据，不应提交 Git 或发送给别人。本仓库不含真实响应 fixture。

## 接口研究与兼容性

研究上游提交：`f5b0157420a4491f6e707b49a8af8e87ea8050a1`。本机只读集成实测版本：`0.1.1307`。未声称验证所有历史版本。

| 接口 | 实际格式与本项目用途 |
| --- | --- |
| `GET /api/hello` | `{name:"magpie",version:"…"}`，识别服务并显示版本 |
| `GET /v1/magpie/quotas` | `{object:"list",data:[...]}`；额度主数据源。含 provider/name/kind/user/alias/plan/windows/balance/readAt/asOf/error 等 |
| `GET /v1/magpie/quotas?kept=1` | 同格式，只读 Magpie 已缓存的额度；研究时用于核验。本版正常刷新用标准 quotas 路径，遵循 Magpie 自身读取策略 |
| `GET /v1/magpie/quotas/cards` | Magpie 保存的 SubscriptionQuota 卡片，`used` 仍为百分比，可带 resetSecs、原始显示字段；与 quotas 的 QuotaSpan 不完全相同。本版不重复请求，避免重复卡片与窗口 |
| `GET /v1/magpie/usage?period=…` | **扁平对象**，不是 data 包装。总计、series、agents、models。实际预设参数是 `today`、`7d`、`30d` |
| `GET /v1/magpie/usage/requests` | 分页 ledger：rows、offset、total、series、by、through/direct/reported 等；limit 默认 100、最大 500。本版不请求，用 usage 汇总与曲线足够 |
| `GET /v1/magpie/quotas/history` | list/data；按 provider/user 返回 lines，每条有 name/points，点包含 at/left/start/resetsAt；days 最多 45。本版未使用，不把额度历史当作 Token 用量趋势 |

**实际发现的文档差异：** 上游 reference 曾将参数描述为 `today|week|month|all`，实现中的 `usage.Week` / `usage.Month` 是 `7d` / `30d`。实测传入 `week` 和 `month` 都回落到 `30d`。客户端把界面的 week/month 映射为 7d/30d，集成测试验证返回的 period。

研究来源：

- [官方集成文档](https://github.com/yetone/magpie/blob/f5b0157420a4491f6e707b49a8af8e87ea8050a1/docs/integrating.md)
- [Quota / QuotaSpan 模型](https://github.com/yetone/magpie/blob/f5b0157420a4491f6e707b49a8af8e87ea8050a1/internal/provider/quotas.go)
- [SubscriptionQuota / QuotaWindow](https://github.com/yetone/magpie/blob/f5b0157420a4491f6e707b49a8af8e87ea8050a1/internal/provider/subscription_usage.go)
- [Usage / Ledger API](https://github.com/yetone/magpie/blob/f5b0157420a4491f6e707b49a8af8e87ea8050a1/internal/usageapi/usageapi.go)
- [Totals / Period / Summary](https://github.com/yetone/magpie/blob/f5b0157420a4491f6e707b49a8af8e87ea8050a1/internal/usage/usage.go)

### 统计口径

- `used` / `remaining` 使用 0–100；不把 72 当作 0.72。缺少 remaining 时由 used 推导；没有两者时显示未知，不显示 0%。
- 保留原始窗口名称、独立 reset、原始余额字符串、display/amount/limit/unit；无限制不画成 100% 剩余。
- Token 总量沿用 Magpie 的 `input + output`，不额外加缓存或 reasoning，避免重复统计。
- 费用为 Magpie 按有效价格计算或调用方上报的金额；汇总不能可靠区分两者，所以统一标“估算费用”，不冒充真实订阅账单。缺失定价数量单独说明。
- 总计直接取服务端汇总，绝不把 agents + models + providers 相加。供应商维度仅对互斥 model 行按 provider 分组。
- 服务端决定每日边界和时间桶，客户端不重新切日；图表显示时间按本机时区。
- 只有经过 Magpie、被其导入或由调用方上报的调用才能计入。
- 未提供字段保留 nil；不兼容类型会触发诊断并保留旧数据。404 说明版本不支持，403 说明网关权限不足，不回退成零用量。

## 项目结构

```text
MagpieWidget.xcodeproj/     主应用 + 真实 Widget Extension
project.yml                可重新生成的 XcodeGen 配置
MagpieApp/                 单窗口概览、菜单栏、同步、Keychain、设置
MagpieWidgets/             App Intent 配置、切换动作、Timeline、三种尺寸
Shared/                    Codable 模型、格式化、客户端、原子存储、展示偏好
Config/                    Info.plist、entitlements
Resources/Assets.xcassets/ 图标与强调色
Scripts/                   本地构建与图标生成
Tests/                     Swift Package 核心测试
```

## 已执行验证

- 主应用和 Widget Extension `xcodebuild` 编译成功；Apple Development 签名构建成功。
- 10 项 XCTest 通过，覆盖额度比例、unknown/unlimited/余额、异常字段、ISO8601 纳秒和时区、统计不重复、缓存原子写入与损坏/版本回退、离线/403/恢复、endpoint 安全、展示偏好共享、本机真实网关。
- 实际运行主应用读取真实额度与统计，App Group 写入成功。
- 桌面 WidgetKit 扩展读取真实快照，显示订阅额度。
- 小组件刷新打开同一主窗口，修复初版重复窗口问题。
- 实际点击小号组件从 Cursor 切换为 Grok；主应用关闭同步时间后桌面对应文本消失。
- 未停止用户的真实 Magpie 进程；离线与恢复通过受控 URLProtocol 测试。
- 未完成远程 HTTPS 网关的实际联调、Developer ID 公证、所有历史 Magpie 版本及每种 macOS 外观组合测试。

若开发中替换了 App Group 或签名，已运行的旧扩展可能仍持有旧配置。关闭本项目的主应用/扩展进程、重新启动已签名构建并请求刷新；不要删除整个 Group Containers 目录，也不要把不同签名的多个构建同时用于验收。
