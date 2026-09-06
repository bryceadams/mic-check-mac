import AppKit
import AVFoundation
import CoreAudio
import Foundation
import Observation
import ServiceManagement

/// Coordinates devices, meters, lock behaviour and preferences for the UI.
@MainActor
@Observable
final class MicCheckModel {
    let audio = AudioDeviceManager()
    let prefs = Preferences()
    let soundTest = SoundTest()

    private(set) var meters: [AudioDeviceID: DeviceLevelMeter] = [:]

    /// Fixed example data used only when rendering README screenshots (see ScreenshotRenderer).
    struct Demo {
        var devices: [InputDevice]
        var currentID: AudioDeviceID
        var levels: [AudioDeviceID: AudioLevel]
        var gain: Float
        var locked: Bool
    }
    var demo: Demo?
    private(set) var panelIsOpen = false
    private(set) var microphoneAccess: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    private var menuBarMeter: DeviceLevelMeter?

    init() {
        DebugLog.write("Mic Check launched; mic access=\(self.microphoneAccess.rawValue) devices=\(self.audio.devices.count)")
        audio.onDefaultInputChanged = { [weak self] _ in self?.enforceLockIfNeeded() }
        syncMenuBarMeter()
    }

    // MARK: Devices

    /// Devices shown in the panel, after the virtual filter and per-device hides.
    var visibleDevices: [InputDevice] {
        if let demo { return demo.devices }
        return audio.devices.filter { device in
            if prefs.hideVirtualDevices && (device.transport.isVirtual || device.transport == .aggregate) { return false }
            // iPhone (Continuity Camera) mics appear whenever a phone is nearby and wake it when tapped; never list them
            // unless one is already the current input.
            if device.transport.isContinuity && !isCurrent(device) { return false }
            if prefs.isHidden(device) { return false }
            return true
        }
    }

    var currentDevice: InputDevice? {
        if let demo { return demo.devices.first { $0.id == demo.currentID } }
        return audio.defaultInput
    }

    func isCurrent(_ device: InputDevice) -> Bool { device.id == (demo?.currentID ?? audio.defaultInputID) }

    /// Input gain shown in the header, 0...1, or nil when the device has no software gain control.
    var currentGain: Float? { demo?.gain ?? audio.defaultInputGain }

    func select(_ device: InputDevice) {
        guard audio.setDefaultInput(device.id) else { return }
        if prefs.lockInput { prefs.lockedDeviceUID = device.uid }
        audio.refreshDefaultInput()
        syncMenuBarMeter()
    }

    // MARK: Lock

    var isLocked: Bool { demo?.locked ?? prefs.lockInput }

    func setLocked(_ locked: Bool) {
        prefs.lockInput = locked
        prefs.lockedDeviceUID = locked ? currentDevice?.uid : nil
    }

    private func enforceLockIfNeeded() {
        guard prefs.lockInput, let uid = prefs.lockedDeviceUID else { syncMenuBarMeter(); return }
        if let target = audio.devices.first(where: { $0.uid == uid }), audio.defaultInputID != target.id {
            audio.setDefaultInput(target.id)
            audio.refreshDefaultInput()
        }
        syncMenuBarMeter()
    }

    // MARK: Metering

    func panelDidOpen() {
        panelIsOpen = true
        audio.refreshDevices()
        audio.refreshDefaultInput()
        requestMicrophoneAccessIfNeeded { [weak self] in self?.syncMeters() }
    }

    func panelDidClose() {
        panelIsOpen = false
        soundTest.cancel()
        syncMeters()
    }

    private var pressStartedRecording = false

    /// Mouse down on the Test button. Starts a hold recording when idle; otherwise waits for release.
    func soundTestPressed() {
        pressStartedRecording = false
        guard let id = audio.defaultInputID else { return }
        switch soundTest.phase {
        case .idle, .failed:
            pressStartedRecording = true
            requestMicrophoneAccessIfNeeded { [weak self] in
                self?.soundTest.startRecording(deviceID: id, maxDuration: SoundTest.holdMaxDuration, hold: true)
            }
        default:
            break
        }
    }

    /// Mouse up on the Test button. A short press is a tap (5s clip); a long press ends the hold recording.
    func soundTestReleased(heldFor held: TimeInterval) {
        defer { pressStartedRecording = false }
        if pressStartedRecording {
            if held < 0.4 { soundTest.limit(to: SoundTest.tapDuration) } else { soundTest.finishAndPlay() }
            return
        }
        switch soundTest.phase {
        case .recording: soundTest.finishAndPlay()
        case .playing: soundTest.stopPlayback()
        default: break
        }
    }

    func meter(for device: InputDevice) -> DeviceLevelMeter? {
        if let demo { return DeviceLevelMeter(deviceID: device.id, fixedLevel: demo.levels[device.id] ?? .silent) }
        return meters[device.id] ?? (menuBarMeter?.deviceID == device.id ? menuBarMeter : nil)
    }

    var currentLevel: AudioLevel {
        if let demo { return demo.levels[demo.currentID] ?? .silent }
        if case .recording = soundTest.phase { return soundTest.level }
        guard let id = audio.defaultInputID else { return .silent }
        return meters[id]?.level ?? menuBarMeter?.level ?? .silent
    }

    private func syncMeters() {
        guard microphoneAccess == .authorized else { return }
        // Meter every visible device while open, except Continuity (iPhone) mics unless they are the current input:
        // opening a tap on one wakes the phone's connection.
        let wanted: Set<AudioDeviceID> = panelIsOpen
            ? Set(visibleDevices.filter { !$0.transport.isContinuity || isCurrent($0) }.map(\.id))
            : []
        for (id, meter) in meters where !wanted.contains(id) {
            meter.stop()
            meters.removeValue(forKey: id)
        }
        for id in wanted where meters[id] == nil {
            let meter = DeviceLevelMeter(deviceID: id)
            meter.start()
            meters[id] = meter
        }
        syncMenuBarMeter()
    }

    /// The menu bar icon meter follows the default input whenever that option is on.
    private func syncMenuBarMeter() {
        guard microphoneAccess == .authorized else { return }
        let wantedID: AudioDeviceID? = prefs.showLevelInMenuBar ? audio.defaultInputID : nil
        if menuBarMeter?.deviceID != wantedID {
            menuBarMeter?.stop()
            menuBarMeter = nil
            if let wantedID {
                let m = DeviceLevelMeter(deviceID: wantedID)
                m.start()
                menuBarMeter = m
            }
        }
    }

    func preferencesDidChange() {
        syncMeters()
    }

    private func requestMicrophoneAccessIfNeeded(then completion: @escaping @MainActor () -> Void) {
        microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
        switch microphoneAccess {
        case .authorized:
            completion()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    self.microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
                    completion()
                }
            }
        default:
            break
        }
    }

    // MARK: Launch at login

    var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login change failed: \(error)")
        }
    }

    func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input") {
            NSWorkspace.shared.open(url)
        }
    }
}
