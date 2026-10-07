package com.azzamalrashed.aqra.tasmee

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.CallEnd
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MicOff
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material.icons.rounded.VideocamOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.account.findActivity
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.FullScreen
import com.azzamalrashed.aqra.ui.components.AqraProgress
import com.azzamalrashed.aqra.ui.components.ChipButton
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.functions.FirebaseFunctionsException
import io.livekit.android.LiveKit
import io.livekit.android.renderer.TextureViewRenderer
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.participant.RemoteParticipant
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.VideoTrack
import io.livekit.android.util.flow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import livekit.org.webrtc.RendererCommon
import java.io.IOException

/**
 * A video session's live call: one LiveKit room per session, joined with a token only the server issues — to the
 * session's teacher, or a student holding a seat in it, within the call's window (backend/functions/src/video.ts).
 */
class CallModel(context: Context, val sessionId: String) {
    sealed interface Phase {
        data object Idle : Phase
        data object Joining : Phase
        data object Joined : Phase
        /** Couldn't join: not yet open, closed, no seat, or no connection. */
        data class Failed(val problem: CallProblem) : Phase
    }

    val room: Room = LiveKit.create(context.applicationContext)
    var phase: Phase by mutableStateOf(Phase.Idle)
        private set
    var isTeacher by mutableStateOf(false)
        private set
    /** The teacher's uid, to put their video first for students. */
    var teacherId: String? by mutableStateOf(null)
        private set
    var microphoneOn by mutableStateOf(true)
        private set
    var cameraOn by mutableStateOf(true)
        private set

    companion object {
        /** When a session's call can be joined: from a quarter of an hour before it starts until three hours after. */
        fun isOpen(session: TasmeeSession, at: Moment = Moment.now()): Boolean =
            session.kind == TasmeeSession.Kind.VIDEO && session.status == TasmeeSession.Status.OPEN &&
                at >= session.startsAt + (-15 * 60.0) && at <= session.startsAt + 3 * 3_600.0
    }

    suspend fun join() {
        if (phase == Phase.Joining || phase == Phase.Joined) return
        phase = Phase.Joining
        try {
            val result = AccountStore.functions.getHttpsCallable("joinCall").call(mapOf("sessionId" to sessionId)).await()
            val data = result.getData() as? Map<*, *>
            val url = data?.get("url") as? String
            val token = data?.get("token") as? String
            if (url == null || token == null) {
                phase = Phase.Failed(CallProblem.FAILED)
                return
            }
            isTeacher = data["isTeacher"] as? Boolean ?: false
            teacherId = data["teacherId"] as? String
            room.connect(reachable(url), token)
            phase = Phase.Joined
            // Without a camera (or permission for it) the call goes on with audio.
            cameraOn = enable { room.localParticipant.setCameraEnabled(true) }
            microphoneOn = enable { room.localParticipant.setMicrophoneEnabled(true) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            android.util.Log.w("Aqra", "Couldn't join the call of $sessionId", error)
            phase = Phase.Failed(CallProblem.of(error))
        }
    }

    suspend fun toggleMicrophone() {
        val on = !microphoneOn
        if (enable { room.localParticipant.setMicrophoneEnabled(on) }) microphoneOn = on
    }

    suspend fun toggleCamera() {
        val on = !cameraOn
        if (enable { room.localParticipant.setCameraEnabled(on) }) cameraOn = on
    }

    /** Leaves the call and lets go of the camera, the microphone and the connection. */
    fun close() {
        room.disconnect()
        room.release()
        phase = Phase.Idle
    }

    /** Whether turning a track on or off worked; a missing permission or device only means it didn't. */
    private suspend fun enable(change: suspend () -> Boolean): Boolean = try {
        change()
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        false
    }

    /** The emulators' LiveKit server runs on the computer, which the Android emulator reaches at 10.0.2.2. */
    private fun reachable(url: String): String =
        if (AccountStore.usesEmulator) url.replace("://127.0.0.1", "://10.0.2.2").replace("://localhost", "://10.0.2.2") else url
}

/** Why a call couldn't be joined, in words the student understands. */
enum class CallProblem {
    NOT_OPEN_YET, CLOSED, NO_SEAT, OFFLINE, FAILED;

