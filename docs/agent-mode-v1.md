# Friday Agent Mode: core V1

## Existing architecture
Friday previously had no AccessibilityService. Local inference is flutter_gemma, not a GGUF loader. The existing local manager, voice input/TTS, installed-app launch bridge, command centre, chat and device pairing remain. Inference is serialized across chat and Agent Mode in the main engine. No cloud provider receives screen contents.

## New files
- android/app/src/main/kotlin/com/friday/assistant/FridayAccessibilityService.kt
- android/app/src/main/res/xml/friday_accessibility.xml
- lib/services/agent/agent_contract.dart
- lib/services/agent/friday_agent.dart
- lib/ui/screens/agent_mode_screen.dart
- test/friday_agent_test.dart
- test/agent_mode_ui_test.dart

## Modified files
- AndroidManifest.xml: exactly one accessibility service declaration.
- DeviceBridge.kt: accessibility channel registration and reusable app launch.
- friday_services.dart: shared model and Agent Mode provider.
- local_model_service.dart: serialized generation queue.
- friday_controller.dart: block chat/paired commands while main agent runs.
- command_center_screen.dart: optional Agent Mode entry.

## Loop
A user enters one supported task. A scoped goal contains the app and exact search text. Native Start requires enabled accessibility and installs a Stop overlay. Observe filters the foreground app tree to at most 70 useful nodes, 400 visits and depth 18; passwords are excluded. The local brain sees separate rules, goal, action-result metadata and untrusted screen data. It returns one JSON action. Both Dart and native code apply action restrictions. The executor rejects ambiguous targets or changed screen tokens. It performs one action, waits 900ms, observes again and checks the proposed expected UI evidence. Most actions also require a changed observation token. A successful native dispatch is not task completion.

The loop stops on completion evidence, unsafe/uncertain action, error, cancellation, 30 steps or three consecutive unverified actions. Limits are constructor-configurable. State includes the goal, observation, action/result, steps, retries and short metadata history. It does not auto-resume after process death.

## Implemented capabilities
Core task parsing accepts the four requested search/settings-navigation patterns: YouTube, Chrome and Instagram search; Settings to Bluetooth. Real Android operations include app launch, exact text/description/resource-ID target lookup, click, ACTION_SET_TEXT, search IME Enter on Android 11+, node scroll and bounds-derived swipe. Back/home are supported but require expected evidence; unsupported decisions stop safely. Finish checks package and visible query/result or Bluetooth-page signals. These are heuristic checks, not proof of semantic correctness on every app version.

The optional screen has text/voice input, compact progress, Stop, four presets and debug metadata. Stop also appears as an accessibility overlay over target apps. A 60-second native watchdog stops an idle abandoned session. Local logs contain action type and verification status, not task text, model reasons or screen content.

## Not implemented or not verified
No sending, calls, purchases, financial actions, settings toggles, permission grants, deletion, posting or sensitive form submission. Those actions cannot be approved and executed in this core milestone. No screenshot capture/vision, coordinate taps, fuzzy target matching, generic arbitrary tasks, automatic scroll-to-target recovery, model bundle/download changes or cross-engine arbitration. UI differences and local-model JSON quality may block tasks. Browser IME submission requires Android 11+. No four-task execution has been verified on a physical phone; automated tests use synthetic screens for loop/guard behavior.

## Permissions and setup
The user must explicitly enable Friday Agent in Android Accessibility settings. BIND_ACCESSIBILITY_SERVICE is the service binding permission, not a runtime permission prompt. Accessibility overlays do not require a separate draw-over-apps grant. Existing microphone permission is needed for voice. Agent screen reading/inference has no cloud dependency; voice transcription can use the existing hosted path and target web/app searches need their own network. A compatible installed Gemma model is required; Replier GGUF files are not compatible.

## Next milestone
Trial the four tasks on the actual phone with its installed model and apps. Fix observed node/verification failures first. Then add user-reviewed recovery/confirmation and optional screenshot fallback without widening the native effect scope silently.
