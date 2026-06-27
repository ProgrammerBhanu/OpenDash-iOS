import SwiftUI

struct VehiclesView: View {
    @EnvironmentObject private var store: OpenDashStore
    @State private var name = ""
    @State private var nickname = ""
    @State private var odometer = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(
                        title: "Vehicles",
                        subtitle: "Profiles, active vehicle selection, and paperwork reminders."
                    )

                    ForEach(store.vehicles) { vehicle in
                        OpenDashCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(vehicle.name)
                                            .font(.headline)
                                            .foregroundStyle(OpenDashTheme.textPrimary)
                                        Text(vehicle.nickname.isEmpty ? "No nickname" : vehicle.nickname)
                                            .font(.subheadline)
                                            .foregroundStyle(OpenDashTheme.textSecondary)
                                    }
                                    Spacer()
                                    if store.activeVehicle.id == vehicle.id {
                                        Label("Active", systemImage: "checkmark.circle.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(OpenDashTheme.gold)
                                    } else {
                                        Button("Select") {
                                            store.selectVehicle(vehicle)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(OpenDashTheme.gold)
                                    }
                                }

                                HStack(spacing: 12) {
                                    MetricTile(title: "Odometer", value: "\(vehicle.odometerKm) km", footnote: nil)
                                    MetricTile(title: "Insurance", value: dateText(vehicle.insuranceDate), footnote: nil)
                                }

                                if store.activeVehicle.id == vehicle.id {
                                    VehicleEditor(vehicle: vehicle)
                                }
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add vehicle")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)
                            TextField("Vehicle name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            TextField("Nickname", text: $nickname)
                                .textFieldStyle(.roundedBorder)
                            TextField("Odometer km", value: $odometer, format: .number)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            PrimaryButton(title: "Add vehicle", systemImage: "plus") {
                                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                store.addVehicle(name: name, nickname: nickname, odometerKm: odometer)
                                name = ""
                                nickname = ""
                                odometer = 0
                            }
                        }
                    }
                }
                .padding(18)
            }
            .openDashScreenBackground()
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "Not set" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct VehicleEditor: View {
    @EnvironmentObject private var store: OpenDashStore
    var vehicle: VehicleProfile
    @State private var odometer: Int = 0
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active vehicle details")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OpenDashTheme.textPrimary)
            TextField("Odometer km", value: $odometer, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    odometer = vehicle.odometerKm
                    notes = vehicle.serviceNotes
                }
            TextField("Service notes", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            SecondaryButton(title: "Save active vehicle", systemImage: "square.and.arrow.down") {
                store.updateActiveVehicle {
                    $0.odometerKm = odometer
                    $0.serviceNotes = notes
                }
            }
        }
        .padding(.top, 4)
    }
}
