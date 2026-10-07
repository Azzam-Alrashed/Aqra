package com.azzamalrashed.aqra.ui.components

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.Problem
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import androidx.compose.ui.res.stringResource

// The onboarding's building blocks, shared by the rest of the app so every screen speaks the same language.

/** A soft purple shadow, as the iOS app draws them: a wide one below and a faint one close. */
fun Modifier.softShadow(shape: Shape, strength: Float = 1f, radius: Dp = 18.dp, y: Dp = 10.dp): Modifier = this
    .dropShadow(shape, Shadow(radius = radius, color = Palette.shadow.copy(alpha = 0.10f * strength), offset = DpOffset(0.dp, y)))
    .dropShadow(shape, Shadow(radius = 2.dp, color = Palette.shadow.copy(alpha = 0.06f * strength), offset = DpOffset(0.dp, 1.dp)))

/**
 * Fades a view, its shadow included. A plain `alpha` draws the view offscreen first, which cuts its shadow off at its
 * edges; this fades each thing it draws instead.
 */
fun Modifier.fade(alpha: Float): Modifier =
    if (alpha >= 1f) this else graphicsLayer { this.alpha = alpha; compositingStrategy = CompositingStrategy.ModulateAlpha }

/** Gives a little as it's pressed, with a spring. */
@Composable
fun Modifier.pressScale(interaction: MutableInteractionSource, pressed: Float = 0.97f): Modifier {
    val isPressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) pressed else 1f, spring(dampingRatio = 0.6f, stiffness = 600f), label = "press")
    return this.graphicsLayer { scaleX = scale; scaleY = scale }
}

/** A tappable area that shrinks a little under the finger, without the ripple. */
@Composable
fun Modifier.pressable(enabled: Boolean = true, pressed: Float = 0.97f, role: Role = Role.Button, onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    return this
        .pressScale(interaction, pressed)
        .clickable(interaction, indication = null, enabled = enabled, role = role, onClick = onClick)
}

/** An emoji in a tinted rounded square: every icon in the app's own voice sits in one, all the same shape. */
@Composable
fun IconTile(icon: String, tint: Color, size: Dp = 34.dp, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(size)
            .background(tint, RoundedCornerShape(size * 0.32f))
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Text(icon, fontSize = (size.value * 0.5f).sp, lineHeight = (size.value * 0.6f).sp)
    }
}

/**
 * A white card lifted off the surface by a soft purple shadow. An [animated] card grows and shrinks with its content,
 * its shadow following (animating the size from outside would cut the shadow off).
 */
@Composable
fun AqraCard(
    modifier: Modifier = Modifier,
    padding: Dp = 12.dp,
    radius: Dp = 22.dp,
    animated: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(radius)
    Column(
        modifier
            .softShadow(shape)
            .background(Color.White, shape)
            .clip(shape)
            .then(if (animated) Modifier.animateContentSize() else Modifier)
            .padding(padding),
        content = content,
    )
}

/** A short fact in a white capsule, led by an icon tile. */
@Composable
fun AqraChip(icon: String, tint: Color, modifier: Modifier = Modifier, label: @Composable RowScope.() -> Unit) {
    Row(
        modifier
            .softShadow(CircleShape, radius = 12.dp, y = 6.dp)
            .background(Color.White, CircleShape)
            .padding(start = 5.dp, end = 12.dp, top = 5.dp, bottom = 5.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconTile(icon, tint, size = 26.dp)
        label()
    }
}

/** The text style of a chip's label. */
val ChipText = aqraStyle(13f, Weight.bold, Palette.ink)

/** A row in a card: an icon tile, a title with an optional detail beneath, and an accessory at the end. */
@Composable
fun AqraRow(
    icon: String,
    tint: Color,
    title: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
    titleColor: Color = Palette.ink,
    accessory: @Composable () -> Unit = { AqraChevron() },
) {
    Row(
        modifier.fillMaxWidth().padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IconTile(icon, tint, size = 38.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = aqraStyle(16f, Weight.heavy, titleColor))
            if (detail != null) Text(detail, style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
        }
        accessory()
    }
}

/** The forward chevron in a lavender circle, pointing the way the screen reads. */
@Composable
fun AqraChevron() {
    Box(Modifier.size(30.dp).background(Palette.lavender, CircleShape), contentAlignment = Alignment.Center) {
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = Palette.brand, modifier = Modifier.size(20.dp))
    }
}

