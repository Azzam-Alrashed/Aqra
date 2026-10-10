package com.azzamalrashed.aqra

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.account.CloudSync
import com.azzamalrashed.aqra.account.Journey
import com.azzamalrashed.aqra.account.ReadingStore
import com.azzamalrashed.aqra.core.AssetQuranFiles
import com.azzamalrashed.aqra.core.Preferences
import com.azzamalrashed.aqra.curriculum.AssessmentStore
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.mushaf.MushafFonts
import com.azzamalrashed.aqra.plan.PlanStore
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.recitation.RecitationModel
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.rewards.RewardStore
import com.azzamalrashed.aqra.social.SocialStore
import com.azzamalrashed.aqra.tasmee.TasmeeStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class AqraApplication : Application() {
    lateinit var app: AqraApp
        private set

    override fun onCreate() {
        super.onCreate()
        AccountStore.configure(this)
        app = AqraApp(this)
    }
}

/**
 * Everything the app keeps while it runs: the Quran data, the student's progress, their account and the app's place.
 * Made once, when the app starts.
 */
class AqraApp(application: Application) {
    /** Work that outlives a screen: saving, backing up, applying a tasmee'. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val prefs = Preferences(application)
    val files = AssetQuranFiles(application)
    val fonts = MushafFonts(files)
    val memorization = MemorizationStore(File(application.filesDir, "memorization.json"), scope)
    val revision = RevisionStore(File(application.filesDir, "revision.json"))
    val plan = PlanStore(File(application.filesDir, "plan.json"))
    val rewards = RewardStore(File(application.filesDir, "rewards.json"))
    val assessments = AssessmentStore(File(application.filesDir, "assessments.json"))
    /** The reader's ribbon in the Mushaf. */
    val reading = ReadingStore(File(application.filesDir, "reading.json"))
    val journey = Journey(plan, rewards, assessments, reading)
    val router = AppRouter()
    val sync = CloudSync(memorization, revision, journey, prefs, scope)
    val tasmee = TasmeeStore(memorization, revision, prefs)
    val social = SocialStore(memorization, revision)
    /** The account the progress is backed up to. */
    val account = AccountStore(application, sync, tasmee, social, prefs, scope)
    /** The speech model a revision is followed with, once downloaded. */
    val recitationModel = RecitationModel(application, scope)

    init {
        // A debug build follows a recording placed in the app's files instead of the microphone (RecitationListener).
        if (BuildConfig.DEBUG) com.azzamalrashed.aqra.recitation.AudioSource.testRecording = File(application.filesDir, "recitation-test.wav")
    }

    /** The Mushaf, once loaded: null while it loads, or why it couldn't be. */
    var mushaf: Result<MushafStore>? by mutableStateOf(null)
        private set

    init {
        // Decoding the Quran data takes a moment; keep it off the main thread so the app stays responsive.
        scope.launch {
            val started = System.nanoTime()
            mushaf = withContext(Dispatchers.Default) { runCatching { MushafStore(files) } }
            android.util.Log.i("Aqra", "MushafStore load time: ${(System.nanoTime() - started) / 1_000_000} ms")
            val store = mushaf?.getOrNull() ?: return@launch
            connect(store)
            // A tasmee' waiting in the account can be applied once the Mushaf says which ayat each page holds.
            tasmee.mushaf = store
        }
        account.start()
    }

    /**
     * How the stores answer one another: each revision, portion, teacher's test and stage passed earns its rewards,
     * and may pass a stage or meet a challenge.
     */
    private fun connect(store: MushafStore) {
        revision.onRecord = { record ->
            rewards.revised(record, revision)
            rewards.checkChallenges(revision, plan)
            assessments.checkPasses(store, memorization)
            account.publicName?.let(social::reportScores)
        }
        plan.onPortion = { portion ->
            rewards.memorized(portion, memorization, store)
            rewards.checkChallenges(revision, plan)
            account.publicName?.let(social::reportScores)
        }
        assessments.onPass = { stage -> rewards.passedStage(stage, assessments.passes.size) }
        tasmee.onApplied = { record ->
            assessments.record(record)
            assessments.checkPasses(store, memorization)
        }
    }
}
