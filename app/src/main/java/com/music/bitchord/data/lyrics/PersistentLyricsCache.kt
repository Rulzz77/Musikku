package com.music.bitchord.data.lyrics

import android.content.Context
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Small, durable cache of lyrics already matched to a YouTube video id.
 *
 * This is deliberately separate from the provider's ISRC cache: it stores the
 * actual displayed lines, so a process death does not make a paused track look
 * as though it has never had lyrics. The source selection/order are part of the
 * key; changing a user's provider choices never silently reuses an answer from
 * a different lookup configuration.
 */
data class CachedLyrics(
    val source: LyricsSource?,
    /** Zero means this answer was obtained from exact-video sources before duration was known. */
    val durationMs: Long,
    val lines: List<LyricLine>,
)

object PersistentLyricsCache {
    private const val DIRECTORY = "lyrics-cache"
    private const val MAX_ENTRIES = 100
    private const val MAX_FILE_BYTES = 1_000_000
    private const val FORMAT_VERSION = 1
    private val lock = Any()

    fun key(
        videoId: String,
        sources: Set<LyricsSource>,
        order: List<LyricsSource>,
        prioritizeSyllableSync: Boolean,
    ): String = buildString {
        append(videoId)
        append('\n')
        append(sources.map { it.name }.sorted().joinToString(","))
        append('\n')
        append(order.joinToString(",") { it.name })
        append('\n')
        append(prioritizeSyllableSync)
    }

