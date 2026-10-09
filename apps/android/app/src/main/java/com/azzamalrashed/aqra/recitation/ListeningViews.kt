package com.azzamalrashed.aqra.recitation

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.text.format.Formatter
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MicOff
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionSession
import com.azzamalrashed.aqra.tasmee.MistakeType
import com.azzamalrashed.aqra.tasmee.mistakeTitle
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.MarkingButton
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.factSeparator
import java.text.NumberFormat

/** The revision panel while Aqra listens: what it's doing, how far the page is, the stumbles so far, and pausing. */
@Composable
fun ColumnScope.ListeningPanel(listener: RecitationListener, session: RevisionSession, style: MushafStyle, onStop: () -> Unit, onDone: () -> Unit) {
    val context = LocalContext.current
    val phase = listener.phase
    val listening = phase == RecitationListener.Phase.LISTENING
    val stopLabel = stringResource(R.string.stop_listening)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.pressable(onClick = onStop).semantics { contentDescription = stopLabel }) {
            ListeningMic(if (listening) listener.level else 0.0, listening, style)
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(when (phase) {
                RecitationListener.Phase.PREPARING -> R.string.getting_ready_to_listen
                RecitationListener.Phase.LISTENING -> R.string.listening
                RecitationListener.Phase.PAUSED -> R.string.paused
                else -> R.string.not_listening
            }), style = aqraStyle(17f, Weight.heavy, style.ink))
            Text(stringResource(R.string.page_n_n_of_n, session.page, minOf(session.revealed, session.ayahs.size), session.ayahs.size),
                style = aqraStyle(12f, Weight.semibold, style.chrome))
        }
        Spacer(Modifier.weight(1f))
        AnimatedVisibility(session.stumbles.isNotEmpty(), enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
            StumbleCount(session.stumbles.size, style)
        }
    }
    when (phase) {
        RecitationListener.Phase.FAILED_MICROPHONE, RecitationListener.Phase.FAILED_MODEL -> Text(
            stringResource(if (phase == RecitationListener.Phase.FAILED_MICROPHONE) R.string.aqra_cant_use_the_microphone_allow_it_in_settings
                else R.string.listening_couldnt_start_try_again),
            style = aqraStyle(12f, Weight.semibold, style.chrome), textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
        )
        else -> {
            LevelMeter(if (listening) listener.level else 0.0, Modifier.fillMaxWidth().padding(top = 10.dp))
            Text(stringResource(R.string.tap_an_ayah_to_mark_a_stumble_or_take_it), style = aqraStyle(12f, Weight.semibold, style.chrome),
                textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 12.dp))
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        when (phase) {
            RecitationListener.Phase.LISTENING, RecitationListener.Phase.PREPARING ->
                MarkingButton(stringResource(R.string.pause), style, Modifier.weight(1f), enabled = listening,
                    leading = { Icon(Icons.Rounded.Pause, null, tint = style.barAccent, modifier = Modifier.size(18.dp)) }) { listener.pause() }
            RecitationListener.Phase.PAUSED ->
                MarkingButton(stringResource(R.string.resume), style, Modifier.weight(1f),
                    leading = { Icon(Icons.Rounded.Mic, null, tint = style.barAccent, modifier = Modifier.size(18.dp)) }) { listener.resume() }
            RecitationListener.Phase.FAILED_MICROPHONE ->
                MarkingButton(stringResource(R.string.open_settings), style, Modifier.weight(1f)) {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                }
            RecitationListener.Phase.FAILED_MODEL ->
                MarkingButton(stringResource(R.string.try_again), style, Modifier.weight(1f)) { listener.start() }
        }
        MarkingButton(stringResource(R.string.done), style, Modifier.weight(1f), prominent = true, onClick = onDone)
    }
}

