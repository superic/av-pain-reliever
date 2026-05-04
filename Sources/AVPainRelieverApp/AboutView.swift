import SwiftUI

let aboutWindowID = "about-window"

/// About scene shown via the menu item and the standard ⌘? path.
/// Replaces `NSApp.orderFrontStandardAboutPanel`. Layout is deliberately
/// minimal: app icon, name, version, an update button, and the existing
/// "Show welcome again" link. The only piece of personality is a one-shot
/// confetti burst on appear — fits the plain-native aesthetic without
/// pulling in a particle library.
struct AboutView: View {
    @ObservedObject var delegate: AppDelegate
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var pulse = false
    @State private var showConfetti = true

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
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

                VStack(spacing: 4) {
                    Text(Theme.Copy.appName)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(VersionInfo.short)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Check for Updates") {
                    delegate.checkForUpdates()
                }
                .controlSize(.large)

                Button("Show welcome again") {
                    delegate.showWelcomeAgain()
                    dismissWindow(id: aboutWindowID)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 28)
            .frame(width: 360, height: 340)

            if showConfetti {
                ConfettiBurst()
                    .allowsHitTesting(false)
                    .task {
                        // Outlast the longest particle trajectory
                        // (max riseDuration + fallDuration ≈ 2.4s)
                        // so every piece arcs back down before the
                        // layer unmounts. After this, the ZStack
                        // collapses and no animations keep ticking.
                        try? await Task.sleep(for: .seconds(3.2))
                        showConfetti = false
                    }
            }
        }
        .background(.background)
        .dialogWindowChrome()
        .centeredOnScreen()
    }
}

