# Friday v58 search fallback device-test candidate

Preserves all v57 fixes and saved-Oro-quote watches.

YouTube verified-query loss and two unverified YouTube/Chrome UI actions now have one package-scoped results-intent fallback. Uses the existing URL-encoded exact query route. Native checks the active unlocked task, foreground app, screen token, exact query and package, and refuses a second fallback. Does not retype, inject Enter/Send, choose another app, or invent an Instagram route.

Intent dispatch alone is not completion. YouTube must show actual results; Chrome must expose the exact Google search URL query. Google URL verification is restricted to google.com/www.google.com and /search. If the app hides its result semantics, Friday stops honestly. Play still requires observed player/audio completion.

Physical-device completion remains unverified. The repeated "python" response is not diagnosed or fixed here; no model/runtime replacement. Qwen .task engine unchanged. Device-test candidate, not general autonomous phone control.
