import AVFoundation
import CoreMedia
import CoreLocation
import CoreVideo
import Darwin
import Foundation
import Security
import SwiftUI
import UIKit
import VideoToolbox

enum BikeDashStreamStage: Equatable {
    case idle
    case connecting
    case authenticating
    case ready
    case streaming
    case error(String)

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .authenticating: return "Authenticating"
        case .ready: return "Ready"
        case .streaming: return "Streaming"
        case .error: return "Error"
        }
    }

    var isActive: Bool {
        switch self {
        case .connecting, .authenticating, .ready, .streaming:
            return true
        case .idle, .error:
            return false
        }
    }
}

enum BikeDashStreamKind: Equatable {
    case none
    case wallpaper
    case navigation

    var title: String {
        switch self {
        case .none: return "No stream"
        case .wallpaper: return "Wallpaper"
        case .navigation: return "Navigation"
        }
    }
}

struct DashNavigationSnapshot: Equatable, @unchecked Sendable {
    var destinationName: String
    var destinationCoordinate: Coordinate
    var userCoordinate: Coordinate?
    var routePoints: [Coordinate]
    var remainingText: String
    var etaText: String
    var durationText: String
    var gpsStatusText: String
    var speedText: String
    var routeStatusText: String
    var isOffRoute: Bool

