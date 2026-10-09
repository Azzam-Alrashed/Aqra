package com.azzamalrashed.aqra.tasmee

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.account.Confirm
import com.azzamalrashed.aqra.account.Problem
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.credits.BidSheet
import com.azzamalrashed.aqra.credits.EarningsScreen
import com.azzamalrashed.aqra.credits.WalletStore
import com.azzamalrashed.aqra.social.Competition
import com.azzamalrashed.aqra.social.NewCompetitionScreen
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.FullScreen
import com.azzamalrashed.aqra.ui.LocalOverlays
import com.azzamalrashed.aqra.ui.Navigator
import com.azzamalrashed.aqra.ui.NavigatorHost
import com.azzamalrashed.aqra.ui.TabPage
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraProgress
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.ChipButton
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.ProblemLine
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumberList
import com.azzamalrashed.aqra.ui.util.formatRelative
import com.azzamalrashed.aqra.ui.util.formatWhen
import com.azzamalrashed.aqra.ui.util.factSeparator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Places in the tasmee' tab's navigation. */
sealed interface TasmeeDestination {
    data class TeacherPage(val teacher: Teacher) : TasmeeDestination
    data class SessionPage(val session: TasmeeSession) : TasmeeDestination
    data class StudentPage(val student: StudentFile) : TasmeeDestination
    data object History : TasmeeDestination
    data object Apply : TasmeeDestination
}

/** Where a session is held: its place, or the video call. */
@Composable
fun placeText(booking: Booking): String = if (booking.kind == TasmeeSession.Kind.VIDEO) stringResource(R.string.video_call) else booking.place

@Composable
fun placeText(session: TasmeeSession): String = placeText(Booking(session))

/**
 * التسميع: for a teacher, their profile, sessions and students; for everyone, the next tasmee' booked, reciting to or
 * hearing a friend, the vetted teachers to book with, what others heard, and the way to apply to teach.
 */
@Composable
fun TasmeeScreen(app: AqraApp, store: MushafStore, navigator: Navigator) {
    val overlays = LocalOverlays.current
    // A friend's code opened from a link or the camera.
    val code = app.router.peerCode
    LaunchedEffect(code) {
        if (code != null) {
            app.router.peerCode = null
            overlays.open(hearFriend(app, store, code))
        }
    }
    NavigatorHost(navigator, root = { TasmeeHome(app, store, navigator) }) { destination ->
        when (destination) {
            is TasmeeDestination.TeacherPage -> TeacherPage(app, store, destination.teacher)
            is TasmeeDestination.SessionPage -> SessionPage(app, store, destination.session, navigator)
            is TasmeeDestination.StudentPage -> StudentFilePage(app, store, destination.student)
            TasmeeDestination.History -> HistoryPage(app, store)
            TasmeeDestination.Apply -> TeacherApplicationPage(app)
        }
    }
}

/** The full-screen view of hearing a friend: their code, then the marking screen. */
fun hearFriend(app: AqraApp, store: MushafStore, code: String?) = FullScreen.Custom("hear-$code") { close -> HearFriendScreen(app, store, code, close) }

