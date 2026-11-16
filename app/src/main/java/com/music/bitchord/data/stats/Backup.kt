package com.music.bitchord.data.stats

import android.content.Context
import android.net.Uri
import com.music.bitchord.BuildConfig
import com.music.bitchord.data.OfflinePlaylist
import com.music.bitchord.data.OfflinePlaylists
import com.music.bitchord.data.model.ArtistRef
import com.music.bitchord.data.model.Song
import com.music.bitchord.playback.LastPlayed
import com.music.bitchord.data.settings.AppSettings
import com.music.bitchord.data.settings.SearchHistory
import com.music.bitchord.data.spotify.LocalPlaylist
import com.music.bitchord.data.spotify.LocalPlaylistStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * A portable snapshot of user-owned MusikKu data.
 *
 * Credentials, downloaded audio files, download-file indexes, cache files and
 * device permission grants are deliberately excluded. Playlist metadata and
 * local file references are included; a content:// or file:// reference may
 * need relinking when the backup is restored on a different device.
 *
 * Preferences are stored with explicit primitive types because JSON numbers
 * otherwise cannot distinguish Android's Int, Long and Float preferences.
 */
object Backup {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        prettyPrint = true
    }

    /** A suggested filename, dated so successive exports don't collide. */
    fun suggestedName(): String =
        "musikku-backup-${DateTimeFormatter.ofPattern("yyyy-MM-dd").format(
            Instant.now().atZone(ZoneId.systemDefault()),
        )}.json"

    suspend fun exportTo(context: Context, target: Uri): Result<ExportSummary> = withContext(Dispatchers.IO) {
        runCatching {
            val buckets = ListeningStats.exportAll()
            val spotifyPlaylists = LocalPlaylistStore.playlists.value.map { it.toBackupPlaylist() }
            val devicePlaylists = OfflinePlaylists.playlists.value.map { it.toBackupPlaylist() }
            val file = BackupFile(
                versionName = BuildConfig.VERSION_NAME,
                exportedAt = Instant.now().toString(),
                settings = AppSettings.exportPrefs().mapNotNull { (key, value) ->
                    PrefValue.of(value)?.let { key to it }
                }.toMap(),
                listening = buckets,
                spotifyPlaylists = spotifyPlaylists,
                remoteSpotifyImports = LocalPlaylistStore.remoteSpotifyImportsSnapshot()
                    .mapValues { (_, ids) -> ids.toList() },
                devicePlaylists = devicePlaylists,
                lastPlayedQueue = LastPlayed.backupSnapshot()?.let { snapshot ->
                    BackupQueue(
                        songs = snapshot.songs.map { it.toBackupSong() },
                        index = snapshot.index,
                        positionMs = snapshot.positionMs,
                    )
                },
            )
            val text = json.encodeToString(BackupFile.serializer(), file)
            context.contentResolver.openOutputStream(target, "wt")
                ?.use { it.write(text.toByteArray(Charsets.UTF_8)) }
                ?: error("Couldn't open that file for writing")

            ExportSummary(
                months = buckets.size,
                spotifyPlaylists = spotifyPlaylists.size,
                devicePlaylists = devicePlaylists.size,
                tracks = spotifyPlaylists.sumOf { it.songs.size } + devicePlaylists.sumOf { it.songs.size },
            )
        }
    }

    /** Parses and validates a backup without changing anything on this device. */
    suspend fun previewFrom(context: Context, source: Uri): Result<Preview> = withContext(Dispatchers.IO) {
        runCatching { readBackup(context, source).toPreview() }
    }

    /**
     * Restores settings and listening totals, then either merges or replaces
     * both local playlist collections. Cloud account credentials and
     * device-specific download indexes are left untouched.
     */
    suspend fun importFrom(
        context: Context,
        source: Uri,
        mergePlaylists: Boolean = false,
    ): Result<Summary> = withContext(Dispatchers.IO) {
        runCatching {
            val file = readBackup(context, source)
            val settings = file.settings.mapValues { (_, value) ->
                value.decoded() ?: error("Backup contains an invalid setting value")
            }
            val spotifyPlaylists = file.spotifyPlaylists.map { it.toLocalPlaylist() }
            val devicePlaylists = file.devicePlaylists.map { it.toOfflinePlaylist() }
            val remoteImports = file.remoteSpotifyImports.mapValues { (_, ids) -> ids.toSet() }

            // All parsing and structural validation happens before the first
            // write. Schema 1 predates playlist and queue backup sections, so
            // importing it must not erase data those older files never held.
            ListeningStats.importAll(file.listening)
            AppSettings.importPrefs(settings)
            if (file.version >= 2) {
                LocalPlaylistStore.restoreFromBackup(spotifyPlaylists, remoteImports, mergePlaylists)
                OfflinePlaylists.restoreFromBackup(devicePlaylists, mergePlaylists)
                LastPlayed.restoreBackupSnapshot(file.lastPlayedQueue?.toSnapshot())
            }
            // Search history lives in the same preference file as AppSettings.
            SearchHistory.reload()

            Summary(
                months = file.listening.size,
                settings = file.settings.size,
                spotifyPlaylists = spotifyPlaylists.size,
                devicePlaylists = devicePlaylists.size,
                tracks = spotifyPlaylists.sumOf { it.songs.size } + devicePlaylists.sumOf { it.songs.size },
                queueTracks = file.lastPlayedQueue?.songs?.size ?: 0,
                from = file.versionName,
                at = file.exportedAt,
                mergedPlaylists = mergePlaylists,
            )
        }
    }

    private fun readBackup(context: Context, source: Uri): BackupFile {
        val bytes = context.contentResolver.openInputStream(source)?.use { input ->
            ByteArrayOutputStream().use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    require(total <= MAX_BACKUP_BYTES) { "Backup is too large to import safely" }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
        } ?: error("Couldn't open that file")
        val text = bytes.decodeToString(throwOnInvalidSequence = true)
        val file = runCatching { json.decodeFromString(BackupFile.serializer(), text) }
            .getOrElse { error("That doesn't look like a MusikKu backup") }

        require(file.app == APP_TAG) { "That backup is from another app" }
        require(file.version in MIN_SCHEMA_VERSION..SCHEMA_VERSION) {
            if (file.version > SCHEMA_VERSION) "That backup was created by a newer MusikKu version"
            else "That backup version is not supported"
        }
        require(file.settings.size <= MAX_SETTINGS) { "Backup contains too many settings" }
        file.settings.forEach { (key, value) ->
            require(key.isNotBlank() && value.isValid()) { "Backup contains an invalid setting" }
        }
        validatePlaylists(file.spotifyPlaylists, "Spotify")
        validatePlaylists(file.devicePlaylists, "device")
        require(file.spotifyPlaylists.size + file.devicePlaylists.size <= MAX_PLAYLISTS) {
            "Backup contains too many playlists"
        }
        val trackCount = file.spotifyPlaylists.sumOf { it.songs.size } +
            file.devicePlaylists.sumOf { it.songs.size }
        require(trackCount <= MAX_TRACKS) { "Backup contains too many playlist tracks" }
        file.lastPlayedQueue?.let { queue ->
            require(queue.songs.size <= MAX_QUEUE_TRACKS) { "Backup contains too many queued tracks" }
            require(queue.index in queue.songs.indices || queue.songs.isEmpty()) {
                "Backup contains an invalid playback queue position"
            }
            require(queue.positionMs >= 0L) { "Backup contains an invalid playback queue position" }
            require(queue.songs.all { it.videoId.isNotBlank() || !it.localUri.isNullOrBlank() }) {
                "Backup contains an invalid track in the playback queue"
            }
        }
        require(file.remoteSpotifyImports.size <= MAX_PLAYLISTS) {
            "Backup contains too many remote playlist mappings"
        }
        file.remoteSpotifyImports.forEach { (playlistId, ids) ->
            require(playlistId.isNotBlank() && ids.size <= MAX_TRACKS && ids.all(String::isNotBlank)) {
                "Backup contains an invalid Spotify playlist mapping"
            }
        }
        require(file.listening.size <= MAX_LISTENING_MONTHS) { "Backup contains too much listening history" }
        val months = HashSet<String>()
        file.listening.forEach { bucket ->
            val month = runCatching { YearMonth.parse(bucket.month).toString() }.getOrNull()
                ?: error("Backup contains an invalid listening-history month")
            require(months.add(month)) { "Backup contains duplicate listening-history months" }
        }
        return file
    }

    private fun validatePlaylists(playlists: List<BackupPlaylist>, label: String) {
        val ids = HashSet<String>()
        playlists.forEach { playlist ->
            require(playlist.id.isNotBlank() && playlist.id.length <= 512) {
                "Backup contains an invalid $label playlist id"
            }
            require(ids.add(playlist.id)) { "Backup contains duplicate $label playlists" }
            require(playlist.title.isNotBlank() && playlist.title.length <= 2_000) {
                "Backup contains an invalid $label playlist title"
            }
            require(playlist.songs.all { song ->
                (song.videoId.isNotBlank() || !song.localUri.isNullOrBlank()) &&
                    song.videoId.length <= 4_096 &&
                    song.title.length <= 4_096 &&
                    song.artist.length <= 4_096
            }) { "Backup contains an invalid track in a $label playlist" }
        }
    }

    private fun BackupFile.toPreview() = Preview(
        versionName = versionName,
        exportedAt = exportedAt,
        months = listening.size,
        settings = settings.size,
        spotifyPlaylists = spotifyPlaylists.size,
        spotifyTracks = spotifyPlaylists.sumOf { it.songs.size },
        devicePlaylists = devicePlaylists.size,
        deviceTracks = devicePlaylists.sumOf { it.songs.size },
        remotePlaylistMappings = remoteSpotifyImports.size,
        schemaVersion = version,
        queueTracks = lastPlayedQueue?.songs?.size ?: 0,
        queueIndex = lastPlayedQueue?.index?.let { (it + 1).coerceIn(1, lastPlayedQueue.songs.size.coerceAtLeast(1)) } ?: 0,
    )

    private fun Song.toBackupSong() = BackupSong(
        videoId = videoId,
        title = title,
        artist = artist,
        thumbnailUrl = thumbnailUrl,
        durationText = durationText,
        artistId = artistId,
        artists = artists.map { BackupArtist(it.name, it.browseId) },
        albumId = albumId,
        albumName = albumName,
        isVideo = isVideo,
        isVideoOrigin = isVideoOrigin,
        localUri = localUri,
        localPath = localPath,
        localDateAddedSeconds = localDateAddedSeconds,
        localDateModifiedSeconds = localDateModifiedSeconds,
        trackNumber = trackNumber,
    )

    private fun BackupSong.toSong() = Song(
        videoId = videoId.ifBlank { localUri.orEmpty() },
        title = title,
        artist = artist,
        thumbnailUrl = thumbnailUrl,
        durationText = durationText,
        artistId = artistId,
        artists = artists.map { ArtistRef(it.name, it.browseId) },
        albumId = albumId,
        albumName = albumName,
        isVideo = isVideo,
        isVideoOrigin = isVideoOrigin || isVideo,
        localUri = localUri,
        localPath = localPath,
        localDateAddedSeconds = localDateAddedSeconds,
        localDateModifiedSeconds = localDateModifiedSeconds,
        trackNumber = trackNumber,
    )

    private fun LocalPlaylist.toBackupPlaylist() = BackupPlaylist(
        id = id,
        title = title,
        coverUrl = coverUrl,
        songs = songs.map { it.toBackupSong() },
    )

    private fun OfflinePlaylist.toBackupPlaylist() = BackupPlaylist(
        id = id,
        title = title,
        coverUrl = coverUrl,
        songs = songs.map { it.toBackupSong() },
    )

    private fun BackupPlaylist.toLocalPlaylist() = LocalPlaylist(
        id = id,
        title = title,
        songs = songs.map { it.toSong() },
        coverUrl = coverUrl,
    )

    private fun BackupPlaylist.toOfflinePlaylist() = OfflinePlaylist(
        id = id,
        title = title,
        songs = songs.map { it.toSong() },
        coverUrl = coverUrl,
    )

    /** What an export contains, for the status shown on the Export row. */
    data class ExportSummary(
        val months: Int,
        val spotifyPlaylists: Int,
        val devicePlaylists: Int,
        val tracks: Int,
        val queueTracks: Int,
    ) {
        val playlistCount: Int get() = spotifyPlaylists + devicePlaylists
    }

    /** Counts shown before the user confirms a restore. */
    data class Preview(
        val versionName: String,
        val exportedAt: String,
        val months: Int,
        val settings: Int,
        val spotifyPlaylists: Int,
        val spotifyTracks: Int,
        val devicePlaylists: Int,
        val deviceTracks: Int,
        val remotePlaylistMappings: Int,
        val schemaVersion: Int,
        val queueTracks: Int,
        val queueIndex: Int,
    ) {
        val playlistCount: Int get() = spotifyPlaylists + devicePlaylists
        val trackCount: Int get() = spotifyTracks + deviceTracks
    }

    data class Summary(
        val months: Int,
        val settings: Int,
        val spotifyPlaylists: Int,
        val devicePlaylists: Int,
        val tracks: Int,
        val queueTracks: Int,
        val from: String,
        val at: String,
        val mergedPlaylists: Boolean,
    ) {
        val playlistCount: Int get() = spotifyPlaylists + devicePlaylists
    }

    // Kept stable so backups made by earlier BitChord-branded builds remain readable.
    private const val APP_TAG = "bitchord"
    private const val MIN_SCHEMA_VERSION = 1
    private const val SCHEMA_VERSION = 2
    private const val MAX_BACKUP_BYTES = 64 * 1024 * 1024
    private const val MAX_SETTINGS = 20_000
    private const val MAX_SETTING_STRING_LENGTH = 16_384
    private const val MAX_PLAYLISTS = 10_000
    private const val MAX_TRACKS = 500_000
    private const val MAX_QUEUE_TRACKS = 100
    private const val MAX_LISTENING_MONTHS = 120

    @Serializable
    data class BackupFile(
        val app: String = APP_TAG,
        val version: Int = SCHEMA_VERSION,
        val versionName: String = "",
        val exportedAt: String = "",
        val settings: Map<String, PrefValue> = emptyMap(),
        val listening: List<StoredBucket> = emptyList(),
        val spotifyPlaylists: List<BackupPlaylist> = emptyList(),
        val remoteSpotifyImports: Map<String, List<String>> = emptyMap(),
        val devicePlaylists: List<BackupPlaylist> = emptyList(),
        val lastPlayedQueue: BackupQueue? = null,
    )

    @Serializable
    data class BackupQueue(
        val songs: List<BackupSong> = emptyList(),
        val index: Int = 0,
        val positionMs: Long = 0L,
    ) {
        fun toSnapshot() = LastPlayed.Snapshot(
            songs = songs.map { it.toSong() },
            index = index.coerceIn(songs.indices),
            positionMs = positionMs.coerceAtLeast(0L),
        )
    }

    @Serializable
    data class BackupPlaylist(
        val id: String,
        val title: String,
        val coverUrl: String? = null,
        val songs: List<BackupSong> = emptyList(),
    )

    @Serializable
    data class BackupSong(
        val videoId: String,
        val title: String,
        val artist: String,
        val thumbnailUrl: String? = null,
        val durationText: String? = null,
        val artistId: String? = null,
        val artists: List<BackupArtist> = emptyList(),
        val albumId: String? = null,
        val albumName: String? = null,
        val isVideo: Boolean = false,
        val isVideoOrigin: Boolean = false,
        val localUri: String? = null,
        val localPath: String? = null,
        val localDateAddedSeconds: Long? = null,
        val localDateModifiedSeconds: Long? = null,
        val trackNumber: Int? = null,
    )

    @Serializable
    data class BackupArtist(val name: String, val browseId: String? = null)

    /** One preference, with the primitive type it must be restored as. */
    @Serializable
    data class PrefValue(
        val type: String,
        val value: String? = null,
        val values: List<String> = emptyList(),
    ) {
        fun decoded(): Any? = when (type) {
            BOOLEAN -> value?.toBooleanStrictOrNull()
            INT -> value?.toIntOrNull()
            LONG -> value?.toLongOrNull()
            FLOAT -> value?.toFloatOrNull()?.takeIf(Float::isFinite)
            STRING -> value
            STRING_SET -> values.toSet()
            else -> null
        }

        fun isValid(): Boolean = when (type) {
            BOOLEAN -> value?.toBooleanStrictOrNull() != null
            INT -> value?.toIntOrNull() != null
            LONG -> value?.toLongOrNull() != null
            FLOAT -> value?.toFloatOrNull()?.isFinite() == true
            STRING -> value != null
            STRING_SET -> values.all { it.length <= MAX_SETTING_STRING_LENGTH }
            else -> false
        }

        companion object {
            fun of(value: Any?): PrefValue? = when (value) {
                is Boolean -> PrefValue(BOOLEAN, value.toString())
                is Int -> PrefValue(INT, value.toString())
                is Long -> PrefValue(LONG, value.toString())
                is Float -> value.takeIf(Float::isFinite)?.let { PrefValue(FLOAT, it.toString()) }
                is String -> PrefValue(STRING, value)
                is Set<*> -> PrefValue(STRING_SET, values = value.filterIsInstance<String>())
                else -> null
            }

            private const val BOOLEAN = "bool"
            private const val INT = "int"
            private const val LONG = "long"
            private const val FLOAT = "float"
            private const val STRING = "string"
            private const val STRING_SET = "stringSet"
        }
    }
}
