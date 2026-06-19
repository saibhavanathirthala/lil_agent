import AppKit

class PaddedTextFieldCell: NSTextFieldCell {
    private let inset = NSSize(width: 8, height: 2)
    var fieldBackgroundColor: NSColor?
    var fieldCornerRadius: CGFloat = 4

    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        if let bg = fieldBackgroundColor {
            let path = NSBezierPath(roundedRect: cellFrame, xRadius: fieldCornerRadius, yRadius: fieldCornerRadius)
            bg.setFill()
            path.fill()
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        return base.insetBy(dx: inset.width, dy: inset.height)
    }

    private func configureEditor(_ textObj: NSText) {
        if let color = textColor {
            textObj.textColor = color
        }
        if let tv = textObj as? NSTextView {
            tv.insertionPointColor = textColor ?? .textColor
            tv.drawsBackground = false
            tv.backgroundColor = .clear
        }
        textObj.font = font
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        configureEditor(textObj)
        super.edit(withFrame: rect.insetBy(dx: inset.width, dy: inset.height), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        configureEditor(textObj)
        super.select(withFrame: rect.insetBy(dx: inset.width, dy: inset.height), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

class TerminalView: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let inputField = NSTextField()
    private let permissionBar = NSView()
    private let permissionTitleLabel = NSTextField(labelWithString: "")
    private let permissionDetailScroll = NSScrollView()
    private let permissionDetailView = NSTextView()
    private let allowButton = NSButton(title: "Allow", target: nil, action: nil)
    private let denyButton = NSButton(title: "Deny", target: nil, action: nil)
    var onSendMessage: ((String) -> Void)?
    var onClearRequested: (() -> Void)?

    private var currentAssistantText = ""
    private var lastAssistantText = ""
    private var isStreaming = false
    private var showingSessionMessage = false
    private var pendingPermissionRespond: ((Bool) -> Void)?
    private let inputHeight: CGFloat = 30
    private let permissionTitleHeight: CGFloat = 20
    private let permissionButtonHeight: CGFloat = 26
    private let permissionDetailMinHeight: CGFloat = 36
    private let permissionDetailMaxHeight: CGFloat = 120
    private var permissionBarHeight: CGFloat = 0
    private let padding: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    var characterColor: NSColor?
    var themeOverride: PopoverTheme?
    var theme: PopoverTheme {
        var t = themeOverride ?? PopoverTheme.current
        if let color = characterColor { t = t.withCharacterColor(color) }
        t = t.withCustomFont()
        return t
    }

    // MARK: - Setup

    private func updatePlaceholder() {
        let t = theme
        inputField.placeholderAttributedString = NSAttributedString(
            string: ClaudeAgent.inputPlaceholder,
            attributes: [.font: t.font, .foregroundColor: t.textDim]
        )
    }

    private func setupViews() {
        let t = theme

        setupPermissionBar(theme: t)

        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        textView.frame = scrollView.contentView.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textColor = t.textPrimary
        textView.font = t.font
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 2, height: 4)
        let defaultPara = NSMutableParagraphStyle()
        defaultPara.paragraphSpacing = 8
        textView.defaultParagraphStyle = defaultPara
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: t.accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        scrollView.documentView = textView
        addSubview(scrollView)

        inputField.focusRingType = .none
        let paddedCell = PaddedTextFieldCell(textCell: "")
        paddedCell.isEditable = true
        paddedCell.isScrollable = true
        paddedCell.font = t.font
        paddedCell.textColor = t.textPrimary
        paddedCell.drawsBackground = false
        paddedCell.isBezeled = false
        paddedCell.fieldBackgroundColor = nil
        paddedCell.fieldCornerRadius = 0
        inputField.cell = paddedCell
        updatePlaceholder()
        inputField.target = self
        inputField.action = #selector(inputSubmitted)
        addSubview(inputField)
        layoutSubviews()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutSubviews()
    }

    private func setupPermissionBar(theme t: PopoverTheme) {
        permissionBar.isHidden = true
        permissionBar.wantsLayer = true
        permissionBar.layer?.backgroundColor = t.inputBg.cgColor
        permissionBar.layer?.cornerRadius = t.inputCornerRadius

        permissionTitleLabel.font = t.fontBold
        permissionTitleLabel.textColor = t.textPrimary
        permissionBar.addSubview(permissionTitleLabel)

        permissionDetailScroll.hasVerticalScroller = true
        permissionDetailScroll.scrollerStyle = .overlay
        permissionDetailScroll.hasHorizontalScroller = false
        permissionDetailScroll.borderType = .noBorder
        permissionDetailScroll.drawsBackground = false
        permissionDetailScroll.autohidesScrollers = true

        permissionDetailView.isEditable = false
        permissionDetailView.isSelectable = true
        permissionDetailView.drawsBackground = false
        permissionDetailView.backgroundColor = .clear
        permissionDetailView.textColor = t.textPrimary
        permissionDetailView.font = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 1, weight: .regular)
        permissionDetailView.textContainerInset = NSSize(width: 2, height: 2)
        permissionDetailView.textContainer?.widthTracksTextView = true
        permissionDetailView.isVerticallyResizable = true
        permissionDetailView.isHorizontallyResizable = false
        permissionDetailScroll.documentView = permissionDetailView
        permissionBar.addSubview(permissionDetailScroll)

        allowButton.bezelStyle = .rounded
        allowButton.font = t.fontBold
        allowButton.target = self
        allowButton.action = #selector(permissionAllowed)
        permissionBar.addSubview(allowButton)

        denyButton.bezelStyle = .rounded
        denyButton.font = t.font
        denyButton.target = self
        denyButton.action = #selector(permissionDenied)
        permissionBar.addSubview(denyButton)

        addSubview(permissionBar)
    }

    private func measuredPermissionDetailHeight(for detail: String, width: CGFloat) -> CGFloat {
        let font = permissionDetailView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let textWidth = max(80, width - 16)
        let rect = (detail as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(permissionDetailMaxHeight, max(permissionDetailMinHeight, ceil(rect.height) + 8))
    }

    private func updatePermissionBarHeight(detail: String) {
        let contentWidth = frame.width - padding * 2
        let detailHeight = measuredPermissionDetailHeight(for: detail, width: contentWidth)
        permissionBarHeight = 8 + permissionTitleHeight + 4 + detailHeight + 8
    }

    private func layoutSubviews() {
        let bottomStackHeight = inputHeight + padding + 6
            + (permissionBar.isHidden ? 0 : permissionBarHeight + 6)

        scrollView.frame = NSRect(
            x: padding, y: bottomStackHeight,
            width: frame.width - padding * 2,
            height: max(0, frame.height - bottomStackHeight - padding)
        )

        inputField.frame = NSRect(
            x: padding, y: 6,
            width: frame.width - padding * 2,
            height: inputHeight
        )
        inputField.autoresizingMask = [.width]

        let permissionY = inputHeight + 12
        permissionBar.frame = NSRect(
            x: padding, y: permissionY,
            width: frame.width - padding * 2,
            height: permissionBar.isHidden ? 0 : permissionBarHeight
        )
        permissionBar.autoresizingMask = [.width]

        let buttonWidth: CGFloat = 64
        let topRowY = max(8, permissionBarHeight - permissionTitleHeight - 6)
        allowButton.frame = NSRect(
            x: permissionBar.bounds.width - buttonWidth * 2 - 8,
            y: topRowY - 1, width: buttonWidth, height: permissionButtonHeight
        )
        allowButton.autoresizingMask = [.minXMargin]
        denyButton.frame = NSRect(
            x: permissionBar.bounds.width - buttonWidth - 4,
            y: topRowY - 1, width: buttonWidth, height: permissionButtonHeight
        )
        denyButton.autoresizingMask = [.minXMargin]

        permissionTitleLabel.frame = NSRect(
            x: 8, y: topRowY,
            width: max(0, permissionBar.bounds.width - buttonWidth * 2 - 20),
            height: permissionTitleHeight
        )
        permissionTitleLabel.autoresizingMask = [.width]

        let detailHeight = max(0, topRowY - 10)
        permissionDetailScroll.frame = NSRect(
            x: 8, y: 8,
            width: permissionBar.bounds.width - 16,
            height: detailHeight
        )
        permissionDetailScroll.autoresizingMask = [.width]

        if detailHeight > 0, let container = permissionDetailView.textContainer,
           let manager = permissionDetailView.layoutManager {
            container.containerSize = NSSize(width: permissionDetailScroll.contentSize.width, height: .greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            let used = manager.usedRect(for: container)
            permissionDetailView.frame = NSRect(
                x: 0, y: 0,
                width: permissionDetailScroll.contentSize.width,
                height: max(detailHeight, used.height + 8)
            )
        }
    }

    func showPermissionRequest(toolName: String, detail: String, respond: @escaping (Bool) -> Void) {
        let t = theme
        pendingPermissionRespond = respond
        permissionTitleLabel.stringValue = "Allow \(toolName)?"
        permissionTitleLabel.textColor = t.textPrimary
        permissionDetailView.font = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 1, weight: .regular)
        permissionDetailView.textColor = t.textPrimary
        permissionDetailView.string = detail
        if detail.contains("⚠ Sensitive path") {
            let attr = NSMutableAttributedString(string: detail)
            let range = (detail as NSString).range(of: "⚠ Sensitive path — review carefully")
            if range.location != NSNotFound {
                attr.addAttribute(.foregroundColor, value: t.errorColor, range: range)
            }
            permissionDetailView.textStorage?.setAttributedString(attr)
        }
        permissionBar.layer?.backgroundColor = t.inputBg.cgColor
        updatePermissionBarHeight(detail: detail)
        permissionBar.isHidden = false
        inputField.isEnabled = false
        layoutSubviews()
        permissionDetailScroll.documentView?.scrollToVisible(
            NSRect(x: 0, y: 0, width: 1, height: 1)
        )
        scrollToBottom()
        window?.makeFirstResponder(allowButton)
    }

    private func resolvePermission(allowed: Bool) {
        guard let respond = pendingPermissionRespond else { return }
        pendingPermissionRespond = nil
        permissionBar.isHidden = true
        permissionBarHeight = 0
        permissionDetailView.string = ""
        inputField.isEnabled = true
        layoutSubviews()

        let t = theme
        let status = allowed ? "allowed" : "denied"
        textView.textStorage?.append(NSAttributedString(
            string: "  PERMISSION \(status)\n",
            attributes: [.font: t.fontBold, .foregroundColor: allowed ? t.successColor : t.errorColor]
        ))
        scrollToBottom()
        respond(allowed)
        window?.makeFirstResponder(inputField)
    }

    @objc private func permissionAllowed() {
        resolvePermission(allowed: true)
    }

    @objc private func permissionDenied() {
        resolvePermission(allowed: false)
    }

    func resetState() {
        isStreaming = false
        currentAssistantText = ""
        lastAssistantText = ""
        showingSessionMessage = false
        pendingPermissionRespond = nil
        permissionBar.isHidden = true
        permissionBarHeight = 0
        permissionDetailView.string = ""
        inputField.isEnabled = true
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        layoutSubviews()
    }

    func showSessionMessage() {
        let t = theme
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: "  \u{2726} new session\n",
            attributes: [.font: t.font, .foregroundColor: t.accentColor]
        ))
        showingSessionMessage = true
    }

