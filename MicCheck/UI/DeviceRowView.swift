import SwiftUI

struct DeviceRowView: View {
    @Environment(MicCheckModel.self) private var model
    let device: InputDevice
    @State private var hovering = false
    @State private var renaming = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        let current = model.isCurrent(device)
        let meter = model.meter(for: device)
        Button {
            guard !renaming else { return }
            model.select(device)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14)
                    .opacity(current ? 1 : 0)
                Image(systemName: device.transport.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    if renaming {
                        TextField(device.systemName, text: $draftName, prompt: Text(device.systemName))
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($nameFieldFocused)
                            .onSubmit { commitRename() }
                            .onExitCommand { renaming = false }
                            .onChange(of: nameFieldFocused) { _, focused in if !focused && renaming { commitRename() } }
                    } else {
                        Text(model.prefs.displayName(for: device))
                            .font(.system(size: 13, weight: current ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    if device.transport.isBluetooth {
                        Text("Lowers output quality")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                LevelMeterView(level: meter?.level ?? .silent, height: 4)
                    .frame(width: 64)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(hovering || renaming ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(device.transport.isBluetooth && !current ? 0.75 : 1)
        .contextMenu {
            Button("Rename…") { beginRename() }
            if model.prefs.deviceNames[device.uid] != nil {
                Button("Use System Name") { model.prefs.rename(device, to: "") }
            }
            Divider()
            Button("Hide from List") {
                model.prefs.setHidden(true, for: device)
                model.preferencesDidChange()
            }
            .disabled(current)
        }
    }

    private func beginRename() {
        draftName = model.prefs.deviceNames[device.uid] ?? ""
        renaming = true
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func commitRename() {
        guard renaming else { return }
        model.prefs.rename(device, to: draftName)
        renaming = false
    }
}
