import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var store: OpenDashStore
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var dashStreamer: BikeDashStreamer
    @EnvironmentObject private var keepAlive: RideKeepAliveService
    @State private var isScreenSaverPresented = false
    @State private var previousBrightness: CGFloat?

    var body: some View {
        ZStack {
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

            if dashStreamer.stage.isActive && !isScreenSaverPresented {
                ScreenSaverLaunchButton {
                    presentScreenSaver()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isScreenSaverPresented {
                RideScreenSaverOverlay(
                    streamKind: dashStreamer.streamKind,
                    frameCount: dashStreamer.frameCount,
                    onExit: dismissScreenSaver
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: dashStreamer.stage.isActive)
        .animation(.easeInOut(duration: 0.2), value: isScreenSaverPresented)
        .onAppear {
            syncNavigationProjection()
            syncRideMode()
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
        .onReceive(dashStreamer.$stage) { _ in
            syncRideMode()
        }
        .onReceive(dashStreamer.$streamKind) { _ in
            syncRideMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            restoreBrightness()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if isScreenSaverPresented {
                dimScreenForSaver()
            }
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

    private func syncRideMode() {
        let shouldRunRideMode = dashStreamer.stage.isActive && dashStreamer.streamKind != .none
        UIApplication.shared.isIdleTimerDisabled = shouldRunRideMode
        if shouldRunRideMode {
            location.startRideMode()
            keepAlive.start()
        } else {
            dismissScreenSaver()
            location.stopRideMode()
            keepAlive.stop()
        }
    }

    private func presentScreenSaver() {
        guard dashStreamer.stage.isActive else { return }
        isScreenSaverPresented = true
        dimScreenForSaver()
    }

    private func dismissScreenSaver() {
        isScreenSaverPresented = false
        restoreBrightness()
    }

    private func dimScreenForSaver() {
        if previousBrightness == nil {
            previousBrightness = UIScreen.main.brightness
        }
        UIScreen.main.brightness = 0.03
    }

    private func restoreBrightness() {
        guard let previousBrightness else { return }
        UIScreen.main.brightness = previousBrightness
        self.previousBrightness = nil
    }
}

private struct ScreenSaverLaunchButton: View {
    var action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: action) {
                    Label("Screen saver", systemImage: "moon.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(OpenDashTheme.gold)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 74)
    }
}

private struct RideScreenSaverOverlay: View {
    var streamKind: BikeDashStreamKind
    var frameCount: Int
    var onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                Image(systemName: "moon.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(OpenDashTheme.gold.opacity(0.9))

                VStack(spacing: 6) {
                    Text("Dash streaming")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text("\(streamKind.title) / \(frameCount) frames")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.4))
                }

                Spacer()

                Text("Hold to exit")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .contentShape(Capsule())
                    .onLongPressGesture(minimumDuration: 1.2, perform: onExit)

                Text("Keep this screen open. Do not press the side button.")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.32))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 34)
        }
    }
}
