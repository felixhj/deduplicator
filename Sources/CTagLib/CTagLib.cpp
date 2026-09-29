#include "CTagLib.h"

#include <memory>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include "aifffile.h"
#include "fileref.h"
#include "flacfile.h"
#include "mp4file.h"
#include "mpegfile.h"
#include "tfilestream.h"
#include "tpropertymap.h"
#include "wavfile.h"

struct CTagLibFile {
    // Declared before `ref` so it's destroyed after it: FileRef doesn't own the stream.
    std::unique_ptr<TagLib::FileStream> stream;
    TagLib::FileRef ref;
    bool writable = false;
    std::vector<std::pair<std::string, std::vector<std::string>>> properties;

    void snapshotProperties() {
        properties.clear();
        for (const auto &entry : ref.properties()) {
            std::vector<std::string> values;
            for (const auto &value : entry.second) {
                values.push_back(value.to8Bit(true));
            }
            properties.emplace_back(entry.first.to8Bit(true), std::move(values));
        }
    }
};

namespace {

CTagLibCodec codecOf(TagLib::File *file) {
    if (auto *mpeg = dynamic_cast<TagLib::MPEG::File *>(file)) {
        const auto *audio = mpeg->audioProperties();
        if (!audio) return CTagLibCodecUnknown;
        if (audio->isADTS()) return CTagLibCodecAAC;
        return audio->layer() == 3 ? CTagLibCodecMP3 : CTagLibCodecOther;
    }
    if (auto *mp4 = dynamic_cast<TagLib::MP4::File *>(file)) {
        const auto *audio = mp4->audioProperties();
        if (!audio) return CTagLibCodecUnknown;
        switch (audio->codec()) {
        case TagLib::MP4::Properties::AAC: return CTagLibCodecAAC;
        case TagLib::MP4::Properties::ALAC: return CTagLibCodecALAC;
        default: return CTagLibCodecUnknown;
        }
    }
    if (dynamic_cast<TagLib::FLAC::File *>(file)) return CTagLibCodecFLAC;
    if (dynamic_cast<TagLib::RIFF::AIFF::File *>(file)) return CTagLibCodecAIFF;
    if (dynamic_cast<TagLib::RIFF::WAV::File *>(file)) return CTagLibCodecWAV;
    return CTagLibCodecOther;
}

/// Bit depth for lossless formats. Lossy codecs report 0: MP4 files state a
/// sample size for AAC too, but it doesn't mean anything there.
int32_t bitsPerSampleOf(TagLib::File *file, CTagLibCodec codec) {
    if (auto *flac = dynamic_cast<TagLib::FLAC::File *>(file)) {
        return flac->audioProperties() ? flac->audioProperties()->bitsPerSample() : 0;
    }
    if (auto *mp4 = dynamic_cast<TagLib::MP4::File *>(file)) {
        return codec == CTagLibCodecALAC && mp4->audioProperties() ? mp4->audioProperties()->bitsPerSample() : 0;
    }
    if (auto *aiff = dynamic_cast<TagLib::RIFF::AIFF::File *>(file)) {
        return aiff->audioProperties() ? aiff->audioProperties()->bitsPerSample() : 0;
    }
    if (auto *wav = dynamic_cast<TagLib::RIFF::WAV::File *>(file)) {
        return wav->audioProperties() ? wav->audioProperties()->bitsPerSample() : 0;
    }
    return 0;
}

}  // namespace

extern "C" {

CTagLibFile *ctaglib_open(const char *path, bool writable) noexcept {
    try {
        auto file = std::make_unique<CTagLibFile>();
        file->stream = std::make_unique<TagLib::FileStream>(path, !writable);
        if (!file->stream->isOpen() || (writable && file->stream->readOnly())) return nullptr;
        file->ref = TagLib::FileRef(file->stream.get(), true, TagLib::AudioProperties::Average);
        if (file->ref.isNull() || !file->ref.file()->isValid()) return nullptr;
        file->writable = writable;
        file->snapshotProperties();
        return file.release();
    } catch (...) {
        return nullptr;
    }
}

void ctaglib_close(CTagLibFile *file) noexcept {
    delete file;
}

bool ctaglib_audio_properties(const CTagLibFile *file, CTagLibAudioProperties *out) noexcept {
    TagLib::File *taglibFile = file->ref.file();
    const TagLib::AudioProperties *audio = file->ref.audioProperties();
    // TagLib opens a .mp3 file with no MPEG frames as an MPEG file with empty properties.
    if (!taglibFile || !audio || audio->sampleRate() <= 0) return false;
    const CTagLibCodec codec = codecOf(taglibFile);
    out->codec = codec;
    out->bitrate = audio->bitrate();
    out->sampleRate = audio->sampleRate();
    out->channels = audio->channels();
    out->bitsPerSample = bitsPerSampleOf(taglibFile, codec);
    out->lengthMilliseconds = audio->lengthInMilliseconds();
    return true;
}

size_t ctaglib_property_count(const CTagLibFile *file) noexcept {
    return file->properties.size();
}

const char *ctaglib_property_key(const CTagLibFile *file, size_t index) noexcept {
    return file->properties.at(index).first.c_str();
}

size_t ctaglib_property_value_count(const CTagLibFile *file, size_t index) noexcept {
    return file->properties.at(index).second.size();
}

const char *ctaglib_property_value(const CTagLibFile *file, size_t index, size_t valueIndex) noexcept {
    return file->properties.at(index).second.at(valueIndex).c_str();
}

bool ctaglib_set_property(CTagLibFile *file, const char *key, const char *const *values, size_t count) noexcept {
    if (!file->writable) return false;
    try {
        const TagLib::String name(key, TagLib::String::UTF8);
        TagLib::PropertyMap map = file->ref.properties();
        if (count == 0) {
            map.erase(name);
        } else {
            TagLib::StringList list;
            for (size_t i = 0; i < count; ++i) {
                list.append(TagLib::String(values[i], TagLib::String::UTF8));
            }
            map.replace(name, list);
        }
        const TagLib::PropertyMap rejected = file->ref.setProperties(map);
        file->snapshotProperties();
        return !rejected.contains(name);
    } catch (...) {
        return false;
    }
}

bool ctaglib_save(CTagLibFile *file) noexcept {
    if (!file->writable) return false;
    try {
        return file->ref.save();
    } catch (...) {
        return false;
    }
}

}  // extern "C"
