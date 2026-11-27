package com.music.bitchord.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FullscreenExit
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.music.bitchord.data.model.LikeStatus
import com.music.bitchord.sharedui.resources.Res
import com.music.bitchord.sharedui.resources.audio_output
import com.music.bitchord.sharedui.resources.like
import com.music.bitchord.sharedui.resources.more
import com.music.bitchord.sharedui.resources.remove_from_liked
import com.music.bitchord.sharedui.resources.repeat_all
import com.music.bitchord.sharedui.resources.repeat_off
import com.music.bitchord.sharedui.resources.repeat_one
import com.music.bitchord.sharedui.resources.shuffle_off
import com.music.bitchord.sharedui.resources.shuffle_on
import com.music.bitchord.ui.icons.BitChordIcons
import org.jetbrains.compose.resources.stringResource

/**
 * The compact control deck shown over the Canvas in fullscreen landscape
 * lyrics. It keeps the transport and playback modes together, and moves the
 * volume slider onto its own line when a phone's short landscape width cannot
 * fit it beside the transport.
 */
@Composable
internal fun FullscreenLyricsControls(
    likeStatus: LikeStatus,
    canLike: Boolean,
    shuffleEnabled: Boolean,
    repeatMode: Int,
    isPlaying: Boolean,
    isLoading: Boolean,
    previousEnabled: Boolean,
    nextEnabled: Boolean,
    volumeVisible: Boolean,
    volumeValue: () -> Float,
    onToggleLike: () -> Unit,
    onToggleShuffle: () -> Unit,
    onCycleRepeat: () -> Unit,
    onPrevious: () -> Unit,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onVolumeChange: (Float) -> Unit,
    onVolumeChangeFinished: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier = modifier) {
        val liked = likeStatus == LikeStatus.LIKE
        val repeatDescription = stringResource(
            when (repeatMode) {
                RepeatModes.ONE -> Res.string.repeat_one
                RepeatModes.ALL -> Res.string.repeat_all
                else -> Res.string.repeat_off
            },
        )
        val likeButton: @Composable () -> Unit = {
            if (canLike) {
                CircleGlyph(
                    icon = if (liked) BitChordIcons.HeartFilled else BitChordIcons.Heart,
                    contentDescription = stringResource(
                        if (liked) Res.string.remove_from_liked else Res.string.like,
                    ),
                    onClick = onToggleLike,
                    active = liked,
                )
            } else {
                Spacer(Modifier.size(34.dp))
            }
        }
        val shuffleButton: @Composable () -> Unit = {
            CircleGlyph(
                icon = BitChordIcons.Shuffle,
                contentDescription = stringResource(
                    if (shuffleEnabled) Res.string.shuffle_on else Res.string.shuffle_off,
                ),
                onClick = onToggleShuffle,
                active = shuffleEnabled,
            )
        }
        val repeatButton: @Composable () -> Unit = {
            CircleGlyph(
                icon = BitChordIcons.Repeat,
                contentDescription = repeatDescription,
                onClick = onCycleRepeat,
                active = repeatMode != RepeatModes.OFF,
            )
        }

        Column {
            if (maxWidth >= 430.dp && volumeVisible) {
                // Wide landscape windows keep every playback control on the
                // same baseline, as in the reference player.
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    likeButton()
                    shuffleButton()
                    Box(Modifier.weight(1f)) {
                        TransportRow(
                            isPlaying = isPlaying,
                            isLoading = isLoading,
                            previousEnabled = previousEnabled,
                            nextEnabled = nextEnabled,
                            onPrevious = onPrevious,
                            onPlayPause = onPlayPause,
                            onNext = onNext,
                            compact = true,
                        )
                    }
                    repeatButton()
                    Box(Modifier.width(132.dp)) {
                        VolumeRow(
                            value = volumeValue,
                            onValueChange = onVolumeChange,
                            onValueChangeFinished = onVolumeChangeFinished,
                        )
                    }
                }
            } else if (maxWidth >= 300.dp) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    likeButton()
                    shuffleButton()
                    Box(Modifier.weight(1f)) {
                        TransportRow(
                            isPlaying = isPlaying,
                            isLoading = isLoading,
                            previousEnabled = previousEnabled,
                            nextEnabled = nextEnabled,
                            onPrevious = onPrevious,
                            onPlayPause = onPlayPause,
                            onNext = onNext,
                            compact = true,
                        )
                    }
                    repeatButton()
                }
                if (volumeVisible) {
                    VolumeRow(
                        value = volumeValue,
                        onValueChange = onVolumeChange,
                        onValueChangeFinished = onVolumeChangeFinished,
                    )
                }
            } else {
                // The small-screen arrangement avoids squeezing the play target
                // or stealing width from the skip buttons on short landscape phones.
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    likeButton()
                    shuffleButton()
                    repeatButton()
                }
                TransportRow(
                    isPlaying = isPlaying,
                    isLoading = isLoading,
                    previousEnabled = previousEnabled,
                    nextEnabled = nextEnabled,
                    onPrevious = onPrevious,
                    onPlayPause = onPlayPause,
                    onNext = onNext,
                    compact = true,
                )
                if (volumeVisible) {
                    VolumeRow(
                        value = volumeValue,
                        onValueChange = onVolumeChange,
                        onValueChangeFinished = onVolumeChangeFinished,
                    )
                }
            }
        }
    }
}

/** Glass toolbar for actions that remain available while reading fullscreen lyrics. */
@Composable
internal fun FullscreenLyricsToolbar(
    onOpenOutput: () -> Unit,
    onOpenLyricsSources: () -> Unit,
    onOpenMenu: () -> Unit,
    onExitFullscreen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(28.dp)
    Row(
        modifier = modifier
            .clip(shape)
            .background(Color.Black.copy(alpha = 0.24f))
            .border(1.dp, Color.White.copy(alpha = 0.16f), shape)
            .padding(horizontal = 6.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircleGlyph(
            icon = Icons.Rounded.Headphones,
            contentDescription = stringResource(Res.string.audio_output),
            onClick = onOpenOutput,
        )
        CircleGlyph(
            icon = BitChordIcons.LyricsQuote,
            contentDescription = "Lyrics sources",
            onClick = onOpenLyricsSources,
        )
        CircleGlyph(
            icon = Icons.Rounded.MoreHoriz,
            contentDescription = stringResource(Res.string.more),
            onClick = onOpenMenu,
        )
        CircleGlyph(
            icon = Icons.Rounded.FullscreenExit,
            contentDescription = stringResource(com.music.bitchord.sharedui.resources.lyrics_exit_fullscreen),
            onClick = onExitFullscreen,
        )
    }
}

