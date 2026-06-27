import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: OpenDashStore
    @EnvironmentObject private var location: LocationProvider

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(
                        title: "OpenDash",
                        subtitle: "Navigation, garage, expenses, and dash setup for iPhone."
                    )

                    OpenDashCard {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OpenDashTheme.elevated)
                                    .frame(width: 92, height: 92)
                                Circle()
                                    .trim(from: 0.15, to: 0.88)
                                    .stroke(OpenDashTheme.gold, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .rotationEffect(.degrees(110))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "location.north.fill")
                                    .font(.title2)
                                    .foregroundStyle(OpenDashTheme.gold)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(store.activeVehicle.name)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(OpenDashTheme.textPrimary)
                                Text(location.gpsStatusText)
                                    .font(.subheadline)
                                    .foregroundStyle(OpenDashTheme.textSecondary)
                                Text("\(store.activeVehicle.odometerKm) km odometer")
                                    .font(.caption)
                                    .foregroundStyle(OpenDashTheme.textMuted)
                            }
                            Spacer()
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricTile(title: "Destination", value: store.currentDestination?.name ?? "None", footnote: store.routePreview?.remainingText)
                        MetricTile(title: "ETA", value: store.routePreview?.etaText ?? "--", footnote: store.routePreview?.durationText)
                        MetricTile(title: "Mileage", value: mileageText, footnote: "Latest fill-ups")
                        MetricTile(title: "Month spend", value: store.monthlyExpenses.reduce(0.0) { $0 + $1.amount }.currencyText, footnote: "\(store.monthlyExpenses.count) expenses")
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ride setup")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)
                            Text("This iOS build includes the app-side features. Locked-screen H.264 dash streaming still needs the iPhone hardware proof first.")
                                .font(.subheadline)
                                .foregroundStyle(OpenDashTheme.textSecondary)
                            HStack {
                                Label("Local-first", systemImage: "lock.shield")
                                Spacer()
                                Label("Keychain Wi-Fi", systemImage: "key")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OpenDashTheme.gold)
                        }
                    }

                    if store.savedDestinations.isEmpty {
                        OpenDashCard {
                            EmptyState(
                                title: "No saved destinations",
                                subtitle: "Paste or open a map link in Navigate, then save it for future rides.",
                                systemImage: "mappin.and.ellipse"
                            )
                        }
                    } else {
                        OpenDashCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Saved destinations")
                                    .font(.headline)
                                    .foregroundStyle(OpenDashTheme.textPrimary)
                                ForEach(store.savedDestinations.prefix(3)) { destination in
                                    Button {
                                        store.setDestination(destination)
                                    } label: {
                                        HStack {
                                            Image(systemName: "mappin.circle.fill")
                                                .foregroundStyle(OpenDashTheme.gold)
                                            VStack(alignment: .leading) {
                                                Text(destination.name)
                                                    .foregroundStyle(OpenDashTheme.textPrimary)
                                                Text(String(format: "%.5f, %.5f", destination.coordinate.latitude, destination.coordinate.longitude))
                                                    .font(.caption)
                                                    .foregroundStyle(OpenDashTheme.textMuted)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .openDashScreenBackground()
        }
    }

    private var mileageText: String {
        guard let mileage = store.averageMileageKmpl else { return "--" }
        return String(format: "%.1f km/l", mileage)
    }
}
