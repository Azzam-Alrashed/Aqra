package com.azzamalrashed.aqra.revision

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.mushaf.MushafColorsMenu
import com.azzamalrashed.aqra.mushaf.MushafPageOptions
import com.azzamalrashed.aqra.mushaf.MushafPageView
import com.azzamalrashed.aqra.mushaf.MushafTopBar
import com.azzamalrashed.aqra.mushaf.SystemBars
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.recitation.ListenSetupSheet
import com.azzamalrashed.aqra.recitation.ListeningPanel
import com.azzamalrashed.aqra.recitation.ListeningSummary
import com.azzamalrashed.aqra.recitation.RecitationListener
import com.azzamalrashed.aqra.ui.components.FloatingCapsule
import com.azzamalrashed.aqra.ui.components.FloatingPanel
import com.azzamalrashed.aqra.ui.components.MarkingButton
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle

/**
 * Today's wird, opened full screen over the home: its pages revised one after another, each veiled and revealed ayah by
 * ayah, and back home when the wird is done. The Mushaf keeps the page the student was reading.
 */
@Composable
fun WirdScreen(
    app: AqraApp,
    store: MushafStore,
    startPage: Int,
    /** A page revised outside the app, with stumbles to record: shown whole, recorded as revised outside, alone. */
    outside: Boolean = false,
    onClose: () -> Unit,
) {
    val style = MushafStyle.current()
    val haptics = LocalHapticFeedback.current
    fun session(page: Int) = RevisionSession(page, store.page(page).ayahs.filter(app.memorization::isMemorized)).also {
        if (outside) it.revealAll()
    }
    var session by remember { mutableStateOf(session(startPage)) }
    val context = LocalContext.current
    /** Aqra following the revision by ear («سمّع بصوتك»), while the student revises aloud. */
    var listener by remember { mutableStateOf<RecitationListener?>(null) }
    var settingUpListening by remember { mutableStateOf(false) }

    fun startListening() {
        val started = RecitationListener(session, store, app.recitationModel)
        listener = started
        app.prefs.recitationListens.value = true
        started.start()
    }
    val microphone = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startListening() else listener?.microphoneRefused() ?: RecitationListener(session, store, app.recitationModel).also {
            listener = it
            it.microphoneRefused()
        }
    }
    /** Asks for the microphone if needed, then listens. */
    fun listen() {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (granted) startListening() else microphone.launch(Manifest.permission.RECORD_AUDIO)
    }
    /** «سمّع بصوتك»: listens right away once the model is on the device; the first time, explains and downloads it. */
    fun beginListening() {
        if (app.recitationModel.isInstalled) listen() else settingUpListening = true
    }
    /** Back to revealing by hand, for this revision and the next. */
    fun stopListening() {
        listener?.close()
        listener = null
        app.prefs.recitationListens.value = false
    }
    // Listening carries on from the last revision; it stops with the screen, and waits in the background.
    LaunchedEffect(Unit) { if (app.prefs.recitationListens.value && !outside && app.recitationModel.isInstalled) listen() }
    DisposableEffect(Unit) { onDispose { listener?.close() } }
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { listener?.pause() }

    SystemBars(visible = true, lightIcons = style.dark)
    // Leaving goes back home without recording the page.
    BackHandler(onBack = onClose)

    fun show(next: RevisionSession) {
        session = next
        listener?.let {
            it.follow(next)
            if (it.phase == RecitationListener.Phase.PAUSED) it.resume()
        }
    }

    /** Recorded, it moves straight on to the next page of today's wird, and back home when the wird is done. */
    fun finish() {
        val current = session
        app.revision.record(current.page, current.ayahs, current.stumbles,
            if (outside) RevisionRecord.Source.OUTSIDE else RevisionRecord.Source.APP, app.memorization)
        val next = if (outside) null else app.revision.plan?.items?.firstOrNull { !it.done }
        if (next != null) {
            show(session(next.page))
        } else {
            haptics.performHapticFeedback(HapticFeedbackType.Confirm)
            onClose()
        }
    }

    // The bars stay for the whole revision, so the page sits between them rather than under them: every ayah stays in
    // sight as it's revealed.
    Column(Modifier.fillMaxSize().background(style.paper).statusBarsPadding().navigationBarsPadding()) {
        MushafTopBar(store, session.page, style, leading = {}, trailing = { FloatingCapsule(style) { MushafColorsMenu(app, style) } })
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(vertical = 6.dp)) {
            val facing = maxWidth > maxHeight && maxWidth >= 900.dp
            // A revision holds its page still: no turning until it's done.
            AnimatedContent(session, transitionSpec = { fadeIn(tween(250)) togetherWith fadeOut(tween(250)) }, label = "page") { current ->
                val options = MushafPageOptions(app.prefs.tajweed.value, app.prefs.topics.value, app.memorization, revision = current)
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    if (facing) {
                        val first = ((current.page + 1) / 2) * 2 - 1
                        Row(Modifier.fillMaxSize()) {
                            MushafPageView(store.page(first), store, app.fonts, style, options, Modifier.weight(1f).fillMaxSize())
                            Box(Modifier.width(1.dp).fillMaxSize().background(style.chrome.copy(alpha = 0.18f)))
                            MushafPageView(store.page(first + 1), store, app.fonts, style, options, Modifier.weight(1f).fillMaxSize())
                        }
                    } else {
                        MushafPageView(store.page(current.page), store, app.fonts, style, options, Modifier.fillMaxSize())
                    }
                }
            }
        }
        val following = listener
        if (following != null && !outside) {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                FloatingPanel(style) {
                    if (session.isComplete) {
                        val hasNext = app.revision.plan?.items?.any { !it.done && it.page != session.page } ?: false
                        ListeningSummary(session, store, style, hasNext, onAgain = { show(session(session.page)) }, onNext = ::finish)
                    } else {
                        ListeningPanel(following, session, style, onStop = ::stopListening, onDone = ::finish)
                    }
                }
            }
            LaunchedEffect(session.revealed) { if (session.revealed > 0) haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }
            LaunchedEffect(session.stumbles.size) { if (session.stumbles.isNotEmpty()) haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick) }
            LaunchedEffect(session.isComplete) { if (session.isComplete) haptics.performHapticFeedback(HapticFeedbackType.Confirm) }
        } else {
            RevisionBar(session, style, outside, canListen = !outside && !session.isComplete, onListen = ::beginListening,
                onLeave = onClose, onDone = ::finish)
        }
    }
    if (settingUpListening) {
        ListenSetupSheet(app.recitationModel, onReady = {
            settingUpListening = false
            listen()
        }, onDismiss = { settingUpListening = false })
    }
}

