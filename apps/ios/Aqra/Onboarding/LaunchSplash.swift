import SwiftUI
import UIKit

/// The app's first moments: the splash stays over the first screen until that screen is ready to show.
@MainActor @Observable
final class LaunchState {
    /// The home's data is loaded, so the splash may leave.
    var isReady = false
    /// The first screen is in place beneath the splash, built while the logo plays.
    var showsScreen = false
    /// The splash has stepped back: the first screen plays its entrance.
    var isRevealed = false
    /// The splash is gone.
    var isFinished = false
}

/// The splash's logo: the arch logo on a canvas `side` points square, in three layers the splash animates apart. The
/// body, the body blurred (it comes into focus from it), and the star with its sparkles. The launch screen shows a faint
/// hint of the blur, exactly where the splash begins. Each is rendered to the asset catalog (`LaunchLogoBody`,
/// `LaunchLogoHaze`, `LaunchLogoStars`, `LaunchLogoHint`) by `AppIconRenderTests.renderLaunchLogo`.
struct LaunchLogo: View {
    enum Layer: String, CaseIterable {
        case body = "Body", haze = "Haze", stars = "Stars", hint = "Hint"

        var imageName: String { "LaunchLogo" + rawValue }
    }

    var layer: Layer

    /// Whole points, so the @2x and @3x images land on whole pixels.
    static let side: CGFloat = 266
    static var scale: CGFloat { side / 1024 }
    /// Where the logo starts its entrance: a little lower and smaller, as faint as the launch screen's hint.
    static let entranceDrop: CGFloat = 14
    static let entranceScale: CGFloat = 0.93
    static let hintOpacity: Float = 0.25
    /// The hint's canvas, larger than the logo so the lowered blur isn't cut off.
    static let hintSide: CGFloat = 300

    /// A point on the logo's 1024-point canvas, in the splash's points (the mark is lifted on the canvas).
    static func point(_ canvas: CGPoint) -> CGPoint {
        CGPoint(x: canvas.x * scale, y: (canvas.y - AqraArchLogo.markLift) * scale)
    }

    var body: some View {
        if layer == .hint {
            LaunchLogo(layer: .haze)
                .opacity(Double(Self.hintOpacity))
                .scaleEffect(Self.entranceScale)
                .offset(y: Self.entranceDrop)
                .frame(width: Self.hintSide, height: Self.hintSide)
        } else {
            logo
                .scaleEffect(Self.scale)
                .frame(width: Self.side, height: Self.side)
        }
    }

    @ViewBuilder private var logo: some View {
        switch layer {
        case .body: AqraArchLogo(withBackground: false, starReveal: 0)
        case .haze, .hint: AqraArchLogo(withBackground: false, starReveal: 0).blur(radius: 44)
        case .stars: AqraArchLogo(withBackground: false, showsBody: false)
        }
    }
}

/// The splash, continuing the launch screen's faint hint of the logo. The logo fades in out of a soft light, coming into
/// focus as it settles; the star turns in and lands, the sparkles follow, and gold light swells around the star as the logo breathes,
/// while the Mushaf loads and the home is built beneath. Then the logo drifts out of focus and the home rises.
struct LaunchSplash: View {
    var launch: LaunchState
    /// Whether the first screen is ready to be shown.
    var isReady: Bool
    /// Whether the logo plays. The welcome builds the logo itself, so on first launch the splash lets the hint fade.
    var playsLogo: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var held = false
    @State private var leaving = false
    @State private var logoLeaves = false
    @State private var fades = false

    var body: some View {
        SplashCanvas(playsLogo: playsLogo, reduceMotion: reduceMotion, logoLeaves: logoLeaves, fades: fades)
            .ignoresSafeArea()
            .allowsHitTesting(!fades)
            .accessibilityHidden(true)
            .task {
                if playsLogo { try? await Task.sleep(for: reduceMotion ? SplashCanvasView.calmHold : SplashCanvasView.hold) }
                held = true
            }
            // Checked from `onChange`, which sees the current `isReady`; the task above holds the value it started with.
            .onChange(of: isReady, initial: true) {
                // The first screen is built beneath the logo as soon as it can be; Core Animation plays on meanwhile.
                if isReady { launch.showsScreen = true }
                leaveIfReady()
            }
            .onChange(of: held) { leaveIfReady() }
    }

    /// The logo drifts away, then the background fades and the first screen plays its entrance.
    private func leaveIfReady() {
        guard held, isReady, !leaving else { return }
        leaving = true
        Task {
            // Resumes once the first screen is built and the main thread is free again.
            try? await Task.sleep(for: .milliseconds(50))
            if playsLogo {
                logoLeaves = true
                try? await Task.sleep(for: .milliseconds(320))
            }
            launch.isRevealed = true
            fades = true
            try? await Task.sleep(for: .milliseconds(350))
            launch.isFinished = true
        }
    }
}

