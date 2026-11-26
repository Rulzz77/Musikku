package com.music.bitchord

import android.content.Context
import com.music.bitchord.data.OfflinePlaylist
import com.music.bitchord.data.YtMusicRepository
import com.music.bitchord.data.PlaylistFolder
import com.music.bitchord.data.model.HomeShelf
import com.music.bitchord.data.model.LibraryPage
import com.music.bitchord.data.model.ShelfItem
import com.music.bitchord.data.model.UiState
import com.music.bitchord.data.model.withoutVideos
import com.music.bitchord.data.spotify.LocalPlaylist

/**
 * Builds device-owned playlist cards outside BitChordApp's already-large
 * Compose body. Callers keep these projections in remember() so playback
 * state changes do not rescan every playlist and its artwork.
 */
internal fun localPlaylistShelfItems(
    playlists: List<LocalPlaylist>,
    context: Context,
): List<ShelfItem> = playlists.map { playlist ->
    ShelfItem(
        title = playlist.title,
        subtitle = context.getString(R.string.local_playlist_subtitle, playlist.songs.size),
        thumbnailUrl = playlist.coverUrl
            ?: playlist.songs.firstOrNull { !it.thumbnailUrl.isNullOrBlank() }?.thumbnailUrl,
        videoId = null,
        browseId = playlist.browseId,
    )
}

internal fun offlinePlaylistShelfItems(
    playlists: List<OfflinePlaylist>,
    context: Context,
): List<ShelfItem> = playlists.map { playlist ->
    ShelfItem(
        title = playlist.title,
        subtitle = context.getString(R.string.local_playlist_subtitle, playlist.songs.size),
        thumbnailUrl = playlist.coverUrl
            ?: playlist.songs.firstOrNull { !it.thumbnailUrl.isNullOrBlank() }?.thumbnailUrl,
        videoId = null,
        browseId = playlist.browseId,
    )
}

internal fun accountPlaylistShelfItems(
    libraryState: UiState<LibraryPage>,
    playlistShelfTitle: String,
): List<ShelfItem> =
    (libraryState as? UiState.Success)
        ?.data?.shelves
        ?.firstOrNull { it.title == playlistShelfTitle }
        ?.items.orEmpty()

internal fun folderablePlaylistShelfItems(
    accountItems: List<ShelfItem>,
    localItems: List<ShelfItem>,
    offlineItems: List<ShelfItem>,
): List<ShelfItem> =
    (accountItems + localItems + offlineItems)
        .filter { it.browseId != null }
        .distinctBy { it.browseId }

internal fun folderedPlaylistIds(folders: List<PlaylistFolder>): Set<String> =
    folders.flatMapTo(HashSet()) { it.playlistBrowseIds }

/** Keeps playlist folder membership out of the account's underlying source data. */
internal fun libraryWithoutFolderedPlaylists(
    libraryState: UiState<LibraryPage>,
    folderedBrowseIds: Set<String>,
): UiState<LibraryPage> =
    when (val current = libraryState) {
        is UiState.Success -> current.copy(
            data = current.data.copy(
                shelves = current.data.shelves.mapNotNull { shelf ->
                    if (shelf.title != YtMusicRepository.PLAYLISTS_SHELF) {
                        shelf
                    } else {
                        shelf.copy(
                            items = shelf.items.filter { item ->
                                item.browseId == null || item.browseId !in folderedBrowseIds
                            },
                        ).takeIf { it.items.isNotEmpty() }
                    }
                },
            ),
        )
        else -> libraryState
    }

internal fun unfolderedHomePlaylistShelfItems(
    offlineItems: List<ShelfItem>,
    folderedBrowseIds: Set<String>,
): List<ShelfItem> =
    offlineItems.filter { item ->
        item.browseId == null || item.browseId !in folderedBrowseIds
    }

internal fun homePlaylistShelves(
    context: Context,
    playlistItems: List<ShelfItem>,
): List<HomeShelf> =
    if (playlistItems.isEmpty()) {
        emptyList()
    } else {
        listOf(HomeShelf(context.getString(R.string.your_playlists), playlistItems))
    }

internal fun visibleHomeShelves(
    homeState: UiState<List<HomeShelf>>,
    hideHomeVideos: Boolean,
    hideRecents: Boolean,
): UiState<List<HomeShelf>> {
    val loaded = homeState as? UiState.Success ?: return homeState
    if (!hideHomeVideos && !hideRecents) return homeState

    var shelves = loaded.data
    if (hideRecents) shelves = shelves.filterNot { it.title == YtMusicRepository.RECENT_TITLE }
    if (hideHomeVideos) shelves = shelves.withoutVideos()
    return UiState.Success(shelves)
}
