package com.azzamalrashed.aqra

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.tasmee.PeerRequest

/** The app's tabs. The Mushaf isn't one: it opens full screen from the home, over everything. */
enum class AppTab { HOME, TASMEE, PROGRESS, ACCOUNT }

/**
 * Where the app is, and the links that move it: `aqra://peer/CODE` (a friend's tasmee' code) and `aqra://friend/CODE`
 * (a friend's invitation).
 */
class AppRouter {
    var tab by mutableStateOf(AppTab.HOME)
    /** A friend's tasmee' code waiting to be heard. */
    var peerCode by mutableStateOf<String?>(null)
    /** A friend's invitation waiting to be accepted. */
    var friendCode by mutableStateOf<String?>(null)

    /** Follows an Aqra link; false when the link isn't one of the app's own. */
    fun open(uri: Uri): Boolean {
        if (uri.scheme != "aqra") return false
        PeerRequest.code(uri.host, uri.lastPathSegment)?.let { code ->
            peerCode = code
            tab = AppTab.TASMEE
            return true
        }
        if (uri.host == "friend") {
            val code = PeerRequest.normalize(uri.lastPathSegment.orEmpty())
            if (!PeerRequest.isWellFormed(code)) return true
            friendCode = code
            tab = AppTab.PROGRESS
        }
        return true
    }
}