/// The splash drawn by Core Animation, whose animations keep running while the main thread builds the first screen.
private struct SplashCanvas: UIViewRepresentable {
    var playsLogo: Bool
    var reduceMotion: Bool
    var logoLeaves: Bool
    var fades: Bool

    func makeUIView(context: Context) -> SplashCanvasView {
        SplashCanvasView(playsLogo: playsLogo, reduceMotion: reduceMotion)
    }

    func updateUIView(_ view: SplashCanvasView, context: Context) {
        if logoLeaves { view.logoLeaves() }
        if fades { view.fade() }
    }
}

private final class SplashCanvasView: UIView {
    /// How long the logo's entrance plays before it may leave, with motion and with Reduce Motion.
    static let hold = Duration.milliseconds(1650)
    static let calmHold = Duration.milliseconds(900)

    private let playsLogo: Bool
    private let reduceMotion: Bool
    /// The logo rises, settles and drifts away; `breather` breathes inside it.
    private let stage = CALayer()
    private let breather = CALayer()
    /// The soft light the logo appears out of.
    private let bloom = CAGradientLayer()
    private let haze = CALayer()
    private let logoBody = CALayer()
    /// Gold light around the star that swells as the logo breathes.
    private let starLight = CAGradientLayer()
    private let star = CALayer()
    private let sparkles = AqraArchLogo.sparkleCenters.map { _ in CALayer() }
    private let haptic = UIImpactFeedbackGenerator(style: .soft)
    private var started = false
    private var left = false
    private var faded = false

    init(playsLogo: Bool, reduceMotion: Bool) {
        self.playsLogo = playsLogo
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        backgroundColor = UIColor(OnboardingPalette.surface)

        bloom.type = .radial
        bloom.colors = [UIColor.white.withAlphaComponent(0.95).cgColor,
                        UIColor(OnboardingPalette.lavender).withAlphaComponent(0.4).cgColor,
                        UIColor(OnboardingPalette.lavender).withAlphaComponent(0).cgColor]
        bloom.locations = [0, 0.42, 1]
        bloom.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloom.endPoint = CGPoint(x: 1, y: 1)

        let gold = UIColor(red: 0xF6 / 255, green: 0xCB / 255, blue: 0x66 / 255, alpha: 1)
        starLight.type = .radial
        starLight.colors = [gold.withAlphaComponent(0.6).cgColor, gold.withAlphaComponent(0).cgColor]
        starLight.startPoint = CGPoint(x: 0.5, y: 0.5)
        starLight.endPoint = CGPoint(x: 1, y: 1)

        let pictures: [(CALayer, LaunchLogo.Layer)] = [(haze, .haze), (logoBody, .body), (star, .stars)] + sparkles.map { ($0, .stars) }
        for (part, name) in pictures {
            let picture = UIImage(named: name.imageName)
            part.contents = picture?.cgImage
            part.contentsScale = picture?.scale ?? 1
        }
        layer.addSublayer(stage)
        stage.addSublayer(bloom)
        stage.addSublayer(breather)
        for part in [haze, logoBody, starLight, star] as [CALayer] + sparkles { breather.addSublayer(part) }
        // As the launch screen left it: only the hint, until the entrance begins.
        stage.transform = start.caTransform3DValue
        for part in [bloom, logoBody, starLight, star] as [CALayer] + sparkles { part.opacity = 0 }
        haze.opacity = LaunchLogo.hintOpacity
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = LaunchLogo.side
        stage.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        stage.position = CGPoint(x: bounds.midX, y: bounds.midY)
        breather.frame = stage.bounds
        bloom.bounds = CGRect(x: 0, y: 0, width: side * 1.8, height: side * 1.8)
        bloom.position = CGPoint(x: side / 2, y: side / 2)
        haze.frame = breather.bounds
        logoBody.frame = breather.bounds
        let starCenter = LaunchLogo.point(AqraArchLogo.starCenter)
        starLight.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        starLight.position = starCenter
        cut(star, around: starCenter, radius: 33)
        for (sparkle, center) in zip(sparkles, AqraArchLogo.sparkleCenters) {
            cut(sparkle, around: LaunchLogo.point(center), radius: 10)
        }
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, playsLogo, !started else { return }
        started = true
        layoutIfNeeded()
        playEntrance()
    }

