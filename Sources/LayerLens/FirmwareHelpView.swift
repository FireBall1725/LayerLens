import SwiftUI

/// "How do I get live layer events?" explainer window. Opened from
/// onboarding's connect step and from the Configure window's "Live no"
/// button.
///
/// Deliberately brief: install snippets, wire format, and the rest of
/// the firmware story live in the LayerLens repo. Keeping the in-app
/// dialog short means we don't have to keep three places (this view,
/// `firmware/layerlens_notify/README.md`, and `PROTOCOL.md`) in sync
/// every time the wiring changes.
struct FirmwareHelpView: View {
    private static let moduleSourceURL = URL(
        string: "https://github.com/FireBall1725/LayerLens/tree/main/firmware/layerlens_notify"
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Text("The floating overlay only flashes when your keyboard runs the `layerlens_notify` QMK module. The module exposes the active-layer bitmask to LayerLens over Raw HID so the overlay can mirror what's happening on the board in real time.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Text("The keymap viewer, custom labels, and lighting controls all work without it. Only the live layer overlay needs the module.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Link(destination: Self.moduleSourceURL) {
                    Label("Open install instructions on GitHub", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(minWidth: 460, idealWidth: 460, minHeight: 280, idealHeight: 280)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.badge.clock")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Live layer events")
                    .font(.title2.weight(.semibold))
                Text("A small QMK module makes the overlay flash whenever you change layers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
