package com.music.bitchord.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.music.bitchord.ui.haptics.Haptic
import com.music.bitchord.ui.haptics.rememberHaptics
import com.music.bitchord.sharedui.resources.Res
import com.music.bitchord.sharedui.resources.decrease_lyrics_offset
import com.music.bitchord.sharedui.resources.increase_lyrics_offset
import com.music.bitchord.sharedui.resources.lyrics_offset
import com.music.bitchord.sharedui.resources.lyrics_offset_description
import com.music.bitchord.sharedui.resources.lyrics_offset_reset
import dev.chrisbanes.haze.HazeState
import org.jetbrains.compose.resources.stringResource
import java.util.Locale
import kotlin.math.roundToInt

private val ControlShape = RoundedCornerShape(16.dp)
private const val StepMs = 100

/** A shared player drawer for shifting synced lyrics against the playback clock. */
@Composable
internal fun LyricsOffsetSheet(
    hazeState: HazeState,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    fullscreen: Boolean = false,
) {
    val offsetMs by PlayerSettings.lyricsOffsetMs.collectAsStateWithLifecycle()
    val haptics = rememberHaptics()

    PlayerDrawer(
        hazeState = hazeState,
        title = stringResource(Res.string.lyrics_offset),
        onDismiss = onDismiss,
        modifier = modifier,
        alignment = if (fullscreen) Alignment.CenterEnd else Alignment.BottomCenter,
        panelMaxWidth = if (fullscreen) FULLSCREEN_PLAYER_PANEL_MAX_WIDTH else DRAWER_MAX_WIDTH,
        panelShape = if (fullscreen) FULLSCREEN_PLAYER_PANEL_SHAPE else DRAWER_SHAPE,
        slideFromEnd = fullscreen,
        titleGap = 8.dp,
    ) {
        Text(
            text = stringResource(Res.string.lyrics_offset_description),
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White.copy(alpha = 0.55f),
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 4.dp, top = 3.dp, bottom = 14.dp),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(ControlShape)
                .background(Color.White.copy(alpha = 0.05f))
                .padding(horizontal = 12.dp, vertical = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = formatOffset(offsetMs),
                style = MaterialTheme.typography.headlineMedium.copy(
                    fontWeight = FontWeight.SemiBold,
                ),
                color = Color.White,
            )
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OffsetButton(
                    label = "−",
                    contentDescription = stringResource(Res.string.decrease_lyrics_offset),
                    enabled = offsetMs > MIN_LYRICS_OFFSET_MS,
                ) {
                    haptics.play(Haptic.Select)
                    PlayerSettings.setLyricsOffsetMs(offsetMs - StepMs)
                }
                ThinSlider(
                    value = offsetToFraction(offsetMs),
                    onValueChange = { PlayerSettings.setLyricsOffsetMs(fractionToOffset(it)) },
                    idleHeight = 6.dp,
                    activeHeight = 10.dp,
                    modifier = Modifier.weight(1f),
                )
                OffsetButton(
                    label = "+",
                    contentDescription = stringResource(Res.string.increase_lyrics_offset),
                    enabled = offsetMs < MAX_LYRICS_OFFSET_MS,
                ) {
                    haptics.play(Haptic.Select)
                    PlayerSettings.setLyricsOffsetMs(offsetMs + StepMs)
                }
            }
        }

        Text(
            text = stringResource(Res.string.lyrics_offset_reset),
            style = MaterialTheme.typography.labelLarge,
            color = Color.White.copy(alpha = if (offsetMs == 0) 0.35f else 0.8f),
            modifier = Modifier
                .padding(top = 12.dp)
                .clip(CircleShape)
                .clickable(enabled = offsetMs != 0) {
                    haptics.play(Haptic.Tap)
                    PlayerSettings.setLyricsOffsetMs(0)
                }
                .padding(horizontal = 18.dp, vertical = 9.dp),
        )
    }
}

@Composable
private fun OffsetButton(
    label: String,
    contentDescription: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.semantics { this.contentDescription = contentDescription },
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.titleLarge,
            color = Color.White.copy(alpha = if (enabled) 0.85f else 0.25f),
        )
    }
}

private fun offsetToFraction(offsetMs: Int): Float =
    (offsetMs - MIN_LYRICS_OFFSET_MS).toFloat() /
        (MAX_LYRICS_OFFSET_MS - MIN_LYRICS_OFFSET_MS)

private fun fractionToOffset(fraction: Float): Int {
    val raw = MIN_LYRICS_OFFSET_MS +
        fraction.coerceIn(0f, 1f) *
        (MAX_LYRICS_OFFSET_MS - MIN_LYRICS_OFFSET_MS)
    return (raw / StepMs).roundToInt() * StepMs
}

private fun formatOffset(offsetMs: Int): String = String.format(
    Locale.getDefault(),
    "%+.1f s",
    offsetMs / 1_000f,
)
