package com.azzamalrashed.aqra.tasmee

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material3.Icon
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AqraTextField
import com.azzamalrashed.aqra.account.Confirm
import com.azzamalrashed.aqra.account.SignInButtons
import com.azzamalrashed.aqra.ui.TabPage
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraProgress
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipButton
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.ProblemLine
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumber
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * «علّم في اقرأ»: applying to teach. A signed-in user tells the vetting team who they are and from whom they hold their
 * ijazah, with a copy of it; the team reviews it, interviews them, and approves or declines. The page shows where the
 * application stands, and lets it be changed while it waits.
 */
@Composable
fun TeacherApplicationPage(app: AqraApp) {
    val tasmee = app.tasmee
    val account = app.account
    val signedIn = account.profile?.isAnonymous == false
    var editing by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf(tasmee.application ?: TeacherApplication(account.profile?.uid.orEmpty(), account.publicName.orEmpty())) }
    LaunchedEffect(tasmee.application, account.profile?.uid) {
        tasmee.application?.let { if (!editing) draft = it }
            ?: run { if (draft.id.isEmpty()) draft = TeacherApplication(account.profile?.uid.orEmpty(), account.publicName.orEmpty()) }
    }

    TabPage(top = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.teach_on_aqra), style = aqraStyle(28f, Weight.heavy, Palette.ink))
            Text(stringResource(R.string.hear_students_recite), style = aqraStyle(28f, Weight.heavy, Palette.brand))
        }
        val application = tasmee.application
        when {
            !signedIn -> AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                Text(stringResource(R.string.sign_in_to_apply), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.teachers_are_vetted_the_team_reviews_your_ijazah_then_meets), style = aqraStyle(13f, Weight.medium, Palette.inkSoft))
                Spacer(Modifier.height(12.dp))
                SignInButtons(app)
                account.problem?.let { ProblemLine(it, Modifier.padding(top = 10.dp)) }
            }
            application != null && !editing -> Status(app, application) {
                draft = application
                editing = true
            }
            else -> Form(app, draft, { draft = it }, onDone = { editing = false })
        }
    }
}

@Composable
private fun Status(app: AqraApp, application: TeacherApplication, onChange: () -> Unit) {
    val scope = rememberCoroutineScope()
    var confirmingWithdraw by remember { mutableStateOf(false) }
    val status = application.status
    AqraCard(Modifier.fillMaxWidth(), padding = 16.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.Top) {
            Step(1, stringResource(R.string.submitted), true)
            Connector(status != TeacherApplication.Status.SUBMITTED, Modifier.weight(1f))
            Step(2, stringResource(R.string.interview), status == TeacherApplication.Status.INTERVIEW || status == TeacherApplication.Status.APPROVED)
            Connector(status == TeacherApplication.Status.APPROVED, Modifier.weight(1f))
            Step(3, stringResource(R.string.approved), status == TeacherApplication.Status.APPROVED)
        }
        Spacer(Modifier.height(16.dp))
        Text(stringResource(when (status) {
            TeacherApplication.Status.SUBMITTED -> R.string.the_team_will_review_your_application_and_your_ijazah
            TeacherApplication.Status.INTERVIEW -> R.string.your_ijazah_was_reviewed_the_team_will_contact_you_to
            TeacherApplication.Status.APPROVED -> R.string.welcome_your_sessions_appear_in_the_tasmee_tab
            TeacherApplication.Status.REJECTED -> R.string.your_application_wasnt_accepted_2
        }), style = aqraStyle(14f, Weight.semibold, Palette.ink))
        if (application.note.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                IconTile("💬", Palette.lavender, size = 30.dp)
                Text(application.note, style = aqraStyle(13f, Weight.medium, Palette.inkSoft))
            }
        }
    }
    AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
        AqraRow("🎓", Palette.butter, application.name, detail = application.city.ifEmpty { null }) {}
        AqraRowDivider()
        AqraRow("📜", Palette.butter, stringResource(R.string.ijazah_from_s, application.ijazahFrom), detail = application.riwayah.ifEmpty { null }) {}
        AqraRowDivider()
        AqraRow("📎", Palette.butter, pluralStringResource(R.plurals.n_files, application.files.size, application.files.size), detail = application.contact.ifEmpty { null }) {}
    }
    if (application.canEdit) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ChipButton(stringResource(R.string.change_it), filled = true, onClick = onChange)
            ChipButton(stringResource(R.string.withdraw), filled = false) { confirmingWithdraw = true }
        }
    }
    if (confirmingWithdraw) {
        Confirm(stringResource(R.string.withdraw_your_application_q), stringResource(R.string.your_application_and_the_copy_of_your_ijazah_are_deleted),
            stringResource(R.string.withdraw), onDismiss = { confirmingWithdraw = false }, cancel = stringResource(R.string.keep_it)) {
            scope.launch { app.tasmee.withdrawApplication() }
        }
    }
}

@Composable
private fun Step(number: Int, title: String, reached: Boolean) {
    Column(Modifier.width(76.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(30.dp).background(if (reached) Palette.brand else Palette.lavender, CircleShape), contentAlignment = Alignment.Center) {
            Text(formatNumber(number), style = aqraStyle(14f, Weight.heavy, if (reached) androidx.compose.ui.graphics.Color.White else Palette.inkSoft))
        }
        FittedText(title, aqraStyle(11f, Weight.bold, if (reached) Palette.brand else Palette.inkSoft), minScale = 0.8f)
    }
}

