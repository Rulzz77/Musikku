package com.music.bitchord.data.stats

import android.content.Context
import android.net.Uri
import com.music.bitchord.BuildConfig
import com.music.bitchord.data.OfflinePlaylist
import com.music.bitchord.data.OfflinePlaylists
import com.music.bitchord.data.PlaylistFolder
import com.music.bitchord.data.PlaylistFolders
import com.music.bitchord.data.model.ArtistRef
import com.music.bitchord.data.model.Song
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
import java.time.LocalDate
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
            val playlistFolders = PlaylistFolders.folders.value.map { it.toBackupFolder() }
            val smartPlaylistRules = SmartPlaylists.rules.value.map { it.toBackupSmartPlaylistRule() }
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
                playlistFolders = playlistFolders,
                smartPlaylistRules = smartPlaylistRules,
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
                playlistFolders = playlistFolders.size,
                smartPlaylistRules = smartPlaylistRules.size,
            )
        }
    }

    /** Parses and validates a backup without changing anything on this device. */
    suspend fun previewFrom(context: Context, source: Uri): Result<Preview> = withContext(Dispatchers.IO) {
        runCatching { readBackup(context, source).toPreview() }
    }

    /**
     * Restores settings, listening totals, playlist collections, folders,
     * and (for schema v4+) custom Smart Playlist rules. Credentials and
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
            val playlistFolders = file.playlistFolders.map { it.toPlaylistFolder() }
            val smartPlaylistRules = file.smartPlaylistRules.map { it.toSmartPlaylistRule() }
            val remoteImports = file.remoteSpotifyImports.mapValues { (_, ids) -> ids.toSet() }

            // Snapshot every store that this restore can replace. All file
            // parsing and validation has already completed in readBackup().
            // Keep the cross-store commit ordered and roll all stores back if
            // any later persistence step fails.
            val previousListening = ListeningStats.exportAll()
            val previousSettings = AppSettings.exportPrefs()
            val previousSpotifyPlaylists = LocalPlaylistStore.playlists.value.toList()
            val previousRemoteImports = LocalPlaylistStore.remoteSpotifyImportsSnapshot()
            val previousDevicePlaylists = OfflinePlaylists.playlists.value.toList()
            val previousPlaylistFolders = PlaylistFolders.folders.value.toList()
            val previousSmartPlaylistRules = SmartPlaylists.rules.value.toList()

            var listeningAttempted = false
            var settingsAttempted = false
            var collectionsAttempted = false
            try {
                ListeningStats.importAll(file.listening)
                listeningAttempted = true

                if (file.version >= 2) {
                    collectionsAttempted = true
                    LocalPlaylistStore.restoreFromBackup(spotifyPlaylists, remoteImports, mergePlaylists)
                    OfflinePlaylists.restoreFromBackup(devicePlaylists, mergePlaylists)
                    if (file.version >= 3) PlaylistFolders.restoreFromBackup(playlistFolders, mergePlaylists)
                    if (file.version >= 4) SmartPlaylists.restoreFromBackup(smartPlaylistRules, mergePlaylists)
                }

                settingsAttempted = true
                AppSettings.importPrefs(settings)
                SearchHistory.reload()
            } catch (failure: Throwable) {
                val rollbackFailures = mutableListOf<Throwable>()
                if (collectionsAttempted) {
                    runCatching {
                        LocalPlaylistStore.restoreFromBackup(
                            previousSpotifyPlaylists,
                            previousRemoteImports,
                            merge = false,
                        )
                    }.exceptionOrNull()?.let(rollbackFailures::add)
                    runCatching {
                        OfflinePlaylists.restoreFromBackup(previousDevicePlaylists, merge = false)
                    }.exceptionOrNull()?.let(rollbackFailures::add)
                    runCatching {
                        PlaylistFolders.restoreFromBackup(previousPlaylistFolders, merge = false)
                    }.exceptionOrNull()?.let(rollbackFailures::add)
                    runCatching {
                        SmartPlaylists.restoreFromBackup(previousSmartPlaylistRules, merge = false)
                    }.exceptionOrNull()?.let(rollbackFailures::add)
                }
                if (listeningAttempted) {
                    runCatching { ListeningStats.importAll(previousListening) }
                        .exceptionOrNull()?.let(rollbackFailures::add)
                }
                if (settingsAttempted) {
                    runCatching { AppSettings.importPrefs(previousSettings) }
                        .exceptionOrNull()?.let(rollbackFailures::add)
                }
                if (rollbackFailures.isNotEmpty()) {
                    throw IllegalStateException(
                        "Backup restore failed and one or more previous stores could not be fully restored",
                        failure,
                    ).also { error -> rollbackFailures.forEach(error::addSuppressed) }
                }
                throw failure
            }

            val restoredSpotifyPlaylists = if (file.version >= 2) {
                LocalPlaylistStore.playlists.value
            } else {
                emptyList()
            }
            val restoredDevicePlaylists = if (file.version >= 2) {
                OfflinePlaylists.playlists.value
            } else {
                emptyList()
            }
            Summary(
                months = file.listening.size,
                settings = file.settings.size,
                spotifyPlaylists = restoredSpotifyPlaylists.size,
                devicePlaylists = restoredDevicePlaylists.size,
                tracks = restoredSpotifyPlaylists.sumOf { it.songs.size } +
                    restoredDevicePlaylists.sumOf { it.songs.size },
                from = file.versionName,
                at = file.exportedAt,
                mergedPlaylists = mergePlaylists,
                playlistFolders = PlaylistFolders.folders.value.size,
                schemaVersion = file.version,
                smartPlaylistRules = if (file.version >= 4) SmartPlaylists.rules.value.size else 0,
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
            require(key.isNotBlank() && value.isValid()) {
                "Backup contains an invalid setting: $key"
            }
            require(AppSettings.isValidImportedPreference(key, value.decoded())) {
                "Backup contains an out-of-range setting: $key"
            }
        }
        validatePlaylists(file.spotifyPlaylists, "Spotify")
        validatePlaylists(file.devicePlaylists, "device")
        if (file.version >= 3) validatePlaylistFolders(file.playlistFolders)
        if (file.version >= 4) validateSmartPlaylistRules(file.smartPlaylistRules)
        if (file.version >= 2) {
            require(file.devicePlaylists.any { it.id == OfflinePlaylists.LIKED_ID }) {
                "Backup is missing the built-in Liked songs playlist"
            }
        }
        require(file.playlistFolders.size <= MAX_PLAYLIST_FOLDERS) {
            "Backup contains too many playlist folders"
        }
        require(file.spotifyPlaylists.size + file.devicePlaylists.size <= MAX_PLAYLISTS) {
            "Backup contains too many playlists"
        }
        val trackCount = file.spotifyPlaylists.sumOf { it.songs.size } +
            file.devicePlaylists.sumOf { it.songs.size }
        require(trackCount <= MAX_TRACKS) { "Backup contains too many playlist tracks" }
        require(file.remoteSpotifyImports.size <= MAX_PLAYLISTS) {
            "Backup contains too many remote playlist mappings"
        }
        file.remoteSpotifyImports.forEach { (playlistId, ids) ->
            require(playlistId.isNotBlank() && ids.size <= MAX_TRACKS && ids.all(String::isNotBlank)) {
                "Backup contains an invalid Spotify playlist mapping"
            }
        }
        require(file.listening.size <= MAX_LISTENING_MONTHS) { "Backup contains too much listening history" }
        validateListeningBuckets(file.listening)
        return file
    }

    /**
     * History buckets are consumed by Replay as trusted aggregates. Reject
     * malformed dates, duplicate IDs, oversized maps, and negative counters
     * here rather than letting corrupt values leak into chart arithmetic.
     */
    private fun validateListeningBuckets(buckets: List<StoredBucket>) {
        val months = HashSet<String>()
        buckets.forEach { bucket ->
            val month = runCatching { YearMonth.parse(bucket.month) }.getOrNull()
                ?: error("Backup contains an invalid listening-history month")
            require(bucket.month == month.toString() && months.add(bucket.month)) {
                "Backup contains a non-canonical or duplicate listening-history month"
            }
            val daysInMonth = month.lengthOfMonth()
            val monthMs = daysInMonth * 86_400_000L
            fun validDate(dateKey: String): Boolean =
                runCatching { LocalDate.parse(dateKey) }.getOrNull()?.let {
                    YearMonth.from(it) == month
                } == true
            fun validDailyStats(stats: DayStats): Boolean =
                stats.ms in 0L..86_400_000L && stats.plays >= 0
            fun validDays(days: Map<String, DayStats>): Boolean =
                days.size <= daysInMonth && days.all { (date, stats) ->
                    validDate(date) && validDailyStats(stats)
                }

            require(bucket.tracks.size <= 600 && bucket.artists.size <= 400 && bucket.albums.size <= 400) {
                "Backup contains too many listening-history entries in $month"
            }
            require(bucket.hours.size <= 24 && bucket.hours.all { it in 0L..86_400_000L }) {
                "Backup contains invalid hourly listening totals in $month"
            }
            require(bucket.days.size <= daysInMonth && bucket.days.all { (day, ms) ->
                day in 1..daysInMonth && ms in 0L..86_400_000L
            }) {
                "Backup contains invalid daily listening totals in $month"
            }
            require(bucket.tracks.map { it.id }.distinct().size == bucket.tracks.size) {
                "Backup contains duplicate listening-history track IDs in $month"
            }
            bucket.tracks.forEach { track ->
                require(track.id.isNotBlank() && track.id.length <= 4_096 &&
                    track.title.length <= 4_096 && track.artist.length <= 4_096 &&
                    (track.album?.length ?: 0) <= 4_096 &&
                    (track.art?.length ?: 0) <= 4_096 &&
                    (track.localUri?.length ?: 0) <= 4_096 &&
                    (track.localPath?.length ?: 0) <= 4_096 &&
                    (track.durationText?.length ?: 0) <= 256 &&
                    track.ms in 0L..monthMs && track.plays >= 0 && track.last >= 0L &&
                    track.days.size <= daysInMonth && validDays(track.days)) {
                    "Backup contains an invalid listening-history track in $month"
                }
            }
            bucket.artists.forEach { artist ->
                require(artist.name.isNotBlank() && artist.name.length <= 4_096 &&
                    (artist.sub?.length ?: 0) <= 4_096 &&
                    (artist.art?.length ?: 0) <= 4_096 &&
                    (artist.id?.length ?: 0) <= 4_096 &&
                    (artist.key?.length ?: 0) <= 8_192 &&
                    artist.ms in 0L..monthMs && artist.plays >= 0 &&
                    artist.days.size <= daysInMonth && validDays(artist.days)) {
                    "Backup contains an invalid listening-history artist in $month"
                }
            }
            bucket.albums.forEach { album ->
                require(album.name.isNotBlank() && album.name.length <= 4_096 &&
                    (album.sub?.length ?: 0) <= 4_096 &&
                    (album.art?.length ?: 0) <= 4_096 &&
                    (album.id?.length ?: 0) <= 4_096 &&
                    (album.key?.length ?: 0) <= 8_192 &&
                    album.ms in 0L..monthMs && album.plays >= 0 &&
                    album.days.size <= daysInMonth && validDays(album.days)) {
                    "Backup contains an invalid listening-history album in $month"
                }
            }

            listOfNotNull(bucket.trackDays, bucket.artistDays, bucket.albumDays).forEach { daily ->
                require(daily.size <= daysInMonth && daily.all { (date, stats) ->
                    validDate(date) && validDailyStats(stats)
                }) {
                    "Backup contains invalid per-day history in $month"
                }
            }
        }
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

    private fun validatePlaylistFolders(folders: List<BackupPlaylistFolder>) {
        val ids = HashSet<String>()
        val assignedPlaylists = HashSet<String>()
        var membershipCount = 0
        folders.forEach { folder ->
            require(folder.id.isNotBlank() && folder.id.length <= 512) {
                "Backup contains an invalid playlist folder id"
            }
            require(ids.add(folder.id)) { "Backup contains duplicate playlist folders" }
            require(folder.title.isNotBlank() && folder.title.length <= 2_000) {
                "Backup contains an invalid playlist folder title"
            }
            folder.playlists.forEach { browseId ->
                membershipCount++
                require(browseId.isNotBlank() && browseId.length <= 4_096 && assignedPlaylists.add(browseId)) {
                    "Backup contains an invalid or duplicate playlist folder membership"
                }
            }
        }
        require(membershipCount <= MAX_FOLDER_MEMBERSHIPS) {
            "Backup contains too many playlist folder memberships"
        }
    }

    private fun validateSmartPlaylistRules(rules: List<BackupSmartPlaylistRule>) {
        require(rules.size <= MAX_SMART_PLAYLIST_RULES) {
            "Backup contains too many Smart Playlist rules"
        }
        val ids = HashSet<String>()
        rules.forEach { rule ->
            require(rule.id.isNotBlank() && rule.id.length <= 512 && ids.add(rule.id)) {
                "Backup contains an invalid or duplicate Smart Playlist rule id"
            }
            require(rule.name.isNotBlank() && rule.name.length <= MAX_SMART_PLAYLIST_NAME_LENGTH) {
                "Backup contains an invalid Smart Playlist name"
            }
            require(rule.artistContains.length <= MAX_SMART_PLAYLIST_ARTIST_LENGTH &&
                rule.genreContains.length <= MAX_SMART_PLAYLIST_GENRE_LENGTH) {
                "Backup contains an oversized Smart Playlist text filter"
            }
            require((rule.releaseYearFrom == null || rule.releaseYearFrom in MIN_RELEASE_YEAR..MAX_RELEASE_YEAR) &&
                (rule.releaseYearTo == null || rule.releaseYearTo in MIN_RELEASE_YEAR..MAX_RELEASE_YEAR) &&
                (rule.releaseYearFrom == null || rule.releaseYearTo == null || rule.releaseYearFrom <= rule.releaseYearTo)) {
                "Backup contains an invalid Smart Playlist year range"
            }
            require((rule.minimumDurationMinutes == null || rule.minimumDurationMinutes in 1..MAX_DURATION_MINUTES) &&
                (rule.maximumDurationMinutes == null || rule.maximumDurationMinutes in 1..MAX_DURATION_MINUTES) &&
                (rule.minimumDurationMinutes == null || rule.maximumDurationMinutes == null ||
                    rule.minimumDurationMinutes <= rule.maximumDurationMinutes)) {
                "Backup contains an invalid Smart Playlist duration range"
            }
            require(rule.lastPlayedWithinDays == null || rule.lastPlayedWithinDays in 1..MAX_LAST_PLAYED_DAYS) {
                "Backup contains an invalid Smart Playlist last-played filter"
            }
            require(rule.matchMode in setOf("ALL", "ANY")) {
                "Backup contains an invalid Smart Playlist match mode"
            }
            require(rule.minimumPlays in 1..MAX_SMART_PLAYLIST_MINIMUM_PLAYS) {
                "Backup contains an invalid Smart Playlist play-count filter"
            }
            require(runCatching { SmartPlaylistSort.valueOf(rule.sort) }.isSuccess) {
                "Backup contains an invalid Smart Playlist sort order"
            }
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
        playlistFolders = playlistFolders.size,
        schemaVersion = version,
        smartPlaylistRules = smartPlaylistRules.size,
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
        isExplicit = isExplicit,
        localUri = localUri,
        localPath = localPath,
        localDateAddedSeconds = localDateAddedSeconds,
        localDateModifiedSeconds = localDateModifiedSeconds,
        trackNumber = trackNumber,
        sourceQuality = sourceQuality,
        sourceHiRes = sourceHiRes,
        isPodcastEpisode = isPodcastEpisode,
        releaseYear = releaseYear,
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
        isExplicit = isExplicit,
        localUri = localUri,
        localPath = localPath,
        localDateAddedSeconds = localDateAddedSeconds,
        localDateModifiedSeconds = localDateModifiedSeconds,
        trackNumber = trackNumber,
        sourceQuality = sourceQuality,
        sourceHiRes = sourceHiRes,
        isPodcastEpisode = isPodcastEpisode,
        releaseYear = releaseYear,
    )

    private fun LocalPlaylist.toBackupPlaylist() = BackupPlaylist(
        id = id,
        title = title,
        coverUrl = coverUrl,
        songs = songs.map { it.toBackupSong() },
    )

    private fun PlaylistFolder.toBackupFolder() = BackupPlaylistFolder(
        id = id,
        title = title,
        playlists = playlistBrowseIds,
    )

    private fun BackupPlaylistFolder.toPlaylistFolder() = PlaylistFolder(
        id = id,
        title = title,
        playlistBrowseIds = playlists,
    )

    private fun SmartPlaylistRule.toBackupSmartPlaylistRule() = BackupSmartPlaylistRule(
        id = id,
        name = name,
        artistContains = artistContains,
        minimumPlays = minimumPlays,
        sort = sort.name,
        genreContains = genreContains,
        releaseYearFrom = releaseYearFrom,
        releaseYearTo = releaseYearTo,
        minimumDurationMinutes = minimumDurationMinutes,
        maximumDurationMinutes = maximumDurationMinutes,
        lastPlayedWithinDays = lastPlayedWithinDays,
        matchMode = matchMode.name,
    )

    private fun BackupSmartPlaylistRule.toSmartPlaylistRule() = SmartPlaylistRule(
        id = id,
        name = name,
        artistContains = artistContains,
        minimumPlays = minimumPlays,
        sort = SmartPlaylistSort.valueOf(sort),
        genreContains = genreContains,
        releaseYearFrom = releaseYearFrom,
        releaseYearTo = releaseYearTo,
        minimumDurationMinutes = minimumDurationMinutes,
        maximumDurationMinutes = maximumDurationMinutes,
        lastPlayedWithinDays = lastPlayedWithinDays,
        matchMode = runCatching { SmartPlaylistMatchMode.valueOf(matchMode) }
            .getOrDefault(SmartPlaylistMatchMode.ALL),
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
        val playlistFolders: Int = 0,
        val smartPlaylistRules: Int = 0,
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
        val playlistFolders: Int = 0,
        val schemaVersion: Int,
        val smartPlaylistRules: Int = 0,
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
        val from: String,
        val at: String,
        val mergedPlaylists: Boolean,
        val playlistFolders: Int = 0,
        val schemaVersion: Int,
        val smartPlaylistRules: Int = 0,
    ) {
        val playlistCount: Int get() = spotifyPlaylists + devicePlaylists
    }

    // Kept stable so backups made by earlier app releases remain readable; do not rename this value.
    private const val APP_TAG = "bitchord"
    private const val MIN_SCHEMA_VERSION = 1
    private const val SCHEMA_VERSION = 5
    private const val MAX_BACKUP_BYTES = 64 * 1024 * 1024
    private const val MAX_SETTINGS = 20_000
    private const val MAX_SETTING_STRING_LENGTH = 16_384
    private const val MAX_PLAYLISTS = 10_000
    private const val MAX_PLAYLIST_FOLDERS = 10_000
    private const val MAX_FOLDER_MEMBERSHIPS = 100_000
    private const val MAX_SMART_PLAYLIST_RULES = 20
    private const val MAX_SMART_PLAYLIST_NAME_LENGTH = 40
    private const val MAX_SMART_PLAYLIST_ARTIST_LENGTH = 80
    private const val MAX_SMART_PLAYLIST_GENRE_LENGTH = 80
    private const val MIN_RELEASE_YEAR = 1888
    private const val MAX_RELEASE_YEAR = 2100
    private const val MAX_DURATION_MINUTES = 1_440
    private const val MAX_LAST_PLAYED_DAYS = 3_650
    private const val MAX_SMART_PLAYLIST_MINIMUM_PLAYS = 100
    private const val MAX_TRACKS = 500_000
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
        val playlistFolders: List<BackupPlaylistFolder> = emptyList(),
        val smartPlaylistRules: List<BackupSmartPlaylistRule> = emptyList(),
    )

    @Serializable
    data class BackupSmartPlaylistRule(
        val id: String,
        val name: String,
        val artistContains: String = "",
        val minimumPlays: Int = 1,
        val sort: String = "MOST_PLAYED",
        val genreContains: String = "",
        val releaseYearFrom: Int? = null,
        val releaseYearTo: Int? = null,
        val minimumDurationMinutes: Int? = null,
        val maximumDurationMinutes: Int? = null,
        val lastPlayedWithinDays: Int? = null,
        val matchMode: String = "ALL",
    )

    @Serializable
    data class BackupPlaylistFolder(
        val id: String,
        val title: String,
        val playlists: List<String> = emptyList(),
    )

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
        val isExplicit: Boolean? = null,
        val sourceQuality: String? = null,
        val sourceHiRes: Boolean = false,
        val isPodcastEpisode: Boolean = false,
        val localUri: String? = null,
        val localPath: String? = null,
        val localDateAddedSeconds: Long? = null,
        val localDateModifiedSeconds: Long? = null,
        val trackNumber: Int? = null,
        val releaseYear: Int? = null,
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
            STRING -> value != null && value.length <= MAX_SETTING_STRING_LENGTH
            STRING_SET -> values.size <= MAX_SETTINGS && values.all { it.length <= MAX_SETTING_STRING_LENGTH }
            else -> false
        }

        companion object {
            fun of(value: Any?): PrefValue? = when (value) {
                is Boolean -> PrefValue(BOOLEAN, value.toString())
                is Int -> PrefValue(INT, value.toString())
                is Long -> PrefValue(LONG, value.toString())
                is Float -> value.takeIf(Float::isFinite)?.let { PrefValue(FLOAT, it.toString()) }
                is String -> value.takeIf { it.length <= MAX_SETTING_STRING_LENGTH }?.let { PrefValue(STRING, it) }
                is Set<*> -> PrefValue(
                    STRING_SET,
                    values = value.filterIsInstance<String>().filter { it.length <= MAX_SETTING_STRING_LENGTH },
                )
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
