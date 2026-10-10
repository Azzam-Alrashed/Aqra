package com.azzamalrashed.aqra.memorization

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.ReviewPolicy
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.ui.components.AqraBackButton
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraSegmented
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumber

/**
 * «كيف حفظك في كل جزء؟»: right after «ماذا تحفظ؟», how firm each juz' declared is (its starting half-life, see
 * [ReviewPolicy.Firmness]), and «أين وصلت في مراجعتك؟», the juz' the rotation continues from. As on iOS.
 */
@Composable
fun MemorizationFirmnessScreen(app: AqraApp, store: MushafStore, onBack: () -> Unit, onDone: () -> Unit) {
    val memorization = app.memorization
    val juzList = remember(memorization.count) {
        (1..30).filter { juz -> store.juzAyahs[juz]?.let { memorization.memorizedCount(it) > 0 } ?: false }
    }
    val firmness = remember { mutableStateMapOf<Int, ReviewPolicy.Firmness>() }
    var startJuz by rememberSaveable { mutableStateOf(juzList.firstOrNull() ?: 1) }
    var choosingStart by remember { mutableStateOf(false) }

    fun apply() {
        for (juz in juzList) {
            val range = store.juzAyahs[juz] ?: continue
            memorization.setFirmness(firmness[juz] ?: ReviewPolicy.Firmness.MIDDLING, range, app.revision.policy)
        }
        RevisionStore.memorizedPages(store, memorization).firstOrNull { store.page(it).juz == startJuz }?.let { app.revision.setRotationStart(it) }
    }

    Box(Modifier.fillMaxSize().background(Palette.surface)) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 22.dp).padding(bottom = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.padding(top = 56.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                TwoLineHeadline(stringResource(R.string.how_firm_is), stringResource(R.string.each_juz_q), size = 28f)
                Text(stringResource(R.string.your_strength_starts_from_it_and_grows_as_you_revise),
                    style = aqraStyle(14f, Weight.semibold, Palette.inkSoft), textAlign = TextAlign.Center)
            }
            Column(
                Modifier.weight(1f).widthIn(max = 560.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                for (juz in juzList) {
                    val face = StepFaces.forJuz(juz).first
                    Column(
                        Modifier.fillMaxWidth().shadow(8.dp, RoundedCornerShape(20.dp), ambientColor = Palette.shadow.copy(alpha = 0.05f), spotColor = Palette.shadow.copy(alpha = 0.05f))
                            .background(Color.White, RoundedCornerShape(20.dp)).padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Box(Modifier.size(34.dp).background(face, CircleShape), contentAlignment = Alignment.Center) {
                                Text(formatNumber(juz), style = aqraStyle(14f, Weight.bold, Palette.ink))
                            }
                            Text(stringResource(R.string.juz_n, juz), style = aqraStyle(17f, Weight.heavy, Palette.ink))
                        }
                        AqraSegmented(
                            firmness[juz] ?: ReviewPolicy.Firmness.MIDDLING,
                            listOf(
                                ReviewPolicy.Firmness.FIRM to stringResource(R.string.firm),
                                ReviewPolicy.Firmness.MIDDLING to stringResource(R.string.fair),
                                ReviewPolicy.Firmness.WEAK to stringResource(R.string.needs_revision),
                            ),
                            onSelect = { firmness[juz] = it }, scale = 0.84f, modifier = Modifier.align(Alignment.CenterHorizontally),
                        )
                    }
                }
                // «أين وصلت في مراجعتك؟»: the juz' the rotation continues from.
                Box(Modifier.padding(top = 8.dp)) {
                    AqraCard(Modifier.fillMaxWidth().pressable { choosingStart = true }, padding = 0.dp, radius = 20.dp) {
                        AqraRow("🧭", Palette.sky, stringResource(R.string.where_are_you_in_your_revision_q),
                            detail = stringResource(R.string.it_continues_from_juz_n, startJuz))
                    }
                    DropdownMenu(choosingStart, onDismissRequest = { choosingStart = false }) {
                        for (juz in juzList) {
                            DropdownMenuItem(text = { Text(stringResource(R.string.juz_n, juz), style = aqraStyle(15f, Weight.semibold)) }, onClick = {
                                startJuz = juz
                                choosingStart = false
                            })
                        }
                    }
                }
            }
            Spacer(Modifier.height(6.dp))
            BrandButton(stringResource(R.string.continue_action), Modifier.widthIn(max = 520.dp)) {
                apply()
                onDone()
            }
        }
        BackHandler(onBack = onBack)
        AqraBackButton(Modifier.align(Alignment.TopStart).safeDrawingPadding(), onClick = onBack)
    }
}
