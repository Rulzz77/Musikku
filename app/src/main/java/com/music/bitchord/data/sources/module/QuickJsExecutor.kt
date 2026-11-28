package com.music.bitchord.data.sources.module

import android.util.Log
import com.music.bitchord.data.TrackLog
import com.dokar.quickjs.QuickJs
import com.dokar.quickjs.binding.AsyncFunctionBinding
import com.dokar.quickjs.binding.FunctionBinding
import com.dokar.quickjs.binding.define
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.UnknownHostException
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.Locale

/**
 * Sandboxed QuickJS engine pool for executing module JS.
 *
 * Modules commonly stash session/auth state in top-level variables set up
 * once at load time (e.g. an eager token pre-fetch). The old one-shot
 * executor re-evaluated the whole script on every function call, so that
 * state never survived from `searchTracks()` to `getStreamUrl()` — each
 * ran in its own throwaway VM. Keeping one engine alive per loaded module,
 * reused across calls, is what a normal module host does and what these
 * modules assume. LRU-capped at [MAX_MODULES]; least-recently-used is
 * evicted to make room rather than refusing to load past the cap.
 *
 * ### Why a module gets several engines and not one
 *
 * A QuickJS VM is a single-threaded interpreter and [callExport] drives it
 * across two `evaluate` calls with the answer parked in a global in between.
 * Both of those make one engine strictly one call at a time: two callers
 * sharing it would interleave their `evaluate`s inside the interpreter, and
 * even if they didn't, the second would overwrite `__spine_resolved_json`
 * before the first had read it — so one track's download would quietly receive
 * another track's stream URL. That was survivable while downloads drained one
 * at a time and playback asked for one track at a time; it is not survivable
 * with several downloads in flight.
 *
 * Serialising on a single engine would be correct and would also give all the
 * concurrency back, since a module's own HTTP fetches happen *inside* the VM
 * and hold it for their whole duration — measured at 7.7s for one module on
 * one query. So each module gets a small pool instead: [ENGINES_PER_MODULE]
 * independent VMs, each handed to one caller at a time, growing lazily so a
 * module nobody is hammering still costs exactly one.
 *
 * Ported from Convx's `QuickJsExecutor`, with the pool added.
 */
internal object QuickJsExecutor {

    private const val TAG = "BitChord"

    /**
     * How many modules stay resident.
     *
     * Has to cover a whole index, not a working set. A search fans out to
     * *every* module at once, so a cap below the index size means each search
     * evicts engines the same search is still using — and the eviction is
     * invisible to [ModuleManager], which caches the load separately and goes
     * on reporting a hit for an engine that is gone. What that produced was
     * `Module … is not loaded` on the stream call for whichever modules lost
     * the race, one wasted attempt per track, on every track. Four was the
     * ported default and is below the size of a real index.
     */
    private const val MAX_MODULES = 12

    /**
     * How many callers one module can serve at once.
     *
     * Each is a whole interpreter with the module's script evaluated into it,
     * so this is not free — and each costs whatever the module does at load
     * time, which for several of them is an eager token fetch. Three is sized
     * against the download queue's own width: enough that the workers are not
     * queueing behind each other on the one slow module in the index, few
     * enough that a three-module index is nine VMs and not thirty.
     */
    private const val ENGINES_PER_MODULE = 3
    private const val MAX_MODULE_SOURCE_BYTES = 2 * 1024 * 1024
    private const val MODULE_MEMORY_LIMIT_BYTES = 24L * 1024 * 1024
    private const val MODULE_EVALUATION_TIMEOUT_MS = 15_000L
    private const val MODULE_CALL_TIMEOUT_MS = 90_000L

    /**
     * One module's interpreters, and the source to make more from.
     *
     * [free] is the ones nobody is inside right now. It is unbounded and only
     * ever holds engines this pool made, so a send to it cannot fail or block;
     * a receive is a caller waiting its turn.
     */
    private class Pool(val jsCode: String, val fetchBase: String) {
        val free = Channel<QuickJs>(Channel.UNLIMITED)
        val lock = Mutex()
        /** Engines made or being made — the claim that stops two callers both growing the pool. */
        var started = 0
        /** Engines actually made, for closing them on unload. Guarded by [lock]. */
        val made = mutableListOf<QuickJs>()
    }

