import XCTest
@testable import MagpieCore

final class CoreTests: XCTestCase {
    func decode<T: Decodable>(_ text: String, as type: T.Type) throws -> T { try Wire.decoder().decode(type, from: Data(text.utf8)) }
    func testQuotaSemanticsAndUnknowns() throws {
        let envelope = try decode(#"{"object":"list","data":[{"provider":"claude","name":"Claude","kind":"subscription","alias":"Work","windows":[{"name":"5h","used":72,"remaining":28,"resetsAt":"2026-10-22T02:00:00.123456789Z"},{"name":"7d","used":12},{"name":"unknown"},{"name":"infinite","unlimited":true,"used":0}]}]}"#, as: QuotaEnvelope.self)
        let quota = try XCTUnwrap(envelope.data.first)
        let windows = try XCTUnwrap(quota.windows)
        XCTAssertEqual(quota.title, "Work")
        XCTAssertEqual(windows[0].remainingPercent, 28)
        XCTAssertEqual(windows[1].remainingPercent, 88)
        XCTAssertNil(windows[2].remainingPercent)
        XCTAssertNil(windows[3].remainingPercent)
        XCTAssertNotNil(windows[0].resetsAt)
        XCTAssertEqual(try decode(#"{"provider":"key","name":"Balance","balance":"CNY 12.50"}"#, as: Quota.self).balance, "CNY 12.50")
    }
    func testOutOfRangeAndNullData() throws {
        XCTAssertEqual(try decode(#"{"name":"credits","used":120}"#, as: QuotaWindow.self).remainingPercent, 0)
        let quota = try decode(#"{"provider":"x","name":"X","windows":null,"error":"unavailable"}"#, as: Quota.self)
        XCTAssertNil(quota.windows)
        XCTAssertEqual(quota.measurementState, "提供商暂不可用")
        XCTAssertThrowsError(try decode(#"{"name":"5h","used":"unexpected"}"#, as: QuotaWindow.self))
    }
    func testTotalsDoNotCountCacheOrDimensionsTwice() throws {
        let usage = try decode(#"{"period":"today","calls":3,"input":100,"output":20,"cache_read":900,"cache_write":400,"cost":0.4,"agents":[{"id":"a","calls":3}],"models":[{"id":"m1","provider":"p","calls":1,"input":30,"output":10,"cost":0.1},{"id":"m2","provider":"p","calls":2,"input":70,"output":10,"cost":0.3}]}"#, as: Usage.self)
        XCTAssertEqual(usage.tokens, 120)
        XCTAssertEqual(usage.calls, 3)
        XCTAssertEqual(usage.providers.count, 1)
        XCTAssertEqual(usage.providers[0].calls, 3)
        XCTAssertEqual(usage.providers[0].cost!, 0.4, accuracy: 0.00001)
        XCTAssertNil(try decode(#"{"period":"today"}"#, as: Usage.self).tokens)
    }
    func testTimestampOffsetsAndInvalidTime() throws {
        let a = try decode(#"{"name":"a","resetsAt":"2026-10-22T08:00:00+08:00"}"#, as: QuotaWindow.self)
        let b = try decode(#"{"name":"a","resetsAt":"2026-10-22T00:00:00Z"}"#, as: QuotaWindow.self)
        XCTAssertEqual(a.resetsAt, b.resetsAt)
        XCTAssertThrowsError(try decode(#"{"name":"a","resetsAt":"invalid"}"#, as: QuotaWindow.self))
    }
    func testAtomicCacheAndCorruptionFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)
        XCTAssertNil(store.load().updatedAt)
        var original = Snapshot(); original.updatedAt = Date(timeIntervalSince1970: 1000)
        try store.save(original)
        var offline = original; offline.issue = "offline"; offline.attemptedAt = Date(timeIntervalSince1970: 2000)
        try store.save(offline)
        XCTAssertEqual(store.load().updatedAt, original.updatedAt)
        XCTAssertEqual(store.load().issue, "offline")
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        XCTAssertEqual(store.load().updatedAt, original.updatedAt)
        var future = Snapshot(); future.schema = 999
        try Wire.encoder().encode(future).write(to: directory.appendingPathComponent("snapshot.json"))
        XCTAssertEqual(store.load().updatedAt, original.updatedAt)
        XCTAssertThrowsError(try SnapshotStore(directory: nil).save(original))
    }
    func testStalenessAndStatus() {
        var snapshot = Snapshot()
        XCTAssertTrue(snapshot.stale())
        snapshot.updatedAt = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(snapshot.stale(at: Date(timeIntervalSince1970: 200)))
        XCTAssertTrue(snapshot.stale(at: Date(timeIntervalSince1970: 281)))
        snapshot.issue = "offline"
        XCTAssertEqual(snapshot.status, "离线 / 同步异常")
    }
    func testEndpointSecurity() throws {
        XCTAssertNoThrow(try Endpoint.validate("http://127.0.0.1:3425"))
        XCTAssertNoThrow(try Endpoint.validate("https://example.com:8443"))
        for invalid in ["http://example.com", "https://user:secret@example.com", "file:///tmp/x", "https://example.com?token=secret", "https://example.com/v1", "https://example.com/#token"] {
            XCTAssertThrowsError(try Endpoint.validate(invalid), invalid)
        }
    }
    func testHTTPErrorOfflineAndRecovery() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let client = try MagpieClient(endpoint: "http://127.0.0.1:3425", session: URLSession(configuration: config))
        StubProtocol.response = (403, "{}")
        do { _ = try await client.hello(); XCTFail("Should fail") } catch GatewayError.http(let code) { XCTAssertEqual(code, 403) }
        StubProtocol.response = (200, #"{"name":"other","version":"1"}"#)
        do { _ = try await client.hello(); XCTFail("Wrong server") } catch GatewayError.wrongServer {}
        StubProtocol.failure = URLError(.cannotConnectToHost)
        do { _ = try await client.hello(); XCTFail("Offline") } catch { XCTAssertTrue(error is URLError) }
        StubProtocol.failure = nil
        StubProtocol.response = (200, #"{"name":"magpie","version":"test"}"#)
        let hello = try await client.hello()
        XCTAssertEqual(hello.version, "test")
        XCTAssertEqual(StubProtocol.lastMethod, "GET")
    }
    func testWidgetPreferencesShareAndRecover() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = WidgetPreferencesStore(directory: directory)
        let reader = WidgetPreferencesStore(directory: directory)
        var preferences = WidgetPreferences()
        preferences.providerIDs = ["codex"]
        preferences.showCost = false
        preferences.showReset = false
        preferences.chartMetric = "cost"
        try writer.save(preferences)
        XCTAssertEqual(reader.load(), preferences)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("widget-preferences.json"))
        XCTAssertEqual(reader.load(), WidgetPreferences())
    }

    func testLiveGatewayWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["MAGPIE_LIVE_TEST"] == "1" else { throw XCTSkip("Set MAGPIE_LIVE_TEST=1 for read-only live integration") }
        let client = try MagpieClient(endpoint: Endpoint.detect())
        let hello = try await client.hello(); XCTAssertEqual(hello.name, "magpie")
        _ = try await client.quotas()
        for period in ["today", "week", "month"] {
            let usage = try await client.usage(period)
            XCTAssertEqual(usage.period, period == "week" ? "7d" : period == "month" ? "30d" : period)
            XCTAssertNotNil(usage.calls)
        }
    }
}
private final class StubProtocol: URLProtocol {
    static var response = (200, "{}")
    static var failure: Error?
    static var lastMethod: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastMethod = request.httpMethod
        if let error = Self.failure { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.response.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
