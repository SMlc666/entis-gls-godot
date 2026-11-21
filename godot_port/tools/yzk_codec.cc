// SPDX-License-Identifier: GPL-3.0-or-later
// In-process native codec shared library for Godot Yosuga no Sora port.
#include <cstddef>
#include <cstdint>
#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "algo/locale.h"
#include "algo/str.h"
#include "dec/entis/common/erisan_decoder.h"
#include "dec/entis/eri_image_decoder.h"
#include "dec/entis/mio_audio_decoder.h"
#include "dec/entis/common/huffman_tree.h"
#include "io/file.h"
#include "io/memory_byte_stream.h"
#include "logger.h"
#include "res/audio.h"
#include "res/image.h"
#include "virtual_file_system.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <cstdlib>
#include <cstring>

#if defined(_WIN32)
#define YZK_EXPORT __declspec(dllexport)
#else
#define YZK_EXPORT __attribute__((visibility("default")))
#endif

extern "C" YZK_EXPORT int yzk_decode_erisan(const uint8_t *, size_t, uint8_t *, size_t);

namespace {

constexpr size_t kMaxCodecInputBytes = 128U * 1024U * 1024U;
constexpr size_t kMaxCodecOutputBytes = 128U * 1024U * 1024U;

struct SectionRange {
    std::string name;
    size_t offset = 0;
    size_t size = 0;
};

struct MeiFrameRecord {
    std::string record_type;
    size_t offset = 0;
    size_t payload_size = 0;
    uint8_t eri_version = 0;
    uint8_t operation_flags = 0;
    uint8_t encode_type = 0;
    uint8_t bit_count = 0;
    char picture_type = 'P';
};

class MeiBitReader {
public:
    MeiBitReader(const uint8_t *bytes, size_t size) : bytes_(bytes), size_(size) {}
    bool read(unsigned count, uint32_t &value) {
        if (count > 32 || count > remaining()) return false;
        value = 0;
        for (unsigned i = 0; i < count; ++i) {
            value = (value << 1) | ((bytes_[bit_ >> 3] >> (7 - (bit_ & 7))) & 1);
            ++bit_;
        }
        return true;
    }
    size_t remaining() const { return size_ * 8 - bit_; }
private:
    const uint8_t *bytes_;
    size_t size_;
    size_t bit_ = 0;
};

bool mei_gamma(MeiBitReader &bits, uint32_t &value) {
    uint32_t bit = 0;
    if (!bits.read(1, bit)) return false;
    if (!bit) { value = 1; return true; }
    uint32_t base = 2, code = 0;
    for (unsigned n = 0; n < 31; ++n) {
        if (!bits.read(1, bit)) return false;
        code = (code << 1) | bit;
        if (!bits.read(1, bit)) return false;
        if (!bit) { value = code + base; return true; }
        if (base > (UINT32_MAX >> 1)) return false;
        base <<= 1;
    }
    return false;
}

bool mei_huffman(MeiBitReader &bits, au::dec::entis::common::HuffmanTree &tree,
    bool gamma_escape, int &value) {
    using namespace au::dec::entis::common;
    if (tree.escape != HuffmanNodes::Null) {
        int entry = HuffmanNodes::Root;
        uint32_t child = tree.nodes[entry].code;
        while (!(child & HuffmanFlags::Code)) {
            uint32_t branch = 0;
            if (!bits.read(1, branch)) return false;
            entry = static_cast<int>(child) + static_cast<int>(branch);
            child = tree.nodes[entry].code;
        }
        if (tree.nodes[HuffmanNodes::Root].weight < 0x3fff)
            tree.increase_occurrences(entry);
        const uint32_t code = child & ~HuffmanFlags::Code;
        if (code != HuffmanFlags::Escape) { value = static_cast<int>(code); return true; }
    }
    uint32_t raw = 0;
    if (gamma_escape) {
        if (!mei_gamma(bits, raw)) return false;
    } else if (!bits.read(8, raw)) return false;
    value = static_cast<int>(raw);
    tree.add_new_entry(value);
    return true;
}

bool decode_mei_first_frame_coefficients(const uint8_t *frame, size_t frame_size,
    size_t width, size_t height, std::vector<int8_t> &coefficients, std::string &error) {
    using namespace au::dec::entis::common;
    if (!frame || frame_size < 4 || frame[0] != 0x28 || frame[1] != 0
        || frame[2] != 1 || frame[3] != 8 || width == 0 || height == 0) {
        error = "First MEI image frame has unsupported ERI parameters.";
        return false;
    }
    MeiBitReader bits(frame + 4, frame_size - 4);
    uint32_t reserved = 0;
    if (!bits.read(1, reserved) || reserved != 0) {
        error = "First MEI image frame has invalid reserved bits.";
        return false;
    }
    const size_t block_width = (width + 15) / 16;
    const size_t block_height = (height + 15) / 16;
    if (block_width > SIZE_MAX / block_height / 384) {
        error = "First MEI frame coefficient count exceeds bounds.";
        return false;
    }
    const size_t total = block_width * block_height * 384;
    HuffmanTree initial_tree;
    std::array<uint8_t, 128> quantization{};
    for (uint8_t &item : quantization) {
        int symbol = 0;
        if (!mei_huffman(bits, initial_tree, false, symbol) || symbol < 0 || symbol > 255) {
            error = "First MEI frame quantization table is truncated.";
            return false;
        }
        item = static_cast<uint8_t>(symbol);
    }
    const size_t op_count = block_width * block_height * 2;
    std::vector<int8_t> operations(op_count);
    uint32_t zero_flag = 0;
    if (!bits.read(1, zero_flag)) {
        error = "First MEI frame operation table is truncated.";
        return false;
    }
    bool zero_run = zero_flag == 0;
    size_t cursor = 0;
    while (cursor < operations.size()) {
        uint32_t run = 0;
        if (!mei_gamma(bits, run) || run == 0) {
            error = "First MEI frame operation run is invalid.";
            return false;
        }
        const size_t count = std::min<size_t>(run, operations.size() - cursor);
        if (!zero_run) {
            for (size_t i = 0; i < count; ++i) {
                uint32_t sign = 0, magnitude = 0;
                if (!bits.read(1, sign) || !mei_gamma(bits, magnitude) || magnitude == 0 || magnitude > 128) {
                    error = "First MEI frame operation value is invalid.";
                    return false;
                }
                operations[cursor++] = static_cast<int8_t>(sign ? -static_cast<int>(magnitude) : static_cast<int>(magnitude));
            }
        } else {
            std::fill_n(operations.begin() + static_cast<std::ptrdiff_t>(cursor), count, 0);
            cursor += count;
        }
        zero_run = !zero_run;
    }
    // ERINA's image stream has independent adaptive trees from the initial table.
    HuffmanTree data_tree, length_tree;
    coefficients.clear();
    coefficients.reserve(total);
    size_t pending_zeros = 0;
    while (coefficients.size() < total) {
        if (pending_zeros) {
            const size_t count = std::min(pending_zeros, total - coefficients.size());
            coefficients.insert(coefficients.end(), count, 0);
            pending_zeros -= count;
            continue;
        }
        int symbol = 0;
        if (!mei_huffman(bits, data_tree, false, symbol) || symbol < 0 || symbol > 255) {
            error = "First MEI frame ERINA coefficient stream is truncated.";
            return false;
        }
        if (symbol == 0) {
            int run = 0;
            if (!mei_huffman(bits, length_tree, true, run) || run <= 0 || static_cast<size_t>(run) > total) {
                error = "First MEI frame ERINA zero run is invalid.";
                return false;
            }
            pending_zeros = static_cast<size_t>(run);
        } else {
            coefficients.push_back(static_cast<int8_t>(static_cast<uint8_t>(symbol)));
        }
    }
    return true;
}

uint32_t read_u32_le(const uint8_t *data) {
    return static_cast<uint32_t>(data[0])
        | (static_cast<uint32_t>(data[1]) << 8)
        | (static_cast<uint32_t>(data[2]) << 16)
        | (static_cast<uint32_t>(data[3]) << 24);
}

uint64_t read_u64_le(const uint8_t *data) {
    return static_cast<uint64_t>(read_u32_le(data))
        | (static_cast<uint64_t>(read_u32_le(data + 4)) << 32);
}

bool read_sections(
    const uint8_t *data,
    size_t begin,
    size_t end,
    std::vector<SectionRange> &sections) {
    sections.clear();
    if (!data || begin > end) return false;
    size_t cursor = begin;
    while (cursor < end) {
        if (end - cursor < 16) return false;
        std::string name(reinterpret_cast<const char *>(data + cursor), 8);
        const size_t trim_at = name.find_first_of(" \0");
        if (trim_at != std::string::npos) name.resize(trim_at);
        const uint64_t section_size_u64 = read_u64_le(data + cursor + 8);
        cursor += 16;
        if (section_size_u64 > static_cast<uint64_t>(end - cursor)) return false;
        const size_t section_size = static_cast<size_t>(section_size_u64);
        sections.push_back({name, cursor, section_size});
        cursor += section_size;
    }
    return cursor == end;
}

bool find_section(
    const std::vector<SectionRange> &sections,
    const char *name,
    SectionRange &result) {
    for (const SectionRange &section : sections) {
        if (section.name == name) {
            result = section;
            return true;
        }
    }
    return false;
}

bool validate_eri_shape(const uint8_t *data, size_t size, std::string &error) {
    if (size < 0x40) {
        error = "ERI input is shorter than its header.";
        return false;
    }
    std::vector<SectionRange> top_sections;
    SectionRange header;
    SectionRange stream;
    if (!read_sections(data, 0x40, size, top_sections)
        || !find_section(top_sections, "Header", header)
        || !find_section(top_sections, "Stream", stream)) {
        error = "ERI section table is malformed or incomplete.";
        return false;
    }
    std::vector<SectionRange> header_sections;
    SectionRange image_info;
    if (!read_sections(data, header.offset, header.offset + header.size, header_sections)
        || !find_section(header_sections, "ImageInf", image_info)
        || image_info.size < 24) {
        error = "ERI ImageInf section is missing or truncated.";
        return false;
    }
    const int32_t width_signed = static_cast<int32_t>(read_u32_le(data + image_info.offset + 16));
    const int32_t height_signed = static_cast<int32_t>(read_u32_le(data + image_info.offset + 20));
    if (width_signed == std::numeric_limits<int32_t>::min()
        || height_signed == std::numeric_limits<int32_t>::min()) {
        error = "ERI dimensions are invalid.";
        return false;
    }
    const size_t width = static_cast<size_t>(width_signed < 0 ? -width_signed : width_signed);
    const size_t height = static_cast<size_t>(height_signed < 0 ? -height_signed : height_signed);
    std::vector<SectionRange> stream_sections;
    if (!read_sections(data, stream.offset, stream.offset + stream.size, stream_sections)) {
        error = "ERI stream section table is malformed.";
        return false;
    }
    size_t frame_count = 0;
    for (const SectionRange &section : stream_sections)
        if (section.name == "ImageFrm") ++frame_count;
    if (width == 0 || height == 0 || frame_count == 0
        || width > 16384 || height > 16384) {
        error = "ERI dimensions or frame count are outside supported bounds.";
        return false;
    }
    const uint64_t pixels = static_cast<uint64_t>(width) * height;
    if (pixels > kMaxCodecOutputBytes / 4
        || frame_count > (kMaxCodecOutputBytes / 4) / pixels) {
        error = "Decoded ERI image would exceed the output limit.";
        return false;
    }
    return true;
}

bool validate_mio_size(const uint8_t *data, size_t size, std::string &error) {
    if (size < 0x40) {
        error = "MIO input is shorter than its header.";
        return false;
    }
    std::vector<SectionRange> top_sections;
    SectionRange header;
    SectionRange stream;
    if (!read_sections(data, 0x40, size, top_sections)
        || !find_section(top_sections, "Header", header)
        || !find_section(top_sections, "Stream", stream)) {
        error = "MIO section table is malformed or incomplete.";
        return false;
    }
    std::vector<SectionRange> header_sections;
    SectionRange sound_info;
    if (!read_sections(data, header.offset, header.offset + header.size, header_sections)
        || !find_section(header_sections, "SoundInf", sound_info)
        || sound_info.size < 40) {
        error = "MIO SoundInf section is missing or truncated.";
        return false;
    }
    const uint32_t channels = read_u32_le(data + sound_info.offset + 12);
    const uint32_t sample_rate = read_u32_le(data + sound_info.offset + 16);
    const uint32_t header_samples = read_u32_le(data + sound_info.offset + 28);
    const uint32_t bits_per_sample = read_u32_le(data + sound_info.offset + 36);
    if (channels == 0 || channels > 8 || sample_rate < 8000 || sample_rate > 384000
        || (bits_per_sample != 8 && bits_per_sample != 16 && bits_per_sample != 24 && bits_per_sample != 32)) {
        error = "MIO audio format fields are outside supported bounds.";
        return false;
    }
    std::vector<SectionRange> stream_sections;
    if (!read_sections(data, stream.offset, stream.offset + stream.size, stream_sections)) {
        error = "MIO stream section table is malformed.";
        return false;
    }
    uint64_t total_samples = 0;
    for (const SectionRange &section : stream_sections) {
        if (section.name != "SoundStm") continue;
        if (section.size < 8) {
            error = "MIO SoundStm chunk is truncated.";
            return false;
        }
        total_samples += read_u32_le(data + section.offset + 4);
        if (total_samples > (kMaxCodecOutputBytes / 4) / channels) {
            error = "Decoded MIO audio would exceed the output limit.";
            return false;
        }
    }
    if (total_samples == 0 || header_samples == 0) {
        error = "MIO contains no samples.";
        return false;
    }
    return true;
}

bool validate_mei_size(
    const uint8_t *data,
    size_t size,
    std::string &error,
    size_t &width,
    size_t &height,
    std::vector<MeiFrameRecord> &frame_records,
    uint32_t &declared_frames,
    uint32_t &duration_ms,
    uint32_t &declared_samples,
    uint32_t &channels,
    uint32_t &sample_rate,
    uint32_t &bits_per_sample) {
    static constexpr uint8_t prefix[] = {'E','n','t','i','s',0x1a,0,0};
    static constexpr char title[] = "Moving Entis Image";
    if (!data || size < 64 || std::memcmp(data, prefix, sizeof(prefix)) != 0
        || std::memcmp(data + 16, title, sizeof(title) - 1) != 0) {
        error = "Input is not an Entis MEI movie.";
        return false;
    }
    std::vector<SectionRange> top_sections;
    SectionRange header, stream;
    if (!read_sections(data, 64, size, top_sections)
        || !find_section(top_sections, "Header", header)
        || !find_section(top_sections, "Stream", stream)) {
        error = "MEI section table is malformed or incomplete.";
        return false;
    }
    std::vector<SectionRange> header_sections;
    SectionRange file_info, image_info, sound_info;
    if (!read_sections(data, header.offset, header.offset + header.size, header_sections)
        || !find_section(header_sections, "FileHdr", file_info)
        || !find_section(header_sections, "ImageInf", image_info)
        || !find_section(header_sections, "SoundInf", sound_info)
        || file_info.size < 20 || image_info.size < 68 || sound_info.size < 40) {
        error = "MEI FileHdr, ImageInf, or SoundInf metadata is missing or truncated.";
        return false;
    }
    const int32_t width_signed = static_cast<int32_t>(read_u32_le(data + image_info.offset + 16));
    const int32_t height_signed = static_cast<int32_t>(read_u32_le(data + image_info.offset + 20));
    if (width_signed == 0 || height_signed == 0
        || width_signed == std::numeric_limits<int32_t>::min()
        || height_signed == std::numeric_limits<int32_t>::min()) {
        error = "MEI image dimensions are invalid.";
        return false;
    }
    width = static_cast<size_t>(width_signed < 0 ? -width_signed : width_signed);
    height = static_cast<size_t>(height_signed < 0 ? -height_signed : height_signed);
    if (width > 16384 || height > 16384 || width > kMaxCodecOutputBytes / 4 / height) {
        error = "MEI image dimensions exceed supported bounds.";
        return false;
    }
    duration_ms = read_u32_le(data + file_info.offset + 16);
    declared_frames = read_u32_le(data + file_info.offset + 12);
    channels = read_u32_le(data + sound_info.offset + 12);
    sample_rate = read_u32_le(data + sound_info.offset + 16);
    declared_samples = read_u32_le(data + sound_info.offset + 28);
    bits_per_sample = read_u32_le(data + sound_info.offset + 36);
    std::vector<SectionRange> stream_sections;
    if (!read_sections(data, stream.offset, stream.offset + stream.size, stream_sections)) {
        error = "MEI frame and audio stream is malformed.";
        return false;
    }
    frame_records.clear();
    for (const SectionRange &section : stream_sections) {
        if (section.name != "ImageFrm" && section.name != "DiffeFrm") continue;
        if (section.size < 4) {
            error = "MEI image frame header is truncated.";
            return false;
        }
        const uint8_t *frame = data + section.offset;
        if (frame[0] != 0x28 || frame[3] != 8) {
            error = "MEI frame uses an unsupported ERI frame header.";
            return false;
        }
        MeiFrameRecord record;
        record.record_type = section.name;
        record.offset = section.offset;
        record.payload_size = section.size;
        record.eri_version = frame[0];
        record.operation_flags = frame[1];
        record.encode_type = frame[2];
        record.bit_count = frame[3];
        record.picture_type = section.name == "ImageFrm"
            ? 'I' : ((frame[1] & 0x02) != 0 ? 'B' : 'P');
        frame_records.push_back(std::move(record));
    }
    if (frame_records.empty() || frame_records.size() > 100000 || declared_frames == 0
        || declared_frames > 100000 || declared_samples == 0 || channels == 0
        || (bits_per_sample != 8 && bits_per_sample != 16 && bits_per_sample != 24 && bits_per_sample != 32)
        || declared_samples > kMaxCodecOutputBytes / channels / (bits_per_sample / 8)) {
        error = "MEI has no frames or an invalid declared frame count.";
        return false;
    }
    if (!validate_mio_size(data, size, error)) return false;
    return true;
}

godot::Dictionary codec_failure(const std::string &message) {
    godot::Dictionary result;
    result["ok"] = false;
    result["error"] = godot::String::utf8(message.c_str());
    return result;
}

au::bstr copy_input(const godot::PackedByteArray &input) {
    au::bstr encoded(static_cast<size_t>(input.size()));
    if (input.size() > 0)
        std::memcpy(encoded.get<char>(), input.ptr(), static_cast<size_t>(input.size()));
    return encoded;
}

} // namespace

