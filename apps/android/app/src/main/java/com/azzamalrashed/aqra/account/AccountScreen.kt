package com.azzamalrashed.aqra.account

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.os.LocaleListCompat
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.BuildConfig
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.credits.WalletScreen
import com.azzamalrashed.aqra.credits.WalletStore
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.Navigator
import com.azzamalrashed.aqra.ui.NavigatorHost
import com.azzamalrashed.aqra.ui.TabPage
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraProgress
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.ProblemLine
import com.azzamalrashed.aqra.ui.components.fade
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatRelative
import com.azzamalrashed.aqra.ui.util.formatTime
import kotlinx.coroutines.launch

/** The sources page, pushed from the account. */
object SourcesDestination

/**
 * حسابي: the account the progress is backed up to, the Mushaf's colors, the daily reminder, the app's language, and the
 * sources Aqra is built on. What's memorized and the daily amount are edited from the home.
 */
@Composable
fun AccountScreen(app: AqraApp, navigator: Navigator) {
    NavigatorHost(navigator, root = { AccountPage(app, navigator) }) { destination ->
        when (destination) {
            SourcesDestination -> SourcesPage()
        }
    }
}

@Composable
private fun AccountPage(app: AqraApp, navigator: Navigator) {
    val context = LocalContext.current
    val account = app.account
    val scope = rememberCoroutineScope()
    var confirmingSignOut by remember { mutableStateOf(false) }
    var confirmingDeletion by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf(false) }
    var notificationsDenied by remember { mutableStateOf(false) }
    var showingWallet by remember { mutableStateOf(false) }
    var reminderOn by app.prefs.reminderOn
    val reminderMinutes by app.prefs.reminderMinutes

    fun turnReminderOn() {
        reminderOn = true
        notificationsDenied = false
        DailyReminder.schedule(context, reminderMinutes)
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted && DailyReminder.isAllowed(context)) turnReminderOn() else notificationsDenied = true
    }

    TabPage(top = 16.dp) {
        Text(stringResource(R.string.account), style = aqraStyle(30f, Weight.heavy, Palette.ink))
        AccountCard(app)
        if (AccountStore.isAvailable) {
            AqraCard(Modifier.fillMaxWidth().pressable { showingWallet = true }, padding = 0.dp, radius = 24.dp) {
                AqraRow("🪙", Palette.butter, stringResource(R.string.credits),
                    detail = if (account.profile?.isAnonymous == false) stringResource(R.string.s_credits, WalletStore.format(account.wallet.balance))
                    else stringResource(R.string.for_seats_won_by_bidding))
            }
        }

        AqraSectionTitle(stringResource(R.string.mushaf), Modifier.padding(top = 10.dp))
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            AqraRow("🖍️", Palette.rose, stringResource(R.string.tajweed_colors)) { AqraSwitch(app.prefs.tajweed.value) { app.prefs.tajweed.value = it } }
            AqraRowDivider()
            AqraRow("🎨", Palette.mint, stringResource(R.string.topic_colors)) { AqraSwitch(app.prefs.topics.value) { app.prefs.topics.value = it } }
        }

        AqraSectionTitle(stringResource(R.string.revision), Modifier.padding(top = 10.dp))
        AqraCard(Modifier.fillMaxWidth(), animated = true, padding = 0.dp, radius = 24.dp) {
            AqraRow("🔔", Palette.sky, stringResource(R.string.daily_reminder),
                detail = if (reminderOn) stringResource(R.string.every_day_at_s, formatTime(reminderMinutes / 60, reminderMinutes % 60)) else null) {
                AqraSwitch(reminderOn) { on ->
                    when {
                        !on -> {
                            reminderOn = false
                            DailyReminder.cancel(context)
                        }
                        DailyReminder.isAllowed(context) -> turnReminderOn()
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                        else -> notificationsDenied = true
                    }
                }
            }
            if (reminderOn) {
                AqraRowDivider()
                Row(
                    Modifier.fillMaxWidth().pressable(pressed = 1f) { pickingTime = true }.padding(start = 64.dp, end = 14.dp, top = 12.dp, bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(stringResource(R.string.time), style = aqraStyle(15f, Weight.bold, Palette.ink), modifier = Modifier.weight(1f))
                    Box(Modifier.background(Palette.lavender, CircleShape).padding(horizontal = 12.dp, vertical = 6.dp)) {
                        Text(formatTime(reminderMinutes / 60, reminderMinutes % 60), style = aqraStyle(15f, Weight.bold, Palette.brand))
                    }
                }
            }
        }
        AnimatedVisibility(notificationsDenied) {
            Row(Modifier.padding(horizontal = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.notifications_are_off), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft), modifier = Modifier.weight(1f, fill = false))
                Text(stringResource(R.string.open_notification_settings), style = aqraStyle(12f, Weight.bold, Palette.brand),
                    modifier = Modifier.pressable { openNotificationSettings(context) })
            }
        }

        AqraSectionTitle(stringResource(R.string.app), Modifier.padding(top = 10.dp))
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            AqraRow("🔔", Palette.butter, stringResource(R.string.sounds), detail = stringResource(R.string.a_gentle_chime_for_rewards)) {
                AqraSwitch(app.prefs.soundsOn.value) { app.prefs.soundsOn.value = it }
            }
            AqraRowDivider()
            LanguageRow()
            AqraRowDivider()
            AqraRow("📚", Palette.butter, stringResource(R.string.sources), Modifier.pressable(pressed = 1f) { navigator.push(SourcesDestination) },
                detail = stringResource(R.string.the_quran_text_fonts_and_data))
        }

        if (account.profile?.isAnonymous == false) {
            AqraCard(Modifier.fillMaxWidth().padding(top = 10.dp).fade(if (account.isWorking) 0.6f else 1f), padding = 0.dp, radius = 24.dp) {
                AqraRow("🚪", Palette.lavender, stringResource(R.string.sign_out), Modifier.pressable(enabled = !account.isWorking, pressed = 1f) { confirmingSignOut = true }) {}
                AqraRowDivider()
                AqraRow("🗑️", Palette.rose, stringResource(R.string.delete_account), Modifier.pressable(enabled = !account.isWorking, pressed = 1f) { confirmingDeletion = true },
                    titleColor = Palette.danger) {}
            }
        }

        Text(stringResource(R.string.version_s, "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"),
            style = aqraStyle(12f, Weight.semibold, Palette.inkSoft), modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }

    if (confirmingSignOut) {
        Confirm(
            title = stringResource(R.string.sign_out_q), message = stringResource(R.string.your_progress_stays_in_your_account_and_this_device_starts),
            action = stringResource(R.string.sign_out), onDismiss = { confirmingSignOut = false },
        ) { scope.launch { account.signOut() } }
    }
    if (confirmingDeletion) {
        Confirm(
            title = stringResource(R.string.delete_your_account_q), message = stringResource(R.string.your_account_and_the_progress_backed_up_in_it_are),
            action = stringResource(R.string.delete), onDismiss = { confirmingDeletion = false },
        ) { context.findActivity()?.let { activity -> scope.launch { account.deleteAccount(activity) } } }
    }
    if (showingWallet) AqraSheet(onDismiss = { showingWallet = false }) { WalletScreen(app) }
    if (pickingTime) {
        ReminderTimeDialog(reminderMinutes, onDismiss = { pickingTime = false }) { minutes ->
            app.prefs.reminderMinutes.value = minutes
            if (reminderOn) DailyReminder.schedule(context, minutes)
            pickingTime = false
        }
    }
}

