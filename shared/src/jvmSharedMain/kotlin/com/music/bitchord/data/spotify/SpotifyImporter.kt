package com.music.bitchord.data.spotify

import com.music.bitchord.data.DebugLog
import com.music.bitchord.data.Http
import com.music.bitchord.data.YtMusicRepository
import com.music.bitchord.data.model.BrowseType
import com.music.bitchord.data.model.SearchFilter
import com.music.bitchord.data.model.SearchResult
import com.music.bitchord.data.model.Song
import com.music.bitchord.data.sources.TrackMatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** Single track metadata extracted from a Spotify playlist. */
data class SpotifyImportTrack(
    val title: String,
    val artist: String,
    val durationMs: Long? = null,
    val album: String? = null,
    val spotifyId: String? = null,
    val leadArtist: String? = null,
    /** Original Spotify artist objects, kept separately from the display string. */
    val artistCredits: List<String> = emptyList(),
)

/** The result of fetching and resolving a Spotify playlist's tracks. */
data class SpotifyImportResult(
    val title: String,
    val description: String,
    val thumbnailUrl: String?,
    val totalTracks: Int,
    val resolvedVideoIds: List<String>,
    val unmatchedTracks: List<SpotifyImportTrack>,
)

object SpotifyImporter {

    private const val USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    /** A Spotify playlist id is 22 base-62 characters. */
    private val PLAYLIST_ID = Regex("""[A-Za-z0-9]{22}""")

    private fun isSpotifyHost(host: String) =
        host == "spotify.com" || host.endsWith(".spotify.com")

    /** Parses a raw user string or link into a Spotify playlist ID if valid. */
    fun extractPlaylistId(input: String): String? {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return null

        if (trimmed.startsWith("spotify:playlist:")) {
            val id = trimmed.removePrefix("spotify:playlist:").substringBefore("?").substringBefore("/")
            return id.takeIf { PLAYLIST_ID.matches(it) }
        }

        val uri = runCatching { java.net.URI(trimmed) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase() !in setOf("http", "https")) return null
        if (!isSpotifyHost(uri.host?.lowercase().orEmpty())) return null
        val segments = uri.path.orEmpty().split('/').filter { it.isNotEmpty() }
        val playlistIdx = segments.indexOf("playlist")
        if (playlistIdx == -1 || playlistIdx + 1 >= segments.size) return null
        return segments[playlistIdx + 1].takeIf { PLAYLIST_ID.matches(it) }
    }

    /**
     * Fetches public Spotify playlist details from Spotify's embed endpoint.
     */
    suspend fun fetchPlaylistTracks(playlistId: String): Pair<String, List<SpotifyImportTrack>> =
        withContext(Dispatchers.IO) {
            val url = "https://open.spotify.com/embed/playlist/$playlistId"
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", USER_AGENT)
                .build()

            val html = Http.client.newCall(request).execute().use { response ->
                val body = response.body?.string().orEmpty()
                if (!response.isSuccessful || body.isBlank()) {
                    error("Failed to load Spotify playlist (HTTP ${response.code})")
                }
                body
            }

            // Extract <script id="__NEXT_DATA__" type="application/json">...</script>
            val scriptRegex = Regex("""<script id="__NEXT_DATA__" type="application/json">(.*?)</script>""", RegexOption.DOT_MATCHES_ALL)
            val match = scriptRegex.find(html)
                ?: error("Could not parse Spotify playlist metadata. Make sure the playlist is public.")

            val jsonString = match.groupValues[1]
            val root = json.parseToJsonElement(jsonString).jsonObject

            val props = root["props"]?.jsonObject
                ?.get("pageProps")?.jsonObject
            val stateData = props?.get("state")?.jsonObject
                ?.get("data")?.jsonObject
                ?.get("entity")?.jsonObject
                ?: props?.get("entity")?.jsonObject
                ?: error("Spotify playlist entity missing or private")

            val playlistTitle = stateData["name"]?.jsonPrimitive?.content
                ?: stateData["title"]?.jsonPrimitive?.content
                ?: "Imported Spotify Playlist"

            val trackListJson = stateData["trackList"]?.jsonArray
                ?: stateData["tracks"]?.jsonArray
                ?: JsonArray(emptyList())

            val tracks = mutableListOf<SpotifyImportTrack>()
            for (element in trackListJson) {
                val obj = element.jsonObject
                val title = obj["title"]?.jsonPrimitive?.content
                    ?: obj["name"]?.jsonPrimitive?.content
                    ?: continue
                val artistNames = obj.spotifyArtistNames()
                val artists = artistNames.takeIf { it.isNotEmpty() }?.joinToString(", ")
                    ?: obj.spotifyArtistCredit()
                if (title.isNotBlank()) {
                    tracks.add(SpotifyImportTrack(
                        title = title.trim(),
                        artist = artists,
                        durationMs = obj.spotifyDurationMs(),
                        album = obj.spotifyAlbumName(),
                        spotifyId = obj.spotifyTrackId(),
                        // Prefer Spotify's structured first credit. Only use the
                        // first subtitle segment as a fallback when Spotify omitted
                        // structured credits, matching the established import behavior.
                        leadArtist = artistNames.firstOrNull()
                            ?: artists.substringBefore(",").trim().takeIf { it.isNotBlank() },
                        artistCredits = artistNames,
                    ))
                }
            }

            if (tracks.isEmpty()) {
                error("No tracks found in public Spotify playlist.")
            }

            // The embed page stops at its first 100 raw entries. Never report a
            // successful partial import when the continuation request fails.
            // Offset is the raw embed count, not the number of rows we could parse.
            if (trackListJson.size >= EMBED_TRACK_LIMIT) {
                val token = props?.get("state")?.jsonObject
                    ?.get("settings")?.jsonObject
                    ?.get("session")?.jsonObject
                    ?.get("accessToken")?.jsonPrimitive?.content
                    ?.takeIf { it.isNotBlank() }
                    ?: error("Spotify only exposed the first 100 tracks and no continuation token. Please retry the import.")
                tracks.addAll(fetchRemainingTracks(playlistId, token, trackListJson.size))
            }

            Pair(playlistTitle, tracks)
        }