    static func make(
        destination: SharedDestination?,
        route: RoutePreview?,
        location: CLLocation?,
        gpsStatusText: String,
        routeState: RouteLoadState
    ) -> DashNavigationSnapshot? {
        guard let destination else { return nil }

        let userCoordinate = location.map {
            Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        let routePoints = route?.points ?? []
        let remainingMeters = remainingMeters(
            userCoordinate: userCoordinate,
            destination: destination.coordinate,
            route: route
        )
        let durationSeconds = remainingDurationSeconds(
            remainingMeters: remainingMeters,
            route: route
        )
        let offRoute = isOffRoute(userCoordinate: userCoordinate, routePoints: routePoints)

        return DashNavigationSnapshot(
            destinationName: destination.name,
            destinationCoordinate: destination.coordinate,
            userCoordinate: userCoordinate,
            routePoints: routePoints,
            remainingText: distanceText(remainingMeters),
            etaText: etaText(durationSeconds),
            durationText: durationText(durationSeconds),
            gpsStatusText: gpsStatusText,
            speedText: speedText(location),
            routeStatusText: statusText(routeState: routeState, offRoute: offRoute),
            isOffRoute: offRoute
        )
    }

    private static func remainingMeters(
        userCoordinate: Coordinate?,
        destination: Coordinate,
        route: RoutePreview?
    ) -> Double {
        guard let userCoordinate else {
            return route?.distanceMeters ?? 0
        }

        guard let route, route.points.count > 1 else {
            return userCoordinate.distanceMeters(to: destination)
        }

        var nearestIndex = 0
        var nearestDistance = Double.greatestFiniteMagnitude
        for (index, point) in route.points.enumerated() {
            let distance = userCoordinate.distanceMeters(to: point)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }

        var remaining = userCoordinate.distanceMeters(to: route.points[nearestIndex])
        if nearestIndex < route.points.count - 1 {
            for index in nearestIndex..<(route.points.count - 1) {
                remaining += route.points[index].distanceMeters(to: route.points[index + 1])
            }
        }
        return max(0, remaining)
    }

    private static func remainingDurationSeconds(
        remainingMeters: Double,
        route: RoutePreview?
    ) -> TimeInterval? {
        guard let route,
              route.distanceMeters > 0,
              route.durationSeconds > 0
        else { return nil }
        return max(60, route.durationSeconds * min(1, remainingMeters / route.distanceMeters))
    }

    private static func isOffRoute(userCoordinate: Coordinate?, routePoints: [Coordinate]) -> Bool {
        guard let userCoordinate, routePoints.count > 1 else { return false }
        let nearestDistance = routePoints
            .map { userCoordinate.distanceMeters(to: $0) }
            .min() ?? 0
        return nearestDistance > 180
    }

    private static func distanceText(_ meters: Double) -> String {
        if meters >= 10_000 {
            return String(format: "%.0f km", meters / 1_000)
        }
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        return "\(max(0, Int(meters))) m"
    }

    private static func etaText(_ durationSeconds: TimeInterval?) -> String {
        guard let durationSeconds else { return "--" }
        return Date()
            .addingTimeInterval(durationSeconds)
            .formatted(date: .omitted, time: .shortened)
    }

    private static func durationText(_ durationSeconds: TimeInterval?) -> String {
        guard let durationSeconds else { return "--" }
        let minutes = max(1, Int(durationSeconds / 60))
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private static func speedText(_ location: CLLocation?) -> String {
        guard let speed = location?.speed, speed >= 0 else { return "--" }
        return "\(Int((speed * 3.6).rounded())) km/h"
    }

    private static func statusText(routeState: RouteLoadState, offRoute: Bool) -> String {
        switch routeState {
        case .idle:
            return "Ready"
        case .resolving:
            return "Resolving"
        case .loading:
            return "Planning"
        case .loaded:
            return offRoute ? "Off route" : "On route"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class BikeDashStreamer: ObservableObject {
    @Published var stage: BikeDashStreamStage = .idle
    @Published private(set) var streamKind: BikeDashStreamKind = .none
    @Published var frameCount = 0
    @Published var detail = "Connect iPhone to bike Wi-Fi first."

    private var streamTask: Task<Void, Never>?
    private var session: DashControlSession?
    private var latestNavigationSnapshot: DashNavigationSnapshot?

    func start(ssid: String, wallpaper: WallpaperItem?) {
        guard streamTask == nil else {
            detail = "Stop the current stream first."
            return
        }
        guard !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            streamKind = .none
            stage = .error("Save the bike Wi-Fi SSID in Settings first.")
            detail = "Missing dash SSID"
            return
        }
        guard let wallpaper else {
            streamKind = .none
            stage = .error("Add a wallpaper first.")
            detail = "No wallpaper selected"
            return
        }

        frameCount = 0
        streamKind = .wallpaper
        stage = .connecting
        detail = "Opening dash sockets"

        streamTask = Task { [weak self] in
            guard let self else { return }
            let control = DashControlSession()

            do {
                await MainActor.run {
                    self.session = control
                }

                try await control.connect(ssid: ssid) { stage, detail in
                    Task { @MainActor in
                        self.stage = stage
                        self.detail = detail
                    }
                }

                let videoFrame = try await MainActor.run {
                    DashVideoFrame(pixelBuffer: try WallpaperFrameRenderer.makePixelBuffer(from: wallpaper))
                }

                let packetizer = RtpPacketizer { packet in
                    control.sendRtp(packet)
                }

                let startMs = DashClock.nowMs
                let encoder = try H264WallpaperEncoder { nal, endOfAccessUnit in
                    let elapsedMs = DashClock.nowMs - startMs
                    packetizer.packetize(nal: nal, endOfAccessUnit: endOfAccessUnit, wallClockMs: elapsedMs)
                }
                defer { encoder.invalidate() }

                control.startProjectionHeartbeat()
                await MainActor.run {
                    self.stage = .streaming
                    self.detail = "Sending wallpaper frames"
                }

                var frameIndex: Int64 = 0
                while !Task.isCancelled {
                    try encoder.encode(pixelBuffer: videoFrame.pixelBuffer, frameIndex: frameIndex)
                    frameIndex += 1
                    await MainActor.run {
                        self.frameCount = Int(frameIndex)
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
            } catch is CancellationError {
                control.disconnect()
            } catch {
                control.disconnect()
                await MainActor.run {
                    self.stage = .error(error.localizedDescription)
                    self.detail = error.localizedDescription
                    self.streamKind = .none
                }
            }

            await MainActor.run {
                if self.streamTask != nil {
                    self.streamTask = nil
                    self.session = nil
                    if self.stage.isActive {
                        self.stage = .idle
                        self.detail = "Stopped"
                    }
                    if !self.stage.isActive {
                        self.streamKind = .none
                    }
                }
            }
        }
    }

    func startNavigation(ssid: String, snapshot: DashNavigationSnapshot?) {
        guard streamTask == nil else {
            detail = "Stop the current stream first."
            return
        }
        guard !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            streamKind = .none
            stage = .error("Save the bike Wi-Fi SSID in Settings first.")
            detail = "Missing dash SSID"
            return
        }
        guard let snapshot else {
            streamKind = .none
            stage = .error("Import a destination first.")
            detail = "No navigation destination"
            return
        }

        latestNavigationSnapshot = snapshot
        frameCount = 0
        streamKind = .navigation
        stage = .connecting
        detail = "Opening dash sockets"

        streamTask = Task { [weak self] in
            guard let self else { return }
            let control = DashControlSession()

            do {
                await MainActor.run {
                    self.session = control
                }

                try await control.connect(ssid: ssid) { stage, detail in
                    Task { @MainActor in
                        self.stage = stage
                        self.detail = detail
                    }
                }

                let packetizer = RtpPacketizer { packet in
                    control.sendRtp(packet)
                }

                let startMs = DashClock.nowMs
                let encoder = try H264WallpaperEncoder { nal, endOfAccessUnit in
                    let elapsedMs = DashClock.nowMs - startMs
                    packetizer.packetize(nal: nal, endOfAccessUnit: endOfAccessUnit, wallClockMs: elapsedMs)
                }
                defer { encoder.invalidate() }

                control.startProjectionHeartbeat()
                await MainActor.run {
                    self.stage = .streaming
                    self.detail = "Sending navigation frames"
                }

                var frameIndex: Int64 = 0
                while !Task.isCancelled {
                    let videoFrame = try await MainActor.run {
                        guard let snapshot = self.latestNavigationSnapshot else {
                            throw DashStreamError.noDestination
                        }
                        return DashVideoFrame(pixelBuffer: try NavigationFrameRenderer.makePixelBuffer(from: snapshot))
                    }
                    try encoder.encode(pixelBuffer: videoFrame.pixelBuffer, frameIndex: frameIndex)
                    frameIndex += 1
                    await MainActor.run {
                        self.frameCount = Int(frameIndex)
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
            } catch is CancellationError {
                control.disconnect()
            } catch {
                control.disconnect()
                await MainActor.run {
                    self.stage = .error(error.localizedDescription)
                    self.detail = error.localizedDescription
                    self.streamKind = .none
                }
            }

            await MainActor.run {
                if self.streamTask != nil {
                    self.streamTask = nil
                    self.session = nil
                    if self.stage.isActive {
                        self.stage = .idle
                        self.detail = "Stopped"
                    }
                    if !self.stage.isActive {
                        self.streamKind = .none
                    }
                }
            }
        }
    }

    func updateNavigation(_ snapshot: DashNavigationSnapshot?) {
        guard streamKind == .navigation else { return }
        latestNavigationSnapshot = snapshot
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        session?.disconnect()
        session = nil
        latestNavigationSnapshot = nil
        streamKind = .none
        stage = .idle
        detail = "Stopped"
    }
}

private enum DashStreamError: LocalizedError {
    case socket(String)
    case authTimeout
    case rsaKeyCreate
    case rsaEncrypt(String)
    case encoder(OSStatus)
    case pixelBuffer
    case imageDecode
    case noDestination

    var errorDescription: String? {
        switch self {
        case .socket(let message): return message
        case .authTimeout: return "Auth timed out. Check iPhone is connected to the bike Wi-Fi and SSID is exact."
        case .rsaKeyCreate: return "Could not create dash RSA key."
        case .rsaEncrypt(let message): return "Could not encrypt dash session key: \(message)"
        case .encoder(let status): return "H.264 encoder failed: \(status)"
        case .pixelBuffer: return "Could not create video frame."
        case .imageDecode: return "Could not decode wallpaper image."
        case .noDestination: return "No navigation destination selected."
        }
    }
}

private struct DashClock {
    static var nowMs: Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

private struct DashVideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}

private enum DashFrameOrientation {
    static func correctForDashDisplay(_ pixelBuffer: CVPixelBuffer) throws {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DashStreamError.pixelBuffer
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerPixel = 4
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let byteCount = bytesPerRow * height
        let source = Data(bytes: baseAddress, count: byteCount)
        let sourceBytes = [UInt8](source)
        let destination = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let sourceIndex = y * bytesPerRow + x * bytesPerPixel
                let destinationIndex = (height - 1 - y) * bytesPerRow + x * bytesPerPixel
                destination[destinationIndex] = sourceBytes[sourceIndex]
                destination[destinationIndex + 1] = sourceBytes[sourceIndex + 1]
                destination[destinationIndex + 2] = sourceBytes[sourceIndex + 2]
                destination[destinationIndex + 3] = sourceBytes[sourceIndex + 3]
            }
        }
    }
}

private final class DashControlSession {
    private static let authTimeoutMs: Int64 = 15_000
    private static let burstPauseNs: UInt64 = 20_000_000

    private let lock = NSLock()
    private var socket: DashUDPSocket?
    private var auth: DashAuth?
    private var authConfirmed = false
    private var authRetries = 0
    private var rxTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var projectionTask: Task<Void, Never>?

    func connect(
        ssid: String,
        onStage: @escaping (BikeDashStreamStage, String) -> Void
    ) async throws {
        onStage(.connecting, "Open bike Wi-Fi sockets")
        let socket = try DashUDPSocket()
        let auth = DashAuth(ssid: ssid)
        lock.withLock {
            self.socket = socket
            self.auth = auth
            self.authConfirmed = false
            self.authRetries = 0
        }

        startReceiveLoop()
        startStatusHeartbeat()

        onStage(.authenticating, "Sending dash auth burst")
        for packet in DashCommands.initialBurst(hostname: "OpenDash") {
            socket.sendControl(packet)
            try await Task.sleep(nanoseconds: Self.burstPauseNs)
        }

        let deadline = DashClock.nowMs + Self.authTimeoutMs
        while !isAuthConfirmed {
            try Task.checkCancellation()
            if DashClock.nowMs >= deadline {
                throw DashStreamError.authTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        onStage(.ready, "Opening idle projection")
        socket.sendControl(DashCommands.projectionFrame())
        try await Task.sleep(nanoseconds: 60_000_000)
        socket.sendControl(DashCommands.projectionOn())
        try await Task.sleep(nanoseconds: 40_000_000)
    }

    func startProjectionHeartbeat() {
        projectionTask?.cancel()
        projectionTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.socket?.sendControl(DashCommands.projectionFrame())
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    func sendRtp(_ packet: Data) {
        socket?.sendRtp(packet)
    }

    func disconnect() {
        rxTask?.cancel()
        heartbeatTask?.cancel()
        projectionTask?.cancel()
        rxTask = nil
        heartbeatTask = nil
        projectionTask = nil
        socket?.sendControl(DashCommands.projectionStop())
        socket?.sendControl(DashCommands.projectionOff())
        socket?.close()
        lock.withLock {
            socket = nil
            auth = nil
            authConfirmed = false
        }
    }

    private var isAuthConfirmed: Bool {
        lock.withLock { authConfirmed }
    }

    private func startReceiveLoop() {
        rxTask?.cancel()
        rxTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    if let packet = try self.socket?.receive() {
                        self.dispatchIncoming(packet)
                    }
                } catch {
                    break
                }
            }
        }
    }

    private func startStatusHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                self?.socket?.sendControl(DashCommands.heartbeat())
                if tick % 30 == 0 {
                    self?.socket?.sendControl(DashCommands.timeSync())
                }
                tick += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func dispatchIncoming(_ packet: Data) {
        let tlvs = K1GPacket.parseIncoming(packet)
        for tlv in tlvs {
            if tlv.type == 0x07 {
                handleAuth(tlv)
                continue
            }

            if tlv.type == 0x09,
               tlv.sub == 0x06,
               tlv.value.first == 0x55 {
                socket?.sendControl(DashCommands.frameDecodedIdr())
                continue
            }

            if tlv.type == 0x09,
               tlv.sub == 0x04,
               tlv.value.first == 0x55 {
                socket?.sendControl(DashCommands.frameDecodedP())
                continue
            }

            if tlv.type == 0x09,
               tlv.sub == 0x00,
               let code = tlv.value.last {
                socket?.sendControl(DashCommands.buttonAck(code: code))
            }
        }
    }

    private func handleAuth(_ tlv: DashTlv) {
        guard let event = lock.withLock({ auth?.ingest(tlv) }) else { return }
        switch event {
        case .sendKey(let packet):
            socket?.sendControl(packet)
        case .confirmed:
            lock.withLock { authConfirmed = true }
        case .rejected:
            var shouldRetry = false
            lock.withLock {
                authRetries += 1
                auth?.reset()
                shouldRetry = authRetries <= 5
            }
            if shouldRetry {
                socket?.sendControl(DashCommands.authRequest())
            }
        case .none:
            break
        }
    }
}

private final class DashUDPSocket {
    private static let dashIP = "192.168.1.1"
    private static let broadcastIP = "192.168.1.255"
    private static let controlPort: UInt16 = 2000
    private static let rxPort: UInt16 = 2002
    private static let rtpPort: UInt16 = 5000
    private static let receiveBufferSize = 65_535

    private let txFD: Int32
    private let rxFD: Int32
    private let rtpFD: Int32
    private let seqLock = NSLock()
    private var sequence = 0

    init() throws {
        txFD = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        rxFD = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        rtpFD = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard txFD >= 0, rxFD >= 0, rtpFD >= 0 else {
            throw DashStreamError.socket("Could not open UDP sockets.")
        }

        do {
            try Self.setBoolOption(txFD, option: SO_REUSEADDR, value: true)
            try Self.setBoolOption(txFD, option: SO_BROADCAST, value: true)
            try Self.bind(fd: txFD, port: Self.controlPort)

            try Self.setBoolOption(rxFD, option: SO_REUSEADDR, value: true)
            try Self.setReceiveTimeout(fd: rxFD, milliseconds: 500)
            try Self.bind(fd: rxFD, port: Self.rxPort)
        } catch {
            close()
            throw error
        }
    }

    func sendControl(_ packet: Data) {
        let patched = seqLock.withLock { () -> Data in
            let data = K1GPacket.patchSeq(packet, sequence: sequence)
            sequence = (sequence + 1) & 0xFF
            return data
        }
        send(patched, fd: txFD, ip: Self.broadcastIP, port: Self.controlPort)
    }

    func sendRtp(_ packet: Data) {
        send(packet, fd: rtpFD, ip: Self.dashIP, port: Self.rtpPort)
    }

    func receive() throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: Self.receiveBufferSize)
        let count = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let baseAddress = raw.baseAddress else { return -1 }
            return Darwin.recvfrom(rxFD, baseAddress, raw.count, 0, nil, nil)
        }

        if count > 0 {
            return Data(buffer.prefix(count))
        }

        if errno == EAGAIN || errno == EWOULDBLOCK {
            return nil
        }

        throw DashStreamError.socket(String(cString: strerror(errno)))
    }

    func close() {
        if txFD >= 0 { Darwin.close(txFD) }
        if rxFD >= 0 { Darwin.close(rxFD) }
        if rtpFD >= 0 { Darwin.close(rtpFD) }
    }

    private func send(_ data: Data, fd: Int32, ip: String, port: UInt16) {
        var address = Self.makeSockaddr(ip: ip, port: port)
        data.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) { socketAddress in
                    _ = Darwin.sendto(
                        fd,
                        baseAddress,
                        raw.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }

    private static func bind(fd: Int32, port: UInt16) throws {
        var address = makeSockaddr(ip: "0.0.0.0", port: port)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            throw DashStreamError.socket("Could not bind UDP port \(port): \(String(cString: strerror(errno)))")
        }
    }

    private static func setBoolOption(_ fd: Int32, option: Int32, value: Bool) throws {
        var optionValue: Int32 = value ? 1 : 0
        let result = Darwin.setsockopt(
            fd,
            SOL_SOCKET,
            option,
            &optionValue,
            socklen_t(MemoryLayout<Int32>.size)
        )
        guard result == 0 else {
            throw DashStreamError.socket(String(cString: strerror(errno)))
        }
    }

    private static func setReceiveTimeout(fd: Int32, milliseconds: Int) throws {
        var timeout = timeval(
            tv_sec: milliseconds / 1_000,
            tv_usec: Int32(milliseconds % 1_000) * 1_000
        )
        let result = Darwin.setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        guard result == 0 else {
            throw DashStreamError.socket(String(cString: strerror(errno)))
        }
    }

    private static func makeSockaddr(ip: String, port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        _ = ip.withCString { pointer in
            inet_pton(AF_INET, pointer, &address.sin_addr)
        }
        return address
    }
}

private enum DashAuthEvent {
    case sendKey(Data)
    case confirmed
    case rejected
    case none
}

private final class DashAuth {
    private let ssid: String
    private var modulus: Data?
    private var exponent: Data?
    private var keySent = false

    init(ssid: String) {
        self.ssid = ssid
    }

    func ingest(_ tlv: DashTlv) -> DashAuthEvent {
        guard tlv.type == 0x07 else { return .none }

        switch tlv.sub {
        case 0x00:
            modulus = tlv.value
        case 0x03:
            exponent = tlv.value
        case 0x01:
            return tlv.value.first == 0x01 ? .confirmed : .rejected
        default:
            return .none
        }

        guard !keySent, let modulus, let exponent else { return .none }
        keySent = true
        do {
            return .sendKey(try buildKeyPacket(modulus: modulus, exponent: exponent))
        } catch {
            return .none
        }
    }

    func reset() {
        modulus = nil
        exponent = nil
        keySent = false
    }

    private func buildKeyPacket(modulus: Data, exponent: Data) throws -> Data {
        var sessionKey = Data(count: 32)
        let status = sessionKey.withUnsafeMutableBytes { raw in
            SecRandomCopyBytes(kSecRandomDefault, 32, raw.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw DashStreamError.rsaEncrypt("random key failed")
        }

        var payload = Data(ssid.utf8)
        payload.append(sessionKey)

        guard let key = Self.makeRSAKey(modulus: modulus, exponent: exponent) else {
            throw DashStreamError.rsaKeyCreate
        }

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            payload as CFData,
            &error
        ) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw DashStreamError.rsaEncrypt(message)
        }

        return DashCommands.authSendKey(ciphertext: encrypted)
    }

    private static func makeRSAKey(modulus: Data, exponent: Data) -> SecKey? {
        let pkcs1 = derSequence(derInteger(modulus) + derInteger(exponent))
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: max(1024, modulus.count * 8)
        ]

        var error: Unmanaged<CFError>?
        if let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) {
            return key
        }

