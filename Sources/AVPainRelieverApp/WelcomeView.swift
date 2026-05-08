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
    @State private var showConfetti = true

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)

            VStack(spacing: 8) {
                Text(Self.greetingTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(Theme.Copy.tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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
        .oneShotConfetti(isPresented: $showConfetti)
        .background(.background)
        .dialogWindowChrome()
        .centeredOnScreen()
    }

    /// Personalised welcome title. Uses the macOS account holder's
    /// first name when available so first launch reads as a hello to
    /// the human at the keyboard, not the product. `NSFullUserName()`
    /// is set by macOS at account creation and almost always non-empty,
    /// but the fallback covers headless / unusual setups.
    private static var greetingTitle: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = full.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        if firstName.isEmpty {
            return "Welcome to \(Theme.Copy.appName)"
        }
        return "Welcome, \(firstName)."
    }
}