@Composable
private fun AqraSwitch(checked: Boolean, onChange: (Boolean) -> Unit) {
    Switch(checked, onChange, colors = SwitchDefaults.colors(checkedTrackColor = Palette.brand, uncheckedTrackColor = Palette.lavender,
        uncheckedThumbColor = Color.White, uncheckedBorderColor = Palette.lavender))
}

/** A question before something that can't be undone, its action in red; an empty message shows none. */
@Composable
fun Confirm(title: String, message: String, action: String, onDismiss: () -> Unit, cancel: String = stringResource(R.string.cancel), destructive: Boolean = true, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color.White,
        title = { Text(title, style = aqraStyle(19f, Weight.heavy, Palette.ink)) },
        text = if (message.isEmpty()) null else { { Text(message, style = aqraStyle(14f, Weight.medium, Palette.inkSoft)) } },
        confirmButton = {
            TextButton({ onDismiss(); onConfirm() }) { Text(action, style = aqraStyle(15f, Weight.bold, if (destructive) Palette.danger else Palette.brand)) }
        },
        dismissButton = { TextButton(onDismiss) { Text(cancel, style = aqraStyle(15f, Weight.bold, Palette.brand)) } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReminderTimeDialog(minutes: Int, onDismiss: () -> Unit, onSet: (Int) -> Unit) {
    val state = rememberTimePickerState(minutes / 60, minutes % 60)
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color.White,
        text = { TimePicker(state, colors = aqraTimePickerColors()) },
        confirmButton = { TextButton({ onSet(state.hour * 60 + state.minute) }) { Text(stringResource(R.string.save), style = aqraStyle(15f, Weight.bold, Palette.brand)) } },
        dismissButton = { TextButton(onDismiss) { Text(stringResource(R.string.cancel), style = aqraStyle(15f, Weight.bold, Palette.inkSoft)) } },
    )
}

/** The time picker in the app's colors: a lavender dial and fields, the hand in purple. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun aqraTimePickerColors() = TimePickerDefaults.colors(
    clockDialColor = Palette.surface, selectorColor = Palette.brand, timeSelectorSelectedContainerColor = Palette.lavender,
    timeSelectorSelectedContentColor = Palette.brand, periodSelectorSelectedContainerColor = Palette.lavender,
)

/** The app's language: the system's per-app setting from Android 13, or a choice here before it. */
@Composable
private fun LanguageRow() {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val name = locale.getDisplayLanguage(locale).replaceFirstChar { it.titlecase(locale) }
    var choosing by remember { mutableStateOf(false) }
    Box {
        AqraRow("🌐", Palette.lavender, stringResource(R.string.language), detail = name, modifier = Modifier.pressable(pressed = 1f) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                runCatching {
                    context.startActivity(Intent(Settings.ACTION_APP_LOCALE_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                }.onFailure { choosing = true }
            } else {
                choosing = true
            }
        })
        DropdownMenu(choosing, onDismissRequest = { choosing = false }) {
            for ((tag, title) in listOf("ar" to R.string.arabic, "en" to R.string.english)) {
                DropdownMenuItem(text = { Text(stringResource(title), style = aqraStyle(15f, Weight.semibold)) }, onClick = {
                    choosing = false
                    AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag))
                })
            }
        }
    }
}