@Composable
private fun TasmeeHome(app: AqraApp, store: MushafStore, navigator: Navigator) {
    val tasmee = app.tasmee
    val overlays = LocalOverlays.current
    var creatingSession by remember { mutableStateOf(false) }
    var editingProfile by remember { mutableStateOf(false) }
    var reciting by remember { mutableStateOf(false) }
    var showingEarnings by remember { mutableStateOf(false) }
    var startingCompetition by remember { mutableStateOf(false) }
    LaunchedEffect(tasmee.uid) { tasmee.loadTeachers() }

    TabPage(top = 16.dp) {
        Text(stringResource(R.string.tasmee), style = aqraStyle(30f, Weight.heavy, Palette.ink))
        if (!AccountStore.isAvailable) {
            AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconTile("🎓", Palette.mint, size = 40.dp)
                    Text(stringResource(R.string.accounts_arent_set_up_in_this_build_so_teachers_and), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
                }
            }
            return@TabPage
        }
        if (tasmee.isTeacher) {
            TeacherSections(app, navigator, onNewSession = { creatingSession = true }, onEditProfile = { editingProfile = true },
                onEarnings = { showingEarnings = true }, onCompetition = { startingCompetition = true })
        }
        // The next booking in full, and any later ones as rows: a teacher may cancel any of them.
        val bookings = tasmee.upcomingBookings
        bookings.firstOrNull()?.let { booking ->
            AqraSectionTitle(stringResource(R.string.your_next_tasmee), Modifier.padding(top = 10.dp))
            BookingCard(app, booking)
        }
        if (bookings.size > 1) {
            AqraSectionTitle(stringResource(R.string.also_booked), Modifier.padding(top = 10.dp))
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                bookings.drop(1).forEachIndexed { index, booking ->
                    if (index > 0) AqraRowDivider()
                    BookingRow(app, booking)
                }
            }
        }
        AqraSectionTitle(stringResource(R.string.with_a_friend), Modifier.padding(top = 10.dp))
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            AqraRow("🗣️", Palette.peach, stringResource(R.string.recite_to_a_friend), Modifier.pressable(pressed = 1f) { reciting = true },
                detail = stringResource(R.string.they_mark_your_stumbles_on_their_phone))
            AqraRowDivider()
            AqraRow("👂", Palette.sky, stringResource(R.string.hear_a_friend), Modifier.pressable(pressed = 1f) { overlays.open(hearFriend(app, store, null)) },
                detail = stringResource(R.string.with_the_code_your_friend_shows_you))
        }
        AqraSectionTitle(stringResource(R.string.teachers), Modifier.padding(top = 10.dp))
        TeachersCard(app, navigator)
        if (tasmee.history.isNotEmpty()) {
            AqraSectionTitle(stringResource(R.string.what_others_heard), Modifier.padding(top = 10.dp))
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                tasmee.history.take(3).forEachIndexed { index, record ->
                    if (index > 0) AqraRowDivider()
                    TasmeeRecordRow(record, store)
                }
                AqraRowDivider()
                AqraRow("🗂️", Palette.lavender, stringResource(R.string.every_tasmee), Modifier.pressable(pressed = 1f) { navigator.push(TasmeeDestination.History) })
            }
        }
        if (!tasmee.isTeacher) {
            AqraCard(Modifier.fillMaxWidth().padding(top = 10.dp).pressable { navigator.push(TasmeeDestination.Apply) }, padding = 0.dp, radius = 24.dp) {
                AqraRow("📜", Palette.butter, stringResource(R.string.teach_on_aqra), detail = applicationLine(tasmee.application))
            }
        }
    }

    if (creatingSession) AqraSheet(onDismiss = { creatingSession = false }, fullHeight = false) { SessionEditor(app, null) { creatingSession = false } }
    if (editingProfile) AqraSheet(onDismiss = { editingProfile = false }, fullHeight = false) { TeacherProfileEditor(app) { editingProfile = false } }
    if (reciting) AqraSheet(onDismiss = { reciting = false }) { PeerRequestSheet(app) { reciting = false } }
    if (showingEarnings) AqraSheet(onDismiss = { showingEarnings = false }) { EarningsScreen(app) }
    if (startingCompetition) {
        AqraSheet(onDismiss = { startingCompetition = false }) {
            NewCompetitionScreen(app, listOf(Competition.Kind.TEACHER)) { startingCompetition = false }
        }
    }
}

@Composable
private fun applicationLine(application: TeacherApplication?): String = stringResource(when (application?.status) {
    null -> R.string.hold_an_ijazah_q_apply_to_hear_students
    TeacherApplication.Status.SUBMITTED -> R.string.your_application_is_waiting_for_review
    TeacherApplication.Status.INTERVIEW -> R.string.well_be_in_touch_for_your_interview
    TeacherApplication.Status.APPROVED -> R.string.approved
    TeacherApplication.Status.REJECTED -> R.string.your_application_wasnt_accepted
})

