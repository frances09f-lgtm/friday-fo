// JNI bridge to the needle speech engine for Friday's optional Shruti
// offline voice input. needle keeps one process-global, non-thread-safe
// model; the Kotlin ShrutiBridge serializes every call behind a lock on a
// single worker thread, so this file adds no threading of its own.

#include <jni.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "needle.h"

namespace {

constexpr int kOutCapacity = 65536;

uint32_t readU32(const unsigned char* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

uint16_t readU16(const unsigned char* p) {
  return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

// Reads a 16 kHz mono 16-bit PCM WAV file (what the record plugin writes)
// into float samples in [-1, 1]. Walks RIFF chunks so extra metadata chunks
// do not break the parse.
bool readWav(const char* path, std::vector<float>* pcm, std::string* err) {
  FILE* f = fopen(path, "rb");
  if (!f) {
    *err = "could not open the recording";
    return false;
  }
  unsigned char riff[12];
  if (fread(riff, 1, 12, f) != 12 || memcmp(riff, "RIFF", 4) != 0 ||
      memcmp(riff + 8, "WAVE", 4) != 0) {
    fclose(f);
    *err = "the recording is not a WAV file";
    return false;
  }
  bool fmtSeen = false;
  bool ok = false;
  for (;;) {
    unsigned char header[8];
    if (fread(header, 1, 8, f) != 8) break;
    const uint32_t size = readU32(header + 4);
    if (memcmp(header, "fmt ", 4) == 0) {
      unsigned char fmt[16];
      if (size < 16 || fread(fmt, 1, 16, f) != 16) break;
      const uint16_t format = readU16(fmt);
      const uint16_t channels = readU16(fmt + 2);
      const uint32_t rate = readU32(fmt + 4);
      const uint16_t bits = readU16(fmt + 14);
      if (format != 1 || channels != 1 || rate != 16000 || bits != 16) {
        fclose(f);
        *err = "the recording is not 16 kHz mono PCM";
        return false;
      }
      fmtSeen = true;
      if (fseek(f, (long)(size - 16) + (size & 1), SEEK_CUR) != 0) break;
    } else if (memcmp(header, "data", 4) == 0) {
      if (!fmtSeen) break;
      std::vector<unsigned char> raw(size);
      if (size > 0 && fread(raw.data(), 1, size, f) != size) break;
      pcm->resize(size / 2);
      for (size_t i = 0; i + 1 < size; i += 2) {
        const int16_t s =
            (int16_t)((uint16_t)raw[i] | ((uint16_t)raw[i + 1] << 8));
        (*pcm)[i / 2] = (float)s / 32768.0f;
      }
      ok = true;
      break;
    } else {
      if (fseek(f, (long)size + (size & 1), SEEK_CUR) != 0) break;
    }
  }
  fclose(f);
  if (!ok) *err = "the recording has no audio data";
  return ok;
}

std::string jsonEscape(const char* text) {
  std::string out;
  for (const char* p = text; p && *p; ++p) {
    if (*p == '"' || *p == '\\') out += '\\';
    out += *p;
  }
  return out;
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_friday_assistant_ShrutiBridge_nativeLoadModel(JNIEnv* env, jobject,
                                                       jstring jpath) {
  const char* path = env->GetStringUTFChars(jpath, nullptr);
  FILE* f = fopen(path, "rb");
  if (!f) {
    env->ReleaseStringUTFChars(jpath, path);
    return env->NewStringUTF("could not open the model file");
  }
  fseek(f, 0, SEEK_END);
  const long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  std::vector<unsigned char> bytes((size_t)size);
  const bool readOk =
      size > 0 && fread(bytes.data(), 1, (size_t)size, f) == (size_t)size;
  fclose(f);
  env->ReleaseStringUTFChars(jpath, path);
  if (!readOk) return env->NewStringUTF("could not read the model file");
  const int rc = needle_load(bytes.data(), (unsigned long long)bytes.size());
  if (rc < 0) {
    const char* why = needle_last_error();
    return env->NewStringUTF(why && *why ? why : "needle_load failed");
  }
  if ((needle_models() & NEEDLE_SPEECH) == 0) {
    return env->NewStringUTF("the file is not a speech model");
  }
  return nullptr;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_friday_assistant_ShrutiBridge_nativeTranscribeWav(JNIEnv* env,
                                                           jobject,
                                                           jstring jpath) {
  const char* path = env->GetStringUTFChars(jpath, nullptr);
  std::vector<float> pcm;
  std::string err;
  const bool ok = readWav(path, &pcm, &err);
  env->ReleaseStringUTFChars(jpath, path);
  if (!ok) {
    const std::string json = "{\"error\":\"" + jsonEscape(err.c_str()) + "\"}";
    return env->NewStringUTF(json.c_str());
  }
  if (pcm.empty()) {
    return env->NewStringUTF("{\"text\":\"\",\"language\":\"\"}");
  }
  std::vector<char> out(kOutCapacity, 0);
  // Language detection is left to the engine (NULL): Shruti handles English,
  // Hindi and Marathi without a forced locale.
  const int rc =
      needle_transcribe(pcm.data(), (int)pcm.size(), nullptr, nullptr, 0,
                        out.data(), kOutCapacity);
  if (rc < 0) {
    const char* why = needle_last_error();
    const std::string json =
        std::string("{\"error\":\"") +
        jsonEscape(why && *why ? why : "transcription failed") + "\"}";
    return env->NewStringUTF(json.c_str());
  }
  out[kOutCapacity - 1] = 0;
  return env->NewStringUTF(out.data());
}
