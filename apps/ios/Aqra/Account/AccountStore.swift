import AuthenticationServices
import CryptoKit
@preconcurrency import FirebaseAuth
import FirebaseCore
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseFunctions
@preconcurrency import FirebaseStorage
import Foundation
@preconcurrency import GoogleSignIn
import Observation
import UIKit

/// Who the student is. Every install starts as an anonymous account, so progress is backed up from the first
/// day; signing in with Apple or Google links that sign-in to the same account, so nothing is lost.
@MainActor @Observable
final class AccountStore {
    enum Provider: String {
        case apple = "apple.com"
        case google = "google.com"
    }

    struct Profile: Equatable {
        var uid: String
        var isAnonymous: Bool
        var name: String?
        var email: String?
        var provider: Provider?
    }

    /// Something that went wrong, shown as a short line where it happened.
    enum Problem: Equatable {
        case offline
        case failed
    }

    private(set) var profile: Profile?
    /// The name the student chose to be shown to teachers, peers and friends, kept in their account.
    private(set) var displayName: String?
    /// A sign-in, sign-out or deletion is under way.
    private(set) var isWorking = false
    var problem: Problem?

    @ObservationIgnored let sync: CloudSync
    /// Teachers, sessions and tasmee' records, through the same account.
    @ObservationIgnored let tasmee: TasmeeStore
    /// Friends and competitions, through the same account.
    @ObservationIgnored let social: SocialStore
    /// Credits, and a teacher's earnings.
    @ObservationIgnored let wallet = WalletStore()
    /// Messages from the server and the team.
    @ObservationIgnored let inbox = InboxStore()
    @ObservationIgnored private let apple = AppleSignIn()
    @ObservationIgnored private var listener: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var userListener: (any ListenerRegistration)?

    init(sync: CloudSync, tasmee: TasmeeStore, social: SocialStore) {
        self.sync = sync
        self.tasmee = tasmee
        self.social = social
    }

    // MARK: - Starting

    /// Whether accounts are set up in this build: they need the Firebase config, which isn't in git.
    static var isAvailable: Bool { FirebaseApp.app() != nil }

    /// Where the Cloud Functions run: beside the database and files, in Belgium (see backend/functions).
    static let functionsRegion = "europe-west1"