        let algorithm = Data(hex: "300D06092A864886F70D0101010500")
        var bitStringBody = Data([0x00])
        bitStringBody.append(pkcs1)
        let bitString = derTagged(0x03, body: bitStringBody)
        let spki = derSequence(algorithm + bitString)
        error = nil
        return SecKeyCreateWithData(spki as CFData, attributes as CFDictionary, &error)
    }

    private static func derInteger(_ data: Data) -> Data {
        var bytes = Array(data)
        while bytes.count > 1 && bytes.first == 0 {
            bytes.removeFirst()
        }
        if bytes.isEmpty {
            bytes = [0]
        }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return derTagged(0x02, body: Data(bytes))
    }

    private static func derSequence(_ body: Data) -> Data {
        derTagged(0x30, body: body)
    }

    private static func derTagged(_ tag: UInt8, body: Data) -> Data {
        var out = Data([tag])
        out.append(derLength(body.count))
        out.append(body)
        return out
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}

private struct DashTlv {
    var type: Int
    var sub: Int
    var value: Data
}

private enum K1GPacket {
    private static let magic = Data([0x4B, 0x31, 0x47, 0x20])
    private static let fixed = Data([
        0x00, 0x00, 0x00, 0x00,
        0x02, 0x01, 0x00, 0x05,
        0x4B, 0x31, 0x47, 0x20
    ])

