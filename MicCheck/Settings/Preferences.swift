import Foundation
import Observation

/// User preferences backed by UserDefaults. Per-device settings are keyed by CoreAudio UID.
@MainActor
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    var showDeviceNameInMenuBar: Bool { didSet { defaults.set(showDeviceNameInMenuBar, forKey: "showDeviceNameInMenuBar") } }
    var showLevelInMenuBar: Bool { didSet { defaults.set(showLevelInMenuBar, forKey: "showLevelInMenuBar") } }
    var hideVirtualDevices: Bool { didSet { defaults.set(hideVirtualDevices, forKey: "hideVirtualDevices") } }
    var showContinuityDevices: Bool { didSet { defaults.set(showContinuityDevices, forKey: "showContinuityDevices") } }
    var lockInput: Bool { didSet { defaults.set(lockInput, forKey: "lockInput") } }
    var lockedDeviceUID: String? { didSet { defaults.set(lockedDeviceUID, forKey: "lockedDeviceUID") } }
    private(set) var deviceNames: [String: String] { didSet { defaults.set(deviceNames, forKey: "deviceNames") } }
    private(set) var hiddenDeviceUIDs: Set<String> { didSet { defaults.set(Array(hiddenDeviceUIDs), forKey: "hiddenDeviceUIDs") } }

    init() {
        defaults.register(defaults: ["hideVirtualDevices": true, "showLevelInMenuBar": false])
        showDeviceNameInMenuBar = defaults.bool(forKey: "showDeviceNameInMenuBar")
        showLevelInMenuBar = defaults.bool(forKey: "showLevelInMenuBar")
        hideVirtualDevices = defaults.bool(forKey: "hideVirtualDevices")
        showContinuityDevices = defaults.bool(forKey: "showContinuityDevices")
        lockInput = defaults.bool(forKey: "lockInput")
        lockedDeviceUID = defaults.string(forKey: "lockedDeviceUID")
        deviceNames = defaults.dictionary(forKey: "deviceNames") as? [String: String] ?? [:]
        hiddenDeviceUIDs = Set(defaults.stringArray(forKey: "hiddenDeviceUIDs") ?? [])
    }

    func displayName(for device: InputDevice) -> String {
        deviceNames[device.uid] ?? device.systemName
    }

    func rename(_ device: InputDevice, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == device.systemName {
            deviceNames.removeValue(forKey: device.uid)
        } else {
            deviceNames[device.uid] = trimmed
        }
    }

    func isHidden(_ device: InputDevice) -> Bool { hiddenDeviceUIDs.contains(device.uid) }

    func setHidden(_ hidden: Bool, for device: InputDevice) {
        if hidden { hiddenDeviceUIDs.insert(device.uid) } else { hiddenDeviceUIDs.remove(device.uid) }
    }
}
