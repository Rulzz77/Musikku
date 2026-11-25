package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.Song
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Kotlin port of Liner Desktop's import matcher:
 * sourceProfile -> rankCandidate -> evaluateImportedTrack.
 *
 * This is intentionally separate from TrackMatcher. TrackMatcher serves
 * playback-source identity rules across the whole app; Spotify import needs
 * the same confidence scoring and ambiguity decisions as Liner's importer.
 */
internal object LinerSpotifyMatcher {

    data class Decision(
        val track: Song? = null,
        val score: Int? = null,
        val reason: String? = null,
        val proposedTrack: Song? = null,
    ) {
        val matched: Boolean get() = track != null
    }

    private data class VersionComparison(
        val matches: Boolean,
        val penalty: Int,
        val bonus: Int,
    )

    private data class RankedCandidate(
        val track: Song,
        val score: Int,
        val deltaMs: Long?,
        val disqualified: Boolean,
        val titleExact: Boolean,
        val titleRatio: Int,
        val artistExact: Boolean,
        val artistRatio: Int,
        val titleClean: String,
        val primaryArtist: String,
        val versionMatches: Boolean,
        val artistConflict: Boolean,
    )

    private data class ParsedArtistTitle(
        val artist: String?,
        val title: String,
    )

    private data class SourceMetadata(
        val artist: String,
        val title: String,
        val versionTags: Set<String>,
        val searchQuery: String,
    )

    // Colon is common inside real song titles (for example "Voor Dilan #III: ...").
    // Only split candidate titles on separators commonly used for artist/title layouts.
    private val titleDelimiter = Regex("""\s*[-–—|~]\s*""")
    private val versionPatterns = listOf(
        "remix" to Regex("""\b(remix(?:ed)?|ремикс|rmx)\b""", RegexOption.IGNORE_CASE),
        "vip" to Regex("""\b(vip|v\.i\.p\.?)\b""", RegexOption.IGNORE_CASE),
        "flip" to Regex("""\b(flip|флип)\b""", RegexOption.IGNORE_CASE),
        "bootleg" to Regex("""\b(bootleg|бутлег)\b""", RegexOption.IGNORE_CASE),
        "mashup" to Regex("""\b(mash\s*up|мэшап|мешап)\b""", RegexOption.IGNORE_CASE),
        "edit" to Regex("""\b((?:radio|club|extended)?\s*edit|эдит)\b""", RegexOption.IGNORE_CASE),
        "slowed" to Regex("""\b(slowed(?:\s*(?:\+|&|and)\s*reverb)?|слоу)\b""", RegexOption.IGNORE_CASE),
        "reverb" to Regex("""\b(reverb|реверб)\b""", RegexOption.IGNORE_CASE),
        "sped_up" to Regex("""\b(sp(?:ed|eed)\s*up|sp(?:ed|eed)up|спид\s*ап|спидап)\b""", RegexOption.IGNORE_CASE),
        "nightcore" to Regex("""\b(nightcore|найткор)\b""", RegexOption.IGNORE_CASE),
        "instrumental" to Regex("""\b(instrumental|инструментал|inst\b\.?)\b""", RegexOption.IGNORE_CASE),
        "acoustic" to Regex("""\b(acoustic|акустика)\b""", RegexOption.IGNORE_CASE),
        "live" to Regex("""\b(live(?:\s+at[^)]+)?|лайв|концерт)\b""", RegexOption.IGNORE_CASE),
        "bass_boosted" to Regex("""\b(bass\s*boost(?:ed)?|басс\s*буст)\b""", RegexOption.IGNORE_CASE),
    )

    private val junkPatterns = listOf(
        Regex("""\.(?:mp3|wav|flac|m4a|aac|ogg)\b""", RegexOption.IGNORE_CASE),
        Regex("""(?:\(|\[|\{)?\s*(?:tgk|tg|t\.me|vk\.com|soundcloud\.com|soundcloud|instagram\.com|instagram|insta|inst|twitter\.com|x\.com)\s*[:/]?\s*[^)\]}]+(?:\)|\]|\})?""", RegexOption.IGNORE_CASE),
        Regex("""@[\w.-]+"""),
        Regex("""(?:\(|\[|\{)?\s*(?:prod(?:uced)?\s+by|beat\s+by|prod\b\.?|beat\b\.?)\s*[:/]?\s*[^)\]}]+(?:\)|\]|\})?""", RegexOption.IGNORE_CASE),
        Regex("""(?:\(|\[|\{)\s*(?:free\s*(?:dl|download)|download(?:\s*link)?|free\s*beat|link\s+in\s+(?:bio|desc(?:ription)?)|out\s+now|stream\s+now|buy\s+now|premiere|exclusive|clip\s+officiel|official\s+video|official\s+audio|official\s+music\s+video|music\s+video|lyric\s+video|visualizer|official\s+visualizer|audio\s+visualizer|og\s+version|og\s+beat|full\s+version|hq|hd|4k)[^)]*(?:\)|\]|\})""", RegexOption.IGNORE_CASE),
        Regex("""\s*(?:\(|\[|\{)\s*(?:remaster(?:ed)?(?:\s*\d{4})?|ремастеринг(?:\s*\d{4})?|deluxe(?:\s+edition)?|anniversary(?:\s+edition)?|original\s+mix|album\s+version|single\s+version|ost|soundtrack|из\s+(?:телесериала|фильма|к/ф)[^)]*)(?:\)|\]|\})""", RegexOption.IGNORE_CASE),
        Regex("""\s*[-–—|]\s*(?:out\s+now|premiere|exclusive|free\s*dl|official\s*video|visualizer|audio|remaster(?:ed)?|ремастеринг|prod\s+by[^\s]+).*$""", RegexOption.IGNORE_CASE),
        Regex("""\*+[^*]+\*+"""),
        Regex("""\(\s*\)|\[\s*\]|\{\s*\}"""),
    )

