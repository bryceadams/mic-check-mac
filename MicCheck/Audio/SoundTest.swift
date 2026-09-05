import AVFoundation
import CoreAudio
import Foundation
import Observation

/// Records a short clip from a chosen input device and plays it back through
/// the system output, so you can hear what others would hear.
///
/// Recording uses a CoreAudio IO proc into memory (same approach as the meters),
/// so a slow Bluetooth device never blocks the UI. Playback uses AVAudioEngine on
/// the default output, started off the main thread.
@MainActor
@Observable
final class SoundTest {
    enum Phase: Equatable {
        case idle
        case starting
        case recording(elapsed: TimeInterval)
        case playing(elapsed: TimeInterval, duration: TimeInterval)
        case failed(String)
    }

    /// A tap records this long. A press-and-hold records until release, capped at `holdMaxDuration`.
    static let tapDuration: TimeInterval = 5
    static let holdMaxDuration: TimeInterval = 60

    private(set) var phase: Phase = .idle
    /// Duration limit for the current recording. Changed by `limit(to:)` when a hold turns out to be a tap.
    private(set) var maxDuration: TimeInterval = SoundTest.tapDuration
    private(set) var isHoldRecording = false
    private(set) var level: AudioLevel = .silent

    /// Recording state touched by the IO thread; guarded by `lock`.
    private final class Capture: @unchecked Sendable {
        let lock = NSLock()
        var channels: [[Float]] = []
        var sampleRate: Double = 0
        var maxFrames = 0
        var frames = 0
        var rms: Float = 0
        var peak: Float = 0
        var full = false