    /** Whether [moduleId] still has a live pool, i.e. hasn't been evicted. */
    fun isLoaded(moduleId: String): Boolean =
        synchronized(engineLock) { pools.containsKey(moduleId) }

    /** Isolated from the app-wide WebDAV auth interceptor; addon servers never receive those credentials. */
    internal val moduleHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .callTimeout(30, TimeUnit.SECONDS)
            // OkHttp follows redirects by default. Re-validate each network
            // hop as well as the initial URL so a public HTTPS endpoint cannot
            // redirect a module into HTTP or a private network.
            .addNetworkInterceptor { chain ->
                validateModuleFetchUrl(chain.request().url.toString())
                chain.proceed(chain.request())
            }
            // Add-on code can call fetch(). Resolve each destination through a
            // checked DNS policy so it cannot reach loopback, LAN or link-local
            // services (including the cloud metadata endpoint).
            .dns { hostname ->
                val host = hostname.trimEnd('.').lowercase(Locale.ROOT)
                if (
                    host == "localhost" || host.endsWith(".localhost") ||
                    host.endsWith(".local") || host.endsWith(".lan") ||
                    host.endsWith(".internal") || host.endsWith(".home")
                ) {
                    throw UnknownHostException("Local network hosts are not available to modules")
                }
                val addresses = Dns.SYSTEM.lookup(hostname)
                if (addresses.isEmpty() || addresses.any(::isBlockedModuleAddress)) {
                    throw UnknownHostException("Private or special-use network addresses are not available to modules")
                }
                addresses
            }
            .build()
    }

    internal fun isBlockedModuleAddress(address: InetAddress): Boolean {
        if (
            address.isAnyLocalAddress || address.isLoopbackAddress ||
            address.isLinkLocalAddress || address.isSiteLocalAddress ||
            address.isMulticastAddress
        ) return true

        val bytes = address.address.map { it.toInt() and 0xff }
        if (bytes.size == 16) {
            // IPv4-mapped IPv6 must inherit the IPv4 policy. Otherwise a
            // private IPv4 literal could be wrapped as ::ffff:a.b.c.d.
            if (bytes.take(10).all { it == 0 } && bytes[10] == 0xff && bytes[11] == 0xff) {
                val mappedIpv4 = InetAddress.getByAddress(bytes.drop(12).map { it.toByte() }.toByteArray())
                return isBlockedModuleAddress(mappedIpv4)
            }
            // IPv6 unique-local fc00::/7 and the documentation-only 2001:db8::/32.
            return (bytes[0] and 0xfe) == 0xfc ||
                (bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8)
        }
        if (bytes.size != 4) return true
        val (a, b, c, _) = bytes
        return a == 0 || a == 10 || a == 127 || a >= 224 ||
            (a == 100 && b in 64..127) ||
            (a == 169 && b == 254) ||
            (a == 172 && b in 16..31) ||
            (a == 192 && ((b == 0 && (c == 0 || c == 2)) || b == 168 || (b == 88 && c == 99))) ||
            (a == 198 && b in 18..19) ||
            (a == 198 && b == 51 && c == 100) ||
            (a == 203 && b == 0 && c == 113)
    }

    internal fun validateModuleFetchUrl(rawUrl: String): String {
        require(rawUrl.length <= MAX_FETCH_URL_LENGTH) { "Module URL is too long" }
        val parsed = rawUrl.toHttpUrlOrNull()
            ?: throw IllegalArgumentException("Module fetch only supports HTTPS URLs")
        require(parsed.scheme == "https") {
            "Module fetch requires HTTPS"
        }
        require(parsed.username.isEmpty() && parsed.password.isEmpty()) {
            "Credentials embedded in module URLs are not allowed"
        }
        val host = parsed.host.lowercase(Locale.ROOT)
        require(
            host != "localhost" && !host.endsWith(".localhost") &&
                !host.endsWith(".local") && !host.endsWith(".lan") &&
                !host.endsWith(".internal") && !host.endsWith(".home")
        ) { "Local network hosts are not available to modules" }
        return parsed.toString()
    }

    private const val MAX_FETCH_URL_LENGTH = 4_096
    private const val MAX_FETCH_REQUEST_BYTES = 512 * 1024
    private const val MAX_FETCH_RESPONSE_BYTES = 2 * 1024 * 1024

    private val engineLock = Any()

    /** LRU map: access-ordered so the oldest-used entry is first. */
    private val pools = LinkedHashMap<String, Pool>(16, 0.75f, true)

    // ── Load ─────────────────────────────────────────────────────────────

    suspend fun loadModule(moduleId: String, jsCode: String, fetchBase: String = ""): Result<Unit> {
        val evicted = synchronized(engineLock) {
            if (pools.containsKey(moduleId)) {
                TrackLog.d(TAG, "QuickJsExecutor.loadModule($moduleId) — ENGINE CACHE HIT")
                return Result.success(Unit)
            }
            buildList {
                while (pools.size >= MAX_MODULES) {
                    val lruId = pools.keys.firstOrNull() ?: break
                    TrackLog.d(TAG, "  Evicting LRU module engine: $lruId")
                    pools.remove(lruId)?.let { addAll(it.made) }
                }
            }
        }
        evicted.forEach { runCatching { it.close() } }

        TrackLog.d(TAG, "QuickJsExecutor.loadModule($moduleId) origin=${safeModuleOrigin(fetchBase)} jsCodeLength=${jsCode.length}")
        return withContext(Dispatchers.Default) {
            runCatching { newEngine(jsCode, fetchBase) }
                .onSuccess { qjs ->
                    // The pool starts at one and grows only if two callers ever
                    // want this module at the same moment. A module that is
                    // never contended never pays for a second interpreter.
                    val pool = Pool(jsCode, fetchBase)
                    pool.started = 1
                    pool.made += qjs
                    pool.free.trySend(qjs)
                    synchronized(engineLock) { pools[moduleId] = pool }
                }
                .onFailure { TrackLog.e(TAG, "  ✗ loadModule FAILED for $moduleId (${it.javaClass.simpleName})") }
                .map { }
        }
    }

    /** A fresh interpreter with [jsCode] evaluated into it, or a throw saying why not. */
    private suspend fun newEngine(jsCode: String, fetchBase: String): QuickJs {
        require(jsCode.toByteArray(Charsets.UTF_8).size <= MAX_MODULE_SOURCE_BYTES) {
            "Module source is too large"
        }
        val qjs = QuickJs.create(Dispatchers.Default)
        qjs.maxStackSize = 512 * 1024L
        qjs.memoryLimit = MODULE_MEMORY_LIMIT_BYTES
        qjs.evaluationTimeoutMillis = MODULE_EVALUATION_TIMEOUT_MS
        try {
            bindConsole(qjs)
            bindAsyncFetch(qjs, fetchBase)

            qjs.evaluate<String>(POLYFILLS)
            val cleanCode = preprocessModuleCode(jsCode)

            qjs.evaluate<String>(
                """
                var __spine_iife_error = null;
                var __spine_mod = (function() {
                    try {
                        var module = { exports: {} };
                        var exports = module.exports;
                        var self = {};
                        $cleanCode
                        if (module.exports && (module.exports.searchTracks || module.exports.getTrackStreamUrl)) {
                            return module.exports;
                        }
                        return {};
                    } catch(e) {
                        __spine_iife_error = e && e.message ? e.message : String(e);
                        return {};
                    }
                })();
                'ok'
                """.trimIndent()
            )

            val iifeError = qjs.evaluate<String>("__spine_iife_error || 'none'")
            if (iifeError != "none") throw IllegalStateException("Module init error: $iifeError")

            val keys = qjs.evaluate<String>("Object.keys(__spine_mod).join(', ')")
            TrackLog.d(TAG, "  Module exports: [$keys]")
            return qjs
        } catch (e: Throwable) {
            qjs.close()
            throw e
        }
    }

    // ── Pool ─────────────────────────────────────────────────────────────

    /**
     * An interpreter of [moduleId]'s, exclusively, until it is given back.
     *
     * Takes a free one if there is one, makes another if the pool has room, and
     * otherwise waits for whoever is using one to finish. The claim on a new
     * engine is taken *before* it is built and released if building throws, so
     * a module whose script fails to evaluate cannot permanently consume a slot
     * in the pool it never joined.
     */
    private suspend fun acquire(moduleId: String, pool: Pool): QuickJs {
        pool.free.tryReceive().getOrNull()?.let { return it }

        val mine = pool.lock.withLock {
            if (pool.started >= ENGINES_PER_MODULE) return@withLock false
            pool.started++
            true
        }
        if (!mine) return pool.free.receive()

        return try {
            newEngine(pool.jsCode, pool.fetchBase).also { fresh ->
                pool.lock.withLock { pool.made += fresh }
            }
        } catch (e: Throwable) {
            pool.lock.withLock { pool.started-- }
            throw e
        }
    }

    // ── Call ─────────────────────────────────────────────────────────────

    suspend fun callExport(moduleId: String, functionName: String, args: List<String>): Result<String> {
        val pool = synchronized(engineLock) { pools[moduleId] }
            ?: return Result.failure(IllegalStateException("Module $moduleId is not loaded"))

        // Module settings may include API keys. Do not write arguments to
        // logcat; record only the shape of the call.
        TrackLog.d(TAG, "QuickJsExecutor.callExport($moduleId, $functionName) argCount=${args.size}")
        return withContext(Dispatchers.Default) {
            val qjs = try {
                acquire(moduleId, pool)
            } catch (e: Throwable) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                return@withContext Result.failure(e)
            }
            try {
                withTimeout(MODULE_CALL_TIMEOUT_MS) {
                    callOn(qjs, moduleId, functionName, args)
                }
            } finally {
                // Back into circulation on every path, including a throw: an
                // engine that is never returned is a slot the pool can never
                // hand out again, and three of those would deadlock the module.
                pool.free.trySend(qjs)
            }
        }
    }

    private suspend fun callOn(
        qjs: QuickJs,
        moduleId: String,
        functionName: String,
        args: List<String>,
    ): Result<String> =
        run {
            runCatching {
                val functionNameLiteral = JSONObject.quote(functionName)
                val hasFn = qjs.evaluate<String>("typeof __spine_mod[$functionNameLiteral]")
                if (hasFn != "function") {
                    throw IllegalStateException("$functionName is not a function on module $moduleId")
                }

                val argsStr = args.joinToString(",")

                // evaluate() converts a Promise via toString() instead of awaiting it.
                // Workaround: store the resolved JSON in a global var inside the async
                // IIFE, then read it in a second evaluate() call.
                qjs.evaluate<String>(
                    """
                    var __spine_resolved_json = undefined;
                    (async function() {
                        var __fn = __spine_mod[$functionNameLiteral];
                        if (!__fn) {
                            __spine_resolved_json = JSON.stringify({ error: $functionNameLiteral + ' not found' });
                            return;
                        }
                        try {
                            var r = await __fn($argsStr);
                            __spine_resolved_json = typeof r === 'string' ? r : JSON.stringify(r);
                        } catch(e) {
                            __spine_resolved_json = JSON.stringify({ error: e && e.message ? e.message : String(e) });
                        }
                    })();
                    """.trimIndent()
                )

                val rawResult = qjs.evaluate<String>("__spine_resolved_json")
                TrackLog.d(TAG, "  callExport result (${rawResult.length} chars)")
                rawResult
            }.onFailure {
                TrackLog.e(TAG, "  ✗ callExport FAILED for $moduleId.$functionName (${it.javaClass.simpleName})")
            }
        }

    // ── Unload ───────────────────────────────────────────────────────────

    fun unload(moduleId: String) {
        val closing = synchronized(engineLock) { pools.remove(moduleId) }?.made.orEmpty()
        closing.forEach { runCatching { it.close() } }
        TrackLog.d(TAG, "QuickJsExecutor.unload($moduleId)")
    }

    fun unloadAll() {
        val all = synchronized(engineLock) {
            val values = pools.values.flatMap { it.made }
            pools.clear()
            values
        }
        all.forEach { runCatching { it.close() } }
        TrackLog.d(TAG, "QuickJsExecutor.unloadAll()")
    }

    // ── Code pre-processing ──────────────────────────────────────────────

    /**
     * Strips ES-module `export` keywords so the code runs inside an IIFE
     * that wraps it in a CommonJS-style `module.exports` object.
     *
     * Also handles the template-literal export format some Spine sources use:
     * `export const x = \`…actual JS…\``
     */
    private fun preprocessModuleCode(jsCode: String): String {
        val code = jsCode.trim()

        val exportPattern = Regex("""^export\s+const\s+\w+\s*=\s*`""")
        val exportMatch = exportPattern.find(code)
        if (exportMatch != null) {
            val contentStart = exportMatch.range.last + 1
            var i = contentStart
            while (i < code.length) {
                if (code[i] == '\\' && i + 1 < code.length) { i += 2; continue }
                if (code[i] == '`') {
                    return code.substring(contentStart, i).trim()
                }
                i++
            }
            TrackLog.w(TAG, "  Template literal not closed, falling through to regex preprocess")
        }

        var result = code
        result = result.replace(Regex("""\bexport\s+default\s+(?=function|class|const|let|var|async)"""), "")
        result = result.replace(Regex("""\bexport\s+(const|let|var|function|class|async)\b"""), "$1")
        result = result.replace(Regex("""\bexport\s*\{[^}]*\}\s*;?"""), "")
        return result
    }

    // ── Console binding ──────────────────────────────────────────────────

    private fun bindConsole(qjs: QuickJs) {
        qjs.define("console") {
            // An add-on may log its own settings object, which can contain
            // API keys or session credentials. Keep call shape for debugging,
            // never persist arbitrary module-supplied values in app logs.
            function("log", object : FunctionBinding<Unit> {
                override fun invoke(args: Array<Any?>) {
                    TrackLog.d(TAG, "[JS] ${args.size} argument(s)")
                }
            })
            function("error", object : FunctionBinding<Unit> {
                override fun invoke(args: Array<Any?>) {
                    TrackLog.e(TAG, "[JS-ERR] ${args.size} argument(s)")
                }
            })
            function("warn", object : FunctionBinding<Unit> {
                override fun invoke(args: Array<Any?>) {
                    TrackLog.w(TAG, "[JS-WARN] ${args.size} argument(s)")
                }
            })
            function("info", object : FunctionBinding<Unit> {
                override fun invoke(args: Array<Any?>) {
                    TrackLog.i(TAG, "[JS-INFO] ${args.size} argument(s)")
                }
            })
        }
    }

    // ── Fetch binding ────────────────────────────────────────────────────

    private fun safeModuleOrigin(rawUrl: String): String =
        rawUrl.toHttpUrlOrNull()?.let { "${it.scheme}://${it.host}" } ?: "<invalid-url>"

    private suspend fun bindAsyncFetch(qjs: QuickJs, fetchBase: String) {
        qjs.define("__spine") {
            asyncFunction("fetch", object : AsyncFunctionBinding<String> {
                override suspend fun invoke(args: Array<Any?>): String {
                    val rawUrl = args[0]?.toString()
                        ?: throw IllegalArgumentException("fetch requires a URL")
                    val method = args[1]?.toString() ?: "GET"
                    val headersJson = args[2]?.toString() ?: "{}"
                    val body = args[3]?.toString()
                    val url = validateModuleFetchUrl(resolveUrl(rawUrl, fetchBase))

                    TrackLog.d(TAG, "  → fetch $method ${safeModuleOrigin(url)}")
                    val (statusCode, responseBody) = fetchUrlSync(url, method, headersJson, body)
                    TrackLog.d(TAG, "    HTTP $statusCode (${responseBody.length} bytes)")

                    val respObj = JSONObject().apply {
                        put("status", statusCode)
                        put("ok", statusCode in 200..299)
                        put("body", responseBody)
                    }
                    return respObj.toString()
                }
            })
            asyncFunction("setTimeout", object : AsyncFunctionBinding<String> {
                override suspend fun invoke(args: Array<Any?>): String {
                    val ms = args.getOrNull(1)?.toString()?.toLongOrNull() ?: 0L
                    kotlinx.coroutines.delay(ms)
                    return "0"
                }
            })
            asyncFunction("clearTimeout", object : AsyncFunctionBinding<String> {
                override suspend fun invoke(args: Array<Any?>): String = "ok"
            })
        }

        // Expose a web-compatible fetch() surface over the native binding.
        qjs.evaluate<Unit>(
            """
            var fetch = async function(url, options) {
                var method = 'GET';
                var headers = '{}';
                var body = null;
                if (options) {
                    method = options.method || 'GET';
                    if (options.headers) {
                        if (typeof options.headers === 'string') {
                            headers = options.headers;
                        } else {
                            try { headers = JSON.stringify(options.headers); } catch(e) { headers = '{}'; }
                        }
                    }
                    if (options.body !== undefined && options.body !== null) {
                        body = typeof options.body === 'string' ? options.body : JSON.stringify(options.body);
                    }
                    if (options.signal && options.signal.aborted) {
                        throw new Error('Aborted');
                    }
                }
                var raw = JSON.parse(await __spine.fetch(url, method, headers, body));
                var respBody = raw.body;
                return {
                    ok: raw.ok,
                    status: raw.status,
                    statusText: raw.ok ? 'OK' : 'Error',
                    json: function() { try { return JSON.parse(respBody); } catch(e) { throw new Error('Invalid JSON: ' + respBody.substring(0, 200)); } },
                    text: function() { return respBody; },
                    arrayBuffer: function() { throw new Error('Not implemented'); },
                    clone: function() { return this; },
                    headers: { get: function(k) { return null; } }
                };
            };

            var setTimeout = async function(fn, ms) {
                await __spine.setTimeout(null, ms || 0);
                if (typeof fn === 'function') fn();
                return 0;
            };
            var clearTimeout = function(id) {};
            """.trimIndent()
        )
    }

    // ── URL resolution ───────────────────────────────────────────────────

    private fun resolveUrl(url: String, base: String): String {
        if (url.startsWith("http://") || url.startsWith("https://")) return url
        if (base.isEmpty()) return url
        return if (url.startsWith("/")) {
            val scheme = base.substringBefore("://")
            val host = base.substringAfter("://").substringBefore("/")
            "$scheme://$host$url"
        } else {
            "$base/$url"
        }
    }

    private fun fetchUrlSync(
        url: String,
        method: String,
        headersJson: String,
        body: String?,
    ): Pair<Int, String> {
        val builder = Request.Builder().url(validateModuleFetchUrl(url))

        if (body != null) {
            require(body.length <= MAX_FETCH_REQUEST_BYTES) {
                "Module request body is too large"
            }
            require(body.toByteArray(Charsets.UTF_8).size <= MAX_FETCH_REQUEST_BYTES) {
                "Module request body is too large"
            }
        }
        require(headersJson.length <= 32 * 1024) { "Module request headers are too large" }

        var hasUserAgent = false
        try {
            val headersObj = JSONObject(headersJson)
            for (key in headersObj.keys()) {
                val value = headersObj.optString(key, "")
                builder.header(key, value)
                if (key.equals("user-agent", ignoreCase = true)) hasUserAgent = true
            }
        } catch (_: Exception) {
        }

        if (!hasUserAgent) {
            builder.header(
                "User-Agent",
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
            )
        }

        when (method.uppercase(Locale.ROOT)) {
            "POST" -> builder.post((body ?: "").toRequestBody("application/json; charset=utf-8".toMediaType()))
            "PUT" -> builder.put((body ?: "").toRequestBody("application/json; charset=utf-8".toMediaType()))
            "DELETE" -> builder.delete()
            "HEAD" -> builder.head()
            else -> builder.get()
        }

        moduleHttpClient.newCall(builder.build()).execute().use { response ->
            val responseBody = response.body?.let { responseBody ->
                if (responseBody.contentLength() > MAX_FETCH_RESPONSE_BYTES) {
                    throw IOException("Module response is too large")
                }
                val output = ByteArrayOutputStream()
                responseBody.byteStream().use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > MAX_FETCH_RESPONSE_BYTES) {
                            throw IOException("Module response is too large")
                        }
                        output.write(buffer, 0, count)
                    }
                }
                output.toString(Charsets.UTF_8.name())
            }.orEmpty()
            return response.code to responseBody
        }
    }

    // ── Polyfills ────────────────────────────────────────────────────────

    private const val POLYFILLS = """
        if (typeof AbortController === 'undefined') {
            var AbortController = function() { this.signal = { aborted: false }; };
            AbortController.prototype.abort = function() { this.signal.aborted = true; };
        }

        if (typeof Object.assign !== 'function') {
            Object.assign = function(target) {
                if (target == null) throw new TypeError('Cannot convert undefined or null to object');
                var to = Object(target);
                for (var i = 1; i < arguments.length; i++) {
                    var source = arguments[i];
                    if (source != null) {
                        for (var key in source) {
                            if (Object.prototype.hasOwnProperty.call(source, key)) {
                                to[key] = source[key];
                            }
                        }
                    }
                }
                return to;
            };
        }

        if (typeof Promise.any !== 'function') {
            Promise.any = function(promises) {
                return new Promise(function(resolve, reject) {
                    var errors = [];
                    var remaining = promises.length;
                    if (remaining === 0) { reject(new AggregateError([], 'All promises were rejected')); return; }
                    promises.forEach(function(p, i) {
                        Promise.resolve(p).then(resolve, function(e) {
                            errors[i] = e;
                            remaining--;
                            if (remaining === 0) reject(new AggregateError(errors, 'All promises were rejected'));
                        });
                    });
                });
            };
        }

        if (typeof Promise.allSettled !== 'function') {
            Promise.allSettled = function(promises) {
                return Promise.all(promises.map(function(p) {
                    return Promise.resolve(p).then(
                        function(value) { return { status: 'fulfilled', value: value }; },
                        function(reason) { return { status: 'rejected', reason: reason }; }
                    );
                }));
            };
        }

        if (typeof AggregateError === 'undefined') {
            var AggregateError = function(errors, message) {
                this.errors = errors;
                this.message = message || '';
                this.name = 'AggregateError';
            };
            AggregateError.prototype = Object.create(Error.prototype);
        }

        if (typeof atob === 'undefined') {
            var atob = function(input) {
                var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
                var str = String(input).replace(/=+${'$'}/, '');
                var output = '';
                for (var bc = 0, bs, buffer, idx = 0; buffer = str.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
                    buffer = chars.indexOf(buffer);
                }
                return output;
            };
        }

        if (typeof setTimeout === 'undefined') {
            var __spine_timers = {};
            var __spine_timer_id = 0;
            var setTimeout = function(fn, ms) {
                var id = ++__spine_timer_id;
                __spine_timers[id] = { fn: fn, ms: ms || 0 };
                return id;
            };
            var clearTimeout = function(id) {
                if (__spine_timers[id]) delete __spine_timers[id];
            };
        }
        if (typeof clearTimeout === 'undefined') {
            var clearTimeout = function(id) {
                if (typeof __spine_timers !== 'undefined' && __spine_timers[id]) delete __spine_timers[id];
            };
        }

        if (typeof URL === 'undefined') {
            var URL = function(url, base) {
                this.href = url;
                try {
                    var a = url.replace(/^[^:]+:/, 'http:');
                    var match = a.match(/^\/\/([^/]+)(\/.*)?$/);
                    if (match) {
                        this.hostname = match[1];
                        this.pathname = match[2] || '/';
                    } else {
                        var m2 = a.match(/^https?:\/\/([^/]+)(\/.*)?$/);
                        if (m2) { this.hostname = m2[1]; this.pathname = m2[2] || '/'; }
                    }
                } catch(e) {}
            };
        }
    """
}
