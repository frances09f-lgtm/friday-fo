# Friday

An on-device AI phone assistant for Android, built in Flutter. Talk or type;
Friday answers, and actually does things on the phone: opens apps, reads your
messages, sets reminders. Named after Iron Man's FRIDAY.

## How Friday thinks (the fallback ladder)

1. **Cloud brains first** - every free-tier API key you add, tried in order.
2. **On-device model** - a small Gemma model running locally (flutter_gemma),
   used when every key fails or you have no network.
3. **Offline engine** - pure pattern matching, no model and no network. Still
   handles the core phone commands: open apps, read messages, set reminders.

Every answer is tagged in the chat with which brain produced it
(cloud / on-device / offline).

## Free API keys

Any ONE of these is enough. All have free tiers; the key never leaves the
phone (stored in Android Keystore via flutter_secure_storage):

- **Google Gemini** (default): https://aistudio.google.com/apikey
- **Groq** (fast Llama): https://console.groq.com/keys
- **OpenRouter** (free models): https://openrouter.ai/keys

## On-device model

Friday uses [flutter_gemma](https://pub.dev/packages/flutter_gemma) to run a
Gemma model locally. The weights are NOT bundled; open Settings in the app,
paste the model URL, and tap Install model (one-time download, then offline).
Free weights: a Gemma 3n E2B `.task` file from Hugging Face
(see https://fluttergemma.dev for current model links).

## Phone actions

| Action | How | Permission |
| --- | --- | --- |
| Open apps | Launch intents via PackageManager (MainActivity.kt) | none |
| Read messages | SMS inbox query via a method channel | READ_SMS (asked when first needed) |
| Set reminders | flutter_local_notifications, exact alarms | SCHEDULE_EXACT_ALARM |

The cloud and local brains answer with a strict JSON envelope
(reply + action), parsed defensively by `FridayParser`; malformed answers
deteriorate to plain chat, never a crash.

## Build it

```bash
flutter pub get
flutter run            # on a connected device or emulator
flutter test           # unit tests (offline engine + parser)
flutter build apk --release
```

The release build is debug-signed out of the box so you get an installable
APK immediately; add your own keystore before publishing.

- minSdk 26 (flutter_gemma needs it), targetSdk 34.
- If Gradle complains about the NDK version, run `flutter doctor` and let
  Flutter's own ndkVersion stand.

## Voice

Speech-to-text uses Android's Google engine (`speech_to_text`), so English
(en-IN), Hindi, and Marathi all work - change `localeId` in
`SpeechService.startListening`. Text replies are spoken back with
`flutter_tts` (toggle in Settings).

Optional upgrade path: [Cactus Whistle](https://cactuscompute.com/blog/whistle)
(16.9 MB, runs on CPU, keyword biasing for wake words) can replace the input
side. Only `SpeechService` needs to change; its gap is language coverage
(7 languages, no Hindi or Marathi), so keep the system engine for those.

## Project layout

```
lib/
  models/          ChatMessage, FridayAction / FridayResponse
  services/
    ai/            AIBrain (fallback ladder), Gemini, Groq/OpenRouter,
                   LocalModelService (flutter_gemma), OfflineEngine, FridayParser
    device/        DeviceHub (method channel), ReminderService
    intent_router  Executes FridayAction on the phone
    speech/        SpeechService (STT + TTS)
    storage/       SettingsStore (secure keys), ChatStore (history)
  state/           FridayController (one turn end to end)
  ui/              Home (chat), Settings
android/
  app/src/main/kotlin/com/friday/assistant/MainActivity.kt   (device bridge)
test/              Offline engine + parser unit tests
```

## Roadmap

- Wake word ("Hey Friday") in the background
- More actions: alarms, calls, maps navigation
- RAG over on-device notes
- Whistle wake-word + system STT hybrid for Hindi/Marathi
