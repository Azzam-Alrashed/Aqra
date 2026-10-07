import SwiftUI

/// The منازل stairs: ten steps rising toward a gold star, each worth three juz' of memorization.
/// Steps light from the bottom as `climb` grows, in the colored-Mushaf bands of the onboarding stairs
/// (butter, peach, rose, lavender, sky, two steps each), and the star lights when all ten are climbed.
///
/// `climb` animates: change it inside `withAnimation` and the steps light one after another as it passes them.
struct ManazilStairs: View, Animatable {
    nonisolated static let stepCount = 10
    nonisolated static let juzPerStep = 3

    /// How many steps are lit, 0...10; a fraction lights the top step partway.
    var climb: Double

    nonisolated var animatableData: Double {
        get { climb }
        set { climb = newValue }
    }

    /// The stairs rise in the reading direction: to the left in Arabic, to the right in English.
    @Environment(\.layoutDirection) private var direction

    private static let unlit = (top: Color(light: 0xF1EBFB, dark: 0xF1EBFB), bottom: Color(light: 0xDFD4F2, dark: 0xDFD4F2))

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, risesLeftward: direction == .rightToLeft)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for index in 0..<Self.stepCount {
                        let rect = layout.step(index)
                        let corner = min(layout.stepWidth * 0.3, 14)
                        let shape = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
                        let lit = min(max(climb - Double(index), 0), 1)
                        let face = Self.face(forJuz: index * Self.juzPerStep + 1)
                        // A lit step casts a soft shadow in its own band's color; unlit steps sit flat.
                        if lit > 0 {
                            context.drawLayer { shadow in
                                shadow.addFilter(.shadow(color: face.bottom.opacity(0.35 * lit), radius: 5, y: 4))
                                shadow.fill(shape, with: .color(Self.unlit.bottom))
                            }
                        }
                        context.fill(shape, with: .linearGradient(
                            Gradient(colors: [Self.unlit.top, Self.unlit.bottom]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                        context.stroke(shape, with: .color(.white.opacity(0.8)), lineWidth: 1)
                        guard lit > 0 else { continue }
                        var step = context
                        step.clip(to: shape)
                        let litRect = CGRect(x: rect.minX, y: rect.maxY - rect.height * lit, width: rect.width, height: rect.height * lit)
                        step.fill(Path(litRect), with: .linearGradient(
                            Gradient(colors: [face.top, face.bottom]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                        // The white sheen across a step's top, as on the onboarding stairs.
                        let sheen = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height * 0.45, 26))
                        step.fill(Path(sheen), with: .linearGradient(
                            Gradient(colors: [.white.opacity(0.7 * lit), .white.opacity(0)]),
                            startPoint: CGPoint(x: sheen.midX, y: sheen.minY), endPoint: CGPoint(x: sheen.midX, y: sheen.maxY)))
                    }
                }

                ManazilStar(lit: climb >= Double(Self.stepCount) - 0.001)
                    .frame(width: layout.starSize, height: layout.starSize)
                    .position(layout.starCenter)
            }
        }
        // The canvas draws in left-to-right coordinates; the reading direction is applied by `Layout`.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    /// A juz's band colors: six juz' (two steps) per band, bottom to top.
    static func face(forJuz juz: Int) -> (top: Color, bottom: Color) {
        let face = AqraLogoMark.faces[min(max(juz - 1, 0) / 6, AqraLogoMark.faces.count - 1)]
        return (Color(light: face.top, dark: face.top), Color(light: face.bottom, dark: face.bottom))
    }

    /// Where each step sits: the first at the reading start, rising to the tallest at the far end, with room
    /// above it for the star.
    private struct Layout {
        var size: CGSize
        var risesLeftward: Bool
        var gap: CGFloat { max(size.width * 0.025, 4) }
        var stepWidth: CGFloat { (size.width - gap * CGFloat(ManazilStairs.stepCount - 1)) / CGFloat(ManazilStairs.stepCount) }
        var starSize: CGFloat { min(size.height * 0.3, stepWidth * 1.3) }
        var lowest: CGFloat { size.height * 0.12 }
        var highest: CGFloat { size.height - starSize * 1.1 }

        func step(_ index: Int) -> CGRect {
            let height = lowest + (highest - lowest) * CGFloat(index) / CGFloat(ManazilStairs.stepCount - 1)
            let offset = CGFloat(index) * (stepWidth + gap)
            let x = risesLeftward ? size.width - stepWidth - offset : offset
            return CGRect(x: x, y: size.height - height, width: stepWidth, height: height)
        }

        var starCenter: CGPoint {
            let top = step(ManazilStairs.stepCount - 1)
            // Right above the top step.
            return CGPoint(x: top.midX, y: top.minY - starSize * 0.6)
        }
    }
}

/// The gold star above the stairs: a quiet outline until the whole Quran is climbed, then it lights,
/// glows and gently twinkles.
private struct ManazilStar: View {
    var lit: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !lit || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(light: 0xFFF1D6, dark: 0xFFF1D6), Color(light: 0xF8D371, dark: 0xF8D371).opacity(0)],
                                         center: .center, startRadius: 2, endRadius: 40))
                    .scaleEffect(lit ? 1.5 + 0.06 * sin(time * 1.8) : 0.5)
                    .opacity(lit ? 0.9 : 0)
                StarShape(points: 8, innerRatio: 0.42, cornerRadius: 0.05)
                    .fill(lit
                          ? AnyShapeStyle(LinearGradient(colors: [Color(light: 0xF8D371, dark: 0xF8D371), Color(light: 0xEFB54A, dark: 0xEFB54A)],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color(light: 0xEDE6F8, dark: 0xEDE6F8)))
                    .overlay {
                        StarShape(points: 8, innerRatio: 0.42, cornerRadius: 0.05)
                            .stroke(lit ? Color(light: 0xD99A2B, dark: 0xD99A2B).opacity(0.5) : Color(light: 0xD5C8EE, dark: 0xD5C8EE), lineWidth: 1.2)
                    }
                    .shadow(color: Color(light: 0xF6CB66, dark: 0xF6CB66).opacity(lit ? 0.7 : 0), radius: 12)
                    .scaleEffect(lit ? 1 + 0.04 * sin(time * 2.2) : 0.82)
                    .rotationEffect(.degrees(lit ? 0 : -30))
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.45), value: lit)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        ManazilStairs(climb: 0).frame(height: 140)
        ManazilStairs(climb: 2.5).frame(height: 140)
        ManazilStairs(climb: 10).frame(height: 140)
    }
    .padding()
    .background(OnboardingPalette.surface)
}
