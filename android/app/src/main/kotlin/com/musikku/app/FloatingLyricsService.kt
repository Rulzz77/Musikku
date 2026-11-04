package com.musikku.app

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

class FloatingLyricsService : Service() {
    companion object {
        const val ACTION_UPDATE = "com.musikku.app.FLOATING_LYRICS_UPDATE"
        const val ACTION_STOP = "com.musikku.app.FLOATING_LYRICS_STOP"
        const val EXTRA_TEXT = "lyrics_text"
        @Volatile private var activeInstance: FloatingLyricsService? = null

        fun updateTextStatic(text: String) {
            activeInstance?.updateText(text)
        }
    }

    private var windowManager: WindowManager? = null
    private var overlay: View? = null
    private var lyricText: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopOverlay()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
                if (overlay == null) showOverlay()
                updateText(text)
            }
            else -> {
                if (overlay == null) showOverlay()
                updateText(intent?.getStringExtra(EXTRA_TEXT).orEmpty())
            }
        }
        return START_STICKY
    }

    private fun showOverlay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !android.provider.Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(9), dp(14), dp(10))
            background = GradientDrawable().apply {
                setColor(0xE91B2432.toInt())
                cornerRadius = dp(18).toFloat()
                setStroke(dp(1), 0x665FFFFFF.toInt())
            }
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val label = TextView(this).apply {
            text = "MUSIKKU · FLOATING LYRICS"
            textSize = 9f
            letterSpacing = 0.12f
            setTextColor(0xFFB8C7DD.toInt())
            typeface = Typeface.DEFAULT_BOLD
        }
        val close = TextView(this).apply {
            text = "×"
            textSize = 22f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            setPadding(dp(12), 0, dp(2), 0)
            setOnClickListener { stopOverlay(); stopSelf() }
        }
        header.addView(label, LinearLayout.LayoutParams(0, dp(28), 1f))
        header.addView(close, LinearLayout.LayoutParams(dp(30), dp(28)))
        val body = TextView(this).apply {
            text = "Lirik akan muncul saat lagu diputar"
            textSize = 15f
            setTextColor(0xFFFFFFFF.toInt())
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            maxLines = 3
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(3), 0, 0)
        }
        root.addView(header)
        root.addView(body)
        lyricText = body
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(90)
            x = 0
        }
        root.setOnTouchListener(DragListener())
        overlay = root
        runCatching { windowManager?.addView(root, params) }.onFailure {
            overlay = null
            lyricText = null
            stopSelf()
        }
    }

    private fun updateText(text: String) {
        lyricText?.text = text.trim().ifBlank { "Lirik tersinkron akan muncul di sini" }
    }

    private fun stopOverlay() {
        val view = overlay ?: return
        runCatching { windowManager?.removeView(view) }
        overlay = null
        lyricText = null
        params = null
    }

    private inner class DragListener : View.OnTouchListener {
        private var startX = 0
        private var startY = 0
        private var touchX = 0f
        private var touchY = 0f

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val layout = params ?: return false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = layout.x
                    startY = layout.y
                    touchX = event.rawX
                    touchY = event.rawY
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    layout.x = startX + (event.rawX - touchX).toInt()
                    layout.y = (startY + (event.rawY - touchY).toInt()).coerceAtLeast(dp(8))
                    runCatching { windowManager?.updateViewLayout(overlay, layout) }
                    return true
                }
            }
            return false
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        stopOverlay()
        if (activeInstance === this) activeInstance = null
        super.onDestroy()
    }
}
