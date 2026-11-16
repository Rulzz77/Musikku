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