    static func build(_ tlvs: [DashTlv]) -> Data {
        let segmentCount = 1 + tlvs.count
        var out = Data([0x00, 0x00, UInt8((segmentCount >> 8) & 0xFF), UInt8(segmentCount & 0xFF)])
        out.append(fixed)
        out.append(0x00)

        for tlv in tlvs {
            out.append(UInt8(tlv.type & 0xFF))
            out.append(UInt8(tlv.sub & 0xFF))
            out.append(UInt8((tlv.value.count >> 8) & 0xFF))
            out.append(UInt8(tlv.value.count & 0xFF))
            out.append(tlv.value)
        }

        out[0] = UInt8((out.count >> 8) & 0xFF)
        out[1] = UInt8(out.count & 0xFF)
        return out
    }

    static func patchSeq(_ packet: Data, sequence: Int) -> Data {
        var out = packet
        if let range = out.range(of: magic), range.upperBound < out.count {
            out[range.upperBound] = UInt8(sequence & 0xFF)
        }
        out[0] = UInt8((out.count >> 8) & 0xFF)
        out[1] = UInt8(out.count & 0xFF)
        return out
    }

    static func parseIncoming(_ data: Data) -> [DashTlv] {
        let bytes = Array(data)
        guard bytes.count >= 8 else { return [] }
        let segmentCount = (Int(bytes[2]) << 8) | Int(bytes[3])
        var tlvs: [DashTlv] = []
        var index = 8
        var count = 0

        while count < segmentCount && index + 4 <= bytes.count {
            let type = Int(bytes[index])
            let sub = Int(bytes[index + 1])
            let length = (Int(bytes[index + 2]) << 8) | Int(bytes[index + 3])
            index += 4
            let end = min(index + length, bytes.count)
            tlvs.append(DashTlv(type: type, sub: sub, value: Data(bytes[index..<end])))
            index = end
            count += 1
        }

        return tlvs
    }

