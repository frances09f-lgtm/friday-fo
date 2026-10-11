# Friday Android assistant

Talk or type to Friday, use supported phone commands, or try checked screen actions in Agent Mode. This README describes the latest published Android release, currently **v56**. Main and a release tag can differ; use the release tag when reproducing a published APK.

## Install and start

1. Open the repository's **Releases** section and download `Friday.apk` from v56 or the newest published Android release. Windows releases are separate.
2. Install on an ARM64 Android phone. Allow installation from your browser or Files app if Android asks. Android 8.0 or newer is required.
3. Open Friday. Start with a typed command. You do not need every permission or an AI key just to open the app.
4. Open **Settings / Overview** for model, provider and permission setup. Save changed settings using **Save**.

## Choose how to get answers

Supported command patterns are handled by the offline command engine before cloud chat. For other chat, configured cloud providers are tried in order: Gemini, Groq, OpenRouter. If they fail, the enabled on-device fallback is tried, then the basic offline engine. Offline commands do not mean arbitrary app tasks can work without a model.

### Optional cloud API keys

Use your own provider account. Create a key in the provider console, then enter it on the phone under **Settings → Cloud fallback keys**:

| Provider | Create your key | App field |
| --- | --- | --- |
| Gemini | `https://aistudio.google.com/apikey` | Gemini API key |
| Groq | `https://console.groq.com/keys` | Groq API key |
| OpenRouter | `https://openrouter.ai/keys` | OpenRouter API key |

Any one configured provider can be used for cloud chat. Groq and OpenRouter also have model-name fields; keep the default unless your provider offers a different model you intend to use. Availability, free quotas and pricing belong to the provider and can change. No paid upgrade is required by this setup guide.

Keys are entered at runtime and kept in encrypted device storage, not compiled into the APK. Cloud requests transmit the prompt and relevant chat context to the selected provider. A key is a secret: never paste it in this README, GitHub issues, screenshots or source code. No shared provider key is supplied.

## Set up the existing local model

Agent Mode uses the local planner. Cloud-chat keys do not replace its local-model setup.

1. Open **Settings → Manage existing .task model**, or **Agent Mode → Set up local model · 547 MB**.
2. Use the guided Qwen setup. The existing model is **Qwen2.5-0.5B-Instruct**, a `.task` file using MediaPipe CPU inference. It is not a GGUF installer.
3. Keep Friday open while downloading. The app checks storage and requires at least 3 GB total RAM. The download is 546,660,344 bytes plus setup space. Use a stable connection.
4. Download can resume from its partial file. Wait for verification and registration, then use **Load and test**.
5. A model response proves local inference started. It does **not** prove Agent Mode can finish every phone task.

The guided setup pins revision `6c237a59eedeb06a821b21f0a59b03d346ac8bc3`, file `Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task`, and SHA256 `e608953f169aeb1bd7b9155fec2559825e08453fc209b84eda3a781ed0452fd2`. Let the app use its existing guided URL. Do not substitute Gemma, a different Qwen revision, converted GGUF weights or an arbitrary model link. **Advanced legacy .task installer** is a separate compatibility path, not the normal guided setup.

## Grant only the permissions you use

- **Microphone:** for voice input. Without it, type instead.
- **Accessibility Service:** enable Friday in Android Accessibility settings for Agent Mode's accessible-screen reading and checked actions. This grants sensitive access; do not enable it on someone else's phone without their knowledge.
- **Floating assistant / Assistant setup:** review display-over-other-apps permission for the floating bar. Default-assistant/power-button behavior depends on Android and your phone's settings.
- **SMS:** needed for SMS-reading commands. Declining it does not grant access through another route.
- **Notifications / exact alarms:** reminders may need these Android permissions. Check the app's setup status and Android settings if reminders do not appear.
- **Spotify controls:** optional notification access is separate from microphone and screen-control setup.

Voice input uses Android speech recognition; available languages depend on the installed speech service. **Speak replies out loud** controls text-to-speech. Do not assume always-listening wake-word behavior or guaranteed background operation.

## Try Agent Mode safely

1. Install/open YouTube and confirm the phone has internet.
2. Load/test the local model and enable Friday Accessibility.
3. Open **Agent Mode**, type `search gta 6 on youtube`, and tap **Start**.
4. Watch what happens. Use **STOP** to cancel.
5. If it stops, open **Last decision · local diagnostic**. Report the Android version, app version, observed screen and the decision. Redact private screen/message contents before sharing.

v56 adds an Android 13+ editor Search-action path for YouTube. It checks the app, focused editor and exact query and then re-observes the result. A dispatched action is not a completed search. The published release is a candidate fix; the requested actual APK YouTube test is still in progress. Search/playback success on your phone is not yet established. Older Android versions use the prior checked fallback.

## Troubleshooting

- **Cloud auth/quota error:** check the selected provider key and account limits. Remove or replace a revoked key in Settings.
- **Download slow/stops:** keep Friday open, check internet/free storage, and resume rather than replacing the model.
- **Local loading fails:** capture the setup diagnostic. RAM, storage and native-engine support can matter. Do not claim model success from download completion alone.
- **Typed search does not submit:** on v56, disable/re-enable Friday Accessibility once if Android has not refreshed the editor flag. Retry and inspect Last decision.
- **Voice unavailable:** grant microphone access and check Android's speech engine. Typed chat remains available.
- **Phone action fails:** review the supported **Commands** screen and that action's permission. Do not assume the cloud model can bypass Android restrictions.

## Build from source

Check out the published release tag for that release. CI uses Flutter 3.47.6 and Java 17:

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release --target-platform android-arm64
cd android && ./gradlew :app:testReleaseUnitTest
```

CI uses a permanent private release signer. A local/debug-signed APK cannot update the owner's signed APK in place. Configure your own keystore for your own distribution. Never commit signing passwords or a keystore. Provider keys belong in the app's runtime Settings, not build flags, assets or CI logs.
