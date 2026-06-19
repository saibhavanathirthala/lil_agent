import AppKit
import AVFoundation
import AudioToolbox
import UserNotifications

enum AlertSound {
    private static var player: AVAudioPlayer?
    private static var activeNSSound: NSSound?

    static func prepare() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func playReminderAlert(title: String, body: String) {
        guard WalkerCharacter.soundsEnabled else { return }

        NSApp.activate(ignoringOtherApps: true)
        playInAppAudio()

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                deliverNotification(title: title, body: body)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        deliverNotification(title: title, body: body)
                    }
                }
            default:
                break
            }
        }
    }

    private static func playInAppAudio() {
        let candidates: [(String, String)] = [
            ("ping-jj", "m4a"),
            ("ping-cc", "mp3"),
            ("ping-ff", "mp3"),
            ("ping-aa", "mp3"),
        ]

        for (name, ext) in candidates {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds"),
                  let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { continue }
            player = audioPlayer
            audioPlayer.volume = 1.0
            audioPlayer.prepareToPlay()
            if audioPlayer.play() { return }
        }

        for name in ["Glass", "Ping", "Hero", "Pop", "Sosumi"] {
            if let sound = NSSound(named: NSSound.Name(name)) {
                activeNSSound = sound
                sound.volume = 1.0
                if sound.play() { return }
            }
        }

        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_UserPreferredAlert))
        NSSound.beep()
    }

    private static func deliverNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "jazz-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
