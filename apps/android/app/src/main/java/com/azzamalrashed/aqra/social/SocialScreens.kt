package com.azzamalrashed.aqra.social

import android.content.Intent
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.PersonRemove
import androidx.compose.material.icons.rounded.QrCode
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.account.AqraTextField
import com.azzamalrashed.aqra.account.Confirm
import com.azzamalrashed.aqra.account.Problem
import com.azzamalrashed.aqra.account.SignInButtons
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.tasmee.PeerRequest
import com.azzamalrashed.aqra.tasmee.QrCode
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraProgress
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.AqraSegmented
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipButton
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.ProblemLine
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressScale
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatDay
import com.azzamalrashed.aqra.ui.util.formatNumber
import kotlinx.coroutines.launch

@Composable
fun Competition.Metric.title(): String = stringResource(
    when (this) {
        Competition.Metric.PAGES_REVISED -> R.string.pages_revised
        Competition.Metric.DAYS_REVISED -> R.string.days_revised
        Competition.Metric.AYAT_MEMORIZED -> R.string.ayat_memorized
        Competition.Metric.PARTS -> R.string.parts_finished
        Competition.Metric.CLEAN_PAGES -> R.string.pages_heard_clean
    },
)

// MARK: - On the progress screen

/** «مع الآخرين»: friends, and the competitions the student is in — constructive, private to their members. */
@Composable
fun TogetherSection(app: AqraApp, store: MushafStore) {
    if (!AccountStore.isAvailable) return
    val account = app.account
    val social = app.social
    var showingFriends by remember { mutableStateOf(false) }
    var creating by remember { mutableStateOf(false) }
    var opened by remember { mutableStateOf<Competition?>(null) }
    var accepting by remember { mutableStateOf<String?>(null) }
    // A race's standings show the student's score as soon as they're in it, not only after their next revision.
    LaunchedEffect(social.competitions) { account.publicName?.let(social::reportScores) }
    // A friend's invitation opened from a link.
    LaunchedEffect(app.router.friendCode) {
        val code = app.router.friendCode ?: return@LaunchedEffect
        app.router.friendCode = null
        accepting = code
    }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        AqraSectionTitle(stringResource(R.string.together), Modifier.padding(top = 10.dp))
        if (account.profile?.isAnonymous != false) {
            AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconTile("🤝", Palette.peach, size = 40.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(stringResource(R.string.compete_with_friends), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                        Text(stringResource(R.string.sign_in_to_add_friends_race_them_and_finish_a), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                    }
                }
                Spacer(Modifier.height(12.dp))
                SignInButtons(app)
            }
        } else {
            AqraCard(Modifier.fillMaxWidth().animateContentSize(), padding = 0.dp, radius = 24.dp) {
                val friends = social.friends
                AqraRow("🤝", Palette.peach, stringResource(R.string.friends), Modifier.pressable(pressed = 0.98f) { showingFriends = true },
                    detail = if (friends.isEmpty()) stringResource(R.string.invite_a_friend_with_a_code)
                        else pluralStringResource(R.plurals.n_friends, friends.size, friends.size))
                for (competition in social.competitions) {
                    AqraRowDivider()
                    val running = competition.isRunning()
                    AqraRow(competition.kind.icon, if (running) Palette.mint else Palette.lavender, competition.title,
                        Modifier.pressable(pressed = 0.98f) { opened = competition },
                        detail = if (running) stringResource(R.string.until_s, formatDay(competition.endsAt.toInstant())) else stringResource(R.string.ended))
                }
                AqraRowDivider()
                AqraRow("➕", Palette.butter, stringResource(R.string.new_competition), Modifier.pressable(pressed = 0.98f) { creating = true }) {}
            }
            social.problem?.let { ProblemLine(it, Modifier.padding(horizontal = 6.dp)) }
        }
    }
    if (showingFriends) AqraSheet(onDismiss = { showingFriends = false }) { FriendsScreen(app) }
    if (creating) {
        AqraSheet(onDismiss = { creating = false }) {
            NewCompetitionScreen(app, listOf(Competition.Kind.FRIENDS, Competition.Kind.KHATMAH)) { creating = false }
        }
    }
    opened?.let { competition -> AqraSheet(onDismiss = { opened = null }) { CompetitionScreen(app, competition) { opened = null } } }
    accepting?.let { code -> AqraSheet(onDismiss = { accepting = null }, fullHeight = false) { AcceptFriendScreen(app, code) { accepting = null } } }
}

