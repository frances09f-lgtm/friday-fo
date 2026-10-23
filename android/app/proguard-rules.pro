# Friday release shrinking rules. Broad keeps on purpose: this build was made
# smaller without changing behaviour, so reflection and native-bridge classes
# stay intact.

# App code: services, receivers and channel handlers referenced by the manifest
# or by name.
-keep class com.friday.assistant.** { *; }

# On-device AI (MediaPipe tasks-genai through flutter_gemma_mediapipe).
-keep class com.google.mediapipe.** { *; }
-keep class com.google.ai.edge.** { *; }
-keep class dev.flutterberlin.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.auto.value.**
-dontwarn javax.lang.model.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn org.checkerframework.**

# flutter_local_notifications serialises scheduled reminders with Gson.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Native methods and WorkManager workers.
-keepclasseswithmembernames class * { native <methods>; }
-keep class * extends androidx.work.ListenableWorker { *; }
