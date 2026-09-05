import SwiftUI

struct SettingsView: View {
    @Environment(MicCheckModel.self) private var model
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var prefs = model.prefs
        TabView {
            Form {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in model.setLaunchAtLogin(v) }
                Toggle("Show input name in menu bar", isOn: $prefs.showDeviceNameInMenuBar)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Always show live level in menu bar icon", isOn: $prefs.showLevelInMenuBar)
                        .onChange(of: prefs.showLevelInMenuBar) { _, _ in model.preferencesDidChange() }
                    Text("Keeps the microphone in use while Mic Check runs, so the orange indicator stays on. Off: the icon shows level only while the panel is open.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Toggle("Hide virtual and aggregate devices", isOn: $prefs.hideVirtualDevices)
                    .onChange(of: prefs.hideVirtualDevices) { _, _ in model.preferencesDidChange() }
                Section("Keyboard shortcuts") {
                    LabeledContent("Cycle input", value: "⌃⌥⌘M")
                    LabeledContent("Toggle input lock", value: "⌃⌥⌘L")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }

            DevicesSettingsView()
                .tabItem { Label("Devices", systemImage: "mic") }
        }
        .frame(width: 440, height: 340)
        .onAppear { launchAtLogin = model.launchesAtLogin }
    }
}

/// Rename or hide individual devices. Keyed by UID so it survives reconnects.
struct DevicesSettingsView: View {
    @Environment(MicCheckModel.self) private var model

    var body: some View {
        Form {
            ForEach(model.audio.devices) { device in
                HStack(spacing: 10) {
                    Image(systemName: device.transport.symbolName).foregroundStyle(.secondary).frame(width: 18)
                    TextField(device.systemName, text: Binding(
                        get: { model.prefs.deviceNames[device.uid] ?? "" },
                        set: { model.prefs.rename(device, to: $0) }
                    ), prompt: Text(device.systemName))
                    .textFieldStyle(.roundedBorder)
                    Toggle("Show", isOn: Binding(
                        get: { !model.prefs.isHidden(device) },
                        set: { model.prefs.setHidden(!$0, for: device); model.preferencesDidChange() }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            Text("Type a name to rename a device. Leave it blank to use the system name.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
