import CoreAudio
import Foundation

/// How a device is attached to the Mac. Drives the row icon and the virtual-device filter.
enum TransportKind: Equatable {
    case builtIn, usb, bluetooth, display, aggregate, virtual, continuity, other

    init(rawTransport: UInt32) {
        switch rawTransport {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeThunderbolt: self = .display
        case kAudioDeviceTransportTypeAggregate: self = .aggregate
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: self = .continuity
        default: self = .other
        }
    }

    var symbolName: String {
        switch self {
        case .builtIn: return "laptopcomputer"
        case .usb: return "cable.connector"
        case .bluetooth: return "wave.3.right"
        case .display: return "display"
        case .aggregate: return "square.stack.3d.up"
        case .virtual: return "app.dashed"
        case .continuity: return "iphone"
        case .other: return "mic"
        }
    }

    var isVirtual: Bool { self == .virtual }
    var isBluetooth: Bool { self == .bluetooth }
    /// Continuity Camera mics wake the iPhone connection when tapped, so they are only metered while selected.
    var isContinuity: Bool { self == .continuity }
}

/// A CoreAudio input device. `uid` is stable across reconnects; `id` is not.
struct InputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let systemName: String
    let transport: TransportKind
    /// True when the device also has output streams (a headset), not just a microphone.
    let hasOutput: Bool

    /// Using a Bluetooth headset's mic drops that headset to the low-quality hands-free profile.
    /// Input-only Bluetooth devices (wireless mic transmitters) are unaffected.
    var degradesOutputWhenUsedAsInput: Bool { transport.isBluetooth && hasOutput }
}
