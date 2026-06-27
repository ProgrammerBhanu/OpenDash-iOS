import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var store: OpenDashStore
    @State private var serviceName = ""
    @State private var serviceInterval = 500
    @State private var litres = 0.0
    @State private var fuelCost = 0.0
    @State private var fuelOdometer = 0
    @State private var fuelLocation = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(
                        title: "Garage",
                        subtitle: "Service intervals, odometer, fuel diary, and mileage."
                    )

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricTile(title: "Odometer", value: "\(store.activeVehicle.odometerKm) km", footnote: store.activeVehicle.name)
                        MetricTile(title: "Mileage", value: mileageText, footnote: "Latest fills")
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Service intervals")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)

                            if store.activeServices.isEmpty {
                                EmptyState(title: "No service items", subtitle: "Add intervals for this vehicle.", systemImage: "wrench")
                            } else {
                                ForEach(store.activeServices) { item in
                                    HStack(spacing: 12) {
                                        Image(systemName: icon(for: item))
                                            .foregroundStyle(color(for: item))
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name)
                                                .foregroundStyle(OpenDashTheme.textPrimary)
                                            Text(serviceSubtitle(item))
                                                .font(.caption)
                                                .foregroundStyle(OpenDashTheme.textSecondary)
                                        }
                                        Spacer()
                                        Button("Done") {
                                            store.markServiceDone(item)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(OpenDashTheme.gold)
                                    }
                                    Divider().overlay(Color.white.opacity(0.08))
                                }
                            }

                            TextField("Service name", text: $serviceName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Interval km", value: $serviceInterval, format: .number)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            SecondaryButton(title: "Add interval", systemImage: "plus") {
                                guard !serviceName.isEmpty else { return }
                                store.addService(name: serviceName, intervalKm: serviceInterval)
                                serviceName = ""
                                serviceInterval = 500
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Fuel diary")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)

                            HStack(spacing: 10) {
                                TextField("Litres", value: $litres, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Cost", value: $fuelCost, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                            TextField("Odometer km", value: $fuelOdometer, format: .number)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .onAppear { fuelOdometer = store.activeVehicle.odometerKm }
                            TextField("Location", text: $fuelLocation)
                                .textFieldStyle(.roundedBorder)
                            PrimaryButton(title: "Add fill-up", systemImage: "fuelpump") {
                                guard litres > 0 else { return }
                                store.addFuel(litres: litres, cost: fuelCost, odometerKm: fuelOdometer, location: fuelLocation)
                                litres = 0
                                fuelCost = 0
                                fuelLocation = ""
                                fuelOdometer = store.activeVehicle.odometerKm
                            }

                            ForEach(store.activeFuelFillUps) { fill in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(String(format: "%.1f", fill.litres)) L - \(fill.cost.currencyText)")
                                            .foregroundStyle(OpenDashTheme.textPrimary)
                                        Text("\(fill.odometerKm) km - \(fill.date.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(OpenDashTheme.textSecondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        store.deleteFuel(fill)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
                .padding(18)
            }
            .openDashScreenBackground()
        }
    }

    private var mileageText: String {
        guard let mileage = store.averageMileageKmpl else { return "--" }
        return String(format: "%.1f km/l", mileage)
    }

    private func serviceSubtitle(_ item: ServiceItem) -> String {
        let remaining = item.remainingKm(currentOdometer: store.activeVehicle.odometerKm)
        if remaining < 0 {
            return "Overdue by \(abs(remaining)) km"
        }
        return "\(remaining) km remaining - every \(item.intervalKm) km"
    }

    private func color(for item: ServiceItem) -> Color {
        let remaining = item.remainingKm(currentOdometer: store.activeVehicle.odometerKm)
        if remaining < 0 { return OpenDashTheme.red }
        if remaining < item.intervalKm / 4 { return OpenDashTheme.gold }
        return OpenDashTheme.green
    }

    private func icon(for item: ServiceItem) -> String {
        let name = item.name.lowercased()
        if name.contains("chain") { return "link" }
        if name.contains("oil") { return "drop.fill" }
        if name.contains("brake") { return "gauge.with.dots.needle.67percent" }
        return "wrench.fill"
    }
}