    companion object {
        fun of(error: Throwable): CallProblem = when (error) {
            is FirebaseFunctionsException -> when (error.code) {
                // The server says when the call opens if it hasn't yet.
                FirebaseFunctionsException.Code.FAILED_PRECONDITION -> if ((error.details as? Map<*, *>)?.get("opensAt") != null) NOT_OPEN_YET else CLOSED
                FirebaseFunctionsException.Code.PERMISSION_DENIED, FirebaseFunctionsException.Code.NOT_FOUND -> NO_SEAT
                FirebaseFunctionsException.Code.UNAVAILABLE, FirebaseFunctionsException.Code.DEADLINE_EXCEEDED -> OFFLINE
                else -> FAILED
            }
            is FirebaseNetworkException, is IOException -> OFFLINE
            else -> FAILED
        }
    }
}

@Composable
private fun CallProblem.message(): String = stringResource(when (this) {
    CallProblem.NOT_OPEN_YET -> R.string.the_call_opens_a_quarter_of_an_hour_before_the
    CallProblem.CLOSED -> R.string.this_call_has_closed
    CallProblem.NO_SEAT -> R.string.only_students_with_a_seat_join_this_call
    CallProblem.OFFLINE -> R.string.you_need_an_internet_connection_for_this
    CallProblem.FAILED -> R.string.that_didnt_work_please_try_again
})

/** The call's own colors: a deep plum stage, whatever the app's theme. */
private object CallColors {
    val stage = Color(0xFF1B1426)
    val tile = Color(0xFF2E2440)
    val leave = Color(0xFFD93A3A)
}

// MARK: - Joining

/** The time now, brought up to date every [seconds]. */
@Composable
private fun rememberNow(seconds: Long): State<Moment> = produceState(Moment.now()) {
    while (true) {
        delay(seconds * 1_000)
        value = Moment.now()
    }
}

/**
 * «انضم إلى المكالمة» on a student's booked video session, or «ابدأ المكالمة» on a teacher's, while its call is open;
 * before then, when it opens.
 */
@Composable
fun CallButton(session: TasmeeSession, title: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val now by rememberNow(30)
    val open = CallModel.isOpen(session, now)
    val color = if (open) Color.White else Palette.inkSoft
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .background(if (open) Palette.brand else Palette.lavender, CircleShape)
            .clip(CircleShape)
            .pressable(enabled = open, pressed = 0.97f, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        Icon(Icons.Rounded.Videocam, null, tint = color, modifier = Modifier.size(20.dp))
        Text(if (open) title else stringResource(R.string.the_call_opens_15_minutes_before), style = aqraStyle(15f, Weight.bold, color), maxLines = 1)
    }
}

/** The student's call, full screen over the tabs. */
fun studentCall(session: TasmeeSession) = FullScreen.Custom("call-${session.id}") { close -> StudentCallScreen(session, close) }

/** The teacher's call, full screen over the tabs. */
fun teacherCall(app: AqraApp, store: MushafStore, session: TasmeeSession) =
    FullScreen.Custom("call-${session.id}") { close -> TeacherCallScreen(app, store, session, close) }

/**
 * A call for as long as the screen shows it: the camera and microphone asked for first (the call goes on without
 * them), then joined; left when the screen goes.
 */
@Composable
private fun rememberCall(sessionId: String): CallModel {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val call = remember(sessionId) { CallModel(context, sessionId) }
    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { scope.launch { call.join() } }
    LaunchedEffect(call) {
        val missing = CALL_PERMISSIONS.filterNot { context.isGranted(it) }
        if (missing.isEmpty()) call.join() else permissions.launch(missing.toTypedArray())
    }
    DisposableEffect(call) { onDispose { call.close() } }
    return call
}

private val CALL_PERMISSIONS = listOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)

