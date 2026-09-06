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
                Text(model.currentDevice.map { model.prefs.displayName(for: $0) } ?? "No Input")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
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
            if let gain = model.currentGain {
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

    private var soundTestButton: some View {
        SoundTestButton()
    }

    @ViewBuilder private var soundTestStatus: some View {
        switch model.soundTest.phase {
        case .recording(let elapsed):
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text(model.soundTest.isHoldRecording ? "Recording… release to play back" : "Recording… say something")
                Spacer()
                Text(model.soundTest.isHoldRecording
                     ? String(format: "%.0fs", elapsed)
                     : String(format: "%.0fs", max(0, model.soundTest.maxDuration - elapsed))).monospacedDigit()
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
        case .starting, .idle:
            EmptyView()
        }
    }

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
            if model.demo != nil {
                // ImageRenderer cannot draw the AppKit-backed switch; draw a static one for screenshots.
                Capsule().fill(Color.accentColor).frame(width: 26, height: 15)
                    .overlay(alignment: .trailing) { Circle().fill(.white).frame(width: 12, height: 12).padding(1.5).shadow(radius: 0.5, y: 0.5) }
            } else {
                Toggle("", isOn: Binding(get: { model.isLocked }, set: { model.setLocked($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
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

/// Bordered button that distinguishes tap from press-and-hold. Tap: 5s clip. Hold: record until release.
private struct SoundTestButton: View {
    @Environment(MicCheckModel.self) private var model
    @State private var pressStart: Date?

    var body: some View {
        let phase = model.soundTest.phase
        let pressing = pressStart != nil
        Group {
            switch phase {
            case .starting: Label("Starting", systemImage: "waveform")
            case .recording, .playing: Label("Stop", systemImage: "stop.fill")
            default: Label("Test", systemImage: "waveform")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.primary.opacity(pressing ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .opacity(model.currentDevice == nil ? 0.4 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard pressStart == nil, model.currentDevice != nil else { return }
                    pressStart = Date()
                    model.soundTestPressed()
                }
                .onEnded { _ in
                    guard let start = pressStart else { return }
                    pressStart = nil
                    model.soundTestReleased(heldFor: Date().timeIntervalSince(start))
                }
        )
        .help("Click to record 5 seconds, or hold to record up to a minute. Plays back when done.")
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
