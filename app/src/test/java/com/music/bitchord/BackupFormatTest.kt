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
        assertTrue(backup.playlistFolders.isEmpty())
    }

    @Test
    fun `schema two round trips both playlist collections and remote mappings`() {
        val song = Backup.BackupSong(
            videoId = "youtube-video-id",
            title = "Song title",
            artist = "Artist",
            artists = listOf(Backup.BackupArtist("Artist", "artist-channel")),
            albumName = "Album",
            isExplicit = false,
            sourceQuality = "LOSSLESS",
            sourceHiRes = true,
            isPodcastEpisode = true,
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
        )

        val encoded = json.encodeToString(Backup.BackupFile.serializer(), original)
        val restored = json.decodeFromString(Backup.BackupFile.serializer(), encoded)

        assertEquals(original.spotifyPlaylists, restored.spotifyPlaylists)
        assertEquals(original.remoteSpotifyImports, restored.remoteSpotifyImports)
        assertEquals(original.devicePlaylists, restored.devicePlaylists)
        assertEquals("LOSSLESS", restored.spotifyPlaylists.single().songs.single().sourceQuality)
        assertTrue(restored.spotifyPlaylists.single().songs.single().sourceHiRes)
        assertTrue(restored.spotifyPlaylists.single().songs.single().isPodcastEpisode)
    }

    @Test
    fun `schema three round trips playlist folders without changing playlist data`() {
        val original = Backup.BackupFile(
            version = 3,
            playlistFolders = listOf(
                Backup.BackupPlaylistFolder(
                    id = "folder-roadtrip",
                    title = "Road trip",
                    playlists = listOf("VLremote-playlist", "local:playlist:spotify-import"),
                ),
                Backup.BackupPlaylistFolder(
                    id = "folder-focus",
                    title = "Focus",
                    playlists = listOf("local:offline:study"),
                ),
            ),
        )

        val encoded = json.encodeToString(Backup.BackupFile.serializer(), original)
        val restored = json.decodeFromString(Backup.BackupFile.serializer(), encoded)

        assertEquals(3, restored.version)
        assertEquals(original.playlistFolders, restored.playlistFolders)
    }

    @Test
    fun `schema two backup without folder metadata remains readable`() {
        val schemaTwo = """
            {
              "app": "bitchord",
              "version": 2,
              "versionName": "0.1.51",
              "exportedAt": "2026-11-16T12:00:00Z",
              "settings": {},
              "listening": [],
              "spotifyPlaylists": [],
              "remoteSpotifyImports": {},
              "devicePlaylists": [
                {"id":"liked","title":"Liked songs","songs":[]}
              ]
            }
        """.trimIndent()

        val restored = json.decodeFromString(Backup.BackupFile.serializer(), schemaTwo)

        assertEquals(2, restored.version)
        assertTrue(restored.playlistFolders.isEmpty())
    }

    @Test
    fun `preference values retain their exact Android primitive types`() {
        assertEquals(0.5f, Backup.PrefValue.of(0.5f)?.decoded())
        assertEquals(42L, Backup.PrefValue.of(42L)?.decoded())
        assertEquals(true, Backup.PrefValue.of(true)?.decoded())
        assertTrue(!Backup.PrefValue("float", "NaN").isValid())
    }
}
