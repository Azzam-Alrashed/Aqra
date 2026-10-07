package com.azzamalrashed.aqra.credits

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.SignInButtons
import com.azzamalrashed.aqra.tasmee.juzSummary
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.revision.StepButton
import com.azzamalrashed.aqra.tasmee.Bid
import com.azzamalrashed.aqra.tasmee.TasmeeSession
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatDayTime
import com.azzamalrashed.aqra.ui.util.formatNumber
import com.azzamalrashed.aqra.ui.util.formatRelativeAhead
import com.azzamalrashed.aqra.ui.util.formatWhen
import kotlinx.coroutines.launch
import kotlin.math.abs

// MARK: - The wallet

/** «رصيدي»: the credits to bid with, those held for active bids, and every movement. */
@Composable
fun WalletScreen(app: AqraApp) {
    val wallet = app.account.wallet
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        TwoLineHeadline(stringResource(R.string.credits), stringResource(R.string.for_seats_in_sessions), size = 28f, alignCenter = false,
            modifier = Modifier.padding(top = 8.dp))
        if (app.account.profile?.isAnonymous != false) {
            AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                Text(stringResource(R.string.sign_in_to_buy_credits), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                Spacer(Modifier.height(6.dp))
                Text(stringResource(R.string.credits_stay_with_your_account_so_theyre_never_lost_with), style = aqraStyle(13f, Weight.medium, Palette.inkSoft))
                Spacer(Modifier.height(12.dp))
                SignInButtons(app)
            }
        } else {
            AqraCard(Modifier.fillMaxWidth(), padding = 16.dp, radius = 24.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    IconTile("🪙", Palette.butter, size = 52.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(WalletStore.format(wallet.balance), style = aqraStyle(34f, Weight.heavy, Palette.ink))
                        Text(stringResource(R.string.credits_to_bid_with), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
                    }
                    if (wallet.held > 0) {
                        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(WalletStore.format(wallet.held), style = aqraStyle(18f, Weight.heavy, Palette.brand))
                            Text(stringResource(R.string.held_for_bids), style = aqraStyle(11f, Weight.semibold, Palette.inkSoft))
                        }
                    }
                }
            }
            AqraSectionTitle(stringResource(R.string.buy_credits), Modifier.padding(top = 6.dp))
            AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                Text(stringResource(R.string.credits_arent_sold_on_android_yet), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
            }
            if (wallet.ledger.isNotEmpty()) {
                AqraSectionTitle(stringResource(R.string.history), Modifier.padding(top = 6.dp))
                LedgerList(wallet.ledger)
            }
            Text(stringResource(R.string.credits_pay_for_seats_won_by_bidding_in_teachers_sessions), style = aqraStyle(12f, Weight.medium, Palette.inkSoft))
        }
    }
}

/** Movements of credits, newest first. */
@Composable
fun LedgerList(entries: List<WalletStore.Entry>) {
    AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
        entries.forEachIndexed { index, entry ->
            if (index > 0) AqraRowDivider()
            val sign = when (entry.kind) {
                WalletStore.Entry.Kind.PURCHASE, WalletStore.Entry.Kind.RELEASE, WalletStore.Entry.Kind.REFUND, WalletStore.Entry.Kind.SEAT -> "+"
                WalletStore.Entry.Kind.HOLD, WalletStore.Entry.Kind.SPEND, WalletStore.Entry.Kind.PAYOUT -> "−"
                WalletStore.Entry.Kind.REVERSAL -> if (entry.amount < 0) "−" else "+"
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp).semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile(ledgerIcon(entry.kind), Palette.lavender, size = 34.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(ledgerTitle(entry.kind), style = aqraStyle(14f, Weight.bold, Palette.ink))
                    Text(formatDayTime(entry.at.toInstant()), style = aqraStyle(11f, Weight.semibold, Palette.inkSoft))
                }
                // The amount reads left to right with its sign, in every language.
                androidx.compose.runtime.CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    Text(sign + WalletStore.format(abs(entry.amount)), style = aqraStyle(15f, Weight.heavy, if (sign == "+") Color(0xFF2E9B63) else Palette.ink))
                }
            }
        }
    }
}