    /// Shows the stars image cut to a circle around one star, turning and scaling about its center.
    private func cut(_ layer: CALayer, around point: CGPoint, radius: CGFloat) {
        let side = LaunchLogo.side
        layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        layer.anchorPoint = CGPoint(x: point.x / side, y: point.y / side)
        layer.position = point
        let mask = CAShapeLayer()
        mask.frame = layer.bounds
        mask.path = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).cgPath
        layer.mask = mask
    }

    // MARK: - Motion

    private func playEntrance() {
        let start = CACurrentMediaTime() + 0.05
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard !reduceMotion else {
            // In place, the hint gives way to the logo.
            animate(haze, "opacity", [LaunchLogo.hintOpacity, 0], start: start, duration: 0.5, timing: .gentle)
            for part in [bloom, logoBody, star] as [CALayer] + sparkles {
                animate(part, "opacity", [0, 1], start: start, duration: 0.5, timing: .gentle)
            }
            return
        }

        // The light opens, and the logo comes into focus out of it as it rises and settles.
        animate(bloom, "opacity", [0, 1], start: start, duration: 0.9, timing: .soft)
        animate(bloom, "transform.scale", [0.5, 1], start: start, duration: 1.2, timing: .soft)
        animate(stage, "transform", [self.start, lifted(y: 0, scale: 1)], start: start, duration: 1.0, timing: .soft)
        animate(haze, "opacity", [LaunchLogo.hintOpacity, 1, 0], keyTimes: [0, 0.4, 1], start: start, duration: 0.85, timing: .gentle)
        animate(logoBody, "opacity", [0, 1], start: start + 0.2, duration: 0.6, timing: .gentle)

        // The star turns in and lands, with a soft tap.
        let starAt = start + 0.6
        animate(star, "opacity", [0, 1], start: starAt, duration: 0.18, timing: .soft)
        animate(star, "transform.scale", [0.15, 1.14, 0.97, 1], keyTimes: [0, 0.55, 0.8, 1], start: starAt, duration: 0.7, timing: .gentle)
        animate(star, "transform.rotation.z", [-CGFloat.pi * 0.6, 0], start: starAt, duration: 0.7, timing: .soft)
        haptic.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + (starAt - CACurrentMediaTime()) + 0.36) { [haptic] in
            haptic.impactOccurred(intensity: 0.55)
        }

        // The sparkles follow, one by one, then twinkle while the home is getting ready.
        for (index, sparkle) in sparkles.enumerated() {
            let at = start + 0.95 + Double(index) * 0.08
            animate(sparkle, "opacity", [0, 1], start: at, duration: 0.15, timing: .soft)
            animate(sparkle, "transform.scale", [0, 1.4, 1], keyTimes: [0, 0.55, 1], start: at, duration: 0.45, timing: .gentle)
            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = 1
            twinkle.toValue = 0.35
            twinkle.duration = 0.7
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.beginTime = at + 0.6 + Double(index) * 0.21
            twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sparkle.add(twinkle, forKey: "twinkle")
        }

        // Gold light swells around the star as the logo breathes.
        let glowAt = start + 1.0
        animate(starLight, "opacity", [0, 0.9, 0.5], keyTimes: [0, 0.45, 1], start: glowAt, duration: 1.0, timing: .gentle)
        animate(starLight, "transform.scale", [0.5, 1.12, 1], keyTimes: [0, 0.45, 1], start: glowAt, duration: 1.0, timing: .gentle)
        animate(breather, "transform.scale", [1, 1.03, 1], keyTimes: [0, 0.5, 1], start: glowAt, duration: 1.1, timing: .gentle)
    }

    func logoLeaves() {
        guard playsLogo, !left else { return }
        left = true
        let start = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        animate(stage, "opacity", [1, 0], start: start, duration: reduceMotion ? 0.4 : 0.5, timing: .gentle)
        guard !reduceMotion else { return }
        // It drifts up and out of focus.
        animate(stage, "transform", [lifted(y: 0, scale: 1), lifted(y: -12, scale: 0.97)], start: start, duration: 0.55, timing: .away)
        animate(haze, "opacity", [0, 1], start: start, duration: 0.3, timing: .gentle)
        animate(logoBody, "opacity", [1, 0], start: start + 0.05, duration: 0.35, timing: .gentle)
    }

    func fade() {
        guard !faded else { return }
        faded = true
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) { [self] in alpha = 0 }
    }

    /// Animates `keyPath` through `values` from `start`, holding the first value until then and keeping the last.
    private func animate(_ layer: CALayer, _ keyPath: String, _ values: [Any], keyTimes: [NSNumber]? = nil,
                         start: CFTimeInterval, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.beginTime = start
        animation.duration = duration
        animation.timingFunction = timing
        animation.calculationMode = .linear
        animation.fillMode = .backwards
        layer.add(animation, forKey: keyPath)
        layer.setValue(values.last, forKeyPath: keyPath)
    }

    /// Where the stage starts, matching the launch screen's hint.
    private var start: NSValue { lifted(y: LaunchLogo.entranceDrop, scale: LaunchLogo.entranceScale) }

    /// A transform for the stage, moved by `y` and scaled, as Core Animation takes it.
    private func lifted(y: CGFloat, scale: CGFloat) -> NSValue {
        NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeTranslation(0, y, 0), scale, scale, 1))
    }
}

private extension CAMediaTimingFunction {
    /// A long, soft settle.
    static var soft: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1) }
    /// In and out, unhurried.
    static var gentle: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1) }
    /// Gathering pace as it leaves.
    static var away: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.6) }
}
