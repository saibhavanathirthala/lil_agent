import Foundation

enum JazzSettings {
    static let userName = "Bhavana"

    static func reminderBubble(message: String) -> String {
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return "Hey \(userName), I wanted to remind you."
        }
        return "Hey \(userName), I wanted to remind you \(body)."
    }

    static func schedulerBubble(message: String) -> String {
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return "Hey \(userName), you will have to do something."
        }
        return "Hey \(userName), you will have to \(body)."
    }

    static func alertBubble(kind: ReminderKind, message: String) -> String {
        switch kind {
        case .reminder:
            return reminderBubble(message: message)
        case .scheduler:
            return schedulerBubble(message: message)
        }
    }

    static func alertTitle(kind: ReminderKind) -> String {
        switch kind {
        case .reminder:
            return "Jazz Reminder"
        case .scheduler:
            return "Jazz Scheduler"
        }
    }

    static func calendarBubble(eventTitle: String) -> String {
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return "Hey \(userName)! Your call starts in 10 minutes."
        }
        return "Hey \(userName)! \(title) starts in 10 minutes."
    }
}
