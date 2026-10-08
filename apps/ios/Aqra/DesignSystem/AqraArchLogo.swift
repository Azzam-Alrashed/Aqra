import SwiftUI

/// Aqra's logo (the user's design): a soft arch with a gold star above a glowing doorway,
/// rising out of two open-book curves. Drawn on a 1024-point canvas; scale it to fit.
struct AqraArchLogo: View {
    /// Draw the pale backdrop behind the mark (for the app icon).
    var withBackground = true
    /// Scale of the mark inside the canvas; the app icon uses a larger mark than the logo artwork.
    var markScale: CGFloat = 1
    var palette: LogoPalette = .aqra

    /// Entrance progress of each part, 0...1. All 1 shows the finished logo.
    var archReveal: CGFloat = 1
    var bookReveal: CGFloat = 1
    var doorReveal: CGFloat = 1
    var starReveal: CGFloat = 1
    /// Seconds since some reference, for the idle sparkle; constant keeps it still.
    var time: TimeInterval = 0
    /// Draw the arch, the doorway and the book. Off leaves only the star and its sparkles, for the splash to animate apart.
    var showsBody = true

    /// Where the star and the sparkles sit on the canvas, before the mark is lifted.
    static let starCenter = CGPoint(x: 512, y: 380)
    static let sparkleCenters = [CGPoint(x: 353, y: 461), CGPoint(x: 671, y: 461), CGPoint(x: 372, y: 590), CGPoint(x: 651, y: 590)]
    /// How far the mark is lifted on the canvas at a mark scale of 1: its visual center sits ~20pt below the canvas center.
    static let markLift: CGFloat = 20

    var body: some View {
        ZStack {
            if withBackground {
                RadialGradient(colors: palette.background.map(hex), center: UnitPoint(x: 0.5, y: 0.46), startRadius: 60, endRadius: 720)
            }
            mark
                .scaleEffect(markScale)
                // Lifted to center it visually, more as it grows.
                .offset(y: -Self.markLift * markScale)
        }
        .frame(width: 1024, height: 1024)
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private var mark: some View {
        ZStack {
            if showsBody {
            Group {
            // A soft white halo around the arch.
            ArchPath.outer.fill(.white).blur(radius: 34).opacity(0.85)

            // The arch: a band that fades as it reaches the book.
            ArchPath.outer.fill(LinearGradient(
                stops: zip(palette.band, [0.0, 0.35, 0.55, 0.66, 0.72]).map { .init(color: hex($0), location: $1) },
                startPoint: UnitPoint(x: 0.5, y: 0.15), endPoint: UnitPoint(x: 0.5, y: 0.9)
            ))
            ArchPath.inner.fill(hex(0xFEFEFF))
            }
            .opacity(archReveal)
            .scaleEffect(0.92 + 0.08 * archReveal, anchor: UnitPoint(x: 0.5, y: 0.9))

            // Warm light gathering behind the doorway.
            ArchPath.inner.fill(RadialGradient(colors: [hex(0xFFE9C4).opacity(0.55), hex(0xFFF6E8).opacity(0.25), .white.opacity(0)], center: UnitPoint(x: 0.5, y: 0.55), startRadius: 10, endRadius: 280))
                .opacity(doorReveal * (0.85 + 0.15 * sin(time * 1.4)))

            // The doorway: a small arch with a glowing path inside, rising toward the star.
            Group {
            ArchPath.door.fill(LinearGradient(colors: [hex(palette.door[0]), hex(palette.door[1]), hex(palette.door[2]).opacity(0.4)], startPoint: UnitPoint(x: 0.5, y: 0.46), endPoint: UnitPoint(x: 0.5, y: 0.7)))
            ArchPath.doorOpening.fill(hex(0xFFFEFB))
            ArchPath.doorLight.fill(LinearGradient(colors: [hex(0xF8CF92), hex(0xFBE3BD), hex(0xFFF7EA).opacity(0.2)], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: UnitPoint(x: 0.5, y: 0.73)))
                .opacity(doorReveal)
            }
            .opacity(archReveal)

            // The open book: two overlapping curves, the right one in front.
            Group {
                Ellipse().fill(LinearGradient(colors: palette.bookBack.map(hex), startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42)))
                    .frame(width: 660, height: 720).position(x: 240, y: 1000)
                Ellipse().fill(LinearGradient(colors: palette.bookBackDeep.map(hex), startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42)))
                    .frame(width: 600, height: 640).position(x: 228, y: 1040)
                Ellipse().fill(LinearGradient(colors: palette.bookFront.map(hex), startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42)))
                    .overlay(Ellipse().stroke(.white.opacity(0.55), lineWidth: 2).blur(radius: 1.5))
                    .frame(width: 660, height: 720).position(x: 784, y: 1000)
                Ellipse().fill(LinearGradient(colors: palette.bookFrontDeep.map(hex), startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42)))
                    .frame(width: 600, height: 640).position(x: 796, y: 1040)
            }
            .frame(width: 1024, height: 1024)
            .offset(y: (1 - bookReveal) * 260)
            .mask(ArchPath.outer)
            .opacity(min(1, bookReveal * 1.5))
            }

            // The star and its sparkles.
            StarShape(points: 8, innerRatio: 0.38, cornerRadius: 0.04)
                .fill(LinearGradient(colors: [hex(0xF8D371), hex(0xEFB54A)], startPoint: .top, endPoint: .bottom))
                .frame(width: 122, height: 122)
                .shadow(color: hex(0xF6CB66).opacity(0.5), radius: 30 + 8 * sin(time * 2))
                .scaleEffect(max(0.01, starReveal) * (1 + 0.03 * sin(time * 2)))
                .rotationEffect(.degrees((1 - starReveal) * -120))
                .opacity(starReveal)
                .position(Self.starCenter)
            ForEach(Array(Self.sparkleCenters.enumerated()), id: \.offset) { index, point in
                StarShape(points: 4, innerRatio: 0.38, cornerRadius: 0.1)
                    .fill(hex(0xEFC47C))
                    .frame(width: 22, height: 22)
                    .scaleEffect(starReveal * (0.85 + 0.25 * sin(time * 2.6 + Double(index) * 1.7)))
                    .opacity(starReveal)
                    .position(point)
            }
        }
        .frame(width: 1024, height: 1024)
    }

    private func hex(_ value: UInt32) -> Color { Color(light: value, dark: value) }
}

