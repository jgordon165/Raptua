#include "formats/font.h"

namespace raptua {

bool decode_font(const Bytes& d, Font& out) {
    constexpr size_t kHdr = 4 + 512 + 256;
    if (d.size() < kHdr) return false;
    out.height = int(uint32_t(d[0] | d[1] << 8 | d[2] << 16 | uint32_t(d[3]) << 24));
    if (out.height <= 0 || out.height > 64) return false;
    for (int i = 0; i < 256; ++i) out.offset[size_t(i)] = int16_t(uint16_t(d[4 + i * 2] | d[5 + i * 2] << 8));
    for (int i = 0; i < 256; ++i) out.width[size_t(i)] = d[516 + size_t(i)];
    out.pixels.assign(d.begin() + kHdr, d.end());
    for (int i = 0; i < 256; ++i) {
        if (out.offset[size_t(i)] < 0) continue;
        size_t end = size_t(out.offset[size_t(i)]) + size_t(out.width[size_t(i)]) * size_t(out.height);
        if (end > out.pixels.size()) out.offset[size_t(i)] = -1;   // damaged glyph: drop it
    }
    return true;
}

} // namespace raptua
