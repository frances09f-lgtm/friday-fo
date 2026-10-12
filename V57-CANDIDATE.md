# Friday v57 device-test candidate

Based on v56, preserving Qwen 0.5B .task / MediaPipe inference and existing actions.

- "Read my screen" and bounded read/describe aliases now route to the accessibility read workflow rather than chat generation. This fixes the app's own Screen shortcut.
- Empty or escaped-newline-only model output is rejected as no readable response. It is not evidence that an action happened.
- Failed screen reads no longer receive a misleading completed status in chat. Read screen contents remain transient and local.
- YouTube focuses the unique observed search field before typing/submitting. On old results pages, it prefers the unique explicit clickable Search opener over search-labelled containers. Completion still requires observed results.
- Saved Oro quote watches use a reusable source/compare pipeline, skip unchanged values, and reject stale, future, invalid or out-of-order evidence. Numeric thresholds use no model or Internet request.
- Battery-saver WorkManager respects a 15-minute floor and requested longer intervals, with low-battery constraints. Existing foreground-service mode retains about five-minute checks with a persistent notification; Android can delay either mode.
- Notification failures remain eligible for retry. Stable notification IDs replace crash retries rather than duplicating alerts.

Not proven on the user's phone: YouTube search submission, accessibility availability, notifications after app closure/reboot. No screenshot vision, arbitrary app support, Internet price feed, or background LLM summary is added. The optional change handler is an extension interface, not a configured model integration. Oro must refresh its saved quote; values older than five minutes cannot alert. No trades are placed.

Verification so far: 253 Flutter tests and eight new pure Kotlin engine tests passed. Signed Android build and APK audit remain pending.
