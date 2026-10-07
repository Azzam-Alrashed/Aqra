package com.azzamalrashed.aqra.mushaf

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.components.AqraSegmented
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.arabicDigits

/** The Mushaf's index: every surah and juz', each opening on its first page. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MushafIndexSheet(store: MushafStore, currentPage: Int, onDismiss: () -> Unit, onSelect: (Int) -> Unit) {
    val currentSurah = store.surahOf(currentPage)
    val currentJuz = store.juzOf(currentPage)
    var surahs by remember { mutableStateOf(true) }
    val listState = rememberLazyListState()
    // Open on the surah (or juz') being read.
    LaunchedEffect(surahs) { listState.scrollToItem(((if (surahs) currentSurah else currentJuz) - 3).coerceAtLeast(0)) }

    ModalBottomSheet(onDismiss, sheetState = rememberModalBottomSheetState(), containerColor = Palette.surface) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            Column(Modifier.fillMaxHeight(0.92f)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 4.dp, bottom = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.index), style = aqraStyle(26f, Weight.heavy, Palette.ink), modifier = Modifier.semantics { heading() })
                    Spacer(Modifier.weight(1f))
                    AqraSegmented(surahs, listOf(true to stringResource(R.string.surahs), false to stringResource(R.string.juz)), onSelect = { surahs = it })
                }
                LazyColumn(state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (surahs) {
                        items((1..114).toList()) { surah ->
                            val page = store.surahStartPages[surah] ?: 1
                            val count = store.surahAyahs[surah]?.count() ?: 0
                            IndexRow(store, surah, store.surahNames[surah].orEmpty(), pluralStringResource(R.plurals.n_ayat, count, count), page, surah == currentSurah) { onSelect(page) }
                        }
                    } else {
                        items((1..30).toList()) { juz ->
                            val page = store.juzStartPages[juz] ?: 1
                            IndexRow(store, juz, "الجزء ${arabicDigits(juz)}", store.surahNames[store.page(page).surah].orEmpty(), page, juz == currentJuz) { onSelect(page) }
                        }
                    }
                }
            }
        }
    }
}

/** A surah or juz': its number in a tile of its juz's color, its name, and the page it starts on. */
@Composable
private fun IndexRow(store: MushafStore, number: Int, title: String, subtitle: String, page: Int, isCurrent: Boolean, onClick: () -> Unit) {
    val face = StepFaces.forJuz(store.page(page).juz)
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .softShadow(shape, strength = 0.6f, radius = 8.dp, y = 4.dp)
            .background(if (isCurrent) Palette.lavender else Color.White, shape)
            .border(1.5.dp, if (isCurrent) Palette.brand.copy(alpha = 0.3f) else Color.Transparent, shape)
            .pressable(onClick = onClick)
            .semantics { selected = isCurrent }
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(40.dp).background(face.first, RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
            Text(arabicDigits(number), style = aqraStyle(15f, Weight.heavy, Palette.ink))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = aqraStyle(17f, Weight.heavy, Palette.ink))
            Text(subtitle, style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
        }
        Box(
            Modifier.height(28.dp).background(if (isCurrent) Color.White else Palette.lavender, CircleShape).padding(horizontal = 10.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(arabicDigits(page), style = aqraStyle(13f, Weight.bold, Palette.brand))
        }
    }
}