@Composable
private fun TeacherSections(
    app: AqraApp,
    navigator: Navigator,
    onNewSession: () -> Unit,
    onEditProfile: () -> Unit,
    onEarnings: () -> Unit,
    onCompetition: () -> Unit,
) {
    val tasmee = app.tasmee
    tasmee.teacherProfile?.let { profile ->
        AqraCard(Modifier.fillMaxWidth().padding(top = 4.dp), padding = 0.dp, radius = 24.dp) {
            AqraRow("🎓", Palette.mint, profile.name, Modifier.pressable(pressed = 1f, onClick = onEditProfile),
                detail = profile.about(factSeparator()) ?: stringResource(R.string.add_your_city_and_a_line_about_you)) { EditBadge() }
        }
    }
    AqraCard(Modifier.fillMaxWidth().pressable(onClick = onEarnings), padding = 0.dp, radius = 24.dp) {
        AqraRow("🏦", Palette.butter, stringResource(R.string.your_earnings),
            detail = stringResource(R.string.s_credits_due_to_you, WalletStore.format(app.account.wallet.due)))
    }
    AqraSectionTitle(stringResource(R.string.my_sessions), Modifier.padding(top = 10.dp))
    AqraCard(Modifier.fillMaxWidth(), animated = true, padding = 0.dp, radius = 24.dp) {
        for (session in tasmee.mySessions) {
            // The count first: a place name in the other script would otherwise reorder the line.
            AqraRow(if (session.kind == TasmeeSession.Kind.VIDEO) "🎥" else "📅", Palette.sky, formatWhen(session.startsAt.toInstant()),
                Modifier.pressable(pressed = 1f) { navigator.push(TasmeeDestination.SessionPage(session)) },
                detail = stringResource(R.string.n_of_n_seats, session.booked, session.seats) + factSeparator() + placeText(session))
            AqraRowDivider()
        }
        AqraRow("➕", Palette.butter, stringResource(R.string.new_session), Modifier.pressable(pressed = 1f, onClick = onNewSession)) {}
    }
    if (tasmee.myStudents.isNotEmpty()) {
        AqraSectionTitle(stringResource(R.string.my_students), Modifier.padding(top = 10.dp))
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            tasmee.myStudents.take(8).forEachIndexed { index, student ->
                if (index > 0) AqraRowDivider()
                AqraRow("🧑‍🎓", Palette.butter, student.name, Modifier.pressable(pressed = 1f) { navigator.push(TasmeeDestination.StudentPage(student)) },
                    detail = stringResource(R.string.last_heard_s, formatRelative(student.lastHeardAt.toInstant())))
            }
            AqraRowDivider()
            AqraRow("🏆", Palette.mint, stringResource(R.string.a_competition_for_my_students), Modifier.pressable(pressed = 1f, onClick = onCompetition),
                detail = stringResource(R.string.scored_from_the_pages_you_hear_clean))
        }
    }
}

@Composable
fun EditBadge() {
    Box(Modifier.size(30.dp).background(Palette.lavender, CircleShape), contentAlignment = Alignment.Center) {
        Icon(Icons.Rounded.Edit, null, tint = Palette.brand, modifier = Modifier.size(16.dp))
    }
}

/** A later booking: when (struck through once the teacher cancelled it), where, and giving the seat back. */
@Composable
private fun BookingRow(app: AqraApp, booking: Booking) {
    val live = app.tasmee.session(booking)
    val cancelled = live?.status == TasmeeSession.Status.CANCELLED
    var confirming by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<Problem?>(null) }
    val scope = rememberCoroutineScope()
    Column(Modifier.padding(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile(if (booking.kind == TasmeeSession.Kind.VIDEO) "🎥" else "🎓", if (cancelled) Palette.rose else Palette.mint, size = 38.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(booking.teacherName, style = aqraStyle(16f, Weight.heavy, Palette.ink))
                Text(formatWhen((live?.startsAt ?: booking.startsAt).toInstant()),
                    style = aqraStyle(12f, Weight.semibold, Palette.inkSoft).copy(textDecoration = if (cancelled) TextDecoration.LineThrough else null))
                // The place on a line of its own: a name in the other script would reorder the date's line.
                Text(if (cancelled) stringResource(R.string.cancelled_by_the_teacher) else placeText(live?.let(::Booking) ?: booking),
                    style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
            }
            ChipButton(stringResource(if (cancelled) R.string.remove else R.string.cancel_booking), filled = false) { confirming = true }
        }
        problem?.let { ProblemLine(it, Modifier.padding(top = 10.dp)) }
    }
    if (confirming) GiveBackSeat(app, booking, scope, onDismiss = { confirming = false }) { problem = it }
}

