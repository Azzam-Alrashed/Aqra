package com.azzamalrashed.aqra.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.azzamalrashed.aqra.AppTab
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AccountScreen
import com.azzamalrashed.aqra.account.DailyReminder
import com.azzamalrashed.aqra.account.SessionReminders
import com.azzamalrashed.aqra.home.HomeScreen
import com.azzamalrashed.aqra.memorization.MemorizationSetupScreen
import com.azzamalrashed.aqra.mushaf.MushafScreen
import com.azzamalrashed.aqra.onboarding.OnboardingScreen
import com.azzamalrashed.aqra.plan.MemorizeScreen
import com.azzamalrashed.aqra.plan.PlanEditorScreen
import com.azzamalrashed.aqra.rewards.CelebrationOverlay
import com.azzamalrashed.aqra.progress.ProgressScreen
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.DailyAmountScreen
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.revision.WirdScreen
import com.azzamalrashed.aqra.tasmee.Booking
import com.azzamalrashed.aqra.tasmee.TasmeeScreen
import com.azzamalrashed.aqra.ui.components.AqraProgress
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import kotlinx.coroutines.launch

/** What opens full screen over the tabs, growing out of the home. */
sealed interface FullScreen {
    data class Mushaf(val marking: Boolean) : FullScreen
    /** Today's wird, from one of its pages; or one page revised outside the app, with its stumbles. */
    data class Wird(val page: Int, val outside: Boolean = false) : FullScreen
    /** Today's new portion, to memorize. */
    data class Memorize(val portion: List<Int>) : FullScreen
    /** Any other full-screen view, such as hearing a student or a friend. */
    class Custom(val key: String, val content: @Composable (close: () -> Unit) -> Unit) : FullScreen
}

/** Opens and closes the full-screen views, from anywhere in the tabs. */
class Overlays {
    var current by mutableStateOf<FullScreen?>(null)
        private set

    fun open(screen: FullScreen) {
        current = screen
    }

    fun close() {
        current = null
    }
}

val LocalOverlays = staticCompositionLocalOf { Overlays() }

/** The app: onboarding on first launch, then «ماذا تحفظ؟» and the daily amount, then the tabs. */
@Composable
fun AqraRoot(app: AqraApp) {
    var hasSeenOnboarding by app.prefs.hasSeenOnboarding
    AnimatedContent(hasSeenOnboarding, transitionSpec = { fadeIn(tween(400)) togetherWith fadeOut(tween(300)) }, label = "root") { seen ->
        if (seen) MushafRoot(app) else OnboardingScreen { hasSeenOnboarding = true }
    }
}