    private val junkSearchPhrases = listOf(
        "reaction", "reacts", "reacting", "first time hearing", "first time listening",
        "first time reacting", "tutorial", "how to play", "guitar lesson", "bass lesson",
        "drum lesson", "piano tutorial", "sheet music", "synthesia", "guitar tab",
        "bass tab", "drum tab", "drum cover", "guitar cover", "bass cover",
        "fingerstyle", "choreography", "dance cover", "dance practice", "dance video",
        "unboxing", "review", "podcast", "interview", "full episode", "1 hour loop",
        "10 hours", "1 hour version", "top 10", "top 20", "top 50",
        "all songs compilation", "playlist", "full album", "album stream",
        "greatest hits", "discography", "реакция", "реакции", "реакцию",
        "реагирует", "разбор", "как играть", "ноты", "обучение",
        "гитарный кавер", "бас кавер", "барабанный кавер", "интервью",
        "подкаст", "обзор", "плейлист", "полный альбом", "дискография", "все песни",
    )
    private val modifierWords = listOf(
        "nightcore", "slowed", "reverb", "sped up", "speed up",
        "bass boosted", "8d audio", "замедленная", "замедленный", "реверб",
    )

    private val knownArtistAliases = listOf(
        setOf("в цой", "виктор цой", "цой", "кино"),
        setOf("горшок", "михаил горшенев", "князь", "андрей князев", "киш", "король и шут"),
        setOf("лсп", "lsp"),
        setOf("пошлая молли", "poshlaya molly"),
        setOf("xxxmanera", "хххманера"),
        setOf("og buda", "ог буда"),
        setOf("scally milano", "скалли милано"),
        setOf("uglystephan", "аглистефан"),
        setOf("три дня дождя", "three days of rain"),
        setOf("miyagi", "мияги", "эндшпиль", "endspiel", "andy panda", "энди панда", "hajime"),
        setOf("скриптонит", "scriptonite", "gruppa skryptonite"),
        setOf("pharaoh", "фараон"),
        setOf("boulevard depo", "бульвар депо"),
        setOf("saluki", "салуки"),
        setOf("markul", "маркул"),
        setOf("oxxxymiron", "оксимирон"),
        setOf("noize mc", "нойз мс"),
        setOf("валентин стрыкало", "юрий каплан", "стрыкало"),
        setOf("serebro", "серебро"),
        setOf("tatu", "t a t u", "тату"),
        setOf("macan", "макан"),
        setOf("kizaru", "кизару"),
        setOf("big baby tape", "биг бейби тейп", "bbtape"),
        setOf("егор крид", "egor kreed"),
        setOf("morgenshtern", "моргенштерн"),
        setOf("mc doni", "doni", "дони"),
        setOf("не будите спящих", "ne budite spyashchikh"),
        setOf("дискотека авария", "diskoteka avariya"),
    )

    private val cyrillicToLatin = mapOf(
        'а' to "a", 'б' to "b", 'в' to "v", 'г' to "g", 'д' to "d",
        'е' to "e", 'ё' to "e", 'ж' to "zh", 'з' to "z", 'и' to "i",
        'й' to "y", 'к' to "k", 'л' to "l", 'м' to "m", 'н' to "n",
        'о' to "o", 'п' to "p", 'р' to "r", 'с' to "s", 'т' to "t",
        'у' to "u", 'ф' to "f", 'х' to "h", 'ц' to "ts", 'ч' to "ch",
        'ш' to "sh", 'щ' to "shch", 'ъ' to "", 'ы' to "y", 'ь' to "",
        'э' to "e", 'ю' to "yu", 'я' to "ya", 'є' to "ye", 'і' to "i",
        'ї' to "yi", 'ґ' to "g",
    )