/**
 * «تلغي حجزك؟», then the seat given back, or the problem that stopped it. The work runs in the [scope] of the row or
 * card asking, which outlives the dialog.
 */
@Composable
private fun GiveBackSeat(app: AqraApp, booking: Booking, scope: CoroutineScope, onDismiss: () -> Unit, onResult: (Problem?) -> Unit) {
    Confirm(stringResource(R.string.cancel_your_booking_q), stringResource(R.string.your_seat_goes_back_to_the_session), stringResource(R.string.cancel_booking),
        onDismiss = onDismiss, cancel = stringResource(R.string.keep_it)) {
        scope.launch {
            onResult(
                try {
                    app.tasmee.cancelBooking(booking)
                    null
                } catch (error: Exception) {
                    AccountStore.problem(error)
                },
            )
        }
    }
}

/** The student's next booking: when and where, or that the teacher cancelled it, and giving the seat back. */
@Composable
private fun BookingCard(app: AqraApp, booking: Booking) {
    val live = app.tasmee.session(booking)
    val cancelled = live?.status == TasmeeSession.Status.CANCELLED
    var confirming by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<Problem?>(null) }
    val scope = rememberCoroutineScope()
    val overlays = LocalOverlays.current
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile(if (booking.kind == TasmeeSession.Kind.VIDEO) "🎥" else "🎓", if (cancelled) Palette.rose else Palette.mint, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(booking.teacherName, style = aqraStyle(17f, Weight.heavy, Palette.ink))
                Text(formatWhen((live?.startsAt ?: booking.startsAt).toInstant()),
                    style = aqraStyle(13f, Weight.bold, if (cancelled) Palette.inkSoft else Palette.brand).copy(textDecoration = if (cancelled) TextDecoration.LineThrough else null))
                Text(placeText(live?.let(::Booking) ?: booking), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                if (cancelled) Text(stringResource(R.string.the_teacher_cancelled_this_session), style = aqraStyle(12f, Weight.semibold, Palette.warning))
            }
            ChipButton(stringResource(if (cancelled) R.string.remove else R.string.cancel_booking), filled = false) { confirming = true }
        }
        if (booking.kind == TasmeeSession.Kind.VIDEO && live != null && !cancelled) {
            Spacer(Modifier.height(12.dp))
            CallButton(live, stringResource(R.string.join_the_call)) { overlays.open(studentCall(live)) }
        }
        problem?.let { ProblemLine(it, Modifier.padding(top = 12.dp)) }
    }
    if (confirming) GiveBackSeat(app, booking, scope, onDismiss = { confirming = false }) { problem = it }
}

@Composable
private fun TeachersCard(app: AqraApp, navigator: Navigator) {
    val tasmee = app.tasmee
    if (tasmee.teachers.isEmpty()) {
        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (tasmee.isLoadingTeachers) {
                    AqraProgress()
                    Text(stringResource(R.string.loading_teachers), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
                } else {
                    IconTile("🕌", Palette.lavender, size = 40.dp)
                    Text(stringResource(R.string.no_teachers_have_joined_yet), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
                }
            }
        }
    } else {
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            tasmee.teachers.forEachIndexed { index, teacher ->
                if (index > 0) AqraRowDivider()
                AqraRow("🎓", Palette.mint, teacher.name, Modifier.pressable(pressed = 1f) { navigator.push(TasmeeDestination.TeacherPage(teacher)) }, detail = teacher.about(factSeparator()))
            }
        }
    }
    tasmee.problem?.let { ProblemLine(it, Modifier.padding(horizontal = 6.dp)) }
}

// MARK: - A teacher, with sessions to book

