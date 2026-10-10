Friday update feature prepared for a future release, not v55.

- Pinned Firebase App Distribution Android SDK16.0.0-beta21 from Google's Maven metadata.
- Native foreground update check. Real SDK checkForNewRelease and updateApp.
- One-time tester sign-in, custom New version available / Update / Later.
- Checks at most once per hour per Activity; Later suppresses that release for24h. Newer version is not suppressed. Consent dismissed waits24h.
- No polling background service, no URL/token logs, no service-account access.
- Firebase app/project identity validated before starting. No config means inert, offline Friday still works.

Required before real update build:
1. Inject console google-services.json for com.friday.assistant. File ignored. Use CI secret FRIDAY_GOOGLE_SERVICES_JSON and require FRIDAY_FIREBASE_UPDATES_REQUIRED=true.
2. Firebase App Testers API enabled on app-testing-2cdba.
3. CI full native build/tests, actual phone sign-in, and later higher-build update test.
4. Same persistent signer. Keep existing Qwen0.5B .task engine untouched.

Source refs: https://firebase.google.com/codelabs/appdistribution-android
https://firebase.google.com/docs/reference/android/com/google/firebase/appdistribution/FirebaseAppDistribution
https://dl.google.com/dl/android/maven2/com/google/firebase/firebase-appdistribution/maven-metadata.xml

NOT yet verified: native compile, runtime dialog pixels, tester sign-in, actual later-build detection/download/install. Don't publish from this feature branch.