    /// Debug builds launched with `-UseFirebaseEmulator` talk to the local Auth and Firestore emulators as the
    /// project `demo-aqra`, with no real account involved (see backend/README.md).
    static var usesEmulator: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UseFirebaseEmulator")
        #else
        false
        #endif
    }

    /// Configures Firebase from `Firebase/GoogleService-Info.plist` in the bundle, unless it's missing or this is
    /// a unit-test run (tests never touch the network).
    static func configure() {
        guard FirebaseApp.app() == nil, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #if DEBUG
        if usesEmulator {
            // Made-up options: the emulators check none of them, and the project's name keeps the Firestore
            // cache apart from the real project's.
            let options = FirebaseOptions(googleAppID: "1:000000000000:ios:0000000000000000", gcmSenderID: "000000000000")
            options.projectID = "demo-aqra"
            options.apiKey = "emulator"
            options.storageBucket = "demo-aqra.appspot.com"
            FirebaseApp.configure(options: options)
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            let settings = Firestore.firestore().settings
            settings.host = "127.0.0.1:8080"
            settings.isSSLEnabled = false
            Firestore.firestore().settings = settings
            Storage.storage().useEmulator(withHost: "127.0.0.1", port: 9199)
            Functions.functions(region: AccountStore.functionsRegion).useEmulator(withHost: "127.0.0.1", port: 5001)
            return
        }
        #endif
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist", subdirectory: "Firebase"),
              let options = FirebaseOptions(contentsOfFile: url.path) else { return }
        FirebaseApp.configure(options: options)
        if let clientID = options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    /// Follows the signed-in account, and signs in anonymously when there's none.
    func start() {
        guard Self.isAvailable, listener == nil else { return }
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshProfile(user)
                self.watchDisplayName(uid: user?.uid)
                if let user {
                    self.inbox.attach(uid: user.uid)
                    self.wallet.attach(uid: user.uid, named: !user.isAnonymous)
                }
                if let user {
                    Task {
                        // The backup first, so a tasmee' arriving isn't applied over a copy being restored.
                        await self.sync.attach(uid: user.uid)
                        self.tasmee.attach(uid: user.uid)
                        self.social.attach(uid: user.uid)
                    }
                } else {
                    Auth.auth().signInAnonymously { _, _ in }
                }
            }
        }
    }

    #if DEBUG
    /// Signs in to the Auth emulator as a made-up Google account, linking it to this install's anonymous account
    /// exactly as a real sign-in would.
    func signInToEmulator(email: String) async {
        let token = #"{"sub":"\#(email)","email":"\#(email)","email_verified":true}"#
        await link(GoogleAuthProvider.credential(withIDToken: token, accessToken: ""), name: nil)
    }
    #endif

    private func refreshProfile(_ user: User? = Auth.auth().currentUser) {
        guard let user else {
            profile = nil
            return
        }
        let linked = user.providerData.first { Provider(rawValue: $0.providerID) != nil }
        profile = Profile(uid: user.uid, isAnonymous: user.isAnonymous,
                          name: user.displayName ?? linked?.displayName,
                          email: user.email ?? linked?.email,
                          provider: linked.flatMap { Provider(rawValue: $0.providerID) })
    }

    // MARK: - The name shown to others

    /// The name others see: the one the student chose, else their sign-in's name. Never an email, and never for an
    /// anonymous account.
    var publicName: String? {
        guard let profile, !profile.isAnonymous else { return nil }
        return displayName ?? profile.name
    }

    private func watchDisplayName(uid: String?) {
        userListener?.remove()
        userListener = nil
        displayName = nil
        guard let uid else { return }
        userListener = Firestore.firestore().collection("users").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                let name = (snapshot.data()?["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.displayName = name?.isEmpty == false ? name : nil
            }
        }
    }

    /// Changes the name shown to others (queued while offline); an empty name goes back to the sign-in's.
    func setDisplayName(_ name: String) {
        guard let uid = profile?.uid else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        displayName = trimmed.isEmpty ? nil : trimmed
        Firestore.firestore().collection("users").document(uid)
            .setData(["displayName": trimmed.isEmpty ? FieldValue.delete() : trimmed], merge: true)
    }

    // MARK: - Signing in

    /// Prepares the Sign in with Apple button's request.
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        apple.prepare(request)
    }

    /// Finishes signing in with Apple, from the button's result.
    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let (credential, name) = apple.credential(from: authorization) else {
                problem = .failed
                return
            }
            await link(credential, name: name)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { problem = .failed }
        }
    }

    func signInWithGoogle() async {
        guard let presenter = UIApplication.shared.topViewController else { return }
        problem = nil
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                problem = .failed
                return
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            await link(credential, name: nil)
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue { problem = Self.problem(for: error) }
        }
    }

    /// Links a sign-in to the current account, keeping its progress. When the sign-in already belongs to another
    /// account (a previous install, another device), that account is used instead and this device's progress is
    /// merged into it.
    private func link(_ credential: AuthCredential, name: PersonNameComponents?) async {
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            if let user = Auth.auth().currentUser {
                do {
                    let result = try await user.link(with: credential)
                    await setName(name, of: result.user)
                    wallet.attach(uid: result.user.uid, named: true)
                } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                    let existing = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential ?? credential
                    // The state listener attaches the backup to that account, which merges this device's progress in.
                    try await Auth.auth().signIn(with: existing)
                }
            } else {
                try await Auth.auth().signIn(with: credential)
            }
            refreshProfile()
        } catch {
            problem = Self.problem(for: error)
        }
    }

    /// Apple shares the name only on the first sign-in; it's kept as the account's display name.
    private func setName(_ name: PersonNameComponents?, of user: User) async {
        guard user.displayName == nil, let name else { return }
        let formatted = PersonNameComponentsFormatter().string(from: name)
        guard !formatted.isEmpty else { return }
        let change = user.createProfileChangeRequest()
        change.displayName = formatted
        try? await change.commitChanges()
    }

    // MARK: - Signing out and deleting

    /// Signs out after making sure the account holds everything, then clears this device and starts afresh.
    /// Returns false when the account couldn't be reached, so nothing was changed.
    @discardableResult
    func signOut() async -> Bool {
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            try await sync.uploadNow()
        } catch {
            problem = .offline
            return false
        }
        sync.detach()
        tasmee.detach()
        social.detach()
        wallet.detach()
        inbox.detach()
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        sync.clearDevice()
        // Back to «ماذا تحفظ؟», as on a new install; the listener signs in anonymously.
        UserDefaults.standard.set(false, forKey: "memorization.hasDeclared")
        return true
    }

    /// Deletes the account and everything it holds. The progress on this device stays, under a new anonymous
    /// account. Signed-in accounts are signed in again first (Apple's token is revoked as Apple requires), so
    /// a sign-in refused or cancelled never leaves a live account with its data gone; then the backups stop,
    /// the data goes, and the account last.
    @discardableResult
    func deleteAccount() async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            // Deleting needs the server: offline, say so now, before anything is asked or half of it is queued.
            _ = try await Firestore.firestore().collection("users").document(user.uid).getDocument(source: .server)
            switch profile?.provider {
            case .apple:
                let authorization = try await apple.request()
                guard let (credential, _) = apple.credential(from: authorization) else { throw CloudSyncError.timedOut }
                try await user.reauthenticate(with: credential)
                if let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                   let code = appleCredential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) {
                    try? await Auth.auth().revokeToken(withAuthorizationCode: code)
                }
            case .google:
                try await reauthenticateWithGoogle(user)
            case nil:
                break
            }
            sync.stopUploads()
            do {
                try await withServerTimeout(.seconds(60)) {
                    try await self.tasmee.deleteAccountData(uid: user.uid)
                    try await self.social.deleteAccountData(uid: user.uid)
                    try await self.sync.deleteAccountData(uid: user.uid)
                }
                try await user.delete()
            } catch {
                sync.resumeUploads()
                throw error
            }
            sync.detach()
            tasmee.detach()
            social.detach()
            wallet.detach()
            inbox.detach()
            GIDSignIn.sharedInstance.signOut()
            return true
        } catch {
            if (error as? ASAuthorizationError)?.code != .canceled,
               (error as NSError).code != GIDSignInError.canceled.rawValue {
                problem = Self.problem(for: error)
            }
            return false
        }
    }

    private func reauthenticateWithGoogle(_ user: User) async throws {
        guard let presenter = UIApplication.shared.topViewController else { throw CloudSyncError.timedOut }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else { throw CloudSyncError.timedOut }
        try await user.reauthenticate(with: GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString))
    }

    /// What to tell the student about an error from the account: offline, or something else.
    static func problem(for error: Error) -> Problem {
        let error = error as NSError
        let offline = error.code == AuthErrorCode.networkError.rawValue || error.domain == NSURLErrorDomain
            || error is CloudSyncError
            || (error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.unavailable.rawValue)
            || (error.domain == FunctionsErrorDomain && error.code == FunctionsErrorCode.unavailable.rawValue)
        return offline ? .offline : .failed
    }
}

/// Sign in with Apple: the nonce Firebase needs, and the request for signing in again before deleting.
@MainActor
private final class AppleSignIn: NSObject {
    private var nonce: String?
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        self.nonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func credential(from authorization: ASAuthorization) -> (AuthCredential, PersonNameComponents?)? {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential, let nonce,
              let token = apple.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
        let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
        return (credential, apple.fullName)
    }

    /// Asks for Sign in with Apple without the button.
    func request() async throws -> ASAuthorization {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepare(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count, using: &generator)] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignIn: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.activeWindow ?? ASPresentationAnchor()
    }
}

extension UIApplication {
    var activeWindow: UIWindow? {
        connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }

    /// The view controller on top, to present Google's sign-in from.
    var topViewController: UIViewController? {
        var top = activeWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