/** A thin line between a card's rows, starting after their icon tiles. */
@Composable
fun AqraRowDivider(start: Dp = 64.dp) {
    Box(Modifier.fillMaxWidth().padding(start = start).height(1.dp).background(Palette.lavender))
}

/** A section title above a group of cards. */
@Composable
fun AqraSectionTitle(title: String, modifier: Modifier = Modifier) {
    Text(title, style = aqraStyle(19f, Weight.heavy, Palette.ink), modifier = modifier.fillMaxWidth().semantics { heading() })
}

/** A few choices in a white capsule, the chosen one in a purple pill that slides to it. */
@Composable
fun <T> AqraSegmented(selection: T, options: List<Pair<T, String>>, onSelect: (T) -> Unit, scale: Float = 1f, modifier: Modifier = Modifier) {
    val haptics = LocalHapticFeedback.current
    val density = LocalDensity.current
    val bounds = remember { mutableStateMapOf<Int, Pair<Dp, Dp>>() }
    val selectedIndex = options.indexOfFirst { it.first == selection }
    val target = bounds[selectedIndex]
    val offset by animateDpAsState(target?.first ?: 0.dp, spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow), label = "thumb")
    val width by animateDpAsState(target?.second ?: 0.dp, spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow), label = "thumb")
    Box(
        modifier
            .background(Color.White, CircleShape)
            .border(1.5.dp, Palette.lavender, CircleShape)
            .padding(4.dp),
    ) {
        if (target != null) {
            // The options' places are measured from the left in either reading direction, so the pill is placed
            // from the left too.
            Box(
                Modifier
                    .align(AbsoluteAlignment.TopLeft)
                    .absoluteOffset { IntOffset(offset.roundToPx(), 0) }
                    .width(width)
                    .height((38 * scale).dp)
                    .background(Brush.verticalGradient(Palette.brandGradient), CircleShape),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            options.forEachIndexed { index, (value, title) ->
                val selected = value == selection
                Box(
                    Modifier
                        .height((38 * scale).dp)
                        .onPlaced { coordinates ->
                            with(density) {
                                bounds[index] = coordinates.positionInParent().x.toDp() to coordinates.size.width.toDp()
                            }
                        }
                        .clip(CircleShape)
                        .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Tab) {
                            if (!selected) {
                                haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                                onSelect(value)
                            }
                        }
                        .semantics { this.selected = selected }
                        .padding(horizontal = (18 * scale).dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(title, style = aqraStyle(15f * scale, Weight.bold, if (selected) Color.White else Palette.inkSoft), maxLines = 1)
                }
            }
        }
    }
}

private fun androidx.compose.ui.layout.LayoutCoordinates.positionInParent() =
    parentLayoutCoordinates?.localPositionOf(this, androidx.compose.ui.geometry.Offset.Zero) ?: androidx.compose.ui.geometry.Offset.Zero

