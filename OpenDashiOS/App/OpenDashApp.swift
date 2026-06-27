import SwiftUI

@main
struct OpenDashApp: App {
    @StateObject private var store = OpenDashStore()
    @StateObject private var location = LocationProvider()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(location)
                .task {
                    location.request()
                }
                .onOpenURL { url in
                    let sharedText = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "text" })?
                        .value ?? url.absoluteString
                    store.importSharedText(sharedText)
                    Task {
                        await store.planRoute(origin: location.coordinate)
                    }
                }
        }
    }
}
