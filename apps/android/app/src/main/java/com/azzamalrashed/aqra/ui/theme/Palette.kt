package com.azzamalrashed.aqra.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.isSystemInDarkTheme
import com.azzamalrashed.aqra.R

/** The app's colors, as the onboarding set them: the colored-Mushaf pastels on a soft lavender surface. */
object Palette {
    val surface = Color(0xFFF7F4FB)
    val ink = Color(0xFF241A33)
    val inkSoft = Color(0xFF7B7290)
    val brand = Color(0xFF5B2D91)
    val brandDeep = Color(0xFF3E1D66)
    val gold = Color(0xFFE8B64C)
    val butter = Color(0xFFFFF1C7)
    val peach = Color(0xFFFFE2CF)
    val rose = Color(0xFFFCDCE7)
    val lavender = Color(0xFFE9DEFA)
    val sky = Color(0xFFDCEBFB)
    val mint = Color(0xFFD8F2E3)
    val shadow = Color(0xFF5B2D91)
    /** A calm warning: what went wrong, a follow-up page, a stumble count. */
    val warning = Color(0xFF9A3E26)
    val danger = Color(0xFFB3261E)
    val success = Color(0xFF1F7A4D)
    val brandGradient = listOf(brand, brandDeep)
}

/** The منازل steps' colors, bottom to top: butter, peach, rose, lavender, sky (top and bottom of each step). */
object StepFaces {
    val faces: List<Pair<Color, Color>> = listOf(
        Color(0xFFFFE7A3) to Color(0xFFF4C65E), // butter
        Color(0xFFFFCDAE) to Color(0xFFF29D72), // peach
        Color(0xFFFBBCD0) to Color(0xFFE7849F), // rose
        Color(0xFFD9C6F7) to Color(0xFFA98BE3), // lavender
        Color(0xFFB9D8F7) to Color(0xFF7FAEE6), // sky
    )

    /** A juz's band colors: six juz' (two steps) per band, bottom to top. */
    fun forJuz(juz: Int): Pair<Color, Color> = faces[((juz - 1).coerceAtLeast(0) / 6).coerceAtMost(faces.size - 1)]
}

/**
 * The Mushaf's look: warm paper, dark ink, gold ornament — and in dark mode, a deep warm page (not pure black) with
 * cream ink and lighter gold.
 */
class MushafStyle(val dark: Boolean) {
    private fun pick(light: Long, dark: Long) = Color(if (this.dark) dark else light)

    val paper = pick(0xFFFBF7EE, 0xFF1A1612)
    val ink = pick(0xFF1C1712, 0xFFEFE6D4)
    val chrome = pick(0xFF8A7A64, 0xFFA8977B)
    val gold = pick(0xFFC9A24A, 0xFFD4B160)
    /** The surah header frame and calligraphy. */
    val ornament = pick(0xFF9A7440, 0xFFC9A35E)
    /** Ayah-end markers: a soft disc behind a brown-gold rosette and number. */
    val markerFill = pick(0xFFF1E4C8, 0xFF3A2F22)
    val marker = pick(0xFF8C6A3F, 0xFFD9BC82)
    /** In revision, the soft bars that veil words not yet revealed, and the wash behind an ayah stumbled on. */
    val veil = pick(0xFFE6DAC2, 0xFF3C3228)
    val stumble = pick(0xFFF4BFAE, 0xFF7C3B2D)
    val stumbleText = pick(0xFF9A3E26, 0xFFF6C9B8)
    /** While choosing how much of a portion was memorized: the wash behind the ayat chosen. */
    val chosen = pick(0xFFCDEBD8, 0xFF24452F)
    /** The bars floating over the page, in the app's colors: white capsules, purple controls on lavender. */
    val barFill = pick(0xFFFFFFFF, 0xFF2B2622)
    val barAccent = pick(0xFF5B2D91, 0xFFCDB8F2)
    val barAccentFill = pick(0xFFE9DEFA, 0xFF3B3150)

    /**
     * Topic sections, in the soft pastels of a colored Mushaf: mint, sky, rose, lavender, butter and peach.
     * Neighboring sections always take different colors.
     */
    private val topics = if (dark) {
        listOf(0xFF22382B, 0xFF1F3243, 0xFF3F252D, 0xFF2D2843, 0xFF3B3320, 0xFF40291E)
    } else {
        listOf(0xFFD9F0E0, 0xFFD7EAF6, 0xFFF6DCE3, 0xFFE5DEF3, 0xFFF6EBC6, 0xFFF8DFCE)
    }.map(::Color)

    fun topic(section: Int): Color = topics[section % topics.size]

    companion object {
        val LIGHT = MushafStyle(dark = false)
        val DARK = MushafStyle(dark = true)

        @Composable
        @ReadOnlyComposable
        fun current(): MushafStyle = if (isSystemInDarkTheme()) DARK else LIGHT
    }
}

/** The hadith's typeface (Amiri, under the SIL Open Font License); the Quran's fonts are only for the Mushaf. */
val Amiri = FontFamily(
    Font(R.font.amiri_regular, FontWeight.Normal),
    Font(R.font.amiri_bold, FontWeight.Bold),
)

/**
 * The app's own voice, in the system font: sizes in points, as the iOS app sets them. Each text runs in its own
 * direction (English stays left to right in the Mushaf's right-to-left bars).
 */
fun aqraStyle(size: Float, weight: FontWeight = FontWeight.Normal, color: Color = Color.Unspecified, lineHeight: TextUnit = TextUnit.Unspecified) =
    TextStyle(fontSize = size.sp, fontWeight = weight, color = color, lineHeight = if (lineHeight == TextUnit.Unspecified) 1.25.em else lineHeight,
        textDirection = TextDirection.Content)

/** SwiftUI's weights, as Compose's: heavy, bold, semibold and medium. */
object Weight {
    val heavy = FontWeight.ExtraBold
    val black = FontWeight.Black
    val bold = FontWeight.Bold
    val semibold = FontWeight.SemiBold
    val medium = FontWeight.Medium
}
