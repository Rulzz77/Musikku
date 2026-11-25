package com.music.bitchord.download

import com.music.bitchord.data.model.ArtistRef
import com.music.bitchord.data.model.Song
import kotlinx.serialization.Serializable

/**
 * Durable, versioned representation of the download manager.
 *
 * Song itself is a shared catalogue model and deliberately is not tied to
 * Android persistence. This DTO stores only stable row metadata needed to
 * render the manager and resolve the same download again after a restart.
 */
@Serializable
internal data class DownloadRecoverySnapshot(
    val schemaVersion: Int = CURRENT_SCHEMA,
    val items: List<DownloadRecoveryItem> = emptyList(),
    val seenAt: Long = 0L,
    val settledAt: Long = 0L,
) {
    companion object {
        const val CURRENT_SCHEMA = 1
        const val MAX_SETTLED_ITEMS = 200
    }
}

@Serializable
internal data class DownloadRecoveryItem(
    val videoId: String,
    val song: DownloadRecoverySong,
    val status: String,
    val fraction: Float = 0f,
    val failureReason: String? = null,
    val from: String? = null,
    val sequence: Long,
    val fromCache: Boolean = false,
)

@Serializable
internal data class DownloadRecoverySong(
    val videoId: String,
    val title: String,
    val artist: String,
    val thumbnailUrl: String? = null,
    val durationText: String? = null,
    val artistId: String? = null,
    val artists: List<DownloadRecoveryArtist> = emptyList(),
    val albumId: String? = null,
    val albumName: String? = null,
    val isVideo: Boolean = false,
    val isVideoOrigin: Boolean = isVideo,
    val sourceQuality: String? = null,
    val sourceHiRes: Boolean = false,
    val isExplicit: Boolean? = null,
    val localUri: String? = null,
    val localPath: String? = null,
    val downloadFormat: String? = null,
    val isPodcastEpisode: Boolean = false,
)

@Serializable
internal data class DownloadRecoveryArtist(
    val name: String,
    val browseId: String? = null,
)

/**
 * Convert the live manager into its durable snapshot.
 *
 * All unsettled rows are retained regardless of queue length. Only the latest
 * [DownloadRecoverySnapshot.MAX_SETTLED_ITEMS] completed/failed rows are kept,
 * so a long-running app does not grow its preferences forever.
 */
internal fun DownloadSession.State.toRecoverySnapshot(): DownloadRecoverySnapshot {
    val recoverable = items.filter { it.recoverable }
    val unsettled = recoverable.filterNot { it.progress.settled }
    val settled = recoverable.filter { it.progress.settled }
        .sortedBy { it.sequence }
        .takeLast(DownloadRecoverySnapshot.MAX_SETTLED_ITEMS)
    val kept = (unsettled + settled).sortedBy { it.sequence }

    return DownloadRecoverySnapshot(
        items = kept.map { item ->
            val (status, fraction, reason) = when (val progress = item.progress) {
                DownloadProgress.Queued -> Triple("queued", 0f, null)
                is DownloadProgress.Running -> Triple("running", progress.fraction, null)
                DownloadProgress.Done -> Triple("done", 1f, null)
                is DownloadProgress.Failed -> Triple("failed", 1f, progress.reason)
            }
            DownloadRecoveryItem(
                videoId = item.videoId,
                song = item.song.toRecoverySong(),
                status = status,
                fraction = fraction,
                failureReason = reason,
                from = item.from,
                sequence = item.sequence,
                fromCache = item.fromCache,
            )
        },
        seenAt = seenAt,
        settledAt = settledAt,
    )
}

/**
 * Restore a saved manager snapshot.
 *
 * A Running row is intentionally converted to Queued: destinations are
 * created as pending/.part files and are not byte-resumable. The next attempt
 * resolves a fresh stream and starts the track from byte zero; completed files
 * are adopted by the normal duplicate-file check.
 */
internal fun DownloadRecoverySnapshot.toDownloadSessionState(): DownloadSession.State {
    if (schemaVersion != DownloadRecoverySnapshot.CURRENT_SCHEMA) {
        return DownloadSession.State()
    }
    val restored = items.mapNotNull { item ->
        if (item.videoId.isBlank() || item.song.videoId.isBlank()) return@mapNotNull null
        val progress = when (item.status) {
            "queued", "running" -> DownloadProgress.Queued
            "done" -> DownloadProgress.Done
            "failed" -> DownloadProgress.Failed(
                item.failureReason?.takeIf { it.isNotBlank() } ?: "Download failed — try again",
            )
            else -> return@mapNotNull null
        }
        DownloadSession.Item(
            videoId = item.videoId,
            song = item.song.toSong(),
            progress = progress,
            from = item.from,
            sequence = item.sequence,
            recoverable = true,
            fromCache = item.fromCache,
        )
    }.sortedBy { it.sequence }

    return DownloadSession.State(
        items = restored,
        seenAt = seenAt,
        settledAt = settledAt,
    )
}

private fun Song.toRecoverySong() = DownloadRecoverySong(
    videoId = videoId,
    title = title,
    artist = artist,
    thumbnailUrl = thumbnailUrl,
    durationText = durationText,
    artistId = artistId,
    artists = artists.map { DownloadRecoveryArtist(it.name, it.browseId) },
    albumId = albumId,
    albumName = albumName,
    isVideo = isVideo,
    isVideoOrigin = isVideoOrigin,
    sourceQuality = sourceQuality,
    sourceHiRes = sourceHiRes,
    isExplicit = isExplicit,
    localUri = localUri,
    localPath = localPath,
    downloadFormat = downloadFormat,
    isPodcastEpisode = isPodcastEpisode,
)

private fun DownloadRecoverySong.toSong() = Song(
    videoId = videoId,
    title = title,
    artist = artist,
    thumbnailUrl = thumbnailUrl,
    durationText = durationText,
    artistId = artistId,
    artists = artists.map { ArtistRef(it.name, it.browseId) },
    albumId = albumId,
    albumName = albumName,
    isVideo = isVideo,
    isVideoOrigin = isVideoOrigin,
    sourceQuality = sourceQuality,
    sourceHiRes = sourceHiRes,
    isExplicit = isExplicit,
    localUri = localUri,
    localPath = localPath,
    downloadFormat = downloadFormat,
    isPodcastEpisode = isPodcastEpisode,
)
