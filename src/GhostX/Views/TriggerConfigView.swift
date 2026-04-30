import SwiftUI

/// Sheet for configuring triggers
struct TriggerConfigView: View {
    @StateObject private var viewModel = TriggerConfigViewModel()
    @State private var newPattern = ""
    @State private var newName = ""
    @State private var newAction: Trigger.TriggerAction = .notify("匹配: {line}")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.triggerConfig)
                .font(.title2)
                .padding(.top)

            // Add new trigger form
            GroupBox(L10n.newTrigger) {
                VStack(spacing: 8) {
                    HStack {
                        TextField("Name", text: $newName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Regex Pattern", text: $newPattern)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Picker(L10n.action, selection: $newAction) {
                            Text(L10n.notifyAction).tag(Trigger.TriggerAction.notify("匹配: {line}"))
                            Text(L10n.sendCmdAction).tag(Trigger.TriggerAction.runCommand(""))
                            Text(L10n.disconnectAction).tag(Trigger.TriggerAction.disconnect)
                        }
                        .pickerStyle(.segmented)
                        Spacer()
                        Button("Add") {
                            guard !newPattern.isEmpty else { return }
                            let trigger = Trigger(name: newName, pattern: newPattern, action: newAction)
                            viewModel.add(trigger)
                            newName = ""
                            newPattern = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newPattern.isEmpty)
                    }
                }
                .padding(8)
            }

            // Existing triggers list
            List {
                ForEach(viewModel.triggers) { trigger in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trigger.name.isEmpty ? trigger.pattern : trigger.name)
                                .font(.body)
                            Text(trigger.pattern)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Text(actionLabel(trigger.action))
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { trigger.enabled },
                            set: { _ in viewModel.add(Trigger(
                                id: trigger.id, name: trigger.name,
                                pattern: trigger.pattern, action: trigger.action,
                                enabled: !trigger.enabled
                            ))}
                        ))
                        Button(action: { viewModel.delete(id: trigger.id) }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
        .padding()
        .frame(width: 550, height: 400)
        .onAppear { viewModel.load() }
    }

    private func actionLabel(_ action: Trigger.TriggerAction) -> String {
        switch action {
        case .notify(let msg): return "Notify: \(msg)"
        case .runCommand(let cmd): return "Send: \(cmd)"
        case .highlight: return "Highlight"
        case .disconnect: return "Disconnect"
        }
    }
}