/** A teacher's profile and the sessions they hold; a signed-in student books a seat here. */
@Composable
private fun TeacherPage(app: AqraApp, store: MushafStore, teacher: Teacher) {
    val tasmee = app.tasmee
    val account = app.account
    val signedIn = account.profile?.isAnonymous == false
    var sessions by remember { mutableStateOf<List<TasmeeSession>?>(null) }
    // This student's bids, by session: a student holds a free seat or a bid, not both.
    var myBids by remember { mutableStateOf<Map<String, Bid>>(emptyMap()) }
    var choosingFreeSeat by remember { mutableStateOf<TasmeeSession?>(null) }
    var working by remember { mutableStateOf<String?>(null) }
    var problem by remember { mutableStateOf<Problem?>(null) }
    val scope = rememberCoroutineScope()
    suspend fun load() {
        try {
            val loaded = tasmee.upcomingSessions(teacher.id)
            myBids = tasmee.myBids(loaded)
            sessions = loaded
        } catch (error: Exception) {
            problem = AccountStore.problem(error)
            sessions = sessions ?: emptyList()
        }
    }
    /** The student's bid in a session, while it holds a seat. */
    fun activeBid(session: TasmeeSession): Bid? = myBids[session.id]?.takeIf { it.status == Bid.Status.ACTIVE }
    LaunchedEffect(teacher.id) { load() }
    fun change(session: TasmeeSession, action: suspend () -> Unit) = scope.launch {
        working = session.id
        problem = null
        try {
            action()
            load()
        } catch (error: Exception) {
            problem = AccountStore.problem(error)
        } finally {
            working = null
        }
    }
    val studentName = account.publicName ?: stringResource(R.string.a_student)
    var bidding by remember { mutableStateOf<TasmeeSession?>(null) }
    bidding?.let { session ->
        BidSheet(app, store, session) {
            bidding = null
            scope.launch { load() }
        }
    }
    choosingFreeSeat?.let { session ->
        val held = activeBid(session)?.amount ?: 0
        Confirm(
            stringResource(R.string.book_a_free_seat_instead_q), pluralStringResource(R.plurals.your_bid_of_n_credits_is_let_go_and_its, held, held),
            stringResource(R.string.book_the_free_seat), onDismiss = { choosingFreeSeat = null }, cancel = stringResource(R.string.keep_my_bid),
            destructive = false,
        ) {
            change(session) { tasmee.takeFreeSeat(session, studentName, memorizedPages(app, store), juzSummary(app, store)) }
        }
    }

    TabPage(top = 16.dp) {
        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile("🎓", Palette.mint, size = 48.dp)
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(teacher.name, style = aqraStyle(22f, Weight.heavy, Palette.ink))
                    if (teacher.city.isNotEmpty()) Text(teacher.city, style = aqraStyle(13f, Weight.bold, Palette.brand))
                    if (teacher.line.isNotEmpty()) Text(teacher.line, style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                }
            }
        }
        AqraSectionTitle(stringResource(R.string.upcoming_sessions), Modifier.padding(top = 10.dp))
        val list = sessions
        when {
            list == null -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { AqraProgress() }
            list.isEmpty() -> Text(stringResource(R.string.no_sessions_scheduled_yet), style = aqraStyle(14f, Weight.medium, Palette.inkSoft), modifier = Modifier.padding(horizontal = 6.dp))
            else -> AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                list.forEachIndexed { index, session ->
                    if (index > 0) AqraRowDivider()
                    val booked = tasmee.hasBooked(session)
                    val seats = if (booked) stringResource(R.string.booked) else stringResource(R.string.seats_left_n, session.seatsLeft)
                    AqraRow(if (session.kind == TasmeeSession.Kind.VIDEO) "🎥" else "📅", Palette.sky, formatWhen(session.startsAt.toInstant()),
                        detail = seats + factSeparator() + placeText(session)) {
                        when {
                            working == session.id -> AqraProgress()
                            booked -> ChipButton(stringResource(R.string.cancel), filled = false) { change(session) { tasmee.cancelBooking(Booking(session)) } }
                            // A bidder takes the free seat instead from the auction's strip.
                            !signedIn || activeBid(session) != null -> Unit
                            session.isFull -> Text(stringResource(R.string.full), style = aqraStyle(13f, Weight.bold, Palette.inkSoft))
                            else -> ChipButton(stringResource(R.string.book), filled = true) {
                                change(session) { tasmee.book(session, studentName, memorizedPages(app, store), juzSummary(app, store)) }
                            }
                        }
                    }
                    // Once the student has a seat, the auction is no longer theirs to join.
                    val bid = activeBid(session)
                    session.auction?.takeIf { !booked && (it.isOpen() || bid != null) }?.let { auction ->
                        AuctionStrip(auction, bid, canBid = signedIn && auction.isOpen(),
                            canTakeFreeSeat = signedIn && bid != null && !session.isFull && working != session.id,
                            onBid = { bidding = session }, onFreeSeat = { choosingFreeSeat = session })
                    }
                }
            }
        }
        if (!signedIn && AccountStore.isAvailable) {
            AqraCard(Modifier.fillMaxWidth().padding(top = 10.dp), padding = 14.dp, radius = 24.dp) {
                Text(stringResource(R.string.sign_in_to_book_a_seat), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                Spacer(Modifier.height(12.dp))
                com.azzamalrashed.aqra.account.SignInButtons(app)
                account.problem?.let { ProblemLine(it, Modifier.padding(top = 10.dp)) }
            }
        }
        problem?.let { ProblemLine(it, Modifier.padding(horizontal = 6.dp)) }
    }
}

