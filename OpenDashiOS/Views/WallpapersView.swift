import SwiftUI
import PhotosUI
import UIKit

struct WallpapersView: View {
    @EnvironmentObject private var store: OpenDashStore
    @EnvironmentObject private var dashStreamer: BikeDashStreamer
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedFit: WallpaperFit = .crop
    @State private var horizontalBias = 0.0
    @State private var verticalBias = 0.0
    @State private var zoom = 1.0
    @State private var rotationQuarterTurns = 0
    @State private var isFlippedHorizontally = false
    @State private var isImporting = false
    @State private var importMessage: String?
    private let credentialStore = SecureCredentialStore()

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

                            WallpaperPreview(
                                wallpaper: store.activeWallpaper,
                                fit: selectedFit,
                                horizontalBias: horizontalBias,
                                verticalBias: verticalBias,
                                zoom: zoom,
                                rotationQuarterTurns: rotationQuarterTurns,
                                isFlippedHorizontally: isFlippedHorizontally
                            )
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                            Picker("Fit", selection: $selectedFit) {
                                ForEach(WallpaperFit.allCases) { fit in
                                    Text(fit.rawValue).tag(fit)
                                }
                            }
                            .pickerStyle(.segmented)

                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Photo size")
                                    Spacer()
                                    Text("\(Int(zoom * 100))%")
                                        .foregroundStyle(OpenDashTheme.textMuted)
                                }
                                .font(.caption)
                                .foregroundStyle(OpenDashTheme.textSecondary)
                                Slider(value: $zoom, in: 0.5...3)
                                    .tint(OpenDashTheme.gold)
                            }

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
                                SecondaryButton(title: "Rotate", systemImage: "rotate.right") {
                                    rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
                                }
                                SecondaryButton(
                                    title: isFlippedHorizontally ? "Unflip" : "Flip",
                                    systemImage: "arrow.left.and.right"
                                ) {
                                    isFlippedHorizontally.toggle()
                                }
                            }

                            Text(transformSummary)
                                .font(.caption)
                                .foregroundStyle(OpenDashTheme.textMuted)

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

                            Button {
                                resetCropControls()
                            } label: {
                                Label("Reset crop", systemImage: "arrow.counterclockwise")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(OpenDashTheme.gold)

                            if isImporting {
                                Label("Adding wallpaper...", systemImage: "photo.badge.plus")
                                    .font(.caption)
                                    .foregroundStyle(OpenDashTheme.textSecondary)
                            } else if let importMessage {
                                Label(importMessage, systemImage: importMessage.hasPrefix("Added") ? "checkmark.circle" : "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(importMessage.hasPrefix("Added") ? OpenDashTheme.green : OpenDashTheme.red)
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Bike dash")
                                    .font(.headline)
                                    .foregroundStyle(OpenDashTheme.textPrimary)
                                Spacer()
                                Text(dashStreamer.stage.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(streamStageColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(streamStageColor.opacity(0.14))
                                    .clipShape(Capsule())
                            }

                            if dashStreamer.stage.isActive {
                                SecondaryButton(title: "Stop stream", systemImage: "stop.fill") {
                                    dashStreamer.stop()
                                }
                            } else {
                                PrimaryButton(title: "Stream wallpaper", systemImage: "dot.radiowaves.left.and.right") {
                                    let credentials = credentialStore.load()
                                    dashStreamer.start(ssid: credentials.ssid, wallpaper: streamWallpaper)
                                }
                            }

                            Label(dashStreamer.detail, systemImage: dashStreamer.stage == .streaming ? "antenna.radiowaves.left.and.right" : "wifi")
                                .font(.caption)
                                .foregroundStyle(OpenDashTheme.textSecondary)
                            if dashStreamer.frameCount > 0 {
                                Text("Frames sent: \(dashStreamer.frameCount)")
                                    .font(.caption)
                                    .foregroundStyle(OpenDashTheme.textMuted)
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
                                        WallpaperPreview(wallpaper: wallpaper)
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
                                            zoom = wallpaper.effectiveZoom
                                            rotationQuarterTurns = wallpaper.effectiveRotationQuarterTurns
                                            isFlippedHorizontally = wallpaper.effectiveIsFlippedHorizontally
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
                syncControls(with: store.activeWallpaper)
            }
            .onChange(of: pickerItem) { _, newItem in
                Task { await importPickedImage(newItem) }
            }
        }
    }

    private var streamStageColor: Color {
        switch dashStreamer.stage {
        case .streaming:
            return OpenDashTheme.green
        case .error:
            return OpenDashTheme.red
        case .connecting, .authenticating, .ready:
            return OpenDashTheme.gold
        case .idle:
            return OpenDashTheme.textSecondary
        }
    }

    private var streamWallpaper: WallpaperItem? {
        guard var wallpaper = store.activeWallpaper else { return nil }
        wallpaper.fit = selectedFit
        wallpaper.horizontalBias = horizontalBias
        wallpaper.verticalBias = verticalBias
        wallpaper.zoom = zoom
        wallpaper.rotationQuarterTurns = rotationQuarterTurns
        wallpaper.isFlippedHorizontally = isFlippedHorizontally
        return wallpaper
    }

    private func importPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        await MainActor.run {
            isImporting = true
            importMessage = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    finishImport(message: "Could not read that photo.")
                }
                return
            }

            guard let image = UIImage(data: data),
                  let imageData = resizedJPEGData(from: image)
            else {
                await MainActor.run {
                    finishImport(message: "That image format is not supported.")
                }
                return
            }

            await MainActor.run {
                store.addWallpaper(name: "Wallpaper \(store.wallpapers.count + 1)", imageData: imageData, fit: selectedFit)
                syncControls(with: store.activeWallpaper)
                pickerItem = nil
                isImporting = false
                importMessage = "Added wallpaper"
            }
        } catch {
            await MainActor.run {
                finishImport(message: error.localizedDescription)
            }
        }
    }

    private func finishImport(message: String) {
        pickerItem = nil
        isImporting = false
        importMessage = message
    }

    private func resizedJPEGData(from image: UIImage) -> Data? {
        let maxPixel: CGFloat = 1_280
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > maxPixel ? maxPixel / longestSide : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }

    private func updateActiveWallpaper() {
        guard var wallpaper = store.activeWallpaper else { return }
        wallpaper.fit = selectedFit
        wallpaper.horizontalBias = horizontalBias
        wallpaper.verticalBias = verticalBias
        wallpaper.zoom = zoom
        wallpaper.rotationQuarterTurns = rotationQuarterTurns
        wallpaper.isFlippedHorizontally = isFlippedHorizontally
        store.updateWallpaper(wallpaper)
    }

    private func resetCropControls() {
        selectedFit = .crop
        horizontalBias = 0
        verticalBias = 0
        zoom = 1
        rotationQuarterTurns = 0
        isFlippedHorizontally = false
    }

    private func syncControls(with wallpaper: WallpaperItem?) {
        guard let wallpaper else {
            resetCropControls()
            return
        }

        selectedFit = wallpaper.fit
        horizontalBias = wallpaper.horizontalBias
        verticalBias = wallpaper.verticalBias
        zoom = wallpaper.effectiveZoom
        rotationQuarterTurns = wallpaper.effectiveRotationQuarterTurns
        isFlippedHorizontally = wallpaper.effectiveIsFlippedHorizontally
    }

    private var transformSummary: String {
        let degrees = rotationQuarterTurns * 90
        return isFlippedHorizontally
            ? "Rotation \(degrees)deg, flipped"
            : "Rotation \(degrees)deg"
    }
}

