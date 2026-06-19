import AppKit

final class ReminderView: NSView {
    var onAdd: ((ReminderKind, String, Date) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onGrantCalendarAccess: ((String, String) -> Void)?
    var onDismissAlert: (() -> Void)?

    private let alertBanner = NSView()
    private let alertLabel = NSTextField(wrappingLabelWithString: "")
    private let gotItButton = NSButton()
    private let scrollView = NSScrollView()
    private let listView = NSView()
    private(set) var messageField = NSTextField()
    private let kindPopUp = NSPopUpButton()
    private let datePicker = NSDatePicker()
    private let timePicker = NSDatePicker()
    private let addButton = NSButton()
    private let calendarStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let clientIDField = NSTextField()
    private let clientSecretField = NSSecureTextField()
    private let grantCalendarButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No reminders or schedulers yet")
    private var theme: PopoverTheme = PopoverTheme.current
    private var characterColor: NSColor = .gray
    private var showGrantButton = false
    private var showCredentialFields = true
    private var showingAlert = false
    private var alertBlockHeight: CGFloat = 120

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func applyTheme(_ theme: PopoverTheme, characterColor: NSColor) {
        self.theme = theme
        self.characterColor = characterColor
        wantsLayer = true
        layer?.backgroundColor = theme.popoverBg.cgColor
        emptyLabel.textColor = theme.textDim
        calendarStatusLabel.textColor = theme.textDim
        calendarStatusLabel.font = theme.font
        messageField.backgroundColor = theme.inputBg
        messageField.textColor = theme.textPrimary
        clientIDField.backgroundColor = theme.inputBg
        clientIDField.textColor = theme.textPrimary
        clientSecretField.backgroundColor = theme.inputBg
        clientSecretField.textColor = theme.textPrimary
        addButton.contentTintColor = characterColor
        grantCalendarButton.contentTintColor = characterColor
        gotItButton.contentTintColor = characterColor
        alertBanner.layer?.backgroundColor = characterColor.withAlphaComponent(0.18).cgColor
        alertLabel.textColor = theme.textPrimary
        reloadList(reminders: [])
    }

    func showActiveAlert(_ message: String) {
        alertLabel.stringValue = message
        showingAlert = true
        alertBanner.isHidden = false

        let pad: CGFloat = 12
        let maxW = max(bounds.width - pad * 4, 360)
        let font = alertLabel.font ?? NSFont.systemFont(ofSize: 14, weight: .semibold)
        let textBounds = (message as NSString).boundingRect(
            with: NSSize(width: maxW, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        alertBlockHeight = max(120, ceil(textBounds.height) + 56)
        needsLayout = true
    }

    func clearActiveAlert() {
        showingAlert = false
        alertBanner.isHidden = true
        needsLayout = true
    }

    func updateCalendarStatus(message: String, isConnected: Bool, clientID: String = "", clientSecret: String = "") {
        calendarStatusLabel.stringValue = message
        showGrantButton = true
        showCredentialFields = !isConnected
        grantCalendarButton.isHidden = false
        grantCalendarButton.title = isConnected ? "Disconnect Google Calendar" : "Connect Google Calendar"
        clientIDField.isHidden = isConnected
        clientSecretField.isHidden = isConnected
        if !clientID.isEmpty {
            clientIDField.stringValue = clientID
        }
        if !clientSecret.isEmpty {
            clientSecretField.stringValue = clientSecret
        }
        needsLayout = true
    }

    func reloadList(reminders: [Reminder]) {
        listView.subviews.forEach { $0.removeFromSuperview() }
        emptyLabel.isHidden = !reminders.isEmpty

        var y: CGFloat = 0
        let rowHeight: CGFloat = 34
        let width = max(listView.bounds.width, scrollView.contentSize.width - 8)

        for reminder in reminders {
            let row = makeRow(for: reminder, width: width, height: rowHeight)
            row.frame.origin = NSPoint(x: 0, y: y)
            listView.addSubview(row)
            y += rowHeight + 4
        }

        listView.frame.size.height = max(y, 1)
        scrollView.documentView = listView
    }

    private func setup() {
        wantsLayer = true

        alertBanner.wantsLayer = true
        alertBanner.layer?.cornerRadius = 10
        alertBanner.isHidden = true
        addSubview(alertBanner)

        alertLabel.isEditable = false
        alertLabel.isSelectable = false
        alertLabel.isBordered = false
        alertLabel.drawsBackground = false
        alertLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        alertLabel.alignment = .center
        alertLabel.maximumNumberOfLines = 0
        alertBanner.addSubview(alertLabel)

        gotItButton.title = "Got it"
        gotItButton.bezelStyle = .rounded
        gotItButton.target = self
        gotItButton.action = #selector(gotItTapped)
        alertBanner.addSubview(gotItButton)

        calendarStatusLabel.isEditable = false
        calendarStatusLabel.isSelectable = false
        calendarStatusLabel.isBordered = false
        calendarStatusLabel.drawsBackground = false
        calendarStatusLabel.lineBreakMode = .byWordWrapping
        calendarStatusLabel.maximumNumberOfLines = 4
        addSubview(calendarStatusLabel)

        clientIDField.placeholderString = "Google OAuth Client ID"
        clientIDField.isBordered = true
        clientIDField.bezelStyle = .roundedBezel
        clientIDField.font = theme.font
        addSubview(clientIDField)

        clientSecretField.placeholderString = "Google OAuth Client Secret"
        clientSecretField.isBordered = true
        clientSecretField.bezelStyle = .roundedBezel
        clientSecretField.font = theme.font
        addSubview(clientSecretField)

        grantCalendarButton.title = "Connect Google Calendar"
        grantCalendarButton.bezelStyle = .rounded
        grantCalendarButton.target = self
        grantCalendarButton.action = #selector(grantCalendarTapped)
        grantCalendarButton.isHidden = true
        addSubview(grantCalendarButton)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        addSubview(scrollView)

        listView.frame = NSRect(x: 0, y: 0, width: 360, height: 1)
        scrollView.documentView = listView

        emptyLabel.font = theme.font
        emptyLabel.alignment = .center
        listView.addSubview(emptyLabel)

        messageField.placeholderString = "What should Jazz remind you about?"
        messageField.isBordered = true
        messageField.bezelStyle = .roundedBezel
        messageField.font = theme.font
        addSubview(messageField)

        for kind in ReminderKind.allCases {
            kindPopUp.addItem(withTitle: kind.displayName)
        }
        kindPopUp.target = self
        kindPopUp.action = #selector(kindChanged)
        addSubview(kindPopUp)

        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.dateValue = Date()
        datePicker.isHidden = true
        addSubview(datePicker)

        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.datePickerElements = .hourMinute
        timePicker.dateValue = Self.defaultReminderTime()
        addSubview(timePicker)

        addButton.title = "Add"
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addTapped)
        addSubview(addButton)
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        let inputH: CGFloat = 24
        let buttonH: CGFloat = 26
        let calendarBlock: CGFloat = {
            guard showGrantButton else { return 44 }
            if showCredentialFields {
                return 36 + 8 + 24 + 8 + 24 + 8 + 26
            }
            return 72
        }()
        let alertBlock: CGFloat = showingAlert ? alertBlockHeight : 0
        let schedulerDateRow: CGFloat = selectedKind == .scheduler ? inputH + 8 : 0
        let bottomBlock = calendarBlock + inputH + 8 + schedulerDateRow + inputH + 8 + buttonH + pad + alertBlock

        if showingAlert {
            alertBanner.frame = NSRect(
                x: pad, y: bounds.height - pad - alertBlock,
                width: bounds.width - pad * 2, height: alertBlock - 8
            )
            alertLabel.frame = NSRect(
                x: pad,
                y: 36,
                width: alertBanner.bounds.width - pad * 2,
                height: alertBanner.bounds.height - 46
            )
            gotItButton.frame = NSRect(
                x: (alertBanner.bounds.width - 80) / 2,
                y: 8,
                width: 80,
                height: buttonH
            )
        }

        let calendarTop = bounds.height - pad - calendarBlock - alertBlock

        calendarStatusLabel.frame = NSRect(
            x: pad, y: calendarTop + (showCredentialFields ? 98 : 28),
            width: bounds.width - pad * 2, height: showCredentialFields ? 36 : 36
        )
        if showCredentialFields {
            clientIDField.frame = NSRect(
                x: pad, y: calendarTop + 66,
                width: bounds.width - pad * 2, height: inputH
            )
            clientSecretField.frame = NSRect(
                x: pad, y: calendarTop + 34,
                width: bounds.width - pad * 2, height: inputH
            )
        }
        grantCalendarButton.frame = NSRect(
            x: pad, y: calendarTop,
            width: min(200, bounds.width - pad * 2), height: buttonH
        )

        scrollView.frame = NSRect(x: pad, y: bottomBlock, width: bounds.width - pad * 2, height: bounds.height - bottomBlock - pad)
        listView.frame.size.width = scrollView.contentSize.width
        emptyLabel.frame = NSRect(x: 0, y: max(0, scrollView.contentSize.height / 2 - 10), width: listView.bounds.width, height: 20)

        messageField.frame = NSRect(x: pad, y: pad + inputH + 8 + buttonH + schedulerDateRow, width: bounds.width - pad * 2, height: inputH)

        if selectedKind == .scheduler {
            timePicker.frame = NSRect(x: pad, y: pad + buttonH, width: 160, height: inputH)
            addButton.frame = NSRect(x: pad + 168, y: pad, width: bounds.width - pad * 2 - 168, height: buttonH)
            kindPopUp.frame = NSRect(x: pad, y: pad + buttonH + inputH + 8, width: 110, height: inputH)
            datePicker.frame = NSRect(x: pad + 118, y: pad + buttonH + inputH + 8, width: bounds.width - pad * 2 - 118, height: inputH)
            datePicker.isHidden = false
        } else {
            kindPopUp.frame = NSRect(x: pad, y: pad + buttonH, width: 110, height: inputH)
            timePicker.frame = NSRect(x: pad + 118, y: pad + buttonH, width: 150, height: inputH)
            addButton.frame = NSRect(x: pad + 276, y: pad, width: bounds.width - pad * 2 - 276, height: buttonH)
            datePicker.isHidden = true
        }
    }

    private var selectedKind: ReminderKind {
        let index = kindPopUp.indexOfSelectedItem
        guard index >= 0, index < ReminderKind.allCases.count else { return .reminder }
        return ReminderKind.allCases[index]
    }

    @objc private func kindChanged() {
        switch selectedKind {
        case .reminder:
            messageField.placeholderString = "What should Jazz remind you about?"
        case .scheduler:
            messageField.placeholderString = "What will you need to do?"
            datePicker.dateValue = Date()
        }
        needsLayout = true
    }

    private static func defaultReminderTime() -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    }

    private func fireDateForAdd() -> Date? {
        switch selectedKind {
        case .reminder:
            return fireDateFromTimePicker()
        case .scheduler:
            return fireDateFromDateAndTimePickers()
        }
    }

    private func fireDateFromTimePicker() -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let picked = timePicker.dateValue
        let timeComponents = calendar.dateComponents([.hour, .minute], from: picked)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = 0
        guard var fireDate = calendar.date(from: dateComponents) else { return nil }
        if fireDate <= now {
            fireDate = calendar.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }
        return fireDate
    }

