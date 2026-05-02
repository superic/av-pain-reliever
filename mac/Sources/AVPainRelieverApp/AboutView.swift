import SwiftUI

let aboutWindowID = "about-window"

/// About scene shown via the menu item and the standard ⌘? path.
/// Replaces `NSApp.orderFrontStandardAboutPanel` so the brand can sit
/// on the hero — pill icon in magenta, app name in big magenta type,
/// cyan tagline, version + a single warm "made to stop the fiddling"
/// line. Personality lives in the copy, not the chrome.
struct AboutView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: Theme.Symbol.appIcon)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.Color.primary)
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(pulse ? 1.04 : 1.0)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }

            VStack(spacing: 6) {
                Text(Theme.Copy.appName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.primary)
                Text(Theme.Copy.tagline)
                    .font(.callout)
                    .foregroundStyle(Theme.Color.highlight)
            }

            VStack(spacing: 4) {
                Text("Version \(versionString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Made to stop the fiddling.")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("Lives quietly in your menu bar.")
                Text("Watches your USB ports. Picks the right defaults.")
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 28)
        .frame(width: 360, height: 420)
        .background(.background)
    }

    private var versionString: String {
        // SPM-built binaries don't carry an Info.plist; fall back to a
        // sensible string so the About reads well during development.
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?): return "\(s) (\(b))"
        case let (s?, nil): return s
        default: return "dev build"
        }
    }
}
