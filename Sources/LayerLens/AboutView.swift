import AppKit
import SwiftUI

/// Static metadata for the About window. Single source of truth so the
/// version string doesn't drift between this view and other places that
/// need it.
enum LayerLensInfo {
  static let appName = "LayerLens"
  /// Version is read from the app bundle's Info.plist so it stays in sync
  /// with whatever `Tools/build_app.sh <version>` baked into the .app at
  /// release time. Falls back to "dev" for unbundled debug runs (e.g.
  /// `swift run LayerLens`), where there is no Info.plist to read from.
  static let version: String = {
    let info = Bundle.main.infoDictionary
    if let v = info?["CFBundleShortVersionString"] as? String, !v.isEmpty {
      return v
    }
    if let v = info?["CFBundleVersion"] as? String, !v.isEmpty {
      return v
    }
    return "dev"
  }()
  static let tagline = "A floating overlay that mirrors your QMK/VIA keyboard's active layer."
  static let license = "GPL-3.0"
  static let repoURL = URL(string: "https://github.com/fireball1725/LayerLens")!
  static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
  static let inspiredBy = "Inspired by keypeek by srwi."
  static let copyright = "© 2026 FireBall1725 (Adaléa). Released under GPL-3.0."
}

/// About window, invoked from the menu bar's "About LayerLens" item. Plain
/// non-resizable card; the surrounding scene supplies window chrome.
struct AboutView: View {
  @Environment(Preferences.self) private var preferences

  /// Hidden trigger: tap the version label `tapsToUnlock` times within
  /// `tapWindow` seconds to unlock the Dev tab. The counter resets if
  /// taps pause for too long so casual double-clicks don't accumulate.
  @State private var unlockTapCount: Int = 0
  @State private var lastTapAt: Date? = nil
  @State private var justUnlocked: Bool = false

  private static let tapsToUnlock = 5
  private static let tapWindow: TimeInterval = 2.0

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "keyboard")
        .resizable()
        .scaledToFit()
        .frame(width: 96, height: 96)
        .foregroundStyle(.tint)
        .padding(.top, 24)

      VStack(spacing: 4) {
        Text(LayerLensInfo.appName)
          .font(.largeTitle.weight(.semibold))
        Text("Version \(LayerLensInfo.version)")
          .font(.callout)
          .foregroundStyle(.secondary)
          .contentShape(Rectangle())
          .onTapGesture { registerUnlockTap() }
        if justUnlocked || preferences.devToolsEnabled {
          Text("Dev tools unlocked")
            .font(.caption2)
            .foregroundStyle(.tint)
            .transition(.opacity)
        }
      }

      Text(LayerLensInfo.tagline)
        .font(.callout)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        Button("GitHub") { NSWorkspace.shared.open(LayerLensInfo.repoURL) }
        Button("License") { NSWorkspace.shared.open(LayerLensInfo.licenseURL) }
      }
      .padding(.top, 4)

      Divider().padding(.horizontal, 40)

      VStack(spacing: 4) {
        Text(LayerLensInfo.inspiredBy)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Built with QMK and the VIA protocol.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(LayerLensInfo.copyright)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      }
      .multilineTextAlignment(.center)
      .padding(.bottom, 18)
    }
    .padding(.horizontal, 28)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func registerUnlockTap() {
    let now = Date()
    if let last = lastTapAt, now.timeIntervalSince(last) > Self.tapWindow {
      unlockTapCount = 0
    }
    lastTapAt = now
    unlockTapCount += 1

    guard unlockTapCount >= Self.tapsToUnlock else { return }
    unlockTapCount = 0
    lastTapAt = nil
    guard !preferences.devToolsEnabled else { return }
    withAnimation { preferences.devToolsEnabled = true }
    withAnimation { justUnlocked = true }
  }
}
