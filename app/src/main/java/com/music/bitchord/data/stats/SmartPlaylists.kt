package com.music.bitchord.data.stats

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** The ordering used by a user-defined Smart Playlist. */
enum class SmartPlaylistSort {
    MOST_PLAYED,
    RECENTLY_PLAYED,
    MOST_LISTENED,
}

/**
 * A saved rule, not a snapshot of songs. Its result is rebuilt from listening
 * statistics whenever the Library is opened or new stats reach disk.
 */
data class SmartPlaylistRule(
    val id: String = "",
    val name: String,
    val artistContains: String = "",
    val minimumPlays: Int = 1,
    val sort: SmartPlaylistSort = SmartPlaylistSort.MOST_PLAYED,
)

/** A built-in or user-defined Smart Playlist and the current matching tracks. */
data class SmartPlaylistItem(
    val id: String,
    val title: String,
    val tracks: List<RankedSong>,
    val rule: SmartPlaylistRule? = null,
)

object SmartPlaylists {
    private const val PREF_NAME = "bitchord_smart_playlists"
    private const val KEY_RULES = "rules_json"
    private const val MAX_RULES = 20

    private lateinit var prefs: SharedPreferences
    private val lock = Any()
    private val _rules = MutableStateFlow<List<SmartPlaylistRule>>(emptyList())
    val rules = _rules.asStateFlow()

    fun init(context: Context) {
        if (this::prefs.isInitialized) return
        prefs = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        _rules.value = load()
    }

    /**
     * Creates or updates a rule. Invalid names are rejected; inputs are bounded
     * before persistence so a corrupt or edited preference cannot make the
     * Library build an unbounded query.
     */
    fun save(rule: SmartPlaylistRule): SmartPlaylistRule? {
        check(this::prefs.isInitialized) { "Smart Playlist storage is not initialized" }
        val name = rule.name.trim().takeIf(String::isNotEmpty) ?: return null
        val cleanId = rule.id.trim().takeIf(String::isNotEmpty) ?: UUID.randomUUID().toString()
        val normalized = rule.copy(
            id = cleanId,
            name = name.take(MAX_NAME_LENGTH),
            artistContains = rule.artistContains.trim().take(MAX_ARTIST_FILTER_LENGTH),
            minimumPlays = rule.minimumPlays.coerceIn(1, MAX_MINIMUM_PLAYS),
        )
        synchronized(lock) {
            val existing = _rules.value.any { it.id == cleanId }
            if (!existing && _rules.value.size >= MAX_RULES) return null
            val updated = if (existing) {
                _rules.value.map { if (it.id == cleanId) normalized else it }
            } else {
                listOf(normalized) + _rules.value
            }
            persist(updated)
        }
        return normalized
    }

    fun delete(id: String) {
        check(this::prefs.isInitialized) { "Smart Playlist storage is not initialized" }
        synchronized(lock) {
            persist(_rules.value.filterNot { it.id == id })
        }
    }

    /**
     * Restores saved rules as part of Backup & Restore. Merge keeps rules already
     * on this device when ids collide; replace uses the backup's complete set.
     */
    fun restoreFromBackup(incoming: List<SmartPlaylistRule>, merge: Boolean): Int {
        check(this::prefs.isInitialized) { "Smart Playlist storage is not initialized" }
        require(incoming.size <= MAX_RULES) { "Backup contains too many Smart Playlists" }

        val imported = LinkedHashMap<String, SmartPlaylistRule>()
        incoming.forEach { rule ->
            val id = rule.id.trim()
            val name = rule.name.trim()
            require(id.isNotEmpty() && name.isNotEmpty()) { "Backup contains an invalid Smart Playlist rule" }
            require(id.length <= 512 && name.length <= MAX_NAME_LENGTH) {
                "Backup contains an oversized Smart Playlist rule"
            }
            require(rule.artistContains.length <= MAX_ARTIST_FILTER_LENGTH &&
                rule.minimumPlays in 1..MAX_MINIMUM_PLAYS) {
                "Backup contains invalid Smart Playlist filters"
            }
            require(imported.putIfAbsent(
                id,
                rule.copy(
                    id = id,
                    name = name,
                    artistContains = rule.artistContains.trim(),
                ),
            ) == null) { "Backup contains duplicate Smart Playlist rules" }
        }

        val next = if (merge) {
            val combined = LinkedHashMap<String, SmartPlaylistRule>()
            _rules.value.forEach { combined[it.id] = it }
            imported.forEach { (id, rule) -> combined.putIfAbsent(id, rule) }
            require(combined.size <= MAX_RULES) {
                "Merging this backup would exceed the 20 Smart Playlist limit"
            }
            combined.values.toList()
        } else {
            imported.values.toList()
        }
        synchronized(lock) { persist(next) }
        return next.size
    }

    private fun persist(value: List<SmartPlaylistRule>) {
        val json = JSONArray()
        value.forEach { rule ->
            json.put(
                JSONObject().apply {
                    put("id", rule.id)
                    put("name", rule.name)
                    put("artistContains", rule.artistContains)
                    put("minimumPlays", rule.minimumPlays)
                    put("sort", rule.sort.name)
                },
            )
        }
        check(prefs.edit().putString(KEY_RULES, json.toString()).commit()) {
            "Could not save Smart Playlist rules"
        }
        _rules.value = value
    }

