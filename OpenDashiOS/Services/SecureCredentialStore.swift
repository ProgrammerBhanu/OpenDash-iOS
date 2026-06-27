import Foundation
import Security

struct SecureCredentialStore {
    private let service = "com.opendash.ios.dash-wifi"
    private let ssidAccount = "dash-ssid"
    private let passwordAccount = "dash-password"

    func load() -> DashCredentials {
        DashCredentials(
            ssid: read(account: ssidAccount) ?? "",
            password: read(account: passwordAccount) ?? ""
        )
    }

    func save(_ credentials: DashCredentials) {
        write(credentials.ssid, account: ssidAccount)
        write(credentials.password, account: passwordAccount)
    }

    func clear() {
        delete(account: ssidAccount)
        delete(account: passwordAccount)
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, account: String) {
        delete(account: account)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