private fun Context.isGranted(permission: String) = ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

// MARK: - The student's call

/** The student's side of a video tasmee': the teacher large, the others in a strip, their own picture small. */
@Composable
private fun StudentCallScreen(session: TasmeeSession, onClose: () -> Unit) {
    val call = rememberCall(session.id)
    CallStage(call, session.teacherName, onLeave = onClose)
}

// MARK: - The teacher's call

/**
 * The teacher's side: everyone in the call, and the students who booked; tapping one opens the marking screen with
 * their video floating over the Mushaf.
 */
@Composable
private fun TeacherCallScreen(app: AqraApp, store: MushafStore, session: TasmeeSession, onClose: () -> Unit) {
    val call = rememberCall(session.id)
    var seats by remember { mutableStateOf(emptyList<Seat>()) }
    var hearing by remember { mutableStateOf<Seat?>(null) }
    LaunchedEffect(session.id) { app.tasmee.seats(session.id).collect { seats = it } }

    Box(Modifier.fillMaxSize()) {
        CallStage(call, stringResource(R.string.your_students), onLeave = onClose, darkBars = hearing == null) {
            if (seats.isNotEmpty()) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    for (seat in seats) {
                        Row(
                            Modifier.heightIn(min = 38.dp).background(Color.White, CircleShape).clip(CircleShape)
                                .pressable { hearing = seat }.padding(horizontal = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(Icons.AutoMirrored.Rounded.MenuBook, null, tint = Palette.brand, modifier = Modifier.size(16.dp))
                            Text(seat.name, style = aqraStyle(13f, Weight.bold, Palette.brand), maxLines = 1)
                        }
                    }
                }
            }
        }
        hearing?.let { seat ->
            TasmeeMarkingScreen(app, store, seat.name, startPage(seat, store), allowsStageTest = true, onClose = { hearing = null }, overlay = {
                ParticipantTile(call.room, seat.id, seat.name,
                    Modifier.size(120.dp, 160.dp).softShadow(RoundedCornerShape(18.dp), strength = 1.2f).clip(RoundedCornerShape(18.dp)))
            }) { result ->
                app.tasmee.recordTasmee(seat, session, result.pages, result.stumbles, result.mistakes, result.test)
            }
        }
    }
}

// MARK: - The call's stage

/**
 * Everyone in a call: the teacher (or, for the teacher, the first student) large, the rest in a strip, the caller's
 * own picture in the corner, and the microphone, camera and leave controls.
 */
