package com.music.bitchord.widget

import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings transport for the last MusikKu queue.
 *
 * The tile uses the same persisted snapshot as the home-screen widgets and
 * forwards taps through MediaWidgetActions, which binds the MediaSession
 * safely from the background and can restore the last queue after process death.
 */
class PlaybackTile : TileService() {

    private val redraw = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> draw() }

    override fun onStartListening() {
        MediaWidgetSnapshot.prefs(this).registerOnSharedPreferenceChangeListener(redraw)
        draw()
    }

    override fun onStopListening() {
        MediaWidgetSnapshot.prefs(this).unregisterOnSharedPreferenceChangeListener(redraw)
    }

    override fun onClick() {
        sendBroadcast(
            Intent(this, MediaWidgetActions::class.java).setAction(MediaWidgetActions.ACTION_TOGGLE),
        )
    }

    private fun draw() {
        val tile = qsTile ?: return
        val snapshot = MediaWidgetSnapshot.load(this)
        tile.state = if (snapshot.isPlaying) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = snapshot.title.takeIf { snapshot.hasTrack }
        }
        tile.updateTile()
    }
}
