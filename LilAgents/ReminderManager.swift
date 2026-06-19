import Foundation

enum ReminderKind: String, Codable, CaseIterable {
    case reminder
    case scheduler

    var displayName: String {
        switch self {
        case .reminder: return "Reminder"
        case .scheduler: return "Scheduler"
        }
    }
}

struct Reminder: Codable, Identifiable, Equatable {
    let id: UUID
    var message: String
    var fireDate: Date
    var kind: ReminderKind

    init(id: UUID = UUID(), message: String, fireDate: Date, kind: ReminderKind = .reminder) {
        self.id = id
        self.message = message
        self.fireDate = fireDate
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        message = try container.decode(String.self, forKey: .message)
        fireDate = try container.decode(Date.self, forKey: .fireDate)
        kind = try container.decodeIfPresent(ReminderKind.self, forKey: .kind) ?? .reminder
    }
}

final class ReminderManager {
    private static let storageKey = "JazzReminders"
    private var timers: [UUID: Timer] = [:]

    var reminders: [Reminder] = [] {
        didSet { save() }
    }

    var onReminderFired: ((Reminder) -> Void)?

    init() {
        load()
        scheduleAll()
    }

    func add(message: String, fireDate: Date, kind: ReminderKind = .reminder) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, fireDate > Date() else { return }
        let reminder = Reminder(message: trimmed, fireDate: fireDate, kind: kind)
        reminders.append(reminder)
        reminders.sort { $0.fireDate < $1.fireDate }
        schedule(reminder)
    }

    func remove(id: UUID) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        reminders.removeAll { $0.id == id }
    }

    private func scheduleAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        reminders = reminders.filter { $0.fireDate > Date() }
        reminders.forEach { schedule($0) }
    }

    private func schedule(_ reminder: Reminder) {
        let interval = reminder.fireDate.timeIntervalSinceNow
        guard interval > 0 else {
            fire(reminder)
            return
        }
        timers[reminder.id]?.invalidate()
        timers[reminder.id] = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.fire(reminder)
        }
    }

    private func fire(_ reminder: Reminder) {
        timers.removeValue(forKey: reminder.id)
        reminders.removeAll { $0.id == reminder.id }
        onReminderFired?(reminder)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        reminders = decoded.filter { $0.fireDate > Date() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