// This project supplies individual NOA entries to the in-memory decoder. The
// upstream ERI implementation has an optional reference-file lookup; game
// assets used here are complete images, so the extension does not mount a
// second filesystem and returns no external base image for that optional path.
namespace au {
namespace algo {
std::vector<std::string> split(const std::string &input, const char separator, const bool keep_separators) {
    std::vector<std::string> tokens;
    size_t start = 0;
    size_t end = 0;
    while ((end = input.find(separator, start)) != std::string::npos) {
        const size_t token_end = end + (keep_separators ? 1 : 0);
        if (token_end > start) tokens.push_back(input.substr(start, token_end - start));
        start = end + 1;
    }
    if (start < input.size()) tokens.push_back(input.substr(start));
    return tokens;
}

std::string replace_all(const std::string &input, const std::string &from, const std::string &to) {
    if (from.empty()) return input;
    std::string output;
    size_t start = 0;
    size_t found = 0;
    while ((found = input.find(from, start)) != std::string::npos) {
        output.append(input, start, found - start);
        output += to;
        start = found + from.size();
    }
    output.append(input, start, std::string::npos);
    return output;
}

bstr utf16_to_utf8(const bstr &input) {
    std::string output;
    output.reserve(input.size());
    for (size_t i = 0; i + 1 < input.size(); i += 2) {
        uint32_t codepoint = static_cast<uint32_t>(input[i])
            | (static_cast<uint32_t>(input[i + 1]) << 8);
        if (codepoint >= 0xD800 && codepoint <= 0xDBFF && i + 3 < input.size()) {
            const uint32_t low = static_cast<uint32_t>(input[i + 2])
                | (static_cast<uint32_t>(input[i + 3]) << 8);
            if (low >= 0xDC00 && low <= 0xDFFF) {
                codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00);
                i += 2;
            } else {
                codepoint = 0xFFFD;
            }
        } else if (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
            codepoint = 0xFFFD;
        }
        if (codepoint <= 0x7F) {
            output.push_back(static_cast<char>(codepoint));
        } else if (codepoint <= 0x7FF) {
            output.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else if (codepoint <= 0xFFFF) {
            output.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else {
            output.push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        }
    }
    return bstr(output);
}
} // namespace algo

std::unique_ptr<io::File> VirtualFileSystem::get_by_name(const std::string &) {
    return nullptr;
}

namespace io {
path::path() : p() {}
path::path(const char *value) : p(value ? value : "") {}
path::path(const std::string &value) : p(value) {}

File::File(const au::io::path &file_path, std::unique_ptr<BaseByteStream> input_stream)
    : stream_holder(std::move(input_stream)), stream(*stream_holder), path(file_path) {}

File::File(const au::io::path &file_path, const bstr &data)
    : File(file_path, std::make_unique<MemoryByteStream>(data)) {}

File::~File() {}
} // namespace io
} // namespace au

namespace godot {

class YzkCodec final : public RefCounted {
    GDCLASS(YzkCodec, RefCounted)

protected:
    static void _bind_methods();

public:
    Dictionary decode_erisan(const PackedByteArray &input, int64_t expected_size) const;
    Dictionary decode_eri(const PackedByteArray &input) const;
    Dictionary decode_mio(const PackedByteArray &input) const;
    Dictionary decode_mei(const PackedByteArray &input) const;
    Array build_shading_levels(const PackedByteArray &rgba, int64_t width, int64_t height) const;
};

void YzkCodec::_bind_methods() {
    ClassDB::bind_method(D_METHOD("decode_erisan", "input", "expected_size"), &YzkCodec::decode_erisan);
    ClassDB::bind_method(D_METHOD("decode_eri", "input"), &YzkCodec::decode_eri);
    ClassDB::bind_method(D_METHOD("decode_mio", "input"), &YzkCodec::decode_mio);
    ClassDB::bind_method(D_METHOD("decode_mei", "input"), &YzkCodec::decode_mei);
    ClassDB::bind_method(D_METHOD("build_shading_levels", "rgba", "width", "height"), &YzkCodec::build_shading_levels);
}

Array YzkCodec::build_shading_levels(const PackedByteArray &rgba, int64_t width, int64_t height) const {
    Array result;
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192
        || width * height > 33554432 || rgba.size() != width * height * 4) return result;