@Composable
private fun CallStage(call: CallModel, title: String, onLeave: () -> Unit, darkBars: Boolean = true, footer: @Composable () -> Unit = {}) {
    val room = call.room
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val remote by room::remoteParticipants.flow.collectAsState()
    /** The others in the call, the teacher first. */
    val others = remote.values.sortedWith(compareBy<RemoteParticipant> { if (it.identity?.value == call.teacherId) 0 else 1 }.thenBy { it.name.orEmpty() })
    val phase = call.phase

    BackHandler(onBack = onLeave)
    if (darkBars) LightBarIcons()
    KeepScreenOn()

    Box(Modifier.fillMaxSize().background(CallColors.stage)) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                // Boxed, so a name in the other script still starts at the reading edge.
                Box(Modifier.weight(1f)) { Text(title, style = aqraStyle(17f, Weight.heavy, Color.White), maxLines = 1) }
                Text("${others.size + 1}", style = aqraStyle(13f, Weight.bold, Color.White.copy(alpha = 0.7f)))
                Icon(Icons.Rounded.Groups, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp))
            }

            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (phase) {
                    CallModel.Phase.Idle, CallModel.Phase.Joining -> Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        AqraProgress(color = Color.White)
                        Text(stringResource(R.string.joining_the_call), style = aqraStyle(15f, Weight.medium, Color.White.copy(alpha = 0.8f)))
                    }
                    is CallModel.Phase.Failed -> Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Text("📵", fontSize = 48.sp)
                        Text(phase.problem.message(), style = aqraStyle(15f, Weight.semibold, Color.White), textAlign = TextAlign.Center)
                        ChipButton(stringResource(R.string.try_again), filled = true) { scope.launch { call.join() } }
                    }
                    CallModel.Phase.Joined -> {
                        val first = others.firstOrNull()
                        if (first != null) {
                            key(first.sid) {
                                ParticipantView(room, first, null, Modifier.fillMaxSize().padding(horizontal = 12.dp).clip(RoundedCornerShape(28.dp)))
                            }
                        } else {
                            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text("🕌", fontSize = 48.sp)
                                Text(stringResource(if (call.isTeacher) R.string.waiting_for_your_students else R.string.waiting_for_the_teacher),
                                    style = aqraStyle(15f, Weight.semibold, Color.White.copy(alpha = 0.85f)))
                            }
                        }
                        LocalPreview(room, call.cameraOn, Modifier.align(Alignment.BottomEnd).padding(24.dp).size(104.dp, 140.dp)
                            .clip(RoundedCornerShape(18.dp)).border(1.dp, Color.White.copy(alpha = 0.4f), RoundedCornerShape(18.dp)))
                    }
                }
            }

            if (others.size > 1) {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (participant in others.drop(1)) {
                        key(participant.sid) {
                            ParticipantView(room, participant, null, Modifier.size(96.dp, 128.dp).clip(RoundedCornerShape(16.dp)))
                        }
                    }
                }
            }

            footer()

            if (phase == CallModel.Phase.Joined && CALL_PERMISSIONS.any { !context.isGranted(it) }) {
                Text(stringResource(R.string.video_calls_need_camera_and_microphone), style = aqraStyle(12f, Weight.semibold, Color.White.copy(alpha = 0.75f)),
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).pressable(pressed = 1f) { openAppSettings(context) })
            }

            Row(Modifier.fillMaxWidth().padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically) {
                CallControl(if (call.microphoneOn) Icons.Rounded.Mic else Icons.Rounded.MicOff, stringResource(R.string.microphone), call.microphoneOn) {
                    scope.launch { call.toggleMicrophone() }
                }
                CallControl(if (call.cameraOn) Icons.Rounded.Videocam else Icons.Rounded.VideocamOff, stringResource(R.string.camera), call.cameraOn) {
                    scope.launch { call.toggleCamera() }
                }
                val leave = stringResource(R.string.leave_the_call)
                Box(Modifier.size(64.dp).background(CallColors.leave, CircleShape).clip(CircleShape).pressable(onClick = onLeave)
                    .semantics { contentDescription = leave }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.CallEnd, null, tint = Color.White, modifier = Modifier.size(28.dp))
                }
            }
        }
    }
}

@Composable
private fun CallControl(icon: ImageVector, label: String, active: Boolean, onClick: () -> Unit) {
    val state = stringResource(if (active) R.string.on else R.string.off)
    Box(
        Modifier.size(56.dp).background(if (active) Color.White.copy(alpha = 0.18f) else Color.White, CircleShape).clip(CircleShape).pressable(onClick = onClick)
            .semantics { contentDescription = label; stateDescription = state },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = if (active) Color.White else CallColors.stage, modifier = Modifier.size(24.dp))
    }
}

/** The call is dark: light status and navigation bar icons while it shows, and the app's own dark ones after. */
@Composable
private fun LightBarIcons() {
    val view = LocalView.current
    DisposableEffect(Unit) {
        val window = view.context.findActivity()?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.isAppearanceLightStatusBars = false
        controller?.isAppearanceLightNavigationBars = false
        onDispose {
            controller?.isAppearanceLightStatusBars = true
            controller?.isAppearanceLightNavigationBars = true
        }
    }
}

