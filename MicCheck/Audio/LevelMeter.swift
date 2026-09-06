import CoreAudio
import Foundation
import Observation

/// Peak and RMS level for one device, 0...1 linear, updated on the main actor.
struct AudioLevel: Equatable {
    var rms: Float = 0
    var peak: Float = 0
    var clipped = false
    static let silent = AudioLevel()
}

/// Meters one input device with a CoreAudio IO proc. No AVAudioEngine, no format
/// negotiation: the HAL hands us the device's Float32 client-format buffers and
/// we reduce them to RMS/peak. Start/stop run on a background queue because
/// Bluetooth devices can take seconds to begin streaming.
@MainActor
@Observable
final class DeviceLevelMeter {
    let deviceID: AudioDeviceID
    private(set) var level: AudioLevel = .silent
    private(set) var isRunning = false

    /// Shared state touched by the IO thread; guarded by `lock`.
    private final class Shared: @unchecked Sendable {
        let lock = NSLock()
        var rms: Float = 0
        var peak: Float = 0
        var clip = false
        var buffers = 0
    }
    private let shared = Shared()
    private var procID: AudioDeviceIOProcID?
    private var displayTimer: Timer?
    private var startedAt: Date?
    private var generation = 0
    private var stopped = false

    /// IO callbacks land on `ioQueue`. Start/stop/destroy go through `controlQueue`, never
    /// `ioQueue`: AudioDeviceStop waits for in-flight IO blocks, so calling it from the IO queue deadlocks.
    private nonisolated static let ioQueue = DispatchQueue(label: "dev.bryceadams.MicCheck.meter.io", qos: .userInteractive)
    private nonisolated static let controlQueue = DispatchQueue(label: "dev.bryceadams.MicCheck.meter.control", qos: .userInitiated)

    init(deviceID: AudioDeviceID) {
        self.deviceID = deviceID
    }

    /// A meter that never runs and always reports `fixedLevel`. Used for screenshot rendering.
    init(deviceID: AudioDeviceID, fixedLevel: AudioLevel) {
        self.deviceID = deviceID
        self.level = fixedLevel
        self.stopped = true
    }

    func start() {
        guard !isRunning, procID == nil else { return }
        stopped = false
        generation += 1
        let gen = generation
        let id = deviceID
        let shared = self.shared
        startedAt = Date()

        Self.controlQueue.async { [weak self] in
            var proc: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&proc, id, Self.ioQueue) { _, inputData, _, _, _ in
                Self.accumulate(inputData, into: shared)
            }
            guard status == noErr, let proc else {
                DebugLog.write("device \(id): create IO proc failed \(status)")
                return
            }
            let startStatus = AudioDeviceStart(id, proc)
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen, !self.stopped else {
                    Self.controlQueue.async { AudioDeviceStop(id, proc); AudioDeviceDestroyIOProcID(id, proc) }
                    return
                }
                guard startStatus == noErr else {
                    DebugLog.write("device \(id): AudioDeviceStart failed \(startStatus)")
                    AudioDeviceDestroyIOProcID(id, proc)
                    return
                }
                self.procID = proc
                self.isRunning = true
                let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.displayTimer = timer
            }
        }
    }

    /// Runs on the IO thread. Treats every buffer as Float32 samples, which covers both
    /// interleaved and non-interleaved client formats.
    private nonisolated static func accumulate(_ list: UnsafePointer<AudioBufferList>, into shared: Shared) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        var sum: Float = 0, peak: Float = 0, count = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<n {
                let v = samples[i]
                sum += v * v
                let a = abs(v)
                if a > peak { peak = a }
            }
            count += n
        }
        guard count > 0 else { return }
        let rms = (sum / Float(count)).squareRoot()
        shared.lock.lock()
        shared.rms = max(shared.rms, rms)
        shared.peak = max(shared.peak, peak)
        shared.clip = shared.clip || peak >= 0.99
        shared.buffers += 1
        shared.lock.unlock()
    }

    private func tick() {
        shared.lock.lock()
        let rms = shared.rms, peak = shared.peak, clip = shared.clip, buffers = shared.buffers
        shared.rms = 0; shared.peak = 0; shared.clip = false
        shared.lock.unlock()

        if buffers == 0, let startedAt, Date().timeIntervalSince(startedAt) > 4 {
            // Still waiting on the device to stream. Bluetooth can take a while; keep waiting but say so once.
            DebugLog.write("device \(deviceID): no audio yet after 4s")
            self.startedAt = nil
        }

        var next = level
        next.rms = max(rms, next.rms * 0.82)
        next.peak = max(peak, next.peak * 0.94)
        next.clipped = clip
        if next != level { level = next }
    }

    func stop() {
        stopped = true
        generation += 1
        displayTimer?.invalidate()
        displayTimer = nil
        if let proc = procID {
            let id = deviceID
            Self.controlQueue.async {
                AudioDeviceStop(id, proc)
                AudioDeviceDestroyIOProcID(id, proc)
            }
        }
        procID = nil
        isRunning = false
        level = .silent
    }
}