/** The page done, heard to its end: how it went, ayah by ayah, then on to the next page or once more. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ColumnScope.ListeningSummary(session: RevisionSession, store: MushafStore, style: MushafStyle, hasNextPage: Boolean, onAgain: () -> Unit, onNext: () -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(stringResource(R.string.you_finished_page_n, session.page), style = aqraStyle(18f, Weight.heavy, style.ink))
        Text(
            if (session.stumbles.isEmpty()) stringResource(R.string.every_ayah_without_a_stumble)
            else pluralStringResource(R.plurals.n_stumbles, session.stumbles.size, session.stumbles.size),
            style = aqraStyle(13f, Weight.semibold, style.chrome),
        )
    }
    if (session.stumbles.isNotEmpty()) {
        FlowRow(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (ayah in session.ayahs.filter { it in session.stumbles }) {
                val kinds = MistakeType.entries.filter { it in session.stumbleKinds[ayah].orEmpty() }
                val prompted = kinds == listOf(MistakeType.PROMPTING)
                val label = (listOf(stringResource(R.string.ayah_n_2, store.reference(ayah).second)) + kinds.map { mistakeTitle(it) }).joinToString(factSeparator())
                Box(Modifier.height(28.dp).background((if (prompted) style.prompt else style.stumble).copy(alpha = 0.7f), CircleShape)
                    .padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                    Text(label, style = aqraStyle(12f, Weight.bold, if (prompted) style.promptText else style.stumbleText))
                }
            }
        }
    }
    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        MarkingButton(stringResource(R.string.recite_the_page_again), style, Modifier.weight(1f), onClick = onAgain)
        MarkingButton(stringResource(if (hasNextPage) R.string.next_page else R.string.finish), style, Modifier.weight(1f), prominent = true, onClick = onNext)
    }
    if (hasNextPage) {
        Text(stringResource(R.string.the_revision_is_recorded_and_listening_carries_on_to_the), style = aqraStyle(11f, Weight.semibold, style.chrome),
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
    }
}

/** «نزّل وابدأ»: what listening does, the one-time download, and the promise that the voice stays on the device. */
@Composable
fun ListenSetupSheet(model: RecitationModel, onReady: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(model.state) { if (model.state == RecitationModel.State.Ready) onReady() }
    AqraSheet(onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.padding(top = 20.dp).size(72.dp).background(Palette.lavender, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Mic, null, tint = Palette.brand, modifier = Modifier.size(32.dp))
            }
            Text(stringResource(R.string.recite_aloud), style = aqraStyle(24f, Weight.heavy, Palette.ink), modifier = Modifier.padding(top = 14.dp))
            Text(stringResource(R.string.recite_from_memory_and_aqra_follows_along), style = aqraStyle(15f, Weight.semibold, Palette.inkSoft),
                textAlign = TextAlign.Center, modifier = Modifier.padding(top = 4.dp))
            Column(Modifier.fillMaxWidth().padding(top = 22.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Point(Icons.Rounded.Visibility, stringResource(R.string.the_ayat_are_revealed_as_you_recite))
                Point(Icons.Rounded.Flag, stringResource(R.string.what_you_stumble_on_is_marked_and_you_can_correct))
                Point(Icons.Rounded.Lightbulb, stringResource(R.string.after_a_long_pause_the_next_word_is_shown))
                Point(Icons.Rounded.Lock, stringResource(R.string.your_voice_stays_on_your_device_and_isnt_kept))
            }
            Spacer(Modifier.weight(1f))
            val state = model.state
            Column(
                Modifier.fillMaxWidth().background(Color(0xFFF6F1E7), RoundedCornerShape(16.dp)).padding(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val text = aqraStyle(13f, Weight.semibold, Palette.inkSoft)
                when (state) {
                    is RecitationModel.State.Downloading -> {
                        val fraction by animateFloatAsState(state.fraction.toFloat(), tween(300), label = "download")
                        LinearProgressIndicator(progress = { fraction }, color = Palette.brand, trackColor = Palette.lavender, modifier = Modifier.fillMaxWidth())
                        val percent = NumberFormat.getPercentInstance().format(state.fraction)
                        Text(stringResource(R.string.downloading_s, percent), style = text)
                    }
                    RecitationModel.State.Installing -> {
                        LinearProgressIndicator(color = Palette.brand, trackColor = Palette.lavender, modifier = Modifier.fillMaxWidth())
                        Text(stringResource(R.string.preparing), style = text)
                    }
                    RecitationModel.State.Failed -> Text(stringResource(R.string.the_download_didnt_finish_try_again), style = text)
                    else -> Text(stringResource(R.string.a_one_time_download_s, Formatter.formatShortFileSize(context, RecitationModel.DOWNLOAD_SIZE)), style = text)
                }
            }
            val busy = state is RecitationModel.State.Downloading || state == RecitationModel.State.Installing
            BrandButton(stringResource(if (state == RecitationModel.State.Failed) R.string.try_again else R.string.download_and_begin),
                Modifier.fillMaxWidth().padding(top = 14.dp), enabled = !busy) { model.download() }
            Text(stringResource(R.string.not_now), style = aqraStyle(15f, Weight.semibold, Palette.inkSoft),
                modifier = Modifier.padding(vertical = 12.dp).pressable(onClick = onDismiss))
        }
    }
}

@Composable
private fun Point(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = Palette.brand, modifier = Modifier.size(20.dp))
        Text(text, style = aqraStyle(15f, Weight.semibold, Palette.ink))
    }
}

/** The microphone in a purple circle, its ring swelling with the voice. */
@Composable
private fun ListeningMic(level: Double, active: Boolean, style: MushafStyle) {
    val ring by animateFloatAsState((4 + 6 * level).toFloat(), tween(120), label = "ring")
    Box(Modifier.size(52.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size((40 + 2 * ring).dp).background(style.barAccentFill, CircleShape))
        Box(Modifier.size(40.dp).background(if (active) Palette.brand else style.chrome, CircleShape), contentAlignment = Alignment.Center) {
            Icon(if (active) Icons.Rounded.Mic else Icons.Rounded.MicOff, null, tint = Color.White, modifier = Modifier.size(20.dp))
        }
    }
}

/** Nine bars that rise with the voice, the middle ones most. */
@Composable
private fun LevelMeter(level: Double, modifier: Modifier = Modifier) {
    Row(modifier.height(24.dp), horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        for (index in 0 until 9) {
            val weight = 1 - kotlin.math.abs(index - 4) / 5.0
            val height by animateFloatAsState((4 + 18 * level * weight).toFloat(), tween(120), label = "bar")
            Box(Modifier.width(3.5.dp).height(height.dp).background(Palette.brand.copy(alpha = (0.35 + 0.65 * weight).toFloat()), CircleShape))
        }
    }
}

/** «٢ تعثّر» in a coral capsule. */
@Composable
fun StumbleCount(count: Int, style: MushafStyle) {
    Box(Modifier.height(30.dp).background(style.stumble.copy(alpha = 0.6f), CircleShape).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
        Text(pluralStringResource(R.plurals.n_stumbles, count, count), style = aqraStyle(13f, Weight.bold, style.stumbleText))
    }
}