    const size_t w = static_cast<size_t>(width);
    const size_t h = static_cast<size_t>(height);
    std::vector<uint8_t> current(static_cast<size_t>(rgba.size()));
    std::memcpy(current.data(), rgba.ptr(), current.size());
    PackedByteArray original;
    original.resize(rgba.size());
    std::memcpy(original.ptrw(), rgba.ptr(), current.size());
    result.push_back(original);

    // The Entis 4:2:1 primitive averages the centre with the floor-average
    // of its two neighbours. Keep edge pixels intact, as the native routine does.
    auto average = [](uint8_t a, uint8_t b) -> uint8_t {
        return static_cast<uint8_t>((static_cast<unsigned>(a) + static_cast<unsigned>(b)) >> 1);
    };
    for (int level = 0; level < 4; ++level) {
        for (int pass = 0; pass < 16; ++pass) {
            std::vector<uint8_t> horizontal(current.size());
            std::memcpy(horizontal.data(), current.data(), current.size());
            if (w > 2) {
                for (size_t y = 0; y < h; ++y) {
                    for (size_t x = 1; x + 1 < w; ++x) {
                        const size_t p = (y * w + x) * 4;
                        for (size_t c = 0; c < 4; ++c)
                            horizontal[p + c] = average(current[p + c], average(current[p - 4 + c], current[p + 4 + c]));
                    }
                }
            }
            std::vector<uint8_t> vertical(horizontal.size());
            std::memcpy(vertical.data(), horizontal.data(), horizontal.size());
            if (h > 2) {
                for (size_t y = 1; y + 1 < h; ++y) {
                    for (size_t x = 0; x < w; ++x) {
                        const size_t p = (y * w + x) * 4;
                        for (size_t c = 0; c < 4; ++c)
                            vertical[p + c] = average(horizontal[p + c], average(horizontal[p - w * 4 + c], horizontal[p + w * 4 + c]));
                    }
                }
            }
            current.swap(vertical);
        }
        PackedByteArray image;
        image.resize(static_cast<int64_t>(current.size()));
        std::memcpy(image.ptrw(), current.data(), current.size());
        result.push_back(image);
    }
    return result;
}

Dictionary YzkCodec::decode_erisan(const PackedByteArray &input, int64_t expected_size) const {
    Dictionary result;
    if (input.size() < 4 || input.size() > 128LL * 1024 * 1024 || expected_size <= 0 || expected_size > 128LL * 1024 * 1024) {
        result["ok"] = false;
        result["error"] = "ERISAN input or output size is outside the supported bounds.";
        result["code"] = -1;
        return result;
    }

    PackedByteArray output;
    output.resize(static_cast<int64_t>(expected_size));
    const int code = yzk_decode_erisan(input.ptr(), static_cast<size_t>(input.size()), output.ptrw(), static_cast<size_t>(expected_size));
    if (code != 0) {
        result["ok"] = false;
		result["error"] = "ERISAN decoding failed; inspect the returned error code.";
        result["code"] = code;
        return result;
    }
    result["ok"] = true;
    result["data"] = output;
    return result;
}

Dictionary YzkCodec::decode_eri(const PackedByteArray &input) const {
    if (input.size() < 64 || static_cast<size_t>(input.size()) > kMaxCodecInputBytes)
        return codec_failure("ERI input size is outside the supported bounds.");
    std::string validation_error;
    if (!validate_eri_shape(input.ptr(), static_cast<size_t>(input.size()), validation_error))
        return codec_failure(validation_error);
    try {
        au::io::File file("input.eri", copy_input(input));
        au::dec::entis::EriImageDecoder decoder;
        au::Logger logger;
        logger.mute();
        const au::res::Image image = decoder.decode(logger, file);
        const size_t width = image.width();
        const size_t height = image.height();
        if (width == 0 || height == 0 || width > std::numeric_limits<size_t>::max() / height
            || width * height > kMaxCodecOutputBytes / 4)
            return codec_failure("Decoded ERI dimensions are outside the supported bounds.");
        PackedByteArray pixels;
        pixels.resize(static_cast<int64_t>(width * height * 4));
        uint8_t *destination = pixels.ptrw();
        size_t offset = 0;
        for (const au::res::Pixel &pixel : image) {
            destination[offset++] = pixel.r;
            destination[offset++] = pixel.g;
            destination[offset++] = pixel.b;
            destination[offset++] = pixel.a;
        }
        Dictionary result;
        result["ok"] = true;
        result["width"] = static_cast<int64_t>(width);
        result["height"] = static_cast<int64_t>(height);
        result["data"] = pixels;
        return result;
    } catch (const std::exception &error) {
        return codec_failure(error.what());
    } catch (...) {
        return codec_failure("Unknown native ERI decoder error.");
    }
}

Dictionary YzkCodec::decode_mio(const PackedByteArray &input) const {
    if (input.size() < 64 || static_cast<size_t>(input.size()) > kMaxCodecInputBytes)
        return codec_failure("MIO input size is outside the supported bounds.");
    std::string validation_error;
    if (!validate_mio_size(input.ptr(), static_cast<size_t>(input.size()), validation_error))
        return codec_failure(validation_error);
    try {
        au::io::File file("input.mio", copy_input(input));
        au::dec::entis::MioAudioDecoder decoder;
        au::Logger logger;
        logger.mute();
        const au::res::Audio audio = decoder.decode(logger, file);
        if (audio.samples.empty() || audio.samples.size() > kMaxCodecOutputBytes
            || audio.channel_count == 0 || audio.channel_count > 8
            || audio.sample_rate < 8000 || audio.sample_rate > 384000
            || (audio.bits_per_sample != 8 && audio.bits_per_sample != 16
                && audio.bits_per_sample != 24 && audio.bits_per_sample != 32))
            return codec_failure("Decoded MIO audio is outside the supported bounds.");
        PackedByteArray samples;
        samples.resize(static_cast<int64_t>(audio.samples.size()));
        std::memcpy(samples.ptrw(), audio.samples.get<const uint8_t>(), audio.samples.size());
        Dictionary result;
        result["ok"] = true;
        result["channels"] = static_cast<int64_t>(audio.channel_count);
        result["sample_rate"] = static_cast<int64_t>(audio.sample_rate);
        result["bits_per_sample"] = static_cast<int64_t>(audio.bits_per_sample);
        result["data"] = samples;
        return result;
    } catch (const std::exception &error) {
        return codec_failure(error.what());
    } catch (...) {
        return codec_failure("Unknown native MIO decoder error.");
    }
}

Dictionary YzkCodec::decode_mei(const PackedByteArray &input) const {
    if (input.size() < 64 || static_cast<size_t>(input.size()) > kMaxCodecInputBytes)
        return codec_failure("MEI input size is outside the supported bounds.");
    std::string validation_error;
    size_t width = 0, height = 0;
    std::vector<MeiFrameRecord> frame_records;
    uint32_t declared_frames = 0, duration_ms = 0, declared_samples = 0;
    uint32_t channels = 0, sample_rate = 0, bits_per_sample = 0;
    if (!validate_mei_size(input.ptr(), static_cast<size_t>(input.size()), validation_error,
        width, height, frame_records, declared_frames, duration_ms, declared_samples,
        channels, sample_rate, bits_per_sample))
        return codec_failure(validation_error);
    try {
        // MEI and MIO share SoundInf/SoundStm coding. Adapt only the private
        // container signature in this owned memory copy, then use the existing
        // in-process MIO decoder without touching the original movie bytes.
        au::bstr encoded = copy_input(input);
        static constexpr char mio_title[] = "Music Interleaved and Orthogonal";
        static_assert(sizeof(mio_title) - 1 == 32);
        std::memcpy(encoded.get<char>() + 16, mio_title, sizeof(mio_title) - 1);
        au::io::File file("input.mio", encoded);
        au::dec::entis::MioAudioDecoder decoder;
        au::Logger logger;
        logger.mute();
        const au::res::Audio audio = decoder.decode(logger, file);
        const uint64_t expected_audio_bytes = static_cast<uint64_t>(declared_samples)
            * channels * (bits_per_sample / 8);
        if (audio.samples.empty() || audio.samples.size() < expected_audio_bytes
            || expected_audio_bytes > kMaxCodecOutputBytes
            || audio.channel_count != channels || audio.sample_rate != sample_rate
            || audio.bits_per_sample != bits_per_sample)
            return codec_failure("Decoded MEI audio is outside the supported bounds.");
        std::vector<int8_t> first_frame_coefficients;
        std::string video_error;
        const MeiFrameRecord &first_frame = frame_records.front();
        const bool first_frame_entropy_decoded = decode_mei_first_frame_coefficients(
            input.ptr() + first_frame.offset, first_frame.payload_size,
            width, height, first_frame_coefficients, video_error);
        PackedByteArray samples;
        samples.resize(static_cast<int64_t>(expected_audio_bytes));
        std::memcpy(samples.ptrw(), audio.samples.get<const uint8_t>(), static_cast<size_t>(expected_audio_bytes));
        Dictionary result;
        result["ok"] = true;
        result["width"] = static_cast<int64_t>(width);
        result["height"] = static_cast<int64_t>(height);
        result["frame_count"] = static_cast<int64_t>(declared_frames);
        result["frame_record_count"] = static_cast<int64_t>(frame_records.size());
        Array frame_info;
        frame_info.resize(static_cast<int64_t>(frame_records.size()));
        for (size_t index = 0; index < frame_records.size(); ++index) {
            const MeiFrameRecord &frame = frame_records[index];
            Dictionary item;
            item["index"] = static_cast<int64_t>(index);
            item["record_type"] = frame.record_type.c_str();
            item["picture_type"] = String::utf8(&frame.picture_type, 1);
            item["payload_size"] = static_cast<int64_t>(frame.payload_size);
            item["eri_version"] = frame.eri_version;
            item["operation_flags"] = frame.operation_flags;
            item["encode_type"] = frame.encode_type;
            item["bit_count"] = frame.bit_count;
            frame_info[static_cast<int64_t>(index)] = item;
        }
        result["video_frame_info"] = frame_info;
        result["duration_ms"] = static_cast<int64_t>(duration_ms);
        result["sample_count_per_channel"] = static_cast<int64_t>(declared_samples);
        result["channels"] = static_cast<int64_t>(channels);
        result["sample_rate"] = static_cast<int64_t>(sample_rate);
        result["bits_per_sample"] = static_cast<int64_t>(bits_per_sample);
        result["audio_data"] = samples;
        result["first_frame_entropy_decoded"] = first_frame_entropy_decoded;
        result["first_frame_coefficient_count"] = static_cast<int64_t>(first_frame_coefficients.size());
        if (first_frame_entropy_decoded) {
            PackedByteArray coefficient_bytes;
            coefficient_bytes.resize(static_cast<int64_t>(first_frame_coefficients.size()));
            std::memcpy(coefficient_bytes.ptrw(), first_frame_coefficients.data(), first_frame_coefficients.size());
            result["first_frame_coefficients"] = coefficient_bytes;
        }
        result["video_frames_decoded"] = false;
        result["video_error"] = first_frame_entropy_decoded
            ? "First I-frame entropy decoded; inverse quantization, transforms, color reconstruction, and remaining frames are pending."
            : String::utf8(video_error.c_str());
        return result;
    } catch (const std::exception &error) {
        return codec_failure(error.what());
    } catch (...) {
        return codec_failure("Unknown native MEI decoder error.");
    }
}

static void yzk_codec_initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(YzkCodec);
    }
}

