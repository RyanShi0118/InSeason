import SeasonBiteKit
import SwiftUI

struct SettingsView: View {
    private struct ChildDraft: Identifiable {
        let id = UUID()
        var age: Int
        var allergies: String
    }

    @Environment(\.dismiss) private var dismiss

    @State private var deepseekModel = ProviderSettings.load().deepseekModel
    @State private var deepseekBaseURL = ProviderSettings.load().deepseekBaseURL.absoluteString
    @State private var qwenModel = ProviderSettings.load().qwenModel
    @State private var qwenBaseURL = ProviderSettings.load().qwenBaseURL.absoluteString

    @State private var deepseekKey = Keychain.read(.deepseek) ?? ""
    @State private var qwenKey = Keychain.read(.qwen) ?? ""
    @State private var adults = ProviderSettings.loadHousehold().adults
    @State private var children = ProviderSettings.loadHousehold().children.map {
        ChildDraft(age: max(1, Int($0.ageYears.rounded())), allergies: ($0.allergies ?? []).joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Adults: \(adults)", value: $adults, in: 0...12)
                    ForEach($children) { $child in
                        VStack(alignment: .leading) {
                            Stepper("Child, age \(child.age)", value: $child.age, in: 1...17)
                            TextField("Allergies, comma-separated", text: $child.allergies)
                                .font(.subheadline)
                        }
                    }
                    .onDelete { children.remove(atOffsets: $0) }
                    Button("Add a child") {
                        children.append(ChildDraft(age: 4, allergies: ""))
                    }
                } header: {
                    Text("家庭 Household")
                } footer: {
                    Text("Swipe a child to remove them. Ages set portions and the sodium limit.")
                }

                Section {
                    SecureField("API key", text: $deepseekKey)
                    TextField("Model", text: $deepseekModel)
                    TextField("Base URL", text: $deepseekBaseURL)
                        .keyboardType(.URL)
                } header: {
                    Text("DeepSeek · meal plans")
                } footer: {
                    Text("deepseek-v4-pro plans more carefully; deepseek-flash is faster and cheaper.")
                }

                Section {
                    SecureField("API key", text: $qwenKey)
                    TextField("Model", text: $qwenModel)
                    TextField("Base URL", text: $qwenBaseURL)
                        .keyboardType(.URL)
                } header: {
                    Text("Qwen · photos")
                } footer: {
                    Text("An Alibaba Cloud Model Studio key for the Beijing region. A workspace URL such as https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1 also works.")
                }

                Section {
                    Text("Keys are stored in this iPhone's Keychain and sent only to DeepSeek and Qwen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        Keychain.save(deepseekKey, for: .deepseek)
        Keychain.save(qwenKey, for: .qwen)
        let defaults = UserDefaults.standard
        defaults.set(deepseekModel, forKey: ProviderSettings.Key.deepseekModel)
        defaults.set(deepseekBaseURL, forKey: ProviderSettings.Key.deepseekBaseURL)
        defaults.set(qwenModel, forKey: ProviderSettings.Key.qwenModel)
        defaults.set(qwenBaseURL, forKey: ProviderSettings.Key.qwenBaseURL)
        let household = Household(
            adults: adults,
            children: children.map { draft in
                Child(
                    ageYears: Double(draft.age),
                    allergies: draft.allergies
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                )
            }
        )
        ProviderSettings.saveHousehold(household)
    }
}