/**
 * A session's seats by auction: what a bid takes now, and «زايد»; with the student's bid, where it stands, and the
 * free seat to take instead.
 */
@Composable
private fun AuctionStrip(
    auction: TasmeeSession.Auction, bid: Bid?, canBid: Boolean, canTakeFreeSeat: Boolean, onBid: () -> Unit, onFreeSeat: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.width(38.dp), contentAlignment = Alignment.Center) { Text("🔨", style = aqraStyle(16f)) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(pluralStringResource(R.plurals.n_seats_by_auction, auction.seats, auction.seats), style = aqraStyle(13f, Weight.heavy, Palette.ink))
                Text(
                    when {
                        bid != null -> stringResource(R.string.your_bid_of_n_holds_a_seat, bid.amount)
                        auction.nextAtLeast == 0 -> stringResource(R.string.free_while_seats_remain)
                        else -> pluralStringResource(R.plurals.next_bid_from_n_credits, auction.nextAtLeast, auction.nextAtLeast)
                    },
                    style = aqraStyle(11f, Weight.semibold, if (bid != null) Palette.brand else Palette.inkSoft),
                )
            }
            if (canBid) ChipButton(stringResource(if (bid == null) R.string.bid else R.string.raise), filled = false, onClick = onBid)
        }
        if (canTakeFreeSeat) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                ChipButton(stringResource(R.string.book_a_free_seat_instead), filled = false, onClick = onFreeSeat)
            }
        }
    }
}

// What the teacher sees of the student: their name and what they've memorized.

fun memorizedPages(app: AqraApp, store: MushafStore) =
    com.azzamalrashed.aqra.revision.RevisionStore.memorizedPages(store, app.memorization).size

/** The juz' memorized in full, as numbers: «29, 30». */
fun juzSummary(app: AqraApp, store: MushafStore): String? {
    val full = (1..30).filter { juz -> store.juzAyahs[juz]?.let { app.memorization.memorizedCount(it) == it.count() } ?: false }
    return if (full.isEmpty()) null else full.joinToString(", ")
}

/** Where the student's memorization begins, if they said: the first page of their first whole juz'. */
fun startPage(seat: Seat, store: MushafStore): Int =
    seat.juzSummary?.split(",")?.firstOrNull()?.trim()?.toIntOrNull()?.let { store.juzStartPages[it] } ?: 1

@Composable
fun seatDetail(seat: Seat): String {
    val pages = pluralStringResource(R.plurals.n_pages, seat.memorizedPages, seat.memorizedPages)
    val summary = seat.juzSummary ?: return pages
    // The student's app writes the juz' as plain numbers, «29, 30»; they're shown in the teacher's language.
    val numbers = summary.split(",").mapNotNull { it.trim().toIntOrNull() }
    val juz = if (numbers.isEmpty()) summary else formatNumberList(numbers)
    return pages + factSeparator() + stringResource(R.string.juz_s, juz)
}
