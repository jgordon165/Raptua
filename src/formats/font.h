// Bitmap fonts (*_FNT): i32 height, i16 offset[256] (-1 = no glyph),
// u8 width[256], then glyph pixels (row-major, width*height each).
// A pixel value of 0 is transparent; other values are palette indices
// (the game recolours them when drawing).
#pragma once
#include <array>
#include <cstdint>
#include <vector>

#include "formats/glb.h"

namespace raptua {

struct Font {
    int height = 0;
    std::array<int16_t, 256> offset{};
    std::array<uint8_t, 256> width{};
    std::vector<uint8_t> pixels;
    bool has(uint8_t c) const { return offset[c] >= 0; }
};

bool decode_font(const Bytes& data, Font& out);

} // namespace raptua