    private func fireDateFromDateAndTimePickers() -> Date? {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: datePicker.dateValue)
        let time = calendar.dateComponents([.hour, .minute], from: timePicker.dateValue)
        var combined = DateComponents()
        combined.year = day.year
        combined.month = day.month
        combined.day = day.day
        combined.hour = time.hour
        combined.minute = time.minute
        combined.second = 0
        return calendar.date(from: combined)
    }

    private func formattedDateTime(for date: Date, kind: ReminderKind) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        switch kind {
        case .reminder:
            if calendar.isDateInToday(date) {
                formatter.timeStyle = .short
                formatter.dateStyle = .none
            } else if calendar.isDateInTomorrow(date) {
                formatter.dateFormat = "'Tomorrow' h:mm a"
            } else {
                formatter.timeStyle = .short
                formatter.dateStyle = .short
            }
        case .scheduler:
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    private func makeRow(for reminder: Reminder, width: CGFloat, height: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        row.wantsLayer = true
        row.layer?.backgroundColor = theme.inputBg.cgColor
        row.layer?.cornerRadius = theme.inputCornerRadius

        let timeText = formattedDateTime(for: reminder.fireDate, kind: reminder.kind)

        let label = NSTextField(labelWithString: "\(timeText) · \(reminder.kind.displayName) — \(reminder.message)")
        label.font = theme.font
        label.textColor = theme.textPrimary
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 10, y: 8, width: width - 44, height: 18)
        row.addSubview(label)

        let deleteBtn = NSButton(frame: NSRect(x: width - 30, y: 6, width: 20, height: 20))
        deleteBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Delete")
        deleteBtn.imageScaling = .scaleProportionallyDown
        deleteBtn.isBordered = false
        deleteBtn.bezelStyle = .inline
        deleteBtn.contentTintColor = theme.textDim
        deleteBtn.identifier = NSUserInterfaceItemIdentifier(reminder.id.uuidString)
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteTapped(_:))
        row.addSubview(deleteBtn)

        return row
    }

    @objc private func addTapped() {
        let message = messageField.stringValue
        guard let fireDate = fireDateForAdd(), fireDate > Date() else { return }
        onAdd?(selectedKind, message, fireDate)
        messageField.stringValue = ""
        timePicker.dateValue = Self.defaultReminderTime()
        datePicker.dateValue = Date()
    }

    @objc private func deleteTapped(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString) else { return }
        onDelete?(id)
    }

    @objc private func grantCalendarTapped() {
        onGrantCalendarAccess?(clientIDField.stringValue, clientSecretField.stringValue)
    }

    @objc private func gotItTapped() {
        clearActiveAlert()
        onDismissAlert?()
    }
}
