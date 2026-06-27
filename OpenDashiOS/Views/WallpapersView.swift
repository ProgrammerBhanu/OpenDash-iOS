import SwiftUI
import PhotosUI
import UIKit

struct WallpapersView: View {
    @EnvironmentObject private var store: OpenDashStore
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedFit: WallpaperFit = .crop
    @State private var horizontalBias = 0.0
    @State private var verticalBias = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(
                        title: "Wallpapers",
                        subtitle: "Idle dash media with crop and fit controls."
                    )

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Current idle screen")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)

                            WallpaperPreview(wallpaper: store.activeWallpaper)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                            Picker("Fit", selection: $selectedFit) {
                                ForEach(WallpaperFit.allCases) { fit in
                                    Text(fit.rawValue).tag(fit)
                                }
                            }
                            .pickerStyle(.segmented)

                            VStack(alignment: .leading) {
                                Text("Horizontal position")
                                    .font(.caption)
                                    .foregroundStyle(OpenDashTheme.textSecondary)
                                Slider(value: $horizontalBias, in: -1...1)
                                    .tint(OpenDashTheme.gold)
                            }

                            VStack(alignment: .leading) {
                                Text("Vertical position")
                                    .font(.caption)
                                    .foregroundStyle(OpenDashTheme.textSecondary)
                                Slider(value: $verticalBias, in: -1...1)
                                    .tint(OpenDashTheme.gold)
                            }

                            HStack(spacing: 10) {
                                PhotosPicker(selection: $pickerItem, matching: .images) {
                                    Label("Add image", systemImage: "plus")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.black)
                                .background(OpenDashTheme.gold)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                SecondaryButton(title: "Save crop", systemImage: "checkmark") {
                                    updateActiveWallpaper()
                                }
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gallery")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)

                            if store.wallpapers.isEmpty {
                                EmptyState(title: "No wallpapers", subtitle: "Add up to five local images.", systemImage: "photo")
                            } else {
                                ForEach(store.wallpapers) { wallpaper in
                                    HStack(spacing: 12) {
                                        WallpaperThumbnail(wallpaper: wallpaper)
                                            .frame(width: 64, height: 42)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(wallpaper.name)
                                                .foregroundStyle(OpenDashTheme.textPrimary)
                                            Text(wallpaper.fit.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(OpenDashTheme.textSecondary)
                                        }
                                        Spacer()
                                        Button("Use") {
                                            store.activeWallpaperID = wallpaper.id
                                            selectedFit = wallpaper.fit
                                            horizontalBias = wallpaper.horizontalBias
                                            verticalBias = wallpaper.verticalBias
                                            store.persist()
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(OpenDashTheme.gold)
                                        Button(role: .destructive) {
                                            store.deleteWallpaper(wallpaper)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    Divider().overlay(Color.white.opacity(0.08))
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .openDashScreenBackground()
            .onAppear {
                if let wallpaper = store.activeWallpaper {
                    selectedFit = wallpaper.fit
                    horizontalBias = wallpaper.horizontalBias
                    verticalBias = wallpaper.verticalBias
                }
            }
            .onChange(of: pickerItem?.itemIdentifier) {
                Task { await importPickedImage() }
            }
        }
    }

    private func importPickedImage() async {
        guard let pickerItem,
              let data = try? await pickerItem.loadTransferable(type: Data.self)
        else { return }
        await MainActor.run {
            store.addWallpaper(name: "Wallpaper \(store.wallpapers.count + 1)", imageData: data, fit: selectedFit)
        }
    }

    private func updateActiveWallpaper() {
        guard var wallpaper = store.activeWallpaper else { return }
        wallpaper.fit = selectedFit
        wallpaper.horizontalBias = horizontalBias
        wallpaper.verticalBias = verticalBias
        store.updateWallpaper(wallpaper)
    }
}

private struct WallpaperPreview: View {
    var wallpaper: WallpaperItem?

    var body: some View {
        ZStack {
            Rectangle().fill(OpenDashTheme.elevated)
            if let image = wallpaper.flatMap({ UIImage(data: $0.imageData) }) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: wallpaper?.fit == .crop ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(OpenDashTheme.gold)
                    Text("Default idle screen")
                        .font(.subheadline)
                        .foregroundStyle(OpenDashTheme.textSecondary)
                }
            }
        }
    }
}

private struct WallpaperThumbnail: View {
    var wallpaper: WallpaperItem

    var body: some View {
        if let image = UIImage(data: wallpaper.imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(OpenDashTheme.elevated)
        }
    }
}
