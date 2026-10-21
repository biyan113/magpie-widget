import Foundation
import OSLog

public struct SnapshotStore {
    public static var groupID: String { Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String ?? "group.net.bytenote.MagpieWidget" }
    public let directory: URL?
    public init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SnapshotStore.groupID)) { self.directory = directory }
    public func load() -> Snapshot {
        guard let directory else { return Snapshot() }
        for name in ["snapshot.json", "previous.json"] {
            do {
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                let value = try Wire.decoder().decode(Snapshot.self, from: data)
                if value.schema == 1 { return value }
            } catch {
                let e = error as NSError
                Logger(subsystem: "net.bytenote.MagpieWidget", category: "Snapshot").error("Snapshot read failed: file=\(name, privacy: .public), domain=\(e.domain, privacy: .public), code=\(e.code), group=\(Self.groupID, privacy: .public)")
            }
        }
        return Snapshot()
    }
    public func save(_ value: Snapshot) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("snapshot.json")
        if let data = try? Data(contentsOf: url), let old = try? Wire.decoder().decode(Snapshot.self, from: data), old.schema == 1 {
            try data.write(to: directory.appendingPathComponent("previous.json"), options: .atomic)
        }
        try Wire.encoder().encode(value).write(to: url, options: .atomic)
    }
}

public enum Endpoint {
    public static func validate(_ text: String) throws -> URL {
        guard let u = URL(string: text), let host = u.host, !host.isEmpty,
              ["http", "https"].contains(u.scheme ?? ""), u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil, u.path.isEmpty || u.path == "/" else {
            throw GatewayError.invalidEndpoint
        }
        guard u.scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(host) else { throw GatewayError.insecureRemote }
        return u
    }
    public static func detect() -> String {
        // Decode ONLY the port; never read provider/account credential files.
        struct Settings: Decodable { var port: Int? }
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
        let url = URL(fileURLWithPath: config).appendingPathComponent("magpie/settings.json")
        if let data = try? Data(contentsOf: url), let settings = try? JSONDecoder().decode(Settings.self, from: data), let port = settings.port, (1...65535).contains(port) {
            return "http://127.0.0.1:\(port)"
        }
        return "http://127.0.0.1:3425"
    }
}
public enum GatewayError: LocalizedError {
    case invalidEndpoint, insecureRemote, wrongServer, http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "请输入不含路径、凭证或查询参数的 Gateway 地址。"
        case .insecureRemote: "远程 Gateway 需要 HTTPS。"
        case .wrongServer: "该服务不是 Magpie。"
        case .http(let code): "Gateway HTTP \(code)" + (code == 403 ? "：网关密钥无权读取这些统计。" : code == 404 ? "：该 Magpie 版本不支持此接口。" : "")
        }
    }
}
public final class MagpieClient: @unchecked Sendable {
    private let session: URLSession
    private let base: URL
    private let token: String?
    public init(endpoint: String, token: String? = nil, session: URLSession? = nil) throws {
        base = try Endpoint.validate(endpoint); self.token = token
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 25; c.timeoutIntervalForResource = 30
        c.urlCache = nil; c.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }
    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("MagpieWidget/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayError.wrongServer }
        guard response.statusCode == 200 else { throw GatewayError.http(response.statusCode) }
        return try Wire.decoder().decode(T.self, from: data)
    }
    public struct Hello: Decodable { public var name: String; public var version: String }
    public func hello() async throws -> Hello {
        let h: Hello = try await get("api/hello")
        guard h.name == "magpie" else { throw GatewayError.wrongServer }; return h
    }
    public func quotas() async throws -> [Quota] {
        let result: QuotaEnvelope = try await get("v1/magpie/quotas")
        return result.data
    }
    public func usage(_ period: String) async throws -> Usage {
        let wirePeriod = period == "week" ? "7d" : period == "month" ? "30d" : period
        return try await get("v1/magpie/usage", query: [.init(name: "period", value: wirePeriod)])
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
