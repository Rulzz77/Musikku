package com.music.bitchord.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.music.bitchord.data.settings.LyricsBackgroundMode
import dev.chrisbanes.haze.HazeState
import kotlin.math.roundToInt

/** Background controls that stay beside the fullscreen lyrics reader. */
@Composable
internal fun LyricsBackgroundSheet(
    hazeState: HazeState,
    onDismiss: () -> Unit,
) {
    val mode by PlayerSettings.lyricsBackgroundMode.collectAsStateWithLifecycle()
    val blurPx by PlayerSettings.lyricsBackgroundBlurPx.collectAsStateWithLifecycle()
    val blurEnabled = mode == LyricsBackgroundMode.ARTIST_IMAGE ||
        mode == LyricsBackgroundMode.COVER_ART

    PlayerDrawer(
        hazeState = hazeState,
        title = "Lyrics background",
        onDismiss = onDismiss,
        alignment = Alignment.CenterEnd,
        panelMaxWidth = 420.dp,
        panelShape = RoundedCornerShape(24.dp),
        slideFromEnd = true,
        titleGap = 10.dp,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Text(
                text = "Choose how the fullscreen lyrics are backed",
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.62f),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
            )

            LyricsBackgroundMode.entries.forEach { option ->
                val selected = option == mode
                val description = when (option) {
                    LyricsBackgroundMode.DYNAMIC_KAWARP ->
                        "Animated colour mesh that slowly drifts"
                    LyricsBackgroundMode.ARTIST_IMAGE ->
                        "Artist photography behind the lyrics"
                    LyricsBackgroundMode.COVER_ART ->
                        "Use the current album cover"
                    LyricsBackgroundMode.COVER_COLORS ->
                        "Blend colours sampled from the cover"
                    LyricsBackgroundMode.TRANSPARENT ->
                        "Keep the lyrics surface clear"
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(15.dp))
                        .background(Color.White.copy(alpha = if (selected) 0.12f else 0.055f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { PlayerSettings.setLyricsBackgroundMode(option) }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = option.label,
                            style = MaterialTheme.typography.bodyMedium.copy(
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                            ),
                            color = Color.White,
                        )
                        Text(
                            text = description,
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.White.copy(alpha = 0.58f),
                        )
                    }
                    if (selected) {
                        Icon(
                            imageVector = Icons.Rounded.Check,
                            contentDescription = "Selected",
                            tint = Color.White,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            Spacer(Modifier.height(2.dp))
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Image blur",
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = Color.White.copy(alpha = if (blurEnabled) 1f else 0.38f),
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "$blurPx px",
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.White.copy(alpha = if (blurEnabled) 0.78f else 0.35f),
                )
            }
            Slider(
                value = blurPx.toFloat(),
                onValueChange = { PlayerSettings.setLyricsBackgroundBlurPx(it.roundToInt()) },
                valueRange = 0f..40f,
                steps = 39,
                enabled = blurEnabled,
            )
            Text(
                text = if (blurEnabled) {
                    "Blur is applied to Artist Image and Cover Art only."
                } else {
                    "Choose Artist Image or Cover Art to adjust blur."
                },
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.52f),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
            )
        }
    }
}
