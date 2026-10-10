package com.azzamalrashed.aqra.core

/**
 * What the Android app doesn't offer yet, kept out of sight rather than leading nowhere. Each turns on once the service
 * behind it is set up; apps/PARITY.md says where each stands.
 */
object Features {
    /** Sign in with Apple goes through Firebase's web flow, which needs the Apple Services ID in the Firebase project. */
    const val APPLE_SIGN_IN = false

    /** Credits are sold through the App Store alone: the server verifies App Store purchases only. */
    const val BUY_CREDITS = false
}
