package com.music.bitchord.data.lyrics

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class YouTubeMusicLyricsTest {
    private fun page(json: String) = Json.parseToJsonElement(json).jsonObject

    private val timed = page(
        """{"timedLyricsData":[
          {"lyricLine":"first line","cueRange":{"startTimeMilliseconds":"2210","endTimeMilliseconds":"7440"}},
          {"lyricLine":"second line","cueRange":{"startTimeMilliseconds":7440,"endTimeMilliseconds":9000}}
        ]}""",
    )

    private val plain = page(
        """{"contents":{"sectionListRenderer":{"contents":[
          {"musicDescriptionShelfRenderer":{"description":{"runs":[{"text":"first line\nsecond line"}]}}}
        ]}}}""",
    )

    @Test
    fun readsTimedLyricsAndEndTimes() {
        val lines = timedLyrics(timed)!!
        assertEquals(listOf("first line", "second line"), lines.map { it.text })
        assertEquals(2_210L, lines[0].timeMs)
        assertEquals(7_440L, lines[0].sungUntilMs)
        assertEquals(9_000L, lines[1].sungUntilMs)
        assertFalse(lines[0].isWordSynced)
        assertTrue(lines.all { it.timeMs > 0 })
    }

    @Test
    fun readsNumericTimestamps() {
        val line = timedLyrics(page("""{"timedLyricsData":[{"lyricLine":"line","cueRange":{"startTimeMilliseconds":1200,"endTimeMilliseconds":3400}}]}"""))!!.single()
        assertEquals(1_200L, line.timeMs)
        assertEquals(3_400L, line.sungUntilMs)
    }

    @Test
    fun fallsBackToPlainLyrics() {
        assertNull(timedLyrics(plain))
        val lines = plainLyrics(plain)!!
        assertEquals(listOf("first line", "second line"), lines.map { it.text })
        assertTrue(lines.all { it.timeMs == 0L })
    }

    @Test
    fun rejectsPagesWithoutLyrics() {
        assertNull(timedLyrics(page("""{"contents":{}}""")))
        assertNull(plainLyrics(page("""{"contents":{}}""")))
    }

    @Test
    fun dropsEmptyLinesAndSortsCues() {
        val payload = page("""{"timedLyricsData":[
          {"lyricLine":"later","cueRange":{"startTimeMilliseconds":"5000"}},
          {"lyricLine":"  ","cueRange":{"startTimeMilliseconds":"0","endTimeMilliseconds":"100"}},
          {"lyricLine":"sooner","cueRange":{"startTimeMilliseconds":"1000"}}
        ]}""")
        assertEquals(listOf("sooner", "later"), timedLyrics(payload)?.map { it.text })
    }
}
