package com.azzamalrashed.aqra.account

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.tasmee.TasmeeStore.Companion.dated
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query

/**
 * Messages from the server and the team, in the account: outbid, a seat won, a session cancelled and refunded, a
 * teacher's tasmee' recorded, the application to teach, a payout. Shown in the app.
 */
class InboxStore {
    data class Message(
        val id: String,
        val kind: Kind,
        val at: Moment,
        val read: Boolean,
        val teacherName: String,
        val amount: Int,
        val pages: Int,
        val status: String,
        val note: String,
    ) {
        enum class Kind(val raw: String, val icon: String) {
            OUTBID("outbid", "🔔"), WON("won", "🎉"), CANCELLED("cancelled", "📅"), REFUND("refund", "↩️"),
            TASMEE("tasmee", "🎓"), APPLICATION("application", "📜"), PAYOUT("payout", "🏦"),
        }
    }

    var messages: List<Message> by mutableStateOf(emptyList())
        private set
    val unread: Int get() = messages.count { !it.read }

    private var uid: String? = null
    private var listener: ListenerRegistration? = null

    private fun inbox(uid: String) = FirebaseFirestore.getInstance().collection("users").document(uid).collection("inbox")

    fun attach(uid: String) {
        if (uid == this.uid) return
        detach()
        this.uid = uid
        listener = inbox(uid).orderBy("at", Query.Direction.DESCENDING).limit(50).addSnapshotListener { snapshot, _ ->
            messages = snapshot?.documents.orEmpty().mapNotNull { document ->
                val data = dated(document.data)
                val kind = Message.Kind.entries.firstOrNull { it.raw == data["kind"] } ?: return@mapNotNull null
                Message(
                    id = document.id, kind = kind, at = data["at"] as? Moment ?: Moment.DISTANT_PAST, read = data["readAt"] is Moment,
                    teacherName = data["teacherName"] as? String ?: "", amount = (data["amount"] as? Number)?.toInt() ?: 0,
                    pages = (data["pages"] as? Number)?.toInt() ?: 0, status = data["status"] as? String ?: "", note = data["note"] as? String ?: "",
                )
            }
        }
    }

    fun detach() {
        listener?.remove()
        listener = null
        uid = null
        messages = emptyList()
    }

    fun markAllRead() {
        val uid = uid ?: return
        for (message in messages) if (!message.read) inbox(uid).document(message.id).update("readAt", Timestamp.now())
    }

    fun delete(message: Message) {
        val uid = uid ?: return
        inbox(uid).document(message.id).delete()
    }
}
