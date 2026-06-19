import AppKit
import Foundation

enum GoogleCalendarConfig {
    static let loopbackRedirectBase = "http://127.0.0.1"
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"
    static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    static let eventsEndpoint = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
    private static let secretsFileName = "GoogleOAuthSecrets"

    static var clientID: String? {
        bundledSecret(forKey: "GoogleOAuthClientID")
            ?? infoPlistValue(forKey: "GoogleOAuthClientID")
    }

    static var clientSecret: String? {
        bundledSecret(forKey: "GoogleOAuthClientSecret")
            ?? infoPlistValue(forKey: "GoogleOAuthClientSecret")
    }

    static var isConfigured: Bool {
        clientID != nil && clientSecret != nil
    }

    static var setupHint: String {
        """
        Copy GoogleOAuthSecrets.example.plist to GoogleOAuthSecrets.plist, \
        add your Client ID and Secret, then rebuild.
        """
    }

    private static func bundledSecret(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: secretsFileName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = plist[key] as? String else { return nil }
        return sanitized(raw)
    }

    private static func infoPlistValue(forKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        return sanitized(raw)
    }

    private static func sanitized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("YOUR_") else { return nil }
        return trimmed
    }
}

final class GoogleOAuth {
    static let shared = GoogleOAuth()

    private let accessTokenKey = "GoogleOAuthAccessToken"
    private let refreshTokenKey = "GoogleOAuthRefreshToken"
    private let expiryKey = "GoogleOAuthExpiry"
    private var loopbackServer: GoogleOAuthLoopbackServer?
    private var pendingRedirectURI: String?

    var isConfigured: Bool { GoogleCalendarConfig.isConfigured }

    var isConnected: Bool {
        refreshToken() != nil || validAccessToken() != nil
    }

    func signOut() {
        deleteToken(accessTokenKey)
        deleteToken(refreshTokenKey)
        deleteToken(expiryKey)
    }

    private var pendingCompletion: ((Result<Void, Error>) -> Void)?
    private var authCompleted = false