    /**
     * The YouTube Music song that is [track], or null if no safe match is
     * found after searching song and music-video results.
     */
    suspend fun matchTrack(track: SpotifyTrack): Song? {
        val target = TrackMatcher.Target(
            title = track.title,
            artist = track.artist,
            durationSec = track.durationMs.takeIf { it > 0 }?.div(1000),
            album = track.album,
            requireSharedArtist = true,
            requiredArtistName = track.leadArtist
                ?: track.artist.substringBefore(",").trim().takeIf { it.isNotBlank() },
            requireExactTitle = true,
            artistCredits = track.artistCredits,
        )
        return bestSpotifyImportMatch(searchCandidates(target), target)
    }

    /**
     * Search budget per query. The unfiltered music catalogue can contain
     * promoted cards and regional releases below the first shelf; pagination
     * stays bounded so a long playlist cannot overwhelm the service.
     */
    private const val MAX_CANDIDATE_SEARCH_PAGES = 5
    private const val MAX_SEARCH_QUERY_VARIANTS = 10
    private const val MIN_PAGES_TO_COMPARE_AFTER_MATCH = 2
    private const val MAX_ARTIST_PAGE_FALLBACKS = 5
    private const val MAX_ALBUM_PAGE_FALLBACKS = 5
    private const val STRONG_MATCH_RUNTIME_SEC = 8