/// The logo's colors. The star and the doorway's light stay gold in every palette.
struct LogoPalette {
    var background: [UInt32]
    /// Five stops down the arch band, from its crown to where it fades into the book.
    var band: [UInt32]
    var door: [UInt32]
    var bookBack: [UInt32]
    var bookBackDeep: [UInt32]
    var bookFront: [UInt32]
    var bookFrontDeep: [UInt32]

    /// Aqra's identity: lavender and purple on cream.
    static let aqra = LogoPalette(
        background: [0xFEFCF9, 0xF4EEF8, 0xE9E0F3],
        band: [0xE6DCF7, 0xC8B4EE, 0xA88BE2, 0xD5C7F3, 0xEEE8FA],
        door: [0xDDD0F5, 0xEDE6FA, 0xF8F5FD],
        bookBack: [0xF2ECFC, 0xC6AFEE, 0x9B78DD],
        bookBackDeep: [0xDCCCF6, 0xA184E2, 0x7C55CC],
        bookFront: [0xF5F0FD, 0xCDB9F1, 0xA383E0],
        bookFrontDeep: [0xE1D4F8, 0xA98DE5, 0x8460D1]
    )

    /// The original sky-blue artwork.
    static let sky = LogoPalette(
        background: [0xFBFCFE, 0xE7EFF9, 0xD9E6F5],
        band: [0xD3E3F9, 0xA8CCF6, 0x8CC0F4, 0xBFD8F8, 0xE3EEFB],
        door: [0xCFE2F9, 0xE3EEFB, 0xF4F8FD],
        bookBack: [0xE9F2FD, 0xA9CEF6, 0x7DB4F0],
        bookBackDeep: [0xC2DCF9, 0x86BBF2, 0x62A6EE],
        bookFront: [0xEDF4FD, 0xB3D4F7, 0x86BBF2],
        bookFrontDeep: [0xC9E0FA, 0x8DBFF3, 0x66A8EE]
    )
}

/// Outlines of the arch, drawn in 1024-point canvas coordinates.
private enum ArchPath {
    /// An ogee arch: straight sides, a rounded base, and a pointed crown.
    static func arch(left: CGFloat, right: CGFloat, shoulder: CGFloat, apex: CGFloat, bottom: CGFloat, corner: CGFloat, crown: CGFloat) -> Path {
        let mid = (left + right) / 2
        var p = Path()
        p.move(to: CGPoint(x: left, y: shoulder))
        p.addLine(to: CGPoint(x: left, y: bottom - corner))
        p.addQuadCurve(to: CGPoint(x: left + corner, y: bottom), control: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: right - corner, y: bottom))
        p.addQuadCurve(to: CGPoint(x: right, y: bottom - corner), control: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: right, y: shoulder))
        p.addCurve(to: CGPoint(x: mid, y: apex),
                   control1: CGPoint(x: right, y: shoulder - (shoulder - apex) * 0.55),
                   control2: CGPoint(x: mid + (right - mid) * crown, y: apex + (shoulder - apex) * 0.22))
        p.addCurve(to: CGPoint(x: left, y: shoulder),
                   control1: CGPoint(x: mid - (right - mid) * crown, y: apex + (shoulder - apex) * 0.22),
                   control2: CGPoint(x: left, y: shoulder - (shoulder - apex) * 0.55))
        p.closeSubpath()
        return p
    }

    static let outer = arch(left: 228, right: 796, shoulder: 470, apex: 152, bottom: 912, corner: 150, crown: 0.42)
    static let inner = arch(left: 270, right: 754, shoulder: 488, apex: 212, bottom: 870, corner: 115, crown: 0.42)
    static let door = arch(left: 432, right: 592, shoulder: 590, apex: 476, bottom: 800, corner: 0, crown: 0.35)
    static let doorOpening = arch(left: 470, right: 554, shoulder: 610, apex: 538, bottom: 800, corner: 0, crown: 0.35)
    static let doorLight = arch(left: 489, right: 535, shoulder: 600, apex: 562, bottom: 800, corner: 0, crown: 0.3)
}

#Preview {
    AqraArchLogo().scaleEffect(0.35).frame(width: 360, height: 360)
}
