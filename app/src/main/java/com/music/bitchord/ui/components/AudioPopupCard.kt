package com.music.bitchord.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.music.bitchord.data.settings.AppSettings
import com.music.bitchord.ui.utils.containSheetGestures
import com.music.bitchord.ui.player.LocalPlayerFrost
import com.music.bitchord.ui.player.FULLSCREEN_PLAYER_PANEL_MAX_WIDTH
import com.music.bitchord.ui.player.FULLSCREEN_PLAYER_PANEL_WIDTH_FRACTION
import com.music.bitchord.ui.player.fullscreenPlayerPanelSurface
import dev.chrisbanes.haze.HazeState

private val POPUP_CARD_SHAPE = RoundedCornerShape(ALERT_CORNER)
private val POPUP_SCRIM_COLOR = Color.Black.copy(alpha = 0.4f)
private val POPUP_WIDTH = 320.dp
private val POPUP_CONTENT_MAX_HEIGHT = 420.dp

/**
 * The frosted card the output drawer's popups open into — the one
 * [AudioPipelineDialog] was drawn in, lifted out so the Cast picker is the same
 * object rather than a second one made to look like it.
 *
 * A scrim that dismisses, a card that swallows the tap so touching it does not,
 * a centred title and subtitle, a scrolling body, and a full-width closing
 * action. Fixed to the player's own dark palette rather than the theme-adaptive
 * one the settings dialogs use, since everything on the player is white alphas
 * whatever the app's light/dark theme is.
 *
 * [content] is the scrolling body, handed a [BoxScope] so a body can lay
 * something behind its rows — the pipeline draws its signal line there.
 */
@Composable
internal fun AudioPopupCard(
    hazeState: HazeState,
    title: String,
    subtitle: String,
    doneLabel: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    fullscreen: Boolean = false,
    content: @Composable BoxScope.() -> Unit,
) {
    val reduceDynamicBlur by AppSettings.reduceDynamicBlur.collectAsStateWithLifecycle()
    val frost = LocalPlayerFrost.current

    Box(
        modifier = modifier
            .fillMaxSize()
            .containSheetGestures()
            .background(POPUP_SCRIM_COLOR)
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onDismiss,
            ),
        contentAlignment = if (fullscreen) Alignment.CenterEnd else Alignment.Center,
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val fullscreenWidth = minOf(maxWidth * FULLSCREEN_PLAYER_PANEL_WIDTH_FRACTION, FULLSCREEN_PLAYER_PANEL_MAX_WIDTH)
            Column(
                modifier = if (fullscreen) {
                    Modifier
                        .width(fullscreenWidth)
                        .fillMaxHeight()
                        .padding(10.dp)
                        .fullscreenPlayerPanelSurface()
                        .clickable(
                            indication = null,
                            interactionSource = remember { MutableInteractionSource() },
                            onClick = {},
                        )
                        .padding(horizontal = 18.dp)
                        .padding(top = 16.dp, bottom = 12.dp)
                } else {
                    Modifier
                        .width(POPUP_WIDTH)
                        .clip(POPUP_CARD_SHAPE)
                        .then(
                            when {
                                reduceDynamicBlur -> Modifier.background(MenuFrostDark)
                                frost != null -> with(frost) {
                                    Modifier.frostPanel(POPUP_CARD_SHAPE, MenuFrostDark.copy(alpha = MENU_FROST_ALPHA))
                                }
                                else -> Modifier.liveMenuFrost(hazeState, MenuFrostDark)
                            }
                        )
                        .clickable(
                            indication = null,
                            interactionSource = remember { MutableInteractionSource() },
                            onClick = {},
                        )
                },
            ) {
                if (fullscreen) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = title,
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.titleLarge.copy(
                                fontSize = 19.sp,
                                fontWeight = FontWeight.Bold,
                            ),
                            color = Color.White,
                        )
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Rounded.Close, contentDescription = "Close", tint = Color.White)
                        }
                    }
                    Text(
                        text = subtitle,
                        modifier = Modifier.fillMaxWidth().padding(start = 4.dp, bottom = 14.dp),
                        style = MaterialTheme.typography.bodySmall.copy(lineHeight = 17.sp),
                        color = Color.White.copy(alpha = 0.68f),
                    )
                } else {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 19.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = title,
                            style = MaterialTheme.typography.bodyLarge.copy(
                                fontSize = 17.sp,
                                fontWeight = FontWeight.W600,
                            ),
                            color = Color.White,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            text = subtitle,
                            modifier = Modifier.padding(top = 4.dp),
                            style = MaterialTheme.typography.bodyMedium.copy(
                                fontSize = 13.sp,
                                lineHeight = 17.sp,
                            ),
                            color = Color.White.copy(alpha = 0.7f),
                            textAlign = TextAlign.Center,
                        )
                    }
                }

                Box(
                    modifier = if (fullscreen) {
                        Modifier.weight(1f).verticalScroll(rememberScrollState())
                    } else {
                        Modifier.heightIn(max = POPUP_CONTENT_MAX_HEIGHT).verticalScroll(rememberScrollState())
                    },
                    content = content,
                )

                PipelineRule(Modifier)
                PipelineDoneAction(label = doneLabel, onClick = onDismiss)
            }
        }
    }
}