private struct WallpaperPreview: View {
    var wallpaper: WallpaperItem?
    var fit: WallpaperFit?
    var horizontalBias: Double?
    var verticalBias: Double?
    var zoom: Double?
    var rotationQuarterTurns: Int?
    var isFlippedHorizontally: Bool?

    var body: some View {
        ZStack {
            Rectangle().fill(OpenDashTheme.elevated)
            if let image = wallpaper.flatMap({ UIImage(data: $0.imageData) }) {
                GeometryReader { geometry in
                    let turns = effectiveRotationQuarterTurns
                    let transformedSize = transformedImageSize(image.size, turns: turns)
                    let layout = wallpaperLayout(
                        imageSize: transformedSize,
                        containerSize: geometry.size,
                        fit: fit ?? wallpaper?.fit ?? .crop,
                        horizontalBias: horizontalBias ?? wallpaper?.horizontalBias ?? 0,
                        verticalBias: verticalBias ?? wallpaper?.verticalBias ?? 0,
                        zoom: zoom ?? wallpaper?.effectiveZoom ?? 1
                    )
                    let frameSize = imageFrameSize(for: layout.size, turns: turns)

                    Image(uiImage: image)
                        .resizable()
                        .frame(width: frameSize.width, height: frameSize.height)
                        .rotationEffect(.degrees(Double(turns * 90)))
                        .scaleEffect(x: effectiveIsFlippedHorizontally ? -1 : 1, y: 1)
                        .position(
                            x: geometry.size.width / 2 + layout.offset.width,
                            y: geometry.size.height / 2 + layout.offset.height
                        )
                }
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

    private var effectiveRotationQuarterTurns: Int {
        let turns = rotationQuarterTurns ?? wallpaper?.effectiveRotationQuarterTurns ?? 0
        return ((turns % 4) + 4) % 4
    }

    private var effectiveIsFlippedHorizontally: Bool {
        isFlippedHorizontally ?? wallpaper?.effectiveIsFlippedHorizontally ?? false
    }

    private func wallpaperLayout(
        imageSize: CGSize,
        containerSize: CGSize,
        fit: WallpaperFit,
        horizontalBias: Double,
        verticalBias: Double,
        zoom: Double
    ) -> (size: CGSize, offset: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return (containerSize, .zero)
        }

        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let baseScale: CGFloat

        switch fit {
        case .crop:
            baseScale = max(widthScale, heightScale)
        case .fitWidth:
            baseScale = widthScale
        case .fitHeight:
            baseScale = heightScale
        }

        let clampedZoom = min(max(zoom, 0.5), 3.0)
        let renderSize = CGSize(
            width: imageSize.width * baseScale * clampedZoom,
            height: imageSize.height * baseScale * clampedZoom
        )
        let maxOffset = CGSize(
            width: abs(renderSize.width - containerSize.width) / 2,
            height: abs(renderSize.height - containerSize.height) / 2
        )
        let offset = CGSize(
            width: maxOffset.width * min(max(horizontalBias, -1), 1),
            height: maxOffset.height * min(max(verticalBias, -1), 1)
        )

        return (renderSize, offset)
    }

    private func transformedImageSize(_ size: CGSize, turns: Int) -> CGSize {
        turns % 2 == 0
            ? size
            : CGSize(width: size.height, height: size.width)
    }

    private func imageFrameSize(for transformedSize: CGSize, turns: Int) -> CGSize {
        turns % 2 == 0
            ? transformedSize
            : CGSize(width: transformedSize.height, height: transformedSize.width)
    }
}
