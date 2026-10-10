package com.azzamalrashed.aqra.account

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraProgress
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipButton
import com.azzamalrashed.aqra.ui.components.ProblemLine
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// MARK: - Reporting and blocking

/**
 * Someone shown to the student by name, in a place they can be reported from: a teacher's page, a call, a friend, a
 * competition's standings, a teacher's student. As on iOS.
 */
data class PersonRef(val uid: String, val name: String, val context: PersonReport.Context, val contextId: String? = null) {
    /** The name as shown, never empty. */
    val shownName: String get() = name.ifEmpty { "—" }
}

/**
 * A report to Aqra's team about someone's name, words or conduct (docs/SRS.md SAF-01). The person reported isn't told;
 * the team reads reports with `npm run admin -- reports`.
 */
data class PersonReport(val person: PersonRef, val reason: Reason, val note: String) {
    enum class Context(val raw: String) { TEACHER("teacher"), STUDENT("student"), CALL("call"), FRIEND("friend"), COMPETITION("competition") }

    enum class Reason(val raw: String, val icon: String) {
        INAPPROPRIATE("inappropriate", "🚫"), ABUSE("abuse", "😠"), SPAM("spam", "📢"), OTHER("other", "💬"),
    }

    companion object {
        /** What Firestore keeps of a note: the rules take at most a thousand characters. */
        const val NOTE_LIMIT = 1000
    }

    /** The report's fields as the rules take them, but its date, which the server sets. */
    fun fields(reporter: String): Map<String, Any> = buildMap {
        put("reporter", reporter)
        put("subject", person.uid)
        put("subjectName", person.name.take(100))
        put("context", person.context.raw)
        put("reason", reason.raw)
        person.contextId?.let { put("contextId", it.take(128)) }
        note.trim().takeIf { it.isNotEmpty() }?.let { put("note", it.take(NOTE_LIMIT)) }
    }
}

@Serializable
data class BlockedPerson(val uid: String, val name: String)

/**
 * The people this student blocked, kept on the device (docs/SRS.md SAF-02): a blocked teacher's sessions leave the
 * list, a blocked friend stops being a friend, and a blocked name in a competition's standings is hidden. Kept under
 * the same name the iOS app uses.
 */
class SafetyStore(private val read: () -> String?, private val write: (String) -> Unit) {
    var blocked by mutableStateOf(read()?.let { runCatching { Json.decodeFromString<List<BlockedPerson>>(it) }.getOrNull() }.orEmpty())
        private set

    fun isBlocked(uid: String) = blocked.any { it.uid == uid }

    fun block(person: PersonRef) {
        if (isBlocked(person.uid)) return
        blocked = blocked + BlockedPerson(person.uid, person.name)
        save()
    }

    fun unblock(uid: String) {
        blocked = blocked.filterNot { it.uid == uid }
        save()
    }

    /** Sends a report to the team; offline, it says so rather than waits. */
    suspend fun send(report: PersonReport, reporter: String) {
        val document = report.fields(reporter) + ("createdAt" to FieldValue.serverTimestamp())
        withTimeout(SERVER_TIMEOUT) { FirebaseFirestore.getInstance().collection("reports").add(document).await() }
    }

    private fun save() = write(Json.encodeToString(blocked))

    companion object {
        const val KEY = "safety.blocked"
    }
}

// MARK: - The menu beside a name

/** «…» beside a name: report the person, block or unblock them, and whatever else the row offers first. */
@Composable
fun PersonMenu(
    app: AqraApp,
    person: PersonRef,
    canBlock: Boolean = true,
    onBlock: (PersonRef) -> Unit = {},
    extra: @Composable (close: () -> Unit) -> Unit = {},
) {
    val safety = app.account.safety
    var open by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf(false) }
    var confirmingBlock by remember { mutableStateOf(false) }
    val more = stringResource(R.string.more)
    Box {
        // Drawn at 30 points, tapped at 44.
        Box(Modifier.size(44.dp).pressable(pressed = 0.9f) { open = true }.semantics { contentDescription = more }, contentAlignment = Alignment.Center) {
            Box(Modifier.size(30.dp).background(Palette.lavender, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.MoreHoriz, null, tint = Palette.inkSoft, modifier = Modifier.size(18.dp))
            }
        }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = Color.White) {
            extra { open = false }
            DropdownMenuItem(text = { Text(stringResource(R.string.report), style = aqraStyle(15f, Weight.semibold)) }, onClick = {
                open = false
                reporting = true
            })
            if (canBlock) {
                if (safety.isBlocked(person.uid)) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.unblock), style = aqraStyle(15f, Weight.semibold)) }, onClick = {
                        open = false
                        safety.unblock(person.uid)
                    })
                } else {
                    DropdownMenuItem(text = { Text(stringResource(R.string.block), style = aqraStyle(15f, Weight.semibold, Palette.danger)) }, onClick = {
                        open = false
                        confirmingBlock = true
                    })
                }
            }
        }
    }
    if (reporting) ReportSheet(app, person, onBlock = onBlock) { reporting = false }
    if (confirmingBlock) BlockConfirm(app, person, onDismiss = { confirmingBlock = false }, onBlock = onBlock)
}

/** «أتحظر فلانًا؟», then blocks. */
@Composable
fun BlockConfirm(app: AqraApp, person: PersonRef, onDismiss: () -> Unit, onBlock: (PersonRef) -> Unit = {}) {
    Confirm(stringResource(R.string.block_s_q, person.shownName),
        stringResource(R.string.you_wont_see_their_sessions_their_name_or_their_scores_2), stringResource(R.string.block),
        onDismiss = onDismiss) {
        app.account.safety.block(person)
        onBlock(person)
    }
}

