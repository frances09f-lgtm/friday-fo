# Friday v60 device-test candidate

- Read-screen selects underlying application windows, excluding Friday-owned UI; no arbitrary label deletion. Security application windows still stop. Direct summary remains local-only/transient.
- Assistant waits for actual TTS completion before automatic dismissal and ignores outside-tap dismissal while a request is still sending. Explicit stop/dismiss behavior remains available after completion.
- Exact observed target bounds can disambiguate duplicate labels; diagnostics identify failing action/app/workflow and exact match count. No invented coordinates or blind fallback tap.
- WhatsApp "open WhatsApp and search for NAME" supports observed search-control/focused field and live-filtered results. Stops at search results; does not open chats or send messages.
- Gallery ordinal playback adapted from user-authorized Abhijeet724/Operator GalleryPlayer.kt at commit9a03ef22dd0aa705f0cbedd6954ecfaddadbd92d: MediaStore sorted newest-added first, ordinals1..50, ACTION_VIEW to video player. "Open gallery and play first video" means newest-added device video, not first visible tile in a Gallery app. Requires media permission; grant then repeat command. Success is a launch request, not verified playback.
- Standalone "play first video" only runs when a fresh underlying YouTube screen exposes a unique search query and verified search results. Otherwise specify the source. Old search history is not reused.
- Preserves v58 search fallback and existing Qwen .task engine. No Operator blind-coordinate YouTube fallback copied.

Device behavior remains to be tested. The two v59 stop messages did not include the failing YouTube tree/step; this release does not claim every missing video card is fixed, nor that a reported permission stop was conclusively false. Ads/Shorts exclusion requires observed labels. Full semantic screenshot vision and Python repetition fix are not claimed.
