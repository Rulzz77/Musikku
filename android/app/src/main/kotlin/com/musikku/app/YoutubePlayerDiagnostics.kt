package com.musikku.app

import android.os.Handler
import android.webkit.WebView
import org.json.JSONArray
import org.json.JSONObject

/**
 * Snapshot diagnostik yang aman ditampilkan di Settings tanpa Logcat.
 */
class YoutubePlayerDiagnostics(
    private val handler: Handler,
    private val getWebView: () -> WebView?,
    private val getVideoId: () -> String,
    private val getState: () -> String,
    private val getPreferredQuality: () -> String,
    private val getActualQuality: () -> String,
    private val isCaptionEnabled: () -> Boolean,
    private val getCaptionLanguage: () -> String,
) {
    fun snapshot(callback: (Map<String, Any?>) -> Unit) {
        val webView = getWebView()
        if (webView == null) {
            callback(baseSnapshot("webview_not_ready"))
            return
        }

        val script = """
            (function(){
              var r={
                videoId:${JSONObject.quote(getVideoId())},
                state:${JSONObject.quote(getState())},
                preferredQuality:${JSONObject.quote(getPreferredQuality())},
                actualQuality:${JSONObject.quote(getActualQuality())},
                captionsRequested:${isCaptionEnabled()},
                captionPreference:${JSONObject.quote(getCaptionLanguage())},
                ready:false,
                availableQualityLevels:[],
                currentQuality:'',
                captionTracks:0,
                captionLanguages:[],
                captionSelected:'',
                captionTranslation:'',
                captionActive:false,
                source:'webview'
              };
              try{
                var p=(typeof player!=='undefined')?player:null;
                r.ready=!!p;
                if(p){
                  // getPlaybackQuality/getAvailableQualityLevels sudah tidak
                  // menjadi sumber kualitas yang dapat diandalkan pada IFrame API.
                  // Kualitas aktual diisi dari onPlaybackQualityChange native.
                  try{
                    var list=p.getOption('captions','tracklist')||[];
                    r.captionTracks=list.length;
                    for(var i=0;i<list.length;i++){
                      if(list[i]&&list[i].languageCode) r.captionLanguages.push(list[i].languageCode);
                    }
                  }catch(e){}
                  try{
                    var track=p.getOption('captions','track');
                    if(track){
                      r.captionSelected=track.languageCode||'';
                      if(track.translationLanguage) r.captionTranslation=track.translationLanguage.languageCode||'';
                    }
                  }catch(e){}
                }
                if(window.__mkCc){
                  r.captionMode=window.__mkCc.mode||'';
                  r.captionSelected=r.captionSelected||window.__mkCc.selected||'';
                  r.captionTranslation=r.captionTranslation||window.__mkCc.translation||'';
                  r.captionActive=!!window.__mkCc.ok && ${isCaptionEnabled()};
                }
              }catch(e){r.error=String(e);}
              return JSON.stringify(r);
            })();
        """.trimIndent()

        try {
            webView.evaluateJavascript(script) { raw ->
                callback(parseJsResult(raw))
            }
        } catch (e: Exception) {
            callback(baseSnapshot("evaluate_failed:${e.message ?: "unknown"}"))
        }
    }

    private fun parseJsResult(raw: String?): Map<String, Any?> {
        if (raw.isNullOrBlank()) return baseSnapshot("empty")

        return try {
            // evaluateJavascript mengembalikan string JSON yang di-quote ketika
            // script memanggil JSON.stringify(...). Decode satu lapis dulu.
            val jsonText = if (raw.startsWith("\"") && raw.endsWith("\"")) {
                JSONObject("{\"v\":$raw}").getString("v")
            } else {
                raw
            }

            val obj = JSONObject(jsonText)
            val map = linkedMapOf<String, Any?>()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val value = obj.opt(key)
                map[key] = when (value) {
                    JSONObject.NULL -> null
                    is JSONArray -> (0 until value.length()).map { value.opt(it) }
                    else -> value
                }
            }
            map
        } catch (e: Exception) {
            baseSnapshot("parse_failed:${e.message ?: "invalid_json"}")
        }
    }

    private fun baseSnapshot(error: String): Map<String, Any?> =
        linkedMapOf(
            "videoId" to getVideoId(),
            "state" to getState(),
            "preferredQuality" to getPreferredQuality(),
            "actualQuality" to getActualQuality(),
            "captionsRequested" to isCaptionEnabled(),
            "captionPreference" to getCaptionLanguage(),
            "ready" to false,
            "availableQualityLevels" to emptyList<String>(),
            "currentQuality" to "",
            "captionTracks" to 0,
            "captionLanguages" to emptyList<String>(),
            "captionSelected" to "",
            "captionTranslation" to "",
            "captionActive" to false,
            "error" to error,
        )
}
