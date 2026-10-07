import StoreKit
import SwiftUI

/// How credits are written: whole credits plainly, a teacher's share with its fraction.
enum CreditsFormat {
    static func credits(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 2)))
    }
}

// MARK: - The wallet

/// «رصيدي»: the credits to bid with, those held for active bids, the packs to buy, and every movement.
struct WalletView: View {
    @Environment(WalletStore.self) private var wallet
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Credits").foregroundStyle(Palette.ink)
                    Text("for seats in sessions").foregroundStyle(Palette.brand)
                }
                .font(.system(size: 28, weight: .heavy))
                .padding(.top, 22)

                if account.profile?.isAnonymous != false {
                    AqraCard(padding: 14, radius: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sign in to buy credits")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(Palette.ink)
                            Text("Credits stay with your account, so they're never lost with a device.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                            SignInButtons()
                        }
                    }
                } else {
                    balanceCard
                    AqraSectionTitle(title: "Buy credits").padding(.top, 6)
                    packs
                    if !wallet.ledger.isEmpty {
                        AqraSectionTitle(title: "History").padding(.top, 6)
                        LedgerList(entries: wallet.ledger)
                    }
                    Text("Credits pay for seats won by bidding in teachers' sessions. A bid holds its credits; they come back if someone outbids you or the session is cancelled.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .presentationDragIndicator(.visible)
        .task { await wallet.loadProducts() }
    }

    private var balanceCard: some View {
        AqraCard(padding: 16, radius: 24) {
            HStack(alignment: .center, spacing: 14) {
                IconTile(icon: "🪙", tint: Palette.butter, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: CreditsFormat.credits(wallet.balance))
                        .font(.system(size: 34, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: wallet.balance))
                    Text("credits to bid with")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
                if wallet.held > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: CreditsFormat.credits(wallet.held))
                            .font(.system(size: 18, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Palette.brand)
                        Text("held for bids")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
        }
        .animation(.snappy, value: wallet.balance)
    }

    private var packs: some View {
        Group {
            if wallet.products.isEmpty {
                AqraCard(padding: 14, radius: 24) {
                    Text("The App Store can't be reached right now.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                AqraCard(padding: 0, radius: 24) {
                    VStack(spacing: 0) {
                        ForEach(Array(wallet.products.enumerated()), id: \.element.id) { index, product in
                            if index > 0 { AqraRowDivider() }
                            AqraRow(icon: "🪙", tint: Palette.butter, title: Text("\(WalletStore.credits(of: product.id)) credits"),
                                    detail: Text(verbatim: product.displayName)) {
                                Button(product.displayPrice) { Task { await wallet.buy(product) } }
                                    .buttonStyle(ChipButtonStyle(filled: true))
                                    .disabled(wallet.isPurchasing)
                            }
                        }
                    }
                }
            }
            if let problem = wallet.problem {
                ProblemLine(problem: problem).padding(.horizontal, 6)
            }
        }
    }
}

/// Movements of credits, newest first.
struct LedgerList: View {
    var entries: [WalletStore.Entry]

    var body: some View {
        AqraCard(padding: 0, radius: 24) {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { AqraRowDivider() }
                    HStack(spacing: 12) {
                        IconTile(icon: icon(entry.kind), tint: Palette.lavender, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            title(entry.kind)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text(verbatim: entry.at.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        Text(verbatim: (sign(entry) + CreditsFormat.credits(abs(entry.amount))))
                            .font(.system(size: 15, weight: .heavy).monospacedDigit())
                            .foregroundStyle(sign(entry) == "+" ? Color(light: 0x2E9B63, dark: 0x2E9B63) : Palette.ink)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func sign(_ entry: WalletStore.Entry) -> String {
        switch entry.kind {
        case .purchase, .release, .refund, .seat: "+"
        case .hold, .spend, .payout: "−"
        case .reversal: entry.amount < 0 ? "−" : "+"
        }
    }

    private func icon(_ kind: WalletStore.Entry.Kind) -> String {
        switch kind {
        case .purchase: "🛒"
        case .hold: "🔒"
        case .release: "🔓"
        case .spend: "🎟️"
        case .refund: "↩️"
        case .seat: "🎓"
        case .reversal: "↩️"
        case .payout: "🏦"
        }
    }

    private func title(_ kind: WalletStore.Entry.Kind) -> Text {
        switch kind {
        case .purchase: Text("Credits bought")
        case .hold: Text("Held for a bid")
        case .release: Text("Released: outbid")
        case .spend: Text("A seat won")
        case .refund: Text("Refunded: session cancelled")
        case .seat: Text("A seat won in your session")
        case .reversal: Text("Reversed: session cancelled")
        case .payout: Text("Paid to you")
        }
    }
}

// MARK: - Bidding

/// Bidding for one of a session's auctioned seats: what it takes now, where the student's bid stands, and the bid.
struct BidSheet: View {
    var session: TasmeeSession
    var store: MushafStore

    @Environment(WalletStore.self) private var wallet
    @Environment(TasmeeStore.self) private var tasmee
    @Environment(AccountStore.self) private var account
    @Environment(MemorizationStore.self) private var memorization
    @Environment(\.dismiss) private var dismiss
    @State private var myBid: Bid?
    @State private var amount = 0
    @State private var working = false
    @State private var error: WalletStore.BidError?
    @State private var buying = false
    @State private var prepared = false
    @State private var live: TasmeeSession?

    private var auction: TasmeeSession.Auction? { (live ?? session).auction }

    /// The least this student can bid now: above their own active bid, or what a new bid must reach.
    private var atLeast: Int {
        if let myBid, myBid.status == .active { return myBid.amount + 1 }
        return auction?.nextAtLeast ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("A seat by auction").foregroundStyle(Palette.ink)
                    Text(verbatim: session.teacherName).foregroundStyle(Palette.brand)
                }
                .font(.system(size: 26, weight: .heavy))
                .padding(.top, 22)

                if let auction {
                    AqraCard(padding: 14, radius: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: TasmeeFormat.when(session.startsAt))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Palette.ink)
                            Text("\(auction.seats) seats by auction · \(auction.bids) bids")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                            Text("Bidding closes \(auction.closesAt.formatted(.relative(presentation: .named)))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.brand)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let myBid {
                    standing(myBid)
                }

                AqraCard(padding: 16, radius: 24) {
                    VStack(spacing: 14) {
                        HStack(spacing: 18) {
                            stepButton("minus", enabled: amount > atLeast) { amount -= 1 }
                            VStack(spacing: 0) {
                                Text(verbatim: amount.formatted())
                                    .font(.system(size: 46, weight: .heavy).monospacedDigit())
                                    .foregroundStyle(Palette.brand)
                                    .contentTransition(.numericText(value: Double(amount)))
                                (amount == 0 ? Text("credits · free while seats remain") : Text("credits"))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            .frame(minWidth: 150)
                            stepButton("plus", enabled: true) { amount += 1 }
                        }
                        Text("Your balance: \(CreditsFormat.credits(wallet.balance)) credits")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let error {
                    errorLine(error)
                }

                BrandButton(myBid?.status == .active ? "Raise my bid" : "Place my bid",
                            metrics: OnboardingButtonMetrics(height: 54, fontSize: 17, compact: false)) {
                    Task { await placeBid() }
                }
                .disabled(working || !(auction?.isOpen() ?? false))
                Button("Buy credits") { buying = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.brand)
                    .frame(maxWidth: .infinity)
                Text("Your bid holds its credits. If someone outbids you, they come back at once; if you win, they pay for the seat when bidding closes.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Palette.brand)
        .environment(\.colorScheme, .light)
        .presentationDragIndicator(.visible)
        .animation(.snappy, value: amount)
        .animation(.snappy, value: myBid)
        .sensoryFeedback(.selection, trigger: amount)
        .sheet(isPresented: $buying) { WalletView() }
        .task {
            for await session in tasmee.session(id: session.id) { live = session }
        }
        .task {
            for await bid in tasmee.myBid(in: session.id) {
                myBid = bid
                if !prepared || amount < atLeast {
                    prepared = true
                    amount = atLeast
                }
            }
        }
    }

    private func standing(_ bid: Bid) -> some View {
        let (icon, title, tint): (String, Text, Color) = switch bid.status {
        case .active: ("🟢", Text("Your bid of \(bid.amount) holds a seat"), Palette.mint)
        case .outbid: ("🔔", Text("You were outbid"), Palette.rose)
        case .won: ("🎉", Text("You won a seat"), Palette.butter)
        case .released: ("↩️", Text("Your bid was released"), Palette.lavender)
        }
        return AqraCard(padding: 14, radius: 24) {
            HStack(spacing: 12) {
                IconTile(icon: icon, tint: tint, size: 40)
                title
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
        }
    }

    private func errorLine(_ error: WalletStore.BidError) -> some View {
        Group {
            switch error {
            case .tooLow(let atLeast): Text("A bid now needs at least \(atLeast) credits.")
            case .notEnoughCredits(let needed): Text("You need \(needed) more credits.")
            case .closed: Text("Bidding has closed for this session.")
            case .failed: Text("That didn't work. Please try again.")
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(light: 0x9A3E26, dark: 0x9A3E26))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(enabled ? Palette.brand : Palette.inkSoft.opacity(0.4))
                .frame(width: 46, height: 46)
                .background(Palette.lavender, in: Circle())
        }
        .buttonStyle(AqraPressStyle())
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
    }

    private func placeBid() async {
        working = true
        error = nil
        defer { working = false }
        let full = (1...30).filter { juz in
            store.juzAyahs[juz].map { memorization.memorizedCount(in: $0) == $0.count } ?? false
        }
        do {
            _ = try await wallet.bid(amount, in: session, name: account.publicName ?? String(localized: "A student"),
                                     memorizedPages: RevisionStore.memorizedPages(in: store, memorization: memorization).count,
                                     juzSummary: full.isEmpty ? nil : full.map(String.init).joined(separator: ", "))
        } catch let bidError as WalletStore.BidError {
            error = bidError
            if case .tooLow(let least) = bidError { amount = least }
        } catch {
            self.error = .failed
        }
    }
}

// MARK: - A teacher's earnings

/// What a teacher has earned from seats won in their sessions, what's been paid to them, and what's due.
struct EarningsView: View {
    @Environment(WalletStore.self) private var wallet

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your earnings").foregroundStyle(Palette.ink)
                    Text("from seats won").foregroundStyle(Palette.brand)
                }
                .font(.system(size: 28, weight: .heavy))
                .padding(.top, 22)
                HStack(spacing: 10) {
                    stat(icon: "🏦", tint: Palette.butter, value: wallet.due, label: Text("Due to you"))
                    stat(icon: "🎓", tint: Palette.mint, value: wallet.earned, label: Text("Earned"))
                    stat(icon: "✅", tint: Palette.sky, value: wallet.paidOut, label: Text("Paid"))
                }
                Text("Your share of each seat won by bidding, after the app's commission, in credits. The team pays it by bank transfer.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if !wallet.earnings.isEmpty {
                    AqraSectionTitle(title: "History").padding(.top, 6)
                    LedgerList(entries: wallet.earnings)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .presentationDragIndicator(.visible)
    }

    private func stat(icon: String, tint: Color, value: Double, label: Text) -> some View {
        AqraCard(padding: 12, radius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                IconTile(icon: icon, tint: tint, size: 32)
                Text(verbatim: CreditsFormat.credits(value))
                    .font(.system(size: 20, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                label
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private typealias Palette = OnboardingPalette
