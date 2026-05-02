import SwiftUI
import AppKit

let welcomeWindowID = "welcome-window"

/// One-time first-run welcome shown when the user has no profiles set
/// up. Frames AV Pain Reliever in plain language and routes the user
/// into the wizard. Suppressed forever after the user either dismisses
/// it or saves a first profile (whichever comes first).
struct WelcomeView: View {
    let onAddProfile: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: Theme.Symbol.appIcon)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Theme.Color.primary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Welcome to \(Theme.Copy.appName)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.primary)
                    .multilineTextAlignment(.center)
                Text(Theme.Copy.tagline)
                    .font(.title3)
                    .foregroundStyle(Theme.Color.highlight)
                    .multilineTextAlignment(.center)
            }

            Text("Plug in different combos of USB devices and AV Pain Reliever picks the right audio + camera defaults — automatically. No tinkering with system settings before every meeting.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button(action: onAddProfile) {
                    Text("Add Your First Location")
                        .frame(minWidth: 220)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Color.primary)
                .controlSize(.large)

                Button("Skip — I'll set up later", action: onSkip)
                    .buttonStyle(.link)
                    .foregroundStyle(Theme.Color.highlight)
            }
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 32)
        .frame(width: 460, height: 520)
        .background(.background)
    }
}
