import AppKit
import AVFoundation
import CoreAudio
import Foundation
import Observation
import ServiceManagement
import os

private let log = Logger(subsystem: "dev.bryceadams.MicCheck", category: "model")

/// Coordinates devices, meters, lock behaviour and preferences for the UI.
@MainActor
@Observable
final class MicCheckModel {
    let audio = AudioDeviceManager()
    let prefs = Preferences()
    let soundTest = SoundTest()

    private(set) var meters: [AudioDeviceID: DeviceLevelMeter] = [:]
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
        audio.devices.filter { device in
            if prefs.hideVirtualDevices && (device.transport.isVirtual || device.transport == .aggregate) { return false }
            if prefs.isHidden(device) { return false }
            return true
        }
    }

    var currentDevice: InputDevice? { audio.defaultInput }

    func isCurrent(_ device: InputDevice) -> Bool { device.id == audio.defaultInputID }

    func select(_ device: InputDevice) {
        guard audio.setDefaultInput(device.id) else { return }
        if prefs.lockInput { prefs.lockedDeviceUID = device.uid }
        audio.refreshDefaultInput()
        syncMenuBarMeter()
    }

    func cycleToNextDevice() {
        let list = visibleDevices
        guard !list.isEmpty else { return }
        let idx = list.firstIndex { isCurrent($0) } ?? -1
        select(list[(idx + 1) % list.count])
    }

    // MARK: Lock

    var isLocked: Bool { prefs.lockInput }

    func setLocked(_ locked: Bool) {
        prefs.lockInput = locked
        prefs.lockedDeviceUID = locked ? currentDevice?.uid : nil
    }

    func toggleLock() { setLocked(!isLocked) }

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

    func toggleSoundTest() {
        guard let id = audio.defaultInputID else { return }
        requestMicrophoneAccessIfNeeded { [weak self] in self?.soundTest.toggle(deviceID: id) }
    }

    func meter(for device: InputDevice) -> DeviceLevelMeter? {
        meters[device.id] ?? (menuBarMeter?.deviceID == device.id ? menuBarMeter : nil)
    }

    var currentLevel: AudioLevel {
        if case .recording = soundTest.phase { return soundTest.level }
        guard let id = audio.defaultInputID else { return .silent }
        return meters[id]?.level ?? menuBarMeter?.level ?? .silent
    }

    private func syncMeters() {
        DebugLog.write("syncMeters: access=\(self.microphoneAccess.rawValue) panelOpen=\(self.panelIsOpen) visible=\(self.visibleDevices.map { "\($0.systemName)#\($0.id)" }.joined(separator: ", ")) default=\(self.audio.defaultInputID ?? 0)")
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
