package com.azzamalrashed.aqra.account

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumber
import com.azzamalrashed.aqra.ui.util.formatRelative
import com.azzamalrashed.aqra.ui.util.formatWhen

/** The bell on the home: messages from the server and the team, newest first. */
@Composable
fun InboxButton(app: AqraApp) {
    val inbox = app.account.inbox
    var open by remember { mutableStateOf(false) }
    val label = stringResource(R.string.messages)
    val unread = inbox.unread
    val state = if (unread > 0) stringResource(R.string.n_unread, unread) else ""
    Box(
        Modifier.size(38.dp).softShadow(CircleShape, radius = 8.dp, y = 4.dp).background(Color.White, CircleShape)
            .pressable { open = true }.semantics { contentDescription = label; stateDescription = state },
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Rounded.Notifications, null, tint = Palette.brand, modifier = Modifier.size(19.dp))
        AnimatedVisibility(unread > 0, Modifier.align(Alignment.TopEnd).offset(x = 3.dp, y = (-3).dp), enter = scaleIn(), exit = scaleOut()) {
            Box(Modifier.size(17.dp).background(Color(0xFFD0505A), CircleShape), contentAlignment = Alignment.Center) {
                Text(formatNumber(minOf(unread, 9)), style = aqraStyle(10f, Weight.heavy, Color.White))
            }
        }
    }
    if (open) AqraSheet(onDismiss = { open = false }) { InboxScreen(app) }
}

/** Messages from the server and the team; they're marked read once seen. */
@Composable
private fun InboxScreen(app: AqraApp) {
    val inbox = app.account.inbox
    DisposableEffect(Unit) { onDispose { inbox.markAllRead() } }
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(R.string.messages), style = aqraStyle(28f, Weight.heavy, Palette.ink), modifier = Modifier.padding(top = 8.dp))
        if (inbox.messages.isEmpty()) {
            Text(stringResource(R.string.nothing_new), style = aqraStyle(15f, Weight.medium, Palette.inkSoft))
        } else {
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                inbox.messages.forEachIndexed { index, message ->
                    if (index > 0) AqraRowDivider()
                    MessageRow(app, message)
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageRow(app: AqraApp, message: InboxStore.Message) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().combinedClickable(onLongClick = { menu = true }, onClick = {}).padding(14.dp),
            verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile(message.kind.icon, if (message.read) Palette.lavender else Palette.butter, size = 38.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(messageText(app, message), style = aqraStyle(15f, if (message.read) Weight.semibold else Weight.heavy, Palette.ink))
                if (message.note.isNotEmpty()) Text(message.note, style = aqraStyle(12f, Weight.medium, Palette.inkSoft))
                Text(formatRelative(message.at.toInstant()), style = aqraStyle(11f, Weight.semibold, Palette.inkSoft))
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.delete), style = aqraStyle(15f, Weight.semibold, Palette.danger)) },
                onClick = { menu = false; app.account.inbox.delete(message) })
        }
    }
}

@Composable
private fun messageText(app: AqraApp, message: InboxStore.Message): String = when (message.kind) {
    InboxStore.Message.Kind.OUTBID -> stringResource(R.string.you_were_outbid_in_s_s_session_your_n_credits, message.teacherName, message.amount)
    InboxStore.Message.Kind.WON -> stringResource(R.string.you_won_a_seat_in_s_s_session, message.teacherName)
    InboxStore.Message.Kind.CANCELLED, InboxStore.Message.Kind.REFUND -> cancellation(app, message)
    InboxStore.Message.Kind.TASMEE -> stringResource(R.string.s_recorded_your_tasmee_of_n_pages, message.teacherName, message.pages)
    InboxStore.Message.Kind.APPLICATION -> stringResource(
        when (message.status) {
            "interview" -> R.string.your_application_to_teach_was_reviewed_the_team_will_be
            "approved" -> R.string.your_application_to_teach_was_approved_welcome
            "rejected" -> R.string.your_application_to_teach_wasnt_accepted
            else -> R.string.your_application_to_teach_was_updated
        },
    )
    InboxStore.Message.Kind.PAYOUT -> pluralStringResource(R.plurals.a_payout_of_n_credits_was_sent_to_you, message.amount, message.amount)
}

/**
 * A cancelled session, named by its day and time: the server sends its start, and older messages find it among the
 * bookings. Credits held or paid for it are back.
 */
@Composable
private fun cancellation(app: AqraApp, message: InboxStore.Message): String {
    val startsAt = message.startsAt ?: app.tasmee.startOfBooked(message.sessionId)
        ?: return if (message.amount > 0) stringResource(R.string.s_cancelled_a_session_your_n_credits_are_back, message.teacherName, message.amount)
        else stringResource(R.string.s_cancelled_a_session_you_were_in, message.teacherName)
    val time = formatWhen(startsAt.toInstant())
    return if (message.amount > 0) stringResource(R.string.s_cancelled_their_session_on_s_your_n_credits_are, message.teacherName, time, message.amount)
    else stringResource(R.string.s_cancelled_their_session_on_s, message.teacherName, time)
}
