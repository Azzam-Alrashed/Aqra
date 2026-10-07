package com.azzamalrashed.aqra.tasmee

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AqraTextField
import com.azzamalrashed.aqra.account.Confirm
import com.azzamalrashed.aqra.account.aqraTimePickerColors
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.FullScreen
import com.azzamalrashed.aqra.ui.LocalOverlays
import com.azzamalrashed.aqra.ui.Navigator
import com.azzamalrashed.aqra.ui.TabPage
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraChevron
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.AqraSegmented
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.arabicDigits
import com.azzamalrashed.aqra.ui.util.formatDay
import com.azzamalrashed.aqra.ui.util.formatNumber
import com.azzamalrashed.aqra.ui.util.formatRelative
import com.azzamalrashed.aqra.ui.util.formatWhen
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.withTimeoutOrNull

// MARK: - A session, new or edited

/** A teacher schedules a session, or changes one: when, in person (where) or by video, and how many seats. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionEditor(app: AqraApp, session: TasmeeSession?, onDone: () -> Unit) {
    val zone = ZoneId.systemDefault()
    // Tomorrow, on the hour.
    val suggested = remember { ZonedDateTime.now(zone).plusDays(1).truncatedTo(ChronoUnit.HOURS) }
    var startsAt by remember { mutableStateOf(session?.startsAt?.toInstant()?.atZone(zone) ?: suggested) }
    var kind by remember { mutableStateOf(session?.kind ?: TasmeeSession.Kind.IN_PERSON) }
    var place by remember { mutableStateOf(session?.place.orEmpty()) }
    var seats by remember { mutableIntStateOf(session?.seats ?: 5) }
    var auctionSeats by remember { mutableIntStateOf(0) }
    var minBid by remember { mutableIntStateOf(0) }
    var pickingDate by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf(false) }
    // A session's seats can't go below the students who already booked.
    val minimumSeats = maxOf(session?.booked ?: 0, 1)
    val isValid = kind == TasmeeSession.Kind.VIDEO || place.isNotBlank()

    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 24.dp).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text(stringResource(if (session == null) R.string.new_session else R.string.edit_session), style = aqraStyle(26f, Weight.heavy, Palette.ink))
        if (session == null) {
            AqraSegmented(kind, listOf(TasmeeSession.Kind.IN_PERSON to stringResource(R.string.in_person), TasmeeSession.Kind.VIDEO to stringResource(R.string.video)), { kind = it })
        }
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            FieldRow(stringResource(R.string.`when`)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ValueChip(formatDay(startsAt.toInstant())) { pickingDate = true }
                    ValueChip(com.azzamalrashed.aqra.ui.util.formatTime(startsAt.hour, startsAt.minute)) { pickingTime = true }
                }
            }
            if (kind == TasmeeSession.Kind.IN_PERSON) {
                AqraRowDivider(start = 14.dp)
                FieldRow(stringResource(R.string.place)) {
                    AqraTextField(place, { place = it }, stringResource(R.string.place), Modifier.widthIn(max = 220.dp))
                }
            }
            AqraRowDivider(start = 14.dp)
            FieldRow(stringResource(R.string.seats)) {
                Stepper(seats, canLower = seats > minimumSeats, canRaise = seats < 30) { seats = (seats + it).coerceIn(minimumSeats, 30) }
            }
        }
        if (session == null) {
            AqraCard(Modifier.fillMaxWidth(), animated = true, padding = 0.dp, radius = 24.dp) {
                FieldRow(stringResource(R.string.seats_by_auction)) {
                    Stepper(auctionSeats, canLower = auctionSeats > 0, canRaise = auctionSeats < 20) { auctionSeats = (auctionSeats + it).coerceIn(0, 20) }
                }
                if (auctionSeats > 0) {
                    AqraRowDivider(start = 14.dp)
                    FieldRow(stringResource(R.string.lowest_bid)) {
                        Stepper(minBid, canLower = minBid > 0, canRaise = minBid < 100) { minBid = (minBid + it).coerceIn(0, 100) }
                    }
                }
            }
            if (auctionSeats > 0) {
                Text(stringResource(R.string.beside_the_free_seats_these_go_to_the_highest_bids), style = aqraStyle(12f, Weight.medium, Palette.inkSoft),
                    modifier = Modifier.padding(horizontal = 6.dp))
            }
        }
        if (kind == TasmeeSession.Kind.VIDEO) {
            Text(stringResource(R.string.students_who_book_join_the_call_from_the_sessions_page), style = aqraStyle(12f, Weight.medium, Palette.inkSoft),
                modifier = Modifier.padding(horizontal = 6.dp))
        }
        BrandButton(stringResource(if (session == null) R.string.create else R.string.save), enabled = isValid && startsAt.toInstant().isAfter(Instant.now())) {
            val moment = Moment.of(startsAt.toInstant())
            if (session != null) {
                app.tasmee.updateSession(session.copy(startsAt = moment, place = if (kind == TasmeeSession.Kind.VIDEO) "" else place.trim(), seats = maxOf(seats, minimumSeats)))
            } else {
                app.tasmee.createSession(moment, kind, place.trim(), seats, auctionSeats, minBid)
            }
            onDone()
        }
    }

    if (pickingDate) {
        // A session can't be set in the past.
        val today = remember { LocalDate.now(zone) }
        val state = rememberDatePickerState(
            initialSelectedDateMillis = startsAt.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate() >= today
                override fun isSelectableYear(year: Int) = year >= today.year
            },
        )
        DatePickerDialog(onDismissRequest = { pickingDate = false }, confirmButton = {
            TextButton({
                state.selectedDateMillis?.let {
                    val date = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                    startsAt = ZonedDateTime.of(date, startsAt.toLocalTime(), zone)
                }
                pickingDate = false
            }) { Text(stringResource(R.string.done), style = aqraStyle(15f, Weight.bold, Palette.brand)) }
        }) { DatePicker(state) }
    }
    if (pickingTime) {
        val state = rememberTimePickerState(startsAt.hour, startsAt.minute)
        androidx.compose.material3.AlertDialog(onDismissRequest = { pickingTime = false }, containerColor = Color.White, text = { TimePicker(state, colors = aqraTimePickerColors()) },
            confirmButton = {
                TextButton({
                    startsAt = ZonedDateTime.of(startsAt.toLocalDate(), LocalTime.of(state.hour, state.minute), zone)
                    pickingTime = false
                }) { Text(stringResource(R.string.done), style = aqraStyle(15f, Weight.bold, Palette.brand)) }
            })
    }
}

@Composable
private fun FieldRow(label: String, control: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = aqraStyle(15f, Weight.bold, Palette.ink), modifier = Modifier.weight(1f))
        control()
    }
}

@Composable
private fun ValueChip(text: String, onClick: () -> Unit) {
    Box(Modifier.background(Palette.lavender, CircleShape).pressable(onClick = onClick).padding(horizontal = 12.dp, vertical = 7.dp)) {
        Text(text, style = aqraStyle(14f, Weight.bold, Palette.brand), maxLines = 1)
    }
}

/** A number between a minus and a plus, each repeating while held; [onStep] gets −1 or +1. */
@Composable
private fun Stepper(value: Int, canLower: Boolean, canRaise: Boolean, onStep: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        RoundStep(Icons.Rounded.Remove, "−", canLower) { onStep(-1) }
        Text(formatNumber(value), style = aqraStyle(17f, Weight.heavy, Palette.ink), textAlign = TextAlign.Center, modifier = Modifier.widthIn(min = 28.dp))
        RoundStep(Icons.Rounded.Add, "+", canRaise) { onStep(1) }
    }
}

