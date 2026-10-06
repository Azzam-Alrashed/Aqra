import SwiftUI

struct PageDots: View {
    var count: Int
    var current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? OnboardingPalette.brand : OnboardingPalette.inkSoft.opacity(0.3))
                    .frame(width: index == current ? 20 : 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}
