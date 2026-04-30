import AppKit

/// Shows a modal password prompt dialog
enum PasswordPrompt {
    @MainActor
    static func ask(host: String, username: String, saveToKeychain: Bool = false) -> String? {
        let alert = NSAlert()
        alert.messageText = L10n.sshAuth
        alert.informativeText = "\(L10n.enterPassword) \(username)@\(host)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.connect)
        alert.addButton(withTitle: L10n.cancel)

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.placeholderString = "Password"
        alert.accessoryView = textField

        // Add "Save to Keychain" checkbox
        let saveCheckbox = NSButton(checkboxWithTitle: L10n.saveToKeychain, target: nil, action: nil)
        saveCheckbox.state = saveToKeychain ? .on : .off
        saveCheckbox.frame = NSRect(x: 0, y: 28, width: 280, height: 20)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 52))
        container.addSubview(textField)
        container.addSubview(saveCheckbox)
        alert.accessoryView = container

        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let password = textField.stringValue
            if saveCheckbox.state == .on, !password.isEmpty {
                try? CredentialStore.shared.savePassword(host: host, username: username, password: password)
            }
            return password.isEmpty ? nil : password
        }
        return nil
    }

    /// Ask for password, return as Credential
    @MainActor
    static func askCredential(host: String, username: String) -> Credential? {
        guard let password = ask(host: host, username: username, saveToKeychain: true) else {
            return nil
        }
        return Credential(host: host, username: username, secret: .password(password))
    }
}