@Composable
private fun RoundStep(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean, onStep: () -> Unit) {
    val step by rememberUpdatedState(onStep)
    Box(
        Modifier
            .size(34.dp)
            .background(Palette.lavender, CircleShape)
            .semantics {
                role = Role.Button
                contentDescription = label
                if (enabled) onClick { step(); true } else disabled()
            }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                awaitEachGesture {
                    awaitFirstDown()
                    step()
                    // Held down, it repeats, faster after a moment.
                    var wait = 450L
                    while (true) {
                        val ended = withTimeoutOrNull(wait) {
                            waitForUpOrCancellation()
                            true
                        }
                        if (ended == true) break
                        step()
                        wait = 90L
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = if (enabled) Palette.brand else Palette.inkSoft.copy(alpha = 0.4f), modifier = Modifier.size(18.dp))
    }
}

// MARK: - A teacher's session

/** One of the teacher's sessions: when and where, and the students who booked, each opening the marking screen. */
@Composable
fun SessionPage(app: AqraApp, store: MushafStore, session: TasmeeSession, navigator: Navigator) {
    val tasmee = app.tasmee
    val overlays = LocalOverlays.current
    var seats by remember { mutableStateOf(emptyList<Seat>()) }
    var editing by remember { mutableStateOf(false) }
    var confirmingCancel by remember { mutableStateOf(false) }
    var bids by remember { mutableStateOf(emptyList<Bid>()) }
    // The session as it is now; the one navigated to is only a snapshot.
    val live = tasmee.mySessions.firstOrNull { it.id == session.id } ?: session
    LaunchedEffect(session.id) { tasmee.seats(session.id).collect { seats = it } }
    LaunchedEffect(session.id) { if (session.auction != null) tasmee.bids(session.id).collect { bids = it } }

    TabPage(top = 16.dp) {
        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile(if (live.kind == TasmeeSession.Kind.VIDEO) "🎥" else "📅", Palette.sky, size = 44.dp)
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(formatWhen(live.startsAt.toInstant()), style = aqraStyle(19f, Weight.heavy, Palette.ink))
                    Text(placeText(live), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
                    Text(stringResource(R.string.n_of_n_seats, seats.size, live.seats), style = aqraStyle(13f, Weight.bold, Palette.brand))
                    live.auction?.let { auction ->
                        val count = if (auction.state == TasmeeSession.Auction.State.SETTLED) auction.won else auction.bids
                        Text(stringResource(R.string.n_seats_by_auction_n_bids, auction.seats, count), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                    }
                }
            }
            if (live.kind == TasmeeSession.Kind.VIDEO) {
                Spacer(Modifier.height(12.dp))
                CallButton(live, stringResource(R.string.start_the_call)) { overlays.open(teacherCall(app, store, live)) }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(stringResource(R.string.edit), style = aqraStyle(13f, Weight.bold, Palette.brand), modifier = Modifier.pressable { editing = true })
                Text(stringResource(R.string.cancel_session), style = aqraStyle(13f, Weight.bold, Palette.danger), modifier = Modifier.pressable { confirmingCancel = true })
            }
        }
        if (live.auction != null && bids.isNotEmpty()) {
            AqraSectionTitle(stringResource(R.string.bids), Modifier.padding(top = 10.dp))
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                bids.forEachIndexed { index, bid ->
                    if (index > 0) AqraRowDivider()
                    val holding = bid.status == Bid.Status.ACTIVE || bid.status == Bid.Status.WON
                    AqraRow(when (bid.status) { Bid.Status.WON -> "🎉"; Bid.Status.ACTIVE -> "🔨"; else -> "↩️" }, Palette.butter, bid.name, detail = bidStatus(bid)) {
                        Text(pluralStringResource(R.plurals.n_credits, bid.amount, bid.amount), style = aqraStyle(14f, Weight.heavy, if (holding) Palette.brand else Palette.inkSoft))
                    }
                }
            }
        }
        AqraSectionTitle(stringResource(R.string.students), Modifier.padding(top = 10.dp))
        if (seats.isEmpty()) {
            Text(stringResource(R.string.no_one_has_booked_a_seat_yet), style = aqraStyle(14f, Weight.medium, Palette.inkSoft), modifier = Modifier.padding(horizontal = 6.dp))
        } else {
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                seats.forEachIndexed { index, seat ->
                    if (index > 0) AqraRowDivider()
                    val detail = seatDetail(seat)
                    AqraRow("🧑‍🎓", Palette.butter, seat.name, Modifier.pressable(pressed = 1f) {
                        overlays.open(FullScreen.Custom("mark-${seat.id}") { close ->
                            TasmeeMarkingScreen(app, store, seat.name, startPage(seat, store), allowsStageTest = true, onClose = close) { result ->
                                tasmee.recordTasmee(seat, live, result.pages, result.stumbles, result.mistakes, result.test)
                            }
                        })
                    }, detail = detail)
                }
            }
            Text(stringResource(R.string.tap_a_student_to_hear_them_mark_the_ayat_they), style = aqraStyle(12f, Weight.medium, Palette.inkSoft),
                modifier = Modifier.padding(horizontal = 6.dp))
        }
    }
    if (editing) AqraSheet(onDismiss = { editing = false }, fullHeight = false) { SessionEditor(app, live) { editing = false } }
    if (confirmingCancel) {
        Confirm(stringResource(R.string.cancel_this_session_q), stringResource(R.string.the_students_who_booked_will_see_it_cancelled), stringResource(R.string.cancel_session),
            onDismiss = { confirmingCancel = false }, cancel = stringResource(R.string.keep_it)) {
            tasmee.cancelSession(live)
            navigator.pop()
        }
    }
}

