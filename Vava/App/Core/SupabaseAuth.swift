import Foundation

@MainActor final class SupabaseAuth {
    private struct Session: Decodable {
        struct User: Decodable { let id: UUID }
        let user: User
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private let base: URL
    private let key: String
    private let transport: URLSession
    private var session: Session?
    private var expiresAt = Date.distantPast

    init() throws {
        guard let ref = Bundle.main.object(forInfoDictionaryKey: "VavaSupabaseProjectRef") as? String,
            ref.range(of: #"^[a-z0-9]{20}$"#, options: .regularExpression) != nil,
            let url = URL(string: "https://" + ref + ".supabase.co"),
            let key = Bundle.main.object(forInfoDictionaryKey: "VavaSupabasePublishableKey") as? String,
            key.hasPrefix("sb_publishable_")
        else { throw AppFailure("Account sign-in is not configured yet.") }
        self.base = url
        self.key = key
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        transport = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
    }

    deinit { transport.invalidateAndCancel() }

    static func isEmail(_ value: String) -> Bool {
        value.utf8.count <= 254
            && value.range(of: #"^[^@\s]+@[^@\s.]+(?:\.[^@\s.]+)+$"#, options: .regularExpression) != nil
    }

    func signIn(email: String, password: String) async throws -> UUID {
        guard Self.isEmail(email), !password.isEmpty else { throw AppFailure("Enter your email and password.") }
        return try await exchange(grant: "password", body: ["email": email, "password": password]).user.id
    }

    private func exchange(grant: String, body: [String: String]) async throws -> Session {
        let data = try await post(
            "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: grant)], body: body)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let next = try? decoder.decode(Session.self, from: data),
            !next.accessToken.isEmpty, !next.refreshToken.isEmpty, next.expiresIn > 0,
            session == nil || session?.user.id == next.user.id
        else { throw AppFailure("Your account session could not be verified. Please log in again.") }
        session = next
        expiresAt = Date().addingTimeInterval(next.expiresIn)
        return next
    }

    private func activeToken() async throws -> String {
        guard let session else { throw AppFailure("Please log in again.") }
        if expiresAt.timeIntervalSinceNow > 30 { return session.accessToken }
        let next = try await exchange(grant: "refresh_token", body: ["refresh_token": session.refreshToken])
        return next.accessToken
    }

    func signOut() async {
        defer { session = nil }
        guard let token = try? await activeToken() else { return }
        _ = try? await post(
            "auth/v1/logout", query: [URLQueryItem(name: "scope", value: "local")], token: token)
    }

    private func post(
        _ path: String, query: [URLQueryItem] = [], body: [String: String] = [:], token: String? = nil
    ) async throws -> Data {
        let endpoint = base.appendingPathComponent(path).appending(queryItems: query)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let result: (Data, URLResponse)
        do {
            result = try await transport.data(for: request)
        } catch {
            throw AppFailure("Could not reach the account service. Check your connection and try again.")
        }
        guard let response = result.1 as? HTTPURLResponse else {
            throw AppFailure("The account service is unavailable.")
        }
        switch response.statusCode {
        case 200..<300: return result.0
        case 429: throw AppFailure("Too many attempts. Please wait before trying again.")
        default:
            let details = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any]
            switch details?["error_code"] as? String {
            case "invalid_credentials": throw AppFailure("The email or password is incorrect.")
            case "email_not_confirmed": throw AppFailure("Confirm your email address before logging in.")
            default: throw AppFailure("Your account request could not be completed. Please try again.")
            }
        }
    }
}
