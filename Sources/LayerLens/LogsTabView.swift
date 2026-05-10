import SwiftUI
import AppKit
import LayerLensCore

/// Settings → Logs. Live-tails `~/Library/Logs/LayerLens/LayerLens.log`,
/// auto-scrolls to the bottom, and exposes file actions alongside the level
/// filter and an auto-scroll toggle.
///
/// Layout: top toolbar (level picker left, file actions right), main scroll
/// view, bottom status bar (auto-scroll toggle left, file path right). The
/// split keeps view-shaping controls (level filter, auto-scroll) visually
/// distinct from destructive/file actions, which the previous single-row
/// layout muddled.
struct LogsTabView: View {
    @Environment(Preferences.self) private var preferences

    @State private var contents: String = ""
    @State private var autoScroll: Bool = true
    @State private var refreshTimer: Timer?

    var body: some View {
        @Bindable var preferences = preferences
        return VStack(spacing: 0) {
            toolbar(preferences: preferences)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            logScrollView

            Divider()

            statusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private func toolbar(preferences: Preferences) -> some View {
        @Bindable var preferences = preferences
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Level")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Picker("Log level", selection: $preferences.logLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.label.capitalized).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)
                .help("Filter what gets written to the log file. Debug includes raw protocol traffic; Info is the default.")
            }
            .fixedSize()

            Spacer()

            Button("Show in Finder") {
                LogService.revealLogInFinder()
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(contents, forType: .string)
            }
            .disabled(contents.isEmpty)
            Button(role: .destructive) {
                LogService.clearLog()
                contents = ""
            } label: {
                Text("Clear")
            }
        }
    }

    // MARK: - Log scroll view

    private var logScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(contents.isEmpty ? "(no log output yet)" : contents)
                    .font(.callout.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)

                // Empty trailing view so the scroll-to anchor is at the
                // very end of the content.
                Color.clear.frame(height: 1).id("log-bottom-anchor")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: contents) { _, _ in
                guard autoScroll else { return }
                withAnimation(.linear(duration: 0.05)) {
                    proxy.scrollTo("log-bottom-anchor", anchor: .bottom)
                }
            }
            .onAppear {
                refresh()
                proxy.scrollTo("log-bottom-anchor", anchor: .bottom)
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            Spacer()

            Text(LogService.logFileURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .truncationMode(.middle)
                .lineLimit(1)
                .help(LogService.logFileURL.path)
        }
    }

    private func refresh() {
        let next = LogService.tail()
        if next != contents {
            contents = next
        }
    }

    private func startTimer() {
        stopTimer()
        // 1s cadence: a reasonable balance between feeling live and not
        // burning IO on a quiet log. Layer-change events fire bursts so the
        // user sees them within a second of pressing the key.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