    fun searchQuery(source: SpotifyImportTrack): String = sourceMetadata(source).searchQuery

    fun cleanedTitle(source: SpotifyImportTrack): String = sourceMetadata(source).title

    /**
     * Alternate lookup queries for tracks whose Spotify primary credit is a
     * label/channel while YouTube Music indexes the actual vocalist. The
     * matcher still evaluates every result against all structured credits;
     * these queries only widen discovery, never acceptance.
     */
    fun alternateArtistSearchQueries(source: SpotifyImportTrack): List<String> {
        val title = cleanedTitle(source)
        if (title.isBlank()) return emptyList()

        val credits = source.artistCredits.ifEmpty {
            source.artist.split(
                Regex("""\s*(?:,|&| feat\.? | ft\.? | featuring | with )\s*""", RegexOption.IGNORE_CASE),
            )
        }
        val primaryArtist = sourceMetadata(source).artist
        return credits.asSequence()
            .map(String::trim)
            .filter(String::isNotBlank)
            .filterNot { artistsMatch(it, primaryArtist) }
            .distinct()
            .take(3)
            .map { artist -> "$artist $title".replace(Regex("""\s+"""), " ").trim() }
            .distinct()
            .toList()
    }

    /**
     * True when a candidate is accepted only from the primary label/channel
     * credit while Spotify also identifies a secondary vocalist. In that case
     * search the secondary credit before finalizing the import.
     */
    fun needsSecondaryArtistSearch(source: SpotifyImportTrack, candidate: Song?): Boolean {
        val profile = buildProfile(source)
        val secondaryArtists = profile.artists.filterNot { artistsMatch(it, profile.primaryArtist) }
        if (secondaryArtists.isEmpty()) return false
        if (candidate == null) return true

        val candidateArtists = candidate.artists.map { it.name }.filter(String::isNotBlank).toMutableList()
        if (candidate.artist.isNotBlank()) candidateArtists += candidate.artist
        val titleCredits = stripJunk(candidate.title)
            .split(titleDelimiter)
            .filter(String::isNotBlank)
            .filter { part ->
                computeTitleRatio(profile, cleanBaseTitle(part), cleanBaseTitle(part)) < 80 &&
                    secondaryArtists.any { artistsMatch(it, part) }
            }
        candidateArtists += titleCredits
        return candidateArtists.none { name -> secondaryArtists.any { artistsMatch(it, name) } }
    }

    fun evaluate(source: SpotifyImportTrack, candidates: List<Song>): Decision {
        val profile = buildProfile(source)
        val ranked = candidates.map { rank(profile, it) }.sortedByDescending { it.score }
        val topRanked = ranked.firstOrNull() ?: return Decision(reason = "low_confidence_match")

        // A high-scoring bad result must not block a valid second result. Remove
        // candidates with impossible duration or explicit performer conflicts
        // before applying the normal confidence and ambiguity rules.
        val eligible = ranked.filterNot { it.disqualified || it.artistConflict }
        val best = eligible.firstOrNull() ?: return Decision(
            score = topRanked.score,
            reason = when {
                topRanked.disqualified -> "duration_mismatch"
                topRanked.artistConflict -> "artist_mismatch"
                else -> "low_confidence_match"
            },
            proposedTrack = topRanked.track,
        )
        val second = eligible.getOrNull(1)
        if (isAmbiguous(best, second)) {
            return Decision(score = best.score, reason = "ambiguous_match", proposedTrack = best.track)
        }
        val accepted = acceptedScore(best) ?: return Decision(
            score = best.score,
            reason = "low_confidence_match",
            proposedTrack = best.track,
        )
        return Decision(track = best.track, score = accepted)
    }

    fun isJunkVideo(title: String, query: String): Boolean {
        val normalizedTitle = normalizeSearchText(title)
        val normalizedQuery = normalizeSearchText(query)
        if (junkSearchPhrases.any { normalizedTitle.contains(it) && !normalizedQuery.contains(it) }) {
            return true
        }
        val userWantsModifier = modifierWords.any(normalizedQuery::contains)
        return !userWantsModifier && modifierWords.any(normalizedTitle::contains)
    }

    fun matchesQueryWell(query: String, title: String, artists: List<String>): Boolean {
        val tokens = queryTokens(query)
        if (tokens.isEmpty()) return true
        val combined = normalizeSearchText((listOf(title) + artists).joinToString(" "))
        val matched = tokens.count(combined::contains)
        val threshold = if (tokens.size <= 2) tokens.size else (tokens.size * 0.75).let { kotlin.math.ceil(it).toInt() }
        return matched >= threshold
    }