    private val artistPageLocks = ConcurrentHashMap<String, Mutex>()
    // Cache exact artist lookups, including misses, across tracks in the playlist.
    private val artistBrowseIdCache = ConcurrentHashMap<String, String>()
    private val artistSongCache = object : LinkedHashMap<String, List<Song>>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<Song>>?): Boolean =
            size > 32
    }
    private val albumPageLocks = ConcurrentHashMap<String, Mutex>()
    private val albumSongCache = object : LinkedHashMap<String, List<Song>>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<Song>>?): Boolean =
            size > 64
    }

    /**
     * Reuse the artist catalogue between tracks in the same Spotify playlist.
     * A per-artist mutex prevents six parallel track lookups from fetching the
     * same large discography at once.
     */
    private suspend fun artistSongs(browseId: String): Result<List<Song>> {
        val lock = artistPageLocks.computeIfAbsent(browseId) { Mutex() }
        return lock.withLock {
            synchronized(artistSongCache) {
                artistSongCache[browseId]?.let { return@withLock Result.success(it) }
            }
            YtMusicRepository.artistSongsForSpotifyImport(browseId).onSuccess { songs ->
                if (songs.isNotEmpty()) {
                    synchronized(artistSongCache) { artistSongCache[browseId] = songs }
                }
            }
        }
    }

    /** Reuse complete album pages across tracks from the same imported playlist. */
    private suspend fun albumSongs(browseId: String): Result<List<Song>> {
        val lock = albumPageLocks.computeIfAbsent(browseId) { Mutex() }
        return lock.withLock {
            synchronized(albumSongCache) {
                albumSongCache[browseId]?.let { return@withLock Result.success(it) }
            }
            YtMusicRepository.browseSongsForSpotifyImport(browseId).onSuccess { songs ->
                if (songs.isNotEmpty()) {
                    synchronized(albumSongCache) { albumSongCache[browseId] = songs }
                }
            }
        }
    }

    /** Find a real artist page by exact displayed name, not a partial search hit. */
    private suspend fun discoverArtistBrowseId(name: String): Result<String?> {
        val key = name.trim().lowercase()
        if (key.isBlank()) return Result.success(null)
        artistBrowseIdCache[key]?.let { cached ->
            return Result.success(cached.takeIf { it.isNotBlank() })
        }
        return YtMusicRepository.findArtistPageId(name).onSuccess { browseId ->
            artistBrowseIdCache.putIfAbsent(key, browseId.orEmpty())
        }
    }

    /**
     * Search the same authenticated YouTube Music catalogue as the manual
     * Search screen. Gather promoted tracks and normal track rows, but keep
     * artist cards too: when a track is missing from global search, the
     * artist's own Top Songs catalogue is a second, more specific source.
     *
     * Audio matches are always preferred. A music video is a fallback only
     * after the audio catalogue and the matching artist page have been tried.
     */
    private suspend fun searchCandidates(target: TrackMatcher.Target, suffix: String? = null): List<Song> {
        val found = LinkedHashMap<String, Song>()
        val artistBrowseIds = LinkedHashSet<String>()
        val albumBrowseIds = LinkedHashSet<String>()
        val failures = mutableListOf<String>()
        var successfulRequests = 0

        val queries = spotifyImportSearchQueries(target)

        // A trusted credit alone is not enough to stop discovery: the first
        // search row can be a shorter edit or a near-runtime regional upload.
        // Keep looking until the title/credit match also has a close runtime.
        fun hasHighConfidenceAudioMatch(): Boolean =
            found.values.any { candidate ->
                !candidate.isVideo &&
                    TrackMatcher.hasTrustedArtistCredit(candidate, target) &&
                    (target.durationSec == null ||
                        TrackMatcher.withinSeconds(candidate, target, STRONG_MATCH_RUNTIME_SEC))
            }

        fun hasHighConfidenceVideoMatch(): Boolean =
            found.values.any { candidate ->
                candidate.isVideo &&
                    TrackMatcher.hasTrustedArtistCredit(candidate, target) &&
                    (target.durationSec == null ||
                        TrackMatcher.withinSeconds(candidate, target, STRONG_MATCH_RUNTIME_SEC))
            }

        suspend fun searchFilter(
            filter: SearchFilter,
            includeLanguageSuffix: Boolean = false,
        ) {
            // A strong match is still compared against one independent query,
            // so a raw-title hit cannot hide a better artist-qualified release.
            // Once that second query has been sampled, further variants add
            // latency without meaningful identity evidence.
            var firstStrongMatchQueryIndex: Int? = null
            fun hasHighConfidenceMatch(): Boolean = when (filter) {
                SearchFilter.ALL -> hasHighConfidenceAudioMatch()
                SearchFilter.VIDEOS -> hasHighConfidenceVideoMatch()
                else -> false
            }

            for ((queryIndex, baseQuery) in queries.take(MAX_SEARCH_QUERY_VARIANTS).withIndex()) {
                // Once a strong result exists, sample just one additional
                // spelling/album query. Queries without a strong result still
                // receive the full page budget.
                val pageLimitForQuery = if (
                    (filter == SearchFilter.ALL && hasHighConfidenceAudioMatch()) ||
                    (filter == SearchFilter.VIDEOS && hasHighConfidenceVideoMatch())
                ) 1 else MAX_CANDIDATE_SEARCH_PAGES
                // Match the manual Search query first, without silently
                // changing the words the listener would type. A preferred
                // language is a fallback query, not part of the primary query:
                // appending it up front can hide an otherwise visible result.
                val query = listOf(
                    baseQuery,
                    suffix?.takeIf { includeLanguageSuffix && it.isNotBlank() },
                )
                    .filterNotNull()
                    .joinToString(" ")
                // Manual Search uses the authenticated endpoint. Starting the
                // import anonymously caused the same query to return a
                // different catalogue, and its continuation then switched
                // back to the authenticated endpoint halfway through.
                val firstPage = YtMusicRepository.searchPage(
                    query = query,
                    filter = filter,
                    anonymous = false,
                ).fold(
                    onSuccess = { successfulRequests++; it },
                    onFailure = { failure ->
                        failures += "search '$query' (${filter.name}): ${failure.message}"
                        null
                    },
                )
                if (firstPage == null) {
                    if (shouldStopSpotifyQueryExpansion(
                            firstStrongMatchQueryIndex,
                            queryIndex,
                            hasHighConfidenceMatch(),
                        )
                    ) return
                    continue
                }

                var page: YtMusicRepository.SearchPage = firstPage ?: continue
                var pagesRead = 0
                while (pagesRead < pageLimitForQuery) {
                    page.rows.forEach { row ->
                        when (row) {
                            is SearchResult.Browse -> {
                                spotifyImportAlbumBrowseId(row)?.let(albumBrowseIds::add)
                                spotifyImportArtistCredits(target).forEach { expectedArtist ->
                                    spotifyArtistBrowseId(row, expectedArtist)?.let(artistBrowseIds::add)
                                }
                            }
                            else -> {
                                val candidate = spotifyImportCandidate(row)
                                val id = candidate?.videoId?.trim().orEmpty()
                                if (candidate != null && id.isNotEmpty()) {
                                    found.putIfAbsent(id, candidate)
                                    spotifyImportArtistCredits(target).forEach { expectedArtist ->
                                        spotifyArtistBrowseId(candidate, expectedArtist)?.let(artistBrowseIds::add)
                                    }
                                }
                            }
                        }
                    }
                    pagesRead++

                    // The normal Search screen shows the same authenticated
                    // ALL catalogue. Once a candidate has a trusted artist
                    // credit, read two pages so a canonical release can outrank
                    // a near-runtime upload. A duration-only composer/uploader
                    // fallback is not trusted enough to stop alternate queries.
                    if (filter == SearchFilter.ALL && hasHighConfidenceAudioMatch() &&
                        pagesRead >= MIN_PAGES_TO_COMPARE_AFTER_MATCH
                    ) {
                        DebugLog.d(
                            "SpotifyImport",
                            "Matched '${target.title}' by '${target.artist}' after ${successfulRequests} search requests; checking one alternate query",
                        )
                        break
                    }
                    if (filter == SearchFilter.VIDEOS && hasHighConfidenceVideoMatch() &&
                        pagesRead >= MIN_PAGES_TO_COMPARE_AFTER_MATCH
                    ) break

                    val continuation = page.continuation ?: break
                    page = YtMusicRepository.searchContinuation(continuation, filter).fold(
                        onSuccess = { successfulRequests++; it },
                        onFailure = { failure ->
                            failures += "continuation '$query' (${filter.name}): ${failure.message}"
                            null
                        },
                    ) ?: break
                }
                val hasStrongMatch = hasHighConfidenceMatch()
                if (hasStrongMatch && firstStrongMatchQueryIndex == null) {
                    firstStrongMatchQueryIndex = queryIndex
                } else if (shouldStopSpotifyQueryExpansion(
                        firstStrongMatchQueryIndex,
                        queryIndex,
                        hasStrongMatch,
                    )
                ) {
                    DebugLog.d(
                        "SpotifyImport",
                        "Strong match for '${target.title}' by '${target.artist}' confirmed by " +
                            "query ${queryIndex + 1}; stopping query expansion after ${successfulRequests} requests",
                    )
                    break
                }
            }
        }

        // ALL is the same authenticated catalogue used by the normal Search
        // screen. Its promoted TopTrack and regular Track rows are both kept.
        // First run the exact, unqualified queries. Only add the optional
        // language term when those queries cannot produce any safe match.
        searchFilter(SearchFilter.ALL)
        if (!suffix.isNullOrBlank() && bestSpotifyImportMatch(found.values.toList(), target) == null) {
            DebugLog.d(
                "SpotifyImport",
                "No safe match for '${target.title}' without language suffix; retrying with '$suffix'",
            )
            searchFilter(SearchFilter.ALL, includeLanguageSuffix = true)
        }

        // Search may return an album card rather than an individual track.
        // Open a small, bounded set of those albums before giving up; rows from
        // them still pass the same strict title/artist/version/runtime matcher.
        if (!hasHighConfidenceAudioMatch()) {
            for (browseId in albumBrowseIds.take(MAX_ALBUM_PAGE_FALLBACKS)) {
                albumSongs(browseId).fold(
                    onSuccess = { songs ->
                        successfulRequests++
                        songs.forEach { song ->
                            val id = song.videoId.trim()
                            if (id.isNotEmpty()) found.putIfAbsent(id, song)
                        }
                    },
                    onFailure = { failure ->
                        failures += "album page '$browseId': ${failure.message}"
                    },
                )
                if (hasHighConfidenceAudioMatch()) break
            }
        }

        if (!hasHighConfidenceAudioMatch()) {
            // Global search may show a duration-only composer/uploader candidate
            // without exposing the requested singer. Keep searching artist
            // pages until a candidate has a trusted credit; every Top Song still
            // passes the strict title/version/runtime matcher.
            spotifyImportArtistCredits(target).take(MAX_ARTIST_PAGE_FALLBACKS).forEach { artistName ->
                discoverArtistBrowseId(artistName).fold(
                    onSuccess = { browseId -> browseId?.let(artistBrowseIds::add) },
                    onFailure = { failure ->
                        failures += "artist lookup '$artistName': ${failure.message}"
                    },
                )
            }
        }

        if (!hasHighConfidenceAudioMatch()) {
            for (browseId in artistBrowseIds) {
                artistSongs(browseId).fold(
                    onSuccess = { songs ->
                        successfulRequests++
                        songs.forEach { song ->
                            val id = song.videoId.trim()
                            if (id.isNotEmpty()) found.putIfAbsent(id, song)
                        }
                    },
                    onFailure = { failure ->
                        failures += "artist page '$browseId': ${failure.message}"
                    },
                )
                if (hasHighConfidenceAudioMatch()) break
            }
        }

        // Search the dedicated Videos tab too when no trusted audio/video
        // recording has been established. A duration-only fallback is not proof.
        if (!hasHighConfidenceAudioMatch() && !hasHighConfidenceVideoMatch()) {
            searchFilter(SearchFilter.VIDEOS)
        }

        val match = bestSpotifyImportMatch(found.values.toList(), target)
        if (match == null) {
            DebugLog.w(
                "SpotifyImport",
                "No match for '${target.title}' by '${target.artist}' " +
                    "(lead='${target.requiredArtistName}', duration=${target.durationSec}s, " +
                    "queries=${queries.size}, requests=${successfulRequests}, " +
                    "candidates=${found.size}, failures=${failures.size}). " +
                    found.values.take(8).joinToString { "${it.title} — ${it.artist} [${it.durationText}]" },
            )
        }
        // A transport/API failure is not proof that a song is absent. Propagate
        // an incomplete lookup so the UI can leave the row retryable instead
        // of permanently labelling it as missing.
        if (match == null && failures.isNotEmpty()) {
            throw IllegalStateException(
                "Spotify lookup incomplete ($successfulRequests successful requests): " +
                    failures.take(3).joinToString("; "),
            )
        }
        if (match == null && successfulRequests == 0 && queries.isNotEmpty()) {
            throw IllegalStateException("Spotify lookup returned no usable YouTube Music response")
        }
        return found.values.toList()
    }

    /** Tracks the embed page lists before it cuts off. */
    private const val EMBED_TRACK_LIMIT = 100
    private const val PAGE_SIZE = 100
    private const val PATHFINDER_URL = "https://api-partner.spotify.com/pathfinder/v1/query"
    private const val FETCH_PLAYLIST_HASH = "19ff1327c29e99c208c86d7a9d8f1929cfdf3d3202a0ff4253c821f1901aa94d"

    /** Tracks from [start] to the end of the playlist, a page at a time. */
    private fun fetchRemainingTracks(
        playlistId: String,
        token: String,
        start: Int,
    ): List<SpotifyImportTrack> {
        val out = mutableListOf<SpotifyImportTrack>()
        var offset = start
        while (true) {
            val variables = """{"uri":"spotify:playlist:$playlistId","offset":$offset,"limit":$PAGE_SIZE,"enableWatchFeedEntrypoint":false}"""
            val extensions = """{"persistedQuery":{"version":1,"sha256Hash":"$FETCH_PLAYLIST_HASH"}}"""
            val url = PATHFINDER_URL.toHttpUrl().newBuilder()
                .addQueryParameter("operationName", "fetchPlaylist")
                .addQueryParameter("variables", variables)
                .addQueryParameter("extensions", extensions)
                .build()
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", USER_AGENT)
                .header("Authorization", "Bearer $token")
                .header("App-platform", "WebPlayer")
                .header("Accept", "application/json")
                .build()
            val body = Http.client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("HTTP ${response.code}")
                response.body?.string().orEmpty()
            }
            val content = json.parseToJsonElement(body).jsonObject["data"]?.jsonObject
                ?.get("playlistV2")?.jsonObject?.get("content")?.jsonObject
                ?: error("Spotify continuation response was incomplete")
            val total = content["totalCount"]?.jsonPrimitive?.content?.toIntOrNull()
                ?: error("Spotify continuation response did not include the playlist total")
            if (offset >= total) break
            val items = content["items"]?.jsonArray
                ?: error("Spotify continuation page did not include track entries")
            if (items.isEmpty()) {
                error("Spotify stopped returning tracks at $offset of $total. Import was not completed.")
            }
            val previousOffset = offset
            for (item in items) {
                val data = item.jsonObject["itemV2"]?.jsonObject?.get("data")?.jsonObject ?: continue
                val title = data["name"]?.jsonPrimitive?.content?.trim().orEmpty()
                if (title.isEmpty()) continue
                val artistNames = data.spotifyArtistNames()
                val artist = artistNames.takeIf { it.isNotEmpty() }?.joinToString(", ")
                    ?: data.spotifyArtistCredit()
                out.add(SpotifyImportTrack(
                    title = title,
                    artist = artist,
                    durationMs = data.spotifyDurationMs(),
                    album = data.spotifyAlbumName(),
                    spotifyId = data.spotifyTrackId(),
                    leadArtist = artistNames.firstOrNull()
                        ?: artist.substringBefore(",").trim().takeIf { it.isNotBlank() },
                    artistCredits = artistNames,
                ))
            }
            offset += items.size
            if (offset <= previousOffset) {
                error("Spotify continuation did not advance; refusing an incomplete playlist import.")
            }
            if (offset >= total) break
        }
        return out
    }

    /**
     * Resolves a list of Spotify tracks to full Song objects using Innertube search.
     * Optionally filters or prioritizes matches by specified [language].
     * Reports real-time progress via [onProgress].
     */
    suspend fun resolveToSongs(
        tracks: List<SpotifyImportTrack>,
        language: String? = null,
        onProgress: (completed: Int, total: Int) -> Unit,
    ): Pair<List<Song>, List<SpotifyImportTrack>> = coroutineScope {
        // Spotify can repeat entries in its page payload; normalize before resolving.
        val uniqueTracks = distinctSpotifyImportTracks(tracks)
        val total = uniqueTracks.size
        val completedCount = AtomicInteger(0)
        val semaphore = Semaphore(3) // Keep YouTube search bursts below the rate-limit threshold.

        val cleanLang = language?.trim()?.takeIf {
            !it.equals("No Preference", ignoreCase = true) &&
            !it.equals("Multilingual", ignoreCase = true) &&
            it.isNotBlank()
        }

        val knownLanguages = listOf(
            "Tamil", "Telugu", "Kannada", "Malayalam", "Hindi", "English",
            "Punjabi", "Marathi", "Bengali", "Bhojpuri", "Gujarati", "Urdu",
            "Arabic", "Japanese", "Korean", "Mandarin", "Cantonese", "Chinese",
            "Spanish", "French", "Portuguese", "Italian", "German", "Russian",
            "Turkish", "Thai", "Indonesian", "Javanese", "Sundanese",
        )

        val deferredResults = uniqueTracks.map { track ->
            async(Dispatchers.IO) {
                semaphore.withPermit {
                    val target = TrackMatcher.Target(
                        title = track.title,
                        artist = track.artist,
                        durationSec = track.durationMs?.takeIf { it > 0 }?.div(1000)?.toInt(),
                        album = track.album,
                        requireSharedArtist = true,
                        requiredArtistName = track.leadArtist
                            ?: track.artist.substringBefore(",").trim().takeIf { it.isNotBlank() },
                        requireExactTitle = true,
                        artistCredits = track.artistCredits,
                    )
                    val candidates = try {
                        searchCandidates(target, cleanLang).let { found ->
                            if (cleanLang == null) found else {
                                val conflictingLangs = knownLanguages.filter { !it.equals(cleanLang, ignoreCase = true) }
                                found.filter { candidate ->
                                    val meta = "${candidate.title} ${candidate.artist} ${candidate.albumName.orEmpty()}".lowercase()
                                    !conflictingLangs.any {
                                        meta.contains("(${it.lowercase()})") ||
                                            meta.contains("${it.lowercase()} version") ||
                                            meta.contains("${it.lowercase()} song")
                                    }
                                }
                            }
                        }
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        DebugLog.w(
                            "SpotifyImport",
                            "Lookup failed for '${track.title}' by '${track.artist}': ${failure.message}",
                            failure,
                        )
                        // One unavailable search must not abort the entire
                        // playlist import. This Spotify row stays retryable.
                        emptyList()
                    }
                    // Never import the search engine's first row as a fallback:
                    // a popular cover/remix with a similar title is worse than
                    // leaving this Spotify entry unmatched for the user to review.
                    val matchedSong = bestSpotifyImportMatch(candidates, target)

                    val done = completedCount.incrementAndGet()
                    onProgress(done, total)

                    if (matchedSong != null) {
                        Pair(matchedSong, null)
                    } else {
                        Pair(null, track)
                    }
                }
            }
        }

        val results = deferredResults.awaitAll()
        // Different Spotify entries may resolve to the same YouTube upload.
        val seenVideoIds = HashSet<String>()
        val songs = results.mapNotNull { it.first }
            .filter { it.videoId.isNotBlank() && seenVideoIds.add(it.videoId) }
        val unmatched = distinctSpotifyImportTracks(results.mapNotNull { it.second })

        Pair(songs, unmatched)
    }
}


