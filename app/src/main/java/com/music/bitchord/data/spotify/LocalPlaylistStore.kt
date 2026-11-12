package com.music.bitchord.data.spotify

import android.content.Context
import android.content.SharedPreferences
import com.music.bitchord.data.model.Song
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

const val IMPORTED_PLAYLIST_PREFIX = "local:playlist:"

data class LocalPlaylist(
    val id: String,
    val title: String,
    val songs: List<Song>,
    val coverUrl: String? = null,
) {
    val browseId: String get() = IMPORTED_PLAYLIST_PREFIX + id
}

object LocalPlaylistStore {
    private const val PREF_NAME = "bitchord_local_playlists"
    private const val KEY_PLAYLISTS = "playlists_json"

    private lateinit var prefs: SharedPreferences

    private val _playlists = MutableStateFlow<List<LocalPlaylist>>(emptyList())
    val playlists = _playlists.asStateFlow()

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        load()
    }

    private fun load() {
        if (!this::prefs.isInitialized) return
        val raw = prefs.getString(KEY_PLAYLISTS, null) ?: return
        runCatching {
            val list = mutableListOf<LocalPlaylist>()
            val jsonArray = JSONArray(raw)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val id = obj.getString("id")
                val title = obj.getString("title")
                val songsArray = obj.getJSONArray("songs")
                val songs = mutableListOf<Song>()
                for (j in 0 until songsArray.length()) {
                    val sObj = songsArray.getJSONObject(j)
                    val song = Song(
                        videoId = sObj.optString("videoId", ""),
                        title = sObj.optString("title", ""),
                        artist = sObj.optString("artist", ""),
                        thumbnailUrl = sObj.optString("thumbnailUrl", null).takeIf { !it.isNullOrBlank() && it != "null" },
                        durationText = sObj.optString("durationText", null).takeIf { !it.isNullOrBlank() && it != "null" },
                        artistId = sObj.optString("artistId", null).takeIf { !it.isNullOrBlank() && it != "null" },
                        albumId = sObj.optString("albumId", null).takeIf { !it.isNullOrBlank() && it != "null" },
                        albumName = sObj.optString("albumName", null).takeIf { !it.isNullOrBlank() && it != "null" },
                        isVideo = sObj.optBoolean("isVideo", false),
                    )
                    songs.add(song)
                }
                val coverUrl = obj.optString("coverUrl", null)
                    .takeIf { !it.isNullOrBlank() && it != "null" }
                list.add(LocalPlaylist(id, title, dedupeSongs(songs), coverUrl))
            }
            _playlists.value = list
        }
    }

    data class AddResult(val added: Int, val alreadyThere: Int)

    /**
     * Adds tracks to Spotify-imported playlists kept on this device.
     *
     * A playlist can be selected by its browse id (the value used by the
     * Library page) or by its stored id. Duplicate video ids are ignored
     * independently for each playlist, and new tracks keep their selection
     * order at the end of the existing list.
     */
    fun addSongs(playlistIds: Collection<String>, songs: List<Song>): AddResult {
        val ids = playlistIds.mapNotNull { value ->
            when {
                value.startsWith(IMPORTED_PLAYLIST_PREFIX) -> value.removePrefix(IMPORTED_PLAYLIST_PREFIX)
                value in _playlists.value.map { it.id } -> value
                else -> null
            }
        }.toSet()
        if (ids.isEmpty() || songs.isEmpty()) return AddResult(0, 0)

        var added = 0
        var alreadyThere = 0
        val updated = _playlists.value.map { playlist ->
            if (playlist.id !in ids) return@map playlist
            val (combined, count) = appendUniqueImportedTracks(playlist.songs, songs)
            if (count == 0) {
                alreadyThere++
                playlist
            } else {
                added++
                playlist.copy(songs = combined)
            }
        }
        if (added > 0) {
            _playlists.value = updated
            persist(updated)
        }
        return AddResult(added, alreadyThere)
    }

    fun savePlaylist(title: String, songs: List<Song>): LocalPlaylist {
        val id = "sp_local_" + System.currentTimeMillis()
        val playlist = LocalPlaylist(id = id, title = title.trim(), songs = dedupeSongs(songs))
        val updated = listOf(playlist) + _playlists.value.filterNot { it.id == id }
        _playlists.value = updated
        persist(updated)
        return playlist
    }

    fun deletePlaylist(id: String) {
        val updated = _playlists.value.filterNot { it.id == id || it.browseId == id || it.id == id.removePrefix("local:playlist:") }
        _playlists.value = updated
        persist(updated)
    }

    fun removeSong(playlistId: String, song: Song) {
        val cleanId = playlistId.removePrefix(IMPORTED_PLAYLIST_PREFIX)
        val updated = _playlists.value.map { playlist ->
            if (playlist.id == cleanId) {
                playlist.copy(songs = playlist.songs.filterNot { it.videoId == song.videoId })
            } else playlist
        }
        _playlists.value = updated
        persist(updated)
    }

    fun updateCover(playlistId: String, coverUrl: String?) {
        val cleanId = playlistId.removePrefix(IMPORTED_PLAYLIST_PREFIX)
        val updated = _playlists.value.map { playlist ->
            if (playlist.id == cleanId) {
                playlist.copy(coverUrl = coverUrl?.takeIf(String::isNotBlank))
            } else playlist
        }
        _playlists.value = updated
        persist(updated)
    }

    fun renamePlaylist(id: String, newTitle: String) {
        val cleanId = id.removePrefix("local:playlist:").removePrefix("VL")
        val updated = _playlists.value.map {
            if (it.id == cleanId || it.id == id || it.browseId == id) {
                it.copy(title = newTitle)
            } else it
        }
        _playlists.value = updated
        persist(updated)
    }

    fun getPlaylist(id: String): LocalPlaylist? {
        val cleanId = id.removePrefix("local:playlist:").removePrefix("VL")
        return _playlists.value.firstOrNull { it.id == cleanId || it.id == id || it.browseId == id }
    }

    private fun persist(list: List<LocalPlaylist>) {
        if (!this::prefs.isInitialized) return
        runCatching {
            val jsonArray = JSONArray()
            for (playlist in list) {
                val pObj = JSONObject()
                pObj.put("id", playlist.id)
                pObj.put("title", playlist.title)
                pObj.putOpt("coverUrl", playlist.coverUrl)
                val songsArray = JSONArray()
                for (song in playlist.songs) {
                    val sObj = JSONObject()
                    sObj.put("videoId", song.videoId)
                    sObj.put("title", song.title)
                    sObj.put("artist", song.artist)
                    sObj.put("thumbnailUrl", song.thumbnailUrl)
                    sObj.put("durationText", song.durationText)
                    sObj.put("artistId", song.artistId)
                    sObj.put("albumId", song.albumId)
                    sObj.put("albumName", song.albumName)
                    sObj.put("isVideo", song.isVideo)
                    songsArray.put(sObj)
                }
                pObj.put("songs", songsArray)
                jsonArray.put(pObj)
            }
            prefs.edit().putString(KEY_PLAYLISTS, jsonArray.toString()).apply()
        }
    }
}


/**
 * Appends only tracks with a new, non-blank video id.
 * Kept pure so duplicate handling can be verified without Android preferences.
 */
internal fun appendUniqueImportedTracks(
    existing: List<Song>,
    incoming: List<Song>,
): Pair<List<Song>, Int> {
    val known = existing.mapNotNullTo(HashSet()) { it.videoId.trim().takeIf(String::isNotEmpty) }
    val fresh = incoming.filter { song ->
        val id = song.videoId.trim()
        id.isNotEmpty() && known.add(id)
    }
    return dedupeSongs(existing + fresh) to fresh.size
}

internal fun dedupeSongs(songs: List<Song>): List<Song> {
    val seen = HashSet<String>()
    return songs.filter { song ->
        val key = song.videoId.trim()
        key.isNotEmpty() && seen.add(key)
    }
}
