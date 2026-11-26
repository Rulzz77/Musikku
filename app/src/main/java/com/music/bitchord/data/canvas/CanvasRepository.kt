package com.music.bitchord.data.canvas

import com.music.bitchord.data.DebugLog as Log
import com.music.bitchord.data.model.Song
import com.music.bitchord.data.settings.AppSettings
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Finds the looping video that belongs behind a track's or a release's cover
 * art — Spotify's Canvas, Apple's motion artwork.
 *
 * Four independent sources that cover genuinely
 * different ground rather than being four routes to the same catalogue:
 * Apple has the most, Tidal has square covers on a lot of what Apple misses,
 * the community index is the only one that reaches back catalogue, and
 * Spotify has the original Canvas but needs the listener's own session
 * cookie to reach (see [SpotifyCanvas]) and is a free no-op without one.
 * Spotify goes last by default even once it's set up: it's the heaviest of the
 * four to reach (an offscreen WebView, not just a request) and the other three
 * between them already cover most of what it would have answered. The Spotify
 * integration setting can deliberately put it first when its original Canvas
 * is more important to the listener than that lookup cost.
 *
 * Every one of them is a public endpoint belonging to someone else, reached
 * without an account, and all of them will confidently answer a search with
 * the wrong record. So the shape of this is: ask, then re-check the answer
 * against what was asked for ([CanvasArtwork.matches]), and treat any failure
 * — network, parse, mismatch — as simply no canvas. The still art is always
 * underneath, so nothing here can break the player or the album page.
 *
 * Results are cached, misses included: nothing having a canvas is the common
 * case, and without negative caching every revisit would pay for three
 * lookups again to learn the same thing.
 */
object CanvasRepository {

    private const val TAG = "CanvasRepository"
    private const val CACHE_SIZE = 64

    /**
     * A settled answer for one track or release.
     *
     * [withAlbum] records whether the album name was known when this was
     * worked out. It is the one thing that can turn a miss into a hit later:
     * the album is what makes the catalogue searches land, and on the player
     * it resolves a beat after the track starts. A miss reached without it is
     * therefore provisional; everything else is final.
     */
    private class Entry(val artwork: CanvasArtwork?, val withAlbum: Boolean)

