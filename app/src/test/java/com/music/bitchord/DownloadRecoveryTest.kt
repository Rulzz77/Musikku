package com.music.bitchord

import com.music.bitchord.data.model.ArtistRef
import com.music.bitchord.data.model.Song
import com.music.bitchord.download.DownloadProgress
import com.music.bitchord.download.DownloadRecoverySnapshot
import com.music.bitchord.download.DownloadSession
import com.music.bitchord.download.toDownloadSessionState
import com.music.bitchord.download.toRecoverySnapshot
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadRecoveryTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `snapshot round trips the metadata needed to retry a download`() {
        val song = Song(
            videoId = "video-1",
            title = "Kesariya",
            artist = "Arijit Singh",
            thumbnailUrl = "https://example.test/cover.jpg",
            durationText = "4:28",
            artistId = "artist-1",
            artists = listOf(ArtistRef("Arijit Singh", "artist-1"), ArtistRef("Pritam", "artist-2")),
            albumId = "album-1",
            albumName = "Brahmastra",
            isVideo = true,
            isVideoOrigin = true,
            sourceQuality = "LOSSLESS",
            sourceHiRes = true,
            isExplicit = false,
        )
        val state = DownloadSession.State(
            items = listOf(
                DownloadSession.Item(
                    videoId = "video-1",
                    song = song,
                    progress = DownloadProgress.Queued,
                    from = "Brahmastra",
                    sequence = 7L,
                    fromCache = true,
                ),
            ),
            seenAt = 8L,
            settledAt = 6L,
        )

        val encoded = json.encodeToString(DownloadRecoverySnapshot.serializer(), state.toRecoverySnapshot())
        val restored = json.decodeFromString(DownloadRecoverySnapshot.serializer(), encoded)
            .toDownloadSessionState()

        assertEquals(8L, restored.seenAt)
        assertEquals(6L, restored.settledAt)
        val item = restored.items.single()
        assertEquals("video-1", item.videoId)
        assertEquals(song.title, item.song.title)
        assertEquals(song.artist, item.song.artist)
        assertEquals(song.thumbnailUrl, item.song.thumbnailUrl)
        assertEquals(song.durationText, item.song.durationText)
        assertEquals(song.albumName, item.song.albumName)
        assertEquals(song.artists, item.song.artists)
        assertEquals(song.sourceQuality, item.song.sourceQuality)
        assertTrue(item.song.sourceHiRes)
        assertEquals("Brahmastra", item.from)
        assertTrue(item.fromCache)
        assertTrue(item.recoverable)
    }

    @Test
    fun `running downloads recover as queued while completed and failed outcomes stay visible`() {
        val state = DownloadSession.State(
            items = listOf(
                DownloadSession.Item("queued", song("queued"), DownloadProgress.Queued, sequence = 1L),
                DownloadSession.Item("running", song("running"), DownloadProgress.Running(0.63f), sequence = 2L),
                DownloadSession.Item("done", song("done"), DownloadProgress.Done, sequence = 3L),
                DownloadSession.Item("failed", song("failed"), DownloadProgress.Failed("HTTP 503"), sequence = 4L),
            ),
            seenAt = 10L,
            settledAt = 9L,
        )

        val restored = state.toRecoverySnapshot().toDownloadSessionState()
        val byId = restored.items.associateBy { it.videoId }

        assertEquals(DownloadProgress.Queued, byId.getValue("queued").progress)
        assertEquals(DownloadProgress.Queued, byId.getValue("running").progress)
        assertEquals(DownloadProgress.Done, byId.getValue("done").progress)
        assertEquals(DownloadProgress.Failed("HTTP 503"), byId.getValue("failed").progress)
        assertTrue(restored.busy)
        assertTrue(restored.visible)
    }

    @Test
    fun `unsettled queue is never truncated but settled history is bounded`() {
        val manySettled = (1L..250L).map { sequence ->
            DownloadSession.Item(
                videoId = "done-$sequence",
                song = song("done-$sequence"),
                progress = DownloadProgress.Done,
                sequence = sequence,
            )
        }
        val waiting = (251L..275L).map { sequence ->
            DownloadSession.Item(
                videoId = "queued-$sequence",
                song = song("queued-$sequence"),
                progress = DownloadProgress.Queued,
                sequence = sequence,
            )
        }

        val snapshot = DownloadSession.State(items = manySettled + waiting).toRecoverySnapshot()

        assertEquals(DownloadRecoverySnapshot.MAX_SETTLED_ITEMS + waiting.size, snapshot.items.size)
        assertEquals(waiting.size, snapshot.items.count { it.status == "queued" })
        assertEquals("done-51", snapshot.items.first().videoId)
    }

    @Test
    fun `unknown snapshot schema is safely ignored`() {
        val restored = DownloadRecoverySnapshot(
            schemaVersion = DownloadRecoverySnapshot.CURRENT_SCHEMA + 1,
            items = emptyList(),
        ).toDownloadSessionState()

        assertTrue(restored.items.isEmpty())
        assertFalse(restored.visible)
    }

    private fun song(id: String) = Song(
        videoId = id,
        title = id,
        artist = "Artist",
        thumbnailUrl = null,
    )
}
