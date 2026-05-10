import SwiftUI

/// One-shot party-popper confetti. Every particle launches from a
/// single point at the bottom-centre of the container, arcs up + outward
/// in a wide cone, and falls back down. Each particle drives its own
/// `KeyframeAnimator` (macOS 14+) so the rise → apex → fall trajectory
/// gets two distinct timing segments (fast launch, slower return) that
/// a single linear `.animation` can't express.
///
/// Sized via the surrounding layout — drop it into a ZStack overlay
/// and let it expand to fill. Used by both the About and Welcome
/// scenes; the burst plays once on appear and the parent unmounts the
/// overlay after the longest trajectory finishes so nothing keeps
/// ticking in the background.
struct ConfettiBurst: View {
    private let particles: [ConfettiParticle.Spec] = (0..<90).map { _ in .random() }

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
    @State private var fire = false

    var body: some View {
        KeyframeAnimator(initialValue: Values(), trigger: fire) { values in
            spec.shapeView
                .frame(
                    width: spec.size,
                    height: spec.shape == .capsule ? spec.size * 2.2 : spec.size
                )
                .foregroundStyle(spec.color)
                .rotationEffect(.degrees(values.rotation))
                .offset(x: values.offsetX, y: values.offsetY)
                .opacity(values.opacity)
                .position(
                    // Single launch point: bottom-centre of the container,
                    // just under any visible buttons. Every particle starts
                    // here and fans outward — that's what makes it read
                    // as a burst rather than snowfall.
                    x: containerSize.width / 2,
                    y: containerSize.height - 40
                )
        } keyframes: { _ in
            // Vertical trajectory: rise to apex (negative y in SwiftUI),
            // then fall well past the launch point. CubicKeyframe gives
            // smooth Catmull-Rom interpolation between segments — feels
            // ballistic without us computing physics.
            KeyframeTrack(\.offsetY) {
                CubicKeyframe(-spec.peakRise, duration: spec.riseDuration)
                CubicKeyframe(spec.fallTarget, duration: spec.fallDuration)
            }
            // Horizontal trajectory: travel to the apex's x, then a
            // small extra drift on the way down (wind / tumble feel).
            KeyframeTrack(\.offsetX) {
                CubicKeyframe(spec.peakDX, duration: spec.riseDuration)
                CubicKeyframe(spec.peakDX + spec.driftDX, duration: spec.fallDuration)
            }
            // Continuous spin across the whole flight.
            KeyframeTrack(\.rotation) {
                LinearKeyframe(spec.spin, duration: spec.riseDuration + spec.fallDuration)
            }
            // Fade out only in the last 30 % of the fall so particles
            // are clearly visible through the apex and most of the
            // descent, then disappear before the overlay unmounts.
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1.0, duration: spec.riseDuration + spec.fallDuration * 0.7)
                LinearKeyframe(0.0, duration: spec.fallDuration * 0.3)
            }
        }
        .onAppear { fire.toggle() }
    }

    /// Animatable bag of values. KeyframeAnimator interpolates each
    /// stored property along its KeyframeTrack and hands a fully-
    /// interpolated `Values` to the content closure on every frame.
    struct Values {
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        var rotation: Double = 0
        var opacity: Double = 1
    }

    enum Shape: Equatable {
        case circle, capsule, pill
    }

    struct Spec: Identifiable {
        let id = UUID()
        let peakDX: CGFloat       // x offset at apex (signed)
        let peakRise: CGFloat     // positive number; subtracted from y at apex
        let driftDX: CGFloat      // extra x drift on the way down
        let fallTarget: CGFloat   // final y offset (positive → below origin)
        let riseDuration: Double
        let fallDuration: Double
        let spin: Double
        let size: CGFloat
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
                // Wink to the brand glyph — a few of the launched pieces
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
            // Launch angle in standard math radians where 0 = right and
            // -π/2 = straight up. Range -150°…-30° is a 120° upward
            // cone — wide enough to look chaotic, narrow enough that
            // every particle visibly clears the buttons.
            let angle = Double.random(in: -.pi * 5/6 ... -.pi * 1/6)
            // Big power range — the strongest particles arc well past
            // the dialog's edges and clip at the window bounds. That
            // clipping is the price for keeping the confetti inside
            // the existing Window scene; rendering truly outside the
            // window requires a borderless transparent host window,
            // which is a separate change.
            let power = Double.random(in: 280...520)
            let peakDX = CGFloat(cos(angle) * power)
            // sin(angle) is negative across the upward cone; flip to a
            // positive rise so the trajectory keyframe can subtract it
            // from y (SwiftUI y-down).
            let peakRise = CGFloat(-sin(angle) * power)
            return Spec(
                peakDX: peakDX,
                peakRise: peakRise,
                driftDX: CGFloat.random(in: -40...40),
                fallTarget: CGFloat.random(in: 360...560),
                riseDuration: Double.random(in: 0.5...0.85),
                fallDuration: Double.random(in: 2.2...3.4),
                spin: Double.random(in: -900...900),
                size: CGFloat.random(in: 8...14),
                color: palette.randomElement() ?? .accentColor,
                shape: shapes.randomElement() ?? .circle
            )
        }
    }
}

extension View {
    /// Overlay a one-shot `ConfettiBurst` when `isPresented` is true.
    /// After `duration` the binding flips back to false so the overlay
    /// unmounts and no animations keep ticking. Default duration
    /// outlasts the longest particle trajectory (≈ 4.25s rise + fall,
    /// rounded up for buffer). Used by the About + Welcome dialogs to
    /// keep the celebratory burst self-contained; the caller just
    /// toggles the flag.
    func oneShotConfetti(
        isPresented: Binding<Bool>,
        duration: Duration = .seconds(4.5)
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                ConfettiBurst()
                    .allowsHitTesting(false)
                    .task {
                        try? await Task.sleep(for: duration)
                        isPresented.wrappedValue = false
                    }
            }
        }
    }
}
