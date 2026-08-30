import Foundation

enum APIError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case notAuthenticated
    case problem(Problem)
    case httpStatus(Int)
    case incompatibleServer(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Adresse du serveur invalide."
        case .invalidResponse:
            return "Réponse invalide du serveur."
        case .notAuthenticated:
            return "Session non authentifiée."
        case .problem(let problem):
            return problem.detail ?? problem.title
        case .httpStatus(let status):
            return "Erreur HTTP \(status)."
        case .incompatibleServer(let message):
            return message
        }
    }
}

actor APIClient {
    static let clientAPIVersion = "1.2.0"

    private var baseURL: URL
    private var tokens: TokenPair?
    private let keychain: KeychainStore
    private let refreshTokenAccount = "refresh-token"

    init(baseURL: URL, keychain: KeychainStore) {
        self.baseURL = baseURL
        self.keychain = keychain
    }

    func systemInfo() async throws -> SystemInfo {
        try await request(
            path: "/api/v1/system/info",
            method: "GET",
            authorized: false,
            expected: [200],
            as: SystemInfo.self
        )
    }

    func validateCompatibility(_ info: SystemInfo) throws {
        guard let client = SemanticVersion(Self.clientAPIVersion),
              let minimum = SemanticVersion(info.minimumClientApiVersion),
              let server = SemanticVersion(info.apiVersion) else {
            return
        }

        if minimum > client {
            throw APIError.incompatibleServer(
                "Le serveur exige au minimum l'API \(info.minimumClientApiVersion), " +
                "mais ce client implémente \(Self.clientAPIVersion)."
            )
        }

        if client.major != server.major {
            throw APIError.incompatibleServer(
                "Version majeure d'API incompatible : client \(Self.clientAPIVersion), serveur \(info.apiVersion)."
            )
        }
    }

    func login(username: String, password: String, clientID: String) async throws -> TokenPair {
        let body = LoginRequest(
            username: username,
            password: password,
            clientId: clientID,
            clientName: "TrainPilot macOS",
            platform: "macOS"
        )

        let pair: TokenPair = try await request(
            path: "/api/v1/auth/login",
            method: "POST",
            body: body,
            authorized: false,
            expected: [200],
            as: TokenPair.self
        )
        try save(pair)
        return pair
    }

    func restore(refreshToken: String) async throws -> TokenPair {
        let pair = try await refresh(using: refreshToken)
        try save(pair)
        return pair
    }

    func currentTokens() -> TokenPair? {
        tokens
    }

    func accessTokenForWebSocket() async throws -> String {
        try await ensureFreshAccessToken()
        guard let accessToken = tokens?.accessToken else {
            throw APIError.notAuthenticated
        }
        return accessToken
    }

    func listLocomotives() async throws -> [Locomotive] {
        let response: ItemsResponse<Locomotive> = try await request(
            path: "/api/v1/locomotives",
            method: "GET",
            expected: [200],
            as: ItemsResponse<Locomotive>.self
        )
        return response.items
    }

    func stationStatus() async throws -> StationStatus {
        try await request(
            path: "/api/v1/station/status",
            method: "GET",
            expected: [200],
            as: StationStatus.self
        )
    }

    func acquire(locomotiveID: String) async throws -> ControlLease {
        try await request(
            path: "/api/v1/locomotives/\(urlComponent(locomotiveID))/control-lease",
            method: "POST",
            expected: [201],
            as: ControlLease.self
        )
    }

    func heartbeat(leaseID: String) async throws -> ControlLease {
        try await request(
            path: "/api/v1/control-leases/\(urlComponent(leaseID))/heartbeat",
            method: "PUT",
            expected: [200],
            as: ControlLease.self
        )
    }

    func release(leaseID: String) async throws {
        try await requestNoContent(
            path: "/api/v1/control-leases/\(urlComponent(leaseID))",
            method: "DELETE",
            expected: [202]
        )
    }

    func throttle(
        locomotiveID: String,
        leaseID: String,
        speed: Int,
        direction: DCCDirection
    ) async throws {
        try await requestNoContent(
            path: "/api/v1/locomotives/\(urlComponent(locomotiveID))/throttle",
            method: "PUT",
            body: ThrottleCommand(leaseId: leaseID, speed: speed, direction: direction),
            expected: [204]
        )
    }

    func setFunction(
        locomotiveID: String,
        leaseID: String,
        functionNumber: Int,
        enabled: Bool
    ) async throws {
        try await requestNoContent(
            path: "/api/v1/locomotives/\(urlComponent(locomotiveID))/functions/\(functionNumber)",
            method: "PUT",
            body: FunctionCommand(leaseId: leaseID, enabled: enabled),
            expected: [204]
        )
    }

    func setTrackPower(_ enabled: Bool) async throws {
        try await requestNoContent(
            path: "/api/v1/track-power",
            method: "PUT",
            body: TrackPowerCommand(enabled: enabled),
            expected: [204]
        )
    }

    func emergencyStop() async throws {
        try await requestNoContent(
            path: "/api/v1/emergency-stop",
            method: "POST",
            expected: [204]
        )
    }

    func logout() async {
        if tokens != nil {
            try? await requestNoContent(
                path: "/api/v1/auth/logout",
                method: "POST",
                expected: [204],
                allowRefresh: false
            )
        }
        tokens = nil
        keychain.delete(account: refreshTokenAccount)
    }

    private func save(_ pair: TokenPair) throws {
        tokens = pair
        try keychain.save(pair.refreshToken, account: refreshTokenAccount)
    }

    private func ensureFreshAccessToken() async throws {
        guard let tokens else {
            throw APIError.notAuthenticated
        }
        if tokens.accessExpiresAt.timeIntervalSinceNow > 30 {
            return
        }
        let pair = try await refresh(using: tokens.refreshToken)
        try save(pair)
    }

    private func refresh(using refreshToken: String) async throws -> TokenPair {
        try await request(
            path: "/api/v1/auth/refresh",
            method: "POST",
            body: RefreshRequest(refreshToken: refreshToken),
            authorized: false,
            expected: [200],
            allowRefresh: false,
            as: TokenPair.self
        )
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        authorized: Bool = true,
        expected: Set<Int>,
        allowRefresh: Bool = true,
        as type: T.Type
    ) async throws -> T {
        try await request(
            path: path,
            method: method,
            bodyData: nil,
            authorized: authorized,
            expected: expected,
            allowRefresh: allowRefresh,
            as: type
        )
    }

    private func request<B: Encodable, T: Decodable>(
        path: String,
        method: String,
        body: B,
        authorized: Bool = true,
        expected: Set<Int>,
        allowRefresh: Bool = true,
        as type: T.Type
    ) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(
            path: path,
            method: method,
            bodyData: data,
            authorized: authorized,
            expected: expected,
            allowRefresh: allowRefresh,
            as: type
        )
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        authorized: Bool,
        expected: Set<Int>,
        allowRefresh: Bool,
        as type: T.Type
    ) async throws -> T {
        let data = try await perform(
            path: path,
            method: method,
            bodyData: bodyData,
            authorized: authorized,
            expected: expected,
            allowRefresh: allowRefresh
        )
        return try JSONDecoder.trainPilot.decode(T.self, from: data)
    }

    private func requestNoContent(
        path: String,
        method: String,
        authorized: Bool = true,
        expected: Set<Int>,
        allowRefresh: Bool = true
    ) async throws {
        _ = try await perform(
            path: path,
            method: method,
            bodyData: nil,
            authorized: authorized,
            expected: expected,
            allowRefresh: allowRefresh
        )
    }

    private func requestNoContent<B: Encodable>(
        path: String,
        method: String,
        body: B,
        authorized: Bool = true,
        expected: Set<Int>,
        allowRefresh: Bool = true
    ) async throws {
        _ = try await perform(
            path: path,
            method: method,
            bodyData: try JSONEncoder().encode(body),
            authorized: authorized,
            expected: expected,
            allowRefresh: allowRefresh
        )
    }

    private func perform(
        path: String,
        method: String,
        bodyData: Data?,
        authorized: Bool,
        expected: Set<Int>,
        allowRefresh: Bool
    ) async throws -> Data {
        if authorized {
            try await ensureFreshAccessToken()
        }

        var request = try makeRequest(path: path, method: method, bodyData: bodyData)
        if authorized, let accessToken = tokens?.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401, authorized, allowRefresh, let refreshToken = tokens?.refreshToken {
            let pair = try await refresh(using: refreshToken)
            try save(pair)
            return try await perform(
                path: path,
                method: method,
                bodyData: bodyData,
                authorized: authorized,
                expected: expected,
                allowRefresh: false
            )
        }

        guard expected.contains(http.statusCode) else {
            if let problem = try? JSONDecoder.trainPilot.decode(Problem.self, from: data) {
                throw APIError.problem(problem)
            }
            throw APIError.httpStatus(http.statusCode)
        }

        return data
    }

    private func makeRequest(path: String, method: String, bodyData: Data?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidServerURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func urlComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