/** The screen stays on through the call, as it would in any call. */
@Composable
private fun KeepScreenOn() {
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
}

private fun openAppSettings(context: Context) {
    runCatching {
        context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
    }
}

// MARK: - The people in it

/** Someone by their uid: their video once they're in the call, and that they aren't until then. */
@Composable
fun ParticipantTile(room: Room, identity: String, name: String, modifier: Modifier = Modifier) {
    val remote by room::remoteParticipants.flow.collectAsState()
    val shown = remote.values.firstOrNull { it.identity?.value == identity }
    if (shown != null) {
        key(shown.sid) { ParticipantView(room, shown, name, modifier) }
    } else {
        Box(modifier.background(CallColors.tile), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Initial(name)
                Text(stringResource(R.string.not_in_the_call), style = aqraStyle(11f, Weight.semibold, Color.White.copy(alpha = 0.7f)))
            }
        }
    }
}

/** One person in the call, redrawn as their tracks come and go: their camera, or their initial when it's off. */
@Composable
private fun ParticipantView(room: Room, participant: Participant, name: String?, modifier: Modifier) {
    val videos by participant::videoTrackPublications.flow.collectAsState()
    val microphoneOn by participant::isMicrophoneEnabled.flow.collectAsState()
    val liveName by participant::name.flow.collectAsState()
    val shownName = name ?: liveName.orEmpty()
    val track = videos.firstOrNull { (publication, track) -> publication.source == Track.Source.CAMERA && !publication.muted && track is VideoTrack }
        ?.second as? VideoTrack
    Box(modifier.background(CallColors.tile)) {
        if (track != null) {
            VideoView(room, track, mirror = false, Modifier.fillMaxSize())
        } else {
            Box(Modifier.align(Alignment.Center)) { Initial(shownName) }
        }
        Row(
            Modifier.align(Alignment.BottomStart).padding(8.dp).background(Color.Black.copy(alpha = 0.35f), CircleShape).padding(PaddingValues(horizontal = 8.dp, vertical = 4.dp)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (!microphoneOn) Icon(Icons.Rounded.MicOff, null, tint = Color.White, modifier = Modifier.size(12.dp))
            Text(shownName, style = aqraStyle(12f, Weight.bold, Color.White), maxLines = 1)
        }
    }
}

@Composable
private fun Initial(name: String, size: Dp = 56.dp) {
    Box(Modifier.size(size).background(Palette.brand, CircleShape), contentAlignment = Alignment.Center) {
        Text(name.take(1), style = aqraStyle(28f, Weight.heavy, Color.White))
    }
}

/** The caller's own camera, mirrored as in a mirror. */
@Composable
private fun LocalPreview(room: Room, cameraOn: Boolean, modifier: Modifier) {
    val videos by room.localParticipant::videoTrackPublications.flow.collectAsState()
    val track = videos.firstOrNull { (publication, track) -> publication.source == Track.Source.CAMERA && track is VideoTrack }?.second as? VideoTrack
    Box(modifier.background(CallColors.tile), contentAlignment = Alignment.Center) {
        if (cameraOn && track != null) {
            VideoView(room, track, mirror = true, Modifier.fillMaxSize())
        } else {
            Icon(Icons.Rounded.VideocamOff, null, tint = Color.White.copy(alpha = 0.6f), modifier = Modifier.size(22.dp))
        }
    }
}

/** A video track drawn to fill its space; a new view for each track, let go of with it. */
@Composable
private fun VideoView(room: Room, track: VideoTrack, mirror: Boolean, modifier: Modifier) {
    key(track) {
        AndroidView(
            factory = { context ->
                TextureViewRenderer(context).apply {
                    room.initVideoRenderer(this)
                    setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
                    setMirror(mirror)
                    track.addRenderer(this)
                }
            },
            onRelease = { view ->
                track.removeRenderer(view)
                view.release()
            },
            modifier = modifier,
        )
    }
}
