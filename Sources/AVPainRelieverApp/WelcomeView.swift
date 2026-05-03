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
        VStack(spacing: 24) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)

            VStack(spacing: 8) {
                Text("Welcome to \(Theme.Copy.appName)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(Theme.Copy.tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                bullet(symbol: "cable.connector",
                       text: "Plug in your dock, microphone, or webcam.")
                bullet(symbol: "wand.and.stars",
                       text: "AV Pain Reliever notices and switches your audio + camera defaults — automatically.")
                bullet(symbol: "sparkles",
                       text: "No tinkering with System Settings before every meeting.")
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onAddProfile) {
                    Text("Add Your First Location")
                        .frame(minWidth: 220)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Skip — I'll set up later", action: onSkip)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 28)
        .frame(width: 480, height: 540)
        .background(.background)
        .dialogWindowChrome()
    }

    /// Three bullet rows below the tagline. Each pairs an SF Symbol
    /// with one short sentence — easier to scan than a single dense
    /// paragraph and gives the user a sense of the product shape on
    /// first read.
    private func bullet(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
