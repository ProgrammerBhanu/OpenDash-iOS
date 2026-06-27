import Foundation
import CoreLocation

final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastError: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
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
}
