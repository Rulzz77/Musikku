package com.music.bitchord.data

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * A user-owned grouping of playlist references.
 *
 * Folder membership stores browse ids only. It never copies or owns a playlist,
 * so deleting a folder cannot delete songs or the source playlist.
 */
data class PlaylistFolder(
    val id: String,
    val title: String,
    val playlistBrowseIds: List<String> = emptyList(),
)

object PlaylistFolders {
    private const val PREF_NAME = "bitchord_playlist_folders"
    private const val KEY_FOLDERS = "folders_json"

    private lateinit var prefs: SharedPreferences
    private val lock = Any()
    private val _folders = MutableStateFlow<List<PlaylistFolder>>(emptyList())
    val folders = _folders.asStateFlow()

    fun init(context: Context) {
        if (this::prefs.isInitialized) return
        prefs = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        _folders.value = load()
    }

    /**
     * Creates or edits a folder and replaces its membership with [playlistBrowseIds].
     * A playlist selected here is moved out of any other folder, never duplicated.
     * Returns null when the title is blank.
     */
    fun save(
        id: String?,
        title: String,
        playlistBrowseIds: Collection<String>,
    ): PlaylistFolder? {
        check(this::prefs.isInitialized) { "Playlist folder storage is not initialized" }
        val cleanTitle = title.trim().takeIf(String::isNotEmpty) ?: return null
        val folderId = id?.trim()?.takeIf(String::isNotEmpty) ?: UUID.randomUUID().toString()
        val selected = playlistBrowseIds.mapNotNull { it.trim().takeIf(String::isNotEmpty) }.distinct()

        synchronized(lock) {
            val existing = _folders.value.any { it.id == folderId }
            val updated = if (existing) {
                _folders.value.map { folder ->
                    when {
                        folder.id == folderId -> folder.copy(title = cleanTitle, playlistBrowseIds = selected)
                        else -> folder.copy(playlistBrowseIds = folder.playlistBrowseIds.filterNot { it in selected })
                    }
                }
            } else {
                _folders.value.map { folder ->
                    folder.copy(playlistBrowseIds = folder.playlistBrowseIds.filterNot { it in selected })
                } + PlaylistFolder(folderId, cleanTitle, selected)
            }
            publishAndPersist(normalizePlaylistFolders(updated))
        }
        return _folders.value.firstOrNull { it.id == folderId }
    }

    /** Assigns one playlist to [folderId], removing it from every other folder. */
    fun movePlaylist(folderId: String, playlistBrowseId: String): Boolean {
        check(this::prefs.isInitialized) { "Playlist folder storage is not initialized" }
        val cleanId = folderId.trim()
        val browseId = playlistBrowseId.trim()
        if (cleanId.isEmpty() || browseId.isEmpty()) return false
        synchronized(lock) {
            if (_folders.value.none { it.id == cleanId }) return false
            publishAndPersist(assignPlaylistToFolder(_folders.value, cleanId, browseId))
        }
        return true
    }

    /** Removes a playlist reference from this folder only. The playlist remains untouched. */
    fun removePlaylist(folderId: String, playlistBrowseId: String) {
        check(this::prefs.isInitialized) { "Playlist folder storage is not initialized" }
        synchronized(lock) {
            val cleanId = folderId.trim()
            val browseId = playlistBrowseId.trim()
            publishAndPersist(
                _folders.value.map { folder ->
                    if (folder.id == cleanId) {
                        folder.copy(playlistBrowseIds = folder.playlistBrowseIds.filterNot { it == browseId })
                    } else folder
                },
            )
        }
    }

    /** Deletes only folder metadata. Playlists and tracks are never deleted. */
    fun delete(folderId: String) {
        check(this::prefs.isInitialized) { "Playlist folder storage is not initialized" }
        synchronized(lock) {
            val cleanId = folderId.trim()
            publishAndPersist(_folders.value.filterNot { it.id == cleanId })
        }
    }

