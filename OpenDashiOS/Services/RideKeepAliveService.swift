import AVFoundation
import UIKit

@MainActor
final class RideKeepAliveService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func start() {
        guard !isActive else { return }

        do {
            try configureAudioSession()
            try startAudioEngine()
            startBackgroundTask()
            lastError = nil
            isActive = true
        } catch {
            lastError = error.localizedDescription
            stop()
        }
    }

    func stop() {
        endBackgroundTask()

        if engine.isRunning {
            engine.stop()
        }
        if let sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = error.localizedDescription
        }

        isActive = false
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func startAudioEngine() throws {
        if engine.isRunning {
            engine.stop()
        }
        if let sourceNode {
            engine.detach(sourceNode)
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let node = AVAudioSourceNode { isSilence, _, frameCount, audioBufferList -> OSStatus in
            isSilence.pointee = false
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let channelCount = max(1, Int(buffer.mNumberChannels))
                let sampleCount = Int(frameCount) * channelCount
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<sampleCount {
                    samples[index] = 0.000_001
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        sourceNode = node
    }

    private func startBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "OpenDashRideKeepAlive") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