// MARK: - Friends

/** The student's friends: an invitation to share, a friend's code to enter, and the friends themselves. */
@Composable
private fun FriendsScreen(app: AqraApp) {
    val social = app.social
    val account = app.account
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var invite by remember { mutableStateOf<FriendInvite?>(null) }
    var making by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }
    var accepting by remember { mutableStateOf<String?>(null) }
    var removing by remember { mutableStateOf<Pair<String, String>?>(null) }

    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        TwoLineHeadline(stringResource(R.string.friends), stringResource(R.string.to_compete_with), size = 28f, alignCenter = false,
            modifier = Modifier.padding(top = 8.dp))
        if (account.publicName == null) NamePrompt(app)

        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile("💌", Palette.rose, size = 40.dp)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(R.string.invite_a_friend), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                    Text(stringResource(R.string.share_your_code_its_valid_for_a_week), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                }
            }
            Spacer(Modifier.height(12.dp))
            val shown = invite
            if (shown != null) {
                val message = stringResource(R.string.be_my_friend_on_aqra_open_this_link_or_enter, shown.id)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    QrCode(shown.link, Modifier.size(84.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        // The code reads left to right in every language.
                        androidx.compose.runtime.CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                            Text(shown.id.toList().joinToString(" "), style = aqraStyle(24f, Weight.heavy, Palette.brand).copy(fontFamily = FontFamily.Monospace))
                        }
                        ChipButton(stringResource(R.string.share), filled = true,
                            leading = { Icon(Icons.Rounded.Share, null, tint = Color.White, modifier = Modifier.size(14.dp)) }) {
                            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "$message\n${shown.link}")
                            context.startActivity(Intent.createChooser(send, null))
                        }
                    }
                }
            } else {
                ChipButton(stringResource(R.string.make_my_code), filled = true, enabled = !making && account.publicName != null,
                    leading = { Icon(Icons.Rounded.QrCode, null, tint = Color.White, modifier = Modifier.size(14.dp)) }) {
                    scope.launch {
                        making = true
                        invite = runCatching { social.createInvite(account.publicName.orEmpty()) }.getOrNull()
                        making = false
                    }
                }
            }
        }

        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AqraTextField(code, { typed -> code = PeerRequest.normalize(typed).take(PeerRequest.CODE_LENGTH) },
                    stringResource(R.string.a_friends_code), Modifier.weight(1f),
                    keyboard = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false))
                ChipButton(stringResource(R.string.add), filled = true, enabled = PeerRequest.isWellFormed(code)) { accepting = code }
            }
        }

        val friends = social.friends
        if (friends.isNotEmpty()) {
            AqraSectionTitle(stringResource(R.string.your_friends), Modifier.padding(top = 6.dp))
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                friends.forEachIndexed { index, friend ->
                    if (index > 0) AqraRowDivider()
                    val label = stringResource(R.string.remove)
                    AqraRow("🙂", Palette.sky, friend.second.ifEmpty { "—" }) {
                        Box(Modifier.size(30.dp).background(Palette.lavender, CircleShape).pressable { removing = friend }
                            .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
                            Icon(Icons.Rounded.PersonRemove, null, tint = Palette.inkSoft, modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }
        }
    }
    accepting?.let { shown -> AqraSheet(onDismiss = { accepting = null }, fullHeight = false) { AcceptFriendScreen(app, shown) { accepting = null } } }
    removing?.let { friend ->
        Confirm(stringResource(R.string.remove_this_friend_q), "", stringResource(R.string.remove), onDismiss = { removing = null }) {
            social.remove(friend.first)
            removing = null
        }
    }
}

/** «أضف صديقًا»: an invitation found by its code, and accepting it. */
@Composable
private fun AcceptFriendScreen(app: AqraApp, code: String, onDone: () -> Unit) {
    val social = app.social
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    var invite by remember { mutableStateOf<FriendInvite?>(null) }
    var loading by remember { mutableStateOf(true) }
    var done by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<Problem?>(null) }
    LaunchedEffect(code) {
        invite = runCatching { social.invite(code) }.getOrNull()
        loading = false
    }
    val mine = invite?.ownerUid == app.account.profile?.uid
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        val shown = invite
        when {
            loading -> Box(Modifier.height(160.dp), contentAlignment = Alignment.Center) { AqraProgress() }
            shown != null && !mine -> {
                Text(if (done) "✅" else "🤝", style = aqraStyle(64f))
                val title = when {
                    shown.ownerName.isEmpty() && done -> stringResource(R.string.youre_friends_now)
                    shown.ownerName.isEmpty() -> stringResource(R.string.add_this_friend_q)
                    done -> stringResource(R.string.youre_friends_with_s, shown.ownerName)
                    else -> stringResource(R.string.be_friends_with_s_q, shown.ownerName)
                }
                Text(title, style = aqraStyle(22f, Weight.heavy, Palette.ink), textAlign = TextAlign.Center)
                Text(stringResource(R.string.friends_see_each_others_names_in_the_competitions_they_share), style = aqraStyle(14f, Weight.medium, Palette.inkSoft),
                    textAlign = TextAlign.Center)
                problem?.let { ProblemLine(it) }
            }
            else -> {
                Text("🔎", style = aqraStyle(56f))
                Text(stringResource(R.string.this_code_isnt_valid_or_it_has_expired), style = aqraStyle(16f, Weight.semibold, Palette.inkSoft), textAlign = TextAlign.Center)
            }
        }
        Spacer(Modifier.height(8.dp))
        if (shown != null && !done && !mine && !loading) {
            BrandButton(stringResource(R.string.become_friends), height = 54.dp, fontSize = 17f) {
                scope.launch {
                    try {
                        social.accept(shown, app.account.publicName.orEmpty())
                        done = true
                        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                    } catch (error: Exception) {
                        problem = AccountStore.problem(error)
                    }
                }
            }
        } else if (!loading) {
            BrandButton(stringResource(R.string.done), height = 54.dp, fontSize = 17f, onClick = onDone)
        }
    }
}

