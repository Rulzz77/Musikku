package com.music.bitchord.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.music.bitchord.R
import com.music.bitchord.data.model.PlaylistPrivacy
import com.music.bitchord.data.model.Song
import com.music.bitchord.data.spotify.SpotifyImportTrack
import com.music.bitchord.data.spotify.SpotifyImporter
import coil3.compose.AsyncImage
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.materials.ExperimentalHazeMaterialsApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private val IMPORT_LANGUAGES = listOf(
    "Tamil",
    "Telugu",
    "Kannada",
    "Malayalam",
    "Hindi",
    "English",
    "Multilingual",
    "No Preference",
    "Manual / Other",
)

/**
 * Paste a Spotify playlist link, match its songs on YouTube Music, keep the result.
 *
 * The same frosted card as the addon editor, rather than a Material dialog.
 * The "who can see it" row exists only for [signedIn]: it is a YouTube Music
 * setting, and a playlist kept on this device has no audience to choose.
 * Unmatched tracks remain retryable and can be manually resolved from
 * YouTube Music search before the import is confirmed.
 */
@OptIn(ExperimentalHazeMaterialsApi::class)
@Composable
fun SpotifyImportAlert(
    hazeState: HazeState,
    signedIn: Boolean,
    /** Called once the songs are matched; [privacy] is meaningful only when signed in. */
    onImported: (title: String, privacy: PlaylistPrivacy, songs: List<Song>) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var link by remember { mutableStateOf("") }
    var privacy by remember { mutableStateOf(PlaylistPrivacy.PRIVATE) }
    var selectedLanguage by remember { mutableStateOf("No Preference") }
    var customLanguageInput by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    var unmatched by remember { mutableStateOf<List<SpotifyImportTrack>?>(null) }
    var importTitle by remember { mutableStateOf<String?>(null) }
    var resolvedSongs by remember { mutableStateOf<List<Song>>(emptyList()) }
    var submitted by remember { mutableStateOf(false) }
    var editingTrack by remember { mutableStateOf<SpotifyImportTrack?>(null) }
    var manualQuery by remember { mutableStateOf("") }
    var manualCandidates by remember { mutableStateOf<List<Song>>(emptyList()) }
    var manualSearching by remember { mutableStateOf(false) }
    var manualError by remember { mutableStateOf<String?>(null) }

    fun effectiveLanguage(): String? = if (selectedLanguage == "Manual / Other") {
        customLanguageInput.trim().ifBlank { null }
    } else selectedLanguage

    fun finishImport() {
        val title = importTitle ?: return
        if (submitted || resolvedSongs.isEmpty()) return
        submitted = true
        onImported(title, privacy, resolvedSongs)
        onDismiss()
    }

    fun closeManualSearch() {
        editingTrack = null
        manualCandidates = emptyList()
        manualError = null
        manualQuery = ""
        manualSearching = false
    }

    fun openManualSearch(track: SpotifyImportTrack) {
        editingTrack = track
        manualQuery = SpotifyImporter.replacementSearchQuery(track)
        manualCandidates = emptyList()
        manualError = null
    }

    fun searchManualCandidates() {
        val requestedTrack = editingTrack ?: return
        val requestedQuery = manualQuery.trim()
        if (requestedQuery.isBlank() || manualSearching) return
        manualSearching = true
        manualError = null
        manualCandidates = emptyList()
        scope.launch {
            try {
                val results = SpotifyImporter.searchReplacementCandidates(requestedQuery)
                if (editingTrack == requestedTrack && manualQuery.trim() == requestedQuery) {
                    manualCandidates = results
                    if (results.isEmpty()) manualError = "Tidak ada kandidat. Coba ubah kata kunci."
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                if (editingTrack == requestedTrack) {
                    manualError = failure.message ?: "Pencarian gagal. Coba lagi."
                }
            } finally {
                if (editingTrack == requestedTrack) manualSearching = false
            }
        }
    }

    fun chooseManualCandidate(track: SpotifyImportTrack, candidate: Song) {
        val remaining = unmatched.orEmpty().toMutableList()
        val sourceIndex = remaining.indexOf(track)
        if (sourceIndex >= 0) remaining.removeAt(sourceIndex)
        unmatched = remaining

        val alreadyAdded = resolvedSongs.any { it.videoId == candidate.videoId }
        if (!alreadyAdded && candidate.videoId.isNotBlank()) {
            resolvedSongs = resolvedSongs + candidate
        }
        // A deliberate user selection is a trusted positive mapping for
        // subsequent playlists containing this same Spotify track ID.
        SpotifyImporter.rememberManualMatch(track, candidate, effectiveLanguage())
        closeManualSearch()
        if (remaining.isEmpty()) finishImport()
    }

    fun retryMissing() {
        val missed = unmatched.orEmpty()
        if (missed.isEmpty() || working) return
        working = true
        failed = false
        status = context.getString(R.string.spotify_import_matching, 0, missed.size)
        scope.launch {
            try {
                val (newSongs, stillMissing) = SpotifyImporter.resolveToSongs(missed, effectiveLanguage()) { done, total ->
                    status = context.getString(R.string.spotify_import_matching, done, total)
                }
                val knownIds = resolvedSongs.mapNotNullTo(HashSet()) { it.videoId.takeIf(String::isNotBlank) }
                val uniqueSongs = newSongs.filter { song ->
                    song.videoId.isNotBlank() && knownIds.add(song.videoId)
                }
                resolvedSongs = resolvedSongs + uniqueSongs
                unmatched = stillMissing
                if (stillMissing.isEmpty()) finishImport()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                status = context.getString(R.string.spotify_import_failed, e.message.orEmpty())
                failed = true
            } finally {
                working = false
            }
        }
    }

    fun start() {
        val id = SpotifyImporter.extractPlaylistId(link)
        if (id == null) {
            status = context.getString(R.string.spotify_import_invalid)
            failed = true
            return
        }
        working = true
        failed = false
        status = context.getString(R.string.spotify_import_fetching)
        scope.launch {
            try {
                val (name, tracks) = SpotifyImporter.fetchPlaylistTracks(id)
                val (songs, missed) = SpotifyImporter.resolveToSongs(tracks, effectiveLanguage()) { done, total ->
                    status = context.getString(R.string.spotify_import_matching, done, total)
                }
                if (songs.isEmpty() && missed.isEmpty()) error(context.getString(R.string.spotify_import_none))
                importTitle = name
                resolvedSongs = songs
                unmatched = missed
                if (missed.isEmpty()) finishImport()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                status = context.getString(R.string.spotify_import_failed, e.message.orEmpty())
                failed = true
            }
            working = false
        }
    }

    AlertScaffold(hazeState = hazeState, onDismiss = {
        if (!working) {
            if (unmatched != null && resolvedSongs.isNotEmpty()) finishImport() else onDismiss()
        }
    }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 520.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 19.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = stringResource(R.string.spotify_import_title),
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 17.sp, fontWeight = FontWeight.W600),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
            )
            val missed = unmatched
            if (missed != null) {
                Text(
                    text = if ((working || failed) && status != null) status.orEmpty()
                    else stringResource(R.string.spotify_import_unmatched, missed.size),
                    modifier = Modifier.padding(top = 4.dp, bottom = 10.dp),
                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 13.sp, lineHeight = 17.sp),
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                )
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 200.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    missed.forEach { track ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(
                                    text = track.title,
                                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                if (track.artist.isNotBlank()) {
                                    Text(
                                        text = track.artist,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                            TextButton(
                                onClick = { openManualSearch(track) },
                                enabled = !working,
                            ) {
                                Text("Cari")
                            }
                        }
                    }
                }
            } else {
                Text(
                    text = status ?: stringResource(
                        if (signedIn) R.string.spotify_import_description
                        else R.string.spotify_import_description_local,
                    ),
                    modifier = Modifier.padding(top = 4.dp, bottom = 14.dp),
                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 13.sp, lineHeight = 17.sp),
                    color = when {
                        status == null -> MaterialTheme.colorScheme.onSurface
                        failed -> MaterialTheme.colorScheme.error
                        else -> MaterialTheme.colorScheme.primary
                    },
                    textAlign = TextAlign.Center,
                )
                PillTextField(
                    value = link,
                    onValueChange = {
                        link = it
                        if (failed) {
                            status = null
                            failed = false
                        }
                    },
                    placeholder = stringResource(R.string.spotify_import_hint),
                    enabled = !working,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { if (link.isNotBlank() && !working) start() }),
                )
                Text(
                    text = stringResource(R.string.spotify_import_language_preference),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 14.dp, bottom = 6.dp),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    IMPORT_LANGUAGES.forEach { lang ->
                        val selected = lang == selectedLanguage
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(percent = 50))
                                .background(
                                    if (selected) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.surfaceVariant,
                                )
                                .clickable(enabled = !working) {
                                    selectedLanguage = lang
                                }
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = lang,
                                style = MaterialTheme.typography.labelLarge.copy(fontSize = 11.sp),
                                color = if (selected) MaterialTheme.colorScheme.onPrimary
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                if (selectedLanguage == "Manual / Other") {
                    Spacer(Modifier.height(8.dp))
                    PillTextField(
                        value = customLanguageInput,
                        onValueChange = { customLanguageInput = it },
                        placeholder = stringResource(R.string.spotify_import_language_hint),
                        enabled = !working,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text, imeAction = ImeAction.Done),
                    )
                }
                if (signedIn) {
                    Text(
                        text = stringResource(R.string.who_can_see_it),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 14.dp, bottom = 6.dp),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        PlaylistPrivacy.entries.forEach { option ->
                            val selected = option == privacy
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(percent = 50))
                                    .background(
                                        if (selected) MaterialTheme.colorScheme.primary
                                        else MaterialTheme.colorScheme.surfaceVariant,
                                    )
                                    .clickable(enabled = !working) { privacy = option }
                                    .padding(vertical = 7.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    text = option.label,
                                    style = MaterialTheme.typography.labelLarge.copy(fontSize = 12.sp),
                                    color = if (selected) MaterialTheme.colorScheme.onPrimary
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
        AlertRule()
        if (unmatched != null) {
            AlertAction(
                label = "Retry missing tracks",
                emphasised = false,
                onClick = ::retryMissing,
                enabled = !working && unmatched.orEmpty().isNotEmpty(),
            )
            AlertRule()
            AlertAction(
                label = "Import matched tracks",
                emphasised = true,
                onClick = ::finishImport,
                enabled = !working && resolvedSongs.isNotEmpty(),
            )
        } else {
            AlertAction(
                label = stringResource(R.string.spotify_import_button),
                emphasised = true,
                onClick = ::start,
                enabled = link.isNotBlank() && !working,
            )
            AlertRule()
            AlertAction(
                label = stringResource(R.string.cancel),
                emphasised = false,
                onClick = onDismiss,
                enabled = !working,
            )
        }
    }

    editingTrack?.let { track ->
        AlertDialog(
            onDismissRequest = { if (!manualSearching) closeManualSearch() },
            title = { Text("Cari pengganti lagu") },
            text = {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = listOf(track.title, track.artist).filter(String::isNotBlank).joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    OutlinedTextField(
                        value = manualQuery,
                        onValueChange = {
                            manualQuery = it
                            manualError = null
                            manualCandidates = emptyList()
                        },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = { Text("Judul atau artis") },
                        enabled = !manualSearching,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Text,
                            imeAction = ImeAction.Search,
                        ),
                        keyboardActions = KeyboardActions(onSearch = { searchManualCandidates() }),
                    )
                    if (manualSearching) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                            Text("Mencari kandidat YouTube Music…", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    manualError?.let { message ->
                        Text(
                            text = message,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    LazyColumn(
                        modifier = Modifier.heightIn(max = 300.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        items(manualCandidates, key = { it.videoId }) { candidate ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable(enabled = !manualSearching) {
                                        chooseManualCandidate(track, candidate)
                                    }
                                    .padding(8.dp),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                AsyncImage(
                                    model = candidate.thumbnailUrl,
                                    contentDescription = null,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier
                                        .size(48.dp)
                                        .clip(RoundedCornerShape(7.dp)),
                                )
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        text = candidate.title,
                                        style = MaterialTheme.typography.bodyMedium,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        text = candidate.artist,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    candidate.durationText?.let { duration ->
                                        Text(
                                            text = duration,
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = ::searchManualCandidates,
                    enabled = manualQuery.isNotBlank() && !manualSearching,
                ) {
                    Text("Cari")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = ::closeManualSearch,
                    enabled = !manualSearching,
                ) {
                    Text("Tutup")
                }
            },
        )
    }
}
