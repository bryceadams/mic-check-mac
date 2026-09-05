import SwiftUI

@main
struct MicCheckApp: App {
    @State private var model = MicCheckModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }

}

private struct MenuBarLabel: View {
    @Environment(MicCheckModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(level: model.currentLevel, locked: model.isLocked, showLevel: model.prefs.showLevelInMenuBar || model.panelIsOpen))
            if model.prefs.showDeviceNameInMenuBar, let d = model.currentDevice {
                Text(model.prefs.displayName(for: d)).font(.system(size: 12))
            }
        }
    }
}