private fun openNotificationSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
    runCatching { context.startActivity(intent) }
}

fun Context.findActivity(): Activity? {
    var context = this
    while (context is ContextWrapper) {
        if (context is Activity) return context
        context = context.baseContext
    }
    return null
}

/** The account the progress is backed up to: an invitation to sign in while anonymous, and who's signed in after. */
@Composable
private fun AccountCard(app: AqraApp) {
    val account = app.account
    val profile = account.profile
    var editingName by remember { mutableStateOf(false) }
    AqraCard(Modifier.fillMaxWidth(), animated = true, padding = 14.dp, radius = 24.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (profile != null && !profile.isAnonymous) {
                Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconTile(if (profile.provider == AccountStore.Provider.APPLE) "🍎" else "🌐", Palette.sky, size = 40.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(profile.name ?: profile.email.orEmpty(), style = aqraStyle(16f, Weight.heavy, Palette.ink), maxLines = 1)
                        if (profile.email != null && profile.name != null) Text(profile.email, style = aqraStyle(12f, Weight.semibold, Palette.inkSoft), maxLines = 1)
                        val backup = app.sync.lastBackup
                        Text(if (backup != null) stringResource(R.string.backed_up_s, formatRelative(backup.toInstant())) else stringResource(R.string.backing_up),
                            style = aqraStyle(12f, Weight.semibold, Palette.brand))
                    }
                }
                // The name teachers, friends and peers see.
                Row(Modifier.fillMaxWidth().pressable(pressed = 1f) { editingName = true }, verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    IconTile("🏷️", Palette.lavender, size = 30.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text(stringResource(R.string.name_others_see), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                        Text(account.publicName ?: "—", style = aqraStyle(15f, Weight.heavy, Palette.ink), maxLines = 1)
                    }
                    Box(Modifier.size(30.dp).background(Palette.lavender, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.Edit, null, tint = Palette.brand, modifier = Modifier.size(16.dp))
                    }
                }
            } else {
                Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconTile("🪪", Palette.butter, size = 40.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(stringResource(R.string.save_your_progress), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                        Text(stringResource(R.string.your_progress_is_only_on_this_device_until_you_sign), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                    }
                }
                if (AccountStore.isAvailable) SignInButtons(app)
                else Text(stringResource(R.string.accounts_need_the_firebase_config), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
            }
            account.problem?.let { ProblemLine(it) }
            if (AccountStore.usesEmulator && profile != null) EmulatorSignIn(app, profile)
        }
    }
    if (editingName) NameDialog(account.publicName.orEmpty(), onDismiss = { editingName = false }) {
        account.changeDisplayName(it)
        editingName = false
    }
}

@Composable
private fun NameDialog(initial: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color.White,
        title = { Text(stringResource(R.string.name_others_see), style = aqraStyle(19f, Weight.heavy, Palette.ink)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.teachers_friends_and_those_who_hear_your_tasmee_see_this), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
                AqraTextField(name, { name = it }, stringResource(R.string.your_name))
            }
        },
        confirmButton = { TextButton({ onSave(name) }) { Text(stringResource(R.string.save), style = aqraStyle(15f, Weight.bold, Palette.brand)) } },
        dismissButton = { TextButton(onDismiss) { Text(stringResource(R.string.cancel), style = aqraStyle(15f, Weight.bold, Palette.inkSoft)) } },
    )
}

