package com.friday.assistant

import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaBrowser
import androidx.media3.session.SessionToken
import io.flutter.plugin.common.MethodChannel

/** Search the selected app's own catalog. No intent that autoplays its first hit. */
@UnstableApi
object BitChordSongSearch {
 private var cancelPending:(()->Unit)?=null
 fun cancel(){cancelPending?.invoke()}
 fun execute(c:Context,query:String,result:MethodChannel.Result) {
  if(cancelPending!=null){result.success("bitchord_search_busy");return}
  if(query.isBlank()||query.length>200){result.success("bitchord_search_invalid");return}
  val main=Handler(Looper.getMainLooper());val executor=ContextCompat.getMainExecutor(c)
  var browser:MediaBrowser?=null;var done=false;var fetching=false;var submitted=false
  lateinit var future:com.google.common.util.concurrent.ListenableFuture<MediaBrowser>
  fun finish(code:String){if(done)return;done=true;cancelPending=null;main.removeCallbacksAndMessages(null);browser?.release();if(browser==null)androidx.media3.session.MediaController.releaseFuture(future);result.success(code)}
  cancelPending={finish(if(submitted)"bitchord_song_unverified" else "bitchord_search_cancelled")}
  val listener=object:MediaBrowser.Listener {
   override fun onSearchResultChanged(b:MediaBrowser,q:String,itemCount:Int,params:androidx.media3.session.MediaLibraryService.LibraryParams?) {
    if(done||fetching||q!=query)return
    fetching=true
    if(itemCount<=0){finish("bitchord_search_no_match");return}
    // Incomplete/truncated results cannot prove uniqueness.
    if(itemCount>100){finish("bitchord_search_ambiguous");return}
    val found=b.getSearchResult(query,0,100,params)
    found.addListener({
     if(done)return@addListener
     try {
      val items=found.get().value?.toList()?:run{finish("bitchord_search_unavailable");return@addListener}
      val songs=items.filter{it.mediaMetadata.isPlayable==true}.map{BitChordSongPolicy.Song(it.mediaId,it.mediaMetadata.title?.toString().orEmpty(),it.mediaMetadata.artist?.toString().orEmpty())}
      val chosen=BitChordSongPolicy.select(query,songs,items.size==itemCount)
      if(chosen==null){finish(if(songs.isEmpty())"bitchord_search_no_match" else "bitchord_search_ambiguous");return@addListener}
      if(!b.isCommandAvailable(Player.COMMAND_SET_MEDIA_ITEM)||!b.isCommandAvailable(Player.COMMAND_PREPARE)||!b.isCommandAvailable(Player.COMMAND_PLAY_PAUSE)){finish("bitchord_search_unavailable");return@addListener}
      val item=items.first{it.mediaId==chosen.id};submitted=true
      b.setMediaItem(item);b.prepare();b.play()
      var checks=0
      val check=object:Runnable{override fun run(){
       if(done)return
       if(b.isPlaying&&b.currentMediaItem?.mediaId==chosen.id){finish("bitchord_verified_song");return}
       if(++checks>=20){finish("bitchord_song_unverified");return}
       main.postDelayed(this,500)
      }};main.postDelayed(check,250)
     }catch(_:Exception){finish(if(submitted)"bitchord_song_unverified" else "bitchord_search_unavailable")}
    },executor)
   }
  }
  try {
   val token=SessionToken(c,ComponentName(BitChordPolicy.PACKAGE,"com.music.bitchord.playback.PlaybackService"))
   future=MediaBrowser.Builder(c,token).setListener(listener).buildAsync()
   main.postDelayed({finish(if(submitted)"bitchord_song_unverified" else "bitchord_search_timeout")},25000)
   future.addListener({if(done)return@addListener;try{val b=future.get();browser=b;val search=b.search(query,null);search.addListener({if(!done)try{if(search.get().resultCode!=0)finish("bitchord_search_unavailable")}catch(_:Exception){finish("bitchord_search_unavailable")}},executor)}catch(_:Exception){finish("bitchord_search_unavailable")}},executor)
  }catch(_:Exception){cancelPending=null;done=true;cancelPending=null;main.removeCallbacksAndMessages(null);browser?.release();result.success("bitchord_search_unavailable")}
 }
}