    /**
     * Restores folder metadata from a backup. Merge keeps existing folder names
     * and combines memberships; replace uses only the incoming folder list.
     */
    fun restoreFromBackup(incoming: List<PlaylistFolder>, merge: Boolean): Int {
        check(this::prefs.isInitialized) { "Playlist folder storage is not initialized" }
        val normalizedIncoming = normalizePlaylistFolders(incoming)
        synchronized(lock) {
            val next = if (merge) mergePlaylistFolders(_folders.value, normalizedIncoming) else normalizedIncoming
            val encoded = encode(next)
            check(prefs.edit().putString(KEY_FOLDERS, encoded).commit()) {
                "Could not save restored playlist folders"
            }
            _folders.value = next
            return next.size
        }
    }

    private fun publishAndPersist(value: List<PlaylistFolder>) {
        val normalized = normalizePlaylistFolders(value)
        prefs.edit().putString(KEY_FOLDERS, encode(normalized)).apply()
        _folders.value = normalized
    }

    private fun load(): List<PlaylistFolder> {
        val raw = prefs.getString(KEY_FOLDERS, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            normalizePlaylistFolders((0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                val id = item.optString("id").takeIf(String::isNotBlank) ?: return@mapNotNull null
                val title = item.optString("title").takeIf(String::isNotBlank) ?: return@mapNotNull null
                val playlistIds = item.optJSONArray("playlists") ?: JSONArray()
                PlaylistFolder(
                    id = id,
                    title = title,
                    playlistBrowseIds = (0 until playlistIds.length()).mapNotNull { playlistIndex ->
                        playlistIds.optString(playlistIndex).takeIf(String::isNotBlank)
                    },
                )
            })
        }.getOrElse { emptyList() }
    }

    private fun encode(value: List<PlaylistFolder>): String {
        val array = JSONArray()
        value.forEach { folder ->
            array.put(
                JSONObject().apply {
                    put("id", folder.id)
                    put("title", folder.title)
                    put("playlists", JSONArray(folder.playlistBrowseIds))
                },
            )
        }
        return array.toString()
    }
}

/** Normalizes user input and guarantees each playlist belongs to at most one folder. */
internal fun normalizePlaylistFolders(folders: List<PlaylistFolder>): List<PlaylistFolder> {
    val seenFolderIds = HashSet<String>()
    val seenPlaylists = HashSet<String>()
    return folders.mapNotNull { folder ->
        val id = folder.id.trim()
        val title = folder.title.trim()
        if (id.isEmpty() || title.isEmpty() || !seenFolderIds.add(id)) return@mapNotNull null
        val members = folder.playlistBrowseIds.mapNotNull { it.trim().takeIf(String::isNotEmpty) }
            .filter { seenPlaylists.add(it) }
            .distinct()
        PlaylistFolder(id, title, members)
    }
}

/** Merge by stable folder id, preserving existing names while adding unseen memberships. */
internal fun mergePlaylistFolders(
    current: List<PlaylistFolder>,
    incoming: List<PlaylistFolder>,
): List<PlaylistFolder> {
    val merged = current.toMutableList()
    val indexes = merged.mapIndexed { index, folder -> folder.id to index }.toMap()
    incoming.forEach { folder ->
        val index = indexes[folder.id]
        if (index == null) {
            merged += folder
        } else {
            val existing = merged[index]
            merged[index] = existing.copy(
                title = existing.title.ifBlank { folder.title },
                playlistBrowseIds = (existing.playlistBrowseIds + folder.playlistBrowseIds).distinct(),
            )
        }
    }
    return normalizePlaylistFolders(merged)
}

/** Moves [playlistBrowseId] into one folder, removing old memberships first. */
internal fun assignPlaylistToFolder(
    folders: List<PlaylistFolder>,
    folderId: String,
    playlistBrowseId: String,
): List<PlaylistFolder> {
    if (folders.none { it.id == folderId } || playlistBrowseId.isBlank()) return normalizePlaylistFolders(folders)
    return normalizePlaylistFolders(
        folders.map { folder ->
            when {
                folder.id == folderId -> folder.copy(
                    playlistBrowseIds = (folder.playlistBrowseIds.filterNot { it == playlistBrowseId } + playlistBrowseId),
                )
                else -> folder.copy(playlistBrowseIds = folder.playlistBrowseIds.filterNot { it == playlistBrowseId })
            }
        },
    )
}
