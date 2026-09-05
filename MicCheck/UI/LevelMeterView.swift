import SwiftUI

/// Horizontal RMS bar with a peak tick and a red clip cap. Matches the design mockup.
struct LevelMeterView: View {
    var level: AudioLevel
    var height: CGFloat = 6

    private func scaled(_ v: Float) -> CGFloat {
        // Perceptual curve: linear amplitude looks tiny; lift quiet signals so speech reads mid-bar.
        CGFloat(min(1, pow(Double(v), 0.5)))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.accentColor).frame(width: max(0, w * scaled(level.rms)))
                if level.peak > 0.01 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: min(w - 2, w * scaled(level.peak)))
                }
                if level.clipped {
                    HStack { Spacer(); UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: height / 2, topTrailingRadius: height / 2).fill(.red).frame(width: 6) }
                }
            }
            .animation(.linear(duration: 1.0 / 30.0), value: level)
        }
        .frame(height: height)
    }
}
