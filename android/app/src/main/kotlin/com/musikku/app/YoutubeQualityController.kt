package com.musikku.app

import android.os.Handler
import android.webkit.WebView

/**
 * Pengatur preferensi kualitas YouTube.
 *
 * Penting: IFrame Player API modern tidak menjamin setPlaybackQuality().
 * Helper ini hanya menerapkan hint/layout preference. Kualitas yang benar-benar
 * dipilih diverifikasi melalui callback onPlaybackQualityChange di
 * YoutubePlatformView.
 */
class YoutubeQualityController(
    private val handler: Handler,
    private val getWebView: () -> WebView?,
    private val getVideoId: () -> String,
    private val getPreferredQuality: () -> String,
    private val getCrop: () -> Double = { 1.0 },
) {
    companion object {
        private const val TAG = "MusikKuQuality"

        fun normalize(requested: String): String? =
            when (requested.trim().lowercase()) {
                "default", "auto" -> "default"
                "tiny", "144p" -> "tiny"
                "small", "240p" -> "small"
                "medium", "360p" -> "medium"
                "large", "480p" -> "large"
                "hd720", "720p" -> "hd720"
                "hd1080", "1080p" -> "hd1080"
                "highres", "1440p", "2160p" -> "highres"
                else -> null
            }
    }

    private var hintKey = ""

    fun apply(force: Boolean) {
        val webView = getWebView() ?: return
        val quality = getPreferredQuality()
        val key = "${getVideoId()}|$quality"
        val sendHint = force || hintKey != key
        if (sendHint) hintKey = key

        val (w, h) = targetSize(quality)
        val crop = getCrop().coerceIn(1.0, 1.3)
        val script = """
            (function(q,w,h,hint,crop){
              var info={q:q};
              try{
                var dpr=window.devicePixelRatio||1;
                var f=document.querySelector('iframe')||document.getElementById('youTubePlayerDOM');
                if(f){
                  var cw=Math.max(200,Math.round(w/dpr));
                  var ch=Math.round(cw*h/w);
                  info.css=cw+'x'+ch;
                  document.documentElement.style.overflow='hidden';
                  if(document.body){document.body.style.overflow='hidden';}
                  var fit=function(){
                    var vw=window.innerWidth||document.documentElement.clientWidth;
                    var vh=window.innerHeight||document.documentElement.clientHeight;
                    if(!vw||!vh){return;}
                    var s=Math.min(vw/cw,vh/ch)*crop;
                    var sp=function(k,v){f.style.setProperty(k,v,'important');};
                    sp('position','absolute');sp('border','0');
                    sp('max-width','none');sp('max-height','none');
                    sp('width',cw+'px');sp('height',ch+'px');
                    sp('transform-origin','0 0');sp('transform','scale('+s+')');
                    sp('left',((vw-cw*s)/2)+'px');sp('top',((vh-ch*s)/2)+'px');
                  };
                  window.__mkFit=fit;
                  fit();
                  if(!window.__mkFitBound){
                    window.__mkFitBound=true;
                    window.addEventListener('resize',function(){if(window.__mkFit){window.__mkFit();}});
                  }
                }
                info.api='adaptive';
                info.hintSent=!!hint;
              }catch(e){info.err=String(e);}
              return JSON.stringify(info);
            })('$quality',$w,$h,$sendHint,$crop);
        """.trimIndent()

        fun run() {
            try {
                webView.evaluateJavascript(script) { value ->
                    MusikKuLogger.d(TAG, "QUALITY HINT RESULT=$value")
                }
            } catch (e: Exception) {
                MusikKuLogger.e(TAG, "QUALITY HINT FAILED", e)
            }
        }

        webView.post { run() }

        if (sendHint) {
            webView.postDelayed({ run() }, 1500L)
            webView.postDelayed({ run() }, 4000L)
        }
    }

    fun invalidateVideo() {
        hintKey = ""
    }

    private fun targetSize(quality: String): Pair<Int, Int> =
        when (quality) {
            "tiny" -> 256 to 144
            "small" -> 426 to 240
            "medium" -> 640 to 360
            "large" -> 854 to 480
            "hd720" -> 1280 to 720
            "hd1080" -> 1920 to 1080
            "highres" -> 2560 to 1440
            else -> 1280 to 720
        }
}
