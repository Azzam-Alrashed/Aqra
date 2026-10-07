import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

// MARK: - Reciting to a friend

/// The student shows a friend a code (and its QR code); the friend hears them on their own phone and records what
/// they heard into the student's account, where it's applied as a peer's tasmee'.
struct PeerRequestView: View {
    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AccountStore.self) private var account
    @Environment(RevisionStore.self) private var revision
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mushaf.lastPage") private var lastPage = 1
    @State private var request: PeerRequest?
    @State private var problem: AccountStore.Problem?

    /// The friend's record, once it arrives.
    private var received: TasmeeRecord? {
        guard let request else { return nil }
        return tasmee.history.first { $0.kind == .peer && $0.sessionId == request.id }
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 2) {
                Text("Recite to a friend").foregroundStyle(Palette.ink)
                Text(received == nil ? "Show them this code" : "Your friend recorded it").foregroundStyle(Palette.brand)
            }
            .font(.system(size: 26, weight: .heavy))
            .multilineTextAlignment(.center)
            .padding(.top, 28)

            Spacer(minLength: 0)
            if let received {
                VStack(spacing: 10) {
                    Text(verbatim: "✅").font(.system(size: 64))
                    TasmeeFormat.counts(pages: Set(received.pages).count, stumbles: received.stumbles.count)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Text("It's been added to your revision.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                }
                .transition(.scale.combined(with: .opacity))
            } else if let request {
                VStack(spacing: 16) {
                    if let qr = QRCode.image(for: request.link.absoluteString) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Palette.shadow.opacity(0.12), radius: 18, y: 10)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: request.id.map(String.init).joined(separator: " "))
                        .font(.system(size: 34, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Palette.brand)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityLabel(Text("Code \(request.id)"))
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        let minutes = max(Int(request.expiresAt.timeIntervalSince(timeline.date) / 60), 0)
                        Text("Valid for \(minutes) minutes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    Text("Your friend opens Aqra, taps «Hear a friend» and scans this, or types the code.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let problem {
                VStack(spacing: 12) {
                    ProblemLine(problem: problem)
                    Button("Try again") { Task { await create() } }
                        .buttonStyle(ChipButtonStyle(filled: true))
                }
            } else {
                ProgressView().tint(Palette.brand)
            }
            Spacer(minLength: 0)

            BrandButton(received == nil ? "Cancel" : "Done", metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                dismiss()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: received)
        .sensoryFeedback(.success, trigger: received != nil) { _, arrived in arrived }
        // The code is left to expire rather than deleted on closing: a friend may still be marking.
        .task { await create() }
    }

    private func create() async {
        problem = nil
        do {
            request = try await tasmee.createPeerRequest(studentName: account.publicName, startPage: startPage)
        } catch {
            problem = AccountStore.problem(for: error)
        }
    }

    /// Where the friend's Mushaf opens: the next page of today's wird, or the page last read.
    private var startPage: Int {
        revision.plan?.items.first { !$0.done }?.page ?? lastPage
    }
}

/// A QR code as an image, drawn sharp at any size.
enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: - Hearing a friend

/// Hearing a friend: their code (typed, scanned, or opened from a link), then the marking screen, then the record
/// goes into their account.
struct HearFriendView: View {
    var store: MushafStore
    var initialCode: String?

    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var request: PeerRequest?
    @State private var checking = false
    @State private var invalid = false
    @State private var problem: AccountStore.Problem?
    @State private var scanning = false
    @State private var recorded = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let request {
                TasmeeMarkingView(store: store, studentName: request.studentName ?? String(localized: "A friend"),
                                  startPage: request.startPage ?? 1) { result in
                    tasmee.recordPeerTasmee(for: request, listenerName: account.publicName, pages: result.pages,
                                            stumbles: result.stumbles, mistakes: result.mistakes)
                    recorded = true
                }
            } else {
                entry
            }
        }
        // The marking screen dismisses itself when it records or leaves; this view closes with it.
        .onChange(of: recorded) { if recorded { dismiss() } }
        .task {
            if let initialCode {
                code = initialCode
                await check()
            }
        }
    }

    private var entry: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Palette.brand)
                        .frame(width: 38, height: 38)
                        .background(Palette.lavender, in: Circle())
                }
                .accessibilityLabel(Text("Close"))
                Spacer()
            }
            .padding(.top, 12)
            VStack(spacing: 2) {
                Text("Hear a friend").foregroundStyle(Palette.ink)
                Text("Enter their code").foregroundStyle(Palette.brand)
            }
            .font(.system(size: 28, weight: .heavy))

            TextField(text: $code, prompt: Text(verbatim: "ABC234")) { Text("Code") }
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused($focused)
                .padding(.vertical, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Palette.shadow.opacity(0.10), radius: 18, y: 10)
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: code) {
                    let normalized = String(PeerRequest.normalize(code).prefix(PeerRequest.codeLength))
                    if normalized != code { code = normalized }
                    invalid = false
                }
                .onSubmit { Task { await check() } }

            if invalid {
                Text("This code isn't valid, or it has expired. Ask your friend for a new one.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
                    .multilineTextAlignment(.center)
            }
            if let problem {
                ProblemLine(problem: problem)
            }
            if DataScannerViewController.isSupported {
                Button {
                    scanning = true
                } label: {
                    Label("Scan their QR code", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(ChipButtonStyle(filled: false))
            }
            Spacer(minLength: 0)
            BrandButton("Continue", metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                Task { await check() }
            }
            .disabled(!PeerRequest.isWellFormed(code) || checking)
            .opacity(PeerRequest.isWellFormed(code) ? 1 : 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .overlay { if checking { ProgressView().tint(Palette.brand) } }
        .sheet(isPresented: $scanning) {
            QRScanner { text in
                scanning = false
                if let url = URL(string: text), let scanned = PeerRequest.code(in: url) {
                    code = scanned
                    Task { await check() }
                }
            }
            .ignoresSafeArea()
        }
        .onAppear { if initialCode == nil { focused = true } }
    }

    private func check() async {
        guard PeerRequest.isWellFormed(code), !checking else { return }
        checking = true
        problem = nil
        defer { checking = false }
        do {
            if let found = try await tasmee.peerRequest(code: code) {
                withAnimation(.easeInOut(duration: 0.25)) { request = found }
            } else {
                invalid = true
            }
        } catch {
            problem = AccountStore.problem(for: error)
        }
    }
}

/// The camera, reading QR codes; hands over the first one it finds.
struct QRScanner: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var found = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !found else { return }
            for case .barcode(let barcode) in items {
                guard let text = barcode.payloadStringValue else { continue }
                found = true
                scanner.stopScanning()
                onFound(text)
                return
            }
        }
    }
}

private typealias Palette = OnboardingPalette
