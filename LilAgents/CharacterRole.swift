import Foundation

enum CharacterRole {
    case claude
    case reminders

    var subtitle: String {
        switch self {
        case .claude: return "Claude"
        case .reminders: return "Reminders"
        }
    }

    var badgeText: String {
        switch self {
        case .claude: return "Claude"
        case .reminders: return "Reminders"
        }
    }
}
