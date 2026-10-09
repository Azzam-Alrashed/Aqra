import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// «علّم في اقرأ»: applying to teach. A signed-in user tells the vetting team who they are and from whom they hold
/// their ijazah, with a copy of it; the team reviews it, interviews them, and approves or declines. The screen
/// shows where the application stands, and lets it be changed while it waits.
struct TeacherApplicationView: View {
    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AccountStore.self) private var account
    @State private var draft = TeacherApplication(id: "", name: "")
    @State private var editing = false
    @State private var photo: PhotosPickerItem?
    @State private var importingPDF = false
    @State private var uploading = false
    @State private var uploadFailed = false
    @State private var confirmingWithdraw = false
    @State private var submitted = false

    private var signedIn: Bool { account.profile?.isAnonymous == false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Teach on Aqra").foregroundStyle(Palette.ink)
                    Text("Hear students recite").foregroundStyle(Palette.brand)
                }
                .aqraFont(size: 28, weight: .heavy)
                .padding(.top, 8)

                if !signedIn {
                    signIn
                } else if let application = tasmee.application, !editing {
                    status(application)
                } else {
                    form
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: editing)
            .animation(.snappy, value: draft.files)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.surface.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .onAppear(perform: prepareDraft)
        .onChange(of: photo) { Task { await uploadPhoto() } }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { Task { await uploadPDF(url) } }
        }
        .sensoryFeedback(.success, trigger: submitted) { _, done in done }
        .alert("Withdraw your application?", isPresented: $confirmingWithdraw) {
            Button("Withdraw", role: .destructive) { Task { await tasmee.withdrawApplication() } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your application and the copy of your ijazah are deleted.")
        }
    }

    // MARK: - Not signed in

    private var signIn: some View {
        AqraCard(padding: 14, radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in to apply")
                    .aqraFont(size: 16, weight: .heavy)
                    .foregroundStyle(Palette.ink)
                Text("Teachers are vetted: the team reviews your ijazah, then meets you for an interview.")
                    .aqraFont(size: 13, weight: .medium)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                SignInButtons()
                if let problem = account.problem {
                    ProblemLine(problem: problem)
                }
            }
        }
    }

    // MARK: - Where it stands

    private func status(_ application: TeacherApplication) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AqraCard(padding: 16, radius: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 0) {
                        step(1, title: Text("Submitted"), reached: true)
                        connector(reached: application.status != .submitted)
                        step(2, title: Text("Interview"), reached: [.interview, .approved].contains(application.status))
                        connector(reached: application.status == .approved)
                        step(3, title: Text("Approved"), reached: application.status == .approved)
                    }
                    Group {
                        switch application.status {
                        case .submitted: Text("The team will review your application and your ijazah.")
                        case .interview: Text("Your ijazah was reviewed. The team will contact you to arrange the interview.")
                        case .approved: Text("Welcome! Your sessions appear in the Tasmee' tab.")
                        case .rejected: Text("Your application wasn't accepted.")
                        }
                    }
                    .aqraFont(size: 14, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    if !application.note.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            IconTile(icon: "💬", tint: Palette.lavender, size: 30)
                            Text(verbatim: application.note)
                                .aqraFont(size: 13, weight: .medium)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    summaryRow(icon: "🎓", title: Text(verbatim: application.name), detail: application.city)
                    AqraRowDivider()
                    summaryRow(icon: "📜", title: Text("Ijazah from \(application.ijazahFrom)"), detail: application.riwayah)
                    AqraRowDivider()
                    summaryRow(icon: "📎", title: Text("\(application.files.count) files"), detail: application.contact)
                }
            }
            if application.canEdit {
                HStack(spacing: 10) {
                    Button("Change it") {
                        draft = application
                        editing = true
                    }
                    .buttonStyle(ChipButtonStyle(filled: true))
                    Button("Withdraw") { confirmingWithdraw = true }
                        .buttonStyle(ChipButtonStyle(filled: false))
                }
            }
        }
    }

    private func step(_ number: Int, title: Text, reached: Bool) -> some View {
        VStack(spacing: 6) {
            Text(number.formatted())
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(reached ? .white : Palette.inkSoft)
                .frame(width: 30, height: 30)
                .background(reached ? Palette.brand : Palette.lavender, in: Circle())
            title
                .aqraFont(size: 11, weight: .bold)
                .foregroundStyle(reached ? Palette.brand : Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 76)
    }

    private func connector(reached: Bool) -> some View {
        Capsule()
            .fill(reached ? Palette.brand : Palette.lavender)
            .frame(height: 3)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
    }

    private func summaryRow(icon: String, title: Text, detail: String) -> some View {
        AqraRow(icon: icon, tint: Palette.butter, title: title, detail: detail.isEmpty ? nil : Text(verbatim: detail)) { EmptyView() }
    }

    // MARK: - The form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Teachers on Aqra hold an ijazah in the Quran. Tell us about yours; the team reviews it and then meets you for a short interview.")
                .aqraFont(size: 14, weight: .medium)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            AqraSectionTitle(title: "Your details").padding(.top, 6)
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    field(Text("Name"), text: $draft.name)
                    AqraRowDivider().padding(.leading, -50)
                    field(Text("City"), text: $draft.city)
                    AqraRowDivider().padding(.leading, -50)
                    field(Text("About you"), text: $draft.line, prompt: Text("What students will read"))
                    AqraRowDivider().padding(.leading, -50)
                    field(Text("Contact"), text: $draft.contact, prompt: Text("Phone or email, for the interview"))
                }
            }

            AqraSectionTitle(title: "Your ijazah").padding(.top, 6)
            AqraCard(padding: 0, radius: 24) {
                VStack(spacing: 0) {
                    field(Text("Riwayah"), text: $draft.riwayah)
                    AqraRowDivider().padding(.leading, -50)
                    field(Text("From"), text: $draft.ijazahFrom, prompt: Text("The sheikh who granted it"))
                    AqraRowDivider().padding(.leading, -50)
                    TextField("Its chain, its date, anything else", text: $draft.ijazahDetails, axis: .vertical)
                        .lineLimit(2...6)
                        .aqraFont(size: 15, weight: .medium)
                        .padding(14)
                }
            }

            AqraCard(padding: 14, radius: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconTile(icon: "📎", tint: Palette.sky, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("A copy of your ijazah")
                                .aqraFont(size: 16, weight: .heavy)
                                .foregroundStyle(Palette.ink)
                            Group {
                                if draft.files.isEmpty {
                                    Text("A photo or a PDF, up to 10 MB")
                                } else {
                                    Text("\(draft.files.count) files attached")
                                }
                            }
                            .aqraFont(size: 12, weight: .semibold)
                            .foregroundStyle(draft.files.isEmpty ? Palette.inkSoft : Palette.brand)
                        }
                        Spacer(minLength: 0)
                        if uploading { ProgressView().tint(Palette.brand) }
                    }
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Photo", systemImage: "photo")
                        }
                        .buttonStyle(ChipButtonStyle(filled: false))
                        Button {
                            importingPDF = true
                        } label: {
                            Label("PDF", systemImage: "doc")
                        }
                        .buttonStyle(ChipButtonStyle(filled: false))
                        if !draft.files.isEmpty {
                            Button("Remove all") { draft.files = [] }
                                .aqraFont(size: 13, weight: .bold)
                                .foregroundStyle(Color(light: 0xB3261E, dark: 0xB3261E))
                                .buttonStyle(.plain)
                        }
                    }
                    .disabled(uploading)
                    if uploadFailed {
                        Text("The file couldn't be uploaded. Check your connection, or try a smaller file.")
                            .aqraFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
                    }
                }
            }

            if let problem = tasmee.problem {
                ProblemLine(problem: problem)
            }
            BrandButton(tasmee.application == nil ? "Send application" : "Save changes",
                        metrics: OnboardingButtonMetrics(height: 56, fontSize: 18, compact: false)) {
                tasmee.submit(trimmed(draft))
                editing = false
                submitted = true
            }
            .disabled(!trimmed(draft).isComplete || uploading)
            .opacity(trimmed(draft).isComplete ? 1 : 0.5)
            .padding(.top, 6)
            if tasmee.application != nil {
                Button("Cancel") { editing = false }
                    .aqraFont(size: 15, weight: .semibold)
                    .foregroundStyle(Palette.brand)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func field(_ label: Text, text: Binding<String>, prompt: Text? = nil) -> some View {
        HStack(spacing: 12) {
            label
                .aqraFont(size: 15, weight: .bold)
                .foregroundStyle(Palette.ink)
            TextField(text: text, prompt: prompt) { label }
                .multilineTextAlignment(.trailing)
                .aqraFont(size: 15, weight: .medium)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func prepareDraft() {
        guard let uid = account.profile?.uid else { return }
        if let application = tasmee.application {
            draft = application
        } else if draft.id.isEmpty {
            draft = TeacherApplication(id: uid, name: account.publicName ?? "")
        }
    }

    private func trimmed(_ application: TeacherApplication) -> TeacherApplication {
        var application = application
        for keyPath in [\TeacherApplication.name, \.city, \.line, \.riwayah, \.ijazahFrom, \.ijazahDetails, \.contact] {
            application[keyPath: keyPath] = application[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return application
    }

    // MARK: - Uploads

    private func uploadPhoto() async {
        guard let photo, let data = try? await photo.loadTransferable(type: Data.self) else { return }
        self.photo = nil
        // Photos are sent as JPEG, made smaller until they fit.
        var jpeg = UIImage(data: data).flatMap { $0.jpegData(compressionQuality: 0.85) } ?? data
        var quality = 0.7
        while jpeg.count > TeacherApplication.maxFileSize, quality > 0.2, let image = UIImage(data: data) {
            jpeg = image.jpegData(compressionQuality: quality) ?? jpeg
            quality -= 0.2
        }
        await upload(jpeg, contentType: "image/jpeg")
    }

    private func uploadPDF(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            uploadFailed = true
            return
        }
        await upload(data, contentType: "application/pdf")
    }

    private func upload(_ data: Data, contentType: String) async {
        guard let uid = account.profile?.uid, data.count <= TeacherApplication.maxFileSize else {
            uploadFailed = true
            return
        }
        uploading = true
        uploadFailed = false
        defer { uploading = false }
        do {
            let path = try await TeacherApplication.upload(data, uid: uid, contentType: contentType)
            draft.files.append(path)
        } catch {
            uploadFailed = true
        }
    }
}

private typealias Palette = OnboardingPalette
