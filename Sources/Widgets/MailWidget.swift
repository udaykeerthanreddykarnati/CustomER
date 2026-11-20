import AppKit
import Foundation

// MARK: - 10. GMAIL UNREAD WIDGET (Keychain-Backed Credentials & Sleep-Aware Polling)
struct GmailEntry {
    var title: String = ""
    var summary: String = ""
    var authorName: String = ""
    var authorEmail: String = ""
}

class GmailAtomParser: NSObject, XMLParserDelegate {
    var fullCount: Int = 0
    var entries: [GmailEntry] = []

    private var currentElement = ""
    private var currentFullCountString = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentAuthorName = ""
    private var currentAuthorEmail = ""
    private var inEntry = false
    private var inAuthor = false

    func parse(xmlData: Data) {
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "fullcount" {
            currentFullCountString = ""
        } else if elementName == "entry" {
            inEntry = true; currentTitle = ""; currentSummary = ""; currentAuthorName = ""; currentAuthorEmail = ""
        } else if elementName == "author" {
            inAuthor = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !inEntry && currentElement == "fullcount" {
            currentFullCountString += string
        } else if inEntry {
            if currentElement == "title" {
                currentTitle += string
            } else if currentElement == "summary" {
                currentSummary += string
            } else if inAuthor {
                if currentElement == "name" { currentAuthorName += string }
                else if currentElement == "email" { currentAuthorEmail += string }
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?) {
        if elementName == "fullcount" {
            fullCount = Int(currentFullCountString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        } else if elementName == "entry" {
            inEntry = false
            entries.append(GmailEntry(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: currentSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                authorName: currentAuthorName.trimmingCharacters(in: .whitespacesAndNewlines),
                authorEmail: currentAuthorEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        } else if elementName == "author" {
            inAuthor = false
        }
    }
}

class MailView: BaseWidgetView {
    private let titleLabel    = NSTextField()
    private let badgeLabel    = NSTextField()
    private let cardView      = NSView()
    private let countNumLabel = NSTextField()
    private let senderLabel   = NSTextField()
    private let subjectLabel  = NSTextField()

    private var timer: Timer?
    private var isSleeping = false

    private static let emailAccount = "gmail.email"
    private static let passAccount  = "gmail.app_password"

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "mail")
        build()
        updateMail()
        startTimer()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }

    private func build() {
        titleLabel.stringValue = "GMAIL"
        titleLabel.font = dynamicFont(size: 13, weight: .bold); titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        badgeLabel.stringValue = "0 UNREAD"
        badgeLabel.font = dynamicFont(size: 10, weight: .bold); badgeLabel.textColor = kDim; badgeLabel.alignment = .right; badgeLabel.tag = 99
        badgeLabel.isEditable = false; badgeLabel.isBordered = false; badgeLabel.backgroundColor = .clear
        addSubview(badgeLabel)

        cardView.wantsLayer = true; cardView.layer?.cornerRadius = kRadius / 2; cardView.layer?.backgroundColor = kSurface.cgColor
        cardView.layer?.borderWidth = kBorderWidth; cardView.layer?.borderColor = kBorder.cgColor
        addSubview(cardView)

        countNumLabel.stringValue = "0"
        countNumLabel.font = dynamicFont(size: 22, weight: .bold); countNumLabel.textColor = kText; countNumLabel.alignment = .center
        countNumLabel.isEditable = false; countNumLabel.isBordered = false; countNumLabel.backgroundColor = .clear
        cardView.addSubview(countNumLabel)

        senderLabel.stringValue = "Double-click to set Gmail"
        senderLabel.font = dynamicFont(size: 11, weight: .bold); senderLabel.textColor = kText; senderLabel.lineBreakMode = .byTruncatingTail
        senderLabel.isEditable = false; senderLabel.isBordered = false; senderLabel.backgroundColor = .clear
        cardView.addSubview(senderLabel)

        subjectLabel.stringValue = "Stored privately on disk (0600)"
        subjectLabel.font = dynamicFont(size: 10, weight: .medium); subjectLabel.textColor = kDim; subjectLabel.lineBreakMode = .byTruncatingTail; subjectLabel.tag = 99
        subjectLabel.isEditable = false; subjectLabel.isBordered = false; subjectLabel.backgroundColor = .clear
        cardView.addSubview(subjectLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 12, y: h - 28, width: 100, height: 18)
        badgeLabel.frame = NSRect(x: w - 120, y: h - 28, width: 108, height: 18)
        cardView.frame   = NSRect(x: 12, y: 12, width: w - 24, height: 58)
        countNumLabel.frame = NSRect(x: 8, y: 14, width: 44, height: 30)
        senderLabel.frame   = NSRect(x: 58, y: 30, width: w - 90, height: 16)
        subjectLabel.frame  = NSRect(x: 58, y: 12, width: w - 90, height: 16)
    }

    private func startTimer() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onWake), name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isSleeping else { return }
            self.updateMail()
        }
    }

    @objc private func onSleep() { isSleeping = true }
    @objc private func onWake()  { isSleeping = false; updateMail() }

    private func getGmailCredentials() -> (email: String, pass: String)? {
        // 1. Primary: macOS Keychain
        if let u = KeychainHelper.load(account: Self.emailAccount), !u.isEmpty,
           let p = KeychainHelper.load(account: Self.passAccount), !p.isEmpty {
            return (u, p)
        }
        // 2. Seamless one-time migration from legacy plaintext `gmail.json`
        let legacyPath = AppPaths.file("gmail.json")
        if let data = try? Data(contentsOf: legacyPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let u = json["email"], !u.isEmpty,
           let p = json["app_password"], !p.isEmpty {
            if KeychainHelper.save(u, account: Self.emailAccount),
               KeychainHelper.save(p, account: Self.passAccount) {
                try? FileManager.default.removeItem(at: legacyPath)
            }
            return (u, p)
        }
        return nil
    }

    private func promptConfigureGmail() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Connect Gmail (Stored Privately Locally)"
        alert.informativeText = "Enter your Gmail address and a 16-character Google App Password."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")

        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 58))
        let emailField = NSTextField(frame: NSRect(x: 0, y: 32, width: 280, height: 24))
        emailField.placeholderString = "you@gmail.com"
        let passField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        passField.placeholderString = "16-char Google App Password"
        stack.addSubview(emailField)
        stack.addSubview(passField)
        alert.accessoryView = stack

