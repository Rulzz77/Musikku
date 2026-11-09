package com.musikku.app

import android.util.Log

/**
 * Logging policy for app-owned native code. Debug diagnostics are useful while
 * developing, but production logcat should not reveal playback identifiers,
 * metadata, extractor errors, or request details.
 */
internal object MusikKuLogger {
    fun d(tag: String, message: String) {
        if (BuildConfig.DEBUG) Log.d(tag, message)
    }

    fun i(tag: String, message: String) {
        if (BuildConfig.DEBUG) Log.i(tag, message)
    }

    fun w(tag: String, message: String, error: Throwable? = null) {
        if (!BuildConfig.DEBUG) return
        if (error == null) Log.w(tag, message) else Log.w(tag, message, error)
    }

    fun e(tag: String, message: String, error: Throwable? = null) {
        if (!BuildConfig.DEBUG) return
        if (error == null) Log.e(tag, message) else Log.e(tag, message, error)
    }
}
