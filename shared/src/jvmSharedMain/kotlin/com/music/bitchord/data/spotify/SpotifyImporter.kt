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
import kotlinx.coroutines.sync.Semaphore
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
        val source = SpotifyImportTrack(
            title = track.title,
            artist = track.artist,
            durationMs = track.durationMs.takeIf { it > 0 }?.toLong(),
            album = track.album,
            spotifyId = track.id,
            leadArtist = track.leadArtist,
            artistCredits = track.artistCredits,
        )
        return LinerSpotifyMatcher.evaluate(source, searchCandidates(source)).track
    }

    /**
     * Liner Desktop's actual import order, not its interactive search UI:
     * track(query) -> all(query) when confidence is insufficient ->
     * track(clean title) when it differs -> video(query) if still unmatched.
     * Each stage is one raw InnerTube request and candidates are re-scored as
     * a merged set, including Liner's ambiguity check.
     */
    private suspend fun searchCandidates(
        source: SpotifyImportTrack,
        suffix: String? = null,
    ): List<Song> {
        val query = LinerSpotifyMatcher.searchQuery(source)
        val cleanTitle = LinerSpotifyMatcher.cleanedTitle(source)
        val failures = mutableListOf<String>()
        var candidates = emptyList<Song>()
        var decision: LinerSpotifyMatcher.Decision? = null

        suspend fun search(
            searchQuery: String,
            kind: YtMusicRepository.SpotifyImportSearchKind,
        ): List<Song> {
            if (searchQuery.isBlank()) return emptyList()
            return YtMusicRepository.searchSpotifyImportRaw(searchQuery, kind).fold(
                onSuccess = { it },
                onFailure = { failure ->
                    if (failure is CancellationException) throw failure
                    failures += "${kind.name.lowercase()} search '$searchQuery': ${failure.message}"
                    emptyList()
                },
            )
        }

        suspend fun attempt(
            searchQuery: String,
            kind: YtMusicRepository.SpotifyImportSearchKind,
        ) {
            val extra = search(searchQuery, kind)
            if (extra.isEmpty()) return
            val combined = LinkedHashMap<String, Song>()
            (candidates + extra).forEach { candidate ->
                val id = candidate.videoId.trim()
                if (id.isNotEmpty()) combined.putIfAbsent(id, candidate)
            }
            val nextCandidates = combined.values.toList()
            val nextDecision = LinerSpotifyMatcher.evaluate(source, nextCandidates)
            if (nextDecision.matched || decision == null) {
                candidates = nextCandidates
                decision = nextDecision
            }
        }

        candidates = search(query, YtMusicRepository.SpotifyImportSearchKind.TRACK)
            .distinctBy { it.videoId }
        if (candidates.isNotEmpty()) {
            decision = LinerSpotifyMatcher.evaluate(source, candidates)
        }

        if (decision?.matched != true || (decision?.score ?: Int.MIN_VALUE) < 75) {
            attempt(query, YtMusicRepository.SpotifyImportSearchKind.ALL)
        }
        if (decision?.matched != true && cleanTitle.isNotBlank() && cleanTitle != query) {
            attempt(cleanTitle, YtMusicRepository.SpotifyImportSearchKind.TRACK)
        }
        if (decision?.matched != true) {
            attempt(query, YtMusicRepository.SpotifyImportSearchKind.VIDEO)
        }

        // An explicit in-app language preference is an optional extension to
        // Liner's default query sequence; no extra language terms are used by
        // default.
        if (decision?.matched != true && !suffix.isNullOrBlank()) {
            val languageQuery = "$query $suffix".trim()
            attempt(languageQuery, YtMusicRepository.SpotifyImportSearchKind.TRACK)
            if (decision?.matched != true) {
                attempt(languageQuery, YtMusicRepository.SpotifyImportSearchKind.ALL)
            }
            if (decision?.matched != true) {
                attempt(languageQuery, YtMusicRepository.SpotifyImportSearchKind.VIDEO)
            }
        }

        if (candidates.isEmpty() && failures.isNotEmpty()) {
            throw IllegalStateException(
                "Spotify lookup incomplete: ${failures.take(3).joinToString("; ")}",
            )
        }
        if (candidates.isEmpty() && query.isNotBlank()) {
            throw IllegalStateException("Spotify lookup returned no usable YouTube Music response")
        }
        return candidates
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
        val semaphore = Semaphore(4) // Match Liner Desktop's four concurrent track lookups.

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
                    val candidates = try {
                        searchCandidates(track, cleanLang).let { found ->
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
                    // Liner's weighted evaluator rejects weak/ambiguous matches.
                    val matchedSong = LinerSpotifyMatcher.evaluate(track, candidates).track

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
    val identityTarget = target.copy(
        // The caller has already established that this row has no trusted
        // artist credit. Disable the lead-credit requirement only for the
        // isolated duration-only fallback; keep all title/version/release
        // and runtime checks in TrackMatcher.
        requiredArtistName = null,
        requireSharedArtist = true,
    )
    val identityCandidate = candidate.copy(
        artist = target.artist,
        artists = emptyList(),
    )
    return TrackMatcher.score(identityCandidate, identityTarget) != null
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
        // The strict matcher intentionally rejects an uncredited composer.
        // These rows have already passed the isolated title/version/runtime
        // guard above, so rank them by closest runtime without sending them
        // through the lead-artist matcher a second time.
        ?: durationOnlyAudio.minByOrNull { candidate ->
            val actual = TrackMatcher.secondsOf(candidate.durationText)
            val expected = target.durationSec
            if (actual != null && expected != null) {
                kotlin.math.abs(actual - expected)
            } else {
                Int.MAX_VALUE
            }
        }
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