private fun ledgerIcon(kind: WalletStore.Entry.Kind): String = when (kind) {
    WalletStore.Entry.Kind.PURCHASE -> "🛒"
    WalletStore.Entry.Kind.HOLD -> "🔒"
    WalletStore.Entry.Kind.RELEASE -> "🔓"
    WalletStore.Entry.Kind.SPEND -> "🎟️"
    WalletStore.Entry.Kind.REFUND, WalletStore.Entry.Kind.REVERSAL -> "↩️"
    WalletStore.Entry.Kind.SEAT -> "🎓"
    WalletStore.Entry.Kind.PAYOUT -> "🏦"
}

@Composable
private fun ledgerTitle(kind: WalletStore.Entry.Kind): String = stringResource(
    when (kind) {
        WalletStore.Entry.Kind.PURCHASE -> R.string.credits_bought
        WalletStore.Entry.Kind.HOLD -> R.string.held_for_a_bid
        WalletStore.Entry.Kind.RELEASE -> R.string.released_outbid
        WalletStore.Entry.Kind.SPEND -> R.string.a_seat_won
        WalletStore.Entry.Kind.REFUND -> R.string.refunded_session_cancelled
        WalletStore.Entry.Kind.SEAT -> R.string.a_seat_won_in_your_session
        WalletStore.Entry.Kind.REVERSAL -> R.string.reversed_session_cancelled
        WalletStore.Entry.Kind.PAYOUT -> R.string.paid_to_you
    },
)

// MARK: - Bidding

/** Bidding for one of a session's auctioned seats: what it takes now, where the student's bid stands, and the bid. */
@Composable
fun BidSheet(app: AqraApp, store: MushafStore, session: TasmeeSession, onDismiss: () -> Unit) {
    val wallet = app.account.wallet
    val tasmee = app.tasmee
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var live by remember { mutableStateOf<TasmeeSession?>(null) }
    var myBid by remember { mutableStateOf<Bid?>(null) }
    var amount by remember { mutableIntStateOf(0) }
    var prepared by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<WalletStore.BidError?>(null) }
    var buying by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val auction = (live ?: session).auction
    /** The least this student can bid now: above their own active bid, or what a new bid must reach. */
    fun atLeast(): Int = myBid?.takeIf { it.status == Bid.Status.ACTIVE }?.let { it.amount + 1 } ?: auction?.nextAtLeast ?: 0
    LaunchedEffect(session.id) { tasmee.session(session.id).collect { live = it } }
    LaunchedEffect(session.id) {
        tasmee.myBid(session.id).collect { bid ->
            myBid = bid
            if (!prepared || amount < atLeast()) {
                prepared = true
                amount = atLeast()
            }
        }
    }
    LaunchedEffect(amount) { haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }

    AqraSheet(onDismiss = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            TwoLineHeadline(stringResource(R.string.a_seat_by_auction), session.teacherName, size = 26f, alignCenter = false, modifier = Modifier.padding(top = 8.dp))
            if (auction != null) {
                AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                    Text(formatWhen(session.startsAt.toInstant()), style = aqraStyle(15f, Weight.heavy, Palette.ink))
                    Spacer(Modifier.height(8.dp))
                    Text(stringResource(R.string.n_seats_by_auction_n_bids, auction.seats, auction.bids), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
                    Spacer(Modifier.height(8.dp))
                    Text(stringResource(R.string.bidding_closes_s, formatRelativeAhead(auction.closesAt.toInstant())), style = aqraStyle(13f, Weight.bold, Palette.brand))
                }
            }
            myBid?.let { Standing(it) }
            AqraCard(Modifier.fillMaxWidth(), padding = 16.dp, radius = 24.dp) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                        StepButton(Icons.Rounded.Remove, enabled = amount > atLeast(), size = 46.dp) { if (amount > atLeast()) amount -= 1 }
                        Column(Modifier.widthIn(min = 150.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            AnimatedContent(amount, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "amount") { value ->
                                Text(formatNumber(value), style = aqraStyle(46f, Weight.heavy, Palette.brand))
                            }
                            Text(stringResource(if (amount == 0) R.string.credits_free_while_seats_remain else R.string.credits_2),
                                style = aqraStyle(12f, Weight.bold, Palette.inkSoft))
                        }
                        StepButton(Icons.Rounded.Add, enabled = true, size = 46.dp) { amount += 1 }
                    }
                    Text(stringResource(R.string.your_balance_s_credits, WalletStore.format(wallet.balance)), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                }
            }
            error?.let { BidErrorLine(it) }
            BrandButton(stringResource(if (myBid?.status == Bid.Status.ACTIVE) R.string.raise_my_bid else R.string.place_my_bid), height = 54.dp, fontSize = 17f,
                enabled = !working && auction?.isOpen() == true) {
                scope.launch {
                    working = true
                    error = null
                    try {
                        wallet.bid(amount, session, app.account.publicName ?: context.getString(R.string.a_student),
                            RevisionStore.memorizedPages(store, app.memorization).size, juzSummary(app, store))
                    } catch (failure: WalletStore.BidError) {
                        error = failure
                        if (failure is WalletStore.BidError.TooLow) amount = failure.atLeast
                    } finally {
                        working = false
                    }
                }
            }
            Text(stringResource(R.string.buy_credits), style = aqraStyle(15f, Weight.semibold, Palette.brand), textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().pressable { buying = true }.padding(6.dp))
            Text(stringResource(R.string.your_bid_holds_its_credits_if_someone_outbids_you_they), style = aqraStyle(12f, Weight.medium, Palette.inkSoft))
        }
    }
    if (buying) AqraSheet(onDismiss = { buying = false }) { WalletScreen(app) }
}

