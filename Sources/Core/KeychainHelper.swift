import Foundation
import Security

// MARK: - Adaptive Single-Bundle Secret Store
// - When the binary is signed with a stable Code Signing certificate (e.g., a local
//   "CustomER Local" certificate or Apple Developer ID), secrets are stored in a SINGLE
//   macOS Keychain item (`secrets_bundle`) and cached in memory — giving per-app Keychain
//   isolation with zero rebuild popups.
// - When compiled unsigned / ad-hoc (`swiftc` without a signing cert), macOS Keychain
//   would re-prompt on every compile. In that mode, secrets are automatically stored in
//   an owner-only (`chmod 0600`) file at ~/Library/Application Support/CustomER/.secrets.json.
enum KeychainHelper {
    private static let service = "com.customER.app"
    private static let bundleAccount = "secrets_bundle"
    private static let queue = DispatchQueue(label: "com.customER.secretstore")
    private static let fileURL = AppPaths.file(".secrets.json")
    private static var cache: [String: String]?

    static let usesSystemKeychain: Bool = hasStableCodeSignature()

    private static func hasStableCodeSignature() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let selfCode = code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess, let sCode = staticCode else { return false }
        var infoCF: CFDictionary?
        let status = SecCodeCopySigningInformation(sCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF)
        guard status == errSecSuccess, let info = infoCF as? [String: Any] else { return false }
        if let certs = info[kSecCodeInfoCertificates as String] as? [Any], !certs.isEmpty {
            return true
        }
        return false
    }

    private static func readFromKeychainLocked() -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: bundleAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return dict
    }

    private static func writeToKeychainLocked(_ dict: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(dict) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: bundleAccount
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    private static func readFromFileLocked() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeToFileLocked(_ dict: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(dict) else { return false }
        AppPaths.writeAtomically(data, to: fileURL, privatePermissions: true)
        return true
    }

    private static func loadStoreLocked() -> [String: String] {
        if let existing = cache { return existing }

        if usesSystemKeychain {
            var dict = readFromKeychainLocked() ?? [:]
            // Automatically upgrade any existing .secrets.json into macOS Keychain
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let fileDict = readFromFileLocked()
                if !fileDict.isEmpty {
                    for (k, v) in fileDict where dict[k] == nil {
                        dict[k] = v
                    }
                    if writeToKeychainLocked(dict) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            }
            cache = dict
            return dict
        } else {
            let dict = readFromFileLocked()
            cache = dict
            return dict
        }
    }

    @discardableResult
    private static func persistLocked(_ dict: [String: String]) -> Bool {
        cache = dict
        if usesSystemKeychain {
            return writeToKeychainLocked(dict)
        } else {
            return writeToFileLocked(dict)
        }
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        queue.sync {
            var dict = loadStoreLocked()
            dict[account] = value
            return persistLocked(dict)
        }
    }

    static func load(account: String) -> String? {
        queue.sync {
            loadStoreLocked()[account]
        }
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        queue.sync {
            var dict = loadStoreLocked()
            dict.removeValue(forKey: account)
            return persistLocked(dict)
        }
    }
}
