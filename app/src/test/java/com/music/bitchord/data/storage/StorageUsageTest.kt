package com.music.bitchord.data.storage

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class StorageUsageTest {

    @Test
    fun directoryBytesCountsNestedFilesButNotDirectoryEntries() {
        val root = createTempDir(prefix = "musikku-storage-")
        try {
            File(root, "one.bin").writeBytes(ByteArray(12))
            val nested = File(root, "nested").apply { mkdirs() }
            File(nested, "two.bin").writeBytes(ByteArray(30))
            File(nested, "empty.bin").writeBytes(byteArrayOf())

            assertEquals(42L, StorageUsage.directoryBytes(root))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun fileUriBytesCountsWholeOfflinePackageForPlaylistEntry() {
        val packageDir = createTempDir(prefix = "musikku-offline-")
        try {
            File(packageDir, "playlist.m3u8").writeText("#EXTM3U")
            File(packageDir, "segment-0001.m4s").writeBytes(ByteArray(128))
            File(packageDir, "cover.jpg").writeBytes(ByteArray(64))

            assertEquals(198L, StorageUsage.fileUriBytes(File(packageDir, "playlist.m3u8").path))
        } finally {
            packageDir.deleteRecursively()
        }
    }

    @Test
    fun directoryBytesReturnsZeroForMissingPaths() {
        val root = File(createTempDir(prefix = "musikku-storage-"), "not-created")
        assertEquals(0L, StorageUsage.directoryBytes(root))
        root.parentFile?.deleteRecursively()
    }

    @Test
    fun formatBytesUsesReadableBinaryUnits() {
        assertEquals("0 B", StorageUsage.formatBytes(0L))
        assertEquals("1.0 KB", StorageUsage.formatBytes(1024L))
        assertEquals("1.0 MB", StorageUsage.formatBytes(1024L * 1024L))
    }
}