@Composable
private fun bidStatus(bid: Bid): String = stringResource(when (bid.status) {
    Bid.Status.ACTIVE -> R.string.holding_a_seat
    Bid.Status.OUTBID -> R.string.outbid
    Bid.Status.WON -> R.string.won_a_seat
    Bid.Status.RELEASED -> R.string.released
})

// MARK: - The teacher's profile

/** The teacher's name, city and line, as students see them. */
@Composable
fun TeacherProfileEditor(app: AqraApp, onDone: () -> Unit) {
    val profile = app.tasmee.teacherProfile
    var name by remember { mutableStateOf(profile?.name.orEmpty()) }
    var city by remember { mutableStateOf(profile?.city.orEmpty()) }
    var line by remember { mutableStateOf(profile?.line.orEmpty()) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(R.string.your_teacher_profile), style = aqraStyle(26f, Weight.heavy, Palette.ink))
        AqraTextField(name, { name = it }, stringResource(R.string.name))
        AqraTextField(city, { city = it }, stringResource(R.string.city))
        AqraTextField(line, { line = it }, stringResource(R.string.ijazah_riwayah_halaqah))
        BrandButton(stringResource(R.string.save), Modifier.padding(top = 6.dp), enabled = name.isNotBlank()) {
            app.tasmee.updateTeacherProfile(name.trim(), city.trim(), line.trim())
            onDone()
        }
    }
}

