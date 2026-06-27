import Foundation
import NetworkExtension

struct DashWiFiConnector {
    enum ConnectionError: LocalizedError {
        case missingSSID
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .missingSSID:
                return "Enter the dash Wi-Fi name first."
            case .rejected(let message):
                return message
            }
        }
    }

    func join(credentials: DashCredentials) async throws {
        let ssid = credentials.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = credentials.password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty else { throw ConnectionError.missingSSID }

        let configuration: NEHotspotConfiguration
        if password.isEmpty {
            configuration = NEHotspotConfiguration(ssid: ssid)
        } else {
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        }
        configuration.joinOnce = false

        try await withCheckedThrowingContinuation { continuation in
            NEHotspotConfigurationManager.shared.apply(configuration) { error in
                if let nsError = error as NSError? {
                    if nsError.domain == NEHotspotConfigurationErrorDomain,
                       nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                        continuation.resume(returning: ())
                        return
                    }

                    continuation.resume(throwing: ConnectionError.rejected(nsError.localizedDescription))
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }
}
