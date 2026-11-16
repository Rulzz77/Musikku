package com.music.bitchord.data.spotify

import android.content.Context
import android.content.SharedPreferences
import com.music.bitchord.data.model.ArtistRef
import com.music.bitchord.data.model.Song
import org.json.JSONArray
import org.json.JSONObject

/**
 * Device-local storage for confirmed Spotify-to-YouTube Music match decisions.
 *
 * This is intentionally a cache, not an account sync format: it contains no
 * Spotify/Google credentials and is not part of the portable Backup & Restore
 * payload. A cache miss still goes through the normal strict matcher.
 */
class AndroidSpotifyImportMatchCachePersistence(context: Context) : SpotifyImportMatchCachePersistence {
    private val preferences: SharedPreferences = context.applicationContext.getSharedPreferences(
        PREF_NAME,
        Context.MODE_PRIVATE,
    )

    override fun load(): List<SpotifyImportCachedMatch> {
        val raw = runCatching { preferences.getString(KEY_CACHE, null) }.getOrNull()
            ?: return emptyList()
        val root = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyList()
        if (root.optInt(KEY_VERSION, -1) != SCHEMA_VERSION) return emptyList()
        val array = root.optJSONArray(KEY_ENTRIES) ?: return emptyList()

        val firstIndex = (array.length() - MAX_ENTRIES).coerceAtLeast(0)
        return buildList {
            for (index in firstIndex until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val key = item.optString("key")
                    .takeIf { it.isNotBlank() && it.length <= MAX_CACHE_KEY_LENGTH }
                    ?: continue
                val song = item.optJSONObject("song")?.toCachedSong() ?: continue
                add(SpotifyImportCachedMatch(cacheKey = key, song = song))
            }
        }
    }

    override fun save(entries: List<SpotifyImportCachedMatch>) {
        runCatching {
            val array = JSONArray()
            entries.takeLast(MAX_ENTRIES).forEach { entry ->
                if (entry.cacheKey.isBlank() || entry.cacheKey.length > MAX_CACHE_KEY_LENGTH) {
                    return@forEach
                }
                if (entry.song.videoId.isBlank()) return@forEach
                array.put(
                    JSONObject()
                        .put("key", entry.cacheKey)
                        .put("song", entry.song.toCacheJson()),
                )
            }
            val root = JSONObject()
                .put(KEY_VERSION, SCHEMA_VERSION)
                .put(KEY_ENTRIES, array)
            // apply() keeps disk IO off the import coroutine/UI thread.
            preferences.edit().putString(KEY_CACHE, root.toString()).apply()
        }
    }

    private fun Song.toCacheJson(): JSONObject = JSONObject().apply {
        put("videoId", videoId)
        put("title", title)
        put("artist", artist)
        putNullable("thumbnailUrl", thumbnailUrl)
        putNullable("durationText", durationText)
        putNullable("artistId", artistId)
        putNullable("albumId", albumId)
        putNullable("albumName", albumName)
        put("artists", JSONArray().apply {
            this@toCacheJson.artists.forEach { artist ->
                put(
                    JSONObject()
                        .put("name", artist.name)
                        .putNullable("browseId", artist.browseId),
                )
            }
        })
        put("isVideo", isVideo)
        put("isVideoOrigin", isVideoOrigin)
        putNullable("sourceQuality", sourceQuality)
        put("sourceHiRes", sourceHiRes)
        put("isExplicit", isExplicit ?: JSONObject.NULL)
        put("isPodcastEpisode", isPodcastEpisode)
    }

    private fun JSONObject.toCachedSong(): Song? {
        val id = optText("videoId")?.takeIf { it.length <= MAX_VIDEO_ID_LENGTH } ?: return null
        val isVideo = optBoolean("isVideo", false)
        val artistList = optJSONArray("artists")?.let { array ->
            buildList {
                for (index in 0 until array.length()) {
                    val artist = array.optJSONObject(index) ?: continue
                    val name = artist.optText("name") ?: continue
                    add(ArtistRef(name = name, browseId = artist.optText("browseId")))
                }
            }
        }.orEmpty()
        val explicit = if (has("isExplicit") && !isNull("isExplicit")) {
            optBoolean("isExplicit")
        } else {
            null
        }

        return Song(
            videoId = id,
            title = optString("title").take(MAX_TEXT_LENGTH),
            artist = optString("artist").take(MAX_TEXT_LENGTH),
            thumbnailUrl = optText("thumbnailUrl"),
            durationText = optText("durationText"),
            artistId = optText("artistId"),
            artists = artistList,
            albumId = optText("albumId"),
            albumName = optText("albumName"),
            isVideo = isVideo,
            isVideoOrigin = optBoolean("isVideoOrigin", isVideo),
            sourceQuality = optText("sourceQuality"),
            sourceHiRes = optBoolean("sourceHiRes", false),
            isExplicit = explicit,
            isPodcastEpisode = optBoolean("isPodcastEpisode", false),
        )
    }

    private fun JSONObject.putNullable(key: String, value: String?): JSONObject {
        put(key, value ?: JSONObject.NULL)
        return this
    }

    private fun JSONObject.optText(key: String): String? {
        if (!has(key) || isNull(key)) return null
        return optString(key).takeIf { it.isNotBlank() && it != "null" }
    }

    private companion object {
        const val PREF_NAME = "bitchord_spotify_match_cache"
        const val KEY_CACHE = "confirmed_matches_json"
        const val KEY_VERSION = "schema_version"
        const val KEY_ENTRIES = "entries"
        const val SCHEMA_VERSION = 1
        const val MAX_ENTRIES = 512
        const val MAX_CACHE_KEY_LENGTH = 128
        const val MAX_VIDEO_ID_LENGTH = 256
        const val MAX_TEXT_LENGTH = 2_048
    }
}