    private fun buildProfile(source: SpotifyImportTrack): SourceProfile {
        val metadata = sourceMetadata(source)
        val leadArtist = source.leadArtist?.trim()?.takeIf(String::isNotBlank)
        val artists = source.artistCredits.filter(String::isNotBlank).toMutableList()
        if (artists.isEmpty()) {
            (leadArtist ?: source.artist)
                .split(Regex("""\s*(?:,|&| feat\.? | ft\.? | featuring | with )\s*""", RegexOption.IGNORE_CASE))
                .map(String::trim)
                .filter(String::isNotBlank)
                .forEach(artists::add)
        }
        // Spotify's structured lead artist and artist objects are authoritative.
        // Never reinterpret punctuation inside the Spotify title as an artist/title pair.
        if (leadArtist != null && artists.none { artistsMatch(it, leadArtist) }) {
            artists.add(0, leadArtist)
        }
        val primaryArtist = leadArtist ?: artists.firstOrNull() ?: source.artist
        return SourceProfile(
            rawTitle = source.title,
            searchTitle = metadata.title,
            searchQuery = metadata.searchQuery,
            baseTitle = cleanBaseTitle(source.title),
            fullClean = cleanBaseTitle(source.title),
            versionTags = metadata.versionTags,
            artists = artists,
            primaryArtist = primaryArtist,
            hasTwoParts = false,
            part0Clean = "",
            part1Clean = "",
            durationMs = source.durationMs?.takeIf { it > 0 },
        )
    }

    private data class SourceProfile(
        val rawTitle: String,
        val searchTitle: String,
        val searchQuery: String,
        val baseTitle: String,
        val fullClean: String,
        val versionTags: Set<String>,
        val artists: List<String>,
        val primaryArtist: String,
        val hasTwoParts: Boolean,
        val part0Clean: String,
        val part1Clean: String,
        val durationMs: Long?,
    )

    private fun sourceMetadata(source: SpotifyImportTrack): SourceMetadata {
        val artist = (
            source.leadArtist?.takeIf(String::isNotBlank)
                ?: source.artistCredits.firstOrNull(String::isNotBlank)
                ?: source.artist
            ).trim()
        // Spotify's track title is a title, not an "Artist - Title" upload string.
        // Preserve hyphens/colons so version suffixes and colon subtitles remain searchable.
        val title = stripJunk(source.title)
        val query = if (artist.isNotBlank() && !title.startsWith(artist, ignoreCase = true)) {
            "$artist $title".trim()
        } else {
            title.trim()
        }
        return SourceMetadata(
            artist = artist,
            title = title,
            versionTags = versionTags(source.title),
            searchQuery = query.replace(Regex("""\s+"""), " "),
        )
    }

    private fun parseArtistAndTitle(rawTitle: String): ParsedArtistTitle {
        val cleaned = stripJunk(rawTitle)
        val parts = cleaned.split(titleDelimiter)
        if (parts.size >= 3 && parts[1].trim().length >= 2 && parts[2].trim().isNotEmpty()) {
            return ParsedArtistTitle(parts[1].trim(), parts.drop(2).joinToString(" - ").trim())
        }
        if (parts.size == 2 && parts[0].trim().length >= 2 &&
            parts[1].trim().isNotEmpty() && parts[0].any { !it.isDigit() && !it.isWhitespace() }
        ) {
            return ParsedArtistTitle(parts[0].trim(), parts[1].trim())
        }
        return ParsedArtistTitle(null, cleaned)
    }

    private fun stripJunk(value: String): String =
        junkPatterns.fold(value) { current, pattern -> current.replace(pattern, "") }
            .trim()
            .replace(Regex("""\s+"""), " ")

    private fun cleanBaseTitle(value: String): String {
        var result = stripJunk(value)
        result = result.replace(
            Regex("""(?:\(|\[|\{)?\s*(?:feat\.?|ft\.?|with)\s+[^)\]}]+(?:\)|\]|\})?""", RegexOption.IGNORE_CASE),
            "",
        )
        result = result.replace(
            Regex("""\s*[-–—]\s*(?:mono|stereo|remaster(?:ed)?(?:\s*\d{4})?|ремастеринг|live(?:\s+at[^)]+)?|acoustic|instrumental|radio\s+edit|single\s+version|original\s+mix|album\s+version)\b.*$""", RegexOption.IGNORE_CASE),
            "",
        )
        versionPatterns.forEach { (_, pattern) -> result = result.replace(pattern, "") }
        return normalizeTrackString(result)
    }

    private fun versionTags(value: String): Set<String> =
        versionPatterns.filter { (_, pattern) -> pattern.containsMatchIn(value) }.map { it.first }.toSet()

    private fun compareVersions(source: Set<String>, candidate: Set<String>): VersionComparison {
        if (source.isEmpty() && candidate.isEmpty()) return VersionComparison(true, 0, 5)
        if (source.isNotEmpty() && candidate.isNotEmpty()) {
            return if (source.any(candidate::contains)) VersionComparison(true, 0, 15)
            else VersionComparison(false, 50, 0)
        }
        return VersionComparison(false, 50, 0)
    }

