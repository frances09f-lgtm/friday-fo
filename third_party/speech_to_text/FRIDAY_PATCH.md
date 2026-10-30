# Friday patch of speech_to_text 7.5.0

Copied from pub.dev `speech_to_text` 7.5.0 (BSD-3-Clause, LICENSE kept).
Only change: `SpeechToTextPlugin.kt` puts `RecognizerIntent.EXTRA_BIASING_STRINGS`
(Friday's command words, `FridayBiasing.words`) on the recognizer intent on
Android 13+, so the recognizer leans towards "above"/"below"/"gold" instead of
"about"/"blow"/"goal". Wired in through `dependency_overrides` in pubspec.yaml.