        alert.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let pass = passField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty && !pass.isEmpty {
                _ = KeychainHelper.save(email, account: Self.emailAccount)
                _ = KeychainHelper.save(pass, account: Self.passAccount)
                self?.updateMail()
            }
        }
        DispatchQueue.main.async { emailField.becomeFirstResponder() }
    }

    private func updateMail() {
        guard let creds = getGmailCredentials() else {
            countNumLabel.stringValue = "0"
            badgeLabel.stringValue = "0 UNREAD"
            senderLabel.stringValue = "Double-click to set Gmail"
            subjectLabel.stringValue = "Stored privately on disk (0600)"
            return
        }
        fetchGmailOnline(user: creds.email, pass: creds.pass)
    }

    private func fetchGmailOnline(user: String, pass: String) {
        guard let url = URL(string: "https://mail.google.com/mail/feed/atom"),
              let loginData = "\(user):\(pass)".data(using: .utf8) else { return }

        var req = URLRequest(url: url)
        req.setValue("Basic \(loginData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10.0

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            let parser = GmailAtomParser()
            parser.parse(xmlData: data)

            DispatchQueue.main.async {
                let count = parser.fullCount
                self?.countNumLabel.stringValue = "\(count)"
                self?.badgeLabel.stringValue = "\(count) UNREAD"
                if let first = parser.entries.first {
                    let sender = first.authorName.isEmpty ? (first.authorEmail.isEmpty ? "Gmail Sender" : first.authorEmail) : first.authorName
                    let subject = !first.title.isEmpty ? first.title : (!first.summary.isEmpty ? first.summary : "(No Subject)")
                    self?.senderLabel.stringValue = sender
                    self?.subjectLabel.stringValue = subject
                } else if count > 0 {
                    self?.senderLabel.stringValue = "Unread Email"
                    self?.subjectLabel.stringValue = "Check Gmail Inbox"
                } else {
                    self?.senderLabel.stringValue = "No unread mail"
                    self?.subjectLabel.stringValue = "All caught up!"
                }
            }
        }.resume()
    }

    override func applyTheme(preset: ThemePreset) {
        cardView.layer?.cornerRadius = preset.cornerRadius / 2
        cardView.layer?.backgroundColor = preset.surfaceColor.cgColor
        cardView.layer?.borderColor = preset.borderColor.cgColor
        cardView.layer?.borderWidth = preset.borderWidth
        updateThemeRecursively(preset: preset)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if getGmailCredentials() == nil {
                promptConfigureGmail()
            } else if let url = URL(string: "https://mail.google.com") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        super.mouseDown(with: event)
    }
}
