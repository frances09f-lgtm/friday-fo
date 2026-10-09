Friday v47 - observed Chrome omnibox recipe

Adds a deterministic recipe for the user's Chrome search phone-test failure: use one uniquely observed URL/search bar, focus and verify editable/focused state, type exact user query, submit using native IME action, and verify an observed search URL with that exact decoded q parameter. Typed text alone is not completion. If Chrome hides full URL/query or exposes multiple bars, it stops without claiming a result; this is not generic browser vision or proof of result accuracy.

Keeps v46 search-label/Stop-overlay guards and existing .task local planner/runtime/model for other workflows. No new model download, GGUF engine, permission or notification access. 216 automated Flutter tests pass; analyze no errors(existing warnings). Native CI and phone retest required.

Retest "Open Chrome and search for latest gold price". If blocked, Agent Mode's Last decision, build label and metadata log identify the failed step. Real-device workflow success remains unverified. Music Play/Next direct session issue remains pending user's app/queue/access choice.
