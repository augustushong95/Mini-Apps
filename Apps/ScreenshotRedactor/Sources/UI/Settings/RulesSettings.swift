import MenuBarKit
import SwiftUI

/// Settings › Your Rules (Pro): domains, words and patterns a company adds.
struct RulesSettings: View {
    @Bindable var preferences: Preferences
    let pro: ProStore
    let upgrade: () -> Void
    @State private var editing: CustomRule?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your rules").font(.headline)
                Text("Cover what only your company knows is sensitive: internal domains, customer IDs, project code names.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            if pro.isPro {
                rulesList
            } else {
                locked
            }
        }
        .sheet(isPresented: $isAdding) {
            RuleEditor(rule: nil) { rule in
                preferences.detection.customRules.append(rule)
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule) { updated in
                if let index = preferences.detection.customRules.firstIndex(where: { $0.id == updated.id }) {
                    preferences.detection.customRules[index] = updated
                }
            }
        }
    }

    private var rulesList: some View {
        VStack(spacing: 0) {
            if preferences.detection.customRules.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                    Text("No rules yet").font(.headline)
                    Text("Add a domain like corp.company.com, a code name, or a pattern like CUST-\\d{6}.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
            } else {
                List {
                    ForEach($preferences.detection.customRules) { $rule in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $rule.isEnabled).labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.value)
                                    .font(rule.kind == .pattern ? .system(.body, design: .monospaced) : .body)
                                    .lineLimit(1)
                                Text(rule.kind.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { editing = rule }.buttonStyle(.borderless)
                            Button {
                                preferences.detection.customRules.removeAll { $0.id == rule.id }
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete rule")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            Divider()
            HStack {
                Button { isAdding = true } label: { Label("Add Rule…", systemImage: "plus") }
                Spacer()
                Text("Rules apply to screenshots taken after you change them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var locked: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Your own rules are part of Pro").font(.headline)
            Text("Pro also removes the daily limit. It's a one-time purchase.")
                .font(.callout).foregroundStyle(.secondary)
            Button("See Pro") { upgrade() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Adds or edits one rule, with a live test so you see what it covers.
private struct RuleEditor: View {
    let rule: CustomRule?
    let onSave: (CustomRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CustomRule.Kind = .domain
    @State private var value = ""
    @State private var sample = ""

    var body: some View {
        let problem = value.isEmpty ? nil : CustomRule.problem(kind: kind, value: value)
        VStack(alignment: .leading, spacing: 14) {
            Text(rule == nil ? "Add a Rule" : "Edit Rule").font(.headline)
            Picker("Kind", selection: $kind) {
                ForEach(CustomRule.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                TextField(kind.placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .font(kind == .pattern ? .system(.body, design: .monospaced) : .body)
                Text(problem ?? kind.help)
                    .font(.caption)
                    .foregroundStyle(problem == nil ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Try it").font(.subheadline.weight(.semibold))
                TextField("Paste some text to see what this rule covers", text: $sample)
                    .textFieldStyle(.roundedBorder)
                Text(testResult(valid: problem == nil))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(rule == nil ? "Add" : "Save") {
                    var saved = rule ?? CustomRule(kind: kind, value: value)
                    saved.kind = kind
                    saved.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(value.isEmpty || problem != nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if let rule {
                kind = rule.kind
                value = rule.value
            }
        }
    }

    private func testResult(valid: Bool) -> String {
        guard !sample.isEmpty else { return " " }
        guard valid, !value.isEmpty else { return "Fix the rule above to test it." }
        let rules = TextRules(settings: DetectionSettings(enabled: [], customRules: [CustomRule(kind: kind, value: value)]))
        let matches = rules.matches(in: sample).map { String(sample[$0.range]) }
        return matches.isEmpty ? "Nothing in this text would be covered." : "Covers: " + matches.joined(separator: ", ")
    }
}

/// What Pro gives, and the buttons to buy or restore it.
struct ProView: View {
    let pro: ProStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: pro.isPro ? "checkmark.seal.fill" : "star.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 4) {
                Text(pro.isPro ? "You have Screenshot Redactor Pro" : "Screenshot Redactor Pro")
                    .font(.title2.weight(.semibold))
                Text(pro.isPro ? "Thank you for supporting the app." : "One purchase. No subscription.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                feature("infinity", "Unlimited redactions", "Free includes \(DailyAllowance.freePerDay) a day.")
                feature("list.bullet.rectangle", "Your own rules", "Internal domains, customer IDs, code names, patterns.")
                feature("lock.shield", "The same privacy", "Everything still stays on this Mac.")
            }
            .frame(maxWidth: 360, alignment: .leading)

            if !pro.isPro {
                Button {
                    Task { await pro.purchase() }
                } label: {
                    Text(pro.isPurchasing ? "Purchasing…" : "Buy Pro for \(pro.priceText)")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(pro.isPurchasing || pro.product == nil)
            }
            Button("Restore Purchase") { Task { await pro.restore() } }
                .buttonStyle(.borderless)
                .disabled(pro.isPurchasing)
            if let message = pro.message {
                Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { if pro.product == nil { await pro.loadProduct() } }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// The upgrade window, opened from "Unlock Unlimited" and the menu.
final class PaywallController: NSObject, NSWindowDelegate {
    private let pro: ProStore
    private var window: NSWindow?

    init(pro: ProStore) {
        self.pro = pro
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Screenshot Redactor Pro"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: ProView(pro: pro).padding(28).frame(width: 460, height: 480))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.deactivate() }
        }
    }
}