/** The name friends will see, asked for before inviting them when the account has none. */
@Composable
private fun NamePrompt(app: AqraApp) {
    var name by remember { mutableStateOf("") }
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        Text(stringResource(R.string.first_the_name_your_friends_will_see), style = aqraStyle(15f, Weight.heavy, Palette.ink))
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AqraTextField(name, { name = it }, stringResource(R.string.your_name), Modifier.weight(1f))
            ChipButton(stringResource(R.string.save), filled = true, enabled = name.isNotBlank()) { app.account.changeDisplayName(name) }
        }
    }
}

// MARK: - A competition

/** A competition: the standings of a race (the student among them), or a khatmah's thirty parts. */
@Composable
private fun CompetitionScreen(app: AqraApp, competition: Competition, onClose: () -> Unit) {
    val social = app.social
    val live = social.competitions.firstOrNull { it.id == competition.id } ?: competition
    val uid = app.account.profile?.uid
    var members by remember { mutableStateOf<List<CompetitionMember>>(emptyList()) }
    var parts by remember { mutableStateOf<List<KhatmahPart>>(emptyList()) }
    var confirmingLeave by remember { mutableStateOf(false) }
    LaunchedEffect(competition.id) {
        if (competition.kind == Competition.Kind.KHATMAH) social.parts(competition).collect { parts = it }
        else social.members(competition).collect { members = it }
    }
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(live.title, style = aqraStyle(26f, Weight.heavy, Palette.ink))
            val until = if (live.isRunning()) stringResource(R.string.until_s, formatDay(live.endsAt.toInstant())) else stringResource(R.string.ended)
            Text(live.metric.title() + " · " + until, style = aqraStyle(13f, Weight.semibold, Palette.brand))
            if (live.kind == Competition.Kind.TEACHER) {
                Text(stringResource(R.string.scored_from_the_pages_s_hears_clean_in_tasmee, live.ownerName), style = aqraStyle(12f, Weight.medium, Palette.inkSoft))
            }
        }
        if (live.kind == Competition.Kind.KHATMAH) Khatmah(app, live, parts, uid) else Standings(live, members, uid)
        Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if (live.ownerUid == uid && live.isRunning()) {
                Text(stringResource(R.string.end_it_now), style = aqraStyle(14f, Weight.bold, Palette.brand), modifier = Modifier.pressable { social.end(live) }.padding(4.dp))
            }
            if (live.ownerUid != uid) {
                Text(stringResource(R.string.leave), style = aqraStyle(14f, Weight.bold, Palette.danger), modifier = Modifier.pressable { confirmingLeave = true }.padding(4.dp))
            }
        }
    }
    if (confirmingLeave) {
        Confirm(stringResource(R.string.leave_this_competition_q), "", stringResource(R.string.leave), onDismiss = { confirmingLeave = false }) {
            confirmingLeave = false
            social.leave(live)
            onClose()
        }
    }
}