    func authorize(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let clientID = GoogleCalendarConfig.clientID else {
            completion(.failure(GoogleOAuthError.notConfigured))
            return
        }

        authCompleted = false
        pendingCompletion = completion
        loopbackServer?.stop()
        let server = GoogleOAuthLoopbackServer()
        loopbackServer = server

        server.onCode = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let code):
                guard let redirectURI = self.pendingRedirectURI else {
                    self.stopLoopback()
                    self.completeOnce(.failure(GoogleOAuthError.invalidURL))
                    return
                }
                self.exchangeCodeForTokens(code: code, redirectURI: redirectURI) { tokenResult in
                    self.stopLoopback()
                    self.completeOnce(tokenResult)
                }
            case .failure(let error):
                self.stopLoopback()
                self.completeOnce(.failure(error))
            }
        }

        server.start { [weak self] startResult in
            guard let self else { return }
            switch startResult {
            case .failure(let error):
                self.loopbackServer = nil
                self.completeOnce(.failure(error))
            case .success(let port):
                let redirectURI = "\(GoogleCalendarConfig.loopbackRedirectBase):\(port)/"
                self.pendingRedirectURI = redirectURI

                var components = URLComponents(string: GoogleCalendarConfig.authEndpoint)!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "redirect_uri", value: redirectURI),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: GoogleCalendarConfig.scope),
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "prompt", value: "consent"),
                ]

                guard let authURL = components.url else {
                    self.stopLoopback()
                    self.completeOnce(.failure(GoogleOAuthError.invalidURL))
                    return
                }

                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    if !NSWorkspace.shared.open(authURL) {
                        self.stopLoopback()
                        self.completeOnce(.failure(GoogleOAuthError.browserOpenFailed))
                    }
                }
            }
        }
    }

    private func completeOnce(_ result: Result<Void, Error>) {
        guard !authCompleted else { return }
        authCompleted = true
        pendingCompletion?(result)
        pendingCompletion = nil
        pendingRedirectURI = nil
    }

    private func stopLoopback() {
        loopbackServer?.stop()
        loopbackServer = nil
    }

    func validAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        if let token = validAccessToken() {
            completion(.success(token))
            return
        }
        refreshAccessToken(completion: completion)
    }

    private func validAccessToken() -> String? {
        guard let token = readToken(accessTokenKey),
              let expiryString = readToken(expiryKey),
              let expiry = TimeInterval(expiryString) else { return nil }
        if Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }
        return nil
    }

    private func exchangeCodeForTokens(code: String, redirectURI: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let clientID = GoogleCalendarConfig.clientID else {
            completion(.failure(GoogleOAuthError.notConfigured))
            return
        }

        let bodyItems = tokenBodyItems(code: code, redirectURI: redirectURI)

        postTokenRequest(bodyItems: bodyItems) { result in
            switch result {
            case .success(let json):
                self.storeTokens(from: json)
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func refreshAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let clientID = GoogleCalendarConfig.clientID else {
            completion(.failure(GoogleOAuthError.notConfigured))
            return
        }
        guard let refresh = refreshToken() else {
            completion(.failure(GoogleOAuthError.notConnected))
            return
        }

        var bodyItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refresh),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        if let secret = GoogleCalendarConfig.clientSecret {
            bodyItems.append(URLQueryItem(name: "client_secret", value: secret))
        }

        postTokenRequest(bodyItems: bodyItems) { result in
            switch result {
            case .success(let json):
                self.storeTokens(from: json)
                if let token = self.validAccessToken() {
                    completion(.success(token))
                } else {
                    completion(.failure(GoogleOAuthError.missingAccessToken))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func tokenBodyItems(code: String, redirectURI: String) -> [URLQueryItem] {
        guard let clientID = GoogleCalendarConfig.clientID else { return [] }
        var items = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
        ]
        if let secret = GoogleCalendarConfig.clientSecret {
            items.append(URLQueryItem(name: "client_secret", value: secret))
        }
        return items
    }

    private func postTokenRequest(bodyItems: [URLQueryItem], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: GoogleCalendarConfig.tokenEndpoint) else {
            completion(.failure(GoogleOAuthError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyItems
            .compactMap { item -> String? in
                guard let value = item.value else { return nil }
                let name = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.name
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(name)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(.failure(GoogleOAuthError.invalidResponse)) }
                return
            }
            if let message = json["error"] as? String {
                let detail = json["error_description"] as? String ?? message
                DispatchQueue.main.async { completion(.failure(GoogleOAuthError.apiError(detail))) }
                return
            }
            DispatchQueue.main.async { completion(.success(json)) }
        }.resume()
    }

    private func storeTokens(from json: [String: Any]) {
        if let accessToken = json["access_token"] as? String {
            saveToken(accessToken, key: accessTokenKey)
        }
        if let refreshToken = json["refresh_token"] as? String {
            saveToken(refreshToken, key: refreshTokenKey)
        }
        if let expiresIn = json["expires_in"] as? TimeInterval {
            let expiry = Date().timeIntervalSince1970 + expiresIn
            saveToken(String(expiry), key: expiryKey)
        }
    }

    private func refreshToken() -> String? {
        readToken(refreshTokenKey)
    }

    private func saveToken(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func readToken(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    private func deleteToken(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum GoogleOAuthError: LocalizedError {
    case notConfigured
    case notConnected
    case invalidURL
    case missingAuthCode
    case missingAccessToken
    case invalidResponse
    case apiError(String)
    case authInProgress
    case authTimeout
    case browserOpenFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google OAuth client ID is not configured."
        case .notConnected:
            return "Google Calendar is not connected."
        case .invalidURL:
            return "Invalid Google OAuth URL."
        case .missingAuthCode:
            return "Google sign-in did not return an authorization code."
        case .missingAccessToken:
            return "Google did not return an access token."
        case .invalidResponse:
            return "Unexpected response from Google."
        case .apiError(let message):
            return message
        case .authInProgress:
            return "Complete sign-in in your browser, then return to Jazz."
        case .authTimeout:
            return "Google sign-in timed out. Click Connect Google Calendar to try again."
        case .browserOpenFailed:
            return "Could not open your browser for Google sign-in."
        }
    }
}