/**
 * Once one query produced a high-confidence match, allow one additional
 * independent query to compare alternate catalogue releases, then stop.
 */
internal fun shouldStopSpotifyQueryExpansion(
    firstStrongMatchQueryIndex: Int?,
    currentQueryIndex: Int,
    hasHighConfidenceMatch: Boolean,
): Boolean = hasHighConfidenceMatch &&
    firstStrongMatchQueryIndex != null &&
    currentQueryIndex > firstStrongMatchQueryIndex

/** Converts playable rows from both mixed and filtered YouTube Music search pages. */
internal fun spotifyImportCandidate(row: SearchResult): Song? = when (row) {
    is SearchResult.Track -> row.song
    is SearchResult.TopTrack -> row.song
    is SearchResult.Browse -> null
}

/** Structured Spotify credits, or a conservative display-line fallback for old callers. */
internal fun spotifyImportArtistCredits(target: TrackMatcher.Target): List<String> =
    target.artistCredits.ifEmpty {
        TrackMatcher.artistNames(target.artist).map { it.joinToString(" ") }
    }.map(String::trim).filter(String::isNotBlank).distinct()

/** Album cards can provide a second path to a track hidden from global song results. */
internal fun spotifyImportAlbumBrowseId(row: SearchResult): String? {
    val item = (row as? SearchResult.Browse)?.item ?: return null
    if (item.type != BrowseType.ALBUM) return null
    return item.browseId.takeIf { it.isNotBlank() }
}

