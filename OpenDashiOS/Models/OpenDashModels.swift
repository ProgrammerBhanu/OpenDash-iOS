import Foundation
import CoreLocation

struct Coordinate: Codable, Hashable, Identifiable {
    var id: String { "\(latitude),\(longitude)" }
    var latitude: Double
    var longitude: Double

    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distanceMeters(to other: Coordinate) -> Double {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return a.distance(from: b)
    }
}

struct SharedDestination: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var coordinate: Coordinate
    var sourceText: String
    var createdAt: Date = Date()
}

struct RoutePreview: Codable, Equatable {
    var points: [Coordinate]
    var distanceMeters: Double
    var durationSeconds: Double

    var remainingText: String {
        if distanceMeters >= 10_000 {
            return String(format: "%.0f km", distanceMeters / 1_000)
        }
        if distanceMeters >= 1_000 {
            return String(format: "%.1f km", distanceMeters / 1_000)
        }
        return "\(Int(distanceMeters)) m"
    }

    var etaText: String {
        let arrival = Date().addingTimeInterval(durationSeconds)
        return arrival.formatted(date: .omitted, time: .shortened)
    }

    var durationText: String {
        let minutes = max(1, Int(durationSeconds / 60))
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

struct VehicleProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var nickname: String
    var odometerKm: Int
    var pucDate: Date?
    var insuranceDate: Date?
    var serviceNotes: String
}

struct ServiceItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var vehicleID: UUID
    var name: String
    var intervalKm: Int
    var lastDoneOdometerKm: Int
    var lastDoneDate: Date

    func remainingKm(currentOdometer: Int) -> Int {
        lastDoneOdometerKm + intervalKm - currentOdometer
    }
}

struct FuelFillUp: Codable, Identifiable, Equatable {
    var id = UUID()
    var vehicleID: UUID
    var date: Date = Date()
    var litres: Double
    var cost: Double
    var odometerKm: Int
    var location: String
}

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case fuel = "Fuel"
    case repairs = "Repairs"
    case accessories = "Accessories"
    case ridingGear = "Riding gear"
    case food = "Food"
    case stays = "Stays"
    case transport = "Transport"
    case other = "Other"

    var id: String { rawValue }
}

struct ExpenseItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var vehicleID: UUID
    var date: Date = Date()
    var category: ExpenseCategory
    var amount: Double
    var note: String
}

enum WallpaperFit: String, Codable, CaseIterable, Identifiable {
    case crop = "Crop"
    case fitHeight = "Fit height"
    case fitWidth = "Fit width"

    var id: String { rawValue }
}

struct WallpaperItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var imageData: Data
    var fit: WallpaperFit
    var horizontalBias: Double
    var verticalBias: Double
    var createdAt: Date = Date()
}

struct RideSummary: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var distanceKm: Double
    var durationMinutes: Int
    var averageSpeedKmh: Double
}

struct DashCredentials: Equatable {
    var ssid: String
    var password: String

    static let empty = DashCredentials(ssid: "", password: "")
}

struct OpenDashSnapshot: Codable {
    var vehicles: [VehicleProfile]
    var activeVehicleID: UUID
    var services: [ServiceItem]
    var fuelFillUps: [FuelFillUp]
    var expenses: [ExpenseItem]
    var wallpapers: [WallpaperItem]
    var activeWallpaperID: UUID?
    var savedDestinations: [SharedDestination]
    var rides: [RideSummary]

    static func seed() -> OpenDashSnapshot {
        let vehicle = VehicleProfile(
            name: "Himalayan 450",
            nickname: "Default vehicle",
            odometerKm: 325,
            pucDate: nil,
            insuranceDate: nil,
            serviceNotes: "Factory setup"
        )
        let services = [
            ServiceItem(vehicleID: vehicle.id, name: "Drive chain", intervalKm: 500, lastDoneOdometerKm: 0, lastDoneDate: Date()),
            ServiceItem(vehicleID: vehicle.id, name: "Engine oil", intervalKm: 10_000, lastDoneOdometerKm: 0, lastDoneDate: Date()),
            ServiceItem(vehicleID: vehicle.id, name: "Oil filter", intervalKm: 10_000, lastDoneOdometerKm: 0, lastDoneDate: Date()),
            ServiceItem(vehicleID: vehicle.id, name: "Air filter", intervalKm: 10_000, lastDoneOdometerKm: 0, lastDoneDate: Date()),
            ServiceItem(vehicleID: vehicle.id, name: "Brake pads - front", intervalKm: 10_000, lastDoneOdometerKm: 0, lastDoneDate: Date())
        ]
        return OpenDashSnapshot(
            vehicles: [vehicle],
            activeVehicleID: vehicle.id,
            services: services,
            fuelFillUps: [],
            expenses: [],
            wallpapers: [],
            activeWallpaperID: nil,
            savedDestinations: [],
            rides: []
        )
    }
}
