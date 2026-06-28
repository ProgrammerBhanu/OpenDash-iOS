import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var keepAlive: RideKeepAliveService
    @State private var credentials = DashCredentials.empty
    @State private var savedMessage: String?
    private let credentialStore = SecureCredentialStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(
                        title: "Settings",
                        subtitle: "Dash pairing details, privacy, and iOS capability notes."
                    )

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Dash Wi-Fi credentials")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)
                            Text("Stored in the iOS Keychain. With a Personal Team build, join the dash hotspot from iPhone Wi-Fi Settings.")
                                .font(.subheadline)
                                .foregroundStyle(OpenDashTheme.textSecondary)
                            TextField("Dash SSID", text: $credentials.ssid)
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(.roundedBorder)
                            SecureField("Password", text: $credentials.password)
                                .textFieldStyle(.roundedBorder)
                            HStack(spacing: 10) {
                                PrimaryButton(title: "Save", systemImage: "key") {
                                    credentialStore.save(credentials)
                                    savedMessage = "Saved to Keychain"
                                }
                                SecondaryButton(title: "Forget", systemImage: "trash") {
                                    credentialStore.clear()
                                    credentials = .empty
                                    savedMessage = "Credentials removed"
                                }
                            }
                            Label("Open iPhone Settings > Wi-Fi, join the bike dash network, then return to OpenDash.", systemImage: "wifi")
                                .font(.caption)
                                .foregroundStyle(OpenDashTheme.textSecondary)
                            if let savedMessage {
                                Text(savedMessage)
                                    .font(.caption)
                                    .foregroundStyle(OpenDashTheme.gold)
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("iOS feature status")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)
                            CapabilityRow(title: "Navigation and routing", status: "Built", color: OpenDashTheme.green)
                            CapabilityRow(title: "Vehicles, garage, expenses", status: "Built", color: OpenDashTheme.green)
                            CapabilityRow(title: "Wallpaper gallery", status: "Built", color: OpenDashTheme.green)
                            CapabilityRow(title: "Media and caller cards", status: "Limited", color: OpenDashTheme.gold)
                            CapabilityRow(title: "Locked-screen dash streaming", status: "Experimental", color: OpenDashTheme.gold)
                            CapabilityRow(title: "Ride Mode background GPS", status: rideModeStatus, color: rideModeColor)
                            CapabilityRow(title: "Audio keepalive", status: audioKeepAliveStatus, color: audioKeepAliveColor)
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Privacy")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)
                            Label("App data is saved locally in Application Support.", systemImage: "externaldrive")
                            Label("Dash credentials are saved in Keychain.", systemImage: "lock.shield")
                            Label("Expense export is created only when you tap share.", systemImage: "square.and.arrow.up")
                        }
                        .font(.subheadline)
                        .foregroundStyle(OpenDashTheme.textSecondary)
                    }
                }
                .padding(18)
            }
            .openDashScreenBackground()
            .onAppear {
                credentials = credentialStore.load()
            }
        }
    }

    private var rideModeStatus: String {
        if location.isRideModeActive { return "Active" }
        switch location.authorizationStatus {
        case .authorizedAlways:
            return "Ready"
        case .authorizedWhenInUse:
            return "Needs Always"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            return "Ask on stream"
        @unknown default:
            return "Unknown"
        }
    }

    private var rideModeColor: Color {
        if location.isRideModeActive { return OpenDashTheme.green }
        switch location.authorizationStatus {
        case .authorizedAlways:
            return OpenDashTheme.green
        case .authorizedWhenInUse, .notDetermined:
            return OpenDashTheme.gold
        case .denied, .restricted:
            return OpenDashTheme.red
        @unknown default:
            return OpenDashTheme.gold
        }
    }

    private var audioKeepAliveStatus: String {
        if keepAlive.isActive { return "Active" }
        if keepAlive.lastError != nil { return "Error" }
        return "Ready"
    }

    private var audioKeepAliveColor: Color {
        if keepAlive.isActive { return OpenDashTheme.green }
        if keepAlive.lastError != nil { return OpenDashTheme.red }
        return OpenDashTheme.gold
    }
}

private struct CapabilityRow: View {
    var title: String
    var status: String
    var color: Color

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(OpenDashTheme.textPrimary)
            Spacer()
            Text(status)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(color)
                .background(color.opacity(0.14))
                .clipShape(Capsule())
        }
    }
}