    private fun rank(profile: SourceProfile, candidate: Song): RankedCandidate {
        val parsed = parseArtistAndTitle(candidate.title)
        val rawParts = stripJunk(candidate.title)
            .split(titleDelimiter)
            .map(String::trim)
            .filter(String::isNotBlank)
        val versions = compareVersions(profile.versionTags, versionTags(candidate.title))
        val candidateArtists = candidate.artists.map { it.name }.filter(String::isNotBlank).toMutableList()
        if (candidate.artist.isNotBlank() &&
            candidateArtists.none { it.equals(candidate.artist, ignoreCase = true) }
        ) {
            candidateArtists += candidate.artist
        }

        // YouTube catalogue titles use both "Artist - Title" and
        // "Title - Artist". Only treat a segment as an artist when it matches
        // a structured Spotify credit; arbitrary title segments are not artists.
        val embeddedArtistParts = rawParts.filter { part ->
            val partBase = cleanBaseTitle(part)
            computeTitleRatio(profile, partBase, partBase) < 80 &&
                profile.artists.any { artistsMatch(it, part) }
        }
        candidateArtists += embeddedArtistParts
        parsed.artist?.let { parsedArtist ->
            if (profile.artists.any { artistsMatch(it, parsedArtist) } &&
                candidateArtists.none { artistsMatch(it, parsedArtist) }
            ) {
                candidateArtists += parsedArtist
            }
        }

        val titleOptions = linkedSetOf<String>().apply {
            add(parsed.title)
            add(candidate.title)
            addAll(rawParts)
            val withoutEmbeddedCredits = rawParts.filterNot { it in embeddedArtistParts }
            if (withoutEmbeddedCredits.isNotEmpty() && withoutEmbeddedCredits.size < rawParts.size) {
                add(withoutEmbeddedCredits.joinToString(" "))
            }
        }
        val bestTitle = titleOptions
            .map { option ->
                val base = cleanBaseTitle(option)
                base to computeTitleRatio(profile, base, base)
            }
            .maxByOrNull { it.second }
        val candidateBase = bestTitle?.first.orEmpty()
        var titleRatio = bestTitle?.second ?: 0

        val primaryCandidate = candidateArtists.firstOrNull { artistsMatch(profile.primaryArtist, it) }
            ?: candidateArtists.firstOrNull().orEmpty()
        val artist = computeArtistScore(profile, candidateArtists, primaryCandidate)
        val inverted = computeInvertedMatch(profile, candidateBase, candidateArtists)
        var artistRatio = artist.second
        var artistExact = artist.first
        if (inverted != null) {
            titleRatio = max(titleRatio, inverted.first)
            artistRatio = max(artistRatio, inverted.second)
            artistExact = true
        }

        val hasSecondaryCredits = profile.artists.any { !artistsMatch(it, profile.primaryArtist) }
        val secondaryCreditIdentified = candidateArtists.any { candidateArtist ->
            profile.artists.any { sourceArtist ->
                !artistsMatch(sourceArtist, profile.primaryArtist) &&
                    artistsMatch(sourceArtist, candidateArtist)
            }
        }
        val primaryCreditIdentified = candidateArtists.any {
            artistsMatch(profile.primaryArtist, it)
        }
        val uncreditedBylineArtist = candidateArtists.any { candidateArtist ->
            containsUncreditedArtistName(candidateArtist, profile.artists)
        }
        val uncreditedTitleArtist = rawParts.any { possibleArtist ->
            val titlePartIsExact = rawParts.any { possibleTitle ->
                possibleTitle != possibleArtist &&
                    computeTitleRatio(
                        profile,
                        cleanBaseTitle(possibleTitle),
                        cleanBaseTitle(possibleTitle),
                    ) >= 85
            }
            titlePartIsExact &&
                looksLikePerformerSegment(possibleArtist) &&
                profile.artists.none { artistsMatch(it, possibleArtist) }
        }

        val candidateDuration = durationMs(candidate.durationText)
        val delta = if (profile.durationMs != null && candidateDuration != null) {
            kotlin.math.abs(profile.durationMs - candidateDuration)
        } else null
        // A label/channel-only byline is weaker evidence than a named credited
        // vocalist. Keep it eligible when no better result exists, but rank it
        // below a result that actually identifies a secondary Spotify credit.
        val labelOnlyPenalty = if (hasSecondaryCredits && !secondaryCreditIdentified) 12 else 0
        val score = (45.0 * titleRatio / 100.0).roundToInt() +
            (30.0 * artistRatio / 100.0).roundToInt() +
            durationScore(delta) + versions.bonus - versions.penalty - labelOnlyPenalty
        val unrelatedArtistConflict = profile.artists.isNotEmpty() &&
            candidateArtists.any { it.isNotBlank() && !isGenericArtistLabel(it) } &&
            !artistExact && artistRatio < 70 && !primaryCreditIdentified
        val conflictingVocalist = hasSecondaryCredits && !secondaryCreditIdentified &&
            (uncreditedBylineArtist || uncreditedTitleArtist)
        return RankedCandidate(
            track = candidate,
            score = score.coerceIn(0, 100),
            deltaMs = delta,
            disqualified = delta != null && delta > DISQUALIFY_DELTA_MS,
            titleExact = candidateBase == profile.baseTitle,
            titleRatio = titleRatio,
            artistExact = artistExact,
            artistRatio = artistRatio,
            titleClean = candidateBase,
            primaryArtist = primaryCandidate,
            versionMatches = versions.matches,
            artistConflict = unrelatedArtistConflict || conflictingVocalist,
        )
    }

