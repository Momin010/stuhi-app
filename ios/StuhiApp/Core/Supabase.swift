import Foundation

// Hand-rolled Supabase client: GoTrue auth + PostgREST + RPC.
//
// Deliberately no SPM dependency. Zero third-party SDKs means zero extra
// privacy manifests to merge, nothing collecting data behind our back, and
// one fewer thing to explain to App Review.

actor Supabase {
    static let shared = Supabase()

    private let base: URL
    private let apiKey: String
    private let session: URLSession

    // Auth state. Held here, persisted to the keychain by TokenStore.
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    /// One refresh at a time. Parallel requests would otherwise each spend the
    /// same refresh token, and the losers log the user out.
    private var refreshing: Task<Void, Error>?

    private init() {
        guard let url = URL(string: Config.supabaseURL) else {
            fatalError("Config.supabaseURL is not a valid URL")
        }
        base = url
        apiKey = Config.supabasePublishableKey

        let cfg = URLSessionConfiguration.default
        // Fail fast. waitsForConnectivity made a request on a bad network wait
        // for up to the resource timeout (7 days by default) — that was the
        // "sign in spins forever".
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)

        if let stored = TokenStore.load() {
            accessToken = stored.accessToken
            refreshToken = stored.refreshToken
            expiresAt = stored.expiresAt
        }
    }

    var isSignedIn: Bool { accessToken != nil }

    // MARK: - JSON

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Postgres timestamptz comes back in several shapes depending on
    /// precision — with or without fractional seconds, and sometimes with a
    /// `+00:00` offset rather than `Z`. One strategy that tries each.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }
            // PostgREST occasionally omits the timezone entirely.
            let padded = raw.contains("+") || raw.hasSuffix("Z") ? raw : raw + "Z"
            if let date = withFraction.date(from: padded) { return date }
            if let date = plain.date(from: padded) { return date }
            throw StuhiError.decoding("date '\(raw)'")
        }
        return d
    }()

    // MARK: - Request plumbing

    private func request(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:],
        authed: Bool = true
    ) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authed {
            try await refreshIfNeeded()
            req.setValue("Bearer \(accessToken ?? apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw StuhiError.message("No response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            // A 401 on an authed call means our token died under us.
            if http.statusCode == 401, authed { await clearSession() }
            throw StuhiError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Auth

    struct AuthResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
    }

    func signUp(email: String, password: String, fullName: String) async throws {
        let payload: [String: Any] = [
            "email": email,
            "password": password,
            "data": ["full_name": fullName],
        ]
        let data = try await request(
            "POST", path: "auth/v1/signup",
            body: try JSONSerialization.data(withJSONObject: payload),
            authed: false
        )
        // With email confirmation off, signup returns a session directly.
        if let auth = try? JSONDecoder().decode(AuthResponse.self, from: data) {
            store(auth)
        } else {
            // Confirmation is on — the caller shows "check your email".
            throw StuhiError.message("Check your email to confirm your account, then sign in.")
        }
    }

    func signIn(email: String, password: String) async throws {
        let data = try await request(
            "POST", path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            body: try JSONSerialization.data(withJSONObject: ["email": email, "password": password]),
            authed: false
        )
        store(try JSONDecoder().decode(AuthResponse.self, from: data))
    }

    func resetPassword(email: String) async throws {
        _ = try await request(
            "POST", path: "auth/v1/recover",
            body: try JSONSerialization.data(withJSONObject: ["email": email]),
            authed: false
        )
    }

    func signOut() async {
        _ = try? await request("POST", path: "auth/v1/logout", body: Data("{}".utf8))
        await clearSession()
    }

    func clearSession() async {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        TokenStore.clear()
    }

    private func store(_ auth: AuthResponse) {
        accessToken = auth.access_token
        refreshToken = auth.refresh_token
        expiresAt = Date().addingTimeInterval(TimeInterval(auth.expires_in))
        TokenStore.save(.init(
            accessToken: auth.access_token,
            refreshToken: auth.refresh_token,
            expiresAt: expiresAt!
        ))
    }

    /// Refresh 60s before expiry so a long request can't straddle the boundary.
    private func refreshIfNeeded() async throws {
        if let refreshing { return try await refreshing.value }
        guard let refreshToken, let expiresAt else { return }
        guard Date() > expiresAt.addingTimeInterval(-60) else { return }

        let task = Task { try await self.refresh(using: refreshToken) }
        refreshing = task
        defer { refreshing = nil }
        try await task.value
    }

    private func refresh(using refreshToken: String) async throws {
        var comps = URLComponents(url: base.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw StuhiError.message("No response from the server.") }
        // Only a real rejection ends the session. A timeout or a dropped
        // connection leaves the tokens alone so the next try can refresh.
        guard (200..<300).contains(http.statusCode) else {
            if (400..<500).contains(http.statusCode) { await clearSession() }
            throw StuhiError.notSignedIn
        }
        store(try JSONDecoder().decode(AuthResponse.self, from: data))
    }

    // MARK: - PostgREST

    func select<T: Decodable>(
        _ table: String,
        columns: String = "*",
        filters: [URLQueryItem] = [],
        order: String? = nil,
        limit: Int? = nil,
        authed: Bool = true
    ) async throws -> [T] {
        var q = [URLQueryItem(name: "select", value: columns)] + filters
        if let order { q.append(URLQueryItem(name: "order", value: order)) }
        if let limit { q.append(URLQueryItem(name: "limit", value: String(limit))) }

        let data = try await request("GET", path: "rest/v1/\(table)", query: q, authed: authed)
        do {
            return try Self.decoder.decode([T].self, from: data)
        } catch {
            throw StuhiError.decoding("\(table): \(error)")
        }
    }

    func insert<T: Encodable>(_ table: String, _ value: T) async throws {
        _ = try await request(
            "POST", path: "rest/v1/\(table)",
            body: try Self.encoder.encode(value),
            headers: ["Prefer": "return=minimal"]
        )
    }

    func insertRaw(_ table: String, _ object: [String: Any]) async throws {
        _ = try await request(
            "POST", path: "rest/v1/\(table)",
            body: try JSONSerialization.data(withJSONObject: object),
            headers: ["Prefer": "return=minimal"]
        )
    }

    func update(_ table: String, filters: [URLQueryItem], values: [String: Any]) async throws {
        _ = try await request(
            "PATCH", path: "rest/v1/\(table)",
            query: filters,
            body: try JSONSerialization.data(withJSONObject: values),
            headers: ["Prefer": "return=minimal"]
        )
    }

    func delete(_ table: String, filters: [URLQueryItem]) async throws {
        _ = try await request("DELETE", path: "rest/v1/\(table)", query: filters)
    }

    /// Call a Postgres function.
    @discardableResult
    func rpc<T: Decodable>(_ name: String, _ args: [String: Any] = [:], as: T.Type) async throws -> T {
        let data = try await request(
            "POST", path: "rest/v1/rpc/\(name)",
            body: try JSONSerialization.data(withJSONObject: args)
        )
        return try Self.decoder.decode(T.self, from: data)
    }

    func rpcVoid(_ name: String, _ args: [String: Any] = [:]) async throws {
        _ = try await request(
            "POST", path: "rest/v1/rpc/\(name)",
            body: try JSONSerialization.data(withJSONObject: args)
        )
    }

    // MARK: - Convenience filters

    nonisolated static func eq(_ column: String, _ value: String) -> URLQueryItem {
        URLQueryItem(name: column, value: "eq.\(value)")
    }

    nonisolated static func eq(_ column: String, _ value: UUID) -> URLQueryItem {
        URLQueryItem(name: column, value: "eq.\(value.uuidString.lowercased())")
    }
}

// MARK: - Token storage

/// Refresh tokens are long-lived credentials, so they go in the keychain
/// rather than UserDefaults.
enum TokenStore {
    struct Stored: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    private static let service = "org.stuhi.app"
    private static let account = "session"

    static func save(_ value: Stored) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load() -> Stored? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data
        else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
