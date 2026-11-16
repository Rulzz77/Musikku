package com.music.bitchord

import com.music.bitchord.data.stats.Backup
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupFormatTest {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    @Test
    fun `schema one backup remains readable without playlist sections`() {
        val legacy = """
            {
              "app": "bitchord",
              "version": 1,
              "versionName": "0.1.45",
              "exportedAt": "2026-11-15T12:00:00Z",
              "settings": {},
              "listening": []
            }
        """.trimIndent()

        val backup = json.decodeFromString(Backup.BackupFile.serializer(), legacy)

        assertEquals(1, backup.version)
        assertTrue(backup.spotifyPlaylists.isEmpty())
        assertTrue(backup.remoteSpotifyImports.isEmpty())
        assertTrue(backup.devicePlaylists.isEmpty())
    }

    @Test
    fun `schema two round trips both playlist collections and remote mappings`() {
        val song = Backup.BackupSong(
            videoId = "youtube-video-id",
            title = "Song title",
            artist = "Artist",
            artists = listOf(Backup.BackupArtist("Artist", "artist-channel")),
            albumName = "Album",
            queueTier = "USER_QUEUE",
            queueEntryId = "queue-entry-1",
            radioName = "Radio seed",
            playbackSource = "Search",
            playbackSourceType = "SEARCH",
            playbackSourceId = "search-page",
            isExplicit = false,
            sourceQuality = "LOSSLESS",
            sourceHiRes = true,
        )
        val local = Backup.BackupPlaylist(
            id = "spotify-local-1",
            title = "Spotify import",
            coverUrl = "https://example.invalid/cover.jpg",
            songs = listOf(song),
        )
        val device = Backup.BackupPlaylist(
            id = "liked",
            title = "Liked songs",
            songs = listOf(
                Backup.BackupSong(
                    videoId = "content://media/external/audio/media/42",
                    title = "Local track",
                    artist = "Local artist",
                    localUri = "content://media/external/audio/media/42",
                    localPath = "/storage/emulated/0/Music/track.flac",
                ),
            ),
        )
        val original = Backup.BackupFile(
            version = 2,
            spotifyPlaylists = listOf(local),
            remoteSpotifyImports = mapOf("VLremote-playlist" to listOf("youtube-video-id")),
            devicePlaylists = listOf(device),
            lastPlayedQueue = Backup.BackupQueue(
                songs = listOf(song),
                index = 0,
                positionMs = 42_000L,
            ),
        )

        val encoded = json.encodeToString(Backup.BackupFile.serializer(), original)
        val restored = json.decodeFromString(Backup.BackupFile.serializer(), encoded)

        assertEquals(original.spotifyPlaylists, restored.spotifyPlaylists)
        assertEquals(original.remoteSpotifyImports, restored.remoteSpotifyImports)
        assertEquals(original.devicePlaylists, restored.devicePlaylists)
        assertEquals(original.lastPlayedQueue, restored.lastPlayedQueue)
        val queueSnapshot = restored.lastPlayedQueue?.toSnapshot()
        assertEquals(0, queueSnapshot?.index)
        assertEquals(42_000L, queueSnapshot?.positionMs)
        assertEquals("youtube-video-id", queueSnapshot?.songs?.single()?.videoId)
        assertEquals("USER_QUEUE", queueSnapshot?.songs?.single()?.queueTier?.name)
        assertEquals("queue-entry-1", queueSnapshot?.songs?.single()?.queueEntryId)
        assertEquals("Radio seed", queueSnapshot?.songs?.single()?.radioName)
        assertEquals("Search", queueSnapshot?.songs?.single()?.playbackSource)
        assertEquals("LOSSLESS", queueSnapshot?.songs?.single()?.sourceQuality)
        assertEquals(true, queueSnapshot?.songs?.single()?.sourceHiRes)
    }

    @Test
    fun `preference values retain their exact Android primitive types`() {
        assertEquals(0.5f, Backup.PrefValue.of(0.5f)?.decoded())
        assertEquals(42L, Backup.PrefValue.of(42L)?.decoded())
        assertEquals(true, Backup.PrefValue.of(true)?.decoded())
        assertTrue(!Backup.PrefValue("float", "NaN").isValid())
    }
}