        func append(_ list: UnsafePointer<AudioBufferList>) {
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            lock.lock(); defer { lock.unlock() }
            guard !full, let first = buffers.first, let firstData = first.mData else { return }
            let interleaved = buffers.count == 1 && first.mNumberChannels > 1
            let channelCount = interleaved ? Int(first.mNumberChannels) : buffers.count
            if channels.isEmpty { channels = Array(repeating: [], count: channelCount) }
            let frameCount = interleaved
                ? Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channelCount)
                : Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let take = min(frameCount, maxFrames - frames)
            guard take > 0 else { full = true; return }
            var sum: Float = 0, pk: Float = 0
            if interleaved {
                let p = firstData.assumingMemoryBound(to: Float.self)
                for c in 0..<channelCount {
                    for i in 0..<take { let v = p[i * channelCount + c]; channels[c].append(v); sum += v * v; pk = max(pk, abs(v)) }
                }
            } else {
                for (c, buffer) in buffers.enumerated() where c < channelCount {
                    guard let d = buffer.mData else { continue }
                    let p = d.assumingMemoryBound(to: Float.self)
                    for i in 0..<take { let v = p[i]; channels[c].append(v); sum += v * v; pk = max(pk, abs(v)) }
                }
            }
            frames += take
            rms = max(rms, (sum / Float(take * channelCount)).squareRoot())
            peak = max(peak, pk)
            if frames >= maxFrames { full = true }
        }
    }

    private var capture: Capture?
    private var procID: AudioDeviceIOProcID?
    private var recordingDevice: AudioDeviceID?
    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timer: Timer?
    private var startedAt: Date?
    private var playDuration: TimeInterval = 0
    private var generation = 0

    private static let ioQueue = DispatchQueue(label: "dev.bryceadams.MicCheck.test.io", qos: .userInteractive)
    private static let controlQueue = DispatchQueue(label: "dev.bryceadams.MicCheck.test.control", qos: .userInitiated)

    var isActive: Bool {
        switch phase {
        case .starting, .recording, .playing: return true
        default: return false
        }
    }

    /// Starts recording from `deviceID`. Calling while recording stops early and plays back;
    /// calling while playing stops playback.
    func toggle(deviceID: AudioDeviceID) {
        switch phase {
        case .recording: finishAndPlay()
        case .playing: stopPlayback()
        case .starting: break
        default: startRecording(deviceID: deviceID, maxDuration: Self.tapDuration, hold: false)
        }
    }

    /// Shortens (or lengthens) the current recording's limit. Used when a press turns out to be a tap.
    func limit(to duration: TimeInterval) {
        maxDuration = duration
        isHoldRecording = false
        if let cap = capture {
            cap.lock.lock()
            cap.maxFrames = Int(cap.sampleRate * duration)
            cap.lock.unlock()
        }
    }

    func finishAndPlay() { finishRecordingAndPlay() }

    func cancel() {
        generation += 1
        stopRecordingProc()
        stopPlayback()
        phase = .idle
    }

    // MARK: Recording

    func startRecording(deviceID: AudioDeviceID, maxDuration: TimeInterval, hold: Bool) {
        generation += 1
        let gen = generation
        self.maxDuration = maxDuration
        isHoldRecording = hold
        let fmtAddr = CoreAudioHelpers.address(kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput)
        let fmt = CoreAudioHelpers.get(deviceID, fmtAddr, default: AudioStreamBasicDescription())
        let sampleRate = (fmt?.mSampleRate ?? 0) > 0 ? fmt!.mSampleRate : 48_000
        let cap = Capture()
        cap.sampleRate = sampleRate
        cap.maxFrames = Int(sampleRate * maxDuration)
        capture = cap
        recordingDevice = deviceID
        phase = .starting
        level = .silent
        DebugLog.write("test: start recording device \(deviceID) at \(sampleRate)Hz")

        Self.controlQueue.async { [weak self] in
            var proc: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, Self.ioQueue) { _, inputData, _, _, _ in
                cap.append(inputData)
            }
            guard status == noErr, let proc else {
                Task { @MainActor in self?.fail("Couldn't open that input", gen: gen) }
                return
            }
            let startStatus = AudioDeviceStart(deviceID, proc)
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen else {
                    Self.controlQueue.async { AudioDeviceStop(deviceID, proc); AudioDeviceDestroyIOProcID(deviceID, proc) }
                    return
                }
                guard startStatus == noErr else {
                    AudioDeviceDestroyIOProcID(deviceID, proc)
                    self.fail("Couldn't start recording", gen: gen); return
                }
                self.procID = proc
                self.startedAt = Date()
                self.phase = .recording(elapsed: 0)
                self.startTimer()
            }
        }
    }

    private func stopRecordingProc() {
        if let proc = procID, let id = recordingDevice {
            Self.controlQueue.async {
                AudioDeviceStop(id, proc)
                AudioDeviceDestroyIOProcID(id, proc)
            }
        }
        procID = nil
        recordingDevice = nil
    }

    private func finishRecordingAndPlay() {
        stopRecordingProc()
        level = .silent
        guard let cap = capture else { phase = .idle; return }
        cap.lock.lock()
        let channels = cap.channels, frames = cap.frames, sampleRate = cap.sampleRate
        cap.lock.unlock()
        capture = nil
        DebugLog.write("test: recorded \(frames) frames x\(channels.count) ch")
        guard frames > Int(sampleRate * 0.1), !channels.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels.count)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let dst = buffer.floatChannelData else {
            phase = .failed("Nothing was recorded"); return
        }
        for c in 0..<channels.count {
            channels[c].withUnsafeBufferPointer { src in
                dst[c].update(from: src.baseAddress!, count: min(frames, src.count))
            }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        play(buffer)
    }

    // MARK: Playback

    private func play(_ buffer: AVAudioPCMBuffer) {
        generation += 1
        let gen = generation
        playDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        phase = .playing(elapsed: 0, duration: playDuration)
        startedAt = Date()
        startTimer()

        Self.controlQueue.async { [weak self] in
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            do {
                try engine.start()
            } catch {
                DebugLog.write("test: playback engine failed: \(error.localizedDescription)")
                Task { @MainActor in self?.fail("Couldn't play the recording", gen: gen) }
                return
            }
            player.scheduleBuffer(buffer, at: nil, options: []) {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == gen else { return }
                    self.stopPlayback()
                }
            }
            player.play()
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen else {
                    player.stop(); engine.stop(); return
                }
                self.playbackEngine = engine
                self.playerNode = player
            }
        }
    }

    func stopPlayback() {
        let engine = playbackEngine, player = playerNode
        playbackEngine = nil
        playerNode = nil
        if engine != nil || player != nil {
            Self.controlQueue.async { player?.stop(); engine?.stop() }
        }
        timer?.invalidate(); timer = nil
        if case .playing = phase { phase = .idle }
    }

    // MARK: Timer

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(startedAt ?? Date())
        switch phase {
        case .recording:
            var rms: Float = 0, peak: Float = 0, full = false
            if let cap = capture {
                cap.lock.lock()
                rms = cap.rms; peak = cap.peak; full = cap.full
                cap.rms = 0; cap.peak = 0
                cap.lock.unlock()
            }
            var next = level
            next.rms = max(rms, next.rms * 0.82)
            next.peak = max(peak, next.peak * 0.94)
            next.clipped = peak >= 0.99
            level = next
            if full || elapsed >= maxDuration { finishRecordingAndPlay() } else { phase = .recording(elapsed: elapsed) }
        case .playing:
            if elapsed >= playDuration + 0.3 { stopPlayback() } else { phase = .playing(elapsed: min(elapsed, playDuration), duration: playDuration) }
        default:
            timer?.invalidate(); timer = nil
        }
    }

    private func fail(_ message: String, gen: Int) {
        guard generation == gen else { return }
        DebugLog.write("test: failed: \(message)")
        stopRecordingProc()
        capture = nil
        phase = .failed(message)
    }
}
