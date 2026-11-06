package com.friday.assistant
import java.text.Normalizer
/** Catalog identity only. Never treats a fuzzy title or first result as a match. */
object BitChordSongPolicy {
 data class Song(val id:String,val title:String,val artist:String)
 fun normalized(s:String):String = Normalizer.normalize(s,Normalizer.Form.NFKC).lowercase(java.util.Locale.ROOT).replace(Regex("[^\\p{L}\\p{N}]+")," ").trim()
 fun select(query:String,songs:List<Song>,complete:Boolean):Song? {
  if(!complete)return null
  val pieces=query.split(Regex("\\s+by\\s+",RegexOption.IGNORE_CASE),limit=2)
  val title=normalized(pieces[0]);val artist=pieces.getOrNull(1)?.let(::normalized)
  if(title.isEmpty()||artist=="")return null
  val matches=songs.filter{it.id.isNotBlank()&&normalized(it.title)==title&&(artist==null||normalized(it.artist)==artist)}.distinctBy{it.id}
  return matches.singleOrNull()
 }
}
