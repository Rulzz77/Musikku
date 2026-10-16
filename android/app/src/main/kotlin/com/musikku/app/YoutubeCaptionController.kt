package com.musikku.app

import android.os.Handler
import android.webkit.WebView

/**
 * Controller subtitle dengan mode eksplisit:
 * - id / en = track langsung jika tersedia
 * - original = track asli pertama yang tersedia
 * - auto:id / auto:en = terjemahan otomatis dari track pertama
 */
class YoutubeCaptionController(
    private val handler: Handler,
    private val getWebView: () -> WebView?,
    private val getVideoId: () -> String,
    private val isEnabled: () -> Boolean,
    private val getLanguage: () -> String,
) {
    companion object {
        private const val TAG = "MusikKuCaption"
    }

    fun applyNow() {
        val webView = getWebView() ?: return
        val enabled = isEnabled()
        val mode = getLanguage().trim().ifBlank { "id" }
        val vid = getVideoId()
        val validSpecialMode = mode in setOf("original", "auto:id", "auto:en")
        val validLanguageCode = Regex("^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*$").matches(mode)
        if ((!validSpecialMode && !validLanguageCode) ||
            !Regex("^[A-Za-z0-9_-]{11}$").matches(vid)) {
            // These values are interpolated into a JavaScript string below.
            // Reject unexpected characters instead of trying to escape arbitrary script input.
            return
        }

        val safeMode = mode
        val safeVid = vid

        val script = if (enabled) {
            """
            (function(mode,vid){
              var r={on:true,mode:mode,tracks:0,languages:[],selected:'',translation:''};
              try{
                var p=(typeof player!=='undefined')?player:null;
                if(!p||!p.setOption){r.err='noplayer';return JSON.stringify(r);}

                var target='';
                if(mode==='auto:id'){target='id';}
                else if(mode==='auto:en'){target='en';}

                function apply(){
                  try{
                    var opts=[];
                    try{opts=p.getOptions()||[];}catch(e){}
                    var captionsReady=opts.indexOf('captions')>=0;
                    if(!captionsReady){
                      try{p.loadModule('captions');}catch(e){}
                      return false;
                    }

                    var list=[];
                    try{list=p.getOption('captions','tracklist')||[];}catch(e){}
                    r.tracks=list.length;
                    r.languages=[];
                    for(var j=0;j<list.length;j++){
                      if(list[j]&&list[j].languageCode)r.languages.push(list[j].languageCode);
                    }

                    var track=null;
                    if(mode==='original'){
                      if(list.length) track={languageCode:list[0].languageCode};
                    }else if(target){
                      // Translation selection works by choosing a source track
                      // and attaching the desired translation language.
                      if(list.length){
                        var tl={languageCode:target};
                        try{
                          var tls=list[0].translationLanguages||[];
                          for(var t=0;t<tls.length;t++){
                            if(tls[t]&&tls[t].languageCode===target){tl=tls[t];break;}
                          }
                        }catch(e){}
                        track={languageCode:list[0].languageCode,translationLanguage:tl};
                      }
                      else track={languageCode:target,translationLanguage:{languageCode:target}};
                    }else{
                      for(var i=0;i<list.length;i++){
                        var c=(list[i].languageCode||'');
                        if(c===mode||c.indexOf(mode+'-')===0){track={languageCode:c};break;}
                      }
                      // The captions module can still accept the requested
                      // language even when tracklist is temporarily empty
                      // (common with auto-generated captions).
                      if(!track && mode && mode!=='original') track={languageCode:mode};
                    }

                    if(!track){
                      r.err='track_not_ready';
                      return false;
                    }

                    try{p.setOption('captions','track',track);}catch(e){r.err='set_track:'+String(e);return false;}
                    try{p.setOption('captions','reload',true);}catch(e){}
                    r.selected=track.languageCode||'';
                    r.translation=(track.translationLanguage&&track.translationLanguage.languageCode)||'';
                    r.ok=true;
                    window.__mkCc={vid:vid,mode:mode,selected:r.selected,translation:r.translation,ok:true};
                    return true;
                  }catch(e){r.err=String(e);return false;}
                }

                // First try immediately after loading the module, then retry
                // because YouTube exposes the captions module asynchronously.
                try{p.loadModule('captions');}catch(e){}
                if(!apply()){
                  var waits=[250,650,1200,2200,3500,5500];
                  for(var k=0;k<waits.length;k++){
                    (function(delay){setTimeout(function(){apply();},delay);})(waits[k]);
                  }
                }
              }catch(e){r.err=String(e);}
              return JSON.stringify(r);
            })('$safeMode','$safeVid');
            """.trimIndent()
        } else {
            """
            (function(vid){try{
              var p=(typeof player!=='undefined')?player:null;
              window.__mkCc={vid:vid,mode:'off',ok:false};
              if(p){
                // Empty track disables the active caption selection first;
                // unloading both module aliases prevents it from immediately
                // reappearing after a state change.
                try{p.setOption('captions','track',{});}catch(e){}
                try{p.unloadModule('captions');}catch(e){}
                try{p.unloadModule('cc');}catch(e){}
              }
            }catch(e){}})('$safeVid');
            """.trimIndent()
        }

        fun run() {
            try {
                webView.evaluateJavascript(script) { value ->
                    if (BuildConfig.DEBUG) MusikKuLogger.d(TAG, "CAPTION RESULT=$value")
                }
            } catch (e: Exception) {
                if (BuildConfig.DEBUG) MusikKuLogger.e(TAG, "CAPTION APPLY FAILED", e)
            }
        }

        val delays = if (enabled) {
            longArrayOf(0L, 700L, 1800L, 3600L, 6000L)
        } else {
            longArrayOf(0L, 450L, 1400L)
        }

        for (delay in delays) {
            if (delay == 0L) webView.post { run() }
            else webView.postDelayed({ run() }, delay)
        }
    }
}