    static func tlv(_ type: Int, _ sub: Int, _ values: [UInt8] = []) -> DashTlv {
        DashTlv(type: type, sub: sub, value: Data(values))
    }
}

private enum DashCommands {
    static func authRequest() -> Data {
        Data(hex: "0016000200000000020100054b314720000804000101")
    }

    static func authSendKey(ciphertext: Data) -> Data {
        var data = Data(hex: "0095000200000000020100054B3147200008000080")
        data.append(ciphertext)
        data[0] = UInt8((data.count >> 8) & 0xFF)
        data[1] = UInt8(data.count & 0xFF)
        return data
    }

    static func initialBurst(hostname: String) -> [Data] {
        [
            authRequest(),
            hostnameAnnounce(hostname: hostname),
            timeSync(),
            Data(hex: "0016000200000000020100054b314720030557000155"),
            Data(hex: "0016000200000000020100054b3147200405560001aa"),
            Data(hex: "0016000200000000020100054b3147200506050001aa"),
            Data(hex: "0016000200000000020100054b3147200605170001aa"),
            Data(hex: "001d000200000000020100054b314720080a020008aa55000000000000"),
            Data(hex: "0044000a00000000020100054b3147200906080001ff060300015506040001a2060f0001aa0601000101054c000113052d00020000051b00011905210001320521000132054d000132")
        ]
    }

    static func hostnameAnnounce(hostname: String) -> Data {
        let raw = Array(hostname.utf8.prefix(200))
        var out = Data(hex: "0021000200000000020100054b314720")
        out.append(contentsOf: [0x01, 0x06, 0x0B, 0x00, UInt8(raw.count + 1)])
        out.append(contentsOf: raw)
        out.append(0x00)
        out[0] = UInt8((out.count >> 8) & 0xFF)
        out[1] = UInt8(out.count & 0xFF)
        return out
    }

    static func timeSync() -> Data {
        let calendar = Calendar.current
        let now = Date()
        return K1GPacket.build([
            K1GPacket.tlv(
                0x06,
                0x06,
                [
                    UInt8(calendar.component(.hour, from: now)),
                    UInt8(calendar.component(.minute, from: now)),
                    UInt8(calendar.component(.second, from: now))
                ]
            )
        ])
    }

    static func projectionFrame() -> Data {
        Data(hex: "0016000200000000020100054B314720000556000155")
    }

    static func projectionOn() -> Data {
        Data(hex: "0016000200000000020100054B314720000605000155")
    }

    static func projectionStop() -> Data {
        Data(hex: "0016000200000000020100054B3147200005560001AA")
    }

    static func projectionOff() -> Data {
        Data(hex: "0016000200000000020100054B3147200006050001AA")
    }

    static func frameDecodedIdr() -> Data {
        Data(hex: "0016000200000000020100054B314720000611000155")
    }

    static func frameDecodedP() -> Data {
        Data(hex: "0016000200000000020100054B314720000612000155")
    }

    static func buttonAck(code: UInt8) -> Data {
        K1GPacket.build([K1GPacket.tlv(0x06, 0x80, [code])])
    }

    static func heartbeat(tempC: Int = 25) -> Data {
        var packet = Data(hex: "0049000b00000000020100054b3147200006080001050610000139060300015506040001a2060f0001aa0601000101054c000113052d00020000051b00011905210001320521000132054d000132")
        let marker = Data([0x06, 0x10, 0x00, 0x01])
        if let range = packet.range(of: marker), range.upperBound < packet.count {
            packet[range.upperBound] = UInt8((tempC + 40) & 0xFF)
        }
        return packet
    }
}

private final class RtpPacketizer {
    private static let maxPayload = 1_380
    private static let payloadType = 96

    private let onPacket: (Data) -> Void
    private var sequence = Int.random(in: 0...0xFFFF)
    private let ssrc = UInt32.random(in: 0...UInt32.max)
    private let timestampBase = UInt32.random(in: 0...UInt32.max)

    init(onPacket: @escaping (Data) -> Void) {
        self.onPacket = onPacket
    }

    func packetize(nal: Data, endOfAccessUnit: Bool, wallClockMs: Int64) {
        let timestamp = timestampBase &+ UInt32(truncatingIfNeeded: wallClockMs * 90)
        if nal.count <= Self.maxPayload {
            emit(payload: nal, marker: endOfAccessUnit, timestamp: timestamp)
        } else {
            fragmentFuA(nal: nal, endOfAccessUnit: endOfAccessUnit, timestamp: timestamp)
        }
    }

