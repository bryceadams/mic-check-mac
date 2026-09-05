import CoreAudio
import Foundation

/// Thin typed wrappers over AudioObjectGetPropertyData / SetPropertyData.
enum CoreAudioHelpers {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func hasProperty(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
        var a = addr
        return AudioObjectHasProperty(object, &a)
    }

    static func get<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, default value: T) -> T? {
        var a = addr
        var size = UInt32(MemoryLayout<T>.size)
        var result = value
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
        return status == noErr ? result : nil
    }

    static func getString(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> String? {
        var a = addr
        var size = UInt32(MemoryLayout<CFString?>.size)
        var result: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(object, &a, 0, nil, &size, &result)
        guard status == noErr, let cf = result?.takeRetainedValue() else { return nil }
        return cf as String
    }

    static func getArray<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, of: T.Type) -> [T] {
        var a = addr
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.size
        var buffer = [T](unsafeUninitializedCapacity: count) { _, initialized in initialized = count }
        let status = buffer.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? buffer : []
    }

    @discardableResult
    static func set<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, value: T) -> Bool {
        var a = addr
        var v = value
        return withUnsafePointer(to: &v) { AudioObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0) } == noErr
    }
}
