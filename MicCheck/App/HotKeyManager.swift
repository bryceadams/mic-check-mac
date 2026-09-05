import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon's RegisterEventHotKey. Defaults: ⌃⌥⌘M cycles input, ⌃⌥⌘L toggles lock.
@MainActor
final class HotKeyManager {
    enum Action: UInt32 { case cycleInput = 1, toggleLock = 2 }

    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private let onAction: (Action) -> Void

    init(onAction: @escaping (Action) -> Void) {
        self.onAction = onAction
        install()
    }

    private func install() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: hotKeyID.id) {
                Task { @MainActor in manager.onAction(action) }
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let mods = UInt32(controlKey | optionKey | cmdKey)
        register(keyCode: UInt32(kVK_ANSI_M), modifiers: mods, action: .cycleInput)
        register(keyCode: UInt32(kVK_ANSI_L), modifiers: mods, action: .toggleLock)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, action: Action) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4D43_4B21), id: action.rawValue) // "MCK!"
        if RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
        }
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
