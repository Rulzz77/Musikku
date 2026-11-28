package com.music.bitchord.ui.player

import java.util.Locale

/**
 * Characters which can make identical lyric text compare as different even
 * though they add no visible glyph. Keep joiners (U+200C/U+200D): they carry
 * meaningful shaping information in Arabic/Indic scripts and emoji sequences.
 */
private val lyricZeroWidthFormatting = setOf(
    '\u200B', // ZERO WIDTH SPACE
    '\u200E', // LEFT-TO-RIGHT MARK
    '\u200F', // RIGHT-TO-LEFT MARK
    '\u2060', // WORD JOINER
    '\uFEFF', // ZERO WIDTH NO-BREAK SPACE / BOM
)

/**
 * Comparison-only normalization for deciding whether a romanized/translated
 * row would repeat the original lyrics. The source text itself is never changed.
 */
internal fun String.lyricsComparisonKey(): String = buildString(length) {
    for (character in this@lyricsComparisonKey) {
        if (!character.isWhitespace() && character !in lyricZeroWidthFormatting) {
            append(character)
        }
    }
}.lowercase(Locale.ROOT)

internal fun String.differsFromLyrics(original: String): Boolean =
    lyricsComparisonKey() != original.lyricsComparisonKey()
