package com.musikku.app

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request as ExtractorRequest
import org.schabi.newpipe.extractor.downloader.Response as ExtractorResponse
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.services.youtube.YoutubeService
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import okhttp3.OkHttpClient
import okhttp3.Request as HttpRequest
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Native bridge for NewPipe Extractor.
 *
 * Important: this is an unofficial, best-effort adapter. The website can
 * change or reject extraction at any time; no stream URL is persisted.
 */
internal object NewPipeExtractorBridge {
    private const val TAG = "MusikKuNewPipe"
    private const val CHANNEL = "musikku/newpipe"
    private const val DEFAULT_USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newFixedThreadPool(2) { runnable ->
        Thread(runnable, "MusikKu-NewPipe").apply { isDaemon = true }
    }
    @Volatile private var isInitialized = false
    private val youtubeService: YoutubeService by lazy { YoutubeService(0) }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "search" -> {
                    val query = call.argument<String>("query")?.trim().orEmpty()
                    val limit = (call.argument<Number>("limit")?.toInt() ?: 20).coerceIn(1, 30)
                    if (query.isBlank()) {
                        result.error("INVALID_QUERY", "Masukkan kata kunci pencarian.", null)
                    } else {
                        runOnWorker(result, "NEWPIPE_SEARCH_FAILED") {
                            search(query, limit)
                        }
                    }
                }
                "resolveAudio" -> {
                    val videoId = call.argument<String>("videoId")?.trim().orEmpty()
                    if (!videoId.matches(Regex("[A-Za-z0-9_-]{11}"))) {
                        result.error("INVALID_VIDEO_ID", "ID video YouTube tidak valid.", null)
                    } else {
                        runOnWorker(result, "NEWPIPE_RESOLVE_FAILED") {
                            resolveAudio(videoId)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun runOnWorker(
        result: MethodChannel.Result,
        errorCode: String,
        operation: () -> Any?
    ) {
        executor.execute {
            try {
                val value = operation()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                Log.e(TAG, "$errorCode: ${error.message ?: error.javaClass.simpleName}", error)
                val message = (error.message ?: error.javaClass.simpleName).take(600)
                mainHandler.post {
                    result.error(errorCode, message, null)
                }
            }
        }
    }

    @Synchronized
    private fun ensureInitialized() {
        if (isInitialized) return
        NewPipe.init(
            NativeHttpDownloader(),
            Localization("id", "ID"),
            ContentCountry("ID")
        )
        isInitialized = true
        Log.i(TAG, "NewPipe Extractor initialized")
    }

    private fun search(query: String, limit: Int): List<Map<String, Any?>> {
        ensureInitialized()
        val queryHandler = youtubeService.searchQHFactory.fromQuery(query)
        val info = SearchInfo.getInfo(youtubeService, queryHandler)
        val output = ArrayList<Map<String, Any?>>(limit)
        for (item in info.relatedItems) {
            if (output.size >= limit) break
            if (item !is StreamInfoItem) continue
            val url = item.url ?: continue
            val videoId = extractVideoId(url) ?: continue
            val thumbnails = try {
                item.thumbnails
            } catch (_: Throwable) {
                emptyList()
            }
            val thumbnailUrl = thumbnails.firstOrNull()?.url.orEmpty()
            val duration = item.duration
            output.add(
                mapOf(
                    "videoId" to videoId,
                    "title" to item.name,
                    "artist" to (item.uploaderName?.takeIf { it.isNotBlank() } ?: "YouTube"),
                    "thumbnailUrl" to thumbnailUrl,
                    "url" to "https://www.youtube.com/watch?v=$videoId",
                    "durationSeconds" to duration.takeIf { it > 0L }
                )
            )
        }
        // An empty result is a valid search response, not an extractor failure.
        return output
    }

    private fun resolveAudio(videoId: String): Map<String, Any> {
        ensureInitialized()
        val watchUrl = "https://www.youtube.com/watch?v=$videoId"
        val info = StreamInfo.getInfo(youtubeService, watchUrl)
        val streams: List<AudioStream> = info.audioStreams
        val directStreams = streams.filter {
            it.isUrl && it.content.startsWith("https://", ignoreCase = true)
        }
        // Prefer M4A/MP4 (typically AAC), which has broad decoder support on
        // Android devices. Use the highest bitrate among compatible formats;
        // if no such stream exists, fall back to the best available URL stream.
        val selected = directStreams
            .sortedWith(
                compareByDescending<AudioStream> {
                    val suffix = it.format?.suffix?.lowercase(Locale.ROOT)
                    suffix == "m4a" || suffix == "mp4"
                }.thenByDescending { it.averageBitrate }
            )
            .firstOrNull()
            ?: throw IOException("NewPipe tidak menemukan direct HTTPS audio stream untuk video ini.")
        val url = selected.content.trim()
        if (url.isEmpty()) throw IOException("URL audio dari NewPipe kosong.")
        val suffix = selected.format?.suffix.orEmpty()
        Log.d(
            TAG,
            "Audio stream selected: format=${suffix.ifBlank { "unknown" }}, " +
                "codec=${selected.codec}, bitrate=${selected.averageBitrate}, " +
                "candidateCount=${directStreams.size}"
        )
        return mapOf(
            "streamUrl" to url,
            "headers" to mapOf(
                "User-Agent" to DEFAULT_USER_AGENT,
                "Referer" to "https://www.youtube.com/"
            ),
            "bitrate" to selected.averageBitrate,
            "format" to suffix,
        )
    }

    private fun extractVideoId(rawUrl: String): String? {
        return try {
            val uri = Uri.parse(rawUrl)
            val queryId = uri.getQueryParameter("v")
            if (queryId != null && queryId.matches(Regex("[A-Za-z0-9_-]{11}"))) {
                queryId
            } else {
                val path = uri.path.orEmpty()
                val candidate = Regex("(?:/shorts/|/live/|/embed/|/)([A-Za-z0-9_-]{11})(?:$|/)")
                    .find(path)?.groupValues?.getOrNull(1)
                candidate?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{11}")) }
            }
        } catch (_: Throwable) {
            null
        }
    }

    /** OkHttp-backed NewPipe Downloader; no media files are saved. */
    private class NativeHttpDownloader : Downloader() {
        private val client = OkHttpClient.Builder()
            .connectTimeout(18, TimeUnit.SECONDS)
            .readTimeout(22, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()

        override fun execute(request: ExtractorRequest): ExtractorResponse {
            val method = request.httpMethod().uppercase(Locale.ROOT)
            val requestBuilder = HttpRequest.Builder().url(request.url())
            val requestHeaders = request.headers().orEmpty()
            var hasUserAgent = false
            requestHeaders.forEach { (name, values) ->
                if (name.equals("User-Agent", ignoreCase = true)) hasUserAgent = true
                values.forEach { value -> requestBuilder.addHeader(name, value) }
            }
            if (!hasUserAgent) requestBuilder.header("User-Agent", DEFAULT_USER_AGENT)

            val bytes = request.dataToSend()
            val body = bytes?.toRequestBody(null)
            when (method) {
                "GET" -> requestBuilder.get()
                "HEAD" -> requestBuilder.head()
                "POST" -> requestBuilder.post(body ?: ByteArray(0).toRequestBody(null))
                else -> requestBuilder.method(method, body)
            }

            client.newCall(requestBuilder.build()).execute().use { response ->
                val responseHeaders = linkedMapOf<String, MutableList<String>>()
                for (index in 0 until response.headers.size) {
                    val name = response.headers.name(index)
                    val value = response.headers.value(index)
                    responseHeaders.getOrPut(name) { mutableListOf() }.add(value)
                }
                val cleanHeaders = responseHeaders.mapValues { it.value.toList() }
                val responseBody = response.body?.string().orEmpty()
                return ExtractorResponse(
                    response.code,
                    response.message,
                    cleanHeaders,
                    responseBody,
                    response.request.url.toString()
                )
            }
        }
    }
}
