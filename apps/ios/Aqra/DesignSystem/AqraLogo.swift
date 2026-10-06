import SwiftUI

/// The منازل mark: stairs in the colored-Mushaf bands rising to a gold star — «اقرَأ وارقَ».
/// Used on the second onboarding page. The app's logo is `AqraArchLogo`.
struct AqraLogoMark: View {
    static let stepCount = 5

    /// How many steps are built (for the entrance animation).
    var built = AqraLogoMark.stepCount
    var starLit = true
    /// -1...1, drives a gentle sparkle on the star.
    var twinkle: Double = 0

    private static let faces: [(top: UInt32, bottom: UInt32)] = [
        (0xFFE7A3, 0xF4C65E), // butter
        (0xFFCDAE, 0xF29D72), // peach
        (0xFBBCD0, 0xE7849F), // rose
        (0xD9C6F7, 0xA98BE3), // lavender
        (0xB9D8F7, 0x7FAEE6), // sky
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(0..<Self.stepCount, id: \.self) { index in
                let face = Self.faces[index]
                StepBlock(top: Color(light: face.top, dark: face.top), bottom: Color(light: face.bottom, dark: face.bottom))
                    .offset(x: -CGFloat(index) * 26, y: -CGFloat(index) * 24)
                    .offset(y: index < built ? 0 : 30)
                    .opacity(index < built ? 1 : 0)
                    .zIndex(Double(Self.stepCount - index))
            }
            AqraStar()
                .frame(width: 38, height: 38)
                .shadow(color: AqraLogoColor.gold.opacity(0.7), radius: starLit ? 9 + twinkle * 3 : 0)
                .scaleEffect(starLit ? 1 + twinkle * 0.04 : 0.1)
                .rotationEffect(.degrees(starLit ? twinkle * 6 : -90))
                .opacity(starLit ? 1 : 0)
                .offset(x: -CGFloat(Self.stepCount - 1) * 26 + 6, y: -CGFloat(Self.stepCount) * 24 - 14)
        }
        .frame(width: 60 + CGFloat(Self.stepCount - 1) * 26, height: 30 + CGFloat(Self.stepCount) * 24, alignment: .bottomTrailing)
        .environment(\.layoutDirection, .leftToRight) // The mark keeps one orientation in every language.
        .accessibilityHidden(true)
    }
}

/// The logo's own gold star (never an emoji, which can't be used in a logo).
struct AqraStar: View {
    var body: some View {
        StarShape(points: 5, innerRatio: 0.48, cornerRadius: 0.18)
            .fill(LinearGradient(colors: [Color(light: 0xFFE38A, dark: 0xFFE38A), Color(light: 0xE8A93A, dark: 0xE8A93A)], startPoint: .top, endPoint: .bottom))
            .overlay {
                StarShape(points: 5, innerRatio: 0.48, cornerRadius: 0.18)
                    .fill(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .scaleEffect(0.86)
                    .offset(y: -1)
            }
            .overlay {
                StarShape(points: 5, innerRatio: 0.48, cornerRadius: 0.18)
                    .stroke(Color(light: 0xC98A22, dark: 0xC98A22).opacity(0.55), lineWidth: 1)
            }
    }
}

/// A star with softly rounded points.
struct StarShape: Shape {
    var points: Int
    var innerRatio: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var vertices: [CGPoint] = []
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = Double(i) * .pi / Double(points) - .pi / 2
            vertices.append(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        var path = Path()
        let r = outer * cornerRadius
        for i in vertices.indices {
            let previous = vertices[(i + vertices.count - 1) % vertices.count]
            let current = vertices[i]
            let next = vertices[(i + 1) % vertices.count]
            let start = point(from: current, toward: previous, distance: r)
            let end = point(from: current, toward: next, distance: r)
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: current)
        }
        path.closeSubpath()
        return path
    }

    private func point(from a: CGPoint, toward b: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let d = min(distance, length / 2)
        return CGPoint(x: a.x + dx / length * d, y: a.y + dy / length * d)
    }
}

struct StepBlock: View {
    var top: Color
    var bottom: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .padding(2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1)
            }
            .frame(width: 60, height: 30)
            .shadow(color: bottom.opacity(0.45), radius: 8, y: 6)
    }
}

/// Glowing concentric rings behind the mark.
struct AqraGlowRings: View {
    var open = true
    /// -1...1, drives a slow breathing motion.
    var breath: Double = 0
    var glow: [Color] = [AqraLogoColor.lavender, AqraLogoColor.rose.opacity(0.5)]
    var ring: Color = .white

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: glow + [glow[0].opacity(0)], center: .center, startRadius: 10, endRadius: 190))
                .frame(width: 380, height: 380)
                .scaleEffect(1 + breath * 0.03)
            ForEach([110.0, 190.0, 270.0], id: \.self) { size in
                Circle()
                    .strokeBorder(ring, lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(open ? 1 + breath * 0.015 : 0.2)
                    .opacity(open ? 0.9 : 0)
            }
            Circle()
                .fill(ring.opacity(0.55))
                .frame(width: 110, height: 110)
                .scaleEffect(open ? 1 : 0.2)
        }
        .opacity(open ? 1 : 0)
        .accessibilityHidden(true)
    }
}

enum AqraLogoColor {
    static let lavender = Color(light: 0xE9DEFA, dark: 0xE9DEFA)
    static let rose = Color(light: 0xFCDCE7, dark: 0xFCDCE7)
    static let gold = Color(light: 0xE8B64C, dark: 0xE8B64C)
}
