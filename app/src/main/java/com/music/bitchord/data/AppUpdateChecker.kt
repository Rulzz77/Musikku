
package com.music.bitchord.data

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import com.music.bitchord.BuildConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Request
import java.io.File
import java.security.MessageDigest

object AppUpdateChecker {

    private const val CACHE_SUBDIR = "updates"

    private const val LATEST_RELEASE_URL =
        "https://api.github.com/repos/Rulzz77/Musikku/releases/latest"

    // Use the active Android variant's version for both local installs and CI releases.
    private val APP_VERSION = BuildConfig.VERSION_NAME

    // Harus sesuai dengan nama APK pada GitHub Releases.
    private const val APK_PREFIX = "MusikKu-"

    private val json = Json {
        ignoreUnknownKeys = true
    }

    data class UpdateInfo(
        val version: String,
        val releaseUrl: String,
        val apkUrl: String?,
        val notes: String?,
        /** SHA-256 published by GitHub for the selected APK asset. */
        val apkSha256: String? = null,
    )

    private val _available = MutableStateFlow<UpdateInfo?>(null)
    val available = _available.asStateFlow()

    sealed interface DownloadState {

        data object Idle : DownloadState

        data class Downloading(
            val fraction: Float,
        ) : DownloadState

        data class Ready(
            val file: File,
        ) : DownloadState

        data class Failed(
            val message: String,
        ) : DownloadState
    }

    private val _download =
        MutableStateFlow<DownloadState>(DownloadState.Idle)

    val download = _download.asStateFlow()

    @Volatile
    private var downloadCancelled = false

    // Prevent two taps/retries from writing the same cache file concurrently.
    private val downloadMutex = Mutex()

    @Volatile
    private var activeDownloadCall: Call? = null

    /**
     * Check the latest published GitHub release.
     */
    suspend fun check() = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url(LATEST_RELEASE_URL)
                .header("Accept", "application/vnd.github+json")
                .header("User-Agent", "MusikKu-Android")
                .build()

            val responseBody = Http.client
                .newCall(request)
                .execute()
                .use { response ->

                    if (!response.isSuccessful) {
                        throw IllegalStateException(
                            "GitHub request failed: HTTP ${response.code}"
                        )
                    }

                    response.body.string()
                }

            val release = json.parseToJsonElement(responseBody)
                    as? JsonObject
                ?: throw IllegalStateException(
                    "Invalid GitHub release response."
                )

            val tag = release["tag_name"]
                ?.jsonPrimitive
                ?.contentOrNull
                ?: throw IllegalStateException(
                    "Release tag not found."
                )

            val releaseUrl = release["html_url"]
                ?.jsonPrimitive
                ?.contentOrNull
                ?: throw IllegalStateException(
                    "Release URL not found."
                )

            val latestVersion = tag.removePrefix("v")

            val notes = release["body"]
                ?.jsonPrimitive
                ?.contentOrNull

            val apkAsset = selectApkAsset(release, Build.SUPPORTED_ABIS.toList())