    // MARK: - Input

    @objc private func inputSubmitted() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""

        if handleSlashCommand(text) { return }

        if showingSessionMessage {
            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
            showingSessionMessage = false
        }
        appendUser(text)
        isStreaming = true
        currentAssistantText = ""
        onSendMessage?(text)
    }

    // MARK: - Slash Commands

    func handleSlashCommandPublic(_ text: String) {
        _ = handleSlashCommand(text)
    }

    private func handleSlashCommand(_ text: String) -> Bool {
        guard text.hasPrefix("/") else { return false }
        let cmd = text.lowercased().trimmingCharacters(in: .whitespaces)

        switch cmd {
        case "/clear":
            resetState()
            onClearRequested?()
            return true

        case "/copy":
            let toCopy = lastAssistantText.isEmpty ? "nothing to copy yet" : lastAssistantText
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(toCopy, forType: .string)
            let t = theme
            textView.textStorage?.append(NSAttributedString(
                string: "  ✓ copied to clipboard\n",
                attributes: [.font: t.font, .foregroundColor: t.successColor]
            ))
            scrollToBottom()
            return true

        case "/help":
            let t = theme
            let help = NSMutableAttributedString()
            help.append(NSAttributedString(string: "  lil agents — slash commands\n",
                attributes: [.font: t.fontBold, .foregroundColor: t.accentColor]))
            help.append(NSAttributedString(string: "  /clear  ", attributes: [.font: t.fontBold, .foregroundColor: t.textPrimary]))
            help.append(NSAttributedString(string: "clear chat history\n", attributes: [.font: t.font, .foregroundColor: t.textDim]))
            help.append(NSAttributedString(string: "  /copy   ", attributes: [.font: t.fontBold, .foregroundColor: t.textPrimary]))
            help.append(NSAttributedString(string: "copy last response\n", attributes: [.font: t.font, .foregroundColor: t.textDim]))
            help.append(NSAttributedString(string: "  /help   ", attributes: [.font: t.fontBold, .foregroundColor: t.textPrimary]))
            help.append(NSAttributedString(string: "show this message\n", attributes: [.font: t.font, .foregroundColor: t.textDim]))
            textView.textStorage?.append(help)
            scrollToBottom()
            return true

        default:
            let t = theme
            textView.textStorage?.append(NSAttributedString(
                string: "  unknown command: \(text) (try /help)\n",
                attributes: [.font: t.font, .foregroundColor: t.errorColor]
            ))
            scrollToBottom()
            return true
        }
    }

    // MARK: - Append Methods

    private var messageSpacing: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = 8
        return p
    }

    private func ensureNewline() {
        if let storage = textView.textStorage, storage.length > 0 {
            if !storage.string.hasSuffix("\n") {
                storage.append(NSAttributedString(string: "\n"))
            }
        }
    }

    func appendUser(_ text: String) {
        let t = theme
        ensureNewline()
        let para = messageSpacing
        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: "> ", attributes: [
            .font: t.fontBold, .foregroundColor: t.accentColor, .paragraphStyle: para
        ]))
        attributed.append(NSAttributedString(string: "\(text)\n", attributes: [
            .font: t.fontBold, .foregroundColor: t.textPrimary, .paragraphStyle: para
        ]))
        textView.textStorage?.append(attributed)
        scrollToBottom()
    }

    func appendStreamingText(_ text: String) {
        var cleaned = text
        if currentAssistantText.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: "^\n+", with: "", options: .regularExpression)
        }
        currentAssistantText += cleaned
        if !cleaned.isEmpty {
            textView.textStorage?.append(renderMarkdown(cleaned))
            scrollToBottom()
        }
    }

    func endStreaming() {
        if isStreaming {
            isStreaming = false
            if !currentAssistantText.isEmpty {
                lastAssistantText = currentAssistantText
            }
            currentAssistantText = ""
        }
    }

    func appendError(_ text: String) {
        let t = theme
        textView.textStorage?.append(NSAttributedString(string: text + "\n", attributes: [
            .font: t.font, .foregroundColor: t.errorColor
        ]))
        scrollToBottom()
    }

    func appendToolUse(toolName: String, summary: String) {
        let t = theme
        endStreaming()
        let block = NSMutableAttributedString()
        block.append(NSAttributedString(string: "  \(toolName.uppercased()) ", attributes: [
            .font: t.fontBold, .foregroundColor: t.accentColor
        ]))
        block.append(NSAttributedString(string: "\(summary)\n", attributes: [
            .font: t.font, .foregroundColor: t.textDim
        ]))
        textView.textStorage?.append(block)
        scrollToBottom()
    }

    func appendToolResult(summary: String, isError: Bool) {
        let t = theme
        let color = isError ? t.errorColor : t.successColor
        let prefix = isError ? "  FAIL " : "  DONE "
        let block = NSMutableAttributedString()
        block.append(NSAttributedString(string: prefix, attributes: [
            .font: t.fontBold, .foregroundColor: color
        ]))
        block.append(NSAttributedString(string: "\(summary.isEmpty ? "" : summary)\n", attributes: [
            .font: t.font, .foregroundColor: t.textDim
        ]))
        textView.textStorage?.append(block)
        scrollToBottom()
    }

    func replayHistory(_ messages: [AgentMessage]) {
        let t = theme
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        for msg in messages {
            switch msg.role {
            case .user:
                appendUser(msg.text)
            case .assistant:
                textView.textStorage?.append(renderMarkdown(msg.text + "\n"))
            case .error:
                appendError(msg.text)
            case .toolUse:
                textView.textStorage?.append(NSAttributedString(string: "  \(msg.text)\n", attributes: [
                    .font: t.font, .foregroundColor: t.accentColor
                ]))
            case .toolResult:
                let isErr = msg.text.hasPrefix("ERROR:")
                textView.textStorage?.append(NSAttributedString(string: "  \(msg.text)\n", attributes: [
                    .font: t.font, .foregroundColor: isErr ? t.errorColor : t.successColor
                ]))
            }
        }
        scrollToBottom()
    }

    private func scrollToBottom() {
        textView.scrollToEndOfDocument(nil)
    }

    // MARK: - Markdown Rendering

    private func renderMarkdown(_ text: String) -> NSAttributedString {
        let t = theme
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockLang = ""
        var codeLines: [String] = []

        for (i, line) in lines.enumerated() {
            let suffix = i < lines.count - 1 ? "\n" : ""

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let codeText = codeLines.joined(separator: "\n")
                    let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 1, weight: .regular)
                    result.append(NSAttributedString(string: codeText + "\n", attributes: [
                        .font: codeFont, .foregroundColor: t.textPrimary, .backgroundColor: t.inputBg
                    ]))
                    inCodeBlock = false
                    codeLines = []
                } else {
                    inCodeBlock = true
                    codeBlockLang = String(line.dropFirst(3))
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            if line.hasPrefix("### ") {
                result.append(NSAttributedString(string: String(line.dropFirst(4)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize, weight: .bold), .foregroundColor: t.accentColor
                ]))
            } else if line.hasPrefix("## ") {
                result.append(NSAttributedString(string: String(line.dropFirst(3)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize + 1, weight: .bold), .foregroundColor: t.accentColor
                ]))
            } else if line.hasPrefix("# ") {
                result.append(NSAttributedString(string: String(line.dropFirst(2)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize + 2, weight: .bold), .foregroundColor: t.accentColor
                ]))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let content = String(line.dropFirst(2))
                result.append(NSAttributedString(string: "  \u{2022} ", attributes: [
                    .font: t.font, .foregroundColor: t.accentColor
                ]))
                result.append(renderInlineMarkdown(content + suffix, theme: t))
            } else {
                result.append(renderInlineMarkdown(line + suffix, theme: t))
            }
        }

        if inCodeBlock && !codeLines.isEmpty {
            let codeText = codeLines.joined(separator: "\n")
            let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 1, weight: .regular)
            result.append(NSAttributedString(string: codeText + "\n", attributes: [
                .font: codeFont, .foregroundColor: t.textPrimary, .backgroundColor: t.inputBg
            ]))
        }

        return result
    }

    private func renderInlineMarkdown(_ text: String, theme t: PopoverTheme) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "`" {
                let afterTick = text.index(after: i)
                if afterTick < text.endIndex, let closeIdx = text[afterTick...].firstIndex(of: "`") {
                    let code = String(text[afterTick..<closeIdx])
                    let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 0.5, weight: .regular)
                    result.append(NSAttributedString(string: code, attributes: [
                        .font: codeFont, .foregroundColor: t.accentColor, .backgroundColor: t.inputBg
                    ]))
                    i = text.index(after: closeIdx)
                    continue
                }
            }
            if text[i] == "*",
               text.index(after: i) < text.endIndex, text[text.index(after: i)] == "*" {
                let start = text.index(i, offsetBy: 2)
                if start < text.endIndex, let range = text.range(of: "**", range: start..<text.endIndex) {
                    let bold = String(text[start..<range.lowerBound])
                    result.append(NSAttributedString(string: bold, attributes: [
                        .font: t.fontBold, .foregroundColor: t.textPrimary
                    ]))
                    i = range.upperBound
                    continue
                }
            }
            if text[i] == "[" {
                let afterBracket = text.index(after: i)
                if afterBracket < text.endIndex,
                   let closeBracket = text[afterBracket...].firstIndex(of: "]") {
                    let parenStart = text.index(after: closeBracket)
                    if parenStart < text.endIndex && text[parenStart] == "(" {
                        let afterParen = text.index(after: parenStart)
                        if afterParen < text.endIndex,
                           let closeParen = text[afterParen...].firstIndex(of: ")") {
                            let linkText = String(text[afterBracket..<closeBracket])
                            let urlStr = String(text[afterParen..<closeParen])
                            var attrs: [NSAttributedString.Key: Any] = [
                                .font: t.font,
                                .foregroundColor: t.accentColor,
                                .underlineStyle: NSUnderlineStyle.single.rawValue
                            ]
                            if let url = URL(string: urlStr) {
                                attrs[.link] = url
                                attrs[.cursor] = NSCursor.pointingHand
                            }
                            result.append(NSAttributedString(string: linkText, attributes: attrs))
                            i = text.index(after: closeParen)
                            continue
                        }
                    }
                }
            }
            if text[i] == "h" {
                let remaining = String(text[i...])
                if remaining.hasPrefix("https://") || remaining.hasPrefix("http://") {
                    var j = i
                    while j < text.endIndex && !text[j].isWhitespace && text[j] != ")" && text[j] != ">" {
                        j = text.index(after: j)
                    }
                    let urlStr = String(text[i..<j])
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: t.font,
                        .foregroundColor: t.accentColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]
                    if let url = URL(string: urlStr) {
                        attrs[.link] = url
                    }
                    result.append(NSAttributedString(string: urlStr, attributes: attrs))
                    i = j
                    continue
                }
            }
            result.append(NSAttributedString(string: String(text[i]), attributes: [
                .font: t.font, .foregroundColor: t.textPrimary
            ]))
            i = text.index(after: i)
        }
        return result
    }
}