/** A text field in the app's colors. */
@Composable
fun AqraTextField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, singleLine: Boolean = true,
                  keyboard: KeyboardOptions = KeyboardOptions.Default) {
    OutlinedTextField(
        value, onChange, modifier.fillMaxWidth(), singleLine = singleLine, keyboardOptions = keyboard,
        placeholder = { Text(placeholder, style = aqraStyle(15f, Weight.medium, Palette.inkSoft)) },
        textStyle = aqraStyle(15f, Weight.medium, Palette.ink),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Palette.brand, unfocusedBorderColor = Palette.lavender, cursorColor = Palette.brand,
            focusedContainerColor = Color.White, unfocusedContainerColor = Color.White),
    )
}

/** Sign in with Apple and with Google, one above the other. */
@Composable
fun SignInButtons(app: AqraApp) {
    val account = app.account
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    Box(contentAlignment = Alignment.Center) {
        Column(Modifier.alpha(if (account.isWorking) 0.6f else 1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).background(Color.Black, CircleShape)
                    .pressable(enabled = !account.isWorking) { context.findActivity()?.let { scope.launch { account.signInWithApple(it) } } },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
            ) {
                Image(painterResource(R.drawable.ic_apple), null, Modifier.size(18.dp).padding(bottom = 2.dp))
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.continue_with_apple), style = aqraStyle(17f, Weight.semibold, Color.White))
            }
            // Google's light button: its own logo on white with a grey outline.
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).background(Color.White, CircleShape).border(1.dp, Color(0xFF747775), CircleShape)
                    .pressable(enabled = !account.isWorking) { context.findActivity()?.let { scope.launch { account.signInWithGoogle(it) } } },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
            ) {
                Image(painterResource(R.drawable.ic_google), null, Modifier.size(18.dp))
                Spacer(Modifier.size(10.dp))
                Text(stringResource(R.string.continue_with_google), style = aqraStyle(17f, Weight.semibold, Color(0xFF1F1F1F)))
            }
        }
        if (account.isWorking) AqraProgress()
    }
}

/** Signing in to the local Auth emulator with any email, and this account's uid for the seed script. */
@Composable
private fun EmulatorSignIn(app: AqraApp, profile: AccountStore.Profile) {
    var email by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Emulator · ${profile.uid}", style = aqraStyle(11f, Weight.semibold, Palette.inkSoft).copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace))
        if (profile.isAnonymous) {
            AqraTextField(email, { email = it.trim() }, stringResource(R.string.email), keyboard = KeyboardOptions(keyboardType = KeyboardType.Email))
            Text(stringResource(R.string.sign_in_to_the_emulator), style = aqraStyle(13f, Weight.bold, Palette.brand),
                modifier = Modifier.pressable(enabled = email.isNotEmpty() && !app.account.isWorking) { scope.launch { app.account.signInToEmulator(email) } })
        }
    }
}

/** The sources Aqra is built on, credited as their terms ask (see shared/quran/README.md). */
@Composable
private fun SourcesPage() {
    TabPage(top = 16.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(R.string.sources), style = aqraStyle(30f, Weight.heavy, Palette.ink))
            Text(stringResource(R.string.aqra_shows_the_quran_exactly_as_published_from_these_sources), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
        }
        Source("📜", Palette.butter, stringResource(R.string.king_fahd_glorious_quran_printing_complex), stringResource(R.string.the_quran_text_and_its_data_in_the_riwayah_of))
        Source("🖋️", Palette.lavender, "Quran Foundation", stringResource(R.string.the_complexs_mushaf_page_fonts_of_the_1441h_print_with))
        Source("🧩", Palette.sky, "Quranic Universal Library (QUL)", stringResource(R.string.the_mushaf_page_layout_and_the_surah_headers))
        Source("🏷️", Palette.mint, "Ayah by Ayah", stringResource(R.string.the_topic_sections_for_now))
        Source("✒️", Palette.rose, "Amiri", stringResource(R.string.the_typeface_of_the_hadith_under_the_sil_open_font))
    }
}

@Composable
private fun Source(icon: String, tint: Color, name: String, detail: String) {
    AqraCard(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile(icon, tint, size = 40.dp)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(name, style = aqraStyle(16f, Weight.heavy, Palette.ink))
                Text(detail, style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
            }
        }
    }
}

