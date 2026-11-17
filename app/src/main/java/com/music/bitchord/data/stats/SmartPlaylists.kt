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

/** How optional criteria are combined; minimum plays remains a required baseline. */
enum class SmartPlaylistMatchMode {
    ALL,
    ANY,
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
    val genreContains: String = "",
    val releaseYearFrom: Int? = null,
    val releaseYearTo: Int? = null,
    val minimumDurationMinutes: Int? = null,
    val maximumDurationMinutes: Int? = null,
    val lastPlayedWithinDays: Int? = null,
    val matchMode: SmartPlaylistMatchMode = SmartPlaylistMatchMode.ALL,
)

private const val MAX_GENRE_FILTER_LENGTH = 80
private const val MIN_RELEASE_YEAR = 1888
private const val MAX_RELEASE_YEAR = 2100
private const val MAX_DURATION_MINUTES = 1_440
private const val MAX_LAST_PLAYED_DAYS = 3_650
private const val MILLIS_PER_DAY = 24L * 60L * 60L * 1_000L

private fun isValidSmartPlaylistRule(rule: SmartPlaylistRule): Boolean =
    rule.name.isNotBlank() && rule.name.length <= 40 &&
        rule.artistContains.length <= 80 && rule.genreContains.length <= MAX_GENRE_FILTER_LENGTH &&
        rule.minimumPlays in 1..100 &&
        (rule.releaseYearFrom == null || rule.releaseYearFrom in MIN_RELEASE_YEAR..MAX_RELEASE_YEAR) &&
        (rule.releaseYearTo == null || rule.releaseYearTo in MIN_RELEASE_YEAR..MAX_RELEASE_YEAR) &&
        (rule.releaseYearFrom == null || rule.releaseYearTo == null || rule.releaseYearFrom <= rule.releaseYearTo) &&
        (rule.minimumDurationMinutes == null || rule.minimumDurationMinutes in 1..MAX_DURATION_MINUTES) &&
        (rule.maximumDurationMinutes == null || rule.maximumDurationMinutes in 1..MAX_DURATION_MINUTES) &&
        (rule.minimumDurationMinutes == null || rule.maximumDurationMinutes == null || rule.minimumDurationMinutes <= rule.maximumDurationMinutes) &&
        (rule.lastPlayedWithinDays == null || rule.lastPlayedWithinDays in 1..MAX_LAST_PLAYED_DAYS)

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
            genreContains = rule.genreContains.trim().take(MAX_GENRE_FILTER_LENGTH),
        )
        if (!isValidSmartPlaylistRule(normalized)) return null
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
     * Restores saved rules without copying generated tracks. Merge keeps current
     * rules for matching ids and appends imported rules that are not on device.
     */
    fun restoreFromBackup(incoming: List<SmartPlaylistRule>, merge: Boolean): Int {
        check(this::prefs.isInitialized) { "Smart Playlist storage is not initialized" }
        require(incoming.size <= MAX_RULES) { "Backup contains too many Smart Playlists" }
        incoming.forEach { rule ->
            require(rule.id.isNotBlank() && rule.id.length <= 512) {
                "Backup contains an invalid Smart Playlist rule id"
            }
            require(rule.name.isNotBlank() && rule.name.length <= MAX_NAME_LENGTH) {
                "Backup contains an invalid Smart Playlist name"
            }
            require(rule.artistContains.length <= MAX_ARTIST_FILTER_LENGTH &&
                rule.minimumPlays in 1..MAX_MINIMUM_PLAYS &&
                isValidSmartPlaylistRule(rule)) {
                "Backup contains invalid Smart Playlist filters"
            }
        }
        val normalizedIncoming = normalizeSmartPlaylistRules(incoming)
        require(normalizedIncoming.size == incoming.size) {
            "Backup contains duplicate or invalid Smart Playlist rules"
        }
        synchronized(lock) {
            val current = normalizeSmartPlaylistRules(_rules.value)
            val next = if (merge) {
                val combined = current + normalizedIncoming.filterNot { imported ->
                    current.any { existing -> existing.id == imported.id }
                }
                require(combined.size <= MAX_RULES) {
                    "Merging this backup would exceed the 20 Smart Playlist limit"
                }
                combined
            } else {
                normalizedIncoming
            }
            persist(next)
            return next.size
        }
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
                    put("genreContains", rule.genreContains)
                    put("releaseYearFrom", rule.releaseYearFrom)
                    put("releaseYearTo", rule.releaseYearTo)
                    put("minimumDurationMinutes", rule.minimumDurationMinutes)
                    put("maximumDurationMinutes", rule.maximumDurationMinutes)
                    put("lastPlayedWithinDays", rule.lastPlayedWithinDays)
                    put("matchMode", rule.matchMode.name)
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
                    genreContains = item.optString("genreContains").trim().take(MAX_GENRE_FILTER_LENGTH),
                    releaseYearFrom = item.optInt("releaseYearFrom", 0).takeIf { it in MIN_RELEASE_YEAR..MAX_RELEASE_YEAR },
                    releaseYearTo = item.optInt("releaseYearTo", 0).takeIf { it in MIN_RELEASE_YEAR..MAX_RELEASE_YEAR },
                    minimumDurationMinutes = item.optInt("minimumDurationMinutes", 0).takeIf { it in 1..MAX_DURATION_MINUTES },
                    maximumDurationMinutes = item.optInt("maximumDurationMinutes", 0).takeIf { it in 1..MAX_DURATION_MINUTES },
                    lastPlayedWithinDays = item.optInt("lastPlayedWithinDays", 0).takeIf { it in 1..MAX_LAST_PLAYED_DAYS },
                    matchMode = runCatching { SmartPlaylistMatchMode.valueOf(item.optString("matchMode")) }
                        .getOrDefault(SmartPlaylistMatchMode.ALL),
                ).takeIf(::isValidSmartPlaylistRule)
            }.take(MAX_RULES)
        }.getOrElse { emptyList() }
    }

    private const val MAX_NAME_LENGTH = 40
    private const val MAX_ARTIST_FILTER_LENGTH = 80
    private const val MAX_MINIMUM_PLAYS = 100
}

