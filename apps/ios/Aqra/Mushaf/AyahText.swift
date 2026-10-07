import SwiftUI

/// One ayah in the Complex's own text and Hafs Smart font, as published, wrapping over as many lines as it needs —
/// where an ayah stands on its own (the stage tests).
///
/// The text is pre-shaped glyph codes, each led by a right-to-left mark. SwiftUI lays a single line of it out
/// right, but reverses the letters of every word once the text wraps; so each word is set on its own, and the words
/// flow from the leading edge of a right-to-left layout, line after line, in any language of the app.
struct AyahText: View {
    var text: String
    /// The ayah's plain (Imla'i) text, read by VoiceOver.
    var spoken: String
    var size: CGFloat

    var body: some View {
        let font = MushafFonts.hafsSmart(size: size) ?? .title3
        WordFlow(spacing: size * 0.28, lineSpacing: size * 0.35) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
                Text(verbatim: String(word))
                    .font(font)
                    // The Complex's font as it is: a design (rounded) would swap it for a system font.
                    .fontDesign(nil)
                    .fixedSize()
            }
        }
        // The flow's leading edge is the right: SwiftUI mirrors a layout's placements in a right-to-left layout.
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}

/// Words laid from the leading edge, wrapping onto new lines, each line centered.
struct WordFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func lines(for subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var lines: [[(Int, CGSize)]] = [[]]
        var used: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !lines[lines.count - 1].isEmpty, used + spacing + size.width > width {
                lines.append([])
                used = 0
            }
            used += (lines[lines.count - 1].isEmpty ? 0 : spacing) + size.width
            lines[lines.count - 1].append((index, size))
        }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(for: subviews, width: width)
        let widest = lines.map { line in line.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(line.count - 1, 0)) }.max() ?? 0
        let height = lines.reduce(0) { $0 + ($1.map(\.size.height).max() ?? 0) } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: subviews, width: bounds.width) {
            let lineWidth = line.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(line.count - 1, 0))
            let lineHeight = line.map(\.size.height).max() ?? 0
            // From the leading edge of the centered line (mirrored by SwiftUI in a right-to-left layout).
            var x = bounds.midX - lineWidth / 2
            for (index, size) in line {
                subviews[index].place(at: CGPoint(x: x, y: y + (lineHeight - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += lineHeight + lineSpacing
        }
    }
}
