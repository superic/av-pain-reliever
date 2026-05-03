import SwiftUI

let aboutWindowID = "about-window"

/// About scene shown via the menu item and the standard ⌘? path.
/// Replaces `NSApp.orderFrontStandardAboutPanel` so the brand can sit
/// on the hero — pill icon in magenta, app name in big magenta type,
/// cyan tagline, version + a single warm "made to stop the fiddling"
/// line. Personality lives in the copy, not the chrome.
struct AboutView: View {
    @ObservedObject var delegate: AppDelegate
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            // Generated app icon — same artwork the OS uses.
            // SwiftUI's Image(nsImage:) downscales cleanly from the
            // 1024-square master.
            Image(nsImage: AppIcon.image)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .scaleEffect(pulse ? 1.03 : 1.0)
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }

            VStack(spacing: 6) {
                Text(Theme.Copy.appName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(Theme.Copy.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text(VersionInfo.short)
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

            Button("Show welcome again") {
                delegate.showWelcomeAgain()
                dismissWindow(id: aboutWindowID)
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 28)
        .frame(width: 360, height: 460)
        .background(.background)
        .dialogWindowChrome()
    }
}