    fun read(context: Context, cacheKey: String): CachedLyrics? = synchronized(lock) {
        val file = cacheFile(context, cacheKey)
        if (!file.baseFile.exists()) return@synchronized null
        try {
            val text = file.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() }
            if (text.toByteArray(Charsets.UTF_8).size > MAX_FILE_BYTES) {
                file.delete()
                return@synchronized null
            }
            val root = JSONObject(text)
            if (root.optInt("version") != FORMAT_VERSION) {
                file.delete()
                return@synchronized null
            }
            val lines = root.optJSONArray("lines")?.let(::decodeLines).orEmpty()
            if (lines.isEmpty()) {
                file.delete()
                return@synchronized null
            }
            val source = root.optString("source").takeIf { it.isNotBlank() }?.let { name ->
                runCatching { LyricsSource.valueOf(name) }.getOrNull()
            }
            file.baseFile.setLastModified(System.currentTimeMillis())
            CachedLyrics(source, root.optLong("durationMs", 0L), lines)
        } catch (_: Exception) {
            file.delete()
            null
        }
    }

    fun write(
        context: Context,
        cacheKey: String,
        source: LyricsSource?,
        durationMs: Long,
        lines: List<LyricLine>,
    ) {
        if (lines.isEmpty()) return
        synchronized(lock) {
            runCatching {
                val root = JSONObject()
                    .put("version", FORMAT_VERSION)
                    .put("source", source?.name ?: JSONObject.NULL)
                    .put("durationMs", durationMs.coerceAtLeast(0L))
                    .put("savedAt", System.currentTimeMillis())
                    .put("lines", encodeLines(lines))
                val bytes = root.toString().toByteArray(Charsets.UTF_8)
                if (bytes.size > MAX_FILE_BYTES) return@runCatching

                val file = cacheFile(context, cacheKey)
                file.baseFile.parentFile?.mkdirs()
                val stream = file.startWrite()
                try {
                    stream.write(bytes)
                    file.finishWrite(stream)
                } catch (failure: Throwable) {
                    file.failWrite(stream)
                    throw failure
                }
                prune(file.baseFile.parentFile)
            }
        }
    }

    private fun cacheFile(context: Context, key: String): AtomicFile {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(key.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> (byte.toInt() and 0xff).toString(16).padStart(2, '0') }
        val directory = File(context.filesDir, DIRECTORY)
        return AtomicFile(File(directory, "$digest.json"))
    }

    private fun prune(directory: File?) {
        val files = directory?.listFiles { file -> file.isFile && file.extension == "json" }
            ?.sortedBy(File::lastModified)
            ?: return
        val excess = (files.size - MAX_ENTRIES).coerceAtLeast(0)
        files.take(excess).forEach(File::delete)
    }

    private fun encodeLines(lines: List<LyricLine>): JSONArray =
        JSONArray().also { array -> lines.forEach { array.put(encodeLine(it, 0)) } }

    private fun encodeLine(line: LyricLine, depth: Int): JSONObject =
        JSONObject()
            .put("timeMs", line.timeMs)
            .put("text", line.text)
            .put("sungUntilMs", line.sungUntilMs ?: JSONObject.NULL)
            .put("alignment", line.alignment.name)
            .put("words", JSONArray().also { words ->
                line.words.forEach { word ->
                    words.put(
                        JSONObject()
                            .put("startMs", word.startMs)
                            .put("endMs", word.endMs)
                            .put("text", word.text)
                            .put("syllables", JSONArray().also { syllables ->
                                word.syllables.forEach { syllable ->
                                    syllables.put(
                                        JSONObject()
                                            .put("startMs", syllable.startMs)
                                            .put("endMs", syllable.endMs)
                                            .put("startChar", syllable.startChar)
                                            .put("endChar", syllable.endChar),
                                    )
                                }
                            }),
                    )
                }
            })
            .put(
                "background",
                if (depth < 2) line.background?.let { encodeLine(it, depth + 1) } ?: JSONObject.NULL
                else JSONObject.NULL,
            )
            .put(
                "timingSource",
                if (depth < 2) line.timingSource?.let { encodeLine(it, depth + 1) } ?: JSONObject.NULL
                else JSONObject.NULL,
            )

    private fun decodeLines(array: JSONArray): List<LyricLine> = buildList(array.length()) {
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            decodeLine(item, 0)?.let(::add)
        }
    }

    private fun decodeLine(json: JSONObject, depth: Int): LyricLine? {
        val text = json.optString("text", "")
        val words = json.optJSONArray("words")?.let(::decodeWords).orEmpty()
        val sungUntil = json.opt("sungUntilMs").takeUnless { it == null || it == JSONObject.NULL }
            ?.let { (it as? Number)?.toLong() }
        val alignment = runCatching {
            LyricAlignment.valueOf(json.optString("alignment", LyricAlignment.Start.name))
        }.getOrDefault(LyricAlignment.Start)
        val background = if (depth < 2) {
            json.optJSONObject("background")?.let { decodeLine(it, depth + 1) }
        } else null
        val timingSource = if (depth < 2) {
            json.optJSONObject("timingSource")?.let { decodeLine(it, depth + 1) }
        } else null
        return LyricLine(
            timeMs = json.optLong("timeMs", 0L),
            text = text,
            words = words,
            sungUntilMs = sungUntil,
            background = background,
            alignment = alignment,
            timingSource = timingSource,
        )
    }

    private fun decodeWords(array: JSONArray): List<LyricWord> = buildList(array.length()) {
        for (index in 0 until array.length()) {
            val word = array.optJSONObject(index) ?: continue
            val syllables = word.optJSONArray("syllables")?.let(::decodeSyllables).orEmpty()
            add(
                LyricWord(
                    startMs = word.optLong("startMs", 0L),
                    endMs = word.optLong("endMs", 0L),
                    text = word.optString("text", ""),
                    syllables = syllables,
                ),
            )
        }
    }

    private fun decodeSyllables(array: JSONArray): List<LyricSyllable> = buildList(array.length()) {
        for (index in 0 until array.length()) {
            val syllable = array.optJSONObject(index) ?: continue
            add(
                LyricSyllable(
                    startMs = syllable.optLong("startMs", 0L),
                    endMs = syllable.optLong("endMs", 0L),
                    startChar = syllable.optInt("startChar", 0),
                    endChar = syllable.optInt("endChar", 0),
                ),
            )
        }
    }
}