    private fun computeTitleRatio(
        profile: SourceProfile,
        candidateBase: String,
        candidateFull: String,
    ): Int {
        var ratio = maxOf(
            bestRatio(profile.baseTitle, candidateBase),
            bestRatio(profile.fullClean, candidateFull),
            bestRatio(profile.baseTitle, candidateFull),
            bestRatio(profile.fullClean, candidateBase),
        )
        if (isNearSubstring(profile.baseTitle, candidateBase) ||
            isNearSubstring(profile.fullClean, candidateFull)
        ) {
            ratio = max(ratio, 92)
        }
        val phonetic = bestRatio(toPhoneticLatin(profile.baseTitle), toPhoneticLatin(candidateBase))
        return max(ratio, phonetic)
    }

    private fun computeArtistScore(
        profile: SourceProfile,
        candidateArtists: List<String>,
        primaryCandidate: String,
    ): Pair<Boolean, Int> {
        val secondaryMatch = candidateArtists.any { candidate ->
            profile.artists.any { sourceArtist ->
                !artistsMatch(sourceArtist, profile.primaryArtist) &&
                    artistsMatch(sourceArtist, candidate)
            }
        }
        val primaryMatch = artistsMatch(profile.primaryArtist, primaryCandidate) ||
            candidateArtists.any { artistsMatch(profile.primaryArtist, it) }
        val hasSecondaryCredits = profile.artists.any { !artistsMatch(it, profile.primaryArtist) }

        // A credited vocalist is the strongest performer evidence. A channel
        // or label matching only the lead credit is useful discovery evidence,
        // but does not prove which singer performed the recording.
        if (secondaryMatch) return true to 100
        // A primary label/artist byline is still valid evidence when the
        // catalogue omits a secondary vocalist. Keep it eligible as a fallback;
        // labelOnlyPenalty in rank() makes an explicitly credited vocalist win
        // when both candidates are available.
        if (primaryMatch) return true to 100

        val inTitle = candidateArtists.any { artist ->
            val normalized = normalizeTrackString(artist)
            normalized.length >= 3 &&
                (profile.fullClean.contains(normalized) ||
                    toPhoneticLatin(profile.rawTitle).contains(toPhoneticLatin(artist)))
        }
        if (inTitle) return true to 100

        var best = 0
        for (sourceArtist in profile.artists) {
            for (candidateArtist in candidateArtists) {
                best = max(
                    best,
                    maxOf(
                        tokenSortRatio(sourceArtist, candidateArtist),
                        tokenSetRatio(sourceArtist, candidateArtist),
                        tokenSortRatio(toPhoneticLatin(sourceArtist), toPhoneticLatin(candidateArtist)),
                    ),
                )
            }
        }
        return (best >= 85) to best
    }

    private fun computeInvertedMatch(
        profile: SourceProfile,
        candidateBase: String,
        candidateArtists: List<String>,
    ): Pair<Int, Int>? {
        if (!profile.hasTwoParts) return null
        val titleRatio = bestRatio(profile.part0Clean, candidateBase)
        val artistRatio = candidateArtists.maxOfOrNull { bestRatio(profile.part1Clean, cleanBaseTitle(it)) } ?: 0
        return if (titleRatio >= 85 && artistRatio >= 85) titleRatio to artistRatio else null
    }

    private fun acceptedScore(best: RankedCandidate): Int? {
        fun within(limit: Long) = best.deltaMs == null || best.deltaMs <= limit
        if (best.titleRatio >= 85 && best.artistExact && best.versionMatches && within(10_000)) {
            return max(best.score, 95)
        }
        if (best.titleRatio >= 88 && best.titleClean.length >= 4 &&
            best.deltaMs != null && best.deltaMs <= 3_000 && best.versionMatches
        ) {
            return max(best.score, 88)
        }
        if (best.artistExact && within(4_000) && best.titleRatio >= 70 && best.versionMatches) {
            return max(best.score, 85)
        }
        if (best.score >= 75 && best.titleRatio >= 75 &&
            (best.artistExact || best.artistRatio >= 70) &&
            best.versionMatches && within(8_000)
        ) {
            return best.score
        }
        return null
    }

