// SPDX-License-Identifier: GPL-3.0-or-later
// In-process native codec shared library for Godot Yosuga no Sora port.
#include <cstddef>
#include <cstdint>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "algo/locale.h"
#include "algo/str.h"
#include "dec/entis/common/erisan_decoder.h"
#include "dec/entis/audio/common.h"
#include "dec/entis/common/sections.h"
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
constexpr uint64_t kMaxMeiWorkingSetBytes = 256ULL * 1024ULL * 1024ULL;
constexpr size_t kMaxSectionCount = 32768;
constexpr uint64_t kMeiDctFixedScratchBytes = 1ULL * 1024ULL * 1024ULL;
// Values from Entis ERISADecoder::DecodeFlag in erisaimage.h.
constexpr uint32_t kMeiPlayNoLoopFilter = 0x0400;
constexpr uint32_t kMeiPlayUseLoopFilter = 0x0800;

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

struct MioDecodeEstimate {
    uint64_t decoded_audio_bytes = 0;
    uint64_t compressed_chunk_bytes = 0;
    uint64_t max_decoded_chunk_bytes = 0;
    uint64_t max_compressed_chunk_bytes = 0;
    uint64_t chunk_count = 0;
    uint64_t stream_section_count = 0;
    uint32_t transformation = 0;
    uint32_t subband_degree = 0;
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

bool mei_gamma_bytes(MeiBitReader &bits, size_t count, std::vector<int8_t> &decoded,
    std::string &error) {
    decoded.assign(count, 0);
    uint32_t zero_flag = 0;
    if (!bits.read(1, zero_flag)) {
        error = "First MEI frame gamma-coded table is truncated.";
        return false;
    }
    bool zero_run = zero_flag == 0;
    size_t cursor = 0;
    while (cursor < decoded.size()) {
        uint32_t run = 0;
        if (!mei_gamma(bits, run) || run == 0) {
            error = "First MEI frame gamma-coded run is invalid.";
            return false;
        }
        const size_t run_size = std::min<size_t>(run, decoded.size() - cursor);
        if (zero_run) {
            cursor += run_size;
        } else {
            for (size_t i = 0; i < run_size; ++i) {
                uint32_t sign = 0, magnitude = 0;
                if (!bits.read(1, sign) || !mei_gamma(bits, magnitude)
                    || magnitude == 0 || magnitude > 128) {
                    error = "First MEI frame gamma-coded value is invalid.";
                    return false;
                }
                decoded[cursor++] = static_cast<int8_t>(sign
                    ? -static_cast<int>(magnitude) : static_cast<int>(magnitude));
            }
        }
        zero_run = !zero_run;
    }
    return true;
}

bool decode_mei_i_frame_coefficients(const uint8_t *frame, size_t frame_size,
    size_t width, size_t height, std::vector<int8_t> &coefficients,
    std::array<uint8_t, 128> &quantization, std::vector<int8_t> &operations,
    std::vector<int8_t> &motion_flags, std::vector<int8_t> &motion_vectors,
    std::string &error) {
    using namespace au::dec::entis::common;
    if (!frame || frame_size < 4 || frame[0] != 0x28
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
    for (uint8_t &item : quantization) {
        int symbol = 0;
        if (!mei_huffman(bits, initial_tree, false, symbol) || symbol < 0 || symbol > 255) {
            error = "First MEI frame quantization table is truncated.";
            return false;
        }
        item = static_cast<uint8_t>(symbol);
    }
    const size_t op_count = block_width * block_height * 2;
    if (!mei_gamma_bytes(bits, op_count, operations, error)) return false;
    if ((frame[1] & 0x01) != 0) {
        const size_t macroblocks = block_width * block_height;
        if (!mei_gamma_bytes(bits, macroblocks, motion_flags, error)
            || !mei_gamma_bytes(bits, macroblocks * 4, motion_vectors, error))
            return false;
    } else {
        motion_flags.clear();
        motion_vectors.clear();
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

uint8_t mei_clamp_byte(int value) {
    return static_cast<uint8_t>(std::clamp(value, 0, 255));
}

int mei_average_byte(int left, int right) {
    // Matches the rounded byte average used by Entis' 486 loop-filter path.
    return ((left >> 1) & 0x7f) + ((right >> 1) & 0x7f) + (left & right & 1);
}

void mei_filter_421_region(std::vector<uint8_t> &rgba, size_t image_width,
    size_t x_begin, size_t y_begin, size_t region_width, size_t region_height) {
    if (region_width < 2 || region_height < 2) return;
    std::vector<uint8_t> horizontal(region_width * region_height * 4);
    const auto source_offset = [=](size_t x, size_t y, size_t channel) {
        return ((y_begin + y) * image_width + x_begin + x) * 4 + channel;
    };
    for (size_t y = 0; y < region_height; ++y) {
        for (size_t channel = 0; channel < 4; ++channel) {
            horizontal[(y * region_width) * 4 + channel] = rgba[source_offset(0, y, channel)];
            horizontal[(y * region_width + region_width - 1) * 4 + channel]
                = rgba[source_offset(region_width - 1, y, channel)];
            for (size_t x = 1; x + 1 < region_width; ++x) {
                const int neighbors = mei_average_byte(
                    rgba[source_offset(x - 1, y, channel)],
                    rgba[source_offset(x + 1, y, channel)]);
                horizontal[(y * region_width + x) * 4 + channel]
                    = static_cast<uint8_t>(mei_average_byte(
                        rgba[source_offset(x, y, channel)], neighbors));
            }
        }
    }
    for (size_t y = 1; y + 1 < region_height; ++y) {
        for (size_t x = 0; x < region_width; ++x) {
            for (size_t channel = 0; channel < 4; ++channel) {
                const size_t dst = source_offset(x, y, channel);
                const int neighbors = mei_average_byte(
                    horizontal[((y - 1) * region_width + x) * 4 + channel],
                    horizontal[((y + 1) * region_width + x) * 4 + channel]);
                rgba[dst] = static_cast<uint8_t>(mei_average_byte(
                    horizontal[(y * region_width + x) * 4 + channel], neighbors));
            }
        }
    }
    for (size_t x = 0; x < region_width; ++x) {
        for (size_t channel = 0; channel < 4; ++channel) {
            rgba[source_offset(x, 0, channel)] = horizontal[x * 4 + channel];
            rgba[source_offset(x, region_height - 1, channel)]
                = horizontal[((region_height - 1) * region_width + x) * 4 + channel];
        }
    }
}

void mei_apply_local_loop_filter_421(std::vector<uint8_t> &rgba,
    size_t width, size_t height, const std::vector<int8_t> *motion_flags) {
    const size_t blocks_wide = (width + 15) / 16;
    const size_t blocks_high = (height + 15) / 16;
    if (!motion_flags || motion_flags->empty()) {
        mei_filter_421_region(rgba, width, 0, 0, width, height);
        return;
    }
    for (size_t by = 0; by < blocks_high; ++by) {
        size_t bx = 0;
        while (bx < blocks_wide) {
            const size_t block_index = by * blocks_wide + bx;
            if (block_index >= motion_flags->size() || (*motion_flags)[block_index] != 0) {
                ++bx;
                continue;
            }
            const size_t begin = bx;
            do {
                ++bx;
            } while (bx < blocks_wide
                && by * blocks_wide + bx < motion_flags->size()
                && (*motion_flags)[by * blocks_wide + bx] == 0);
            const size_t x_begin = begin * 16;
            const size_t x_end = std::min(width, bx * 16);
            const size_t y_begin = by * 16;
            const size_t y_end = std::min(height, y_begin + 16);
            mei_filter_421_region(rgba, width, x_begin, y_begin,
                x_end - x_begin, y_end - y_begin);
        }
    }
}

bool reconstruct_mei_frame_pixels(size_t width, size_t height,
    const std::vector<int8_t> &coefficients,
    const std::array<uint8_t, 128> &quantization,
    const std::vector<int8_t> &operations, std::vector<uint8_t> &rgba,
    int &minimum_luma, int &maximum_luma,
    std::string &error, bool differential = false,
    const std::vector<uint8_t> *reference = nullptr,
    const std::vector<int8_t> *motion_flags = nullptr,
    const std::vector<int8_t> *motion_vectors = nullptr,
    const std::vector<uint8_t> *next_reference = nullptr,
    bool allow_bidirectional = false, int operation_flags = 0,
    uint32_t play_mode_flags = 0,
    std::vector<uint8_t> *reference_rgba = nullptr) {
    const size_t block_width = (width + 15) / 16;
    const size_t block_height = (height + 15) / 16;
    if (coefficients.size() != block_width * block_height * 384
        || operations.size() != block_width * block_height * 2) {
        error = "MEI frame reconstruction buffers have invalid dimensions.";
        return false;
    }
    const size_t macroblock_count = block_width * block_height;
    if (differential && ((!reference || reference->size() != width * height * 4)
        && (!next_reference || next_reference->size() != width * height * 4))) {
        error = "Differential MEI frame is missing its reference image.";
        return false;
    }
    if (differential && (!motion_flags || motion_flags->size() != macroblock_count
        || !motion_vectors || motion_vectors->size() != macroblock_count * 4)) {
        error = "Differential MEI frame is missing its reference image or motion tables.";
        return false;
    }
    constexpr size_t kBlockArea = 64;
    static constexpr int16_t idct_matrix[8][8] = {
        {16385,16069,15137,13623,11585,9103,6271,3197},
        {16385,13623,6271,-3196,-11585,-16069,-15137,-9102},
        {16385,9103,-6270,-16069,-11585,3197,15137,13623},
        {16385,3197,-15137,-9102,11585,13623,-6270,-16069},
        {16385,-3196,-15137,9103,11585,-13623,-6270,16069},
        {16385,-9102,-6270,16069,-11585,-3196,15137,-13623},
        {16385,-13623,6271,3197,-11585,16069,-15137,9103},
        {16385,-16069,15137,-13623,11585,-9102,6271,-3196}
    };
    rgba.assign(width * height * 4, differential ? 0 : 255);
    std::array<std::array<int8_t, kBlockArea>, 6> spatial{};
    std::array<std::array<int16_t, kBlockArea>, 6> spectrum{};
    std::array<std::array<int16_t, kBlockArea>, 6> horizontal{};
    minimum_luma = 255;
    maximum_luma = 0;
    std::vector<int32_t> cumulative_vectors;
    if (differential) {
        cumulative_vectors.resize(motion_vectors->size());
        for (size_t i = 0; i < motion_vectors->size(); ++i)
            cumulative_vectors[i] = (*motion_vectors)[i];
        for (size_t y = 1; y < block_height; ++y) {
            for (size_t x = 0; x < block_width; ++x) {
                const size_t current = (y * block_width + x) * 4;
                const size_t above = current - block_width * 4;
                for (size_t component = 0; component < 4; ++component)
                    cumulative_vectors[current + component] += cumulative_vectors[above + component];
            }
        }
        for (size_t y = 0; y < block_height; ++y) {
            for (size_t x = 1; x < block_width; ++x) {
                const size_t current = (y * block_width + x) * 4;
                const size_t previous = current - 4;
                for (size_t component = 0; component < 4; ++component)
                    cumulative_vectors[current + component] += cumulative_vectors[previous + component];
            }
        }
    }
    for (size_t by = 0; by < block_height; ++by) {
        for (size_t bx = 0; bx < block_width; ++bx) {
            const size_t macroblock = by * block_width + bx;
            const size_t coefficient_base = macroblock * 384;
            if (differential) {
                const int reference_mode = (*motion_flags)[macroblock];
                if ((reference_mode == 2 || reference_mode == -1) && !allow_bidirectional) {
                    error = "Bidirectional MEI frame requires both previous and next references.";
                    return false;
                }
                if ((reference_mode != 0 && reference_mode != 1
                    && reference_mode != 2 && reference_mode != -1)
                    || (reference_mode == 1 && !reference)
                    || ((reference_mode == -1 || reference_mode == 2) && !next_reference)) {
                    error = "MEI motion flag requests a missing or unsupported reference.";
                    return false;
                }
                const size_t dst_x = bx * 16;
                const size_t dst_y = by * 16;
                const size_t vector_index = macroblock * 4;
                auto reference_origin = [&](size_t component) {
                    int sx = static_cast<int>(dst_x) + (cumulative_vectors[vector_index + component] >> 1);
                    int sy = static_cast<int>(dst_y) + (cumulative_vectors[vector_index + component + 1] >> 1);
                    if (sx < 0 || sy < 0 || sx + 16 > static_cast<int>(width)
                        || sy + 16 > static_cast<int>(height)) {
                        sx = static_cast<int>(dst_x);
                        sy = static_cast<int>(dst_y);
                    }
                    return std::pair<int, int>(sx, sy);
                };
                const auto previous_origin = reference_mode == 1 || reference_mode == 2
                    ? reference_origin(0) : std::pair<int, int>(0, 0);
                const auto next_origin = reference_mode == -1 || reference_mode == 2
                    ? reference_origin(2) : std::pair<int, int>(0, 0);
                auto predicted_reference_pixel = [&](const std::vector<uint8_t> *image,
                    const std::pair<int, int> &origin, size_t component,
                    size_t local_x, size_t local_y, size_t channel) {
                    if (!image) return 0;
                    const int horizontal_half = cumulative_vectors[vector_index + component] & 1;
                    const int vertical_half = cumulative_vectors[vector_index + component + 1] & 1;
                    const auto sample = [&](size_t x, size_t y) {
                        const size_t source_x = std::min<size_t>(
                            static_cast<size_t>(origin.first) + x, width - 1);
                        const size_t source_y = std::min<size_t>(
                            static_cast<size_t>(origin.second) + y, height - 1);
                        return static_cast<int>((*image)[(source_y * width + source_x) * 4 + channel]);
                    };
                    const int top_left = sample(local_x, local_y);
                    if (!horizontal_half && !vertical_half) return top_left;
                    const int top_right = horizontal_half ? sample(local_x + 1, local_y) : top_left;
                    const int top = horizontal_half ? (top_left + top_right + 1) >> 1 : top_left;
                    if (!vertical_half) return top;
                    const int bottom_left = sample(local_x, local_y + 1);
                    const int bottom_right = horizontal_half
                        ? sample(local_x + 1, local_y + 1) : bottom_left;
                    const int bottom = horizontal_half
                        ? (bottom_left + bottom_right + 1) >> 1 : bottom_left;
                    return (top + bottom + 1) >> 1;
                };
                for (size_t local_y = 0; local_y < 16 && dst_y + local_y < height; ++local_y) {
                    for (size_t local_x = 0; local_x < 16 && dst_x + local_x < width; ++local_x) {
                        const size_t dst_pixel = ((dst_y + local_y) * width + dst_x + local_x) * 4;
                        for (size_t channel = 0; channel < 4; ++channel) {
                            const int previous_value = (reference_mode == 1 || reference_mode == 2)
                                ? predicted_reference_pixel(reference, previous_origin, 0, local_x, local_y, channel) : 0;
                            const int next_value = (reference_mode == -1 || reference_mode == 2)
                                ? predicted_reference_pixel(next_reference, next_origin, 2, local_x, local_y, channel) : 0;
                            if (reference_mode == 2)
                                rgba[dst_pixel + channel] = static_cast<uint8_t>((previous_value + next_value + 1) >> 1);
                            else if (reference_mode == 1)
                                rgba[dst_pixel + channel] = static_cast<uint8_t>(previous_value);
                            else if (reference_mode == -1)
                                rgba[dst_pixel + channel] = static_cast<uint8_t>(next_value);
                            else
                                rgba[dst_pixel + channel] = channel == 3 ? 255 : 0;
                        }
                    }
                }
            }
            for (size_t block = 0; block < 6; ++block) {
                const size_t operation_index = macroblock * 2 + (block >= 4 ? 1 : 0);
                const int operation = operations[operation_index];
                const int exponent = operation >> 1;
                const int odd_scale = operation & 1;
                const int right_shift = exponent < 0 ? -exponent + odd_scale : odd_scale;
                const int exponent_scale = exponent > 0 ? exponent : 0;
                const size_t quant_base = block < 4 ? 0 : 64;
                spectrum[block].fill(0);
                static constexpr int zigzag[64] = {
                    0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,
                    12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,
                    35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,
                    58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63
                };
                for (size_t index = 0; index < kBlockArea; ++index) {
                    // ERI's 4:1:1 stream interleaves the six blocks at each
                    // coefficient position: Y0,Y1,Y2,Y3,U,V, then the next
                    // zigzag position. The four Y blocks delta-code their DC
                    // terms against Y0's DC.
                    int coefficient = static_cast<int>(
                        coefficients[coefficient_base + index * 6 + block]);
                    if (block > 0 && block < 4 && index == 0)
                        coefficient = static_cast<int>(static_cast<int8_t>(
                            coefficient + static_cast<int>(coefficients[coefficient_base])));
                    int quantizer = static_cast<int>(quantization[quant_base + index]) + 1;
                    if (exponent >= 0)
                        quantizer *= odd_scale ? 3 : 1;
                    quantizer <<= exponent_scale;
                    const int dequantized = (coefficient * quantizer) >> right_shift;
                    spectrum[block][zigzag[index]] = static_cast<int16_t>(
                        std::clamp(dequantized, -32768, 32767));
                }
                // Preserve the Entis integer IDCT's asymmetric pass shifts:
                // the row pass shifts by 14 and the column pass by 16. Their
                // combined scale is unchanged by 15/15, but the intermediate
                // truncation changes decoded pixels when using 15/15.
                for (size_t y = 0; y < 8; ++y) {
                    for (size_t x = 0; x < 8; ++x) {
                        int32_t sum = 0;
                        for (size_t frequency = 0; frequency < 8; ++frequency)
                            sum += static_cast<int32_t>(spectrum[block][y * 8 + frequency])
                                * idct_matrix[x][frequency];
                        horizontal[block][y * 8 + x] = static_cast<int16_t>(
                            std::clamp(sum >> 14, -32768, 32767));
                    }
                }
                for (size_t y = 0; y < 8; ++y) {
                    for (size_t x = 0; x < 8; ++x) {
                        int32_t sum = 0;
                        for (size_t frequency = 0; frequency < 8; ++frequency)
                            sum += static_cast<int32_t>(horizontal[block][frequency * 8 + x])
                                * idct_matrix[y][frequency];
                        const int value = std::clamp(sum >> 16, -32768, 32767);
                        spatial[block][y * 8 + x] = block < 4 && !differential
                            ? static_cast<int8_t>(mei_clamp_byte(value))
                            : static_cast<int8_t>(std::clamp(value, -128, 127));
                    }
                }
            }
            // 4:1:1 stores U and V as 8x8 planes replicated to 16x16 pixels.
            for (size_t local_y = 0; local_y < 16; ++local_y) {
                const size_t y_block = local_y / 8;
                const size_t y_in_block = local_y % 8;
                for (size_t local_x = 0; local_x < 16; ++local_x) {
                    const size_t x_block = local_x / 8;
                    const size_t x_in_block = local_x % 8;
                    const size_t y_index = y_block * 2 + x_block;
                    const int y_value = differential
                        ? static_cast<int>(spatial[y_index][y_in_block * 8 + x_in_block])
                        : static_cast<int>(static_cast<uint8_t>(spatial[y_index][y_in_block * 8 + x_in_block]));
                    const int u = spatial[4][(local_y / 2) * 8 + local_x / 2];
                    const int v = spatial[5][(local_y / 2) * 8 + local_x / 2];
                    minimum_luma = std::min(minimum_luma, y_value);
                    maximum_luma = std::max(maximum_luma, y_value);
                    const size_t x = bx * 16 + local_x;
                    const size_t y = by * 16 + local_y;
                    if (x >= width || y >= height) continue;
                    const size_t pixel = (y * width + x) * 4;
                    if (differential) {
                        // Entis scales Y/U/V before its RGB conversion and
                        // clips only after adding each residual to its
                        // reference pixel. Clipping the unscaled residual
                        // first loses odd values and overflows on saturated
                        // chroma.
                        const int y2 = y_value * 2;
                        const int u2 = u * 2;
                        const int v2 = v * 2;
                        const int u7 = u2 * 7;
                        const int u3 = u2 * 3;
                        const int v3 = v2 * 3;
                        const int blue_delta = y2 + (u7 >> 2);
                        const int green_delta = y2 - ((u3 + v3 + v3) >> 3);
                        const int red_delta = y2 + (v3 >> 1);
                        rgba[pixel] = mei_clamp_byte(static_cast<int>(rgba[pixel]) + red_delta);
                        rgba[pixel + 1] = mei_clamp_byte(static_cast<int>(rgba[pixel + 1]) + green_delta);
                        rgba[pixel + 2] = mei_clamp_byte(static_cast<int>(rgba[pixel + 2]) + blue_delta);
                        rgba[pixel + 3] = 255;
                    } else {
                        const int blue = y_value + ((u * 7) >> 2);
                        const int green = y_value - ((u * 3 + v * 6) >> 3);
                        const int red = y_value + ((v * 3) >> 1);
                        rgba[pixel] = mei_clamp_byte(red);
                        rgba[pixel + 1] = mei_clamp_byte(green);
                        rgba[pixel + 2] = mei_clamp_byte(blue);
                    }
                }
            }
        }
    }
    if ((play_mode_flags & kMeiPlayNoLoopFilter) == 0) {
        if ((operation_flags & 0x04) != 0 || (play_mode_flags & kMeiPlayUseLoopFilter) != 0) {
            if (reference_rgba)
                *reference_rgba = rgba;
            mei_filter_421_region(rgba, width, 0, 0, width, height);
        } else if ((operation_flags & 0x08) != 0) {
            if (reference_rgba)
                *reference_rgba = rgba;
            mei_apply_local_loop_filter_421(rgba, width, height, motion_flags);
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
        if (end - cursor < 16 || sections.size() >= kMaxSectionCount) return false;
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

bool validate_mio_size(const uint8_t *data, size_t size, std::string &error,
    MioDecodeEstimate *estimate = nullptr) {
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
    const uint32_t transformation = read_u32_le(data + sound_info.offset + 4);
    const uint32_t subband_degree = read_u32_le(data + sound_info.offset + 24);
    const uint32_t lapped_degree = read_u32_le(data + sound_info.offset + 32);
    const bool lossless = transformation == 0x03020000U;
    const bool lossy = transformation == 0x00000005U || transformation == 0x00000105U;
    if (channels == 0 || channels > 8 || sample_rate < 8000 || sample_rate > 384000
        || (bits_per_sample != 8 && bits_per_sample != 16 && bits_per_sample != 24 && bits_per_sample != 32)
        || (!lossless && !lossy)
        || (lossy && (subband_degree < 8 || subband_degree > 11 || lapped_degree != 1))) {
        error = "MIO audio format fields are outside supported bounds.";
        return false;
    }
    // arc_unpacker's Entis audio decoders emit signed 16-bit PCM. Lossy DCT
    // chunks round each channel's sample count up to the subband block width;
    // budget against that allocation rather than only the declared/raw count.
    const uint64_t block_width = lossless ? 1ULL : (1ULL << subband_degree);
    std::vector<SectionRange> stream_sections;
    if (!read_sections(data, stream.offset, stream.offset + stream.size, stream_sections)) {
        error = "MIO stream section table is malformed.";
        return false;
    }
    uint64_t total_samples = 0;
    uint64_t compressed_chunk_bytes = 0;
    uint64_t max_decoded_chunk_bytes = 0;
    uint64_t max_compressed_chunk_bytes = 0;
    uint64_t chunk_count = 0;
    for (const SectionRange &section : stream_sections) {
        if (section.name != "SoundStm") continue;
        if (section.size < 8) {
            error = "MIO SoundStm chunk is truncated.";
            return false;
        }
        const uint64_t chunk_samples = read_u32_le(data + section.offset + 4);
        const uint64_t padded_samples = ((chunk_samples + block_width - 1) / block_width) * block_width;
        const uint64_t chunk_pcm_bytes = padded_samples * channels * sizeof(int16_t);
        if (padded_samples > std::numeric_limits<uint64_t>::max() - total_samples) {
            error = "Decoded MIO audio sample count overflows.";
            return false;
        }
        if (section.size - 8 > std::numeric_limits<uint64_t>::max() - compressed_chunk_bytes) {
            error = "Decoded MIO compressed chunk size overflows.";
            return false;
        }
        total_samples += padded_samples;
        compressed_chunk_bytes += section.size - 8;
        max_decoded_chunk_bytes = std::max(max_decoded_chunk_bytes, chunk_pcm_bytes);
        max_compressed_chunk_bytes = std::max<uint64_t>(max_compressed_chunk_bytes, section.size - 8);
        ++chunk_count;
        if (total_samples > kMaxCodecOutputBytes / channels / sizeof(int16_t)) {
            error = "Decoded MIO audio would exceed the output limit.";
            return false;
        }
    }
    if (total_samples == 0 || header_samples == 0) {
        error = "MIO contains no samples.";
        return false;
    }
    if (estimate) {
        estimate->decoded_audio_bytes = total_samples * channels * sizeof(int16_t);
        estimate->compressed_chunk_bytes = compressed_chunk_bytes;
        estimate->max_decoded_chunk_bytes = max_decoded_chunk_bytes;
        estimate->max_compressed_chunk_bytes = max_compressed_chunk_bytes;
        estimate->chunk_count = chunk_count;
        estimate->stream_section_count = stream_sections.size();
        estimate->transformation = transformation;
        estimate->subband_degree = subband_degree;
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
    uint32_t &bits_per_sample,
    MioDecodeEstimate &audio_estimate,
    uint64_t &metadata_estimate_bytes) {
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
    if (frame_records.empty() || frame_records.size() > kMaxSectionCount || declared_frames == 0
        || declared_frames > kMaxSectionCount || declared_samples == 0 || channels == 0
        || (bits_per_sample != 8 && bits_per_sample != 16 && bits_per_sample != 24 && bits_per_sample != 32)
        || declared_samples > kMaxCodecOutputBytes / channels / (bits_per_sample / 8)) {
        error = "MEI has no frames or an invalid declared frame count.";
        return false;
    }
    if (!validate_mio_size(data, size, error, &audio_estimate)) return false;
    // The outer MEI tables remain alive while validate_mio_size reparses the
    // MIO view and constructs a second set of tables. read_sections caps each
    // table, so this deliberately budgets both parser layers and index growth.
    const uint64_t section_count_sum = top_sections.size() + header_sections.size()
        + stream_sections.size();
    metadata_estimate_bytes = section_count_sum * sizeof(SectionRange) * 8
        + static_cast<uint64_t>(frame_records.size()) * sizeof(MeiFrameRecord) * 2;
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

    struct MeiMovieIndex {
        PackedByteArray source;
        bool attempted = false;
        bool valid = false;
        std::string error;
        size_t width = 0;
        size_t height = 0;
        std::vector<MeiFrameRecord> frames;
        uint32_t declared_frames = 0;
        uint32_t duration_ms = 0;
        uint32_t declared_samples = 0;
        uint32_t channels = 0;
        uint32_t sample_rate = 0;
        uint32_t bits_per_sample = 0;
        MioDecodeEstimate audio_estimate;
        uint64_t metadata_estimate_bytes = 0;
        uint64_t build_count = 0;
        uint64_t reuse_count = 0;
        uint64_t validation_us = 0;
    };

    mutable std::mutex mei_index_mutex_;
    mutable MeiMovieIndex mei_index_;

    static uint64_t frame_bytes(const MeiMovieIndex &index) {
        return static_cast<uint64_t>(index.width) * index.height * 4;
    }

    static uint64_t coefficient_bytes(const MeiMovieIndex &index) {
        const uint64_t blocks_wide = (index.width + 15) / 16;
        const uint64_t blocks_high = (index.height + 15) / 16;
        return blocks_wide * blocks_high * 384;
    }

    static uint64_t estimate_mei_open_working_set(
        size_t input_bytes, const MeiMovieIndex &index) {
        const MioDecodeEstimate &audio = index.audio_estimate;
        const uint64_t input_size = input_bytes;
        const uint64_t expected_audio_bytes = static_cast<uint64_t>(index.declared_samples)
            * index.channels * (index.bits_per_sample / 8);
        const uint64_t copy_phase = input_size * 3 + index.metadata_estimate_bytes;

        // The pinned MIO reader owns one SectionReader table, a filtered
        // SoundStm table, and a MioChunk table. It then copies one compressed
        // chunk into each by-value process_chunk argument. Include vector
        // growth room for all three tables plus those transient byte copies.
        const uint64_t mio_metadata = audio.stream_section_count
                * 2 * sizeof(au::dec::entis::common::Section)
            + audio.chunk_count * 2 * sizeof(au::dec::entis::common::Section)
            + audio.chunk_count * 3 * sizeof(au::dec::entis::audio::MioChunk);
        const uint64_t compressed_live = audio.compressed_chunk_bytes
            + audio.max_compressed_chunk_bytes * 2 + mio_metadata;

        // bstr::operator+= grows a vector while the previous storage remains
        // live, keeps the active decoded chunk, then MioAudioDecoder copies
        // the completed aggregate into Audio::samples. This 3x aggregate plus
        // one chunk covers those peak live buffers for the pinned toolchain.
        const uint64_t aggregate_audio = audio.decoded_audio_bytes * 3
            + audio.max_decoded_chunk_bytes;
        const uint64_t decoder_scratch = audio.transformation == 0x03020000U
            ? audio.max_decoded_chunk_bytes * 2
            : audio.max_decoded_chunk_bytes * 8 + kMeiDctFixedScratchBytes;
        const uint64_t video_live = frame_bytes(index) * 6
            + coefficient_bytes(index) * 4
            + static_cast<uint64_t>(index.frames.size()) * 512;
        const uint64_t decode_phase = input_size * 2 + index.metadata_estimate_bytes
            + compressed_live + aggregate_audio + decoder_scratch
            + expected_audio_bytes + video_live;
        return std::max(copy_phase, decode_phase);
    }

    static uint64_t estimate_mei_frame_working_set(
        size_t input_bytes, const MeiMovieIndex &index,
        uint64_t previous_bytes, uint64_t next_bytes) {
        // I/P/B reconstruction can retain the input references, independent
        // copies of them, coefficient/motion tables, RGBA/reference surfaces,
        // and a loop-filter scratch surface at the same time. The multipliers
        // are intentionally conservative for the maximum supported frame.
        return static_cast<uint64_t>(input_bytes) + index.metadata_estimate_bytes
            + previous_bytes + next_bytes + frame_bytes(index) * 12
            + coefficient_bytes(index) * 4 + 2ULL * 1024ULL * 1024ULL;
    }

    bool get_or_build_mei_index(const PackedByteArray &input, std::string &error) const {
        // Holding this snapshot keeps the backing allocation alive. Godot's
        // PackedByteArray copy-on-write makes writes detach from the shared
        // storage, so a live snapshot plus size/pointer identity is a stable
        // immutable-content key without rescanning a large movie on every seek.
        if (mei_index_.attempted && mei_index_.source.size() == input.size()
            && mei_index_.source.ptr() == input.ptr()) {
            ++mei_index_.reuse_count;
            error = mei_index_.error;
            return mei_index_.valid;
        }

        const uint64_t next_build_count = mei_index_.build_count + 1;
        const uint64_t reuse_count = mei_index_.reuse_count;
        const uint64_t validation_us = mei_index_.validation_us;
        mei_index_ = MeiMovieIndex{};
        mei_index_.build_count = next_build_count;
        mei_index_.reuse_count = reuse_count;
        mei_index_.validation_us = validation_us;
        mei_index_.attempted = true;
        mei_index_.source = input;
        const auto started = std::chrono::steady_clock::now();
        mei_index_.valid = validate_mei_size(input.ptr(), static_cast<size_t>(input.size()),
            mei_index_.error, mei_index_.width, mei_index_.height, mei_index_.frames,
            mei_index_.declared_frames, mei_index_.duration_ms, mei_index_.declared_samples,
            mei_index_.channels, mei_index_.sample_rate, mei_index_.bits_per_sample,
            mei_index_.audio_estimate, mei_index_.metadata_estimate_bytes);
        const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - started).count();
        mei_index_.validation_us += static_cast<uint64_t>(std::max<int64_t>(elapsed, 0));
        error = mei_index_.error;
        return mei_index_.valid;
    }

protected:
    static void _bind_methods();

public:
    Dictionary decode_erisan(const PackedByteArray &input, int64_t expected_size) const;
    Dictionary decode_eri(const PackedByteArray &input) const;
    Dictionary decode_mio(const PackedByteArray &input) const;
    Dictionary decode_mei(const PackedByteArray &input) const;
    Dictionary get_mei_index_stats() const;
    Dictionary decode_mei_i_frame(const PackedByteArray &input, int64_t frame_index,
        int64_t play_mode_flags = 0) const;
    Dictionary decode_mei_p_frame(const PackedByteArray &input, int64_t frame_index,
        const PackedByteArray &previous_rgba, int64_t play_mode_flags = 0) const;
    Dictionary decode_mei_b_frame(const PackedByteArray &input, int64_t frame_index,
        const PackedByteArray &previous_rgba, const PackedByteArray &next_rgba,
        int64_t play_mode_flags = 0) const;
    Array build_shading_levels(const PackedByteArray &rgba, int64_t width, int64_t height) const;
};

void YzkCodec::_bind_methods() {
    ClassDB::bind_method(D_METHOD("decode_erisan", "input", "expected_size"), &YzkCodec::decode_erisan);
    ClassDB::bind_method(D_METHOD("decode_eri", "input"), &YzkCodec::decode_eri);
    ClassDB::bind_method(D_METHOD("decode_mio", "input"), &YzkCodec::decode_mio);
    ClassDB::bind_method(D_METHOD("decode_mei", "input"), &YzkCodec::decode_mei);
    ClassDB::bind_method(D_METHOD("get_mei_index_stats"), &YzkCodec::get_mei_index_stats);
    ClassDB::bind_method(D_METHOD("decode_mei_i_frame", "input", "frame_index", "play_mode_flags"), &YzkCodec::decode_mei_i_frame, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("decode_mei_p_frame", "input", "frame_index", "previous_rgba", "play_mode_flags"), &YzkCodec::decode_mei_p_frame, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("decode_mei_b_frame", "input", "frame_index", "previous_rgba", "next_rgba", "play_mode_flags"), &YzkCodec::decode_mei_b_frame, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("build_shading_levels", "rgba", "width", "height"), &YzkCodec::build_shading_levels);
}

Dictionary YzkCodec::get_mei_index_stats() const {
    std::lock_guard<std::mutex> index_lock(mei_index_mutex_);
    Dictionary result;
    result["attempted"] = mei_index_.attempted;
    result["valid"] = mei_index_.valid;
    result["frame_count"] = static_cast<int64_t>(mei_index_.frames.size());
    result["input_size"] = mei_index_.source.size();
    result["build_count"] = static_cast<int64_t>(mei_index_.build_count);
    result["reuse_count"] = static_cast<int64_t>(mei_index_.reuse_count);
    result["validation_us"] = static_cast<int64_t>(mei_index_.validation_us);
    return result;
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
    std::lock_guard<std::mutex> index_lock(mei_index_mutex_);
    if (input.size() < 64 || static_cast<size_t>(input.size()) > kMaxCodecInputBytes)
        return codec_failure("MEI input size is outside the supported bounds.");
    std::string validation_error;
    if (!get_or_build_mei_index(input, validation_error))
        return codec_failure(validation_error);
    const MeiMovieIndex &index = mei_index_;
    const size_t width = index.width, height = index.height;
    const std::vector<MeiFrameRecord> &frame_records = index.frames;
    const uint32_t declared_frames = index.declared_frames;
    const uint32_t duration_ms = index.duration_ms;
    const uint32_t declared_samples = index.declared_samples;
    const uint32_t channels = index.channels;
    const uint32_t sample_rate = index.sample_rate;
    const uint32_t bits_per_sample = index.bits_per_sample;
    const uint64_t expected_audio_bytes = static_cast<uint64_t>(declared_samples)
        * channels * (bits_per_sample / 8);
    const uint64_t estimated_working_set = estimate_mei_open_working_set(
        static_cast<size_t>(input.size()), index);
    if (estimated_working_set > kMaxMeiWorkingSetBytes)
        return codec_failure("MEI estimated live working set would exceed the 256 MiB session budget.");
    try {
        // MEI and MIO share SoundInf/SoundStm coding. Adapt only an owned copy
        // of the private container signature. MemoryByteStream deep-copies
        // that bstr, so release the intermediate encoded copy before decoding
        // chunks; the input, encoded bstr, and stream copy coexist only during
        // this short copy phase.
        std::unique_ptr<au::io::BaseByteStream> mio_stream;
        {
            au::bstr encoded = copy_input(input);
            static constexpr char mio_title[] = "Music Interleaved and Orthogonal";
            static_assert(sizeof(mio_title) - 1 == 32);
            std::memcpy(encoded.get<char>() + 16, mio_title, sizeof(mio_title) - 1);
            mio_stream = std::make_unique<au::io::MemoryByteStream>(encoded);
        }
        au::io::File file("input.mio", std::move(mio_stream));
        au::dec::entis::MioAudioDecoder decoder;
        au::Logger logger;
        logger.mute();
        const au::res::Audio audio = decoder.decode(logger, file);
        if (audio.samples.empty() || audio.samples.size() != index.audio_estimate.decoded_audio_bytes
            || audio.samples.size() > kMaxCodecOutputBytes
            || expected_audio_bytes > audio.samples.size()
            || audio.channel_count != channels || audio.sample_rate != sample_rate
            || audio.bits_per_sample != bits_per_sample)
            return codec_failure("Decoded MEI audio is outside the supported bounds.");
        const uint64_t actual_working_set = estimate_mei_open_working_set(
            static_cast<size_t>(input.size()), index);
        if (actual_working_set > kMaxMeiWorkingSetBytes)
            return codec_failure("MEI estimated live working set would exceed the 256 MiB session budget.");
        std::vector<int8_t> first_frame_coefficients;
        std::array<uint8_t, 128> first_frame_quantization{};
        std::vector<int8_t> first_frame_operations, first_frame_motion_flags, first_frame_motion_vectors;
        std::string video_error;
        const MeiFrameRecord &first_frame = frame_records.front();
        const bool first_frame_entropy_decoded = decode_mei_i_frame_coefficients(
            input.ptr() + first_frame.offset, first_frame.payload_size,
            width, height, first_frame_coefficients, first_frame_quantization,
            first_frame_operations, first_frame_motion_flags, first_frame_motion_vectors, video_error);
        std::vector<uint8_t> first_frame_rgba;
        std::vector<uint8_t> first_frame_reference_rgba;
        int first_frame_min_luma = 0, first_frame_max_luma = 0;
        const bool first_frame_decoded = first_frame_entropy_decoded
            && reconstruct_mei_frame_pixels(width, height, first_frame_coefficients,
                first_frame_quantization, first_frame_operations, first_frame_rgba,
                first_frame_min_luma, first_frame_max_luma, video_error,
                false, nullptr, nullptr, nullptr, nullptr, false,
                first_frame.operation_flags, 0, &first_frame_reference_rgba);
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
        result["first_frame_decoded"] = first_frame_decoded;
        result["first_frame_coefficient_count"] = static_cast<int64_t>(first_frame_coefficients.size());
        result["first_frame_min_luma"] = first_frame_min_luma;
        result["first_frame_max_luma"] = first_frame_max_luma;
        if (first_frame_entropy_decoded) {
            PackedByteArray coefficient_bytes;
            coefficient_bytes.resize(static_cast<int64_t>(first_frame_coefficients.size()));
            std::memcpy(coefficient_bytes.ptrw(), first_frame_coefficients.data(), first_frame_coefficients.size());
            result["first_frame_coefficients"] = coefficient_bytes;
        }
        if (first_frame_decoded) {
            PackedByteArray rgba;
            rgba.resize(static_cast<int64_t>(first_frame_rgba.size()));
            std::memcpy(rgba.ptrw(), first_frame_rgba.data(), first_frame_rgba.size());
            result["first_frame_rgba"] = rgba;
            PackedByteArray reference_rgba;
            if (first_frame_reference_rgba.empty()) {
                reference_rgba = rgba;
            } else {
                reference_rgba.resize(static_cast<int64_t>(first_frame_reference_rgba.size()));
                std::memcpy(reference_rgba.ptrw(), first_frame_reference_rgba.data(), first_frame_reference_rgba.size());
            }
            result["first_frame_reference_rgba"] = reference_rgba;
        }
        result["video_frames_decoded"] = false;
        result["video_error"] = first_frame_decoded
            ? "First I-frame reconstructed; remaining I/P/B frames are pending."
            : String::utf8(video_error.c_str());
        return result;
    } catch (const std::exception &error) {
        return codec_failure(error.what());
    } catch (...) {
        return codec_failure("Unknown native MEI decoder error.");
    }
}

Dictionary YzkCodec::decode_mei_i_frame(const PackedByteArray &input, int64_t frame_index,
    int64_t play_mode_flags) const {
    std::lock_guard<std::mutex> index_lock(mei_index_mutex_);
    if (input.size() < 64 || static_cast<size_t>(input.size()) > kMaxCodecInputBytes)
        return codec_failure("MEI input size is outside the supported bounds.");
    std::string validation_error;
    if (!get_or_build_mei_index(input, validation_error))
        return codec_failure(validation_error);
    const MeiMovieIndex &index = mei_index_;
    const size_t width = index.width, height = index.height;
    const std::vector<MeiFrameRecord> &frame_records = index.frames;
    if (estimate_mei_frame_working_set(static_cast<size_t>(input.size()), index, 0, 0)
        > kMaxMeiWorkingSetBytes)
        return codec_failure("MEI frame estimated live working set would exceed the 256 MiB session budget.");
    if (frame_index < 0 || static_cast<uint64_t>(frame_index) >= frame_records.size())
        return codec_failure("MEI frame index is outside the stream.");
    const MeiFrameRecord &frame = frame_records[static_cast<size_t>(frame_index)];
    if (frame.picture_type != 'I' || frame.record_type != "ImageFrm")
        return codec_failure("Selected MEI frame is differential and needs reference frames.");
    std::vector<int8_t> coefficients, operations, motion_flags, motion_vectors;
    std::array<uint8_t, 128> quantization{};
    std::string frame_error;
    if (!decode_mei_i_frame_coefficients(input.ptr() + frame.offset, frame.payload_size,
        width, height, coefficients, quantization, operations, motion_flags, motion_vectors, frame_error))
        return codec_failure(frame_error);
    std::vector<uint8_t> rgba;
    std::vector<uint8_t> reference_rgba;
    int minimum_luma = 0, maximum_luma = 0;
    if (!reconstruct_mei_frame_pixels(width, height, coefficients, quantization,
        operations, rgba, minimum_luma, maximum_luma, frame_error,
        false, nullptr, nullptr, nullptr, nullptr, false,
        frame.operation_flags, static_cast<uint32_t>(play_mode_flags), &reference_rgba))
        return codec_failure(frame_error);
    PackedByteArray pixels;
    pixels.resize(static_cast<int64_t>(rgba.size()));
    std::memcpy(pixels.ptrw(), rgba.data(), rgba.size());
    PackedByteArray reference_pixels;
    if (reference_rgba.empty()) {
        reference_pixels = pixels;
    } else {
        reference_pixels.resize(static_cast<int64_t>(reference_rgba.size()));
        std::memcpy(reference_pixels.ptrw(), reference_rgba.data(), reference_rgba.size());
    }
    Dictionary result;
    result["ok"] = true;
    result["frame_index"] = frame_index;
    result["width"] = static_cast<int64_t>(width);
    result["height"] = static_cast<int64_t>(height);
    result["rgba"] = pixels;
    result["reference_rgba"] = reference_pixels;
    result["coefficient_count"] = static_cast<int64_t>(coefficients.size());
    result["min_luma"] = minimum_luma;
    result["max_luma"] = maximum_luma;
    return result;
}

Dictionary YzkCodec::decode_mei_p_frame(const PackedByteArray &input, int64_t frame_index,
    const PackedByteArray &previous_rgba, int64_t play_mode_flags) const {
    std::lock_guard<std::mutex> index_lock(mei_index_mutex_);
    if (input.size() < 64 || static_cast<size_t>(input.size()) > kMaxCodecInputBytes)
        return codec_failure("MEI input size is outside the supported bounds.");
    std::string validation_error;
    if (!get_or_build_mei_index(input, validation_error))
        return codec_failure(validation_error);
    const MeiMovieIndex &index = mei_index_;
    const size_t width = index.width, height = index.height;
    const std::vector<MeiFrameRecord> &frame_records = index.frames;
    if (estimate_mei_frame_working_set(static_cast<size_t>(input.size()), index,
        static_cast<uint64_t>(previous_rgba.size()), 0) > kMaxMeiWorkingSetBytes)
        return codec_failure("MEI frame estimated live working set would exceed the 256 MiB session budget.");
    if (frame_index < 0 || static_cast<uint64_t>(frame_index) >= frame_records.size())
        return codec_failure("MEI frame index is outside the stream.");
    const MeiFrameRecord &frame = frame_records[static_cast<size_t>(frame_index)];
    if (frame.picture_type != 'P' || frame.record_type != "DiffeFrm")
        return codec_failure("Selected MEI frame is not a unidirectional P-frame.");
    if (width > SIZE_MAX / height / 4 || previous_rgba.size() != static_cast<int64_t>(width * height * 4))
        return codec_failure("Previous MEI reference frame has invalid dimensions.");
    std::vector<int8_t> coefficients, operations, motion_flags, motion_vectors;
    std::array<uint8_t, 128> quantization{};
    std::string frame_error;
    if (!decode_mei_i_frame_coefficients(input.ptr() + frame.offset, frame.payload_size,
        width, height, coefficients, quantization, operations, motion_flags, motion_vectors, frame_error))
        return codec_failure(frame_error);
    std::vector<uint8_t> previous(static_cast<size_t>(previous_rgba.size()));
    std::memcpy(previous.data(), previous_rgba.ptr(), previous.size());
    std::vector<uint8_t> rgba;
    std::vector<uint8_t> reference_rgba;
    int minimum_luma = 0, maximum_luma = 0;
    if (!reconstruct_mei_frame_pixels(width, height, coefficients, quantization,
        operations, rgba, minimum_luma, maximum_luma, frame_error, true,
        &previous, &motion_flags, &motion_vectors, nullptr, false,
        frame.operation_flags, static_cast<uint32_t>(play_mode_flags), &reference_rgba))
        return codec_failure(frame_error);
    PackedByteArray pixels;
    pixels.resize(static_cast<int64_t>(rgba.size()));
    std::memcpy(pixels.ptrw(), rgba.data(), rgba.size());
    PackedByteArray reference_pixels;
    if (reference_rgba.empty()) {
        reference_pixels = pixels;
    } else {
        reference_pixels.resize(static_cast<int64_t>(reference_rgba.size()));
        std::memcpy(reference_pixels.ptrw(), reference_rgba.data(), reference_rgba.size());
    }
    Dictionary result;
    result["ok"] = true;
    result["frame_index"] = frame_index;
    result["width"] = static_cast<int64_t>(width);
    result["height"] = static_cast<int64_t>(height);
    result["rgba"] = pixels;
    result["reference_rgba"] = reference_pixels;
    result["coefficient_count"] = static_cast<int64_t>(coefficients.size());
    result["min_luma"] = minimum_luma;
    result["max_luma"] = maximum_luma;
    return result;
}

Dictionary YzkCodec::decode_mei_b_frame(const PackedByteArray &input, int64_t frame_index,
    const PackedByteArray &previous_rgba, const PackedByteArray &next_rgba,
    int64_t play_mode_flags) const {
    std::lock_guard<std::mutex> index_lock(mei_index_mutex_);
    if (input.size() < 64 || static_cast<size_t>(input.size()) > kMaxCodecInputBytes)
        return codec_failure("MEI input size is outside the supported bounds.");
    std::string validation_error;
    if (!get_or_build_mei_index(input, validation_error))
        return codec_failure(validation_error);
    const MeiMovieIndex &index = mei_index_;
    const size_t width = index.width, height = index.height;
    const std::vector<MeiFrameRecord> &frame_records = index.frames;
    if (estimate_mei_frame_working_set(static_cast<size_t>(input.size()), index,
        static_cast<uint64_t>(previous_rgba.size()), static_cast<uint64_t>(next_rgba.size()))
        > kMaxMeiWorkingSetBytes)
        return codec_failure("MEI frame estimated live working set would exceed the 256 MiB session budget.");
    if (frame_index < 0 || static_cast<uint64_t>(frame_index) >= frame_records.size())
        return codec_failure("MEI frame index is outside the stream.");
    const MeiFrameRecord &frame = frame_records[static_cast<size_t>(frame_index)];
    if (frame.picture_type != 'B' || frame.record_type != "DiffeFrm")
        return codec_failure("Selected MEI frame is not a bidirectional B-frame.");
    if (width > SIZE_MAX / height / 4
        || previous_rgba.size() != static_cast<int64_t>(width * height * 4)
        || next_rgba.size() != static_cast<int64_t>(width * height * 4))
        return codec_failure("MEI B-frame reference images have invalid dimensions.");
    std::vector<int8_t> coefficients, operations, motion_flags, motion_vectors;
    std::array<uint8_t, 128> quantization{};
    std::string frame_error;
    if (!decode_mei_i_frame_coefficients(input.ptr() + frame.offset, frame.payload_size,
        width, height, coefficients, quantization, operations, motion_flags, motion_vectors, frame_error))
        return codec_failure(frame_error);
    std::vector<uint8_t> previous(static_cast<size_t>(previous_rgba.size()));
    std::memcpy(previous.data(), previous_rgba.ptr(), previous.size());
    std::vector<uint8_t> next(static_cast<size_t>(next_rgba.size()));
    std::memcpy(next.data(), next_rgba.ptr(), next.size());
    std::vector<uint8_t> rgba;
    std::vector<uint8_t> reference_rgba;
    int minimum_luma = 0, maximum_luma = 0;
    if (!reconstruct_mei_frame_pixels(width, height, coefficients, quantization,
        operations, rgba, minimum_luma, maximum_luma, frame_error, true,
        &previous, &motion_flags, &motion_vectors, &next, true,
        frame.operation_flags, static_cast<uint32_t>(play_mode_flags), &reference_rgba))
        return codec_failure(frame_error);
    PackedByteArray pixels;
    pixels.resize(static_cast<int64_t>(rgba.size()));
    std::memcpy(pixels.ptrw(), rgba.data(), rgba.size());
    PackedByteArray reference_pixels;
    if (reference_rgba.empty()) {
        reference_pixels = pixels;
    } else {
        reference_pixels.resize(static_cast<int64_t>(reference_rgba.size()));
        std::memcpy(reference_pixels.ptrw(), reference_rgba.data(), reference_rgba.size());
    }
    Dictionary result;
    result["ok"] = true;
    result["frame_index"] = frame_index;
    result["width"] = static_cast<int64_t>(width);
    result["height"] = static_cast<int64_t>(height);
    result["rgba"] = pixels;
    result["reference_rgba"] = reference_pixels;
    result["coefficient_count"] = static_cast<int64_t>(coefficients.size());
    result["min_luma"] = minimum_luma;
    result["max_luma"] = maximum_luma;
    return result;
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
