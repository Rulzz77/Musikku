package com.music.bitchord.data.remote

import android.content.Context
import android.content.SharedPreferences
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.music.bitchord.BuildConfig
import com.music.bitchord.data.Http
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Small, public remote configuration for switches that must be recoverable
 * without publishing another APK.
 *
 * The JSON is served from this repository's main branch. A cached copy is
 * applied synchronously at startup; refresh happens off the main thread when
 * the app process enters the foreground and the cache is older than [REFRESH_INTERVAL_MS].
 *
 * This is deliberately not a security boundary. It only controls presentation
 * and rollout of features already present in the installed app. Never put
 * secrets, account data or credentials in the remote file.
 */
object RemoteConfig {
    private const val CONFIG_URL =
        "https://raw.githubusercontent.com/Rulzz77/Musikku/main/remote-config.json"
    private const val PREFERENCES = "remote_config_v1"
    private const val KEY_JSON = "config_json"
    private const val KEY_LAST_ATTEMPT = "last_attempt_ms"
    private const val REFRESH_INTERVAL_MS = 15 * 60 * 1000L
    private const val MAX_CONFIG_BYTES = 16 * 1024L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val refreshMutex = Mutex()
    private val mutableSnapshot = MutableStateFlow(RemoteConfigSnapshot())
    val snapshot: StateFlow<RemoteConfigSnapshot> = mutableSnapshot.asStateFlow()

    @Volatile
    private var initialized = false
    private var preferences: SharedPreferences? = null

    private val client by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        Http.client.newBuilder()
            .callTimeout(8, TimeUnit.SECONDS)
            .build()
    }

    /** Safe to call more than once. Cached flags are available before this returns. */
    fun initialize(context: Context) {
        synchronized(this) {
            if (initialized) return

            val appContext = context.applicationContext
            val prefs = appContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            preferences = prefs

            val cached = prefs.getString(KEY_JSON, null)
                ?.let(::parseRemoteConfig)
            if (cached != null) {
                mutableSnapshot.value = cached.copy(
                    loadedFromServer = true,
                    fetchedAtMs = prefs.getLong(KEY_LAST_ATTEMPT, 0L),
                )
            }

            ProcessLifecycleOwner.get().lifecycle.addObserver(
                object : DefaultLifecycleObserver {
                    override fun onStart(owner: LifecycleOwner) {
                        scope.launch { refreshIfStale() }
                    }
                },
            )
            initialized = true
        }
    }

    /** Allows an explicit retry from future settings/support UI without blocking callers. */
    fun refreshNow() {
        if (initialized) scope.launch { refreshIfStale(force = true) }
    }

    private suspend fun refreshIfStale(force: Boolean = false): Boolean =
        refreshMutex.withLock {
            val prefs = preferences ?: return@withLock false
            val now = System.currentTimeMillis()
            val lastAttempt = prefs.getLong(KEY_LAST_ATTEMPT, 0L)
            if (!force && now - lastAttempt < REFRESH_INTERVAL_MS) return@withLock false

            // Record attempts as well as successes. A failed network request should
            // not be retried every time Compose resumes or a screen recomposes.
            prefs.edit().putLong(KEY_LAST_ATTEMPT, now).apply()

            try {
                val request = Request.Builder()
                    .url(CONFIG_URL)
                    .header("Accept", "application/json")
                    .header("Cache-Control", "no-cache")
                    .header("User-Agent", "MusikKu/\u0024{BuildConfig.VERSION_NAME}")
                    .get()
                    .build()

                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@withLock false
                    val body = response.body ?: return@withLock false
                    if (body.contentLength() > MAX_CONFIG_BYTES) return@withLock false

                    // Bound the read without relying on newer InputStream APIs
                    // that are not present on every Android version we support.
                    val input = body.byteStream()
                    val output = java.io.ByteArrayOutputStream()
                    val chunk = ByteArray(4 * 1024)
                    var totalBytes = 0
                    while (true) {
                        val count = input.read(chunk)
                        if (count < 0) break
                        totalBytes += count
                        if (totalBytes > MAX_CONFIG_BYTES) return@withLock false
                        output.write(chunk, 0, count)
                    }
                    val raw = String(output.toByteArray(), Charsets.UTF_8)
                    val parsed = parseRemoteConfig(raw) ?: return@withLock false
                    // A stale CDN response must never roll back a newer config
                    // already loaded from disk or from a previous request.
                    if (parsed.revision < mutableSnapshot.value.revision) {
                        return@withLock false
                    }
                    mutableSnapshot.value = parsed.copy(
                        loadedFromServer = true,
                        fetchedAtMs = now,
                    )
                    prefs.edit()
                        .putString(KEY_JSON, raw)
                        .putLong(KEY_LAST_ATTEMPT, now)
                        .apply()
                    true
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Offline, timeout, GitHub unavailable, or malformed response:
                // keep the last known-good cache (or safe built-in defaults).
                false
            }
        }
}

/** Feature switches are permissive by default so an unavailable config never removes features. */
data class RemoteFeatureFlags(
    val globalSearch: Boolean = true,
    val playlistSearch: Boolean = true,
)

data class RemoteConfigSnapshot(
    val revision: Int = 0,
    val features: RemoteFeatureFlags = RemoteFeatureFlags(),
    val loadedFromServer: Boolean = false,
    val fetchedAtMs: Long = 0L,
)

/**
 * Pure parser kept separate from networking so unknown keys can be added
 * without breaking older APKs and the accepted schema can be unit-tested.
 */
internal fun parseRemoteConfig(raw: String): RemoteConfigSnapshot? {
    return try {
        val root = Json.parseToJsonElement(raw) as? JsonObject ?: return null
        val schemaVersion = root["schemaVersion"]?.jsonPrimitive?.intOrNull ?: return null
        if (schemaVersion != 1) return null
        val revision = root["revision"]?.jsonPrimitive?.intOrNull ?: return null
        if (revision < 1) return null
        val features = root["features"] as? JsonObject ?: return null

        fun flag(name: String, default: Boolean): Boolean =
            features[name]?.jsonPrimitive?.booleanOrNull ?: default

        RemoteConfigSnapshot(
            revision = revision,
            features = RemoteFeatureFlags(
                globalSearch = flag("globalSearch", true),
                playlistSearch = flag("playlistSearch", true),
            ),
        )
    } catch (_: Exception) {
        null
    }
}