    private func fragmentFuA(nal: Data, endOfAccessUnit: Bool, timestamp: UInt32) {
        guard let first = nal.first else { return }
        let nalType = first & 0x1F
        let fuIndicator = (first & 0xE0) | 28
        let bytes = Array(nal)
        var offset = 1
        var isFirst = true

        while offset < bytes.count {
            let remaining = bytes.count - offset
            let chunkLength = min(Self.maxPayload - 2, remaining)
            let isLast = chunkLength >= remaining
            let fuHeader = (isFirst ? 0x80 : 0x00) | (isLast ? 0x40 : 0x00) | nalType
            var payload = Data([fuIndicator, fuHeader])
            payload.append(contentsOf: bytes[offset..<(offset + chunkLength)])
            emit(payload: payload, marker: isLast && endOfAccessUnit, timestamp: timestamp)
            offset += chunkLength
            isFirst = false
        }
    }

    private func emit(payload: Data, marker: Bool, timestamp: UInt32) {
        var packet = Data(count: 12)
        packet[0] = 0x80
        packet[1] = UInt8((marker ? 0x80 : 0x00) | Self.payloadType)
        packet[2] = UInt8((sequence >> 8) & 0xFF)
        packet[3] = UInt8(sequence & 0xFF)
        packet[4] = UInt8((timestamp >> 24) & 0xFF)
        packet[5] = UInt8((timestamp >> 16) & 0xFF)
        packet[6] = UInt8((timestamp >> 8) & 0xFF)
        packet[7] = UInt8(timestamp & 0xFF)
        packet[8] = UInt8((ssrc >> 24) & 0xFF)
        packet[9] = UInt8((ssrc >> 16) & 0xFF)
        packet[10] = UInt8((ssrc >> 8) & 0xFF)
        packet[11] = UInt8(ssrc & 0xFF)
        packet.append(payload)
        sequence = (sequence + 1) & 0xFFFF
        onPacket(packet)
    }
}

private final class H264WallpaperEncoder {
    static let width = 526
    static let height = 300
    private static let fps: Int32 = 4
    private static let bitrate = 200_000

    private let onNal: (Data, Bool) -> Void
    private var session: VTCompressionSession?

    init(onNal: @escaping (Data, Bool) -> Void) throws {
        self.onNal = onNal
        try prepare()
    }

    func encode(pixelBuffer: CVPixelBuffer, frameIndex: Int64) throws {
        guard let session else { throw DashStreamError.encoder(kVTInvalidSessionErr) }
        let presentationTime = CMTime(value: frameIndex, timescale: Self.fps)
        let duration = CMTime(value: 1, timescale: Self.fps)
        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        guard status == noErr else { throw DashStreamError.encoder(status) }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: presentationTime)
    }

    func invalidate() {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    private func prepare() throws {
        var createdSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(Self.width),
            height: Int32(Self.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: Self.outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &createdSession
        )
        guard status == noErr, let createdSession else {
            throw DashStreamError.encoder(status)
        }

        session = createdSession
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_4_1)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: Self.bitrate))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: Self.fps))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: Self.fps))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1))
        VTCompressionSessionPrepareToEncodeFrames(createdSession)
    }

    private static let outputCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
        guard status == noErr,
              let refcon,
              let sampleBuffer,
              CMSampleBufferDataIsReady(sampleBuffer)
        else { return }

        let encoder = Unmanaged<H264WallpaperEncoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.handle(sampleBuffer: sampleBuffer)
    }

    private func handle(sampleBuffer: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        let attachment = attachments.flatMap { unsafeBitCast(CFArrayGetValueAtIndex($0, 0), to: CFDictionary.self) }
        let isKeyFrame = attachment.map {
            !CFDictionaryContainsKey($0, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
        } ?? true

        var sps: Data?
        var pps: Data?
        if isKeyFrame, let description = CMSampleBufferGetFormatDescription(sampleBuffer) {
            sps = parameterSet(description: description, index: 0).map(normalizeSpsForDash)
            pps = parameterSet(description: description, index: 1)
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        guard CMBlockBufferGetDataLength(blockBuffer) > 0 else { return }
        totalLength = CMBlockBufferGetDataLength(blockBuffer)

        var data = Data(count: totalLength)
        let copyStatus = data.withUnsafeMutableBytes { raw -> OSStatus in
            guard let baseAddress = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: totalLength, destination: baseAddress)
        }
        guard copyStatus == noErr else { return }

        var offset = 0
        while offset + 4 <= data.count {
            let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            guard length > 0, offset + length <= data.count else { break }
            let nal = data[offset..<offset + length]
            emit(nal: Data(nal), sps: sps, pps: pps)
            offset += length
        }
    }

    private func emit(nal: Data, sps: Data?, pps: Data?) {
        guard let first = nal.first else { return }
        let type = first & 0x1F
        switch type {
        case 5:
            if let sps, let pps {
                var bundle = sps
                bundle.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                bundle.append(pps)
                bundle.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                bundle.append(nal)
                onNal(bundle, true)
            } else {
                onNal(nal, true)
            }
        case 1...4, 10...12:
            onNal(nal, false)
        default:
            break
        }
    }

    private func parameterSet(description: CMFormatDescription, index: Int) -> Data? {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        var count = 0
        var headerLength: Int32 = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            description,
            parameterSetIndex: index,
            parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size,
            parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: &headerLength
        )
        guard status == noErr, let pointer else { return nil }
        return Data(bytes: pointer, count: size)
    }

    private func normalizeSpsForDash(_ sps: Data) -> Data {
        var output = sps
        if output.count >= 4,
           output[0] & 0x1F == 7,
           output[1] == 0x42,
           output[3] == 0x29 {
            output[2] = 0x00
        }
        return output
    }
}

@MainActor
private enum NavigationFrameRenderer {
    private static let background = UIColor(red: 0.035, green: 0.043, blue: 0.043, alpha: 1)
    private static let surface = UIColor(red: 0.095, green: 0.105, blue: 0.10, alpha: 1)
    private static let elevated = UIColor(red: 0.14, green: 0.15, blue: 0.14, alpha: 1)
    private static let gold = UIColor(red: 0.95, green: 0.65, blue: 0.24, alpha: 1)
    private static let green = UIColor(red: 0.27, green: 0.78, blue: 0.50, alpha: 1)
    private static let red = UIColor(red: 0.93, green: 0.34, blue: 0.30, alpha: 1)
    private static let muted = UIColor(white: 1, alpha: 0.58)
    private static let faint = UIColor(white: 1, alpha: 0.18)