/** Loads the Mushaf once, then shows the app, or explains what's missing. */
@Composable
private fun MushafRoot(app: AqraApp) {
    var hasDeclared by app.prefs.hasDeclared
    var startsMarking by rememberSaveable { mutableStateOf(false) }
    /** After choosing what they've memorized, the student chooses how much to revise each day (1), then their plan (2). */
    var setupStep by rememberSaveable { mutableIntStateOf(0) }
    /** When they chose to mark it in the Mushaf instead, the same two steps follow the marking. */
    var afterMarking by app.prefs.setupAfterMarking
    // After signing out, setup starts from «ماذا تحفظ؟» again.
    LaunchedEffect(hasDeclared) {
        if (!hasDeclared) {
            setupStep = 0
            afterMarking = ""
        }
    }
    // Once the setup's marking is over, the home that comes back doesn't open the Mushaf on its own again; and a
    // marking cut short (the app was closed during it) goes on to its next steps.
    LaunchedEffect(afterMarking) { if (afterMarking != AFTER_MARKING) startsMarking = false }
    LaunchedEffect(Unit) { if (afterMarking == AFTER_MARKING && !startsMarking) afterMarking = nextAfterMarking(app) }
    /** «رجوع» on «كم تراجع كل يوم؟»: back to «ماذا تحفظ؟», or to the marking in the Mushaf when that came before. */
    fun backToMemorized() {
        if (afterMarking.isNotEmpty()) {
            startsMarking = true
            afterMarking = AFTER_MARKING
        } else {
            setupStep = 0
        }
    }
    /** «رجوع» on the plan's first page: back to the daily revision, or, with nothing memorized, to the step before it. */
    fun backFromPlan() {
        when {
            app.memorization.count == 0 -> backToMemorized()
            afterMarking == AFTER_MARKING_PLAN -> afterMarking = AFTER_MARKING_AMOUNT
            else -> setupStep = 1
        }
    }

    val result = app.mushaf
    when {
        result == null -> Box(Modifier.fillMaxSize().background(MushafStyle.current().paper), contentAlignment = Alignment.Center) {
            AqraProgress(color = MushafStyle.current().chrome)
        }
        result.isFailure -> Column(
            Modifier.fillMaxSize().background(Palette.surface).padding(32.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(stringResource(R.string.the_mushaf_couldnt_be_loaded), style = aqraStyle(20f, Weight.heavy, Palette.ink), textAlign = TextAlign.Center)
            Text(result.exceptionOrNull()?.message.orEmpty(), style = aqraStyle(14f, Weight.medium, Palette.inkSoft), textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 8.dp))
        }
        else -> {
            val store = result.getOrThrow()
            AnimatedContent(
                targetState = when {
                    afterMarking == AFTER_MARKING_AMOUNT -> 1
                    afterMarking == AFTER_MARKING_PLAN -> 2
                    hasDeclared -> 3
                    else -> setupStep
                },
                transitionSpec = { slideInHorizontally { -it } + fadeIn() togetherWith slideOutHorizontally { it } + fadeOut() },
                label = "setup",
            ) { step ->
                when (step) {
                    0 -> MemorizationSetupScreen(app, store, isSheet = false) { markInMushaf ->
                        startsMarking = markInMushaf
                        when {
                            markInMushaf -> {
                                afterMarking = AFTER_MARKING
                                hasDeclared = true
                            }
                            // With something memorized, its daily revision first; starting from zero, straight to the plan.
                            app.memorization.count > 0 -> setupStep = 1
                            else -> setupStep = 2
                        }
                    }
                    1 -> {
                        val pages = RevisionStore.memorizedPages(store, app.memorization).size
                        DailyAmountScreen(pages, app.revision.effectiveDailyPages(pages), isEditor = false, onBack = ::backToMemorized) { amount ->
                            app.revision.setDailyPages(amount)
                            setupStep = 2
                            if (afterMarking == AFTER_MARKING_AMOUNT) afterMarking = AFTER_MARKING_PLAN
                        }
                    }
                    2 -> PlanEditorScreen(app, store, isSetup = true, onBack = ::backFromPlan) {
                        hasDeclared = true
                        afterMarking = ""
                    }
                    else -> AppTabs(app, store, startsMarking)
                }
            }
        }
    }
}

/** The app after setup: the home, tasmee', progress and account tabs, under the app's own floating tab bar. */
@Composable
private fun AppTabs(app: AqraApp, store: MushafStore, startsMarking: Boolean) {
    val overlays = remember { Overlays() }
    val router = app.router
    val navigators = remember { AppTab.entries.associateWith { Navigator() } }

    // Today's plan is made (or kept) whenever the app comes back and whenever what's memorized changes; a challenge
    // may have ended while it was away.
    val count = app.memorization.count
    LaunchedEffect(count) { app.revision.refreshPlan(RevisionStore.memorizedPages(store, app.memorization)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        app.revision.refreshPlan(RevisionStore.memorizedPages(store, app.memorization))
        app.rewards.checkChallenges(app.revision, app.plan)
        // Back in the foreground: what another device wrote to the account meanwhile is merged in.
        app.scope.launch { app.sync.syncIfChanged() }
    }
    // The account's copy merged in (another device revised): today's plan follows.
    val lastMerge = app.sync.lastMerge
    LaunchedEffect(lastMerge) { if (lastMerge != null) app.revision.refreshPlan(RevisionStore.memorizedPages(store, app.memorization)) }
    // A reminder an hour before each booked session, as the sessions are now; set again once the daily reminder has
    // been allowed to notify.
    val context = LocalContext.current
    val bookings = app.tasmee.upcomingBookings.map { booking ->
        val live = app.tasmee.session(booking)
        (live?.let(::Booking) ?: booking) to live?.status
    }
    LaunchedEffect(bookings, app.prefs.reminderOn.value) { SessionReminders.schedule(context, bookings) }
    // Today's reminder, if it was shown, goes once today's work is done.
    LaunchedEffect(app.revision.plan?.isComplete, app.plan.portions.size) { DailyReminder.withdrawIfDone(context, app) }
    // After choosing to mark in the Mushaf, the app opens straight on it, with the home underneath.
    LaunchedEffect(Unit) { if (startsMarking) overlays.open(FullScreen.Mushaf(marking = true)) }

    CompositionLocalProvider(LocalOverlays provides overlays) {
        Box(Modifier.fillMaxSize().background(Palette.surface)) {
            AnimatedContent(router.tab, transitionSpec = { fadeIn(tween(220)) togetherWith fadeOut(tween(160)) }, label = "tabs") { tab ->
                val navigator = navigators.getValue(tab)
                when (tab) {
                    AppTab.HOME -> HomeScreen(app, store)
                    AppTab.TASMEE -> TasmeeScreen(app, store, navigator)
                    AppTab.PROGRESS -> ProgressScreen(app, store)
                    AppTab.ACCOUNT -> AccountScreen(app, navigator)
                }
            }
            AqraTabBar(router.tab, Modifier.align(Alignment.BottomCenter)) { router.tab = it }
            // Rewards are celebrated over the tabs, never over the Mushaf's own reading.
            if (overlays.current == null) CelebrationOverlay(app)

            val current = overlays.current
            AnimatedVisibility(
                visible = current != null,
                enter = scaleIn(initialScale = 0.92f, animationSpec = spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow)) + fadeIn(),
                exit = scaleOut(targetScale = 0.94f) + fadeOut(),
            ) {
                var shown by remember { mutableStateOf(current) }
                if (current != null) shown = current
                // Touches stay in the full-screen view rather than reaching the tabs beneath it.
                Box(Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures {} }) {
                    when (val screen = shown) {
                        is FullScreen.Mushaf -> MushafWithSetup(app, store, screen.marking, overlays)
                        is FullScreen.Wird -> WirdScreen(app, store, screen.page, screen.outside) { overlays.close() }
                        is FullScreen.Memorize -> MemorizeScreen(app, store, screen.portion) { overlays.close() }
                        is FullScreen.Custom -> screen.content { overlays.close() }
                        null -> Unit
                    }
                }
            }
        }
    }
}

