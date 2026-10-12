# Friday v59 device-test candidate

Preserves the user-confirmed v58 YouTube/Chrome search fallback and Qwen .task engine.

- Read-screen output is a bounded accessibility overview: app, observed title where available, two key excerpts and three controls. It is shown in chat and spoken directly, not behind an Agent Mode link. No screenshot vision or full article summarization claimed.
- Screen replies remain local-only and transient, excluded from saved chat and cloud history. Password and editable-field contents are omitted from the overview.
- Exact compound "open youtube search for X and play first video" and "open youtube and search for X and play first video" parse as a search/play workflow, not one long app name.
- First regular video requires observed video-card semantics, screen bounds, unique topmost order and query identity. Ads/Shorts are excluded when labeled. If evidence is missing/ambiguous, Friday asks for manual selection. Playback completion still requires observed player/audio evidence. Phone behavior needs testing.
- Other "open APP and ACTION" compounds separate app name from action, request only the exact app launch, and clearly report the unsupported remainder. Gallery playback and standalone "play first video" are not added in this version.

Operator source review is in progress for a later version; no Operator code was copied into this build. Five-python model repetition remains undiagnosed. No arbitrary-app action scope or permission bypass added.