    private fun load(): List<SmartPlaylistRule> {
        val raw = prefs.getString(KEY_RULES, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            val seen = HashSet<String>()
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                val id = item.optString("id").trim().takeIf(String::isNotEmpty)
                    ?: return@mapNotNull null
                val name = item.optString("name").trim().takeIf(String::isNotEmpty)
                    ?: return@mapNotNull null
                if (!seen.add(id)) return@mapNotNull null
                val sort = runCatching {
                    SmartPlaylistSort.valueOf(item.optString("sort"))
                }.getOrDefault(SmartPlaylistSort.MOST_PLAYED)
                SmartPlaylistRule(
                    id = id,
                    name = name.take(MAX_NAME_LENGTH),
                    artistContains = item.optString("artistContains").trim().take(MAX_ARTIST_FILTER_LENGTH),
                    minimumPlays = item.optInt("minimumPlays", 1).coerceIn(1, MAX_MINIMUM_PLAYS),
                    sort = sort,
                )
            }.take(MAX_RULES)
        }.getOrElse { emptyList() }
    }

    private const val MAX_NAME_LENGTH = 40
    private const val MAX_ARTIST_FILTER_LENGTH = 80
    private const val MAX_MINIMUM_PLAYS = 100
}

/** Applies a saved rule to the current stats. Stable tie-breaks prevent cards jumping around. */
internal fun applySmartPlaylistRule(
    tracks: List<RankedSong>,
    rule: SmartPlaylistRule,
): List<RankedSong> {
    val artistFilter = rule.artistContains.trim()
    val filtered = tracks.filter { track ->
        track.plays >= rule.minimumPlays &&
            (artistFilter.isEmpty() || track.song.artist.contains(artistFilter, ignoreCase = true))
    }
    val sorted = when (rule.sort) {
        SmartPlaylistSort.MOST_PLAYED -> filtered.sortedWith(
            compareByDescending<RankedSong> { it.plays }
                .thenByDescending { it.ms }
                .thenBy { it.song.title.lowercase() },
        )
        SmartPlaylistSort.RECENTLY_PLAYED -> filtered.sortedWith(
            compareByDescending<RankedSong> { it.lastPlayedAt }
                .thenByDescending { it.plays }
                .thenBy { it.song.title.lowercase() },
        )
        SmartPlaylistSort.MOST_LISTENED -> filtered.sortedWith(
            compareByDescending<RankedSong> { it.ms }
                .thenByDescending { it.plays }
                .thenBy { it.song.title.lowercase() },
        )
    }
    return sorted.take(MAX_SMART_PLAYLIST_TRACKS)
}

/**
 * Built-ins and saved rules are all views over the same listening aggregates.
 * No track is copied into or removed from a normal playlist.
 */
internal fun buildSmartPlaylistItems(
    tracks: List<RankedSong>,
    rules: List<SmartPlaylistRule>,
    nowMs: Long,
): List<SmartPlaylistItem> {
    if (tracks.isEmpty()) {
        return rules.take(20).map { rule ->
            SmartPlaylistItem(
                id = "custom:${rule.id}",
                title = rule.name,
                tracks = emptyList(),
                rule = rule,
            )
        }
    }

    val result = buildList {
        val mostPlayed = tracks.filter { it.plays > 0 }.sortedWith(
            compareByDescending<RankedSong> { it.plays }
                .thenByDescending { it.ms }
                .thenBy { it.song.title.lowercase() },
        ).take(MAX_SMART_PLAYLIST_TRACKS)
        if (mostPlayed.isNotEmpty()) {
            add(SmartPlaylistItem("most_played", "Most played", mostPlayed))
        }

        val recentlyPlayed = tracks.filter { it.lastPlayedAt > 0L }.sortedWith(
            compareByDescending<RankedSong> { it.lastPlayedAt }
                .thenByDescending { it.plays }
                .thenBy { it.song.title.lowercase() },
        ).take(MAX_SMART_PLAYLIST_TRACKS)
        if (recentlyPlayed.isNotEmpty()) {
            add(SmartPlaylistItem("recently_played", "Recently played", recentlyPlayed))
        }

        val mostListened = tracks.filter { it.ms > 0L }.sortedWith(
            compareByDescending<RankedSong> { it.ms }
                .thenByDescending { it.plays }
                .thenBy { it.song.title.lowercase() },
        ).take(MAX_SMART_PLAYLIST_TRACKS)
        if (mostListened.isNotEmpty()) {
            add(SmartPlaylistItem("most_listened", "Most listened", mostListened))
        }

        val forgotten = tracks.filter {
            it.lastPlayedAt > 0L && nowMs - it.lastPlayedAt >= FORGOTTEN_AFTER_MS
        }.sortedWith(
            compareBy<RankedSong> { it.lastPlayedAt }
                .thenByDescending { it.ms }
                .thenBy { it.song.title.lowercase() },
        ).take(MAX_SMART_PLAYLIST_TRACKS)
        if (forgotten.isNotEmpty()) {
            add(SmartPlaylistItem("forgotten_tracks", "Forgotten tracks", forgotten))
        }

        rules.take(20).forEach { rule ->
            add(
                SmartPlaylistItem(
                    id = "custom:${rule.id}",
                    title = rule.name,
                    tracks = applySmartPlaylistRule(tracks, rule),
                    rule = rule,
                ),
            )
        }
    }
    return result
}

private const val MAX_SMART_PLAYLIST_TRACKS = 100
private const val FORGOTTEN_AFTER_MS = 30L * 24L * 60L * 60L * 1000L