static void yzk_codec_deinitialize(ModuleInitializationLevel) {}

} // namespace godot

extern "C" {

YZK_EXPORT int yzk_codec_version() {
    return 100;
}

YZK_EXPORT GDExtensionBool GDE_EXPORT yzk_codec_init(
    GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject init_object(get_proc_address, library, initialization);
    init_object.register_initializer(godot::yzk_codec_initialize);
    init_object.register_terminator(godot::yzk_codec_deinitialize);
	init_object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_object.init();
}

YZK_EXPORT int yzk_decode_erisan(const uint8_t* in_data, size_t in_size, uint8_t* out_data, size_t out_size) {
    if (!in_data || in_size < 4 || !out_data || out_size == 0) {
        return -1;
    }
    try {
        au::bstr encoded(in_size);
        std::memcpy(encoded.get<char>(), in_data, in_size);
        au::dec::entis::common::ErisaNDecoder decoder;
        decoder.set_input(encoded);
        decoder.reset();
        decoder.decode(out_data, out_size);

        uint8_t checksum[4] = {0, 0, 0, 0};
        for (size_t i = 0; i < out_size; ++i) {
            checksum[i % 4] ^= out_data[i];
        }
        for (size_t i = 0; i < 4; ++i) {
            if (checksum[i] != in_data[in_size - 4 + i]) {
                return -2; // checksum mismatch
            }
        }
        return 0; // success
    } catch (...) {
        return -3;
    }
}

YZK_EXPORT void yzk_free(void* ptr) {
    std::free(ptr);
}

}
