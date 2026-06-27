import Foundation
import Combine
import CoreLocation

enum RouteLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class OpenDashStore: ObservableObject {
    @Published var vehicles: [VehicleProfile] = []
    @Published var activeVehicleID: UUID?
    @Published var services: [ServiceItem] = []
    @Published var fuelFillUps: [FuelFillUp] = []
    @Published var expenses: [ExpenseItem] = []
    @Published var wallpapers: [WallpaperItem] = []
    @Published var activeWallpaperID: UUID?
    @Published var savedDestinations: [SharedDestination] = []
    @Published var rides: [RideSummary] = []
    @Published var currentDestination: SharedDestination?
    @Published var routePreview: RoutePreview?
    @Published var routeState: RouteLoadState = .idle

    private let persistence = LocalPersistence()

    init() {
        load()
    }

    var activeVehicle: VehicleProfile {
        if let id = activeVehicleID, let vehicle = vehicles.first(where: { $0.id == id }) {
            return vehicle
        }
        if let first = vehicles.first {
            return first
        }
        let seed = OpenDashSnapshot.seed()
        vehicles = seed.vehicles
        activeVehicleID = seed.activeVehicleID
        return seed.vehicles[0]
    }

    var activeServices: [ServiceItem] {
        services
            .filter { $0.vehicleID == activeVehicle.id }
            .sorted { lhs, rhs in
                lhs.remainingKm(currentOdometer: activeVehicle.odometerKm) <
                    rhs.remainingKm(currentOdometer: activeVehicle.odometerKm)
            }
    }

    var activeFuelFillUps: [FuelFillUp] {
        fuelFillUps
            .filter { $0.vehicleID == activeVehicle.id }
            .sorted { $0.odometerKm > $1.odometerKm }
    }

    var activeExpenses: [ExpenseItem] {
        expenses
            .filter { $0.vehicleID == activeVehicle.id }
            .sorted { $0.date > $1.date }
    }

