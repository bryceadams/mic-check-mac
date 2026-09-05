import AVFoundation
import CoreAudio
import Foundation
import Observation

/// Records a short clip from a chosen input device and plays it back through
/// the system output, so you can hear what others would hear.
@MainActor
@Observable
final class SoundTest {
    enum Phase: Equatable {
        case idle
        case recording(elapsed: TimeInterval)
        case playing(elapsed: TimeInterval, duration: TimeInterval)
        case failed(String)
    }

    static let maxDuration: TimeInterval = 5

    private(set) var phase: Phase = .idle
    private(set) var level: AudioLevel = .silent

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var startedAt: Date?
    private var pendingPeak: Float = 0
    private var pendingRMS: Float = 0

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("miccheck-test.caf")
    }

    var isActive: Bool {
        switch phase {
        case .recording, .playing: return true
        default: return false
        }
    }

    /// Starts recording from `deviceID`. Calling while recording stops early and plays back;
    /// calling while playing stops playback.
    func toggle(deviceID: AudioDeviceID) {
        switch phase {
        case .recording: finishRecordingAndPlay()
        case .playing: stopPlayback()
        default: startRecording(deviceID: deviceID)
        }
    }

    func cancel() {
        tearDownEngine()
        stopPlayback()
        phase = .idle
    }

    private func startRecording(deviceID: AudioDeviceID) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        do {
            try input.auAudioUnit.setDeviceID(deviceID)
        } catch {
            phase = .failed("Couldn't open that input"); return
        }
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { phase = .failed("Input has no signal format"); return }

        try? FileManager.default.removeItem(at: fileURL)
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        } catch {
            phase = .failed("Couldn't create test recording"); return
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            try? file.write(from: buffer)
            guard let self, let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
            var sum: Float = 0, peak: Float = 0
            for c in 0..<channels {
                for i in 0..<frames { let v = data[c][i]; sum += v * v; peak = max(peak, abs(v)) }
            }
            let rms = frames > 0 ? (sum / Float(frames * channels)).squareRoot() : 0
            DispatchQueue.main.async { self.pendingRMS = max(self.pendingRMS, rms); self.pendingPeak = max(self.pendingPeak, peak) }
        }
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            phase = .failed("Couldn't start recording"); return
        }
        self.engine = engine
        self.file = file
        startedAt = Date()
        phase = .recording(elapsed: 0)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        switch phase {
        case .recording:
            let elapsed = Date().timeIntervalSince(startedAt ?? Date())
            var next = level
            next.rms = max(pendingRMS, next.rms * 0.82)
            next.peak = max(pendingPeak, next.peak * 0.94)
            next.clipped = pendingPeak >= 0.99
            pendingRMS = 0; pendingPeak = 0
            level = next
            if elapsed >= Self.maxDuration { finishRecordingAndPlay() } else { phase = .recording(elapsed: elapsed) }
        case .playing(_, let duration):
            guard let player, player.isPlaying else { stopPlayback(); return }
            phase = .playing(elapsed: player.currentTime, duration: duration)
        default:
            break
        }
    }

    private func finishRecordingAndPlay() {
        tearDownEngine()
        level = .silent
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.prepareToPlay()
            guard player.duration > 0.1 else { phase = .failed("Nothing was recorded"); return }
            player.play()
            self.player = player
            phase = .playing(elapsed: 0, duration: player.duration)
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
            }
        } catch {
            phase = .failed("Couldn't play the recording")
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        timer?.invalidate(); timer = nil
        if case .playing = phase { phase = .idle }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func tearDownEngine() {
        // Timer keeps running into playback; it is invalidated in stopPlayback.
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        file = nil
    }
}
