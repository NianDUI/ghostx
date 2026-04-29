import Foundation
import RegexBuilder

/// Monitors terminal output for pattern matches and fires actions
final class TriggerEngine {
    struct Rule {
        let id: UUID
        let pattern: String
        let regex: NSRegularExpression?
        let action: Trigger.TriggerAction
        var enabled: Bool = true

        init(from trigger: Trigger) {
            self.id = trigger.id
            self.pattern = trigger.pattern
            self.regex = try? NSRegularExpression(pattern: trigger.pattern, options: [.caseInsensitive])
            self.action = trigger.action
            self.enabled = trigger.enabled
        }
    }

    private var rules: [Rule] = []
    private var outputBuffer: String = ""
    private var onNotify: ((String, String) -> Void)?  // title, body
    private var onRunCommand: ((String) -> Void)?
    private var onDisconnect: (() -> Void)?

    func setCallbacks(notify: @escaping (String, String) -> Void,
                      runCommand: @escaping (String) -> Void,
                      disconnect: @escaping () -> Void) {
        self.onNotify = notify
        self.onRunCommand = runCommand
        self.onDisconnect = disconnect
    }

    func loadTriggers(_ triggers: [Trigger]) {
        rules = triggers.map(Rule.init)
    }

    func addTrigger(_ trigger: Trigger) {
        rules.append(Rule(from: trigger))
    }

    func removeTrigger(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    /// Feed output data and check for matches
    func feed(_ data: Data) {
        guard let str = String(data: data, encoding: .utf8) else { return }
        outputBuffer += str

        // Keep buffer bounded
        if outputBuffer.count > 100_000 {
            outputBuffer = String(outputBuffer.suffix(50_000))
        }

        // Check each line against rules
        let lines = str.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            for rule in rules where rule.enabled {
                guard let regex = rule.regex else { continue }
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    fire(rule.action, matchedLine: line)
                }
            }
        }
    }

    private func fire(_ action: Trigger.TriggerAction, matchedLine: String) {
        switch action {
        case .highlight:
            break // Handled at rendering layer

        case .notify(let message):
            onNotify?("Trigger Match", message.replacingOccurrences(of: "{line}", with: matchedLine))

        case .runCommand(let command):
            let expanded = command.replacingOccurrences(of: "{line}", with: matchedLine)
            onRunCommand?(expanded + "\n")

        case .disconnect:
            onDisconnect?()
        }
    }
}

// MARK: - Trigger configuration view model

final class TriggerConfigViewModel: ObservableObject {
    @Published var triggers: [Trigger] = []
    private let repo = SessionRepository()

    func add(_ trigger: Trigger) {
        triggers.append(trigger)
        // Persist in UserDefaults for now (simple)
        save()
    }

    func delete(id: UUID) {
        triggers.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(triggers) {
            UserDefaults.standard.set(data, forKey: "GhostX.triggers")
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: "GhostX.triggers"),
           let saved = try? JSONDecoder().decode([Trigger].self, from: data) {
            triggers = saved
        }
    }
}
