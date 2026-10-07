package com.azzamalrashed.aqra.credits

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.tasmee.TasmeeSession
import com.azzamalrashed.aqra.tasmee.TasmeeStore.Companion.dated
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.QuerySnapshot
import com.google.firebase.functions.FirebaseFunctionsException
import kotlinx.coroutines.tasks.await
import java.text.NumberFormat
import kotlin.math.roundToLong

/**
 * Credits: held for bids and spent on seats won. The wallet and its ledger are written only by the server. For a
 * teacher, also their earnings from won seats and the payouts made to them.
 *
 * Credits are bought as App Store purchases in the iOS app, which the server verifies; Google Play purchases aren't
 * verified by the server yet, so this app shows the balance and bids with it but doesn't sell credits.
 */
class WalletStore {
    data class Entry(val id: String, val kind: Kind, val amount: Double, val at: Moment) {
        enum class Kind(val raw: String) {
            PURCHASE("purchase"), HOLD("hold"), RELEASE("release"), SPEND("spend"), REFUND("refund"), SEAT("seat"),
            REVERSAL("reversal"), PAYOUT("payout"),
        }
    }

    var balance by mutableStateOf(0.0)
        private set
    var held by mutableStateOf(0.0)
        private set
    var ledger: List<Entry> by mutableStateOf(emptyList())
        private set
    /** A teacher's earnings: earned and paid out, and the entries behind them. */
    var earned by mutableStateOf(0.0)
        private set
    var paidOut by mutableStateOf(0.0)
        private set
    var earnings: List<Entry> by mutableStateOf(emptyList())
        private set

    private var uid: String? = null
    private var isNamed = false
    private val listeners = ArrayList<ListenerRegistration>()

    private val database: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    /** The balance due to a teacher. */
    val due: Double get() = maxOf(earned - paidOut, 0.0)

    // MARK: - The account in use

    fun attach(uid: String, named: Boolean) {
        // An anonymous account has no wallet; once it's signed in (the same uid), the wallet opens.
        if (uid == this.uid && named == isNamed) return
        detach()
        this.uid = uid
        isNamed = named
        if (!named) return
        val wallet = database.collection("wallets").document(uid)
        listeners += wallet.addSnapshotListener { snapshot, _ ->
            balance = (snapshot?.get("balance") as? Number)?.toDouble() ?: 0.0
            held = (snapshot?.get("held") as? Number)?.toDouble() ?: 0.0
        }
        listeners += wallet.collection("ledger").orderBy("at", Query.Direction.DESCENDING).limit(50).addSnapshotListener { snapshot, _ ->
            ledger = entries(snapshot)
        }
        val teacher = database.collection("teacherBalances").document(uid)
        listeners += teacher.addSnapshotListener { snapshot, _ ->
            earned = (snapshot?.get("earned") as? Number)?.toDouble() ?: 0.0
            paidOut = (snapshot?.get("paidOut") as? Number)?.toDouble() ?: 0.0
        }
        listeners += teacher.collection("entries").orderBy("at", Query.Direction.DESCENDING).limit(100).addSnapshotListener { snapshot, _ ->
            earnings = entries(snapshot)
        }
    }

    fun detach() {
        listeners.forEach { it.remove() }
        listeners.clear()
        uid = null
        isNamed = false
        balance = 0.0
        held = 0.0
        ledger = emptyList()
        earned = 0.0
        paidOut = 0.0
        earnings = emptyList()
    }

    private fun entries(snapshot: QuerySnapshot?): List<Entry> = snapshot?.documents.orEmpty().mapNotNull { document ->
        val data = dated(document.data)
        val kind = Entry.Kind.entries.firstOrNull { it.raw == data["kind"] } ?: return@mapNotNull null
        val at = data["at"] as? Moment ?: return@mapNotNull null
        Entry(document.id, kind, (data["amount"] as? Number)?.toDouble() ?: 0.0, at)
    }

    // MARK: - Bidding

    data class BidOutcome(val amount: Int, val nextAtLeast: Int)

    sealed class BidError : Exception() {
        /** The bid must be at least this. */
        data class TooLow(val atLeast: Int) : BidError()
        data class NotEnoughCredits(val needed: Int) : BidError()
        data object Closed : BidError()
        data object Failed : BidError()
    }

    /** Bids for an auctioned seat, holding the credits; the server decides, in one transaction. */
    suspend fun bid(amount: Int, session: TasmeeSession, name: String, memorizedPages: Int, juzSummary: String?): BidOutcome {
        val data = buildMap<String, Any> {
            put("sessionId", session.id)
            put("amount", amount)
            put("name", name)
            put("memorizedPages", memorizedPages)
            juzSummary?.let { put("juzSummary", it) }
        }
        try {
            val result = AccountStore.functions.getHttpsCallable("placeBid").call(data).await()
            val response = result.getData() as? Map<*, *>
            return BidOutcome(amount, (response?.get("nextAtLeast") as? Number)?.toInt() ?: (amount + 1))
        } catch (error: FirebaseFunctionsException) {
            val details = error.details as? Map<*, *>
            (details?.get("atLeast") as? Number)?.let { throw BidError.TooLow(it.toInt()) }
            (details?.get("needed") as? Number)?.let { throw BidError.NotEnoughCredits(it.toInt()) }
            if (error.code == FirebaseFunctionsException.Code.FAILED_PRECONDITION) throw BidError.Closed
            throw BidError.Failed
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (_: Exception) {
            throw BidError.Failed
        }
    }

    companion object {
        /** Credits as they're written: whole credits plainly, a teacher's share with its fraction. */
        fun format(value: Double): String = NumberFormat.getNumberInstance().apply {
            val whole = (value * 100).roundToLong() % 100 == 0L
            minimumFractionDigits = if (whole) 0 else 2
            maximumFractionDigits = if (whole) 0 else 2
        }.format(value)
    }
}
