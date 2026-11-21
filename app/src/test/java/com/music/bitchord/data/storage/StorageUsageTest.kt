package com.music.bitchord.data.storage

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.nio.file.Files

class StorageUsageTest {

    @Test
    fun directoryBytesCountsNestedFilesButNotDirectoryEntries() {
        val root = Files.createTempDirectory("musikku-storage-").toFile()
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
    fun automixModelBytesCountsCacheAndLegacyCopies() {
        val cacheDir = Files.createTempDirectory("musikku-model-cache-").toFile()
        val filesDir = Files.createTempDirectory("musikku-files-").toFile()
        try {
            val modelCache = File(cacheDir, "automix_models").apply { mkdirs() }
            File(modelCache, "beat_this_final0_q8.onnx").writeBytes(ByteArray(64))
            File(filesDir, "vocals_umxhq_int8.onnx").writeBytes(ByteArray(32))
            File(filesDir, "beat_this_int8.onnx").writeBytes(ByteArray(16))

            assertEquals(112L, StorageUsage.automixModelBytes(cacheDir, filesDir))
        } finally {
            cacheDir.deleteRecursively()
            filesDir.deleteRecursively()
        }
    }

    @Test
    fun automixModelBytesReturnsZeroWhenNoModelsWereExtracted() {
        val cacheDir = Files.createTempDirectory("musikku-model-cache-").toFile()
        val filesDir = Files.createTempDirectory("musikku-files-").toFile()
        try {
            assertEquals(0L, StorageUsage.automixModelBytes(cacheDir, filesDir))
        } finally {
            cacheDir.deleteRecursively()
            filesDir.deleteRecursively()
        }
    }

    @Test
    fun fileUriBytesCountsWholeOfflinePackageForPlaylistEntry() {
        val packageDir = Files.createTempDirectory("musikku-offline-").toFile()
        try {
            File(packageDir, "playlist.m3u8").writeText("#EXTM3U")
            File(packageDir, "segment-0001.m4s").writeBytes(ByteArray(128))
            File(packageDir, "cover.jpg").writeBytes(ByteArray(64))

            assertEquals(199L, StorageUsage.fileUriBytes(File(packageDir, "playlist.m3u8").path))
        } finally {
            packageDir.deleteRecursively()
        }
    }

    @Test
    fun directoryBytesReturnsZeroForMissingPaths() {
        val root = File(Files.createTempDirectory("musikku-storage-").toFile(), "not-created")
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
