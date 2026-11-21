package com.music.bitchord.data.storage

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.music.bitchord.data.canvas.CanvasCache
import com.music.bitchord.download.Downloads
import com.music.bitchord.playback.AudioCache
import com.music.bitchord.playback.smart.AUTOMIX_MODEL_ASSET_NAMES
import com.music.bitchord.playback.smart.AUTOMIX_MODEL_CACHE_DIRECTORY
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

/**
 * A read-only view of storage the app manages directly.
 *
 * Downloaded files and their sidecar artwork are durable user data. Audio
 * cache is kept separately because complete entries can be played offline;
 * image and Canvas caches are disposable and can be fetched again.
 *
 * Local music selected through the document picker, playlists, backups and
 * other app databases are deliberately outside this report and are never
 * touched by its cleanup actions.
 */
object StorageUsage {

    data class Snapshot(
        val downloadedBytes: Long,
        val audioCacheBytes: Long,
        val imageCacheBytes: Long,
        val canvasCacheBytes: Long,
        val automixModelBytes: Long,
        val availableBytes: Long,
        val totalDeviceBytes: Long,
    ) {
        val managedBytes: Long
            get() = downloadedBytes + audioCacheBytes + imageCacheBytes + canvasCacheBytes + automixModelBytes
    }

    suspend fun inspect(context: Context): Snapshot = withContext(Dispatchers.IO) {
        val app = context.applicationContext

        // The same content URI can be recorded for more than one catalogue id.
        // Count the underlying file once, not once per alias.
        val savedUris = Downloads.saved.value.values.distinct()
        val savedBytes = savedUris.sumOf { savedUriBytes(app, it) }

        // Count durable artwork sidecars from the metadata of saved downloads.
        // HLS/DASH packages may already contain the same cover, so skip artwork
        // paths covered by one of the package directories counted above.
        val savedRoots = savedUris.mapNotNull(::savedFileRoot).toSet()
        val artworkPaths = Downloads.savedMetadata.value.values
            .asSequence()
            .mapNotNull { metadata -> metadata.thumbnailUrl?.takeIf { it.startsWith("file://") } }
            .mapNotNull { raw -> runCatching { Uri.parse(raw).path }.getOrNull() }
            .distinct()
            .filterNot { path -> savedRoots.any { root -> isInside(File(path), root) } }
        val savedArtworkBytes = artworkPaths.sumOf { path -> directoryBytes(File(path)) }

        Snapshot(
            downloadedBytes = savedBytes + savedArtworkBytes,
            audioCacheBytes = directoryBytes(AudioCache.storageDirectory(app)),
            imageCacheBytes = directoryBytes(File(app.cacheDir, IMAGE_CACHE_DIRECTORY)),
            canvasCacheBytes = directoryBytes(CanvasCache.storageDirectory(app)),
            automixModelBytes = automixModelBytes(app.cacheDir, app.filesDir),
            availableBytes = app.filesDir.usableSpace.coerceAtLeast(0L),
            totalDeviceBytes = app.filesDir.totalSpace.coerceAtLeast(0L),
        )
    }

    private fun savedFileRoot(rawUri: String): File? {
        val uri = runCatching { Uri.parse(rawUri) }.getOrNull() ?: return null
        if (uri.scheme != "file") return null
        val target = uri.path?.let(::File) ?: return null
        return if (target.name == OFFLINE_PLAYLIST_FILE) target.parentFile ?: target else target
    }

    private fun isInside(file: File, root: File): Boolean {
        val filePath = runCatching { file.canonicalPath }.getOrElse { file.absolutePath }
        val rootPath = runCatching { root.canonicalPath }.getOrElse { root.absolutePath }
        return filePath == rootPath || filePath.startsWith(rootPath.trimEnd(File.separatorChar) + File.separator)
    }

    private fun savedUriBytes(context: Context, rawUri: String): Long {
        val uri = runCatching { Uri.parse(rawUri) }.getOrNull() ?: return 0L
        if (uri.scheme == "file") {
            return fileUriBytes(uri.path)
        }
        if (uri.scheme != "content") return 0L

        val indexedSize = runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val column = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (column < 0 || cursor.isNull(column)) null else cursor.getLong(column)
            }
        }.getOrNull()
        if (indexedSize != null && indexedSize >= 0L) return indexedSize

        // Some content providers do not expose OpenableColumns.SIZE. An asset
        // descriptor can still give the length without reading audio data into RAM.
        return runCatching {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length }
        }.getOrNull()?.coerceAtLeast(0L) ?: 0L
    }

    /**
     * Offline HLS/DASH downloads are directories whose public entry point is
     * playlist.m3u8. Count every segment and sidecar in that package rather
     * than reporting only the small manifest file.
     */
    internal fun fileUriBytes(path: String?): Long {
        if (path.isNullOrBlank()) return 0L
        val target = File(path)
        val root = if (target.name == OFFLINE_PLAYLIST_FILE) target.parentFile ?: target else target
        return directoryBytes(root)
    }

    /**
     * Counts the disposable model copies used by Automix, including files left
     * in filesDir by versions before they were moved to cacheDir.
     */
    internal fun automixModelBytes(cacheDir: File, filesDir: File): Long {
        val cached = directoryBytes(File(cacheDir, AUTOMIX_MODEL_CACHE_DIRECTORY))
        val legacy = AUTOMIX_MODEL_ASSET_NAMES.sumOf { name ->
            File(filesDir, name).takeIf(File::isFile)?.length()?.coerceAtLeast(0L) ?: 0L
        }
        return if (Long.MAX_VALUE - cached < legacy) Long.MAX_VALUE else cached + legacy
    }

    internal fun directoryBytes(root: File): Long {
        if (!root.exists()) return 0L
        if (root.isFile) return root.length().coerceAtLeast(0L)
        var total = 0L
        root.walkTopDown().forEach { file ->
            if (file.isFile) {
                val size = file.length().coerceAtLeast(0L)
                total = if (Long.MAX_VALUE - total < size) Long.MAX_VALUE else total + size
            }
        }
        return total
    }

    fun formatBytes(bytes: Long): String {
        val safe = bytes.coerceAtLeast(0L)
        if (safe < 1024L) return "$safe B"
        val units = arrayOf("KB", "MB", "GB", "TB")
        var amount = safe.toDouble()
        var unit = -1
        do {
            amount /= 1024.0
            unit++
        } while (amount >= 1024.0 && unit < units.lastIndex)
        return String.format(Locale.ROOT, "%.1f %s", amount, units[unit])
    }

    private const val IMAGE_CACHE_DIRECTORY = "image_cache"
    private const val OFFLINE_PLAYLIST_FILE = "playlist.m3u8"
}