@Composable
private fun RevisionBar(
    session: RevisionSession, style: MushafStyle, outside: Boolean,
    /** Whether «سمّع بصوتك» is offered. */
    canListen: Boolean, onListen: () -> Unit,
    onLeave: () -> Unit, onDone: () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(session.revealed) { if (session.revealed > 0) haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }
    LaunchedEffect(session.stumbles.size) { if (session.stumbles.isNotEmpty()) haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick) }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        FloatingPanel(style) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    Modifier.size(38.dp).background(style.barAccentFill, CircleShape).pressable(onClick = onLeave),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Close, stringResource(R.string.leave_revision), tint = style.barAccent, modifier = Modifier.size(20.dp))
                }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(R.string.page_n, session.page), style = aqraStyle(17f, Weight.heavy, style.ink))
                    Text(stringResource(R.string.n_of_n, minOf(session.revealed, session.ayahs.size), session.ayahs.size), style = aqraStyle(12f, Weight.semibold, style.chrome))
                }
                Spacer(Modifier.weight(1f))
                AnimatedVisibility(session.stumbles.isNotEmpty(), enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
                    Box(Modifier.height(30.dp).background(style.stumble.copy(alpha = 0.6f), CircleShape).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                        Text(pluralStringResource(R.plurals.n_stumbles, session.stumbles.size, session.stumbles.size), style = aqraStyle(13f, Weight.bold, style.stumbleText))
                    }
                }
            }
            Text(
                stringResource(if (outside) R.string.tap_the_ayat_you_stumbled_on_when_you_revised_this else R.string.tap_to_reveal_the_next_ayah_and_tap_a_revealed),
                style = aqraStyle(12f, Weight.semibold, style.chrome), textAlign = TextAlign.Center, maxLines = 2,
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            )
            if (canListen) {
                MarkingButton(stringResource(R.string.recite_aloud), style, Modifier.fillMaxWidth().padding(bottom = 10.dp), prominent = true,
                    leading = { Icon(Icons.Rounded.Mic, null, tint = Color.White, modifier = Modifier.size(18.dp)) }, onClick = onListen)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!outside) {
                    MarkingButton(stringResource(R.string.next_ayah), style, Modifier.weight(1f), enabled = !session.isComplete) { session.revealNext() }
                    MarkingButton(stringResource(R.string.show_page), style, Modifier.weight(1f), enabled = !session.isComplete) { session.revealAll() }
                }
                MarkingButton(stringResource(R.string.done), style, Modifier.weight(1f), prominent = !canListen, onClick = onDone)
            }
        }
    }
}
