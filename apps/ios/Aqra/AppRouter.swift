import Foundation
import Observation

/// Where the app is, and the links that move it: `aqra://peer/CODE` (a friend's tasmee' code) and
/// `aqra://friend/CODE` (a friend's invitation).
@MainActor @Observable
final class AppRouter {
    var tab = AppTab.home
    /// A friend's tasmee' code waiting to be heard.
    var peerCode: String?
    /// A friend's invitation waiting to be accepted.
    var friendCode: String?

    /// Follows an Aqra link; false when the link isn't one of the app's own.
    func open(_ url: URL) -> Bool {
        guard url.scheme == "aqra" else { return false }
        if let code = PeerRequest.code(in: url) {
            peerCode = code
            tab = .tasmee
            return true
        }
        if url.host == "friend" {
            let code = PeerRequest.normalize(url.lastPathComponent)
            guard PeerRequest.isWellFormed(code) else { return true }
            friendCode = code
            tab = .progress
            return true
        }
        return true
    }
}