// MARK: - A student's file

/** A teacher's file on one student: what the teacher heard from them, and the teacher's own notes. */
@Composable
fun StudentFilePage(app: AqraApp, store: MushafStore, student: StudentFile) {
    val tasmee = app.tasmee
    var records by remember { mutableStateOf(emptyList<TasmeeRecord>()) }
    val saved = tasmee.myStudents.firstOrNull { it.id == student.id }?.notes ?: student.notes
    var notes by remember { mutableStateOf(saved) }
    LaunchedEffect(student.id) { tasmee.records(student.id).collect { records = it } }
    // The notes are kept as the teacher types, and when they leave the page.
    val latest by androidx.compose.runtime.rememberUpdatedState(notes)
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { if (latest != saved) tasmee.saveNotes(latest, student.id) }
    }
    LaunchedEffect(notes) {
        kotlinx.coroutines.delay(800)
        if (notes != saved) tasmee.saveNotes(notes, student.id)
    }

    TabPage(top = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(student.name, style = aqraStyle(28f, Weight.heavy, Palette.ink))
            Text(stringResource(R.string.last_heard_s, formatRelative(student.lastHeardAt.toInstant())), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
        }
        if (records.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Stat("📖", Palette.sky, formatNumber(records.flatMap { it.pages }.toSet().size), stringResource(R.string.pages_heard), Modifier.weight(1f))
                Stat("🎯", Palette.rose, formatNumber(records.sumOf { it.stumbles.size }), stringResource(R.string.stumbles), Modifier.weight(1f))
                Stat("🗓️", Palette.mint, formatNumber(records.size), stringResource(R.string.tasmee), Modifier.weight(1f))
            }
        }
        AqraSectionTitle(stringResource(R.string.notes), Modifier.padding(top = 10.dp))
        AqraTextField(notes, { notes = it }, stringResource(R.string.what_to_work_on_next_time), singleLine = false)
        AqraSectionTitle(stringResource(R.string.what_you_heard), Modifier.padding(top = 10.dp))
        if (records.isEmpty()) {
            Text(stringResource(R.string.nothing_recorded_yet), style = aqraStyle(14f, Weight.medium, Palette.inkSoft), modifier = Modifier.padding(horizontal = 6.dp))
        } else {
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                records.forEachIndexed { index, record ->
                    if (index > 0) AqraRowDivider()
                    TasmeeRecordRow(record, store, showsListener = false)
                }
            }
        }
    }
}

