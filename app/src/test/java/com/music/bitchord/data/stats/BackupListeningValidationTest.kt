package com.music.bitchord.data.stats

import org.junit.Assert.fail
import org.junit.Test

class BackupListeningValidationTest {

    @Test
    fun `accepts a normal monthly aggregate and daily maps`() {
        val bucket = StoredBucket(
            month = "2026-04",
            tracks = listOf(
                TrackEntry(
                    id = "youtube-video-id",
                    title = "Song",
                    artist = "Artist",
                    ms = 3_600_000L,
                    plays = 2,
                    last = 1_777_000_000_000L,
                    days = mutableMapOf("2026-04-05" to DayStats(3_600_000L, 2)),
                ),
            ),
            artists = listOf(
                NameEntry(
                    name = "Artist",
                    ms = 3_600_000L,
                    plays = 2,
                    days = mutableMapOf("2026-04-05" to DayStats(3_600_000L, 2)),
                ),
            ),
            albums = emptyList(),
            hours = List(24) { if (it == 18) 3_600_000L else 0L },
            days = mapOf(5 to 3_600_000L),
            trackDays = mapOf("2026-04-05" to DayStats(3_600_000L, 2)),
        )

        Backup.validateListeningBuckets(
            listOf(bucket.copy(hours = List(24) { if (it == 18) 90_000_000L else 0L })),
        )
    }

    @Test
    fun `rejects negative or out of month aggregate values`() {
        val invalid = listOf(
            StoredBucket(month = "2026-04", days = mapOf(0 to 1L)),
            StoredBucket(month = "2026-04", days = mapOf(32 to 1L)),
            StoredBucket(month = "2026-04", days = mapOf(1 to -1L)),
            StoredBucket(month = "2026-04", hours = List(25) { 0L }),
            StoredBucket(month = "2026-04", hours = List(24) { if (it == 0) -1L else 0L }),
            StoredBucket(
                month = "2026-04",
                trackDays = mapOf("2026-05-01" to DayStats(1L, 1)),
            ),
            StoredBucket(
                month = "2026-04",
                artistDays = mapOf("not-a-date" to DayStats(1L, 1)),
            ),
        )
        invalid.forEach { bucket ->
            try {
                Backup.validateListeningBuckets(listOf(bucket))
                fail("Malformed bucket should be rejected: $bucket")
            } catch (_: IllegalArgumentException) {
                // Expected.
            }
        }
    }

    @Test
    fun `rejects negative counters oversized collections and duplicate track IDs`() {
        val invalid = listOf(
            StoredBucket(
                month = "2026-04",
                tracks = listOf(TrackEntry(id = "song", ms = -1L)),
            ),
            StoredBucket(
                month = "2026-04",
                tracks = listOf(TrackEntry(id = "song", plays = -1)),
            ),
            StoredBucket(
                month = "2026-04",
                tracks = listOf(TrackEntry(id = "song", plays = Int.MAX_VALUE)),
            ),
            StoredBucket(
                month = "2026-04",
                tracks = listOf(TrackEntry(id = "song"), TrackEntry(id = "song")),
            ),
            StoredBucket(
                month = "2026-04",
                tracks = listOf(TrackEntry(id = "")),
            ),
        )
        invalid.forEach { bucket ->
            try {
                Backup.validateListeningBuckets(listOf(bucket))
                fail("Malformed bucket should be rejected: $bucket")
            } catch (_: IllegalArgumentException) {
                // Expected.
            }
        }
    }

    @Test
    fun `rejects a duplicate or non canonical month string`() {
        listOf(
            listOf(StoredBucket(month = "2026-04"), StoredBucket(month = "2026-04")),
            listOf(StoredBucket(month = "2026-4")),
        ).forEach { buckets ->
            try {
                Backup.validateListeningBuckets(buckets)
                fail("Duplicate month should be rejected")
            } catch (_: Exception) {
                // Expected.
            }
        }
    }
}
