package com.music.bitchord.data.stats

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log
import androidx.annotation.Keep
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import java.io.IOException
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Automatic cloud snapshots use the Android document provider selected by the
 * user. Selecting a Google Drive folder grants access only to that folder;
 * MusikKu does not store a Google OAuth token or upload credentials.
 *
 * The destination URI is device-local and deliberately lives outside
 * AppSettings, so it is never copied to another phone by Backup.exportTo().
 */
object AutoBackupController {
    private const val PREFS = "musikku_auto_backup"
    private const val KEY_FOLDER_URI = "folder_uri"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_LAST_SUCCESS = "last_success_at"
    private const val KEY_LAST_ERROR = "last_run_failed"
    private const val PERIODIC_WORK = "musikku_auto_backup_periodic"
    private const val ONE_TIME_WORK = "musikku_auto_backup_once"

    data class Status(
        val folderUri: String? = null,
        val enabled: Boolean = false,
        val lastSuccessAtMillis: Long = 0L,
        val lastRunFailed: Boolean = false,
    ) {
        val configured: Boolean get() = !folderUri.isNullOrBlank()
    }

    fun status(context: Context): Status = prefs(context).let { p ->
        Status(
            folderUri = p.getString(KEY_FOLDER_URI, null),
            enabled = p.getBoolean(KEY_ENABLED, false),
            lastSuccessAtMillis = p.getLong(KEY_LAST_SUCCESS, 0L),
            lastRunFailed = p.getBoolean(KEY_LAST_ERROR, false),
        )
    }

    fun observe(context: Context): Flow<Status> = callbackFlow {
        val preferences = prefs(context)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
            trySend(status(context))
        }
        preferences.registerOnSharedPreferenceChangeListener(listener)
        trySend(status(context))
        awaitClose { preferences.unregisterOnSharedPreferenceChangeListener(listener) }
    }.distinctUntilChanged()

    /** Stores explicit folder consent and schedules the initial snapshot. */
    fun setFolder(context: Context, folder: Uri) {
        require(folder.scheme == "content" && DocumentsContract.isTreeUri(folder)) {
            "Choose a folder from the system document picker"
        }
        val resolver = context.contentResolver
        val access = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        resolver.takePersistableUriPermission(folder, access)
        check(resolver.persistedUriPermissions.any { it.uri == folder && it.isWritePermission }) {
            "The selected folder did not grant persistent write access"
        }

        val preferences = prefs(context)
        val previous = preferences.getString(KEY_FOLDER_URI, null)
        preferences.edit()
            .putString(KEY_FOLDER_URI, folder.toString())
            .putBoolean(KEY_ENABLED, true)
            .putLong(KEY_LAST_SUCCESS, 0L)
            .putBoolean(KEY_LAST_ERROR, false)
            .apply()

        if (!previous.isNullOrBlank() && previous != folder.toString()) {
            runCatching {
                resolver.releasePersistableUriPermission(Uri.parse(previous), access)
            }
        }
        schedule(context, runImmediately = true)
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        val current = status(context)
        require(!enabled || current.configured) { "Choose a backup folder first" }
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (enabled) {
            schedule(context, runImmediately = true)
        } else {
            val manager = WorkManager.getInstance(context)
            manager.cancelUniquePeriodicWork(PERIODIC_WORK)
            manager.cancelUniqueWork(ONE_TIME_WORK)
        }
    }

    /** A one-off backup is also available when the daily schedule is disabled. */
    fun backupNow(context: Context): Boolean {
        if (!status(context).configured) return false
        prefs(context).edit().putBoolean(KEY_LAST_ERROR, false).apply()
        enqueueOneTime(context, manual = true, replace = false)
        return true
    }

    private fun schedule(context: Context, runImmediately: Boolean) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val periodic = PeriodicWorkRequestBuilder<AutoBackupWorker>(24, TimeUnit.HOURS)
            .setConstraints(constraints)
            .build()
        val manager = WorkManager.getInstance(context)
        manager.enqueueUniquePeriodicWork(
            PERIODIC_WORK,
            ExistingPeriodicWorkPolicy.UPDATE,
            periodic,
        )
        if (runImmediately) enqueueOneTime(context, manual = false, replace = true)
    }

    private fun enqueueOneTime(context: Context, manual: Boolean, replace: Boolean) {
        val request = OneTimeWorkRequestBuilder<AutoBackupWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setInputData(workDataOf(AutoBackupWorker.KEY_MANUAL to manual))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            ONE_TIME_WORK,
            if (replace) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP,
            request,
        )
    }

    internal fun markSuccess(context: Context, folderUri: String) {
        val preferences = prefs(context)
        if (preferences.getString(KEY_FOLDER_URI, null) != folderUri) return
        preferences.edit()
            .putLong(KEY_LAST_SUCCESS, System.currentTimeMillis())
            .putBoolean(KEY_LAST_ERROR, false)
            .apply()
    }

    internal fun markFailure(context: Context, folderUri: String?) {
        val preferences = prefs(context)
        if (folderUri != null && preferences.getString(KEY_FOLDER_URI, null) != folderUri) return
        preferences.edit().putBoolean(KEY_LAST_ERROR, true).apply()
    }

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

