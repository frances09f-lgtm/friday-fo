Friday v47 - observed Chrome omnibox recipe

Adds a deterministic recipe for the user's Chrome search phone-test failure: use one uniquely observed URL/search bar, focus and verify editable/focused state, type exact user query, submit using native IME action, and verify an observed search URL with that exact decoded q parameter. Typed text alone is not completion. If Chrome hides full URL/query or exposes multiple bars, it stops without claiming a result; this is not generic browser vision or proof of result accuracy.

Keeps v46 search-label/Stop-overlay guards and existing .task local planner/runtime/model for other workflows. No new model download, GGUF engine, permission or notification access. 216 automated Flutter tests pass; analyze no errors(existing warnings). Native CI and phone retest required.

Retest "Open Chrome and search for latest gold price". If blocked, Agent Mode's Last decision, build label and metadata log identify the failed step. Real-device workflow success remains unverified. Music Play/Next direct session issue remains pending user's app/queue/access choice.

YouTube v46 phone feedback: opens and types GTA6, but search did not submit. Added observed YouTube recipe: submit exact typed query through IME, then try a distinct uniquely observed Search button if IME did not verify. Native alternate submit requires one editable field containing the exact authorized query. Duplicate buttons remain blocked; results verification still required. 218 tests pass after submit regressions. This addresses a tested failed step, but new submit behavior needs phone retest.

Speed follow-up: all recognized safe observed workflow recipes (including WhatsApp/ChatGPT fields) run before a model call, so known unique controls need no repeated inference. Initial post-action wait is250ms instead of900ms, with additional read-only waits only until verification succeeds(up to4seconds). Safety, ambiguity and post-action evidence are retained. Actual phone speed not benchmarked. WhatsApp failure details still pending; no claim that recipe priority fixes every layout.
