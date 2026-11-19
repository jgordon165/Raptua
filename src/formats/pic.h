// Raptor images (*_PIC, *_BLK, tiles) and VGA palettes (*_DAT).
//
// Every image starts with five u32: {type, hot?, spans, width, height}.
// spans == 0: width*height raw palette indices follow (tiles, full screens).
// spans != 0: a list of horizontal runs {i32 x, i32 y, i32 linear, i32 n,
// n bytes}, ended by a run with linear == n == -1. Unlisted pixels are
// transparent. See docs/formats.md.
#pragma once
#include <array>
#include <cstdint>
#include <vector>

#include "formats/glb.h"

namespace raptua {

struct Span {
    int16_t x, y;
    uint32_t offset;   // into Pic::pixels
    uint16_t count;
};

struct Pic {
    int width = 0, height = 0;
    uint32_t header0 = 0, header1 = 0;   // meaning not settled yet
    bool sprite = false;                 // true: spans with transparency
    std::vector<uint8_t> pixels;         // raw: width*height; sprite: span data
    std::vector<Span> spans;
};

bool decode_pic(const Bytes& data, Pic& out);

// 6-bit VGA palette (768 bytes) -> 8-bit RGB.
using Palette = std::array<uint8_t, 768>;
bool decode_palette(const Bytes& data, Palette& out);

} // namespace raptua
