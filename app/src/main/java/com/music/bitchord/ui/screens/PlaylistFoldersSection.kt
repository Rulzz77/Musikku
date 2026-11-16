package com.music.bitchord.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.music.bitchord.R
import com.music.bitchord.data.PlaylistFolder
import com.music.bitchord.data.model.HomeShelf
import com.music.bitchord.data.model.ShelfItem

/**
 * The phone Library's personal playlist folders.
 *
 * A folder contains browse-id references to playlists from any source. This
 * composable only edits those references; it never edits playlist contents.
 */
@Composable
fun PlaylistFoldersSection(
    folders: List<PlaylistFolder>,
    playlists: List<ShelfItem>,
    onSave: (String?, String, Set<String>) -> Unit,
    onDelete: (String) -> Unit,
    onOpen: (HomeShelf) -> Unit,
    modifier: Modifier = Modifier,
) {
    var editorOpen by remember { mutableStateOf(false) }
    var editingFolder by remember { mutableStateOf<PlaylistFolder?>(null) }
    var deletingFolder by remember { mutableStateOf<PlaylistFolder?>(null) }

    Column(modifier = modifier.fillMaxWidth().padding(bottom = 18.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringResource(R.string.playlist_folders_title),
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Spacer(Modifier.weight(1f))
            TextButton(
                onClick = {
                    editingFolder = null
                    editorOpen = true
                },
            ) {
                Icon(Icons.Rounded.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.create_playlist_folder))
            }
        }

        if (folders.isNotEmpty()) {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                folders.forEach { folder ->
                    val availableItems = playlists.filter { it.browseId in folder.playlistBrowseIds }
                    Card(
                        modifier = Modifier.width(208.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    if (availableItems.isNotEmpty()) {
                                        onOpen(HomeShelf(folder.title, availableItems))
                                    } else {
                                        editingFolder = folder
                                        editorOpen = true
                                    }
                                }
                                .padding(14.dp),
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Rounded.Folder,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(24.dp),
                                )
                                Spacer(Modifier.width(10.dp))
                                Text(
                                    text = folder.title,
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            Text(
                                text = stringResource(R.string.playlist_folder_count, folder.playlistBrowseIds.size),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(start = 34.dp, top = 4.dp),
                            )
                            TextButton(
                                onClick = {
                                    editingFolder = folder
                                    editorOpen = true
                                },
                                modifier = Modifier.align(Alignment.End),
                            ) {
                                Text(stringResource(R.string.edit_playlist_folder))
                            }
                        }
                    }
                }
            }
        }
    }

    if (editorOpen) {
        val currentFolder = editingFolder
        var title by remember(currentFolder?.id, editorOpen) {
            mutableStateOf(currentFolder?.title.orEmpty())
        }
        var selected by remember(currentFolder?.id, editorOpen) {
            mutableStateOf(currentFolder?.playlistBrowseIds.orEmpty().toSet())
        }
        val availableIds = playlists.mapNotNull { it.browseId }.toSet()
        val unavailableIds = selected - availableIds

        AlertDialog(
            onDismissRequest = { editorOpen = false },
            title = {
                Text(
                    stringResource(
                        if (currentFolder == null) R.string.create_playlist_folder
                        else R.string.edit_playlist_folder,
                    ),
                )
            },
            text = {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 520.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = title,
                        onValueChange = { title = it },
                        label = { Text(stringResource(R.string.playlist_folder_name)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        text = stringResource(R.string.playlist_folder_select_playlists),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Text(
                        text = stringResource(R.string.playlist_folder_move_notice),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (playlists.isEmpty()) {
                        Text(
                            text = stringResource(R.string.playlist_folder_no_playlists),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        playlists.forEach { playlist ->
                            val id = playlist.browseId ?: return@forEach
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        selected = if (id in selected) selected - id else selected + id
                                    }
                                    .padding(vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(
                                    checked = id in selected,
                                    onCheckedChange = { checked ->
                                        selected = if (checked) selected + id else selected - id
                                    },
                                )
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        text = playlist.title,
                                        style = MaterialTheme.typography.bodyMedium,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    if (playlist.subtitle.isNotBlank()) {
                                        Text(
                                            text = playlist.subtitle,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                }
                            }
                        }
                    }
                    if (unavailableIds.isNotEmpty()) {
                        Text(
                            text = stringResource(R.string.playlist_folder_empty) + " (${unavailableIds.size})",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = title.isNotBlank(),
                    onClick = {
                        onSave(currentFolder?.id, title, selected)
                        editorOpen = false
                    },
                ) {
                    Text(stringResource(R.string.save))
                }
            },
            dismissButton = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (currentFolder != null) {
                        TextButton(
                            onClick = {
                                deletingFolder = currentFolder
                                editorOpen = false
                            },
                        ) {
                            Text(stringResource(R.string.delete))
                        }
                    }
                    TextButton(onClick = { editorOpen = false }) {
                        Text(stringResource(R.string.cancel))
                    }
                }
            },
        )
    }

    deletingFolder?.let { folder ->
        AlertDialog(
            onDismissRequest = { deletingFolder = null },
            title = { Text(stringResource(R.string.delete) + " — " + folder.title) },
            text = { Text(stringResource(R.string.playlist_folder_delete_notice)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDelete(folder.id)
                        deletingFolder = null
                    },
                ) {
                    Text(stringResource(R.string.delete))
                }
            },
            dismissButton = {
                TextButton(onClick = { deletingFolder = null }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }
}
