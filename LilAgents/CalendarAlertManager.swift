import Foundation

struct GoogleCalendarEvent {
    let id: String
    let title: String
    let startDate: Date
}

final class CalendarAlertManager {
    static let leadMinutes: TimeInterval = 10

    private var pollTimer: Timer?
    private var alertedKeys = Set<String>()
    private var isConnected = false
    private var isAuthorizing = false
    private var lastErrorMessage: String?

    var onCalendarAlert: ((String) -> Void)?
    var onAccessChanged: ((Bool) -> Void)?

    var statusMessage: String {
        if let lastErrorMessage, !lastErrorMessage.isEmpty, !GoogleOAuth.shared.isConfigured {
            return lastErrorMessage
        }
        if !GoogleOAuth.shared.isConfigured {
            return GoogleCalendarConfig.setupHint
        }
        if isConnected {
            return "Google Calendar connected — Jazz alerts 10 min before meetings."
        }
        if isAuthorizing {
            return GoogleOAuthError.authInProgress.localizedDescription ?? "Complete sign-in in your browser, then return to Jazz."
        }
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return lastErrorMessage
        }
        return "Connect Google Calendar so Jazz can alert you 10 min before calls."
    }

    func start() {
        isConnected = GoogleOAuth.shared.isConnected
        onAccessChanged?(isConnected)
        if isConnected {
            startPolling()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func requestAccess(completion: ((Bool) -> Void)? = nil) {
        guard GoogleOAuth.shared.isConfigured else {
            lastErrorMessage = GoogleCalendarConfig.setupHint
            onAccessChanged?(false)
            completion?(false)
            return
        }

        isAuthorizing = true
        lastErrorMessage = nil
        onAccessChanged?(false)

        GoogleOAuth.shared.authorize { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthorizing = false
                switch result {
                case .success:
                    self.lastErrorMessage = nil
                    self.isConnected = true
                    self.onAccessChanged?(true)
                    self.startPolling()
                    completion?(true)
                case .failure(let error):
                    self.isConnected = false
                    self.lastErrorMessage = error.localizedDescription
                    self.onAccessChanged?(false)
                    completion?(false)
                }
            }
        }
    }

    func disconnect() {
        GoogleOAuth.shared.signOut()
        isConnected = false
        lastErrorMessage = nil
        stop()
        onAccessChanged?(false)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        checkUpcomingEvents()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkUpcomingEvents()
        }
    }

    private func checkUpcomingEvents() {
        guard GoogleOAuth.shared.isConnected else { return }

        GoogleOAuth.shared.validAccessToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.isConnected = false
                self.lastErrorMessage = error.localizedDescription
                self.onAccessChanged?(false)
                self.stop()
            case .success(let token):
                self.fetchEvents(accessToken: token)
            }
        }
    }

    private func fetchEvents(accessToken: String) {
        let now = Date()
        guard let horizon = Calendar.current.date(byAdding: .hour, value: 24, to: now) else { return }

        var components = URLComponents(string: GoogleCalendarConfig.eventsEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso8601String(now)),
            URLQueryItem(name: "timeMax", value: iso8601String(horizon)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.lastErrorMessage = error.localizedDescription
                }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if let apiError = json["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                DispatchQueue.main.async {
                    self.lastErrorMessage = message
                    if (apiError["code"] as? Int) == 401 {
                        self.isConnected = false
                        self.onAccessChanged?(false)
                        self.stop()
                    }
                }
                return
            }

            let events = self.parseEvents(from: json)
            DispatchQueue.main.async {
                self.lastErrorMessage = nil
                self.process(events: events, relativeTo: now)
            }
        }.resume()
    }

    private func parseEvents(from json: [String: Any]) -> [GoogleCalendarEvent] {
        guard let items = json["items"] as? [[String: Any]] else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let title = (item["summary"] as? String ?? "Meeting").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start = item["start"] as? [String: Any],
                  let dateTime = start["dateTime"] as? String else { return nil }
            let startDate = formatter.date(from: dateTime) ?? fallbackFormatter.date(from: dateTime)
            guard let startDate else { return nil }
            return GoogleCalendarEvent(id: id, title: title, startDate: startDate)
        }
    }

    private func process(events: [GoogleCalendarEvent], relativeTo now: Date) {
        let lead = Self.leadMinutes * 60
        let window: TimeInterval = 90

        for event in events where event.startDate > now {
            let secondsUntilStart = event.startDate.timeIntervalSince(now)
            let secondsUntilAlert = secondsUntilStart - lead
            guard secondsUntilAlert >= -window / 2, secondsUntilAlert <= window / 2 else { continue }

            let key = "\(event.id)|\(event.startDate.timeIntervalSince1970)"
            guard !alertedKeys.contains(key) else { continue }

            alertedKeys.insert(key)
            onCalendarAlert?(event.title)
        }

        pruneAlertedKeys()
    }

    private func pruneAlertedKeys() {
        guard alertedKeys.count > 200 else { return }
        alertedKeys = Set(alertedKeys.suffix(100))
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
