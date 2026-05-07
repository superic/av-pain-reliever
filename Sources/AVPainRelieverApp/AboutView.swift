import SwiftUI

let aboutWindowID = "about-window"

/// About scene shown via the menu item and the standard ⌘? path.
/// Replaces `NSApp.orderFrontStandardAboutPanel`. Layout: app icon
/// (with a slow scale-pulse), the name, the version, a small
/// fortune-paper slip with a randomly-selected oracular pronouncement
/// from `HoroscopeOracle`, the update button, the "Show welcome
/// again" link, and a copyright/source footer. A one-shot confetti
/// burst fires on appear.
///
/// The fortune slip is intentionally off-spec for native macOS chrome
/// — physical-paper skeuomorphism doesn't normally appear in Apple's
/// design language. About dialogs are the most personality-tolerant
/// surface in any Mac app though (Apple's own About panels carry the
/// scrolling Mac-team credits Easter egg), so a small playful element
/// here doesn't undermine the otherwise plain-native chrome of the
/// rest of the app.
struct AboutView: View {
    @ObservedObject var delegate: AppDelegate
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var pulse = false
    @State private var showConfetti = true
    /// Selected once when the view's @State is initialized so the
    /// slip stays stable while the user is reading it. Closing and
    /// re-opening the About window mints a fresh AboutView (new
    /// @State), which picks a new horoscope.
    @State private var horoscope: String = HoroscopeOracle.random()

    var body: some View {
        ZStack {
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

                VStack(spacing: 4) {
                    Text(Theme.Copy.appName)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(VersionInfo.short)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                fortuneSlip

                Button("Check for Updates") {
                    delegate.checkForUpdates()
                }
                .controlSize(.large)
                // Extra top padding so the action group breathes
                // away from the fortune slip — without it the
                // sequence (slip → button → link) reads as squished.
                .padding(.top, 14)

                Button("Show welcome again") {
                    delegate.showWelcomeAgain()
                    dismissWindow(id: aboutWindowID)
                }
                .buttonStyle(.link)
                .font(.caption)

                Spacer(minLength: 0)

                copyrightFooter
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 28)
            .frame(width: 360, height: 460)

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

    /// A small "paper fortune" slip rendering today's horoscope.
    /// Italic serif text is the visual cue that turns "rounded box
    /// with a sentence" into "printed fortune from a cookie." Stays
    /// light-cream in both light and dark mode — real paper doesn't
    /// invert when you turn off the lights, and the slip is small
    /// enough that it doesn't visually overwhelm a dark dialog.
    private var fortuneSlip: some View {
        Text(horoscope)
            .font(.system(.body, design: .serif).italic())
            // Hardcoded dark "ink" color (not `.primary`) so the
            // text on the cream slip stays readable in dark mode
            // — `.primary` would flip to white and disappear.
            .foregroundStyle(Color(red: 30 / 255, green: 25 / 255, blue: 20 / 255))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    // Warm off-white ≈ #FDFCF5 — barely-cream, reads
                    // as "real paper" without being aggressive.
                    .fill(Color(red: 253 / 255, green: 252 / 255, blue: 245 / 255))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            )
            // Subtle tilt — casually-placed, not deliberately-displayed.
            // Bigger angles read as cartoonish.
            .rotationEffect(.degrees(-1.5))
    }

    /// Copyright + source link at the very bottom. Smallest text in
    /// the dialog so it lives quietly without competing with the
    /// horoscope or the update button.
    private var copyrightFooter: some View {
        HStack(spacing: 4) {
            Text("© 2026 Eric Willis ·")
            Link("Source on GitHub", destination: URL(string: "https://github.com/superic/av-pain-reliever")!)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
