package com.azzamalrashed.aqra.account

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.azzamalrashed.aqra.BuildConfig
import com.azzamalrashed.aqra.core.Preferences
import com.azzamalrashed.aqra.credits.WalletStore
import com.azzamalrashed.aqra.social.SocialStore
import com.azzamalrashed.aqra.tasmee.TasmeeStore
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.AuthCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthRecentLoginRequiredException
import com.google.firebase.auth.FirebaseAuthUserCollisionException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.auth.OAuthCredential
import com.google.firebase.auth.OAuthProvider
import com.google.firebase.auth.userProfileChangeRequest
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.storage.FirebaseStorage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.io.IOException

/**
 * Who the student is. Every install starts as an anonymous account, so progress is backed up from the first day;
 * signing in with Apple or Google links that sign-in to the same account, so nothing is lost.
 */
class AccountStore(
    private val context: Context,
    val sync: CloudSync,
    /** Teachers, sessions and tasmee' records, through the same account. */
    val tasmee: TasmeeStore,
    /** Friends and competitions, through the same account. */
    val social: SocialStore,
    private val prefs: Preferences,
    private val scope: CoroutineScope,
) {
    /** Credits, and a teacher's earnings. */
    val wallet = WalletStore()
    /** Messages from the server and the team. */
    val inbox = InboxStore()

    enum class Provider(val id: String) { APPLE("apple.com"), GOOGLE("google.com") }

    data class Profile(val uid: String, val isAnonymous: Boolean, val name: String?, val email: String?, val provider: Provider?)

    var profile: Profile? by mutableStateOf(null)
        private set
    /** The name the student chose to be shown to teachers, peers and friends, kept in their account. */
    var displayName: String? by mutableStateOf(null)
        private set
    /** A sign-in, sign-out or deletion is under way. */
    var isWorking by mutableStateOf(false)
        private set
    var problem: Problem? by mutableStateOf(null)

    private var listener: FirebaseAuth.AuthStateListener? = null
    private var userListener: ListenerRegistration? = null

    companion object {
        /** Whether accounts are set up in this build: they need the Firebase config, which isn't in git. */
        val isAvailable: Boolean get() = FirebaseApp.getApps(appContext ?: return false).isNotEmpty()

        /** Debug builds made with `-PuseFirebaseEmulator` talk only to the local emulators, as the project `demo-aqra`. */
        val usesEmulator: Boolean get() = BuildConfig.DEBUG && BuildConfig.USE_FIREBASE_EMULATOR

        private var appContext: Context? = null

        /** Where the Cloud Functions run: beside the database and files, in Belgium. */
        const val FUNCTIONS_REGION = "europe-west1"

        val functions: FirebaseFunctions get() = FirebaseFunctions.getInstance(FUNCTIONS_REGION)

        /**
         * Sets up Firebase from the config bundled by the google-services plugin, unless it's missing; or, for the
         * emulators, with made-up options (the emulators check none of them, and the project's name keeps the
         * Firestore cache apart from the real project's). The API key only has to look like one: Cloud Functions
         * refuses to call out without a well-formed key. The Android emulator reaches the computer at 10.0.2.2.
         */
        fun configure(context: Context) {
            appContext = context.applicationContext
            if (usesEmulator) {
                if (FirebaseApp.getApps(context).isEmpty()) {
                    FirebaseApp.initializeApp(context, FirebaseOptions.Builder()
                        .setProjectId("demo-aqra").setApplicationId("1:000000000000:android:0000000000000000").setApiKey("AIzaAqra-local-emulators-only-000000000")
                        .build())
                }
                val host = "10.0.2.2"
                FirebaseAuth.getInstance().useEmulator(host, 9099)
                FirebaseFirestore.getInstance().useEmulator(host, 8080)
                FirebaseStorage.getInstance().useEmulator(host, 9199)
                functions.useEmulator(host, 5001)
                return
            }
            if (BuildConfig.HAS_FIREBASE_CONFIG && FirebaseApp.getApps(context).isEmpty()) FirebaseApp.initializeApp(context)
        }

        /** What to tell the student about an error from the account: offline, or something else. */
        fun problem(error: Throwable): Problem =
            if (error is FirebaseNetworkException || error is IOException || error is TimeoutCancellationException ||
                (error is com.google.firebase.firestore.FirebaseFirestoreException && error.code == com.google.firebase.firestore.FirebaseFirestoreException.Code.UNAVAILABLE)
            ) Problem.OFFLINE else Problem.FAILED
    }

    private val auth get() = FirebaseAuth.getInstance()

    /** Follows the signed-in account, and signs in anonymously when there's none. */
    fun start() {
        if (!isAvailable || listener != null) return
        val listener = FirebaseAuth.AuthStateListener { auth ->
            val user = auth.currentUser
            refreshProfile(user)
            watchDisplayName(user?.uid)
            if (user != null) {
                inbox.attach(user.uid)
                wallet.attach(user.uid, named = !user.isAnonymous)
                scope.launch {
                    // The backup first, so a tasmee' arriving isn't applied over a copy being restored.
                    sync.attach(user.uid)
                    tasmee.attach(user.uid)
                    social.attach(user.uid)
                }
            } else {
                auth.signInAnonymously()
            }
        }
        this.listener = listener
        auth.addAuthStateListener(listener)
    }

    private fun refreshProfile(user: FirebaseUser? = auth.currentUser) {
        if (user == null) {
            profile = null
            return
        }
        val linked = user.providerData.firstOrNull { info -> Provider.entries.any { it.id == info.providerId } }
        profile = Profile(
            uid = user.uid, isAnonymous = user.isAnonymous,
            name = user.displayName?.takeIf { it.isNotEmpty() } ?: linked?.displayName?.takeIf { it.isNotEmpty() },
            email = user.email?.takeIf { it.isNotEmpty() } ?: linked?.email,
            provider = linked?.let { info -> Provider.entries.firstOrNull { it.id == info.providerId } },
        )
    }

    // MARK: - The name shown to others

    /** The name others see: the one the student chose, else their sign-in's name. Never an email, never anonymous. */
    val publicName: String?
        get() {
            val profile = profile ?: return null
            if (profile.isAnonymous) return null
            return displayName ?: profile.name
        }

    private fun watchDisplayName(uid: String?) {
        userListener?.remove()
        userListener = null
        displayName = null
        uid ?: return
        userListener = FirebaseFirestore.getInstance().collection("users").document(uid).addSnapshotListener { snapshot, _ ->
            val name = snapshot?.getString("displayName")?.trim()
            displayName = name?.takeIf { it.isNotEmpty() }
        }
    }

    /** Changes the name shown to others (queued while offline); an empty name goes back to the sign-in's. */
    fun changeDisplayName(name: String) {
        val uid = profile?.uid ?: return
        val trimmed = name.trim().take(40)
        displayName = trimmed.ifEmpty { null }
        FirebaseFirestore.getInstance().collection("users").document(uid)
            .set(mapOf("displayName" to if (trimmed.isEmpty()) FieldValue.delete() else trimmed), SetOptions.merge())
    }

    // MARK: - Signing in

    /**
     * The web client id the google-services plugin writes from the Firebase config, or null without it. Looked up by
     * name because builds without the config (which isn't in git) don't have the resource at all.
     */
    @get:android.annotation.SuppressLint("DiscouragedApi")
    private val googleClientId: String?
        get() = context.resources.getIdentifier("default_web_client_id", "string", context.packageName)
            .takeIf { it != 0 }?.let(context::getString)

    suspend fun signInWithGoogle(activity: Activity) {
        problem = null
        val clientId = googleClientId ?: run { problem = Problem.FAILED; return }
        try {
            val token = googleIdToken(activity, clientId)
            link(GoogleAuthProvider.getCredential(token, null), name = null)
        } catch (_: GetCredentialCancellationException) {
        } catch (_: androidx.credentials.exceptions.NoCredentialException) {
            // No Google account on the device to choose.
            problem = Problem.FAILED
        } catch (error: Exception) {
            problem = problem(error)
        }
    }

    private suspend fun googleIdToken(activity: Activity, clientId: String): String {
        val request = GetCredentialRequest.Builder().addCredentialOption(GetSignInWithGoogleOption.Builder(clientId).build()).build()
        val result = CredentialManager.create(activity).getCredential(activity, request)
        val credential = result.credential as? CustomCredential
        require(credential?.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) { "Not a Google credential" }
        return GoogleIdTokenCredential.createFrom(credential.data).idToken
    }

    /**
     * Sign in with Apple, through Apple's web page (Android has no Apple sign-in of its own). Linked to this install's
     * account like any other sign-in; Apple shares the name only on the first sign-in.
     */
    suspend fun signInWithApple(activity: Activity) {
        isWorking = true
        problem = null
        try {
            val provider = OAuthProvider.newBuilder(Provider.APPLE.id).setScopes(listOf("email", "name")).build()
            val user = auth.currentUser
            if (user != null) {
                try {
                    val result = user.startActivityForLinkWithProvider(activity, provider).await()
                    result.user?.let { setName(result.additionalUserInfo?.profile, it) }
                    result.user?.let { wallet.attach(it.uid, named = true) }
                } catch (collision: FirebaseAuthUserCollisionException) {
                    // The Apple ID already belongs to an account: use that one, which merges this device's progress in.
                    auth.signInWithCredential(collision.updatedCredential ?: throw collision).await()
                }
            } else {
                auth.startActivityForSignInWithProvider(activity, provider).await()
            }
            refreshProfile()
        } catch (error: Exception) {
            if (!isCancellation(error)) problem = problem(error)
        } finally {
            isWorking = false
        }
    }

    /**
     * Links a sign-in to the current account, keeping its progress. When the sign-in already belongs to another
     * account (a previous install, another device), that account is used instead and this device's progress is merged
     * into it.
     */
    private suspend fun link(credential: AuthCredential, name: String?) {
        isWorking = true
        problem = null
        try {
            val user = auth.currentUser
            if (user != null) {
                try {
                    val result = user.linkWithCredential(credential).await()
                    if (name != null) result.user?.let { setDisplayNameOnce(it, name) }
                    result.user?.let { wallet.attach(it.uid, named = true) }
                } catch (collision: FirebaseAuthUserCollisionException) {
                    // The state listener attaches the backup to that account, which merges this device's progress in.
                    auth.signInWithCredential(collision.updatedCredential ?: credential).await()
                }
            } else {
                auth.signInWithCredential(credential).await()
            }
            refreshProfile()
        } catch (error: Exception) {
            problem = problem(error)
        } finally {
            isWorking = false
        }
    }

    /** Apple shares the name only on the first sign-in; it's kept as the account's display name. */
    private suspend fun setName(appleProfile: Map<String, Any>?, user: FirebaseUser) {
        val name = (appleProfile?.get("name") as? Map<*, *>)?.let { listOf(it["firstName"], it["lastName"]) }
            ?.filterIsInstance<String>()?.joinToString(" ")?.trim()
        if (!name.isNullOrEmpty()) setDisplayNameOnce(user, name)
    }

    private suspend fun setDisplayNameOnce(user: FirebaseUser, name: String) {
        if (!user.displayName.isNullOrEmpty()) return
        runCatching { user.updateProfile(userProfileChangeRequest { displayName = name }).await() }
    }

    /** Signs in to the Auth emulator as a made-up Google account, linking it exactly as a real sign-in would. */
    suspend fun signInToEmulator(email: String) {
        val token = """{"sub":"$email","email":"$email","email_verified":true}"""
        link(GoogleAuthProvider.getCredential(token, null), name = null)
    }

    // MARK: - Signing out and deleting

    /**
     * Signs out after making sure the account holds everything, then clears this device and starts afresh. Returns
     * false when the account couldn't be reached, so nothing was changed.
     */
    suspend fun signOut(): Boolean {
        isWorking = true
        problem = null
        try {
            try {
                sync.uploadNow()
            } catch (_: Exception) {
                problem = Problem.OFFLINE
                return false
            }
            sync.detach()
            tasmee.detach()
            social.detach()
            wallet.detach()
            inbox.detach()
            runCatching { CredentialManager.create(context).clearCredentialState(androidx.credentials.ClearCredentialStateRequest()) }
            auth.signOut()
            sync.clearDevice()
            // Back to «ماذا تحفظ؟», as on a new install; the listener signs in anonymously.
            prefs.hasDeclared.value = false
            return true
        } finally {
            isWorking = false
        }
    }

    /**
     * Deletes the account and everything it holds. The progress on this device stays, under a new anonymous account.
     * Apple accounts are signed in again first, so Apple's token can be revoked as Apple requires.
     */
    suspend fun deleteAccount(activity: Activity): Boolean {
        val user = auth.currentUser ?: return false
        isWorking = true
        problem = null
        try {
            if (profile?.provider == Provider.APPLE) {
                val provider = OAuthProvider.newBuilder(Provider.APPLE.id).build()
                val result = user.startActivityForReauthenticateWithProvider(activity, provider).await()
                (result.credential as? OAuthCredential)?.accessToken?.let { token -> runCatching { auth.revokeAccessToken(token).await() } }
            }
            tasmee.deleteAccountData(user.uid)
            social.deleteAccountData(user.uid)
            sync.deleteAccountData(user.uid)
            try {
                user.delete().await()
            } catch (_: FirebaseAuthRecentLoginRequiredException) {
                val clientId = googleClientId ?: throw IllegalStateException("No Google client")
                user.reauthenticate(GoogleAuthProvider.getCredential(googleIdToken(activity, clientId), null)).await()
                user.delete().await()
            }
            sync.detach()
            tasmee.detach()
            social.detach()
            wallet.detach()
            inbox.detach()
            return true
        } catch (error: Exception) {
            if (!isCancellation(error)) problem = problem(error)
            return false
        } finally {
            isWorking = false
        }
    }

    private fun isCancellation(error: Exception) =
        error is GetCredentialCancellationException ||
            (error is com.google.firebase.auth.FirebaseAuthException && error.errorCode == "ERROR_WEB_CONTEXT_CANCELED")
}
