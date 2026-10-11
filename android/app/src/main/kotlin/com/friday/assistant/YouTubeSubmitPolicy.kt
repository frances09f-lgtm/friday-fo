package com.friday.assistant

/** Keyboard fallback is a Search action, never generic Enter or Send. */
object YouTubeSubmitPolicy {
 fun permits(pkg:String, workflow:String, query:String, exactFields:Int, focused:Boolean):Boolean =
  pkg=="com.google.android.youtube" && workflow in setOf("search","play") && query.isNotBlank() && exactFields==1 && focused
 fun searchKey(text:String,description:String,enabled:Boolean,visible:Boolean,password:Boolean,editable:Boolean):Boolean =
  enabled && visible && !password && !editable &&
   listOf(text.trim(),description.trim()).filter{it.isNotEmpty()}.let { labels ->
    labels.isNotEmpty() && labels.all{it.equals("Search",ignoreCase=true)}
   }
 fun editorSearch(editorPackage:String,action:Int,started:Boolean,editorText:String,offset:Int,password:Boolean,query:String):Boolean =
  editorPackage=="com.google.android.youtube" && action==3 && started && !password && query.isNotBlank() && query.length<=250 && offset==0 && editorText==query
}