/** Artist cards are used only when the complete requested performer matches. */
internal fun spotifyArtistBrowseId(row: SearchResult, expectedArtist: String?): String? {
    val item = (row as? SearchResult.Browse)?.item ?: return null
    if (item.type != BrowseType.ARTIST) return null
    val expected = expectedArtist?.takeIf { it.isNotBlank() } ?: return null
    return item.browseId.takeIf { TrackMatcher.sameArtistIdentity(expected, item.title) }
}

/** A matching song row can expose the artist page id even without an artist card. */
internal fun spotifyArtistBrowseId(song: Song, expectedArtist: String?): String? {
    val expected = expectedArtist?.takeIf { it.isNotBlank() } ?: return null
    // Search rows may expose browse ids for more than the first credited singer.
    song.artists.firstOrNull { artist ->
        artist.browseId?.isNotBlank() == true && TrackMatcher.sameArtistIdentity(expected, artist.name)
    }?.browseId?.takeIf { it.isNotBlank() }?.let { return it }
    val browseId = song.artistId?.takeIf { it.isNotBlank() } ?: return null
    val lead = song.artists.firstOrNull()?.name?.takeIf { it.isNotBlank() } ?: song.artist
    return browseId.takeIf { TrackMatcher.sameArtistIdentity(expected, lead) }
}

