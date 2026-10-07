package com.azzamalrashed.aqra

import android.content.Intent
import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import com.azzamalrashed.aqra.ui.AqraRoot
import com.azzamalrashed.aqra.ui.theme.Palette

class MainActivity : AppCompatActivity() {
    private val app get() = (application as AqraApplication).app

    override fun onCreate(savedInstanceState: Bundle?) {
        // The app's own screens are light (their dark mode isn't designed yet); the Mushaf follows the system.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) open(intent)
        setContent {
            MaterialTheme(colorScheme = lightColorScheme(primary = Palette.brand, secondary = Palette.brand, surface = Palette.surface, background = Palette.surface)) {
                AqraRoot(app)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        open(intent)
    }

    /** An Aqra link (a friend's tasmee' code) opened from outside the app. */
    private fun open(intent: Intent?) {
        intent?.data?.let(app.router::open)
    }
}
