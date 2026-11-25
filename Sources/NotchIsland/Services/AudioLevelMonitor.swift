import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Measures how loud the Mac's sound output is, so the edge glow can pulse with
/// the music. Uses ScreenCaptureKit audio capture, which needs the Screen & System
/// Audio Recording permission. Audio is only measured, never recorded or stored.
@MainActor
final class AudioLevelMonitor: ObservableObject {
    enum State: Equatable {
        case off
        case starting
        case running
        /// Screen & System Audio Recording is not allowed yet.
        case needsPermission
        /// Allowed, but capture failed to start.
        case unavailable
    }

    /// Loudness from 0 (silent) to 1, smoothed.
    @Published private(set) var level: Double = 0
    @Published private(set) var state: State = .off

    private var stream: SCStream?
    private let output = AudioLevelOutput()
    /// Features currently wanting audio (edge glow, wallpaper). Metering runs while any do.
    private var users: Set<String> = []
    /// Slow-moving average loudness, for beat detection.
    private var average: Double = 0
    /// When the last beat was detected (CFAbsoluteTime). Not published: read per frame.
    private(set) var lastBeatTime: CFAbsoluteTime = 0

    init() {
        output.onLevel = { [weak self] value in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.ingest(value) }
            }
        }
    }

    /// Starts metering if the permission is already granted. Never shows a prompt:
    /// starting capture without permission makes macOS ask again every time.
    func start() {
        guard state != .running, state != .starting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            state = .needsPermission
            return
        }
        state = .starting
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    state = .unavailable
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                // Video is required but unused: keep it tiny and slow.
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 2)

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                try await stream.startCapture()
                guard state == .starting else {
                    try? await stream.stopCapture()
                    return
                }
                self.stream = stream
                state = .running
            } catch {
                state = .unavailable
            }
        }
    }

    func stop() {
        let running = stream
        stream = nil
        level = 0
        if state == .running || state == .starting { state = .off }
        Task { try? await running?.stopCapture() }
    }

    /// Shows the macOS permission prompt once. Called only from a button in Settings.
    /// macOS applies a new grant after the app is quit and reopened.
    func requestPermission() {
        if CGRequestScreenCaptureAccess() {
            state = .off
            start()
        } else {
            state = .needsPermission
        }
    }

    /// Turns metering on while at least one feature needs it.
    func use(_ user: String, _ needed: Bool) {
        if needed {
            users.insert(user)
        } else {
            users.remove(user)
        }
        if users.isEmpty {
            stop()
        } else {
            start()
        }
    }

    private func ingest(_ value: Double) {
        // Rise fast, fall slowly, so beats read as pulses.
        level = value > level ? value : level * 0.82 + value * 0.18

        // A beat is a jump well above the recent average, at most ~3.5 per second.
        average = average * 0.95 + value * 0.05
        let now = CFAbsoluteTimeGetCurrent()
        if Self.isBeat(value: value, average: average, sinceLastBeat: now - lastBeatTime) {
            lastBeatTime = now
        }
    }

    nonisolated static func isBeat(value: Double, average: Double, sinceLastBeat: Double) -> Bool {
        value > average + 0.08 && sinceLastBeat > 0.28
    }
}

/// Receives audio buffers on a background queue and reports loudness ~30 times a second.
final class AudioLevelOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "NotchIsland.audio-level")
    var onLevel: ((Double) -> Void)?
    private var lastReport: CFAbsoluteTime = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReport >= 1.0 / 30, let rms = Self.rms(of: sampleBuffer) else { return }
        lastReport = now
        onLevel?(Self.normalized(rms: rms))
    }

    /// Maps -50 dB…0 dB to 0…1.
    static func normalized(rms: Float) -> Double {
        let decibels = 20 * log10(max(Double(rms), 1e-6))
        return min(max((decibels + 50) / 50, 0), 1)
    }

    static func rms(of sampleBuffer: CMSampleBuffer) -> Float? {
        let maxBuffers = 2
        let list = AudioBufferList.allocate(maximumBuffers: maxBuffers)
        defer { free(list.unsafeMutablePointer) }
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: maxBuffers),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        var sum: Float = 0
        var count = 0
        for buffer in list {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for index in 0..<n {
                sum += samples[index] * samples[index]
            }
            count += n
        }
        guard count > 0 else { return nil }
        return (sum / Float(count)).squareRoot()
    }
}