/**
 * The only permitted composer/uploader fallback: a non-video row whose runtime
 * is within one second, and whose release does not contradict Spotify when
 * both catalogues expose an album. It remains a last resort after credited
 * audio and credited music-video rows have been considered.
 */
internal fun isSafeSpotifyDurationOnlyFallback(
    candidate: Song,
    target: TrackMatcher.Target,
): Boolean {
    if (candidate.isVideo || TrackMatcher.hasTrustedArtistCredit(candidate, target)) return false
    if (!TrackMatcher.withinSeconds(candidate, target, 1)) return false
    val targetAlbum = target.album?.takeIf { it.isNotBlank() }
    val candidateAlbum = candidate.albumName?.takeIf { it.isNotBlank() }
    if (targetAlbum != null && candidateAlbum != null &&
        !TrackMatcher.hasExactAlbumMatch(targetAlbum, candidateAlbum)
    ) return false
    // Deliberately ignore the untrusted catalogue byline only for this
    // isolated fallback check. Title/version, runtime, release and explicit
    // metadata still pass through the normal matcher; this helper is called
    // only after all credited audio and video rows have been checked.
    val identityCandidate = candidate.copy(
        artist = target.requiredArtistName?.takeIf { it.isNotBlank() } ?: target.artist,
        artists = emptyList(),
    )
    return TrackMatcher.score(identityCandidate, target) != null
}

