import SwiftUI

@main
struct OpenDashApp: App {
    @StateObject private var store = OpenDashStore()
    @StateObject private var location = LocationProvider()
    @StateObject private var dashStreamer = BikeDashStreamer()
    @StateObject private var keepAlive = RideKeepAliveService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(dashStreamer)
                .environmentObject(keepAlive)
                .task {
                    location.request()
                }
                .onOpenURL { url in
                    let sharedText = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "text" })?
                        .value ?? url.absoluteString
                    Task {
                        await store.importDestinationAndPlanRoute(sharedText, origin: location.coordinate)
                    }
                }
        }
    }
}
