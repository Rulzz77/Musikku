package com.music.bitchord.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.music.bitchord.R
import com.music.bitchord.data.settings.AppFont

// Apple Music's signature red. No longer the primary accent, but kept for the
// spots (Replay's rank badge) that want that specific red regardless of theme.
val AccentRed = Color(0xFFFA2D48)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFB6A5FF),
    onPrimary = Color(0xFF17112B),
    primaryContainer = Color(0xFF352A61),
    onPrimaryContainer = Color(0xFFE9E2FF),
    secondary = Color(0xFF64E1D0),
    onSecondary = Color(0xFF062620),
    secondaryContainer = Color(0xFF17433D),
    onSecondaryContainer = Color(0xFFC2F8EF),
    tertiary = Color(0xFFFF9BCB),
    onTertiary = Color(0xFF3B102A),
    tertiaryContainer = Color(0xFF5B2346),
    onTertiaryContainer = Color(0xFFFFD9EA),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    background = Color(0xFF090E19),
    onBackground = Color(0xFFF3F5FC),
    surface = Color(0xFF111827),
    onSurface = Color(0xFFF3F5FC),
    surfaceVariant = Color(0xFF1B2639),
    onSurfaceVariant = Color(0xFFB0BCD1),
    outline = Color(0xFF39475F),
    outlineVariant = Color(0xFF29364B),
    inverseSurface = Color(0xFFE9EDF8),
    inverseOnSurface = Color(0xFF20283A),
    inversePrimary = Color(0xFF6551C8),
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF6654D9),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE9E4FF),
    onPrimaryContainer = Color(0xFF21145F),
    secondary = Color(0xFF147F75),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFB6F1E8),
    onSecondaryContainer = Color(0xFF00201C),
    tertiary = Color(0xFFB13E80),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFFD8E9),
    onTertiaryContainer = Color(0xFF3B0827),
    error = Color(0xFFBA1A1A),
    onError = Color.White,
    background = Color(0xFFF6F7FC),
    onBackground = Color(0xFF171C2B),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF171C2B),
    surfaceVariant = Color(0xFFEDF0F8),
    onSurfaceVariant = Color(0xFF5E687D),
    outline = Color(0xFFD5DCEC),
    outlineVariant = Color(0xFFE2E7F0),
    inverseSurface = Color(0xFF2B3040),
    inverseOnSurface = Color(0xFFF0F1F8),
    inversePrimary = Color(0xFFC4B8FF),
)

/**
 * SF Pro Display, the face Apple Music itself is set in, drawn one weight
 * lighter than it is asked for.
 *
 * Measured against Apple Music's own screens, every weight here came out a
 * cut heavier than the same text there: its titles are Semibold where these
 * asked for Bold, its metadata Medium where these asked for Semibold. The
 * shift is made once, in the family, so it reaches the type scale and every
 * weight set in place alike and keeps the steps between them: Heavy draws
 * Bold, Bold draws Semibold, Semibold draws Medium, Medium draws Regular.
 * Regular stays Regular — no lighter cut is bundled, and Apple's body text is
 * Regular too. A FontWeight in this app therefore names the step it sits at in
 * the scale, not the cut it draws.
 *
 * Compose synthesises nothing, so a weight outside these falls back to the
 * nearest one listed.
 */
val SFProDisplay = FontFamily(
    Font(R.font.sf_pro_display_regular, FontWeight.W400),
    Font(R.font.sf_pro_display_regular, FontWeight.W500),
    Font(R.font.sf_pro_display_medium, FontWeight.W600),
    Font(R.font.sf_pro_display_semibold, FontWeight.W700),
    Font(R.font.sf_pro_display_bold, FontWeight.W800),
)

/*
 * Letter spacing measured off Apple Music's own screens: the spacing the
 * bundled Display cut needs, at the weight it draws, to set a line to the
 * width Apple sets it. Apple sets text under 20pt in SF Pro Text, which is
 * spaced looser than Display, so the small sizes open up — about +0.25 to
 * +0.4 at 12 to 14 — and the spacing closes as the size grows, to just under
 * nothing for semibold titles at 18 to 24. The large titles had nothing to
 * measure against and follow the same trend.
 */