/** Prefer a credited audio catalogue recording over a weaker duration-only fallback. */
internal fun bestSpotifyImportMatch(candidates: List<Song>, target: TrackMatcher.Target): Song? {
    val audio = candidates.filterNot { it.isVideo }
    val videos = candidates.filter { it.isVideo }
    val creditedAudio = audio.filter { TrackMatcher.hasTrustedArtistCredit(it, target) }
    val creditedVideos = videos.filter { TrackMatcher.hasTrustedArtistCredit(it, target) }
    val durationOnlyAudio = audio.filter { isSafeSpotifyDurationOnlyFallback(it, target) }

    return TrackMatcher.best(creditedAudio, target)
        ?: TrackMatcher.best(creditedVideos, target)
        ?: TrackMatcher.best(durationOnlyAudio, target)
}

/**
 * Query both Spotify's original spelling and TrackMatcher's normalized form.
 *
 * Manual Search receives the title/artist text the listener types. Import used
 * to search only the stripped title generated by TrackMatcher; a packaging
 * suffix, transliteration, or unusual DJ/language label could therefore change
 * the query enough for YouTube Music to return a different result set.
 */
internal fun spotifyImportSearchQueries(target: TrackMatcher.Target): List<String> {
    val normalized = TrackMatcher.queries(target)
    val rawTitle = target.title.trim()
    val fullArtist = target.artist.trim()
    val leadArtist = target.requiredArtistName?.trim().orEmpty()
    val album = target.album?.trim().orEmpty()

    return buildList {
        // Match the simplest manual Search first. Adding an artist or album
        // can change YouTube Music's ranking enough to bury a track that is
        // plainly visible when the listener searches by title alone.
        if (rawTitle.isNotBlank()) add(rawTitle)
        // Then progressively add Spotify's structured performer/release data.
        if (rawTitle.isNotBlank() && leadArtist.isNotBlank()) add("$rawTitle $leadArtist")
        if (rawTitle.isNotBlank() && fullArtist.isNotBlank()) add("$rawTitle $fullArtist")
        // Album-qualified variants help when the global title query ranks an
        // unrelated cover above the exact regional/album catalogue entry.
        if (rawTitle.isNotBlank() && leadArtist.isNotBlank() && album.isNotBlank()) {
            add("$rawTitle $leadArtist $album")
        }
        if (rawTitle.isNotBlank() && album.isNotBlank()) add("$rawTitle $album")
        if (rawTitle.isNotBlank()) {
            target.artistCredits.take(3).forEach { credit ->
                if (credit.isNotBlank()) add("$rawTitle $credit")
            }
            add(rawTitle)
        }
        addAll(normalized)
        if (album.isNotBlank() && normalized.firstOrNull() != null) {
            add("${normalized.first()} $album")
        }
    }
        .map { it.replace(Regex("\\s+"), " ").trim() }
        .filter { it.isNotBlank() }
        .distinct()
}

