/*
 * A small C interface to TagLib, so Swift can read and write tags without
 * C++ interop. Each CTagLibFile must be used from one thread at a time;
 * different files can be used concurrently.
 */

#ifndef CTAGLIB_H
#define CTAGLIB_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
#define CTAGLIB_NOEXCEPT noexcept
extern "C" {
#else
#define CTAGLIB_NOEXCEPT
#endif

#pragma clang assume_nonnull begin

/// A file opened with TagLib. It holds a snapshot of the file's tags.
typedef struct CTagLibFile CTagLibFile;

/// The codec, as far as TagLib can tell from the file.
typedef enum __attribute__((enum_extensibility(closed))) CTagLibCodec : int32_t {
    CTagLibCodecUnknown = 0,
    CTagLibCodecMP3,
    CTagLibCodecAAC,
    CTagLibCodecALAC,
    CTagLibCodecFLAC,
    CTagLibCodecAIFF,
    CTagLibCodecWAV,
    /// A format TagLib reads that the app doesn't support, such as Ogg Vorbis.
    CTagLibCodecOther,
} CTagLibCodec;

typedef struct CTagLibAudioProperties {
    CTagLibCodec codec;
    /// Kilobits per second, or 0 when unknown.
    int32_t bitrate;
    /// Hertz, or 0 when unknown.
    int32_t sampleRate;
    /// 0 when unknown.
    int32_t channels;
    /// 0 for lossy codecs, or when unknown.
    int32_t bitsPerSample;
    /// Read from the stream headers, so it's an estimate. For information only:
    /// the app measures duration from the decoded audio.
    int32_t lengthMilliseconds;
} CTagLibAudioProperties;

/// Opens the file at `path` (UTF-8). Returns NULL when the file can't be opened
/// or TagLib doesn't recognise the format. Pass `writable` to allow saving.
CTagLibFile *_Nullable ctaglib_open(const char *path, bool writable) CTAGLIB_NOEXCEPT;

/// Closes the file. Strings returned for it become invalid.
void ctaglib_close(CTagLibFile *_Nullable file) CTAGLIB_NOEXCEPT;

/// Fills `out` and returns true, or returns false when TagLib found no audio stream.
bool ctaglib_audio_properties(const CTagLibFile *file, CTagLibAudioProperties *out) CTAGLIB_NOEXCEPT;

/// The tags, as TagLib's unified property map ("TITLE", "ARTIST", "INITIALKEY", ...),
/// sorted by key. Strings are UTF-8 and stay valid until the next change or close.
size_t ctaglib_property_count(const CTagLibFile *file) CTAGLIB_NOEXCEPT;
const char *ctaglib_property_key(const CTagLibFile *file, size_t index) CTAGLIB_NOEXCEPT;
size_t ctaglib_property_value_count(const CTagLibFile *file, size_t index) CTAGLIB_NOEXCEPT;
const char *ctaglib_property_value(const CTagLibFile *file, size_t index, size_t valueIndex) CTAGLIB_NOEXCEPT;

/// Replaces the values for `key`, or removes the key when `count` is 0. Nothing is
/// written until ctaglib_save. Returns false if the file isn't writable or the
/// format can't store the key.
bool ctaglib_set_property(CTagLibFile *file, const char *key, const char *_Nonnull const *_Nullable values, size_t count) CTAGLIB_NOEXCEPT;

/// Writes changed tags to disk. Returns false if the file isn't writable or saving failed.
bool ctaglib_save(CTagLibFile *file) CTAGLIB_NOEXCEPT;

#pragma clang assume_nonnull end

#ifdef __cplusplus
}
#endif

#endif