@Composable
private fun Standing(bid: Bid) {
    val (icon, title, tint) = when (bid.status) {
        Bid.Status.ACTIVE -> Triple("🟢", stringResource(R.string.your_bid_of_n_holds_a_seat, bid.amount), Palette.mint)
        Bid.Status.OUTBID -> Triple("🔔", stringResource(R.string.you_were_outbid), Palette.rose)
        Bid.Status.WON -> Triple("🎉", stringResource(R.string.you_won_a_seat), Palette.butter)
        Bid.Status.RELEASED -> Triple("↩️", stringResource(R.string.your_bid_was_released), Palette.lavender)
    }
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile(icon, tint, size = 40.dp)
            Text(title, style = aqraStyle(16f, Weight.heavy, Palette.ink))
        }
    }
}

@Composable
private fun BidErrorLine(error: WalletStore.BidError) {
    val text = when (error) {
        is WalletStore.BidError.TooLow -> pluralStringResource(R.plurals.a_bid_now_needs_at_least_n_credits, error.atLeast, error.atLeast)
        is WalletStore.BidError.NotEnoughCredits -> pluralStringResource(R.plurals.you_need_n_more_credits, error.needed, error.needed)
        WalletStore.BidError.Closed -> stringResource(R.string.bidding_has_closed_for_this_session)
        WalletStore.BidError.Failed -> stringResource(R.string.that_didnt_work_please_try_again)
    }
    Text(text, style = aqraStyle(13f, Weight.semibold, Palette.warning))
}

// MARK: - A teacher's earnings

/** What a teacher has earned from seats won in their sessions, what's been paid to them, and what's due. */
@Composable
fun EarningsScreen(app: AqraApp) {
    val wallet = app.account.wallet
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        TwoLineHeadline(stringResource(R.string.your_earnings), stringResource(R.string.from_seats_won), size = 28f, alignCenter = false,
            modifier = Modifier.padding(top = 8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            EarningsStat("🏦", Palette.butter, wallet.due, stringResource(R.string.due_to_you), Modifier.weight(1f))
            EarningsStat("🎓", Palette.mint, wallet.earned, stringResource(R.string.earned), Modifier.weight(1f))
            EarningsStat("✅", Palette.sky, wallet.paidOut, stringResource(R.string.paid), Modifier.weight(1f))
        }
        Text(stringResource(R.string.your_share_of_each_seat_won_by_bidding_after_the), style = aqraStyle(12f, Weight.medium, Palette.inkSoft))
        if (wallet.earnings.isNotEmpty()) {
            AqraSectionTitle(stringResource(R.string.history), Modifier.padding(top = 6.dp))
            LedgerList(wallet.earnings)
        }
    }
}

@Composable
private fun EarningsStat(icon: String, tint: Color, value: Double, label: String, modifier: Modifier) {
    AqraCard(modifier.semantics(mergeDescendants = true) {}, padding = 12.dp, radius = 20.dp) {
        IconTile(icon, tint, size = 32.dp)
        Spacer(Modifier.height(8.dp))
        Text(WalletStore.format(value), style = aqraStyle(20f, Weight.heavy, Palette.ink))
        Text(label, style = aqraStyle(11f, Weight.semibold, Palette.inkSoft))
    }
}