@Composable
private fun Standings(competition: Competition, members: List<CompetitionMember>, uid: String?) {
    AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
        val ranked = CompetitionMember.ranked(members.filter { it.id in competition.memberUids })
        if (ranked.isEmpty()) {
            Text(stringResource(R.string.no_scores_yet_they_appear_as_members_revise), style = aqraStyle(14f, Weight.medium, Palette.inkSoft),
                modifier = Modifier.padding(16.dp))
        }
        ranked.forEachIndexed { index, (rank, member) ->
            if (index > 0) AqraRowDivider()
            val me = member.id == uid
            Row(Modifier.fillMaxWidth().background(if (me) Palette.lavender.copy(alpha = 0.5f) else Color.Transparent).padding(14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.width(38.dp), contentAlignment = Alignment.Center) {
                    Text(if (rank <= 3) listOf("🥇", "🥈", "🥉")[rank - 1] else formatNumber(rank),
                        style = aqraStyle(if (rank <= 3) 22f else 16f, Weight.heavy, Palette.ink))
                }
                Text(member.name.ifEmpty { "—" }, style = aqraStyle(16f, if (me) Weight.heavy else Weight.semibold, if (me) Palette.brand else Palette.ink),
                    modifier = Modifier.weight(1f))
                Text(formatNumber(member.score), style = aqraStyle(17f, Weight.heavy, Palette.ink))
            }
        }
    }
}

@Composable
private fun Khatmah(app: AqraApp, competition: Competition, parts: List<KhatmahPart>, uid: String?) {
    val done = parts.count { it.done }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Text(stringResource(R.string.n_of_30_parts_finished, done), style = aqraStyle(16f, Weight.heavy, Palette.ink))
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(progress = { done / 30f }, modifier = Modifier.fillMaxWidth().height(5.dp), color = Palette.brand,
                trackColor = Palette.lavender, drawStopIndicator = {})
        }
        for (row in parts.chunked(5)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (part in row) PartTile(app, competition, part, uid, Modifier.weight(1f))
                repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        Text(stringResource(R.string.tap_a_free_part_to_take_it_and_tap_yours), style = aqraStyle(12f, Weight.medium, Palette.inkSoft))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PartTile(app: AqraApp, competition: Competition, part: KhatmahPart, uid: String?, modifier: Modifier) {
    val social = app.social
    val mine = part.claimedBy != null && part.claimedBy == uid
    val (top, _) = StepFaces.forJuz(part.id)
    val shape = RoundedCornerShape(14.dp)
    var menu by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val label = stringResource(R.string.juz_n, part.id)
    Box(modifier) {
        Column(
            Modifier.fillMaxWidth().height(56.dp).pressScale(interaction).clip(shape)
                .background(if (part.done) top else if (part.claimedBy == null) Color.White else top.copy(alpha = 0.35f))
                .border(if (mine) 2.dp else 1.dp, if (mine) Palette.brand else Palette.lavender, shape)
                .combinedClickable(interaction, indication = null,
                    onLongClick = { if (mine && !part.done) menu = true },
                    onClick = {
                        if (uid == null) return@combinedClickable
                        if (part.claimedBy == null) social.claim(part, competition, app.account.publicName.orEmpty())
                        else if (mine) social.setDone(!part.done, part, competition)
                    })
                .semantics(mergeDescendants = true) { contentDescription = label },
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
        ) {
            Text(formatNumber(part.id), style = aqraStyle(17f, Weight.heavy, Palette.ink))
            Text(if (part.done) "✓" else part.claimedName.take(6), style = aqraStyle(10f, Weight.bold, if (mine) Palette.brand else Palette.inkSoft), maxLines = 1)
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.give_it_back), style = aqraStyle(15f, Weight.semibold)) },
                onClick = { menu = false; social.release(part, competition) })
        }
    }
}

// MARK: - A new competition

/**
 * Starting a competition: a race among friends, a group khatmah, or — for a teacher — a competition among their
 * students, scored from the pages the teacher hears clean.
 */