    static func makePixelBuffer(from snapshot: DashNavigationSnapshot) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            H264WallpaperEncoder.width,
            H264WallpaperEncoder.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw DashStreamError.pixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DashStreamError.pixelBuffer
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: H264WallpaperEncoder.width,
            height: H264WallpaperEncoder.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw DashStreamError.pixelBuffer
        }

        UIGraphicsPushContext(context)
        guard let drawContext = UIGraphicsGetCurrentContext() else {
            UIGraphicsPopContext()
            throw DashStreamError.pixelBuffer
        }

        draw(snapshot, context: drawContext)
        UIGraphicsPopContext()

        try DashFrameOrientation.correctForDashDisplay(pixelBuffer)

        return pixelBuffer
    }

    private static func draw(_ snapshot: DashNavigationSnapshot, context: CGContext) {
        let canvas = CGRect(x: 0, y: 0, width: H264WallpaperEncoder.width, height: H264WallpaperEncoder.height)
        background.setFill()
        UIRectFill(canvas)

        drawHeader(snapshot, in: CGRect(x: 16, y: 12, width: 494, height: 36))
        drawMetrics(snapshot, in: CGRect(x: 16, y: 60, width: 234, height: 146))
        drawMap(snapshot, context: context, in: CGRect(x: 266, y: 60, width: 244, height: 146))
        drawFooter(snapshot, in: CGRect(x: 16, y: 218, width: 494, height: 66))
    }

    private static func drawHeader(_ snapshot: DashNavigationSnapshot, in rect: CGRect) {
        drawRounded(rect, color: surface, radius: 14)
        drawText(
            "OPENDASH NAV",
            in: rect.insetBy(dx: 12, dy: 9),
            font: .systemFont(ofSize: 15, weight: .bold),
            color: .white
        )

        let chipColor = snapshot.isOffRoute ? red : green
        let chipRect = CGRect(x: rect.maxX - 132, y: rect.minY + 6, width: 120, height: 24)
        drawRounded(chipRect, color: chipColor.withAlphaComponent(0.22), radius: 12)
        drawText(
            snapshot.routeStatusText,
            in: chipRect.insetBy(dx: 10, dy: 4),
            font: .systemFont(ofSize: 11, weight: .bold),
            color: chipColor,
            alignment: .center
        )
    }

    private static func drawMetrics(_ snapshot: DashNavigationSnapshot, in rect: CGRect) {
        drawRounded(rect, color: surface, radius: 18)

        drawText(
            "REMAINING",
            in: CGRect(x: rect.minX + 14, y: rect.minY + 14, width: rect.width - 28, height: 16),
            font: .systemFont(ofSize: 11, weight: .bold),
            color: muted
        )
        drawText(
            snapshot.remainingText,
            in: CGRect(x: rect.minX + 14, y: rect.minY + 30, width: rect.width - 28, height: 46),
            font: .systemFont(ofSize: 39, weight: .heavy),
            color: .white
        )

        let itemWidth = (rect.width - 42) / 2
        drawMetricTile(
            title: "ETA",
            value: snapshot.etaText,
            rect: CGRect(x: rect.minX + 14, y: rect.minY + 88, width: itemWidth, height: 44)
        )
        drawMetricTile(
            title: "SPEED",
            value: snapshot.speedText,
            rect: CGRect(x: rect.minX + 28 + itemWidth, y: rect.minY + 88, width: itemWidth, height: 44)
        )
    }

    private static func drawMetricTile(title: String, value: String, rect: CGRect) {
        drawRounded(rect, color: elevated, radius: 12)
        drawText(
            title,
            in: CGRect(x: rect.minX + 9, y: rect.minY + 7, width: rect.width - 18, height: 12),
            font: .systemFont(ofSize: 9, weight: .bold),
            color: muted
        )
        drawText(
            value,
            in: CGRect(x: rect.minX + 9, y: rect.minY + 19, width: rect.width - 18, height: 18),
            font: .systemFont(ofSize: 15, weight: .bold),
            color: .white
        )
    }

    private static func drawMap(_ snapshot: DashNavigationSnapshot, context: CGContext, in rect: CGRect) {
        drawRounded(rect, color: surface, radius: 18)
        let inset = rect.insetBy(dx: 14, dy: 14)

        context.saveGState()
        UIBezierPath(roundedRect: inset, cornerRadius: 12).addClip()
        UIColor(red: 0.07, green: 0.085, blue: 0.08, alpha: 1).setFill()
        UIRectFill(inset)

        drawGrid(in: inset, context: context)

        let routePoints = snapshot.routePoints.count > 1
            ? snapshot.routePoints
            : [snapshot.userCoordinate, snapshot.destinationCoordinate].compactMap { $0 }
        let allPoints = routePoints + [snapshot.userCoordinate, snapshot.destinationCoordinate].compactMap { $0 }
        guard !allPoints.isEmpty else {
            context.restoreGState()
            return
        }

        let mapper = CoordinateMapper(points: allPoints, rect: inset.insetBy(dx: 14, dy: 14))

        if routePoints.count > 1 {
            context.setStrokeColor(gold.cgColor)
            context.setLineWidth(5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            for (index, point) in routePoints.enumerated() {
                let cgPoint = mapper.point(for: point)
                if index == 0 {
                    context.move(to: cgPoint)
                } else {
                    context.addLine(to: cgPoint)
                }
            }
            context.strokePath()
        }

        if let userCoordinate = snapshot.userCoordinate {
            drawDot(mapper.point(for: userCoordinate), color: green, radius: 7)
        }
        drawDot(mapper.point(for: snapshot.destinationCoordinate), color: gold, radius: 7)

        context.restoreGState()

        drawText(
            "ROUTE",
            in: CGRect(x: rect.minX + 16, y: rect.minY + 10, width: 70, height: 14),
            font: .systemFont(ofSize: 10, weight: .bold),
            color: muted
        )
    }

    private static func drawGrid(in rect: CGRect, context: CGContext) {
        context.setStrokeColor(faint.cgColor)
        context.setLineWidth(1)
        for index in 1...3 {
            let x = rect.minX + rect.width * CGFloat(index) / 4
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for index in 1...2 {
            let y = rect.minY + rect.height * CGFloat(index) / 3
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.strokePath()
    }

    private static func drawFooter(_ snapshot: DashNavigationSnapshot, in rect: CGRect) {
        drawRounded(rect, color: surface, radius: 18)
        drawText(
            snapshot.destinationName,
            in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 23),
            font: .systemFont(ofSize: 19, weight: .bold),
            color: .white
        )
        drawText(
            "\(snapshot.durationText)  |  \(snapshot.gpsStatusText)",
            in: CGRect(x: rect.minX + 14, y: rect.minY + 38, width: rect.width - 28, height: 16),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: snapshot.isOffRoute ? red : muted
        )
    }

    private static func drawDot(_ point: CGPoint, color: UIColor, radius: CGFloat) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )).fill()
        UIColor.white.withAlphaComponent(0.72).setStroke()
        UIBezierPath(ovalIn: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )).stroke()
    }

    private static func drawRounded(_ rect: CGRect, color: UIColor, radius: CGFloat) {
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private struct CoordinateMapper {
        private let minLat: Double
        private let maxLat: Double
        private let minLng: Double
        private let maxLng: Double
        private let rect: CGRect

        init(points: [Coordinate], rect: CGRect) {
            let latitudes = points.map(\.latitude)
            let longitudes = points.map(\.longitude)
            let rawMinLat = latitudes.min() ?? 0
            let rawMaxLat = latitudes.max() ?? 0
            let rawMinLng = longitudes.min() ?? 0
            let rawMaxLng = longitudes.max() ?? 0
            let latPadding = max(0.002, (rawMaxLat - rawMinLat) * 0.12)
            let lngPadding = max(0.002, (rawMaxLng - rawMinLng) * 0.12)
            minLat = rawMinLat - latPadding
            maxLat = rawMaxLat + latPadding
            minLng = rawMinLng - lngPadding
            maxLng = rawMaxLng + lngPadding
            self.rect = rect
        }

        func point(for coordinate: Coordinate) -> CGPoint {
            let lngSpan = max(0.000_001, maxLng - minLng)
            let latSpan = max(0.000_001, maxLat - minLat)
            let x = rect.minX + CGFloat((coordinate.longitude - minLng) / lngSpan) * rect.width
            let y = rect.maxY - CGFloat((coordinate.latitude - minLat) / latSpan) * rect.height
            return CGPoint(x: x, y: y)
        }
    }
}