    private fun isAmbiguous(best: RankedCandidate, second: RankedCandidate?): Boolean {
        if (second == null || second.disqualified || best.score - second.score >= 10) return false
        val bestDuration = durationMs(best.track.durationText)
        val secondDuration = durationMs(second.track.durationText)
        val duplicate = best.titleClean == second.titleClean &&
            artistsMatch(best.primaryArtist, second.primaryArtist) &&
            bestDuration != null && secondDuration != null &&
            kotlin.math.abs(bestDuration - secondDuration) <= 3_000
        val clearWinner = best.score >= 75 && best.versionMatches && best.artistExact &&
            best.deltaMs != null && best.deltaMs <= 4_000
        return !duplicate && !clearWinner && (!best.titleExact || !best.versionMatches)
    }

    private fun durationScore(delta: Long?): Int = when {
        delta == null -> 10
        delta <= 3_000 -> 30
        delta <= 5_000 -> 22
        delta <= 8_000 -> 12
        delta <= 12_000 -> 2
        delta <= DISQUALIFY_DELTA_MS -> -20
        else -> -100
    }

    private fun durationMs(text: String?): Long? {
        if (text.isNullOrBlank()) return null
        val parts = text.trim().split(':').mapNotNull { it.toLongOrNull() }
        if (parts.isEmpty() || parts.size != text.trim().split(':').size) return null
        val seconds = when (parts.size) {
            2 -> parts[0] * 60 + parts[1]
            3 -> parts[0] * 3600 + parts[1] * 60 + parts[2]
            else -> return null
        }
        return seconds.takeIf { it > 0 }?.times(1000)
    }

    private fun bestRatio(left: String, right: String): Int =
        max(tokenSortRatio(left, right), tokenSetRatio(left, right))

    private fun tokenSortRatio(left: String, right: String): Int {
        val a = normalizeTrackString(left)
        val b = normalizeTrackString(right)
        if (a.isBlank() || b.isBlank()) return 0
        if (a == b) return 100
        val sortedA = a.split(' ').filter(String::isNotBlank).sorted().joinToString(" ")
        val sortedB = b.split(' ').filter(String::isNotBlank).sorted().joinToString(" ")
        if (sortedA == sortedB) return 100
        val distance = levenshtein(sortedA, sortedB)
        val longest = max(sortedA.length, sortedB.length)
        return if (longest == 0) 0 else ((1.0 - distance.toDouble() / longest) * 100).roundToInt().coerceAtLeast(0)
    }

    private fun tokenSetRatio(left: String, right: String): Int {
        val a = normalizeTrackString(left).split(' ').filter(String::isNotBlank).toSet()
        val b = normalizeTrackString(right).split(' ').filter(String::isNotBlank).toSet()
        if (a.isEmpty() || b.isEmpty()) return 0
        if (a == b) return 100
        val intersection = a.intersect(b)
        if (intersection.isEmpty()) return 0
        val minTokens = min(a.size, b.size)
        val maxTokens = max(a.size, b.size)
        if (a.size == b.size && intersection.size == a.size) return 100
        val coverage = (2.0 * intersection.size) / (a.size + b.size)
        var ratio = (coverage * 100).roundToInt()
        if (intersection.size == minTokens) {
            if (minTokens >= 2) {
                ratio = max(ratio, ((minTokens.toDouble() / maxTokens) * 35 + 55).roundToInt())
            } else {
                val common = intersection.firstOrNull().orEmpty()
                if (common.length >= 5 && minTokens.toDouble() / maxTokens >= 0.5) ratio = max(ratio, 72)
            }
        }
        return ratio
    }

    private fun levenshtein(a: String, b: String): Int {
        if (a == b) return 0
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var previous = IntArray(b.length + 1) { it }
        var current = IntArray(b.length + 1)
        for (i in a.indices) {
            current[0] = i + 1
            for (j in b.indices) {
                val cost = if (a[i] == b[j]) 0 else 1
                current[j + 1] = minOf(current[j] + 1, previous[j + 1] + 1, previous[j] + cost)
            }
            val temp = previous
            previous = current
            current = temp
        }
        return previous[b.length]
    }

    private fun isGenericArtistLabel(value: String): Boolean =
        normalizeTrackString(value) in setOf(
            "unknown artist", "various artists", "various", "soundtrack",
        )

