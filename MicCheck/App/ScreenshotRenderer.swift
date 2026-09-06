import AppKit
import CoreAudio
import SwiftUI

/// Renders the menu panel with example data to PNG files for the README.
/// Invoked with `--render-screenshots <output directory>`; the app exits afterwards.
@MainActor
enum ScreenshotRenderer {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-menubar-icon"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            renderMenuBarIcons(to: dir)
            exit(0)
        }
        guard let i = args.firstIndex(of: "--render-screenshots"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        render(to: dir)
        exit(0)
    }

    /// Exports the menu bar glyph in several states, as black and white PNGs at 1x/2x/4x and a large size.
    private static func renderMenuBarIcons(to dir: URL) {
        let states: [(String, AudioLevel, Bool)] = [
            ("idle", .silent, false),
            ("level", AudioLevel(rms: 0.3, peak: 0.5, clipped: false), false),
            ("clipping", AudioLevel(rms: 1, peak: 1, clipped: true), false),
            ("locked", .silent, true),
        ]
        for (name, level, locked) in states {
            let template = MenuBarIcon.image(level: level, locked: locked, showLevel: true)
            for (suffix, pixels) in [("@1x", 18), ("@2x", 36), ("@4x", 72), ("-512", 512)] {
                for (tone, color) in [("black", NSColor.black), ("white", NSColor.white)] {
                    let tinted = NSImage(size: NSSize(width: pixels, height: pixels), flipped: false) { rect in
                        template.draw(in: rect)
                        color.set()
                        rect.fill(using: .sourceIn) // recolor the template's alpha
                        return true
                    }
                    guard let tiff = tinted.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { continue }
                    try? png.write(to: dir.appendingPathComponent("menubar-\(name)-\(tone)\(suffix).png"))
                }
            }
        }
        print("wrote menu bar icons to \(dir.path)")
    }

    private static func render(to dir: URL) {
        let devices = [
            InputDevice(id: 1, uid: "demo-usb", systemName: "Wireless Mic Rx", transport: .usb, hasOutput: false),
            InputDevice(id: 2, uid: "demo-display", systemName: "Studio Display Microphone", transport: .display, hasOutput: true),
            InputDevice(id: 3, uid: "demo-builtin", systemName: "MacBook Pro Microphone", transport: .builtIn, hasOutput: false),
            InputDevice(id: 4, uid: "demo-bt", systemName: "AirPods Pro", transport: .bluetooth, hasOutput: true),
        ]
        let model = MicCheckModel()
        model.prefs.rename(devices[0], to: "Lapel Mic")
        model.demo = .init(
            devices: devices,
            currentID: 1,
            levels: [
                1: AudioLevel(rms: 0.30, peak: 0.55, clipped: false),
                2: AudioLevel(rms: 0.05, peak: 0.12, clipped: false),
                3: AudioLevel(rms: 0.07, peak: 0.15, clipped: false),
                4: AudioLevel(rms: 0.00, peak: 0.00, clipped: false),
            ],
            gain: 0.7,
            locked: true
        )

        for scheme in [ColorScheme.light, .dark] {
            let panelColor = scheme == .dark ? Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1)) : Color(nsColor: NSColor(calibratedWhite: 0.95, alpha: 1))
            let view = MenuPanelView()
                .environment(model)
                .background(panelColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.25), radius: 18, y: 10)
                .padding(40)
                .environment(\.colorScheme, scheme)
                .tint(scheme == .dark ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color(red: 0, green: 0.48, blue: 1.0))

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            renderer.isOpaque = false
            guard let cg = renderer.cgImage else { print("render failed for \(scheme)"); continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let name = scheme == .dark ? "panel-dark.png" : "panel-light.png"
            try? png.write(to: dir.appendingPathComponent(name))
            print("wrote \(name) \(cg.width)x\(cg.height)")
        }
    }
}