    private val cache = object : LinkedHashMap<String, Entry>(CACHE_SIZE, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Entry>) =
            size > CACHE_SIZE
    }

    // The catalogue providers are independent. Give the fast public sources
    // their own IO workers so one stalled endpoint cannot hold up the others.
    // This scope is process-local: cancelling a song lookup cancels its sibling
    // jobs without tying network work to a transient Compose screen.
    private val lookupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * The canvas for [song], or null when there isn't one. Never throws.
     *
     * A local file with no catalogue identity (no [Song.videoId]) is answered
     * as a miss without a request — there is nothing to search on.  Downloaded
     * tracks carry a videoId and full metadata, so they get the same canvas
     * lookup as streaming ones; network guards live in the caller
     * ([NowPlayingScreen], which checks [AppSettings.canvasOverCellular]).
     */
    suspend fun canvasFor(song: Song): CanvasArtwork? {
        // Only skip when there is no catalogue identity to search on.
        if (song.videoId.isBlank() && (song.localUri != null || song.localPath != null)) return null

        val title = song.title.cleaned()
        val artist = song.artist.cleaned()
        if (title.isBlank() || artist.isBlank()) return null

        // Keyed on the track alone. The album is deliberately not part of
        // this: it arrives after the player opens, and keying on it made the
        // late arrival look like a different question and run the whole chain
        // a second time. [reusable] decides when the earlier answer still
        // stands instead.
        val album = song.albumName
        val spotifyFirst = AppSettings.prioritizeSpotifyCanvas.value
        val key = cacheKey("song|${song.videoId}", spotifyFirst)

        return resolve(key, album != null) {
            val matchesTrack: (CanvasArtwork) -> Boolean = { it.matches(title, artist, album) }
            if (spotifyFirst) {
                // Respect an explicit Spotify-first preference. This path is
                // intentionally sequential because Spotify needs a WebView token.
                firstHit(
                    { SpotifyCanvas.search(title, artist, album) },
                    { AppleMusicCanvas.search(title, artist, album) },
                    { TidalCanvas.search(title, artist, album) },
                    { CommunityCanvas.search(title, artist, album) },
                    accept = matchesTrack,
                )
            } else {
                // Apple, Tidal and the community index do not depend on one
                // another. Race these three; only fall back to Spotify when
                // none returns a verified match.
                firstHitParallel(
                    { AppleMusicCanvas.search(title, artist, album) },
                    { TidalCanvas.search(title, artist, album) },
                    { CommunityCanvas.search(title, artist, album) },
                    accept = matchesTrack,
                ) ?: firstHit(
                    { SpotifyCanvas.search(title, artist, album) },
                    accept = matchesTrack,
                )
            }
        }
    }

    /**
     * A canvas already worked out for [song], without going near the network.
     *
     * Lets a caller paint what it knows before it starts waiting on anything —
     * reopening the player on a track resolved a minute ago should not go
     * through the settling delay again to arrive back at the same clip.
     */
    fun cached(song: Song): CanvasArtwork? {
        val key = cacheKey(
            base = "song|${song.videoId}",
            spotifyFirst = AppSettings.prioritizeSpotifyCanvas.value,
        )
        return synchronized(cache) { cache[key]?.artwork }
    }

    /**
     * The canvas for a release, for the album page's header artwork.
     *
     * A separate lookup rather than the first track's: the services hang
     * motion artwork off the album, so asking for it directly is both fewer
     * requests and a better match than picking a song and hoping it sits on
     * the right edition.
     */
    suspend fun canvasForAlbum(album: String, artist: String): CanvasArtwork? {
        val name = album.cleaned()
        val credit = artist.cleaned()
        if (name.isBlank() || credit.isBlank()) return null

        val spotifyFirst = AppSettings.prioritizeSpotifyCanvas.value
        return resolve(cacheKey("album|$name|$credit", spotifyFirst), withAlbum = true) {
            val matchesAlbum: (CanvasArtwork) -> Boolean = { it.matches(name, credit, name) }
            if (spotifyFirst) {
                firstHit(
                    { SpotifyCanvas.searchAlbum(name, credit) },
                    { AppleMusicCanvas.searchAlbum(name, credit) },
                    { TidalCanvas.searchAlbum(name, credit) },
                    { CommunityCanvas.searchAlbum(name, credit) },
                    accept = matchesAlbum,
                )
            } else {
                firstHitParallel(
                    { AppleMusicCanvas.searchAlbum(name, credit) },
                    { TidalCanvas.searchAlbum(name, credit) },
                    { CommunityCanvas.searchAlbum(name, credit) },
                    accept = matchesAlbum,
                ) ?: firstHit(
                    { SpotifyCanvas.searchAlbum(name, credit) },
                    accept = matchesAlbum,
                )
            }
        }
    }

    /** Priority is part of the question, so a toggle never reuses the other order's answer. */
    private fun cacheKey(base: String, spotifyFirst: Boolean): String =
        "$base|spotifyFirst=$spotifyFirst"

    private suspend fun resolve(
        key: String,
        withAlbum: Boolean,
        lookUp: suspend () -> CanvasArtwork?,
    ): CanvasArtwork? {
        synchronized(cache) {
            cache[key]?.let { if (it.reusable(withAlbum)) return it.artwork }
        }
        // Do not serialize different tracks behind one slow lookup. Cache
        // access itself stays synchronized; provider IO is isolated below.
        val found = lookUp()
        synchronized(cache) { cache[key] = Entry(found, withAlbum) }
        return found
    }

    /**
     * Whether this answer can stand in for a lookup that now knows [withAlbum].
     *
     * A hit is a hit — the album could only have confirmed it. A miss stands
     * too, unless it was reached blind and there is now an album name to try,
     * which is the one case worth spending a second round of requests on.
     */
    private fun Entry.reusable(withAlbum: Boolean): Boolean =
        artwork != null || this.withAlbum || !withAlbum

    /**
     * The first source that answers with something that survives [accept].
     *
     * Sources are passed unevaluated so each is only reached — and only paid
     * for — if the ones before it came up empty. One that throws is treated as
     * one that found nothing: none of these hosts are ours, and a missing
     * canvas is not worth surfacing as an error.
     */
    private suspend fun firstHit(
        vararg sources: suspend () -> CanvasArtwork?,
        accept: (CanvasArtwork) -> Boolean,
    ): CanvasArtwork? {
        for (source in sources) {
            checkedHit(source, accept)?.let { return it }
        }
        return null
    }

    /**
     * Searches independent public catalogues concurrently. The first verified
     * result wins; unfinished siblings are cancelled so a slow provider does
     * not delay the visible Canvas. Each HTTP call also has a short hard
     * timeout, so a cancelled blocking provider cannot occupy an IO worker long.
     */
    private suspend fun firstHitParallel(
        vararg sources: suspend () -> CanvasArtwork?,
        accept: (CanvasArtwork) -> Boolean,
    ): CanvasArtwork? {
        if (sources.isEmpty()) return null
        val results = Channel<CanvasArtwork?>(capacity = sources.size)
        val pending = sources.map { source ->
            lookupScope.launch {
                results.send(checkedHit(source, accept))
            }
        }
        try {
            repeat(sources.size) {
                val found = results.receive()
                if (found != null) return found
            }
            return null
        } finally {
            // Stop outstanding provider work as soon as a match is found or
            // the caller leaves. Closing the channel also frees suspended senders.
            pending.forEach { it.cancel() }
            results.close()
        }
    }

    private suspend fun checkedHit(
        source: suspend () -> CanvasArtwork?,
        accept: (CanvasArtwork) -> Boolean,
    ): CanvasArtwork? {
        return try {
            val found = source() ?: return null
            if (!accept(found)) {
                Log.d(TAG, "rejected '${found.title}' by '${found.artist}'")
                null
            } else {
                found
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            Log.d(TAG, "source failed: ${failure.message}")
            null
        }
    }

    /**
     * YouTube Music titles carry packaging the catalogue services never see —
     * "| Official Video", bracketed tags, "(Lyrical)". Searching with it finds
     * nothing and matching against it rejects everything, so it comes off
     * before either. Same treatment as the lyrics lookup gives it.
     */
    private fun String.cleaned(): String = replace(NOISE, " ")
        .substringBefore(" | ")
        .replace(Regex("\\s+"), " ")
        .trim()
        .ifBlank { this }

    private val NOISE = Regex(
        """\((?:from|official|lyrical|video|audio)[^)]*\)|\[[^]]*]|""" +
            """\b(?:official (?:video|audio|music video)|lyrical|full song|4k video)\b""",
        RegexOption.IGNORE_CASE,
    )
}