@Composable
fun NewCompetitionScreen(app: AqraApp, kinds: List<Competition.Kind>, onDone: () -> Unit) {
    val social = app.social
    val tasmee = app.tasmee
    val scope = rememberCoroutineScope()
    var kind by remember { mutableStateOf(kinds.first()) }
    var title by remember { mutableStateOf("") }
    var metric by remember { mutableStateOf(Competition.Metric.PAGES_REVISED) }
    var days by remember { mutableIntStateOf(7) }
    var chosen by remember { mutableStateOf(emptySet<String>()) }
    var working by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<Problem?>(null) }
    val people = if (kind == Competition.Kind.TEACHER) tasmee.myStudents.map { it.id to it.name } else social.friends
    val trimmed = title.trim()

    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(R.string.new_competition), style = aqraStyle(26f, Weight.heavy, Palette.ink), modifier = Modifier.padding(top = 8.dp))
        if (kinds.size > 1) {
            AqraSegmented(kind, listOf(Competition.Kind.FRIENDS to stringResource(R.string.a_race), Competition.Kind.KHATMAH to stringResource(R.string.a_khatmah_together)),
                { kind = it })
        }
        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Text(stringResource(R.string.name), style = aqraStyle(15f, Weight.bold, Palette.ink))
            Spacer(Modifier.height(8.dp))
            AqraTextField(title, { title = it.take(60) }, stringResource(R.string.ramadans_revision))
            if (kind == Competition.Kind.FRIENDS) {
                Spacer(Modifier.height(14.dp))
                Text(stringResource(R.string.counting), style = aqraStyle(15f, Weight.bold, Palette.ink))
                Spacer(Modifier.height(8.dp))
                Choices(listOf(Competition.Metric.PAGES_REVISED, Competition.Metric.DAYS_REVISED, Competition.Metric.AYAT_MEMORIZED).map { it to it.title() }, metric) { metric = it }
            }
            Spacer(Modifier.height(14.dp))
            Text(stringResource(R.string.for_action), style = aqraStyle(15f, Weight.bold, Palette.ink))
            Spacer(Modifier.height(8.dp))
            Choices(listOf(7 to stringResource(R.string.a_week), 14 to stringResource(R.string.two_weeks), 30 to stringResource(R.string.a_month)), days) { days = it }
        }
        AqraSectionTitle(stringResource(if (kind == Competition.Kind.TEACHER) R.string.your_students else R.string.friends_to_invite), Modifier.padding(top = 6.dp))
        if (people.isEmpty()) {
            Text(stringResource(if (kind == Competition.Kind.TEACHER) R.string.students_appear_here_once_youve_heard_them else R.string.add_friends_first_with_a_code),
                style = aqraStyle(14f, Weight.medium, Palette.inkSoft), modifier = Modifier.padding(horizontal = 6.dp))
        } else {
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                people.forEachIndexed { index, (uid, name) ->
                    if (index > 0) AqraRowDivider()
                    val on = uid in chosen
                    AqraRow(if (kind == Competition.Kind.TEACHER) "🧑‍🎓" else "🙂", Palette.sky, name,
                        Modifier.pressable(pressed = 0.98f) { chosen = if (on) chosen - uid else chosen + uid }) {
                        Icon(if (on) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null,
                            tint = if (on) Palette.brand else Palette.lavender, modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
        problem?.let { ProblemLine(it) }
        BrandButton(stringResource(R.string.start), Modifier.padding(top = 8.dp), height = 54.dp, fontSize = 17f,
            enabled = trimmed.isNotEmpty() && chosen.isNotEmpty() && !working) {
            scope.launch {
                working = true
                val chosenMetric = when (kind) {
                    Competition.Kind.KHATMAH -> Competition.Metric.PARTS
                    Competition.Kind.TEACHER -> Competition.Metric.CLEAN_PAGES
                    Competition.Kind.FRIENDS -> metric
                }
                val owner = if (kind == Competition.Kind.TEACHER) tasmee.teacherProfile?.name.orEmpty() else app.account.publicName.orEmpty()
                try {
                    social.start(kind, trimmed.take(60), chosenMetric, days, owner, chosen.toList())
                    app.account.publicName?.let(social::reportScores)
                    onDone()
                } catch (error: Exception) {
                    problem = AccountStore.problem(error)
                } finally {
                    working = false
                }
            }
        }
    }
}

/** A few choices as capsules, the chosen one filled. */
@Composable
private fun <T> Choices(options: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((value, label) in options) ChipButton(label, filled = value == selection) { onSelect(value) }
    }
}
