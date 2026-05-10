import AppKit
import Foundation
import Sparkle

/// Owns the Sparkle updater. Wires up the appcast URL, hooks into the user
/// driver for the "skip / remind / install" UI, and lets the menu bar trigger
/// a manual check.
@MainActor
final class UpdateController: NSObject {
    /// Appcast XML location. Committed to the repo's main branch by the
    /// release workflow; branch-pinned so updates only flip when a release
    /// explicitly publishes a new appcast.
    nonisolated static let publicAppcastURL = URL(
        string: "https://raw.githubusercontent.com/FireBall1725/LayerLens/main/appcast.xml"
    )!

    private var updaterController: SPUStandardUpdaterController!

    var updater: SPUUpdater { updaterController.updater }

    override init() {
        super.init()
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Triggered by the menu bar's "Check for Updates…" item. Forces a
    /// foreground check (vs. the silent scheduled checks Sparkle runs once
    /// a day).
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateController.publicAppcastURL.absoluteString
    }
}
