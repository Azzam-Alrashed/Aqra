@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseFunctions
import Foundation
import Observation
import StoreKit

/// Credits: bought as App Store consumables and credited by the server once it has verified each purchase, then
/// held for bids and spent on seats won. The wallet and its ledger are written only by the server. For a teacher,
/// also their earnings from won seats and the payouts made to them.
@MainActor @Observable
final class WalletStore {
    struct Entry: Identifiable, Hashable {
        enum Kind: String { case purchase, hold, release, spend, refund, seat, reversal, payout }

        let id: String
        var kind: Kind
        var amount: Double
        var at: Date
    }

    /// The credit packs on sale, by product id, from the App Store; empty until loaded (or when the store can't be
    /// reached).
    private(set) var products: [Product] = []
    private(set) var balance = 0.0
    private(set) var held = 0.0
    private(set) var ledger: [Entry] = []
    /// A teacher's earnings: earned and paid out, and the entries behind them.
    private(set) var earned = 0.0
    private(set) var paidOut = 0.0
    private(set) var earnings: [Entry] = []
    private(set) var isPurchasing = false
    var problem: AccountStore.Problem?

    /// The credit packs (product ids as in App Store Connect and Credits.storekit), smallest first.
    static let productIDs = ["aqra.credits.10", "aqra.credits.30", "aqra.credits.60"]

    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var isNamed = false
    @ObservationIgnored private var listeners: [any ListenerRegistration] = []
    @ObservationIgnored private var updates: Task<Void, Never>?

    private var database: Firestore { Firestore.firestore() }
    private var functions: Functions { Functions.functions(region: AccountStore.functionsRegion) }

    // MARK: - The account in use

    func attach(uid: String, named: Bool) {
        // An anonymous account has no wallet; once it's signed in (the same uid), the wallet opens.
        guard uid != self.uid || named != isNamed else { return }
        detach()
        self.uid = uid
        isNamed = named
        guard named else { return }
        let wallet = database.collection("wallets").document(uid)
        listeners.append(wallet.addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                self?.balance = (snapshot?.data()?["balance"] as? NSNumber)?.doubleValue ?? 0
                self?.held = (snapshot?.data()?["held"] as? NSNumber)?.doubleValue ?? 0
            }
        })
        listeners.append(wallet.collection("ledger").order(by: "at", descending: true).limit(to: 50).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated { self?.ledger = Self.entries(snapshot) }
        })
        let balance = database.collection("teacherBalances").document(uid)
        listeners.append(balance.addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                self?.earned = (snapshot?.data()?["earned"] as? NSNumber)?.doubleValue ?? 0
                self?.paidOut = (snapshot?.data()?["paidOut"] as? NSNumber)?.doubleValue ?? 0
            }
        })
        listeners.append(balance.collection("entries").order(by: "at", descending: true).limit(to: 100).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated { self?.earnings = Self.entries(snapshot) }
        })
        // Purchases the App Store finished while the app was away, or that weren't credited yet, are credited now.
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.unfinished { await self?.redeem(result) }
            for await result in StoreKit.Transaction.updates { await self?.redeem(result) }
        }
    }

    func detach() {
        for listener in listeners { listener.remove() }
        listeners = []
        updates?.cancel()
        updates = nil
        uid = nil
        isNamed = false
        balance = 0
        held = 0
        ledger = []
        earned = 0
        paidOut = 0
        earnings = []
    }

    private static func entries(_ snapshot: QuerySnapshot?) -> [Entry] {
        (snapshot?.documents ?? []).compactMap { document in
            let data = TasmeeStore.dated(document.data())
            guard let kind = (data["kind"] as? String).flatMap(Entry.Kind.init), let at = data["at"] as? Date else { return nil }
            return Entry(id: document.documentID, kind: kind, amount: (data["amount"] as? NSNumber)?.doubleValue ?? 0, at: at)
        }
    }

    /// The balance due to a teacher.
    var due: Double { max(earned - paidOut, 0) }

    // MARK: - Buying credits

    func loadProducts() async {
        guard products.isEmpty else { return }
        let found = (try? await Product.products(for: Self.productIDs)) ?? []
        products = found.sorted { $0.price < $1.price }
    }

    /// Buys a pack; the credits arrive once the server has verified the purchase.
    func buy(_ product: Product) async {
        isPurchasing = true
        problem = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result { await redeem(verification) }
        } catch {
            problem = .failed
        }
    }

    /// Sends a purchase to the server to be verified and credited, then finishes it with the App Store. A purchase
    /// the server can't reach stays unfinished and is tried again at the next launch.
    private func redeem(_ verification: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = verification, Self.productIDs.contains(transaction.productID) else { return }
        do {
            _ = try await functions.httpsCallable("redeemPurchase").call(["signedTransaction": verification.jwsRepresentation])
            await transaction.finish()
        } catch {
            problem = AccountStore.problem(for: error)
        }
    }

    /// Credits a pack holds, by its product id.
    static func credits(of productID: String) -> Int {
        Int(productID.split(separator: ".").last ?? "") ?? 0
    }

    // MARK: - Bidding

    struct BidOutcome {
        var amount: Int
        var nextAtLeast: Int
    }

    enum BidError: Error, Equatable {
        /// The bid must be at least this.
        case tooLow(atLeast: Int)
        case notEnoughCredits(needed: Int)
        case closed
        case failed
    }

    /// Bids for an auctioned seat, holding the credits; the server decides, in one transaction.
    func bid(_ amount: Int, in session: TasmeeSession, name: String, memorizedPages: Int, juzSummary: String?) async throws -> BidOutcome {
        var data: [String: Any] = ["sessionId": session.id, "amount": amount, "name": name, "memorizedPages": memorizedPages]
        if let juzSummary { data["juzSummary"] = juzSummary }
        do {
            let result = try await functions.httpsCallable("placeBid").call(data)
            let response = result.data as? [String: Any] ?? [:]
            return BidOutcome(amount: amount, nextAtLeast: (response["nextAtLeast"] as? NSNumber)?.intValue ?? amount + 1)
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            if let atLeast = (details?["atLeast"] as? NSNumber)?.intValue { throw BidError.tooLow(atLeast: atLeast) }
            if let needed = (details?["needed"] as? NSNumber)?.intValue { throw BidError.notEnoughCredits(needed: needed) }
            if FunctionsErrorCode(rawValue: error.code) == .failedPrecondition { throw BidError.closed }
            throw BidError.failed
        }
    }
}
