package com.music.bitchord.ui.screens

import androidx.annotation.StringRes
import androidx.compose.ui.graphics.vector.ImageVector
import com.music.bitchord.R
import com.music.bitchord.ui.icons.SfIcons

/**
 * The groups of Settings that are pages of their own, in the order the main
 * page lists them. Account, Listen Together and Audio quality aren't here:
 * they stay on the main page, where they always were.
 */
enum class SettingsCategory(@param:StringRes val title: Int) {
    DOWNLOADS(R.string.downloads),
    PLAYBACK(R.string.playback),
    CONTENT_PREFERENCES(R.string.content_preferences),
    APPEARANCE(R.string.appearance),
    PERFORMANCE(R.string.performance),
    LOCAL_MUSIC(R.string.local_music),
    STORAGE(R.string.storage),
    YOUR_DATA(R.string.your_data),
    MISCELLANEOUS(R.string.miscellaneous),
    LANGUAGE(R.string.language),
    ;

    val icon: ImageVector
        get() = when (this) {
            DOWNLOADS -> SfIcons.Download
            PLAYBACK -> SfIcons.PlayCircle
            CONTENT_PREFERENCES -> SfIcons.Video
            APPEARANCE -> SfIcons.Appearance
            PERFORMANCE -> SfIcons.Performance
            LOCAL_MUSIC -> SfIcons.LibraryMusic
            STORAGE -> SfIcons.Storage
            YOUR_DATA -> SfIcons.YourData
            MISCELLANEOUS -> SfIcons.Miscellaneous
            LANGUAGE -> SfIcons.Language
        }
}

/** The settings whose options are a page of their own — see [SettingsChoicePage]. */
enum class SettingsChoiceKind(@param:StringRes val title: Int) {
    AUDIO_QUALITY_WIFI(R.string.on_wifi),
    AUDIO_QUALITY_CELLULAR(R.string.on_mobile_data),
    DOWNLOAD_QUALITY(R.string.download_quality),
    AUTOMIX_PERFORMANCE(R.string.automix_performance),
    BIT_PERFECT(R.string.bit_perfect_output),
    FONT(R.string.font),
}