@MainActor
private enum WallpaperFrameRenderer {
    static func makePixelBuffer(from wallpaper: WallpaperItem) throws -> CVPixelBuffer {
        guard let source = UIImage(data: wallpaper.imageData) else {
            throw DashStreamError.imageDecode
        }

        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            H264WallpaperEncoder.width,
            H264WallpaperEncoder.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw DashStreamError.pixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DashStreamError.pixelBuffer
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: H264WallpaperEncoder.width,
            height: H264WallpaperEncoder.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw DashStreamError.pixelBuffer
        }

        UIGraphicsPushContext(context)
        guard let drawContext = UIGraphicsGetCurrentContext() else {
            UIGraphicsPopContext()
            throw DashStreamError.pixelBuffer
        }

        UIColor(red: 0.04, green: 0.05, blue: 0.05, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: H264WallpaperEncoder.width, height: H264WallpaperEncoder.height))
        draw(source, wallpaper: wallpaper, context: drawContext)
        UIGraphicsPopContext()

        try DashFrameOrientation.correctForDashDisplay(pixelBuffer)

        return pixelBuffer
    }

    private static func draw(_ image: UIImage, wallpaper: WallpaperItem, context: CGContext) {
        let turns = wallpaper.effectiveRotationQuarterTurns
        let transformedSize = transformedImageSize(image.size, turns: turns)
        let transformedRect = drawRect(for: transformedSize, wallpaper: wallpaper)
        let sourceRect = sourceDrawRect(for: transformedRect, turns: turns)

        context.saveGState()
        context.translateBy(x: transformedRect.midX, y: transformedRect.midY)
        if wallpaper.effectiveIsFlippedHorizontally {
            context.scaleBy(x: -1, y: 1)
        }
        context.rotate(by: CGFloat(turns) * .pi / 2)
        image.draw(in: sourceRect)
        context.restoreGState()
    }

    private static func drawRect(for imageSize: CGSize, wallpaper: WallpaperItem) -> CGRect {
        let container = CGSize(width: H264WallpaperEncoder.width, height: H264WallpaperEncoder.height)
        let widthScale = container.width / max(imageSize.width, 1)
        let heightScale = container.height / max(imageSize.height, 1)
        let baseScale: CGFloat
        switch wallpaper.fit {
        case .crop:
            baseScale = max(widthScale, heightScale)
        case .fitWidth:
            baseScale = widthScale
        case .fitHeight:
            baseScale = heightScale
        }

        let scale = baseScale * wallpaper.effectiveZoom
        let renderSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let maxOffset = CGSize(
            width: abs(renderSize.width - container.width) / 2,
            height: abs(renderSize.height - container.height) / 2
        )
        let offset = CGSize(
            width: maxOffset.width * min(max(wallpaper.horizontalBias, -1), 1),
            height: maxOffset.height * min(max(wallpaper.verticalBias, -1), 1)
        )
        return CGRect(
            x: (container.width - renderSize.width) / 2 + offset.width,
            y: (container.height - renderSize.height) / 2 + offset.height,
            width: renderSize.width,
            height: renderSize.height
        )
    }

    private static func transformedImageSize(_ size: CGSize, turns: Int) -> CGSize {
        turns % 2 == 0
            ? size
            : CGSize(width: size.height, height: size.width)
    }

    private static func sourceDrawRect(for transformedRect: CGRect, turns: Int) -> CGRect {
        let size = turns % 2 == 0
            ? transformedRect.size
            : CGSize(width: transformedRect.height, height: transformedRect.width)
        return CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private extension Data {
    init(hex: String) {
        let clean = hex.filter { !$0.isWhitespace }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            bytes.append(UInt8(clean[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
