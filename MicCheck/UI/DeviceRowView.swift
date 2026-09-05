import SwiftUI

struct DeviceRowView: View {
    @Environment(MicCheckModel.self) private var model
    let device: InputDevice
    @State private var hovering = false

    var body: some View {
        let current = model.isCurrent(device)
        let meter = model.meter(for: device)
        Button {
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
                    Text(model.prefs.displayName(for: device))
                        .font(.system(size: 13, weight: current ? .semibold : .regular))
                        .lineLimit(1)
                    if device.transport.isBluetooth {
                        Text("Bluetooth input lowers output quality")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if device.transport.isContinuity && !current {
                        Text("Level shown when selected")
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
            .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(device.transport.isBluetooth && !current ? 0.75 : 1)
    }
}
