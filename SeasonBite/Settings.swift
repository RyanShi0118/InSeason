import Foundation
import SeasonBiteKit
import Security

/// Provider choices and the household, stored in UserDefaults. API keys live in the Keychain.
struct ProviderSettings {
    enum Key {
        static let deepseekModel = "deepseekModel"
        static let deepseekBaseURL = "deepseekBaseURL"
        static let qwenModel = "qwenModel"
        static let qwenBaseURL = "qwenBaseURL"
        static let household = "household"
    }

    var deepseekModel: String
    var deepseekBaseURL: URL
    var qwenModel: String
    var qwenBaseURL: URL
    var household: Household

    static let defaultHousehold = Household(adults: 2, children: [Child(ageYears: 4, allergies: [])])

    static func load(from defaults: UserDefaults = .standard) -> ProviderSettings {
        func string(_ key: String, _ fallback: String) -> String {
            let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? fallback : value
        }
        return ProviderSettings(
            deepseekModel: string(Key.deepseekModel, DeepSeekPlanner.defaultModel),
            deepseekBaseURL: URL(string: string(Key.deepseekBaseURL, DeepSeekPlanner.defaultBaseURL.absoluteString))
                ?? DeepSeekPlanner.defaultBaseURL,
            qwenModel: string(Key.qwenModel, QwenImageClient.defaultModel),
            qwenBaseURL: URL(string: string(Key.qwenBaseURL, QwenImageClient.defaultBaseURL.absoluteString))
                ?? QwenImageClient.defaultBaseURL,
            household: loadHousehold(from: defaults)
        )
    }

    static func loadHousehold(from defaults: UserDefaults = .standard) -> Household {
        guard let data = defaults.data(forKey: Key.household),
              let household = try? JSONDecoder().decode(Household.self, from: data)
        else { return defaultHousehold }
        return household
    }

    static func saveHousehold(_ household: Household, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(household), forKey: Key.household)
    }
}

enum Keychain {
    enum Account: String {
        case deepseek = "deepseek-api-key"
        case qwen = "qwen-api-key"
    }

    private static let service = "com.ryanshi.seasonbite"

    private static func query(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    static func read(_ account: Account) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saving an empty string removes the key.
    static func save(_ value: String, for account: Account) {
        SecItemDelete(query(account) as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = query(account)
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
