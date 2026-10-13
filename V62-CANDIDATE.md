# Friday v62 device-test candidate

User selected OnePlus Gallery for Gallery-video commands, replacing the v61 Friday-local player.

- Selects local video using the existing user-authorized Operator MediaStore newest-added ordinal logic.
- Sends ACTION_VIEW content URI with read permission strictly to com.oneplus.gallery, after live installed-app and video-handler checks on the phone.
- Never uses Android's unspecified default video player, Friday player, Google Photos or another OEM Gallery as fallback.
- If the selected Gallery package is absent or cannot handle the URI, reports the problem and asks for App info; no alternate player is opened.
- Reply describes a request to OnePlus Gallery, not verified playback. The app may require the user to press play depending on its handler/version. No blind accessibility taps added to force autoplay.

Operator source unchanged and prior attribution retained. Package discovery lead: https://sysapps.bayton.org/packages/com.oneplus.gallery . Device identity/handler checked at runtime, not inferred only from this source. README unchanged; Qwen .task, WhatsApp search and screen-summary changes retained. Physical/visual destination and autoplay remain unverified until user tests. Only Gallery destination changed in this build.
