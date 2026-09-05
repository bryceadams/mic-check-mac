import SwiftUI

@main
struct MicCheckApp: App {
    @State private var model = MicCheckModel()
    @State private var hotKeys: HotKeyManager?

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environment(model)
                .onAppear { installHotKeysIfNeeded() }
        } label: {
            MenuBarLabel()
                .environment(model)
                .task { installHotKeysIfNeeded() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }

    private func installHotKeysIfNeeded() {
        guard hotKeys == nil else { return }
        hotKeys = HotKeyManager { action in
            switch action {
            case .cycleInput: model.cycleToNextDevice()
            case .toggleLock: model.toggleLock()
            }
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
