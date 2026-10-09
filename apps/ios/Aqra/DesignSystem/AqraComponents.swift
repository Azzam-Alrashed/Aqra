import SwiftUI

// The onboarding's building blocks, shared by the rest of the app so every screen speaks the same language.

/// An emoji in a tinted rounded square: every icon in the app's own voice sits in one, all the same shape.
struct IconTile: View {
    var icon: String
    var tint: Color
    var size: CGFloat = 34

    var body: some View {
        Text(verbatim: icon)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A white card lifted off the surface by a soft purple shadow.
struct AqraCard<Content: View>: View {
    var padding: CGFloat = 12
    var radius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: OnboardingPalette.shadow.opacity(0.10), radius: 18, y: 10)
            .shadow(color: OnboardingPalette.shadow.opacity(0.06), radius: 2, y: 1)
    }
}

/// A short fact in a white capsule, led by an icon tile.
struct AqraChip<Label: View>: View {
    var icon: String
    var tint: Color
    @ViewBuilder var label: Label

    var body: some View {
        HStack(spacing: 8) {
            IconTile(icon: icon, tint: tint, size: 26)
            label
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OnboardingPalette.ink)
                .lineLimit(1)
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(.white, in: Capsule())
        .shadow(color: OnboardingPalette.shadow.opacity(0.10), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// A row in a card: an icon tile, a title with an optional detail beneath, and an accessory at the end.
struct AqraRow<Accessory: View>: View {
    var icon: String
    var tint: Color
    var title: Text
    var detail: Text?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            IconTile(icon: icon, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                title
                    .aqraFont(size: 16, weight: .heavy)
                    .foregroundStyle(OnboardingPalette.ink)
                if let detail {
                    detail
                        .aqraFont(size: 12, weight: .semibold)
                        .foregroundStyle(OnboardingPalette.inkSoft)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

extension AqraRow where Accessory == AqraChevron {
    /// A row that leads somewhere.
    init(icon: String, tint: Color, title: Text, detail: Text? = nil) {
        self.init(icon: icon, tint: tint, title: title, detail: detail) { AqraChevron() }
    }
}

/// The forward chevron in a lavender circle, pointing the way the screen reads.
struct AqraChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(OnboardingPalette.brand)
            .frame(width: 30, height: 30)
            .background(OnboardingPalette.lavender, in: Circle())
            .accessibilityHidden(true)
    }
}

/// «رجوع» at the top of a setup step: the backward chevron in a white circle, pointing the way the screen reads.
struct AqraBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(OnboardingPalette.inkSoft)
                .frame(width: 36, height: 36)
                .background(.white, in: Circle())
                .shadow(color: OnboardingPalette.shadow.opacity(0.10), radius: 8, y: 4)
        }
        .buttonStyle(AqraPressStyle())
        .accessibilityLabel(Text("Back"))
    }
}

/// A thin line between a card's rows, starting after their icon tiles.
struct AqraRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(OnboardingPalette.lavender)
            .frame(height: 1)
            .padding(.leading, 64)
    }
}

/// A section title above a group of cards.
struct AqraSectionTitle: View {
    var title: LocalizedStringKey