private const val AFTER_MARKING = "marking"
private const val AFTER_MARKING_AMOUNT = "dailyAmount"
private const val AFTER_MARKING_PLAN = "plan"

/** The step after the setup's marking: the daily amount when anything is marked, else the plan. */
private fun nextAfterMarking(app: AqraApp) = if (app.memorization.count > 0) AFTER_MARKING_AMOUNT else AFTER_MARKING_PLAN

/** The Mushaf, with the juz' and surahs sheet its marking bar opens. */
@Composable
private fun MushafWithSetup(app: AqraApp, store: MushafStore, marking: Boolean, overlays: Overlays) {
    var choosing by remember { mutableStateOf(false) }
    var afterMarking by app.prefs.setupAfterMarking
    MushafScreen(app, store, startsMarking = marking, onClose = {
        overlays.close()
        // The setup's marking is over once the Mushaf closes: the daily amount and the plan follow.
        if (afterMarking == AFTER_MARKING) afterMarking = nextAfterMarking(app)
    }, onChooseJuzAndSurahs = { choosing = true })
    if (choosing) {
        AqraSheet(onDismiss = { choosing = false }) {
            MemorizationSetupScreen(app, store, isSheet = true) { choosing = false }
        }
    }
}

/** A screen's own stack of pages within a tab: a teacher, a session, the sources. */
class Navigator {
    val stack = mutableStateListOf<Any>()

    fun push(destination: Any) {
        stack += destination
    }

    fun pop() {
        if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex)
    }
}

/** Shows a tab's root, or the page on top of its stack, sliding in the reading direction; back goes back. */
@Composable
fun NavigatorHost(navigator: Navigator, root: @Composable () -> Unit, destination: @Composable (Any) -> Unit) {
    BackHandler(enabled = navigator.stack.isNotEmpty()) { navigator.pop() }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val top = navigator.stack.lastOrNull()
    val depth = navigator.stack.size
    AnimatedContent(
        targetState = depth to top,
        transitionSpec = {
            val forward = targetState.first > initialState.first
            val sign = (if (forward) 1 else -1) * (if (rtl) -1 else 1)
            slideInHorizontally(spring(dampingRatio = 0.9f, stiffness = Spring.StiffnessMediumLow)) { it * sign } + fadeIn() togetherWith
                slideOutHorizontally(spring(dampingRatio = 0.9f, stiffness = Spring.StiffnessMediumLow)) { -it * sign / 3 } + fadeOut()
        },
        label = "navigator",
    ) { (_, page) ->
        if (page == null) root() else destination(page)
    }
}