@Composable
private fun Stat(icon: String, tint: Color, value: String, label: String, modifier: Modifier) {
    AqraCard(modifier, padding = 12.dp, radius = 20.dp) {
        IconTile(icon, tint, size = 32.dp)
        Spacer(Modifier.height(8.dp))
        FittedText(value, aqraStyle(20f, Weight.heavy, Palette.ink), alignCenter = false)
        Spacer(Modifier.height(8.dp))
        FittedText(label, aqraStyle(11f, Weight.semibold, Palette.inkSoft), alignCenter = false, minScale = 0.8f)
    }
}

// MARK: - What others heard

/** Every tasmee' others heard from the student: teachers and friends, newest first. */
@Composable
fun HistoryPage(app: AqraApp, store: MushafStore) {
    val history = app.tasmee.history
    TabPage(top = 16.dp) {
        Text(stringResource(R.string.every_tasmee), style = aqraStyle(28f, Weight.heavy, Palette.ink))
        val verified = history.count { it.kind == TasmeeRecord.Kind.SHEIKH }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Stat("🎓", Palette.mint, formatNumber(verified), stringResource(R.string.with_a_teacher), Modifier.weight(1f))
            Stat("🤝", Palette.peach, formatNumber(history.size - verified), stringResource(R.string.with_a_friend), Modifier.weight(1f))
            Stat("📖", Palette.sky, formatNumber(history.flatMap { it.pages }.toSet().size), stringResource(R.string.pages_heard), Modifier.weight(1f))
        }
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            history.forEachIndexed { index, record ->
                if (index > 0) AqraRowDivider()
                TasmeeRecordRow(record, store)
            }
        }
    }
}

/** One tasmee' in a list: who heard it, when, how much and how it went. Tapping it opens the details. */
@Composable
fun TasmeeRecordRow(record: TasmeeRecord, store: MushafStore, showsListener: Boolean = true) {
    var showing by remember { mutableStateOf(false) }
    val peer = record.kind == TasmeeRecord.Kind.PEER
    val title = when {
        record.test != null -> stringResource(R.string.stage_n_test, record.test.stage)
        showsListener -> record.teacherName.ifEmpty { stringResource(R.string.a_friend) }
        else -> formatDay(record.at.toInstant())
    }
    val counts = pluralStringResource(R.plurals.n_pages, record.pages.toSet().size, record.pages.toSet().size) + " · " +
        pluralStringResource(R.plurals.n_stumbles, record.stumbles.size, record.stumbles.size)
    val detail = if (showsListener || record.test != null) formatRelative(record.at.toInstant()) + " · " + counts else counts
    AqraRow(if (peer) "🤝" else "🎓", if (peer) Palette.peach else Palette.mint, title, Modifier.pressable(pressed = 1f) { showing = true }, detail = detail) {
        val passed = record.passesTest
        if (passed != null) {
            Box(Modifier.height(26.dp).background(if (passed) Palette.mint else Palette.rose, CircleShape).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                Text(stringResource(if (passed) R.string.passed else R.string.not_yet), style = aqraStyle(12f, Weight.bold, if (passed) Palette.success else Palette.warning))
            }
        } else {
            AqraChevron()
        }
    }
    if (showing) AqraSheet(onDismiss = { showing = false }) { RecordDetails(record, store, showsListener) }
}