    var body: some View {
        Text(title)
            .aqraFont(size: 19, weight: .heavy)
            .foregroundStyle(OnboardingPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A few choices in a white capsule, the chosen one in a purple pill that slides to it.
struct AqraSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: LocalizedStringKey)]
    var scale: CGFloat = 1
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                item(options[index].value, title: options[index].title)
            }
        }
        .padding(4)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(OnboardingPalette.lavender, lineWidth: 1.5))
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func item(_ value: Value, title: LocalizedStringKey) -> some View {
        let selected = selection == value
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selection = value }
        } label: {
            Text(title)
                .font(.system(size: 15 * scale, weight: .bold))
                // On a narrow phone a label shrinks a little rather than breaking a word across lines.
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(selected ? .white : OnboardingPalette.inkSoft)
                .padding(.horizontal, 18 * scale)
                .frame(height: 38 * scale)
                .background {
                    if selected {
                        Capsule()
                            .fill(LinearGradient(colors: [OnboardingPalette.brand, OnboardingPalette.brandDeep], startPoint: .top, endPoint: .bottom))
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A card or tile that gives a little as it's pressed.
struct AqraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - The منازل stairs

/// The منازل as the onboarding draws them: ten glossy steps, three juz' each, rising in the reading direction
/// toward the gold star. Climbed steps take their colored-Mushaf band from the bottom up; the rest are white glass.
///
/// `climb` animates (0...10): change it with an animation and the steps fill one after another.
struct GlossyStairs: View, Animatable {
    static let stepCount = ManazilStairs.stepCount
    static let size = CGSize(width: block.width + CGFloat(stepCount - 1) * rise.width,
                             height: block.height + CGFloat(stepCount) * rise.height + 26)
    private static let block = CGSize(width: 44, height: 24)
    private static let rise = CGSize(width: 30, height: 17)

    var climb: Double

    nonisolated var animatableData: Double {
        get { climb }
        set { climb = newValue }
    }

    @Environment(\.layoutDirection) private var direction

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(0..<Self.stepCount, id: \.self) { index in
                GlossyStep(face: ManazilStairs.face(forJuz: index * ManazilStairs.juzPerStep + 1),
                           lit: min(max(climb - Double(index), 0), 1), height: Self.block.height)
                    .frame(width: Self.block.width, height: Self.block.height)
                    .offset(x: -CGFloat(index) * Self.rise.width, y: -CGFloat(index) * Self.rise.height)
                    .zIndex(Double(Self.stepCount - index))
            }
            AqraStar()
                .frame(width: 34, height: 34)
                .shadow(color: AqraLogoColor.gold.opacity(0.6), radius: 10)
                .offset(x: -CGFloat(Self.stepCount - 1) * Self.rise.width + 5, y: -CGFloat(Self.stepCount) * Self.rise.height - 14)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottomTrailing)
        // Drawn rising to the left, as Arabic reads; mirrored for left-to-right languages.
        .environment(\.layoutDirection, .leftToRight)
        .scaleEffect(x: direction == .rightToLeft ? 1 : -1)
        .accessibilityHidden(true)
    }
}

/// One step: white glass, filled from the bottom with its band's color as far as it's climbed, under a sheen.
private struct GlossyStep: View {
    var face: (top: Color, bottom: Color)
    var lit: Double
    var height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack(alignment: .bottom) {
            shape.fill(.white.opacity(0.75))
            shape
                .fill(LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom))
                .mask(alignment: .bottom) { Rectangle().frame(height: height * lit) }
            shape
                .fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0)], startPoint: .top, endPoint: .center))
                .padding(2)
        }
        .overlay(shape.strokeBorder(lit > 0 ? Color.white.opacity(0.7) : OnboardingPalette.lavender, lineWidth: 1))
        .shadow(color: lit > 0 ? face.bottom.opacity(0.45 * min(lit * 2, 1)) : OnboardingPalette.brand.opacity(0.08), radius: 8, y: 6)
    }
}

extension View {
    /// What scrolls up fades away under the status bar instead of running into it.
    func fadesUnderStatusBar() -> some View {
        overlay(alignment: .top) {
            GeometryReader { geometry in
                LinearGradient(colors: [OnboardingPalette.surface, OnboardingPalette.surface.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.safeAreaInsets.top + 14)
                    .offset(y: -geometry.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Over the Mushaf

/// A white capsule floating over the Mushaf's page, holding its buttons or its title. It follows the page into
/// dark mode.
struct FloatingCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 4)
            .frame(minHeight: 48)
            .background(MushafStyle.barFill, in: Capsule())
            .shadow(color: OnboardingPalette.shadow.opacity(0.12), radius: 14, y: 6)
            .shadow(color: OnboardingPalette.shadow.opacity(0.05), radius: 2, y: 1)
    }
}

/// A white card floating over the Mushaf's page: the marking and revision bars.
struct FloatingPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: 620)
            .background(MushafStyle.barFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: OnboardingPalette.shadow.opacity(0.14), radius: 20, y: 8)
            .shadow(color: OnboardingPalette.shadow.opacity(0.05), radius: 2, y: 1)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
    }
}