internal const val AUTO_BACKUP_PREFIX = "MusikKu-Auto-Backup-"

internal fun autoBackupFileName(timestampMillis: Long): String =
    AUTO_BACKUP_PREFIX + AUTO_BACKUP_DATE_FORMAT.format(java.time.Instant.ofEpochMilli(timestampMillis)) + ".json"

private val AUTO_BACKUP_DATE_FORMAT =
    java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd_HH-mm-ss-SSS", Locale.ROOT)
        .withZone(java.time.ZoneOffset.UTC)

@Keep
class AutoBackupWorker(
    context: Context,
    parameters: androidx.work.WorkerParameters,
) : CoroutineWorker(context, parameters) {

    override suspend fun doWork(): Result {
        val manual = inputData.getBoolean(KEY_MANUAL, false)
        val status = AutoBackupController.status(applicationContext)
        if (!manual && !status.enabled) return Result.success()
        val folderText = status.folderUri
        if (folderText.isNullOrBlank()) return Result.failure()

        val folder = Uri.parse(folderText)
        var pending: Uri? = null
        return try {
            val resolver = applicationContext.contentResolver
            val hasWriteGrant = resolver.persistedUriPermissions.any {
                it.uri == folder && it.isWritePermission
            }
            if (!hasWriteGrant) throw SecurityException("Cloud backup folder access was revoked")

            val parentId = DocumentsContract.getTreeDocumentId(folder)
            val parent = DocumentsContract.buildDocumentUriUsingTree(folder, parentId)
            val timestamp = System.currentTimeMillis()
            val finalName = autoBackupFileName(timestamp)
            val pendingUri = DocumentsContract.createDocument(
                resolver,
                parent,
                "application/json",
                AUTO_BACKUP_PREFIX + timestamp + ".pending",
            ) ?: throw IOException("Cloud provider could not create a backup file")
            pending = pendingUri

            val exported = Backup.exportTo(applicationContext, pendingUri)
            exported.exceptionOrNull()?.let { throw it }
            publish(resolver, parent, pendingUri, finalName)
            pending = null
            AutoBackupController.markSuccess(applicationContext, folderText)
            runCatching { pruneOldBackups(resolver, folder) }
            Log.i(TAG, "Automatic cloud backup saved")
            Result.success()
        } catch (cancelled: CancellationException) {
            pending?.let {
                runCatching { DocumentsContract.deleteDocument(applicationContext.contentResolver, it) }
            }
            throw cancelled
        } catch (failure: Exception) {
            pending?.let {
                runCatching { DocumentsContract.deleteDocument(applicationContext.contentResolver, it) }
            }
            AutoBackupController.markFailure(applicationContext, folderText)
            Log.w(TAG, "Automatic cloud backup failed", failure)
            if (failure is SecurityException) Result.failure() else Result.retry()
        }
    }

    private fun publish(
        resolver: android.content.ContentResolver,
        parent: Uri,
        pending: Uri,
        finalName: String,
    ): Uri {
        val renamed = runCatching {
            DocumentsContract.renameDocument(resolver, pending, finalName)
        }.getOrNull()
        if (renamed != null) return renamed

        val finalUri = DocumentsContract.createDocument(
            resolver,
            parent,
            "application/json",
            finalName,
        ) ?: throw IOException("Cloud provider could not publish the completed backup")
        try {
            resolver.openInputStream(pending)?.use { input ->
                resolver.openOutputStream(finalUri, "wt")?.use { output ->
                    input.copyTo(output)
                } ?: throw IOException("Cloud provider did not open the backup for writing")
            } ?: throw IOException("Cloud provider did not open the temporary backup")
        } catch (failure: Exception) {
            runCatching { DocumentsContract.deleteDocument(resolver, finalUri) }
            throw failure
        }
        runCatching { DocumentsContract.deleteDocument(resolver, pending) }
        return finalUri
    }

    private fun pruneOldBackups(resolver: android.content.ContentResolver, folder: Uri) {
        val parentId = DocumentsContract.getTreeDocumentId(folder)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(folder, parentId)
        val documents = mutableListOf<Pair<String, Uri>>()
        resolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            if (idColumn >= 0 && nameColumn >= 0) {
                while (cursor.moveToNext()) {
                    val id = cursor.getString(idColumn) ?: continue
                    val name = cursor.getString(nameColumn) ?: continue
                    if (name.startsWith(AUTO_BACKUP_PREFIX) && name.endsWith(".json")) {
                        documents += name to DocumentsContract.buildDocumentUriUsingTree(folder, id)
                    }
                }
            }
        } ?: return

        documents.sortedByDescending { it.first }
            .drop(MAX_KEPT_BACKUPS)
            .forEach { (_, uri) ->
                runCatching { DocumentsContract.deleteDocument(resolver, uri) }
            }
    }

    companion object {
        const val KEY_MANUAL = "manual_backup"
        private const val TAG = "MusikKuAutoBackup"
        private const val MAX_KEPT_BACKUPS = 7
    }
}
