import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: OpenDashStore
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var dashStreamer: BikeDashStreamer

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "gauge.with.dots.needle.67percent") }
            NavigationFeatureView()
                .tabItem { Label("Navigate", systemImage: "location.north.line") }
            VehiclesView()
                .tabItem { Label("Vehicles", systemImage: "motorcycle") }
            GarageView()
                .tabItem { Label("Garage", systemImage: "wrench.and.screwdriver") }
            ExpensesView()
                .tabItem { Label("Expenses", systemImage: "chart.bar.xaxis") }
            WallpapersView()
                .tabItem { Label("Wallpapers", systemImage: "photo.on.rectangle.angled") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(OpenDashTheme.gold)
        .onAppear {
            syncNavigationProjection()
        }
        .onReceive(location.$location) { _ in
            syncNavigationProjection()
        }
        .onReceive(store.$currentDestination) { _ in
            syncNavigationProjection()
        }
        .onReceive(store.$routePreview) { _ in
            syncNavigationProjection()
        }
        .onReceive(store.$routeState) { _ in
            syncNavigationProjection()
        }
    }

    private func syncNavigationProjection() {
        let snapshot = DashNavigationSnapshot.make(
            destination: store.currentDestination,
            route: store.routePreview,
            location: location.location,
            gpsStatusText: location.gpsStatusText,
            routeState: store.routeState
        )
        dashStreamer.updateNavigation(snapshot)
    }
}
