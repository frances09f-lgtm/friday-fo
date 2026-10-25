package com.friday.assistant

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Optional offline speech recognition: the needle engine running the Shruti
 * model (udgamlabs/Shruti on HuggingFace, Apache-2.0). The model file is
 * downloaded once into app storage from Settings; recognition then runs on
 * the phone and the audio never leaves it.
 *
 * needle keeps one process-global, non-thread-safe model, so every call is
 * serialized behind [gate] on a single worker thread. The main app engine
 * and the floating-bar overlay engine live in the same process and register
 * the same channel; the lock covers both.
 */
object ShrutiBridge {
    private const val CHANNEL = "friday/shruti"

    private val worker = Executors.newSingleThreadExecutor()
    private val gate = ReentrantLock()

    @Volatile
    private var loadedModelPath: String? = null

    private val nativeAvailable: Boolean by lazy {
        try {
            System.loadLibrary("friday_shruti")
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun register(messenger: BinaryMessenger) {
        if (!nativeAvailable) {
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { _, result ->
                result.error("unavailable", "Shruti native engine is not in this build", null)
            }
            return
        }
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "transcribe" -> {
                    val modelPath = call.argument<String>("modelPath")
                    val wavPath = call.argument<String>("wavPath")
                    if (modelPath.isNullOrEmpty() || wavPath.isNullOrEmpty()) {
                        result.error("bad_args", "modelPath and wavPath are required", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        val reply = gate.withLock {
                            try {
                                if (loadedModelPath != modelPath) {
                                    val loadError = nativeLoadModel(modelPath)
                                    if (loadError != null) {
                                        loadedModelPath = null
                                        errorJson("Model failed to load: $loadError")
                                    } else {
                                        loadedModelPath = modelPath
                                        nativeTranscribeWav(wavPath)
                                    }
                                } else {
                                    nativeTranscribeWav(wavPath)
                                }
                            } catch (t: Throwable) {
                                errorJson(t.message ?: "native transcription failed")
                            }
                        }
                        Handler(Looper.getMainLooper()).post { result.success(reply) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun errorJson(message: String): String {
        val escaped = message.replace("\\", "\\\\").replace("\"", "\\\"")
        return "{\"error\":\"$escaped\"}"
    }

    private external fun nativeLoadModel(path: String): String?
    private external fun nativeTranscribeWav(path: String): String
}