    var monthlyExpenses: [ExpenseItem] {
        let calendar = Calendar.current
        return activeExpenses.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    var averageMileageKmpl: Double? {
        let fills = activeFuelFillUps.sorted { $0.odometerKm < $1.odometerKm }
        guard fills.count >= 2 else { return nil }
        let pairs = zip(fills.dropFirst(), fills).compactMap { current, previous -> Double? in
            guard current.odometerKm > previous.odometerKm, current.litres > 0 else { return nil }
            return Double(current.odometerKm - previous.odometerKm) / current.litres
        }
        let latest = Array(pairs.suffix(5))
        guard !latest.isEmpty else { return nil }
        return latest.reduce(0, +) / Double(latest.count)
    }

    var activeWallpaper: WallpaperItem? {
        guard let id = activeWallpaperID else { return wallpapers.first }
        return wallpapers.first(where: { $0.id == id }) ?? wallpapers.first
    }

    func load() {
        let snapshot = persistence.load() ?? OpenDashSnapshot.seed()
        vehicles = snapshot.vehicles
        activeVehicleID = snapshot.activeVehicleID
        services = snapshot.services
        fuelFillUps = snapshot.fuelFillUps
        expenses = snapshot.expenses
        wallpapers = snapshot.wallpapers
        activeWallpaperID = snapshot.activeWallpaperID
        savedDestinations = snapshot.savedDestinations
        rides = snapshot.rides
    }

    func persist() {
        guard let activeID = activeVehicleID ?? vehicles.first?.id else { return }
        let snapshot = OpenDashSnapshot(
            vehicles: vehicles,
            activeVehicleID: activeID,
            services: services,
            fuelFillUps: fuelFillUps,
            expenses: expenses,
            wallpapers: wallpapers,
            activeWallpaperID: activeWallpaperID,
            savedDestinations: savedDestinations,
            rides: rides
        )
        persistence.save(snapshot)
    }

    func importSharedText(_ text: String) {
        guard let destination = DestinationParser.parse(text) else {
            routeState = .failed("No destination coordinates found")
            return
        }
        currentDestination = destination
        routePreview = nil
        routeState = .idle
    }

    func setDestination(_ destination: SharedDestination) {
        currentDestination = destination
        routePreview = nil
        routeState = .idle
    }

    func saveCurrentDestination() {
        guard let destination = currentDestination else { return }
        if !savedDestinations.contains(where: { $0.coordinate == destination.coordinate }) {
            savedDestinations.insert(destination, at: 0)
            persist()
        }
    }

    func deleteDestination(_ destination: SharedDestination) {
        savedDestinations.removeAll { $0.id == destination.id }
        persist()
    }

    func planRoute(origin: CLLocationCoordinate2D?) async {
        guard let destination = currentDestination else { return }
        guard let origin else {
            routeState = .failed("Waiting for GPS")
            return
        }
        routeState = .loading
        do {
            let preview = try await RouteService.shared.route(
                from: Coordinate(latitude: origin.latitude, longitude: origin.longitude),
                to: destination.coordinate
            )
            routePreview = preview
            routeState = .loaded
        } catch {
            routePreview = nil
            routeState = .failed(error.localizedDescription)
        }
    }

    func addVehicle(name: String, nickname: String, odometerKm: Int) {
        let vehicle = VehicleProfile(
            name: name,
            nickname: nickname,
            odometerKm: odometerKm,
            pucDate: nil,
            insuranceDate: nil,
            serviceNotes: ""
        )
        vehicles.append(vehicle)
        activeVehicleID = vehicle.id
        persist()
    }

    func updateActiveVehicle(_ transform: (inout VehicleProfile) -> Void) {
        guard let index = vehicles.firstIndex(where: { $0.id == activeVehicle.id }) else { return }
        transform(&vehicles[index])
        persist()
    }

    func selectVehicle(_ vehicle: VehicleProfile) {
        activeVehicleID = vehicle.id
        persist()
    }

    func addService(name: String, intervalKm: Int) {
        services.append(
            ServiceItem(
                vehicleID: activeVehicle.id,
                name: name,
                intervalKm: intervalKm,
                lastDoneOdometerKm: activeVehicle.odometerKm,
                lastDoneDate: Date()
            )
        )
        persist()
    }

    func markServiceDone(_ item: ServiceItem) {
        guard let index = services.firstIndex(where: { $0.id == item.id }) else { return }
        services[index].lastDoneOdometerKm = activeVehicle.odometerKm
        services[index].lastDoneDate = Date()
        persist()
    }

    func addFuel(litres: Double, cost: Double, odometerKm: Int, location: String) {
        fuelFillUps.append(
            FuelFillUp(
                vehicleID: activeVehicle.id,
                litres: litres,
                cost: cost,
                odometerKm: odometerKm,
                location: location
            )
        )
        if odometerKm > activeVehicle.odometerKm {
            updateActiveVehicle { $0.odometerKm = odometerKm }
        } else {
            persist()
        }
    }

    func deleteFuel(_ fill: FuelFillUp) {
        fuelFillUps.removeAll { $0.id == fill.id }
        persist()
    }

    func addExpense(category: ExpenseCategory, amount: Double, note: String) {
        expenses.append(
            ExpenseItem(
                vehicleID: activeVehicle.id,
                category: category,
                amount: amount,
                note: note
            )
        )
        persist()
    }

    func deleteExpense(_ expense: ExpenseItem) {
        expenses.removeAll { $0.id == expense.id }
        persist()
    }

    func addWallpaper(name: String, imageData: Data, fit: WallpaperFit) {
        let wallpaper = WallpaperItem(
            name: name,
            imageData: imageData,
            fit: fit,
            horizontalBias: 0,
            verticalBias: 0
        )
        wallpapers.insert(wallpaper, at: 0)
        activeWallpaperID = wallpaper.id
        if wallpapers.count > 5 {
            wallpapers = Array(wallpapers.prefix(5))
        }
        persist()
    }

    func updateWallpaper(_ wallpaper: WallpaperItem) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        wallpapers[index] = wallpaper
        activeWallpaperID = wallpaper.id
        persist()
    }

    func deleteWallpaper(_ wallpaper: WallpaperItem) {
        wallpapers.removeAll { $0.id == wallpaper.id }
        if activeWallpaperID == wallpaper.id {
            activeWallpaperID = wallpapers.first?.id
        }
        persist()
    }

    func exportExpensesCSV(monthOnly: Bool) -> URL? {
        let selected = monthOnly ? monthlyExpenses : activeExpenses
        let rows = selected.map { item in
            [
                item.date.formatted(date: .numeric, time: .omitted),
                item.category.rawValue,
                String(format: "%.2f", item.amount),
                item.note
            ].map(Self.csvCell).joined(separator: ",")
        }
        let header = "Date,Category,Amount,Note"
        let csv = ([header] + rows).joined(separator: "\n")
        let name = monthOnly ? "opendash-expenses-month.csv" : "opendash-expenses-all.csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func csvCell(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

struct LocalPersistence {
    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("opendash.json")
    }

    func load() -> OpenDashSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.openDash.decode(OpenDashSnapshot.self, from: data)
    }

    func save(_ snapshot: OpenDashSnapshot) {
        guard let data = try? JSONEncoder.openDash.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var openDash: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var openDash: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
