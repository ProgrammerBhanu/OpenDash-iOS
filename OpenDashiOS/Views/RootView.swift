import SwiftUI

struct RootView: View {
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
    }
}
