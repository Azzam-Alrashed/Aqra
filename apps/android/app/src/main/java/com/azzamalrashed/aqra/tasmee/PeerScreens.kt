package com.azzamalrashed.aqra.tasmee

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.account.Problem
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.art.LeftToRight
import com.azzamalrashed.aqra.ui.components.AqraProgress
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipButton
import com.azzamalrashed.aqra.ui.components.ProblemLine
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// MARK: - Reciting to a friend

/**
 * The student shows a friend a code (and its QR code); the friend hears them on their own phone and records what they
 * heard into the student's account, where it's applied as a peer's tasmee'.
 */
@Composable
fun PeerRequestSheet(app: AqraApp, onDone: () -> Unit) {
    val tasmee = app.tasmee
    var request by remember { mutableStateOf<PeerRequest?>(null) }
    var problem by remember { mutableStateOf<Problem?>(null) }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    /** Where the friend's Mushaf opens: the next page of today's wird, or the page last read. */
    val startPage = app.revision.plan?.items?.firstOrNull { !it.done }?.page ?: app.prefs.lastPage.value
    suspend fun create() {
        problem = null
        try {
            request = tasmee.createPeerRequest(app.account.publicName, startPage)
        } catch (error: Exception) {
            problem = AccountStore.problem(error)
        }
    }
    LaunchedEffect(Unit) { create() }
    // The friend's record, once it arrives.
    val received = request?.let { r -> tasmee.history.firstOrNull { it.kind == TasmeeRecord.Kind.PEER && it.sessionId == r.id } }
    LaunchedEffect(received != null) { if (received != null) haptics.performHapticFeedback(HapticFeedbackType.Confirm) }
    // The code is left to expire rather than deleted on closing: a friend may still be marking.

    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp).padding(bottom = 20.dp).safeDrawingPadding(),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        TwoLineHeadline(stringResource(R.string.recite_to_a_friend),
            stringResource(if (received == null) R.string.show_them_this_code else R.string.your_friend_recorded_it), size = 26f, modifier = Modifier.padding(top = 12.dp))
        Spacer(Modifier.weight(1f))
        AnimatedContent(Triple(received, request, problem), label = "peer") { (received, request, problem) ->
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                when {
                    received != null -> {
                        Text("✅", style = aqraStyle(64f))
                        Text(pluralStringResource(R.plurals.n_pages, received.pages.toSet().size, received.pages.toSet().size) + " · " +
                            pluralStringResource(R.plurals.n_stumbles, received.stumbles.size, received.stumbles.size), style = aqraStyle(17f, Weight.heavy, Palette.ink))
                        Text(stringResource(R.string.its_been_added_to_your_revision), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
                    }
                    request != null -> {
                        QrCode(request.link, Modifier.softShadow(RoundedCornerShape(24.dp), strength = 1.2f).background(Color.White, RoundedCornerShape(24.dp)).padding(14.dp).size(200.dp))
                        val code = stringResource(R.string.code_s, request.id)
                        LeftToRight {
                            Text(request.id.toList().joinToString(" "), style = aqraStyle(34f, Weight.heavy, Palette.brand).copy(fontFamily = FontFamily.Monospace),
                                modifier = Modifier.clearAndSetSemantics { contentDescription = code })
                        }
                        var now by remember { mutableStateOf(Moment.now()) }
                        LaunchedEffect(request.id) { while (true) { now = Moment.now(); delay(30_000) } }
                        val minutes = maxOf(((request.expiresAt - now) / 60).toInt(), 0)
                        Text(pluralStringResource(R.plurals.valid_for_n_minutes, minutes, minutes), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
                        Text(stringResource(R.string.your_friend_opens_aqra_taps_hear_a_friend_and_scans), style = aqraStyle(13f, Weight.medium, Palette.inkSoft),
                            textAlign = TextAlign.Center)
                    }
                    problem != null -> {
                        ProblemLine(problem)
                        ChipButton(stringResource(R.string.try_again), filled = true) { scope.launch { create() } }
                    }
                    else -> AqraProgress()
                }
            }
        }
        Spacer(Modifier.weight(1f))
        BrandButton(stringResource(if (received == null) R.string.cancel else R.string.done), Modifier.widthIn(max = 520.dp), onClick = onDone)
    }
}

