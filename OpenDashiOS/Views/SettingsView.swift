import SwiftUI

struct SettingsView: View {
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
                            Text("Stored in the iOS Keychain. The streaming proof-of-concept will use these values when it is added.")
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
                            CapabilityRow(title: "Locked-screen dash streaming", status: "Needs hardware proof", color: OpenDashTheme.red)
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