            _available.value = if (
                isNewer(latestVersion, APP_VERSION)
            ) {
                UpdateInfo(
                    version = latestVersion,
                    releaseUrl = releaseUrl,
                    apkUrl = apkAsset?.url,
                    notes = notes,
                    apkSha256 = apkAsset?.sha256,
                )
            } else {
                null
            }

        }.onFailure {
            if (it is CancellationException) throw it
            // Pertahankan state sebelumnya jika pengecekan gagal.
        }
    }

    /**
     * Finds a signed-release APK for this device and keeps GitHub's published
     * SHA-256 alongside the URL. Assets without a valid digest are deliberately
     * excluded: the updater must never mark an unverified file as installable.
     *
     * Priority:
     * 1. APK matching device ABI.
     * 2. Universal APK as fallback.
     */
    internal data class VerifiedApkAsset(
        val variant: String,
        val url: String,
        val sha256: String,
    )

    internal fun selectApkAsset(
        release: JsonObject,
        supportedAbis: List<String>,
    ): VerifiedApkAsset? {
        val assets = release["assets"]
            ?.jsonArray
            ?.mapNotNull { it as? JsonObject }
            ?.mapNotNull { asset ->
                val name = asset["name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                val url = asset["browser_download_url"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                val digest = asset["digest"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                val uploaded = asset["state"]?.jsonPrimitive?.contentOrNull == "uploaded"

                val sha256 = digest
                    .takeIf { it.startsWith("sha256:", ignoreCase = true) }
                    ?.substringAfter(':')
                    ?.takeIf(::isValidSha256)
                    ?: return@mapNotNull null

                if (
                    !uploaded ||
                    !name.startsWith(APK_PREFIX, ignoreCase = true) ||
                    !name.endsWith(".apk", ignoreCase = true) ||
                    !url.startsWith("https://github.com/", ignoreCase = true)
                ) {
                    return@mapNotNull null
                }

                VerifiedApkAsset(
                    variant = name.substring(APK_PREFIX.length).substringBeforeLast("."),
                    url = url,
                    sha256 = sha256.lowercase(),
                )
            }
            .orEmpty()

        return supportedAbis.firstNotNullOfOrNull { abi ->
            assets.firstOrNull { it.variant.equals(abi, ignoreCase = true) }
        } ?: assets.firstOrNull { it.variant.equals("universal", ignoreCase = true) }
    }

    internal fun isValidSha256(value: String): Boolean =
        value.length == 64 && value.all { it in '0'..'9' || it.lowercaseChar() in 'a'..'f' }

    internal fun sha256Matches(expected: String, actual: String): Boolean =
        isValidSha256(expected) &&
            isValidSha256(actual) &&
            MessageDigest.isEqual(
                expected.lowercase().toByteArray(Charsets.US_ASCII),
                actual.lowercase().toByteArray(Charsets.US_ASCII),
            )

    /**
     * Clear cached update APK files.
     */
    suspend fun clearCache(context: Context) =
        withContext(Dispatchers.IO) {

            val directory = File(
                context.cacheDir,
                CACHE_SUBDIR,
            )

            directory.listFiles()?.forEach { file ->
                if (file.isDirectory) {
                    file.deleteRecursively()
                } else {
                    file.delete()
                }
            }
        }

    /**
     * Download APK and report progress.
     */
    suspend fun downloadApk(context: Context) = withContext(Dispatchers.IO) {
        if (!downloadMutex.tryLock()) return@withContext

        try {
            val info = _available.value ?: return@withContext
            val url = info.apkUrl
            val expectedSha256 = info.apkSha256

            if (url.isNullOrBlank() || expectedSha256.isNullOrBlank()) {
                _download.value = DownloadState.Failed(
                    "APK atau informasi integritasnya tidak tersedia. Buka halaman rilis GitHub untuk mengunduh manual."
                )
                return@withContext
            }

            if (!isValidSha256(expectedSha256)) {
                _download.value = DownloadState.Failed(
                    "Hash APK dari GitHub tidak valid. Instalasi otomatis dibatalkan."
                )
                return@withContext
            }

            downloadCancelled = false
            _download.value = DownloadState.Downloading(0f)

            var partialFile: File? = null
            var call: Call? = null

            try {
                val directory = File(context.cacheDir, CACHE_SUBDIR)
                if (!directory.exists() && !directory.mkdirs()) {
                    throw IllegalStateException("Tidak dapat membuat folder download.")
                }

                // Only one updater owns this directory at a time (downloadMutex).
                directory.listFiles()?.forEach { file ->
                    if (!file.deleteRecursively()) {
                        throw IllegalStateException("Tidak dapat membersihkan cache APK lama.")
                    }
                }

                val target = File(directory, "musikku-${info.version}.apk")
                val temporary = File(directory, "${target.name}.part")
                partialFile = temporary

                val request = Request.Builder()
                    .url(url)
                    .header("User-Agent", "MusikKu-Android")
                    .build()

                val activeCall = Http.client.newCall(request)
                call = activeCall
                activeDownloadCall = activeCall

                val digest = MessageDigest.getInstance("SHA-256")
                activeCall.execute().use { response ->
                    if (!response.isSuccessful) {
                        throw IllegalStateException("Download gagal: HTTP ${response.code}")
                    }

                    val body = response.body
                    val total = body.contentLength()

                    body.byteStream().use { input ->
                        temporary.outputStream().use { output ->
                            val buffer = ByteArray(64 * 1024)
                            var downloaded = 0L

                            while (true) {
                                if (downloadCancelled) {
                                    temporary.delete()
                                    _download.value = DownloadState.Idle
                                    return@withContext
                                }

                                val count = input.read(buffer)
                                if (count == -1) break

                                output.write(buffer, 0, count)
                                digest.update(buffer, 0, count)
                                downloaded += count

                                if (total > 0L) {
                                    val progress = downloaded.toFloat() / total.toFloat()
                                    _download.value = DownloadState.Downloading(
                                        progress.coerceIn(0f, 1f)
                                    )
                                }
                            }

                            output.flush()
                        }
                    }
                }

                if (downloadCancelled) {
                    temporary.delete()
                    _download.value = DownloadState.Idle
                    return@withContext
                }

                check(temporary.exists() && temporary.length() > 0L) {
                    "File APK kosong atau tidak ditemukan."
                }

                val actualSha256 = digest.digest().joinToString("") { "%02x".format(it) }
                check(sha256Matches(expectedSha256, actualSha256)) {
                    "Verifikasi integritas APK gagal. File tidak cocok dengan rilis GitHub."
                }

                check(temporary.renameTo(target)) {
                    "APK sudah diverifikasi, tetapi tidak dapat disiapkan untuk installer."
                }

                _download.value = DownloadState.Ready(target)
            } catch (cancelled: CancellationException) {
                partialFile?.delete()
                _download.value = DownloadState.Idle
                throw cancelled
            } catch (error: Exception) {
                partialFile?.delete()
                _download.value = if (downloadCancelled) {
                    DownloadState.Idle
                } else {
                    DownloadState.Failed(
                        error.message ?: "Download gagal."
                    )
                }
            } finally {
                if (call != null && activeDownloadCall === call) {
                    activeDownloadCall = null
                }
            }
        } finally {
            downloadMutex.unlock()
        }
    }

    /**
     * Cancel active download.
     */
    fun cancelDownload() {
        downloadCancelled = true
        activeDownloadCall?.cancel()
    }

    /**
     * Reset download state.
     */
    fun resetDownload() {
        cancelDownload()
        _download.value = DownloadState.Idle
    }

    /**
     * Open Android package installer.
     */
    fun installApk(
        context: Context,
        file: File,
    ) {
        if (!file.exists() || file.length() <= 0L) {
            _download.value = DownloadState.Failed(
                "File APK tidak valid."
            )
            return
        }

        // Minta izin instalasi dari sumber tidak dikenal.
        if (!context.packageManager.canRequestPackageInstalls()) {

            val opened = runCatching {

                context.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    )
                        .setData(
                            "package:${context.packageName}".toUri()
                        )
                        .addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK
                        )
                )

            }.isSuccess

            if (opened) return
        }

        runCatching {

            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file,
            )

            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(
                    uri,
                    "application/vnd.android.package-archive",
                )
                .addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_ACTIVITY_NEW_TASK,
                )

            context.startActivity(intent)

        }.onFailure { error ->

            _download.value = DownloadState.Failed(
                error.message ?: "Tidak dapat membuka installer."
            )
        }
    }

    private data class ParsedVersion(
        val parts: List<Int>,
        val isPreRelease: Boolean,
    )

    /**
     * Parse version, for example:
     * 1.0.0
     * 1.0.1
     * 1.0.0-beta
     */
    private fun parseVersion(raw: String): ParsedVersion {

        val dashIndex = raw.indexOf('-')

        val base = if (dashIndex >= 0) {
            raw.substring(0, dashIndex)
        } else {
            raw
        }

        return ParsedVersion(
            parts = base.split(".").map { part ->
                part.toIntOrNull() ?: 0
            },
            isPreRelease = dashIndex >= 0,
        )
    }

    /**
     * Compare numeric versions.
     *
     * 1.10.0 > 1.9.0
     * 1.0.1 > 1.0.0
     * 1.0.0 > 1.0.0-beta
     */
    private fun isNewer(
        latest: String,
        current: String,
    ): Boolean {

        val latestVersion = parseVersion(latest)
        val currentVersion = parseVersion(current)

        val maxParts = maxOf(
            latestVersion.parts.size,
            currentVersion.parts.size,
        )

        for (index in 0 until maxParts) {

            val latestPart =
                latestVersion.parts.getOrElse(index) { 0 }

            val currentPart =
                currentVersion.parts.getOrElse(index) { 0 }

            if (latestPart != currentPart) {
                return latestPart > currentPart
            }
        }

        return currentVersion.isPreRelease &&
                !latestVersion.isPreRelease
    }
}