private val BitChordTypography = Typography(
    displayLarge = TextStyle(fontWeight = FontWeight.W800, fontSize = 34.sp, letterSpacing = (-0.65).sp, lineHeight = 40.sp),
    displayMedium = TextStyle(fontWeight = FontWeight.W800, fontSize = 30.sp, letterSpacing = (-0.45).sp, lineHeight = 36.sp),
    displaySmall = TextStyle(fontWeight = FontWeight.W700, fontSize = 26.sp, letterSpacing = (-0.3).sp, lineHeight = 32.sp),
    headlineLarge = TextStyle(fontWeight = FontWeight.W800, fontSize = 28.sp, letterSpacing = (-0.45).sp, lineHeight = 34.sp),
    headlineMedium = TextStyle(fontWeight = FontWeight.W700, fontSize = 22.sp, letterSpacing = (-0.2).sp, lineHeight = 28.sp),
    headlineSmall = TextStyle(fontWeight = FontWeight.W700, fontSize = 20.sp, letterSpacing = (-0.15).sp, lineHeight = 26.sp),
    titleLarge = TextStyle(fontWeight = FontWeight.W700, fontSize = 19.sp, letterSpacing = (-0.1).sp, lineHeight = 24.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.W600, fontSize = 16.sp, letterSpacing = 0.05.sp, lineHeight = 21.sp),
    titleSmall = TextStyle(fontWeight = FontWeight.W600, fontSize = 14.sp, letterSpacing = 0.1.sp, lineHeight = 19.sp),
    bodyLarge = TextStyle(fontWeight = FontWeight.W400, fontSize = 16.sp, letterSpacing = 0.1.sp, lineHeight = 23.sp),
    bodyMedium = TextStyle(fontWeight = FontWeight.W400, fontSize = 14.sp, letterSpacing = 0.15.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontWeight = FontWeight.W400, fontSize = 12.sp, letterSpacing = 0.2.sp, lineHeight = 17.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.W600, fontSize = 14.sp, letterSpacing = 0.15.sp, lineHeight = 18.sp),
    labelMedium = TextStyle(fontWeight = FontWeight.W600, fontSize = 12.sp, letterSpacing = 0.3.sp, lineHeight = 16.sp),
    labelSmall = TextStyle(fontWeight = FontWeight.W600, fontSize = 11.sp, letterSpacing = 0.35.sp, lineHeight = 14.sp),
).withFamily(SFProDisplay)

/**
 * SF Pro Display as the app first shipped it, before [SFProDisplay] moved every
 * weight a cut lighter: each weight draws its own cut, Heavy included. Kept for
 * [AppFont.LEGACY].
 */
val SFProDisplayLegacy = FontFamily(
    Font(R.font.sf_pro_display_regular, FontWeight.W400),
    Font(R.font.sf_pro_display_medium, FontWeight.W500),
    Font(R.font.sf_pro_display_semibold, FontWeight.W600),
    Font(R.font.sf_pro_display_bold, FontWeight.W700),
    Font(R.font.sf_pro_display_heavy, FontWeight.W800),
)

// Heavy, tight typography — the original scale [AppFont.LEGACY] restores.
private val LegacyTypography = Typography(
    displayLarge = TextStyle(fontWeight = FontWeight.W800, fontSize = 34.sp, letterSpacing = (-0.8).sp),
    headlineLarge = TextStyle(fontWeight = FontWeight.W800, fontSize = 30.sp, letterSpacing = (-0.7).sp),
    headlineMedium = TextStyle(fontWeight = FontWeight.W700, fontSize = 22.sp, letterSpacing = (-0.4).sp),
    titleLarge = TextStyle(fontWeight = FontWeight.W700, fontSize = 20.sp, letterSpacing = (-0.3).sp),
    titleMedium = TextStyle(fontWeight = FontWeight.W600, fontSize = 16.sp, letterSpacing = (-0.2).sp),
    bodyLarge = TextStyle(fontWeight = FontWeight.W400, fontSize = 16.sp),
    bodyMedium = TextStyle(fontWeight = FontWeight.W400, fontSize = 14.sp),
    labelMedium = TextStyle(fontWeight = FontWeight.W600, fontSize = 12.sp),
    labelSmall = TextStyle(fontWeight = FontWeight.W600, fontSize = 11.sp),
).withFamily(SFProDisplayLegacy)

/** Applies [family] to every style in the scale, so nothing is left on Roboto. */
private fun Typography.withFamily(family: FontFamily) = Typography(
    displayLarge = displayLarge.copy(fontFamily = family),
    displayMedium = displayMedium.copy(fontFamily = family),
    displaySmall = displaySmall.copy(fontFamily = family),
    headlineLarge = headlineLarge.copy(fontFamily = family),
    headlineMedium = headlineMedium.copy(fontFamily = family),
    headlineSmall = headlineSmall.copy(fontFamily = family),
    titleLarge = titleLarge.copy(fontFamily = family),
    titleMedium = titleMedium.copy(fontFamily = family),
    titleSmall = titleSmall.copy(fontFamily = family),
    bodyLarge = bodyLarge.copy(fontFamily = family),
    bodyMedium = bodyMedium.copy(fontFamily = family),
    bodySmall = bodySmall.copy(fontFamily = family),
    labelLarge = labelLarge.copy(fontFamily = family),
    labelMedium = labelMedium.copy(fontFamily = family),
    labelSmall = labelSmall.copy(fontFamily = family),
)

@Composable
fun BitChordTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    font: AppFont = AppFont.DEFAULT,
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = when (font) {
            AppFont.DEFAULT -> BitChordTypography
            AppFont.LEGACY -> LegacyTypography
        },
        content = content,
    )
}

/**
 * Draws the status and navigation bar glyphs dark or light.
 *
 * `enableEdgeToEdge()` decides this from the *system* dark-mode setting, which
 * is the wrong input the moment the in-app theme disagrees with it: Light theme
 * on a phone in dark mode left white icons on a white bar, invisible. The bars
 * have to follow the content the app is actually painting. The player supplies
 * its own stable light-icon value and paints contrast behind it; every other
 * surface follows the theme. Hence a parameter rather than reading it here.
 */
@Composable
fun SystemBarIcons(dark: Boolean) {
    val view = LocalView.current
    if (view.isInEditMode) return
    val window = findWindow(view) ?: return
    SideEffect {
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = dark
            isAppearanceLightNavigationBars = dark
        }
    }
}