/** Removes invalid/duplicate ids and keeps the persisted rule set bounded. */
internal fun normalizeSmartPlaylistRules(rules: List<SmartPlaylistRule>): List<SmartPlaylistRule> {
    val seen = HashSet<String>()
    return rules.mapNotNull { rule ->
        val id = rule.id.trim().takeIf(String::isNotEmpty) ?: return@mapNotNull null
        val name = rule.name.trim().takeIf(String::isNotEmpty) ?: return@mapNotNull null
        if (!seen.add(id)) return@mapNotNull null
        rule.copy(
            id = id, name = name.take(40),
            artistContains = rule.artistContains.trim().take(80),
            genreContains = rule.genreContains.trim().take(MAX_GENRE_FILTER_LENGTH),
            minimumPlays = rule.minimumPlays.coerceIn(1, 100),
        ).takeIf(::isValidSmartPlaylistRule)
    }.take(20)
}

/** Applies a saved rule to the current stats. Stable tie-breaks prevent cards jumping around. */
internal fun applySmartPlaylistRule(
    tracks: List<RankedSong>,
    rule: SmartPlaylistRule,
    nowMs: Long = System.currentTimeMillis(),
    genresForArtist: (String) -> List<String> = { ArtistFacts.genresFor(it) },
): List<RankedSong> {
    val optionalFilters = buildList<(RankedSong) -> Boolean> {
        rule.artistContains.trim().takeIf(String::isNotEmpty)?.let { filter ->
            add { track -> track.song.artist.contains(filter, ignoreCase = true) }
        }
        rule.genreContains.trim().takeIf(String::isNotEmpty)?.let { filter ->
            add { track ->
                val artists = (listOf(track.song.artist) + track.song.artists.map { it.name })
                    .filter(String::isNotBlank).distinct()
                artists.asSequence().flatMap { genresForArtist(it).asSequence() }
                    .any { it.contains(filter, ignoreCase = true) }
            }
        }
        if (rule.releaseYearFrom != null || rule.releaseYearTo != null) {
            add { track ->
                val year = track.song.releaseYear
                year != null && (rule.releaseYearFrom == null || year >= rule.releaseYearFrom) &&
                    (rule.releaseYearTo == null || year <= rule.releaseYearTo)
            }
        }
        if (rule.minimumDurationMinutes != null || rule.maximumDurationMinutes != null) {
            add { track ->
                val seconds = parseSmartPlaylistDurationSeconds(track.song.durationText)
                seconds != null &&
                    (rule.minimumDurationMinutes == null || seconds >= rule.minimumDurationMinutes * 60) &&
                    (rule.maximumDurationMinutes == null || seconds <= rule.maximumDurationMinutes * 60)
            }
        }
        rule.lastPlayedWithinDays?.let { days ->
            val cutoff = nowMs - days.toLong() * MILLIS_PER_DAY
            add { track -> track.lastPlayedAt > 0L && track.lastPlayedAt >= cutoff }
        }
    }
    val filtered = tracks.filter { track ->
        if (track.plays < rule.minimumPlays) return@filter false
        if (optionalFilters.isEmpty()) return@filter true
        when (rule.matchMode) {
            SmartPlaylistMatchMode.ALL -> optionalFilters.all { it(track) }
            SmartPlaylistMatchMode.ANY -> optionalFilters.any { it(track) }
        }
    }
    val sorted = when (rule.sort) {
        SmartPlaylistSort.MOST_PLAYED -> filtered.sortedWith(
            compareByDescending<RankedSong> { it.plays }.thenByDescending { it.ms }.thenBy { it.song.title.lowercase() },
        )
        SmartPlaylistSort.RECENTLY_PLAYED -> filtered.sortedWith(
            compareByDescending<RankedSong> { it.lastPlayedAt }.thenByDescending { it.plays }.thenBy { it.song.title.lowercase() },
        )
        SmartPlaylistSort.MOST_LISTENED -> filtered.sortedWith(
            compareByDescending<RankedSong> { it.ms }.thenByDescending { it.plays }.thenBy { it.song.title.lowercase() },
        )
    }
    return sorted.take(MAX_SMART_PLAYLIST_TRACKS)
}

