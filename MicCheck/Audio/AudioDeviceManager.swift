import CoreAudio
import Foundation
import Observation

/// Enumerates input devices, tracks and sets the system default input, and
/// exposes input gain. All published state changes on the main actor.
@MainActor
@Observable
final class AudioDeviceManager {
    private(set) var devices: [InputDevice] = []
    private(set) var defaultInputID: AudioDeviceID?
    /// Input volume of the default device, 0...1. nil when the device has no software gain control.
    private(set) var defaultInputGain: Float?

    /// Called whenever the system default input changes, with the new device ID.
    var onDefaultInputChanged: ((AudioDeviceID?) -> Void)?

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var listenerBlocks: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var gainListenerDevice: AudioDeviceID?

    init() {
        refreshDevices()
        refreshDefaultInput()
        installSystemListeners()
    }

    var defaultInput: InputDevice? {
        devices.first { $0.id == defaultInputID }
    }

    // MARK: Enumeration

    func refreshDevices() {
        let ids = CoreAudioHelpers.getArray(systemObject, CoreAudioHelpers.address(kAudioHardwarePropertyDevices), of: AudioDeviceID.self)
        devices = ids.compactMap { id in
            // Only devices with at least one input stream count as inputs.
            let streams = CoreAudioHelpers.getArray(id, CoreAudioHelpers.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput), of: AudioStreamID.self)
            guard !streams.isEmpty else { return nil }
            guard let uid = CoreAudioHelpers.getString(id, CoreAudioHelpers.address(kAudioDevicePropertyDeviceUID)) else { return nil }
            let name = CoreAudioHelpers.getString(id, CoreAudioHelpers.address(kAudioObjectPropertyName)) ?? "Unknown Device"
            let raw = CoreAudioHelpers.get(id, CoreAudioHelpers.address(kAudioDevicePropertyTransportType), default: UInt32(0)) ?? 0
            let outputs = CoreAudioHelpers.getArray(id, CoreAudioHelpers.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput), of: AudioStreamID.self)
            return InputDevice(id: id, uid: uid, systemName: name, transport: TransportKind(rawTransport: raw), hasOutput: !outputs.isEmpty)
        }
        .sorted { $0.systemName.localizedCaseInsensitiveCompare($1.systemName) == .orderedAscending }
    }

    // MARK: Default input

    func refreshDefaultInput() {
        let id = CoreAudioHelpers.get(systemObject, CoreAudioHelpers.address(kAudioHardwarePropertyDefaultInputDevice), default: AudioDeviceID(0))
        let newID: AudioDeviceID? = (id == nil || id == 0) ? nil : id
        if newID != defaultInputID {
            defaultInputID = newID
            installGainListener(for: newID)
        }
        refreshGain()
    }

    @discardableResult
    func setDefaultInput(_ id: AudioDeviceID) -> Bool {
        CoreAudioHelpers.set(systemObject, CoreAudioHelpers.address(kAudioHardwarePropertyDefaultInputDevice), value: id)
    }

    // MARK: Gain

    private func gainAddress(for device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        let main = CoreAudioHelpers.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: kAudioObjectPropertyElementMain)
        if CoreAudioHelpers.hasProperty(device, main) { return main }
        let ch1 = CoreAudioHelpers.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: 1)
        if CoreAudioHelpers.hasProperty(device, ch1) { return ch1 }
        return nil
    }

    func refreshGain() {
        guard let id = defaultInputID, let addr = gainAddress(for: id) else { defaultInputGain = nil; return }
        defaultInputGain = CoreAudioHelpers.get(id, addr, default: Float(0))
    }

    func setGain(_ value: Float) {
        guard let id = defaultInputID, let addr = gainAddress(for: id) else { return }
        let clamped = max(0, min(1, value))
        // Some devices expose per-channel controls only; set both channels when using channel addressing.
        if addr.mElement == kAudioObjectPropertyElementMain {
            CoreAudioHelpers.set(id, addr, value: clamped)
        } else {
            for ch: AudioObjectPropertyElement in [1, 2] {
                let a = CoreAudioHelpers.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: ch)
                if CoreAudioHelpers.hasProperty(id, a) { CoreAudioHelpers.set(id, a, value: clamped) }
            }
        }
        defaultInputGain = clamped
    }

    // MARK: Listeners

    private func installSystemListeners() {
        addListener(on: systemObject, CoreAudioHelpers.address(kAudioHardwarePropertyDevices)) { [weak self] in
            self?.refreshDevices()
            self?.refreshDefaultInput()
        }
        addListener(on: systemObject, CoreAudioHelpers.address(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in
            guard let self else { return }
            self.refreshDefaultInput()
            self.onDefaultInputChanged?(self.defaultInputID)
        }
    }

    private func installGainListener(for device: AudioDeviceID?) {
        if let old = gainListenerDevice {
            listenerBlocks.removeAll { entry in
                guard entry.0 == old else { return false }
                var addr = entry.1
                AudioObjectRemovePropertyListenerBlock(old, &addr, .main, entry.2)
                return true
            }
        }
        gainListenerDevice = device
        guard let device, let addr = gainAddress(for: device) else { return }
        addListener(on: device, addr) { [weak self] in self?.refreshGain() }
    }

    private func addListener(on object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ handler: @escaping @MainActor () -> Void) {
        var a = addr
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in handler() }
        }
        if AudioObjectAddPropertyListenerBlock(object, &a, .main, block) == noErr {
            listenerBlocks.append((object, addr, block))
        }
    }
}