@Composable
private fun Connector(reached: Boolean, modifier: Modifier) {
    Box(modifier.padding(top = 13.5.dp).height(3.dp).background(if (reached) Palette.brand else Palette.lavender, CircleShape))
}

@Composable
private fun Form(app: AqraApp, draft: TeacherApplication, onDraft: (TeacherApplication) -> Unit, onDone: () -> Unit) {
    val tasmee = app.tasmee
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var uploading by remember { mutableStateOf(false) }
    var uploadFailed by remember { mutableStateOf(false) }

    fun upload(read: suspend () -> Pair<ByteArray, String>?) = scope.launch {
        uploading = true
        uploadFailed = false
        try {
            val (data, type) = read() ?: run { uploadFailed = true; return@launch }
            if (data.size > TeacherApplication.MAX_FILE_SIZE) { uploadFailed = true; return@launch }
            onDraft(draft.copy(files = draft.files + tasmee.uploadIjazah(data, type)))
        } catch (_: Exception) {
            uploadFailed = true
        } finally {
            uploading = false
        }
    }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        // Photos are sent as JPEG, made smaller until they fit.
        upload { withContext(Dispatchers.IO) { jpeg(context, uri)?.let { it to "image/jpeg" } } }
    }
    val pdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        upload { withContext(Dispatchers.IO) { context.contentResolver.openInputStream(uri)?.use { it.readBytes() }?.let { it to "application/pdf" } } }
    }

    Text(stringResource(R.string.teachers_on_aqra_hold_an_ijazah_in_the_quran_tell), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
    AqraSectionTitle(stringResource(R.string.about_you), Modifier.padding(top = 6.dp))
    AqraTextField(draft.name, { onDraft(draft.copy(name = it)) }, stringResource(R.string.name))
    AqraTextField(draft.city, { onDraft(draft.copy(city = it)) }, stringResource(R.string.city))
    AqraTextField(draft.line, { onDraft(draft.copy(line = it)) }, stringResource(R.string.what_students_will_read))
    AqraTextField(draft.contact, { onDraft(draft.copy(contact = it)) }, stringResource(R.string.phone_or_email_for_the_interview))
    AqraSectionTitle(stringResource(R.string.your_ijazah), Modifier.padding(top = 6.dp))
    AqraTextField(draft.riwayah, { onDraft(draft.copy(riwayah = it)) }, stringResource(R.string.riwayah))
    AqraTextField(draft.ijazahFrom, { onDraft(draft.copy(ijazahFrom = it)) }, stringResource(R.string.the_sheikh_who_granted_it))
    AqraTextField(draft.ijazahDetails, { onDraft(draft.copy(ijazahDetails = it)) }, stringResource(R.string.its_chain_its_date_anything_else), singleLine = false)

    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile("📎", Palette.sky, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.a_copy_of_your_ijazah), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                Text(if (draft.files.isEmpty()) stringResource(R.string.a_photo_or_a_pdf_up_to_10_mb)
                    else pluralStringResource(R.plurals.n_files_attached, draft.files.size, draft.files.size),
                    style = aqraStyle(12f, Weight.semibold, if (draft.files.isEmpty()) Palette.inkSoft else Palette.brand))
            }
            if (uploading) AqraProgress()
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            ChipButton(stringResource(R.string.photo), filled = false, enabled = !uploading,
                leading = { Icon(Icons.Rounded.Photo, null, tint = Palette.brand, modifier = Modifier.size(16.dp)) }) {
                photo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }
            ChipButton(stringResource(R.string.pdf), filled = false, enabled = !uploading,
                leading = { Icon(Icons.Rounded.Description, null, tint = Palette.brand, modifier = Modifier.size(16.dp)) }) {
                pdf.launch(arrayOf("application/pdf"))
            }
            if (draft.files.isNotEmpty()) {
                Text(stringResource(R.string.remove_all), style = aqraStyle(13f, Weight.bold, Palette.danger), modifier = Modifier.pressable { onDraft(draft.copy(files = emptyList())) })
            }
        }
        if (uploadFailed) {
            Text(stringResource(R.string.the_file_couldnt_be_uploaded_check_your_connection_or_try), style = aqraStyle(12f, Weight.semibold, Palette.warning),
                modifier = Modifier.padding(top = 12.dp))
        }
    }
    tasmee.problem?.let { ProblemLine(it) }
    val complete = draft.trimmed().isComplete
    BrandButton(stringResource(if (tasmee.application == null) R.string.send_application else R.string.save_changes), Modifier.padding(top = 6.dp),
        enabled = complete && !uploading) {
        tasmee.submit(draft.trimmed())
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        onDone()
    }
    if (tasmee.application != null) {
        Text(stringResource(R.string.cancel), style = aqraStyle(15f, Weight.semibold, Palette.brand),
            modifier = Modifier.fillMaxWidth().pressable(onClick = onDone).padding(vertical = 8.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

/** A photo as a JPEG no larger than the upload limit. */
private fun jpeg(context: android.content.Context, uri: Uri): ByteArray? {
    val bitmap = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return null
    var quality = 85
    while (true) {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
        if (out.size() <= TeacherApplication.MAX_FILE_SIZE || quality <= 25) return out.toByteArray()
        quality -= 20
    }
}