    private fun looksLikePerformerSegment(value: String): Boolean {
        val tokens = normalizeTrackString(value).split(' ').filter(String::isNotBlank)
        if (tokens.isEmpty() || isGenericArtistLabel(value)) return false
        val packagingWords = setOf(
            "official", "audio", "video", "music", "lyrics", "lyric", "visualizer",
            "cover", "karaoke", "remix", "live", "edit", "version", "slowed",
            "reverb", "sped", "speed", "up", "instrumental", "acoustic", "pop",
            "sunda", "jawa", "full", "hd", "4k", "mv", "radio", "feat", "ft",
            "featuring", "with", "and",
        )
        val nameTokens = tokens.filterNot { it in packagingWords }
        return nameTokens.isNotEmpty() && nameTokens.size <= 4 &&
            nameTokens.any { token -> token.any(Char::isLetter) }
    }

    private fun containsUncreditedArtistName(candidateArtist: String, sourceArtists: List<String>): Boolean {
        val candidateTokens = normalizeTrackString(candidateArtist)
            .split(' ')
            .filter(String::isNotBlank)
        val creditedTokens = sourceArtists
            .flatMap { normalizeTrackString(it).split(' ') }
            .filter(String::isNotBlank)
            .distinct()
        // Remove token-level spelling variants too (for example Gasantra /
        // Gasentra), but do not let a similar label hide an extra singer name.
        val remaining = candidateTokens.filter { candidateToken ->
            creditedTokens.none { creditedToken ->
                tokenSortRatio(candidateToken, creditedToken) >= 85
            }
        }.joinToString(" ")
        return looksLikePerformerSegment(remaining)
    }

    private fun artistsMatch(source: String, candidate: String): Boolean {
        if (source.isBlank() || candidate.isBlank()) return false
        val sourceClean = normalizeTrackString(source)
        val candidateClean = normalizeTrackString(candidate)
        if (sourceClean.isNotBlank() && sourceClean == candidateClean) return true
        val sourceCompact = sourceClean.replace(" ", "")
        val candidateCompact = candidateClean.replace(" ", "")
        if (sourceCompact.isNotBlank() && sourceCompact == candidateCompact) return true
        if (knownArtistAliases.any { sourceClean in it && candidateClean in it }) return true
        if (containsEither(sourceCompact, candidateCompact, 3)) return true
        val sourcePhonetic = toPhoneticLatin(source)
        val candidatePhonetic = toPhoneticLatin(candidate)
        if (sourcePhonetic.isNotBlank() && sourcePhonetic == candidatePhonetic) return true
        return containsEither(sourcePhonetic, candidatePhonetic, 4)
    }

    private fun containsEither(left: String, right: String, minimum: Int): Boolean =
        left.length >= minimum && right.length >= minimum && (left.contains(right) || right.contains(left))

    private fun isNearSubstring(left: String, right: String): Boolean {
        val minimum = min(left.length, right.length)
        val maximum = max(left.length, right.length)
        return minimum >= 4 && minimum.toDouble() / maximum >= 0.7 &&
            (left.contains(right) || right.contains(left))
    }

    private fun normalizeSearchText(value: String): String =
        value.lowercase()
            .replace("ё", "е")
            .replace("!", "i")
            .replace("\$", "s")
            .replace(Regex("""[()\[\]\-–—_"'!?.,:;/\\|#]"""), " ")
            .replace(Regex("""\s+"""), " ")
            .trim()

    private fun queryTokens(query: String): List<String> {
        val stopWords = setOf(
            "the", "a", "an", "of", "in", "on", "to", "and", "or", "feat", "ft",
            "official", "audio", "video", "music", "lyrics", "и", "в", "на", "с",
            "со", "к", "по", "о", "об", "из", "клип", "трек", "песня",
        )
        return normalizeSearchText(query).split(' ').filter { it.isNotBlank() && it !in stopWords }
    }

    private fun normalizeTrackString(value: String): String {
        val withoutExtension = value.replace(
            Regex("""\.(?:mp3|wav|flac|m4a|aac|ogg)\b""", RegexOption.IGNORE_CASE),
            "",
        )
        return withoutExtension.lowercase().replace("ё", "е")
            .replace(Regex("""[^\p{L}\p{N}]+"""), " ")
            .trim().replace(Regex("""\s+"""), " ")
    }

    private fun toPhoneticLatin(value: String): String {
        var result = value.lowercase().replace("ё", "e")
        cyrillicToLatin.forEach { (letter, latin) -> result = result.replace(letter.toString(), latin) }
        return result
            .replace("kh", "h")
            .replace(Regex("""[yj]"""), "i")
            .replace("w", "v")
            .replace("ph", "f")
            .replace("oo", "u")
            .replace("ee", "i")
            .replace("z", "s")
            .replace(Regex("""e\b"""), "")
            .replace(Regex("""[^a-z0-9\s]"""), " ")
            .trim().replace(Regex("""\s+"""), " ")
    }

    private const val DISQUALIFY_DELTA_MS = 15_000L
}