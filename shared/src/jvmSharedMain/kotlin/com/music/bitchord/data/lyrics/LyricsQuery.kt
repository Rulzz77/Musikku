package com.music.bitchord.data.lyrics

/**
 * A YouTube title, as a lyrics database would have indexed it.
 *
 * Every source here but [SimpMusicLyrics] is asked for a name, and the name
 * this app has is YouTube's, which is not the name anyone catalogued. "Dracula
 * (feat. JENNIE)" is filed by Apple, LRCLIB and everyone else as "Dracula", and
 * asked for verbatim it misses all of them — which is exactly how a track ends
 * up answered by whichever source happened to clean the title on its own
 * ([PaxSenix] was the only one that did) regardless of the order the user put
 * their sources in.
 *
 * ### What is taken off, and what is deliberately left on
 *
 * Only credits and packaging: who else is on the record, and how the upload was
 * labelled. Those are not part of the recording's name anywhere.
 *
 * Anything that names a *different recording* stays — "(Remix)", "(Acoustic)",
 * "(Live)", "(Remastered 2011)", "(Sped Up)". Those look like the same kind of
 * bracket and are the opposite: stripping them turns a search for one recording
 * into a search for another, and the lyrics that come back are confidently
 * wrong rather than merely missing. A miss is recoverable; the wrong words
 * scrolling in time with the right song is not.
 */
fun String.forLyricsSearch(): String {
    var name = this
    CREDITS.forEach { pattern -> name = pattern.replace(name, " ") }
    return name.replace(WHITESPACE, " ").trim().trimEnd(',', '-', '–', '—').trim()
        // A title that was *only* packaging is no title at all; better to ask
        // with what we were given than with nothing.
        .ifBlank { trim() }
}

/**
 * Trims " - Topic" off an auto-generated channel name.
 *
 * YouTube's own artist channels for licensed music are named this way, and it
 * reaches the player as the artist on anything played from one.
 */
fun String.artistForLyricsSearch(): String =
    removeSuffix(" - Topic").trim().ifBlank { trim() }

private val WHITESPACE = Regex("""\s+""")

private val CREDITS = listOf(
    // Bracketed credits: (feat. X), [ft. X], (with X).
    Regex("""\s*[(\[]\s*(feat|ft|featuring|with)\b[^)\]]*[)\]]""", RegexOption.IGNORE_CASE),
    // The same, unbracketed and running to the end of the title.
    Regex("""\s+(feat|ft|featuring)\.?\s+.*$""", RegexOption.IGNORE_CASE),
    // How the upload was labelled, not what was recorded.
    Regex(
        """\s*[(\[]\s*(official\s*)?(music\s*)?""" +
            """(video|audio|visuali[sz]er|lyrics?\s*video|lyrics?|m/?v|hd|hq|4k|full\s*song)""" +
            """\s*[)\]]""",
        RegexOption.IGNORE_CASE,
    ),
    Regex("""\s*[(\[]\s*official\s*[)\]]""", RegexOption.IGNORE_CASE),
)

/**
 * Reject a lyrics catalogue hit unless it names the same title and at least
 * one of the credited artists. A close runtime alone is never enough: common
 * titles routinely return a different recording or cover.
 *
 * [candidateDurationMs] may be absent for providers that do not publish a
 * runtime. When both sides have one, allow a small service-specific rounding
 * tolerance (and a little extra for video runtimes) before accepting the hit.
 */
internal fun lyricsCandidateMatches(
    title: String,
    artist: String,
    durationMs: Long,
    candidateTitle: String?,
    candidateArtist: String?,
    candidateDurationMs: Long?,
    durationToleranceMs: Long = 12_000L,
): Boolean {
    val wantedTitle = lyricsIdentity(title.forLyricsSearch())
    val foundTitle = lyricsIdentity(candidateTitle.orEmpty().forLyricsSearch())
    if (wantedTitle.isBlank() || wantedTitle != foundTitle) return false

    val wantedArtists = artistNamesForLyrics(artist.artistForLyricsSearch())
    val foundArtists = artistNamesForLyrics(candidateArtist.orEmpty().artistForLyricsSearch())
    if (wantedArtists.isEmpty() || foundArtists.isEmpty() || wantedArtists.intersect(foundArtists).isEmpty()) {
        return false
    }

    if (durationMs > 0L && (candidateDurationMs ?: 0L) > 0L) {
        val allowed = maxOf(durationToleranceMs, durationMs / 40L)
        if (kotlin.math.abs(durationMs - candidateDurationMs!!) > allowed) return false
    }
    return true
}

private fun lyricsIdentity(value: String): String =
    java.text.Normalizer.normalize(value, java.text.Normalizer.Form.NFD)
        .replace(Regex("""\\p{Mn}+"""), "")
        .lowercase(java.util.Locale.ROOT)
        .map { if (it.isLetterOrDigit()) it else ' ' }
        .joinToString("")
        .replace(Regex("""\\s+"""), " ")
        .trim()

private fun artistNamesForLyrics(value: String): Set<String> =
    value.split(
        Regex("""\\s*(?:,|&|;|/|\\s+and\\s+|\\s+x\\s+|\\s+with\\s+|\\s+feat\\.?\\s+|\\s+ft\\.?\\s+)\\s*"""),
    ).map(::lyricsIdentity).filter(String::isNotBlank).toSet()