/** A QR code drawn as sharp squares, at any size. */
@Composable
fun QrCode(text: String, modifier: Modifier) {
    val matrix = remember(text) {
        QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0))
    }
    Canvas(modifier.clearAndSetSemantics {}) {
        val cell = size.minDimension / matrix.width
        for (y in 0 until matrix.height) for (x in 0 until matrix.width) {
            if (matrix[x, y]) drawRect(Palette.ink, Offset(x * cell, y * cell), Size(cell + 0.5f, cell + 0.5f))
        }
    }
}

// MARK: - Hearing a friend

/** Hearing a friend: their code (typed, scanned, or opened from a link), then the marking screen, then the record goes into their account. */
@Composable
fun HearFriendScreen(app: AqraApp, store: MushafStore, initialCode: String?, onClose: () -> Unit) {
    val tasmee = app.tasmee
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf(initialCode.orEmpty()) }
    var request by remember { mutableStateOf<PeerRequest?>(null) }
    var checking by remember { mutableStateOf(false) }
    var invalid by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<Problem?>(null) }
    var scanUnavailable by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }

    suspend fun check() {
        if (!PeerRequest.isWellFormed(code) || checking) return
        checking = true
        problem = null
        try {
            val found = tasmee.peerRequest(code)
            if (found != null) request = found else invalid = true
        } catch (error: Exception) {
            problem = AccountStore.problem(error)
        } finally {
            checking = false
        }
    }
    LaunchedEffect(Unit) { if (initialCode != null) check() else runCatching { focus.requestFocus() } }

    val found = request
    if (found != null) {
        TasmeeMarkingScreen(app, store, found.studentName ?: stringResource(R.string.a_friend), found.startPage ?: 1, onClose = onClose) { result ->
            tasmee.recordPeerTasmee(found, app.account.publicName, result.pages, result.stumbles, result.mistakes)
        }
        return
    }
    BackHandler(onBack = onClose)
    Box(Modifier.fillMaxSize().background(Palette.surface).safeDrawingPadding()) {
        Column(Modifier.fillMaxSize().padding(horizontal = 24.dp).padding(bottom = 20.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 12.dp)) {
                Box(Modifier.size(38.dp).background(Palette.lavender, CircleShape).pressable(onClick = onClose), contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Close, stringResource(R.string.close), tint = Palette.brand, modifier = Modifier.size(20.dp))
                }
            }
            TwoLineHeadline(stringResource(R.string.hear_a_friend), stringResource(R.string.enter_their_code), size = 28f)
            LeftToRight {
                OutlinedTextField(
                    code,
                    { typed ->
                        code = PeerRequest.normalize(typed).take(PeerRequest.CODE_LENGTH)
                        invalid = false
                    },
                    Modifier.fillMaxWidth().focusRequester(focus).semantics { contentDescription = "" },
                    textStyle = aqraStyle(34f, Weight.heavy, Palette.ink).copy(fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center),
                    placeholder = { Text("ABC234", Modifier.fillMaxWidth(), style = aqraStyle(34f, Weight.heavy, Palette.inkSoft.copy(alpha = 0.4f)).copy(fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center)) },
                    singleLine = true,
                    shape = RoundedCornerShape(22.dp),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii, imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { scope.launch { check() } }),
                    colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = Color.White, unfocusedContainerColor = Color.White,
                        focusedBorderColor = Palette.brand, unfocusedBorderColor = Color.White, cursorColor = Palette.brand),
                )
            }
            if (invalid) Text(stringResource(R.string.this_code_isnt_valid_or_it_has_expired_ask_your), style = aqraStyle(13f, Weight.semibold, Palette.warning), textAlign = TextAlign.Center)
            problem?.let { ProblemLine(it) }
            ChipButton(stringResource(R.string.scan_their_qr_code), filled = false, leading = {
                Icon(Icons.Rounded.QrCodeScanner, null, tint = Palette.brand, modifier = Modifier.size(16.dp))
            }) {
                val scanner = GmsBarcodeScanning.getClient(context, GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build())
                scanner.startScan()
                    .addOnSuccessListener { barcode ->
                        PeerRequest.code(barcode.rawValue.orEmpty())?.let {
                            code = it
                            scope.launch { check() }
                        }
                    }
                    .addOnFailureListener { scanUnavailable = true }
            }
            if (scanUnavailable) Text(stringResource(R.string.scanning_isnt_available), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
            Spacer(Modifier.weight(1f))
            BrandButton(stringResource(R.string.continue_action), Modifier.widthIn(max = 520.dp), enabled = PeerRequest.isWellFormed(code) && !checking) {
                scope.launch { check() }
            }
        }
        if (checking) AqraProgress(Modifier.align(Alignment.Center))
    }
}
