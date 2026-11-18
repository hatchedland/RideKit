package com.hatchedland.ridetracker.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.width
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The "Milestone" look (ios/Shared/Brand.swift, PLAN.md §12): one accent, one neutral pair, one
 * signal colour. Highway yellow is a fill with asphalt text on it, never text on a light background.
 * Signal red is for recording, End and problems only. Dynamic colour stays off: the brand is the identity.
 */
object Brand {
    val HighwayYellow = Color(0xFFF5C400)
    val Asphalt = Color(0xFF1B1A17)
    val Chalk = Color(0xFFF6F3EA)

    /** Text and controls tint: deep ochre on light (5.5:1 on white), highway yellow on dark. */
    @Composable fun accent() = if (isSystemInDarkTheme()) HighwayYellow else Color(0xFF8A6100)
    /** Recording, stop and destructive actions only. */
    @Composable fun signal() = if (isSystemInDarkTheme()) Color(0xFFFF5A4A) else Color(0xFFC22E22)
    /** Journal page: chalk by day, deep asphalt by night. */
    @Composable fun page() = if (isSystemInDarkTheme()) Color(0xFF100F0D) else Chalk
    /** A card on the page. */
    @Composable fun card() = if (isSystemInDarkTheme()) Color(0xFF22201C) else Color.White

    /**
     * Signboard numbers. iOS uses SF's expanded width; Android will bundle Roboto Flex (width axis)
     * — until then, heavy and wide-tracked system type stands in.
     */
    fun readout(size: Int) = TextStyle(fontSize = size.sp, fontWeight = FontWeight.Black, letterSpacing = 0.5.sp)
    val stat = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.5.sp)
    val label = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.5.sp)
}

private val Light: ColorScheme = lightColorScheme(
    primary = Color(0xFF8A6100),
    onPrimary = Color.White,
    primaryContainer = Brand.HighwayYellow,
    onPrimaryContainer = Brand.Asphalt,
    secondaryContainer = Brand.HighwayYellow,
    onSecondaryContainer = Brand.Asphalt,
    background = Brand.Chalk,
    onBackground = Brand.Asphalt,
    surface = Brand.Chalk,
    onSurface = Brand.Asphalt,
    surfaceContainer = Color.White,
    error = Color(0xFFC22E22),
)

private val Dark: ColorScheme = darkColorScheme(
    primary = Brand.HighwayYellow,
    onPrimary = Brand.Asphalt,
    primaryContainer = Brand.HighwayYellow,
    onPrimaryContainer = Brand.Asphalt,
    secondaryContainer = Brand.HighwayYellow,
    onSecondaryContainer = Brand.Asphalt,
    background = Color(0xFF100F0D),
    onBackground = Brand.Chalk,
    surface = Color(0xFF100F0D),
    onSurface = Brand.Chalk,
    surfaceContainer = Color(0xFF22201C),
    error = Color(0xFFFF5A4A),
)

@Composable
fun RideTrackerTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (dark) Dark else Light, typography = Typography(), content = content)
}

/** A small km-stone: yellow cap over a chalk body, outlined in asphalt. `filled = false`: wishlist outline. */
@Composable
fun MilestoneMark(modifier: Modifier = Modifier, width: Dp = 56.dp, cap: Color = Brand.HighwayYellow, filled: Boolean = true) {
    Canvas(modifier.width(width).aspectRatio(0.72f)) {
        val w = size.width
        val h = size.height
        val radius = w / 2
        val stone = Path().apply {
            moveTo(0f, h)
            lineTo(0f, radius)
            arcTo(Rect(Offset.Zero, Size(w, w)), 180f, 180f, false)
            lineTo(w, h)
            close()
        }
        if (filled) drawPath(stone, Brand.Chalk)
        clipRect(bottom = w * 0.75f) { drawPath(stone, cap) }
        drawPath(stone, Brand.Asphalt, style = Stroke(width = maxOf(1f, w * 0.08f)))
    }
}
