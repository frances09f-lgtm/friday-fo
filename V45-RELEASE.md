Friday v45 - invalid planner decision recovery

Fixes v44 phone-test failure on "open YouTube and search for GTA 6": syntactically valid JSON with absent/zero/low confidence previously skipped malformed-output recovery and stopped. Local decisions now require finite confidence, authorized scope, unique observed target and verification package before acceptance. When invalid, the separate deterministic workflow parser can propose an exact unique observed search control or field. It does not promote model confidence, disable target safety, or permit ambiguous clicks.

Existing Qwen0.5B .task model/runtime/path/hash unchanged. No GGUF, conversion or extra model download. Preserves v44 guarded screen workflows and measured bar controls. Phone retest remains required; next/previous ignored media keys remain unresolved without media-app/queue/direct-session access choice. No full-spec completion or real-device success claim.

209 Flutter tests pass and analyze has no errors (existing lint warnings). CI native APK and task-unit tests required before release.