// MARK: - The report sheet

/** «الإبلاغ»: why, a word more if the student wants, and whether to block the person too; then a thank-you. */
@Composable
fun ReportSheet(app: AqraApp, person: PersonRef, onBlock: (PersonRef) -> Unit = {}, onDismiss: () -> Unit) {
    val safety = app.account.safety
    val scope = rememberCoroutineScope()
    var reason by remember { mutableStateOf<PersonReport.Reason?>(null) }
    var note by remember { mutableStateOf("") }
    var alsoBlock by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var sent by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<Problem?>(null) }
    val wasBlocked = remember { safety.isBlocked(person.uid) }

    fun send() {
        val chosen = reason ?: return
        val reporter = app.account.profile?.uid ?: run { problem = Problem.FAILED; return }
        sending = true
        problem = null
        scope.launch {
            try {
                safety.send(PersonReport(person, chosen, note), reporter)
                if (alsoBlock) safety.block(person)
                sent = true
            } catch (error: Exception) {
                problem = AccountStore.problem(error)
            } finally {
                sending = false
            }
        }
    }

    // What the screen does once someone is blocked (closing a teacher's page) waits for the thank-you to close.
    fun close() {
        if (sent && alsoBlock) onBlock(person)
        onDismiss()
    }

    AqraSheet(onDismiss = { if (!sending) close() }) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(top = 8.dp, bottom = 24.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (sent) {
                Column(Modifier.fillMaxWidth().padding(top = 30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("🤍", style = aqraStyle(52f, Weight.medium))
                    Text(stringResource(R.string.thank_you), style = aqraStyle(26f, Weight.heavy, Palette.ink))
                    Text(stringResource(R.string.the_team_will_look_into_it), style = aqraStyle(14f, Weight.semibold, Palette.inkSoft))
                    if (alsoBlock) {
                        Text(stringResource(R.string.s_is_blocked_you_can_unblock_them_in_account, person.shownName),
                            style = aqraStyle(13f, Weight.semibold, Palette.inkSoft), textAlign = TextAlign.Center)
                    }
                }
                Spacer(Modifier.height(18.dp))
                BrandButton(stringResource(R.string.done), onClick = ::close)
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.report_s, person.shownName), style = aqraStyle(26f, Weight.heavy, Palette.ink),
                        modifier = Modifier.semantics { heading() })
                    Text(stringResource(R.string.aqras_team_reads_every_report_s_isnt_told_who_sent, person.shownName),
                        style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
                }
                AqraSectionTitle(stringResource(R.string.what_happened_q), Modifier.padding(top = 6.dp))
                AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                    PersonReport.Reason.entries.forEachIndexed { index, choice ->
                        if (index > 0) AqraRowDivider()
                        val chosen = reason == choice
                        AqraRow(choice.icon, Palette.lavender, reasonTitle(choice),
                            Modifier.pressable(pressed = 1f) { reason = choice }.semantics { selected = chosen }) {
                            Icon(if (chosen) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null,
                                tint = if (chosen) Palette.brand else Palette.lavender, modifier = Modifier.size(24.dp))
                        }
                    }
                }
                AqraTextField(note, { note = it.take(PersonReport.NOTE_LIMIT) }, stringResource(R.string.anything_that_helps_the_team_optional),
                    singleLine = false)
                if (!wasBlocked) {
                    AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                        AqraRow("✋", Palette.rose, stringResource(R.string.block_s_too, person.shownName),
                            detail = stringResource(R.string.you_wont_see_their_sessions_their_name_or_their_scores)) {
                            AqraSwitch(alsoBlock) { alsoBlock = it }
                        }
                    }
                }
                problem?.let { ProblemLine(it, Modifier.padding(horizontal = 6.dp)) }
                Box(Modifier.fillMaxWidth().padding(top = 6.dp), contentAlignment = Alignment.Center) {
                    if (sending) AqraProgress() else BrandButton(stringResource(R.string.send_report), enabled = reason != null, onClick = ::send)
                }
            }
        }
    }
}

@Composable
private fun reasonTitle(reason: PersonReport.Reason): String = stringResource(when (reason) {
    PersonReport.Reason.INAPPROPRIATE -> R.string.inappropriate_name_words_or_picture
    PersonReport.Reason.ABUSE -> R.string.abuse_or_harassment
    PersonReport.Reason.SPAM -> R.string.spam_or_a_scam
    PersonReport.Reason.OTHER -> R.string.something_else
})

// MARK: - The people blocked

/** «المحظورون» in Account: everyone blocked on this device, each with «إلغاء الحظر». */
@Composable
fun BlockedPeopleSheet(app: AqraApp, onDismiss: () -> Unit) {
    val safety = app.account.safety
    AqraSheet(onDismiss = onDismiss) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(top = 8.dp, bottom = 24.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(R.string.blocked), style = aqraStyle(28f, Weight.heavy, Palette.ink), modifier = Modifier.semantics { heading() })
            Text(stringResource(R.string.you_dont_see_their_sessions_their_names_or_their_scores), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
            if (safety.blocked.isEmpty()) {
                AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                    Text(stringResource(R.string.no_one_is_blocked), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
                }
            } else {
                AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                    safety.blocked.forEachIndexed { index, person ->
                        if (index > 0) AqraRowDivider()
                        AqraRow("✋", Palette.rose, person.name.ifEmpty { "—" }) {
                            ChipButton(stringResource(R.string.unblock), filled = false) { safety.unblock(person.uid) }
                        }
                    }
                }
            }
        }
    }
}

/** «المحظورون»: how many, for the row in Account. */
@Composable
fun blockedCount(count: Int): String = pluralStringResource(R.plurals.n_people, count, count)
