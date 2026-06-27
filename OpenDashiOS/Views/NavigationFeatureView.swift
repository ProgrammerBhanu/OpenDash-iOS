import SwiftUI
import MapKit

struct NavigationFeatureView: View {
    @EnvironmentObject private var store: OpenDashStore
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var dashStreamer: BikeDashStreamer
    @State private var sharedText = ""
    private let credentialStore = SecureCredentialStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(
                        title: "Navigation",
                        subtitle: "Paste or open a Google Maps, Apple Maps, or geo link."
                    )

                    RouteMapView(
                        destination: store.currentDestination,
                        route: store.routePreview,
                        userCoordinate: location.coordinate
                    )
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Shared destination")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)
                            TextField("Paste map link or geo:lat,lng", text: $sharedText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                            PrimaryButton(title: "Import destination", systemImage: "square.and.arrow.down") {
                                Task {
                                    await store.importDestinationAndPlanRoute(sharedText, origin: location.coordinate)
                                }
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                    .foregroundStyle(OpenDashTheme.gold)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.currentDestination?.name ?? "No destination")
                                        .font(.headline)
                                        .foregroundStyle(OpenDashTheme.textPrimary)
                                    Text(destinationSubtitle)
                                        .font(.caption)
                                        .foregroundStyle(OpenDashTheme.textSecondary)
                                }
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                MetricTile(title: "Remaining", value: store.routePreview?.remainingText ?? "--", footnote: "Route")
                                MetricTile(title: "Arrive", value: store.routePreview?.etaText ?? "--", footnote: store.routePreview?.durationText)
                            }

                            Text(routeStatus)
                                .font(.caption)
                                .foregroundStyle(statusColor)

                            HStack(spacing: 10) {
                                SecondaryButton(title: "Plan route", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                                    Task { await store.planRoute(origin: location.coordinate) }
                                }
                                SecondaryButton(title: "Save", systemImage: "pin") {
                                    store.saveCurrentDestination()
                                }
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Bike dash")
                                    .font(.headline)
                                    .foregroundStyle(OpenDashTheme.textPrimary)
                                Spacer()
                                Text("\(dashStreamer.streamKind.title) / \(dashStreamer.stage.title)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(streamStageColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(streamStageColor.opacity(0.14))
                                    .clipShape(Capsule())
                            }

                            if dashStreamer.stage.isActive {
                                SecondaryButton(
                                    title: dashStreamer.streamKind == .navigation ? "Stop navigation" : "Stop current stream",
                                    systemImage: "stop.fill"
                                ) {
                                    dashStreamer.stop()
                                }
                            } else {
                                PrimaryButton(title: "Stream navigation", systemImage: "location.north.line.fill") {
                                    let credentials = credentialStore.load()
                                    dashStreamer.startNavigation(ssid: credentials.ssid, snapshot: navigationSnapshot)
                                }
                            }

                            Label(
                                dashStreamer.detail,
                                systemImage: dashStreamer.streamKind == .navigation ? "antenna.radiowaves.left.and.right" : "wifi"
                            )
                            .font(.caption)
                            .foregroundStyle(OpenDashTheme.textSecondary)

                            if dashStreamer.frameCount > 0 {
                                Text("Frames sent: \(dashStreamer.frameCount)")
                                    .font(.caption)
                                    .foregroundStyle(OpenDashTheme.textMuted)
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("GPS")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)
                            Label(location.gpsStatusText, systemImage: "location.fill")
                                .foregroundStyle(OpenDashTheme.textSecondary)
                            if let error = location.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(OpenDashTheme.red)
                            }
                            SecondaryButton(title: "Refresh location", systemImage: "arrow.clockwise") {
                                location.request()
                            }
                        }
                    }

                    if !store.savedDestinations.isEmpty {
                        OpenDashCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Saved")
                                    .font(.headline)
                                    .foregroundStyle(OpenDashTheme.textPrimary)
                                ForEach(store.savedDestinations) { destination in
                                    HStack {
                                        Button {
                                            store.setDestination(destination)
                                            Task { await store.planRoute(origin: location.coordinate) }
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(destination.name)
                                                    .foregroundStyle(OpenDashTheme.textPrimary)
                                                Text(String(format: "%.5f, %.5f", destination.coordinate.latitude, destination.coordinate.longitude))
                                                    .font(.caption)
                                                    .foregroundStyle(OpenDashTheme.textMuted)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.deleteDestination(destination)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
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

    private var navigationSnapshot: DashNavigationSnapshot? {
        DashNavigationSnapshot.make(
            destination: store.currentDestination,
            route: store.routePreview,
            location: location.location,
            gpsStatusText: location.gpsStatusText,
            routeState: store.routeState
        )
    }

    private var destinationSubtitle: String {
        guard let destination = store.currentDestination else {
            return "Import a Maps URL to begin"
        }
        return String(format: "%.5f, %.5f", destination.coordinate.latitude, destination.coordinate.longitude)
    }

    private var routeStatus: String {
        switch store.routeState {
        case .idle: return "Ready to plan"
        case .resolving: return "Resolving destination..."
        case .loading: return "Finding route with OSRM..."
        case .loaded: return "Route ready"
        case .failed(let message): return message
        }
    }

    private var streamStageColor: Color {
        switch dashStreamer.stage {
        case .streaming:
            return dashStreamer.streamKind == .navigation ? OpenDashTheme.green : OpenDashTheme.gold
        case .error:
            return OpenDashTheme.red
        case .connecting, .authenticating, .ready:
            return OpenDashTheme.gold
        case .idle:
            return OpenDashTheme.textSecondary
        }
    }

    private var statusColor: Color {
        switch store.routeState {
        case .failed: return OpenDashTheme.red
        case .loaded: return OpenDashTheme.green
        case .resolving: return OpenDashTheme.gold
        default: return OpenDashTheme.textSecondary
        }
    }
}

private struct RouteMapView: View {
    var destination: SharedDestination?
    var route: RoutePreview?
    var userCoordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            if let userCoordinate {
                Marker("You", systemImage: "location.fill", coordinate: userCoordinate)
                    .tint(.blue)
            }
            if let destination {
                Marker(destination.name, systemImage: "flag.fill", coordinate: destination.coordinate.locationCoordinate)
                    .tint(.orange)
            }
            if let route, route.points.count > 1 {
                MapPolyline(coordinates: route.points.map { $0.locationCoordinate })
                    .stroke(.blue, lineWidth: 5)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onChange(of: destination?.id) {
            fitMap()
        }
        .onChange(of: route?.points.count) {
            fitMap()
        }
    }

    private func fitMap() {
        let points = route?.points.map { $0.locationCoordinate } ??
            [destination?.coordinate.locationCoordinate, userCoordinate].compactMap { $0 }
        guard !points.isEmpty else {
            position = .automatic
            return
        }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLng = longitudes.min() ?? 0
        let maxLng = longitudes.max() ?? 0
        position = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLng + maxLng) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: max(0.01, (maxLat - minLat) * 1.35),
                    longitudeDelta: max(0.01, (maxLng - minLng) * 1.35)
                )
            )
        )
    }
}
