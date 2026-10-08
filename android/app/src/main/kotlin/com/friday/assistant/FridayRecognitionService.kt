package com.friday.assistant

import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * A real RecognitionService backed by Groq's hosted Whisper - the same
 * engine the Windows build uses for voice input. Android requires the
 * default assistant to name a recognitionService, and once Friday IS the
 * default, SpeechRecognizer clients (including Friday's own mic) are
 * routed here, so this has to actually work, not be a stub.
 *
 * Records 16 kHz mono PCM until onStopListening/onCancel (20 s cap),
 * posts it as WAV to whisper-large-v3-turbo (English/Hindi/Marathi) and
 * returns the transcript. Without a built key it errors honestly.
 */
class FridayRecognitionService : RecognitionService() {

    private val io = Executors.newSingleThreadExecutor()
    @Volatile private var recorder: AudioRecord? = null
    @Volatile private var capturing = false

    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        if (listener == null) return
        val key = RuntimeSecrets.read(this)
        if (key.isEmpty()) {
            listener.error(SpeechRecognizer.ERROR_CLIENT)
            return
        }
        io.execute { recordAndTranscribe(key, listener) }
    }

    override fun onCancel(listener: Callback?) {
        capturing = false
        try { recorder?.stop() } catch (_: Exception) {}
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
    }

    override fun onStopListening(listener: Callback?) {
        // Signal the capture loop to finish; it transcribes what it got.
        capturing = false
    }

    private fun recordAndTranscribe(key: String, listener: Callback) {
        val rate = 16000
        val minBuf = AudioRecord.getMinBufferSize(
            rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuf <= 0) {
            listener.error(SpeechRecognizer.ERROR_CLIENT)
            return
        }
        val rec = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC, rate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                minBuf * 2)
        } catch (e: Exception) {
            listener.error(SpeechRecognizer.ERROR_CLIENT)
            return
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            listener.error(SpeechRecognizer.ERROR_CLIENT)
            return
        }
        recorder = rec
        val pcm = ByteArrayOutputStream()
        val buf = ByteArray(3200) // 100 ms
        try {
            rec.startRecording()
            capturing = true
            listener.readyForSpeech(Bundle())
            listener.beginningOfSpeech()
            val deadline = System.currentTimeMillis() + 20000
            while (capturing && System.currentTimeMillis() < deadline) {
                val n = rec.read(buf, 0, buf.size)
                if (n > 0) pcm.write(buf, 0, n)
            }
        } catch (e: Exception) {
            listener.error(SpeechRecognizer.ERROR_AUDIO)
            return
        } finally {
            capturing = false
            try { rec.stop() } catch (_: Exception) {}
            rec.release()
            recorder = null
        }
        listener.endOfSpeech()
        val audio = pcm.toByteArray()
        if (audio.size < 3200) { // under ~100 ms of speech
            listener.error(SpeechRecognizer.ERROR_NO_MATCH)
            return
        }
        val text = try {
            transcribeGroq(key, wav(audio, rate))
        } catch (e: Exception) {
            null
        }
        if (text.isNullOrEmpty()) {
            listener.error(SpeechRecognizer.ERROR_SERVER)
            return
        }
        listener.results(Bundle().apply {
            putStringArrayList(
                SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(text))
            putFloatArray(SpeechRecognizer.CONFIDENCE_SCORES, floatArrayOf(1.0f))
        })
    }

    /** 44-byte RIFF header around raw 16-bit mono PCM. */
    private fun wav(pcm: ByteArray, rate: Int): ByteArray {
        val header = ByteArrayOutputStream(44)
        fun putInt(v: Int) {
            header.write(v and 0xff); header.write((v shr 8) and 0xff)
            header.write((v shr 16) and 0xff); header.write((v shr 24) and 0xff)
        }
        fun putShort(v: Int) { header.write(v and 0xff); header.write((v shr 8) and 0xff) }
        header.write("RIFF".toByteArray(Charsets.US_ASCII)); putInt(36 + pcm.size)
        header.write("WAVE".toByteArray(Charsets.US_ASCII))
        header.write("fmt ".toByteArray(Charsets.US_ASCII)); putInt(16)
        putShort(1); putShort(1); putInt(rate); putInt(rate * 2); putShort(2); putShort(16)
        header.write("data".toByteArray(Charsets.US_ASCII)); putInt(pcm.size)
        val out = ByteArrayOutputStream(44 + pcm.size)
        out.write(header.toByteArray()); out.write(pcm)
        return out.toByteArray()
    }

    private fun transcribeGroq(key: String, wavBytes: ByteArray): String {
        val boundary = "frid4yboundary"
        val conn = (URL(
            "https://api.groq.com/openai/v1/audio/transcriptions"
        ).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 15000
            readTimeout = 45000
            setRequestProperty("Authorization", "Bearer $key")
            setRequestProperty(
                "Content-Type", "multipart/form-data; boundary=$boundary")
        }
        val body = ByteArrayOutputStream()
        fun field(name: String, value: String) {
            body.write(
                "--$boundary\r\nContent-Disposition: form-data; name=\"$name\"\r\n\r\n$value\r\n"
                    .toByteArray())
        }
        field("model", "whisper-large-v3-turbo")
        field("response_format", "json")
        body.write(
            "--$boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
                .toByteArray())
        body.write(wavBytes)
        body.write("\r\n--$boundary--\r\n".toByteArray())
        conn.outputStream.use { it.write(body.toByteArray()) }
        val code = conn.responseCode
        val raw = (if (code in 200..299) conn.inputStream else conn.errorStream)
            ?.bufferedReader()?.readText() ?: ""
        conn.disconnect()
        if (code !in 200..299) throw IllegalStateException("groq $code")
        val m = Regex("\"text\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(raw)
            ?: return ""
        return m.groupValues[1]
            .replace("\\\"", "\"")
            .replace("\\n", " ")
            .trim()
    }
}
