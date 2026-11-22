package com.music.bitchord.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.music.bitchord.R
import com.music.bitchord.data.model.Song
import com.music.bitchord.data.stats.ArtistFacts
import com.music.bitchord.data.stats.ListeningStats
import com.music.bitchord.data.stats.ReplayPeriod
import com.music.bitchord.data.stats.SmartPlaylistItem
import com.music.bitchord.data.stats.SmartPlaylistMatchMode
import com.music.bitchord.data.stats.SmartPlaylistRule
import com.music.bitchord.data.stats.SmartPlaylistSort
import com.music.bitchord.data.stats.SmartPlaylists
import com.music.bitchord.data.stats.buildSmartPlaylistItems

/**
 * Compact, Library-native entry to dynamic playlists. The cards are generated
 * from the existing listening aggregates; only custom rules are persisted.
 */
@Composable
fun SmartPlaylistsSection(
    onPlay: (String, List<Song>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val rules by SmartPlaylists.rules.collectAsStateWithLifecycle()
    val revision by ListeningStats.revision.collectAsStateWithLifecycle()
    val artistRevision by ArtistFacts.revision.collectAsStateWithLifecycle()
    var summary by remember { mutableStateOf<com.music.bitchord.data.stats.ReplaySummary?>(null) }
    var loading by remember { mutableStateOf(true) }
    var editorOpen by remember { mutableStateOf(false) }
    var editingRule by remember { mutableStateOf<SmartPlaylistRule?>(null) }

    LaunchedEffect(revision) {
        loading = summary == null
        summary = ListeningStats.summary(ReplayPeriod.ALL_TIME)
        loading = false
    }

    val items = remember(summary, rules, artistRevision) {
        buildSmartPlaylistItems(
            tracks = summary?.songs.orEmpty(),
            rules = rules,
            nowMs = System.currentTimeMillis(),
        )
    }

    Column(modifier = modifier.fillMaxWidth().padding(bottom = 16.dp)) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp),
        ) {
            val createPlaylist: () -> Unit = {
                editingRule = null
                editorOpen = true
            }
            val sectionHeading: @Composable () -> Unit = {
                Column {
                    Text(
                        text = stringResource(R.string.smart_playlists_title),
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onBackground,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = stringResource(R.string.smart_playlist_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (maxWidth < 400.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    sectionHeading()
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        FilledTonalButton(
                            onClick = createPlaylist,
                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(stringResource(R.string.smart_playlist_create))
                        }
                    }
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { sectionHeading() }
                    FilledTonalButton(
                        onClick = createPlaylist,
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.smart_playlist_create))
                    }
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        when {
            loading && summary == null -> {
                Text(
                    text = stringResource(R.string.smart_playlist_loading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                )
            }
            items.isEmpty() -> {
                Text(
                    text = stringResource(R.string.smart_playlist_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                )
            }
            else -> {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(items, key = SmartPlaylistItem::id) { item ->
                        val title = when (item.id) {
                            "most_played" -> stringResource(R.string.smart_playlist_most_played)
                            "recently_played" -> stringResource(R.string.smart_playlist_recently_played)
                            "most_listened" -> stringResource(R.string.smart_playlist_most_listened)
                            "forgotten_tracks" -> stringResource(R.string.smart_playlist_forgotten)
                            else -> item.title
                        }
                        SmartPlaylistCard(
                            item = item,
                            title = title,
                            onPlay = { onPlay(title, item.tracks.map { it.song }) },
                            onEdit = {
                                editingRule = item.rule
                                editorOpen = true
                            },
                        )
                    }
                }
            }
        }
    }

    if (editorOpen) {
        val current = editingRule
        var name by remember(editorOpen, current?.id) { mutableStateOf(current?.name.orEmpty()) }
        var artist by remember(editorOpen, current?.id) { mutableStateOf(current?.artistContains.orEmpty()) }
        var genre by remember(editorOpen, current?.id) { mutableStateOf(current?.genreContains.orEmpty()) }
        var yearFrom by remember(editorOpen, current?.id) { mutableStateOf(current?.releaseYearFrom?.toString().orEmpty()) }
        var yearTo by remember(editorOpen, current?.id) { mutableStateOf(current?.releaseYearTo?.toString().orEmpty()) }
        var minimumDuration by remember(editorOpen, current?.id) { mutableStateOf(current?.minimumDurationMinutes?.toString().orEmpty()) }
        var maximumDuration by remember(editorOpen, current?.id) { mutableStateOf(current?.maximumDurationMinutes?.toString().orEmpty()) }
        var lastPlayedDays by remember(editorOpen, current?.id) { mutableStateOf(current?.lastPlayedWithinDays?.toString().orEmpty()) }
        var matchMode by remember(editorOpen, current?.id) { mutableStateOf(current?.matchMode ?: SmartPlaylistMatchMode.ALL) }
        var minimumPlays by remember(editorOpen, current?.id) {
            mutableStateOf(current?.minimumPlays?.coerceIn(1, 20) ?: 1)
        }
        var sort by remember(editorOpen, current?.id) {
            mutableStateOf(current?.sort ?: SmartPlaylistSort.MOST_PLAYED)
        }
        var validationError by remember(editorOpen, current?.id) { mutableStateOf<Int?>(null) }

        AlertDialog(
            onDismissRequest = { editorOpen = false },
            title = {
                Text(
                    stringResource(
                        if (current == null) R.string.smart_playlist_create
                        else R.string.smart_playlist_edit,
                    ),
                )
            },
            text = {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 520.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    Text(
                        text = stringResource(R.string.smart_playlist_editor_description),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = name,
                        onValueChange = {
                            name = it.take(40)
                            validationError = null
                        },
                        label = { Text(stringResource(R.string.smart_playlist_name)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = artist,
                        onValueChange = { artist = it.take(80) },
                        label = { Text(stringResource(R.string.smart_playlist_artist_filter)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(value = genre, onValueChange = { genre = it.take(80) },
                        label = { Text(stringResource(R.string.smart_playlist_genre_filter)) }, singleLine = true,
                        modifier = Modifier.fillMaxWidth())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedTextField(value = yearFrom, onValueChange = { yearFrom = it.filter(Char::isDigit).take(4) },
                            label = { Text(stringResource(R.string.smart_playlist_year_from)) }, singleLine = true, modifier = Modifier.weight(1f))
                        OutlinedTextField(value = yearTo, onValueChange = { yearTo = it.filter(Char::isDigit).take(4) },
                            label = { Text(stringResource(R.string.smart_playlist_year_to)) }, singleLine = true, modifier = Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedTextField(value = minimumDuration, onValueChange = { minimumDuration = it.filter(Char::isDigit).take(4) },
                            label = { Text(stringResource(R.string.smart_playlist_min_duration)) }, singleLine = true, modifier = Modifier.weight(1f))
                        OutlinedTextField(value = maximumDuration, onValueChange = { maximumDuration = it.filter(Char::isDigit).take(4) },
                            label = { Text(stringResource(R.string.smart_playlist_max_duration)) }, singleLine = true, modifier = Modifier.weight(1f))
                    }
                    OutlinedTextField(value = lastPlayedDays, onValueChange = { lastPlayedDays = it.filter(Char::isDigit).take(4) },
                        label = { Text(stringResource(R.string.smart_playlist_last_played_days)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Text(stringResource(R.string.smart_playlist_match_mode), style = MaterialTheme.typography.titleSmall)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        TextButton(onClick = { matchMode = SmartPlaylistMatchMode.ALL }) {
                            Text((if (matchMode == SmartPlaylistMatchMode.ALL) "✓ " else "") + stringResource(R.string.smart_playlist_match_all),
                                color = if (matchMode == SmartPlaylistMatchMode.ALL) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
                        }
                        TextButton(onClick = { matchMode = SmartPlaylistMatchMode.ANY }) {
                            Text((if (matchMode == SmartPlaylistMatchMode.ANY) "✓ " else "") + stringResource(R.string.smart_playlist_match_any),
                                color = if (matchMode == SmartPlaylistMatchMode.ANY) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
                        }
                    }
                    Text(
                        text = stringResource(R.string.smart_playlist_minimum_plays_value, minimumPlays),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Slider(
                        value = minimumPlays.toFloat(),
                        onValueChange = { minimumPlays = it.toInt().coerceIn(1, 20) },
                        valueRange = 1f..20f,
                        steps = 18,
                    )
                    Text(
                        text = stringResource(R.string.smart_playlist_sort),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        SmartPlaylistSort.entries.forEach { option ->
                            val selected = sort == option
                            TextButton(
                                onClick = { sort = option },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(
                                    text = (if (selected) "✓ " else "") + when (option) {
                                        SmartPlaylistSort.MOST_PLAYED -> stringResource(R.string.smart_playlist_sort_played)
                                        SmartPlaylistSort.RECENTLY_PLAYED -> stringResource(R.string.smart_playlist_sort_recent)
                                        SmartPlaylistSort.MOST_LISTENED -> stringResource(R.string.smart_playlist_sort_listened)
                                    },
                                    color = if (selected) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurface,
                                )
                                Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                    validationError?.let { errorId ->
                        Text(text = stringResource(errorId), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error)
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = name.isNotBlank(),
                    onClick = {
                        val yearFromValue = yearFrom.toIntOrNull()
                        val yearToValue = yearTo.toIntOrNull()
                        val minimumDurationValue = minimumDuration.toIntOrNull()
                        val maximumDurationValue = maximumDuration.toIntOrNull()
                        val lastPlayedDaysValue = lastPlayedDays.toIntOrNull()
                        val valid =
                            (yearFrom.isBlank() || yearFromValue?.let { it in 1888..2100 } == true) &&
                            (yearTo.isBlank() || yearToValue?.let { it in 1888..2100 } == true) &&
                            (yearFromValue == null || yearToValue == null || yearFromValue <= yearToValue) &&
                            (minimumDuration.isBlank() || minimumDurationValue?.let { it in 1..1440 } == true) &&
                            (maximumDuration.isBlank() || maximumDurationValue?.let { it in 1..1440 } == true) &&
                            (minimumDurationValue == null || maximumDurationValue == null || minimumDurationValue <= maximumDurationValue) &&
                            (lastPlayedDays.isBlank() || lastPlayedDaysValue?.let { it in 1..3650 } == true)
                        if (!valid) { validationError = R.string.smart_playlist_invalid_filter; return@TextButton }
                        val saved = SmartPlaylists.save(SmartPlaylistRule(
                            id = current?.id.orEmpty(), name = name, artistContains = artist,
                            minimumPlays = minimumPlays, sort = sort, genreContains = genre,
                            releaseYearFrom = yearFromValue, releaseYearTo = yearToValue,
                            minimumDurationMinutes = minimumDurationValue, maximumDurationMinutes = maximumDurationValue,
                            lastPlayedWithinDays = lastPlayedDaysValue, matchMode = matchMode,
                        ))
                        if (saved != null) {
                            editingRule = saved
                            editorOpen = false
                        } else { validationError = R.string.smart_playlist_max_reached }
                    },
                ) {
                    Text(stringResource(R.string.save))
                }
            },
            dismissButton = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (current != null) {
                        TextButton(
                            onClick = {
                                SmartPlaylists.delete(current.id)
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
}

@Composable
private fun SmartPlaylistCard(
    item: SmartPlaylistItem,
    title: String,
    onPlay: () -> Unit,
    onEdit: () -> Unit,
) {
    Card(
        modifier = Modifier
            .width(184.dp)
            .clip(RoundedCornerShape(18.dp))
            .clickable(enabled = item.tracks.isNotEmpty(), onClick = onPlay),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column {
            val artwork = item.tracks.firstOrNull()?.song?.thumbnailUrl
            if (artwork != null) {
                AsyncImage(
                    model = artwork,
                    contentDescription = null,
                    modifier = Modifier.fillMaxWidth().height(92.dp),
                    contentScale = ContentScale.Crop,
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(92.dp)
                        .background(MaterialTheme.colorScheme.surface),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.AutoAwesome,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(32.dp),
                    )
                }
            }
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    if (item.tracks.isNotEmpty()) {
                        Icon(
                            imageVector = Icons.Filled.PlayArrow,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
                Text(
                    text = stringResource(R.string.smart_playlist_track_count, item.tracks.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                item.rule?.let {
                    TextButton(
                        onClick = onEdit,
                        contentPadding = PaddingValues(0.dp),
                        modifier = Modifier.align(Alignment.End),
                    ) {
                        Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(15.dp))
                        Spacer(Modifier.width(3.dp))
                        Text(stringResource(R.string.smart_playlist_edit_action))
                    }
                }
            }
        }
    }
}