/** The app's primary button: a purple capsule with a soft glow beneath. */
@Composable
fun BrandButton(
    title: String,
    modifier: Modifier = Modifier,
    height: Dp = 56.dp,
    fontSize: Float = 18f,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = height)
            .fade(if (enabled) 1f else 0.5f)
            .pressScale(interaction, 0.96f)
            .dropShadow(CircleShape, Shadow(radius = 14.dp, color = Palette.brand.copy(alpha = 0.35f), offset = DpOffset(0.dp, 8.dp)))
            .background(Brush.verticalGradient(Palette.brandGradient), CircleShape)
            .border(1.dp, Color.White.copy(alpha = 0.18f), CircleShape)
            .clip(CircleShape)
            .clickable(interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 20.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = aqraStyle(fontSize, Weight.bold, Color.White), textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A small capsule button at the end of a row: purple when filled, lavender otherwise. */
@Composable
fun ChipButton(title: String, filled: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    Row(
        modifier
            .alpha(if (enabled) 1f else 0.5f)
            .height(30.dp)
            .background(if (filled) Palette.brand else Palette.lavender, CircleShape)
            .clip(CircleShape)
            .pressable(enabled = enabled, pressed = 0.96f, onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        leading?.invoke()
        Text(title, style = aqraStyle(13f, Weight.bold, if (filled) Color.White else Palette.brand), maxLines = 1)
    }
}

/** What went wrong, in one calm line. */
@Composable
fun ProblemLine(problem: Problem, modifier: Modifier = Modifier) {
    val text = when (problem) {
        Problem.OFFLINE -> stringResource(R.string.you_need_an_internet_connection_for_this)
        Problem.FAILED -> stringResource(R.string.that_didnt_work_please_try_again)
    }
    Text(text, style = aqraStyle(12f, Weight.semibold, Palette.warning), modifier = modifier)
}

/** A headline in two lines, the second in the brand color, shrinking to fit one line each. */
@Composable
fun TwoLineHeadline(first: String, second: String, size: Float = 31f, modifier: Modifier = Modifier, alignCenter: Boolean = true) {
    Column(modifier, horizontalAlignment = if (alignCenter) Alignment.CenterHorizontally else Alignment.Start, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        FittedText(first, aqraStyle(size, Weight.heavy, Palette.ink), alignCenter)
        FittedText(second, aqraStyle(size, Weight.heavy, Palette.brand), alignCenter)
    }
}

/** One line of text that shrinks (to 60% at most) rather than wrap. */
@Composable
fun FittedText(text: String, style: TextStyle, alignCenter: Boolean = true, modifier: Modifier = Modifier, minScale: Float = 0.6f) {
    BasicText(
        text,
        modifier = modifier,
        style = style.copy(textAlign = if (alignCenter) TextAlign.Center else TextAlign.Start),
        maxLines = 1,
        autoSize = TextAutoSize.StepBased(minFontSize = style.fontSize * minScale, maxFontSize = style.fontSize, stepSize = 0.5.sp),
    )
}

/** The progress spinner, in the brand's purple. */
@Composable
fun AqraProgress(modifier: Modifier = Modifier, color: Color = Palette.brand) {
    CircularProgressIndicator(modifier.size(22.dp), color = color, strokeWidth = 2.5.dp)
}

// MARK: - Over the Mushaf

/** A white capsule floating over the Mushaf's page, holding its buttons or its title. It follows the page into dark mode. */
@Composable
fun FloatingCapsule(style: MushafStyle, modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier
            .heightIn(min = 48.dp)
            .softShadow(CircleShape, strength = 1.2f, radius = 14.dp, y = 6.dp)
            .background(style.barFill, CircleShape)
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

/** A white card floating over the Mushaf's page: the marking and revision bars. */
@Composable
fun FloatingPanel(style: MushafStyle, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(28.dp)
    Box(modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 6.dp), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .widthIn(max = 620.dp)
                .fillMaxWidth()
                .softShadow(shape, strength = 1.4f, radius = 20.dp, y = 8.dp)
                .background(style.barFill, shape)
                .padding(16.dp),
            content = content,
        )
    }
}

/** The marking and revision bars' buttons: lavender capsules, the main one the purple of the app's buttons. */
@Composable
fun MarkingButton(
    title: String,
    style: MushafStyle,
    modifier: Modifier = Modifier,
    prominent: Boolean = false,
    enabled: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier
            .heightIn(min = 46.dp)
            .fade(if (enabled) 1f else 0.45f)
            .pressScale(interaction, 0.96f)
            .then(
                if (prominent) Modifier
                    .dropShadow(CircleShape, Shadow(radius = 10.dp, color = Palette.brand.copy(alpha = 0.3f), offset = DpOffset(0.dp, 5.dp)))
                    .background(Brush.verticalGradient(Palette.brandGradient), CircleShape)
                else Modifier.background(style.barAccentFill, CircleShape)
            )
            .clip(CircleShape)
            .clickable(interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(6.dp))
        }
        FittedText(title, aqraStyle(15f, Weight.bold, if (prominent) Color.White else style.barAccent), minScale = 0.8f)
    }
}

/** A box that centers its content and keeps it no wider than [maxWidth] (iPad and tablet layouts). */
@Composable
fun CenteredColumn(modifier: Modifier = Modifier, maxWidth: Dp = 560.dp, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.widthIn(max = maxWidth).fillMaxWidth(), content = content)
    }
}
