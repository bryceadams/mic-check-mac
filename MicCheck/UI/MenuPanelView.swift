import SwiftUI

/// The dropdown shown from the menu bar item.
struct MenuPanelView: View {
    @Environment(MicCheckModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Divider().padding(.horizontal, 4).padding(.vertical, 2)
            if model.microphoneAccess == .denied || model.microphoneAccess == .restricted {
                permissionNotice
            }
            ForEach(model.visibleDevices) { device in
                DeviceRowView(device: device)
            }
            if model.visibleDevices.isEmpty {
                Text("No input devices").font(.system(size: 13)).foregroundStyle(.secondary).padding(10)
            }
            Divider().padding(.horizontal, 4).padding(.vertical, 2)
            lockRow
            Divider().padding(.horizontal, 4).padding(.vertical, 2)
            footer
        }
        .padding(8)
        .frame(width: 320)
        .onAppear { model.panelDidOpen() }
        .onDisappear { model.panelDidClose() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INPUT").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).kerning(0.3)
                    Text(model.currentDevice.map { model.prefs.displayName(for: $0) } ?? "No Input")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer()
                if model.isLocked {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                soundTestButton
            }
            LevelMeterView(level: model.currentLevel, height: 8)
            soundTestStatus
            if let gain = model.audio.defaultInputGain {
                HStack(spacing: 10) {
                    Image(systemName: "mic").font(.system(size: 12)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(gain) }, set: { model.audio.setGain(Float($0)) }), in: 0...1)
                        .controlSize(.small)
                    Text("\(Int((gain * 100).rounded()))%")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
    }

    @ViewBuilder private var soundTestButton: some View {
        let phase = model.soundTest.phase
        Button {
            model.toggleSoundTest()
        } label: {
            switch phase {
            case .recording: Label("Stop", systemImage: "stop.fill")
            case .playing: Label("Stop", systemImage: "stop.fill")
            default: Label("Test", systemImage: "waveform")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .controlSize(.small)
        .buttonStyle(.bordered)
        .disabled(model.currentDevice == nil)
        .help("Record a few seconds from this input and play it back")
    }

    @ViewBuilder private var soundTestStatus: some View {
        switch model.soundTest.phase {
        case .recording(let elapsed):
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text("Recording… say something")
                Spacer()
                Text(String(format: "%.0fs", Self.maxDuration - elapsed)).monospacedDigit()
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        case .playing(let elapsed, let duration):
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                Text("Playing back")
                Spacer()
                Text(String(format: "%.1f / %.1fs", elapsed, duration)).monospacedDigit()
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    private static let maxDuration = SoundTest.maxDuration

    private var permissionNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash").foregroundStyle(.secondary)
            Text("Allow microphone access in System Settings to see levels.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var lockRow: some View {
        HStack {
            Label("Lock current input", systemImage: "lock")
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(get: { model.isLocked }, set: { model.setLocked($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .help("Re-select this input if macOS or another app changes it")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuActionRow(title: "Settings…", shortcut: "⌘,") { showSettings() }
            MenuActionRow(title: "Sound Settings…", systemImage: "chevron.right") { model.openSoundSettings() }
            MenuActionRow(title: "Quit Mic Check", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
    }
}

extension MenuPanelView {
    /// A menu bar app is never the active app, so the Settings window would open behind
    /// whatever is frontmost. Activate first, then open on the next run loop turn.
    fileprivate func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true || $0.title.contains("Settings") }?.makeKeyAndOrderFront(nil)
            }
        }
    }
}

private struct MenuActionRow: View {
    let title: String
    var shortcut: String? = nil
    var systemImage: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 11)).foregroundStyle(.secondary) }
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
