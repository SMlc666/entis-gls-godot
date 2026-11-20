// SPDX-License-Identifier: GPL-3.0-or-later
// Small process boundary around arc_unpacker's ERISAN decoder for Linux.
#include "dec/entis/common/erisan_decoder.h"

#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>

int main(int argc, char **argv) {
    constexpr std::uint64_t max_bytes = 128ULL * 1024 * 1024;
    if (argc != 4) {
        std::cerr << "usage: erisan_decode input output unpacked_size\n";
        return 2;
    }
    try {
        std::size_t used = 0;
        const std::string requested(argv[3]);
        const auto output_size = std::stoull(requested, &used);
        if (used != requested.size() || output_size == 0 || output_size > max_bytes) {
            std::cerr << "invalid output size\n";
            return 2;
        }
        std::ifstream input(argv[1], std::ios::binary | std::ios::ate);
        const auto input_size = input.tellg();
        if (!input || input_size < 4 || static_cast<std::uint64_t>(input_size) > max_bytes) {
            std::cerr << "invalid input size\n";
            return 2;
        }
        au::bstr encoded(static_cast<std::size_t>(input_size));
        input.seekg(0);
        if (!input.read(encoded.get<char>(), input_size)) {
            std::cerr << "input read failed\n";
            return 1;
        }
        au::bstr decoded(static_cast<std::size_t>(output_size));
        au::dec::entis::common::ErisaNDecoder decoder;
        decoder.set_input(encoded);
        decoder.reset();
        decoder.decode(decoded.get<au::u8>(), decoded.size());

        std::uint8_t checksum[4] = {0, 0, 0, 0};
        for (std::size_t i = 0; i < decoded.size(); ++i)
            checksum[i % 4] ^= decoded[i];
        for (std::size_t i = 0; i < 4; ++i) {
            if (checksum[i] != encoded[encoded.size() - 4 + i]) {
                std::cerr << "ERISAN checksum mismatch\n";
                return 1;
            }
        }
        std::ofstream output(argv[2], std::ios::binary | std::ios::trunc);
        if (!output.write(decoded.get<const char>(), decoded.size()) || !output.flush()) {
            std::cerr << "output write failed\n";
            return 1;
        }
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "ERISAN decode failed: " << error.what() << '\n';
        return 1;
    }
}
