package com.music.bitchord.data.storage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    fun bundledAutomixModelsMatchPinnedGitBlobDigests() {
        val moduleAssets = File("src/main/assets")
        val projectAssets = File("app/src/main/assets")
        val assets = if (moduleAssets.isDirectory) moduleAssets else projectAssets
        assertTrue("Bundled app/src/main/assets directory must exist", assets.isDirectory)

        com.music.bitchord.playback.smart.AUTOMIX_MODEL_INTEGRITY.forEach { (name, integrity) ->
            assertTrue(
                "Bundled model must match its pinned size and Git blob digest: $name",
                com.music.bitchord.playback.smart.isValidAutomixModelCopy(File(assets, name), integrity),
            )
        }
    }

    @Test
    fun migrateLegacyAutomixModelsMovesOnlyVerifiedAssetsToCache() {
        val filesDir = Files.createTempDirectory("musikku-files-").toFile()
        val cacheDir = Files.createTempDirectory("musikku-cache-").toFile()
        try {
            val beat = File(filesDir, "beat_this_final0_q8.onnx").apply { writeBytes(ByteArray(64) { 1 }) }
            val vocals = File(filesDir, "vocals_umxhq_int8.onnx").apply { writeBytes(ByteArray(32) { 2 }) }
            val retired = File(filesDir, "beat_this_int8.onnx").apply { writeBytes(ByteArray(16)) }
            val interruptedCopy = File(cacheDir, "automix_models/.vocals_umxhq_int8.onnx.tmp").apply {
                parentFile?.mkdirs()
                writeBytes(ByteArray(12))
            }
            val unrelated = File(filesDir, "user-data.bin").apply { writeBytes(ByteArray(8)) }
            val expected = mapOf(
                beat.name to com.music.bitchord.playback.smart.AutomixModelIntegrity(
                    beat.length(),
                    com.music.bitchord.playback.smart.automixModelGitBlobSha1(beat),
                ),
                vocals.name to com.music.bitchord.playback.smart.AutomixModelIntegrity(
                    vocals.length(),
                    com.music.bitchord.playback.smart.automixModelGitBlobSha1(vocals),
                ),
            )

            com.music.bitchord.playback.smart.migrateLegacyAutomixModelCache(filesDir, cacheDir, expected)

            val modelCache = File(cacheDir, "automix_models")
            assertTrue(com.music.bitchord.playback.smart.isValidAutomixModelCopy(File(modelCache, beat.name), expected.getValue(beat.name)))
            assertTrue(com.music.bitchord.playback.smart.isValidAutomixModelCopy(File(modelCache, vocals.name), expected.getValue(vocals.name)))
            assertFalse(beat.exists())
            assertFalse(vocals.exists())
            assertFalse(retired.exists())
            assertFalse(interruptedCopy.exists())
            assertTrue(unrelated.exists())
        } finally {
            filesDir.deleteRecursively()
            cacheDir.deleteRecursively()
        }
    }

    @Test
    fun migrateLegacyAutomixModelsReplacesSameLengthCorruptCacheAndDiscardsTruncatedLegacy() {
        val filesDir = Files.createTempDirectory("musikku-files-").toFile()
        val cacheDir = Files.createTempDirectory("musikku-cache-").toFile()
        try {
            val beat = File(filesDir, "beat_this_final0_q8.onnx").apply { writeBytes(ByteArray(64) { 7 }) }
            val corruptedBeatCache = File(cacheDir, "automix_models/beat_this_final0_q8.onnx").apply {
                parentFile?.mkdirs()
                writeBytes(ByteArray(64) { 9 })
            }
            val truncatedVocal = File(filesDir, "vocals_umxhq_int8.onnx").apply { writeBytes(ByteArray(9)) }
            val expected = mapOf(
                beat.name to com.music.bitchord.playback.smart.AutomixModelIntegrity(
                    beat.length(),
                    com.music.bitchord.playback.smart.automixModelGitBlobSha1(beat),
                ),
                truncatedVocal.name to com.music.bitchord.playback.smart.AutomixModelIntegrity(
                    32L,
                    "0000000000000000000000000000000000000000",
                ),
            )

            assertFalse(com.music.bitchord.playback.smart.isValidAutomixModelCopy(corruptedBeatCache, expected.getValue(beat.name)))
            com.music.bitchord.playback.smart.migrateLegacyAutomixModelCache(filesDir, cacheDir, expected)

            val recoveredBeat = File(cacheDir, "automix_models/" + beat.name)
            assertTrue(com.music.bitchord.playback.smart.isValidAutomixModelCopy(recoveredBeat, expected.getValue(beat.name)))
            assertFalse(beat.exists())
            assertFalse(truncatedVocal.exists())
            assertFalse(File(cacheDir, "automix_models/" + truncatedVocal.name).exists())
        } finally {
            filesDir.deleteRecursively()
            cacheDir.deleteRecursively()
        }
    }

    @Test
    fun automixModelIntegrityRejectsFilesWithMatchingLengthButDifferentContent() {
        val root = Files.createTempDirectory("musikku-model-integrity-").toFile()
        try {
            val file = File(root, "model.onnx").apply { writeBytes(ByteArray(96) { 4 }) }
            val integrity = com.music.bitchord.playback.smart.AutomixModelIntegrity(
                file.length(),
                com.music.bitchord.playback.smart.automixModelGitBlobSha1(file),
            )
            assertTrue(com.music.bitchord.playback.smart.isValidAutomixModelCopy(file, integrity))

            val originalModifiedAt = file.lastModified()
            file.writeBytes(ByteArray(96) { 5 })
            // Keep the same length but advance the timestamp deterministically,
            // including on filesystems with coarse timestamp resolution.
            assertTrue(file.setLastModified(originalModifiedAt + 2_000L))
            assertFalse(com.music.bitchord.playback.smart.isValidAutomixModelCopy(file, integrity))
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
