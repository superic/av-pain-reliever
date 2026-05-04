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
                        // Outlast the longest particle (~2.5s) so every
                        // piece falls off the bottom before the layer
                        // unmounts. After this, the ZStack collapses and
                        // no animations keep ticking in the background.
                        try? await Task.sleep(for: .seconds(2.6))
                        showConfetti = false
                    }
            }
        }
        .background(.background)
        .dialogWindowChrome()
        .centeredOnScreen()
    }
}

// MARK: - Confetti

/// One-shot confetti overlay. Generates a fixed batch of particles on
/// init and lets each one animate itself from above the frame to below.
/// No TimelineView, no DisplayLink — every particle has a single
/// `.animation` driven by a per-particle `@State` flipped on appear.
private struct ConfettiBurst: View {
    private let particles: [ConfettiParticle.Spec] = (0..<36).map { _ in .random() }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { spec in
                    ConfettiParticle(spec: spec, containerSize: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct ConfettiParticle: View {
    let spec: Spec
    let containerSize: CGSize
    @State private var animate = false

    var body: some View {
        spec.shapeView
            .frame(
                width: spec.size,
                height: spec.shape == .capsule ? spec.size * 2.2 : spec.size
            )
            .foregroundStyle(spec.color)
            .rotationEffect(.degrees(animate ? spec.spin : 0))
            .position(x: spec.startX * max(containerSize.width, 1), y: 0)
            .offset(
                x: animate ? spec.driftX : 0,
                y: animate ? containerSize.height + 80 : -40
            )
            .animation(
                .easeOut(duration: spec.duration),
                value: animate
            )
            .onAppear { animate = true }
    }

    enum Shape: Equatable {
        case circle, capsule, pill
    }

    struct Spec: Identifiable {
        let id = UUID()
        let startX: CGFloat       // 0...1, multiplied by container width
        let driftX: CGFloat       // horizontal drift in points
        let spin: Double          // total degrees over the fall
        let duration: Double      // seconds
        let size: CGFloat         // base dimension in points
        let color: Color
        let shape: Shape

        @ViewBuilder
        var shapeView: some View {
            switch shape {
            case .circle:
                Circle()
            case .capsule:
                Capsule()
            case .pill:
                // Wink to the brand glyph — a few of the falling pieces
                // are the same `pills.fill` symbol the menu bar wears.
                Image(systemName: "pills.fill")
                    .resizable()
            }
        }

        static func random() -> Spec {
            // System palette so the burst inherits the user's macOS
            // accent color and stays plain-native.
            let palette: [Color] = [.accentColor, .yellow, .pink, .green, .blue, .orange]
            let shapes: [Shape] = [.circle, .capsule, .pill]
            return Spec(
                startX: .random(in: 0.05...0.95),
                driftX: .random(in: -40...40),
                spin: .random(in: -540...540),
                duration: .random(in: 1.8...2.5),
                size: .random(in: 7...11),
                color: palette.randomElement() ?? .accentColor,
                shape: shapes.randomElement() ?? .circle
            )
        }
    }
}
