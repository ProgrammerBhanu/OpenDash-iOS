import Foundation
import CoreLocation

final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastError: String?
    @Published var isRideModeActive = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    var coordinate: CLLocationCoordinate2D? {
        location?.coordinate
    }

    var gpsStatusText: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard let location else { return "Waiting for GPS" }
            if location.horizontalAccuracy < 0 { return "Waiting for GPS" }
            if location.horizontalAccuracy <= 20 { return "GPS strong" }
            if location.horizontalAccuracy <= 50 { return "GPS weak" }
            return "GPS poor"
        case .denied, .restricted:
            return "Location disabled"
        case .notDetermined:
            return "Permission needed"
        @unknown default:
            return "GPS unknown"
        }
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func startRideMode() {
        guard !isRideModeActive else { return }
        isRideModeActive = true
        lastError = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            startBackgroundLocation()
        case .authorizedAlways:
            startBackgroundLocation()
        case .denied, .restricted:
            lastError = "Enable Location Always permission for locked-screen Ride Mode."
        @unknown default:
            lastError = "Location permission unavailable."
        }
    }

    func stopRideMode() {
        guard isRideModeActive else { return }
        isRideModeActive = false
        manager.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            if isRideModeActive {
                startBackgroundLocation()
            } else {
                manager.startUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        location = newest
        lastError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }

    private func startBackgroundLocation() {
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }
}