/** Parses m:ss, h:mm:ss, or a labelled duration; unknown text is not guessed. */
internal fun parseSmartPlaylistDurationSeconds(value: String?): Int? {
    val raw = value?.trim()?.takeIf(String::isNotEmpty) ?: return null
    val colonParts = raw.split(':')
    if (colonParts.size in 2..3 && colonParts.all { it.isNotEmpty() && it.all(Char::isDigit) }) {
        val numbers = colonParts.map { it.toLongOrNull() ?: return null }
        val seconds = if (numbers.size == 2) {
            if (numbers[1] > 59) return null
            numbers[0] * 60 + numbers[1]
        } else {
            if (numbers[1] > 59 || numbers[2] > 59) return null
            numbers[0] * 3_600 + numbers[1] * 60 + numbers[2]
        }
        return seconds.takeIf { it in 1..Int.MAX_VALUE.toLong() }?.toInt()
    }
    val parts = Regex("""(\d+)\s*(hours?|hrs?|hr|h|minutes?|mins?|min|m|seconds?|secs?|sec|s)""", RegexOption.IGNORE_CASE)
        .findAll(raw).toList()
    if (parts.isEmpty()) return null
    var total = 0L
    for (part in parts) {
        val amount = part.groupValues[1].toLongOrNull() ?: return null
        val multiplier = when (part.groupValues[2].lowercase().first()) {
            'h' -> 3_600L; 'm' -> 60L; else -> 1L
        }
        total += amount * multiplier
        if (total > Int.MAX_VALUE) return null
    }
    return total.takeIf { it > 0L }?.toInt()
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
                    tracks = applySmartPlaylistRule(tracks, rule, nowMs),
                    rule = rule,
                ),
            )
        }
    }
    return result
}

private const val MAX_SMART_PLAYLIST_TRACKS = 100
private const val FORGOTTEN_AFTER_MS = 30L * 24L * 60L * 60L * 1000L
