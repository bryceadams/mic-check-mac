import AppKit
import Combine
import Foundation
import Observation
import Sparkle

/// Wraps Sparkle's standard updater for SwiftUI. The appcast URL and public key live in Info.plist.
@MainActor
@Observable
final class UpdateController {
    private let controller: SPUStandardUpdaterController
    private(set) var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    /// User-initiated check. Activates the app first so Sparkle's window comes to the front.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
