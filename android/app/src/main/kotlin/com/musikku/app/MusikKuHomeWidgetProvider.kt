package com.musikku.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class MusikKuHomeWidgetProvider : AppWidgetProvider() {
    companion object {
        private const val ACTION_PLAY_PAUSE = PlaybackService.ACTION_PLAY_PAUSE
        private const val ACTION_NEXT = PlaybackService.ACTION_NEXT
        private const val ACTION_PREVIOUS = PlaybackService.ACTION_PREVIOUS

        fun updateAll(context: Context, title: String, artist: String, playing: Boolean) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, MusikKuHomeWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { id ->
                val views = RemoteViews(context.packageName, R.layout.musikku_player_widget)
                views.setTextViewText(R.id.widget_title, title.ifBlank { "Belum ada lagu" })
                views.setTextViewText(R.id.widget_artist, artist.ifBlank { "Putar musik di MusikKu" })
                views.setImageViewResource(
                    R.id.widget_play_pause,
                    if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                )
                views.setOnClickPendingIntent(R.id.widget_previous, actionPendingIntent(context, id, ACTION_PREVIOUS))
                views.setOnClickPendingIntent(R.id.widget_play_pause, actionPendingIntent(context, id, ACTION_PLAY_PAUSE))
                views.setOnClickPendingIntent(R.id.widget_next, actionPendingIntent(context, id, ACTION_NEXT))
                views.setOnClickPendingIntent(R.id.widget_open, openPendingIntent(context, id))
                manager.updateAppWidget(id, views)
            }
        }

        private fun actionPendingIntent(context: Context, widgetId: Int, action: String): PendingIntent {
            val intent = Intent(context, PlaybackService::class.java).apply {
                this.action = action
            }
            return PendingIntent.getService(
                context,
                widgetId * 10 + action.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun openPendingIntent(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                widgetId * 10 + 9,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun refreshFromSnapshot(context: Context) {
            val snapshot = context.getSharedPreferences("musikku_native_playback", Context.MODE_PRIVATE)
            updateAll(
                context,
                snapshot.getString("title", "Belum ada lagu") ?: "Belum ada lagu",
                snapshot.getString("artist", "") ?: "",
                snapshot.getBoolean("playing", false),
            )
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        refreshFromSnapshot(context)
    }

}

