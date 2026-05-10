import SwiftUI
import AppKit

/// Static metadata for the About window. Single source of truth so the
/// version string doesn't drift between this view and other places that
/// need it.
enum LayerLensInfo {
    static let appName    = "LayerLens"
    static let version    = "0.3.0"
    static let tagline    = "A floating overlay that mirrors your QMK/VIA keyboard's active layer."
    static let license    = "GPL-3.0"
    static let repoURL    = URL(string: "https://github.com/fireball1725/LayerLens")!
    static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    static let inspiredBy = "Inspired by keypeek by srwi."
    static let copyright  = "© 2026 FireBall1725 (Adaléa). Released under GPL-3.0."
}

/// About window, invoked from the menu bar's "About LayerLens" item. Plain
/// non-resizable card; the surrounding scene supplies window chrome.
struct AboutView: View {
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
}