internal fun distinctSpotifyImportTracks(tracks: List<SpotifyImportTrack>): List<SpotifyImportTrack> =
    tracks.distinctBy { track ->
        track.spotifyId?.trim()?.takeIf { it.isNotEmpty() }?.let { "spotify:$it" }
            ?: listOf(
                track.title.normalizedImportKey(),
                track.artist.normalizedImportKey(),
                track.durationMs?.toString().orEmpty(),
                track.album?.normalizedImportKey().orEmpty(),
            ).joinToString("|")
    }

private fun JsonObject.spotifyTrackId(): String? {
    val raw = sequenceOf("uri", "id").mapNotNull { key ->
        this[key]?.let { runCatching { it.jsonPrimitive.content }.getOrNull() }
    }.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    return raw.substringAfterLast(':').substringAfterLast('/').takeIf { it.isNotBlank() }
}

private fun JsonObject.spotifyArtistNames(): List<String> {
    val artists = this["artists"] ?: return emptyList()
    val items = runCatching { artists.jsonArray }.getOrNull()
        ?: runCatching { artists.jsonObject["items"]?.jsonArray }.getOrNull()
        ?: return emptyList()
    return items.mapNotNull { element ->
        runCatching {
            val artist = element.jsonObject
            val profile = artist["profile"]?.jsonObject
            (artist["name"] ?: profile?.get("name"))?.jsonPrimitive?.content?.trim()
        }.getOrNull()?.takeIf { it.isNotBlank() }
    }.distinct()
}

private fun JsonObject.spotifyArtistCredit(): String {
    val subtitle = this["subtitle"]?.let {
        runCatching { it.jsonPrimitive.content.trim() }.getOrNull()
    }
    if (!subtitle.isNullOrBlank()) return subtitle
    return spotifyArtistNames().joinToString(", ")
}

private fun JsonObject.spotifyDurationMs(): Long? {
    val value = this["durationMs"] ?: this["duration_ms"] ?: this["duration"] ?: return null
    return runCatching { value.jsonPrimitive.longOrNull }.getOrNull()
        ?: runCatching {
            val duration = value.jsonObject
            (duration["totalMilliseconds"] ?: duration["milliseconds"] ?: duration["ms"])
                ?.jsonPrimitive?.longOrNull
        }.getOrNull()
        ?: runCatching {
            value.jsonObject["total_seconds"]?.jsonPrimitive?.longOrNull?.times(1000)
        }.getOrNull()
}

private fun JsonObject.spotifyAlbumName(): String? {
    val value = this["albumName"] ?: this["album"] ?: this["albumOfTrack"] ?: return null
    return runCatching { value.jsonPrimitive.content.trim().takeIf { it.isNotBlank() } }.getOrNull()
        ?: runCatching {
            value.jsonObject["name"]?.jsonPrimitive?.content?.trim()?.takeIf { it.isNotBlank() }
        }.getOrNull()
}

private fun String.normalizedImportKey(): String =
    lowercase().replace(Regex("[ \\t\\n]+"), " ").trim()
