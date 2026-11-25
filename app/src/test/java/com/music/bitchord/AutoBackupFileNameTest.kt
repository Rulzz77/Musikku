package com.music.bitchord

import com.music.bitchord.data.stats.autoBackupFileName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoBackupFileNameTest {
    @Test
    fun namesAreStableUtcJsonFiles() {
        assertEquals(
            "MusikKu-Auto-Backup-1970-01-01_00-00-00-000.json",
            autoBackupFileName(0L),
        )
    }

    @Test
    fun newerSnapshotsSortAfterOlderOnes() {
        val first = autoBackupFileName(1_000L)
        val second = autoBackupFileName(2_000L)
        assertTrue(first < second)
        assertTrue(first.endsWith(".json"))
        assertTrue(second.endsWith(".json"))
    }
}