/** A tasmee' in full: the pages heard, and each stumble with its surah, ayah and kind. */
@Composable
private fun RecordDetails(record: TasmeeRecord, store: MushafStore, showsListener: Boolean) {
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(when {
                record.test != null -> stringResource(R.string.stage_n_test, record.test.stage)
                record.kind == TasmeeRecord.Kind.PEER -> stringResource(R.string.tasmee_with_a_friend)
                else -> stringResource(R.string.tasmee_with_a_teacher)
            }, style = aqraStyle(26f, Weight.heavy, Palette.ink))
            val time = formatWhen(record.at.toInstant())
            Text(if (showsListener && record.teacherName.isNotEmpty()) record.teacherName + " · " + time else time, style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
        }
        val test = record.test
        val passed = record.passesTest
        if (test != null && passed != null) {
            AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconTile(if (passed) "🏅" else "🌱", if (passed) Palette.butter else Palette.mint, size = 40.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(stringResource(if (passed) R.string.the_test_was_passed else R.string.not_passed_yet), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                        Text(stringResource(R.string.n_mistakes_n_allowed_per_page_heard, record.stumbles.size, test.allowedMistakesPerPage), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                    }
                }
            }
        }
        AqraSectionTitle(stringResource(R.string.pages_heard))
        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Text(pagesLine(record, store), style = aqraStyle(14f, Weight.semibold, Palette.ink))
        }
        if (record.stumbles.isNotEmpty()) {
            AqraSectionTitle(stringResource(R.string.stumbles), Modifier.padding(top = 6.dp))
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                record.stumbles.forEachIndexed { index, ayah ->
                    if (index > 0) AqraRowDivider()
                    val (surah, number) = store.reference(ayah)
                    AqraRow("🎯", Palette.rose, "${store.surahNames[surah].orEmpty()} ${arabicDigits(number)}", detail = mistakeTitle(record.mistakeType(ayah))) {}
                }
            }
        }
    }
}

/** «البقرة: ٢–٣ · آل عمران: ٥٠»: the pages heard, grouped by the surah each starts in. */
private fun pagesLine(record: TasmeeRecord, store: MushafStore): String {
    val groups = ArrayList<Pair<Int, MutableList<Int>>>()
    for (page in record.pages.toSortedSet()) {
        val surah = store.page(page).surah
        val last = groups.lastOrNull()
        if (last != null && last.first == surah && last.second.last() == page - 1) last.second += page else groups += surah to mutableListOf(page)
    }
    return groups.joinToString(" · ") { (surah, pages) ->
        val range = if (pages.size > 1) "${arabicDigits(pages.first())}–${arabicDigits(pages.last())}" else arabicDigits(pages.first())
        "${store.surahNames[surah].orEmpty()}: $range"
    }
}

@Composable
fun mistakeTitle(type: MistakeType): String = stringResource(when (type) {
    MistakeType.MEMORIZATION -> R.string.memorization_error
    MistakeType.FORGETTING -> R.string.forgot
    MistakeType.PROMPTING -> R.string.needed_prompting
    MistakeType.HESITATION -> R.string.hesitated
    MistakeType.LAHN -> R.string.clear_error
    MistakeType.TAJWEED -> R.string.tajweed
})
