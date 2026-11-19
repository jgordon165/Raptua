#include "formats/pic.h"

namespace raptua {

namespace {
int32_t rd32(const uint8_t* p) {
    return int32_t(uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24);
}
} // namespace

bool decode_pic(const Bytes& d, Pic& out) {
    out = Pic{};
    if (d.size() < 20) return false;
    out.header0 = uint32_t(rd32(&d[0]));
    out.header1 = uint32_t(rd32(&d[4]));
    int32_t spans = rd32(&d[8]);
    out.width = rd32(&d[12]);
    out.height = rd32(&d[16]);
    if (out.width <= 0 || out.height <= 0 || out.width > 4096 || out.height > 4096) return false;

    if (spans == 0) {
        size_t n = size_t(out.width) * size_t(out.height);
        if (d.size() < 20 + n) return false;
        out.pixels.assign(d.begin() + 20, d.begin() + 20 + long(n));
        return true;
    }

    out.sprite = true;
    size_t o = 20;
    while (o + 16 <= d.size()) {
        int32_t x = rd32(&d[o]), y = rd32(&d[o + 4]), lin = rd32(&d[o + 8]), n = rd32(&d[o + 12]);
        o += 16;
        if (lin == -1 && n == -1) return true;
        if (n < 0 || o + size_t(n) > d.size()) return false;
        out.spans.push_back({int16_t(x), int16_t(y), uint32_t(out.pixels.size()), uint16_t(n)});
        out.pixels.insert(out.pixels.end(), d.begin() + long(o), d.begin() + long(o) + n);
        o += size_t(n);
    }
    return !out.spans.empty();   // tolerate a missing terminator
}

bool decode_palette(const Bytes& d, Palette& out) {
    if (d.size() < 768) return false;
    for (size_t i = 0; i < 768; ++i) {
        unsigned v = d[i] & 63u;
        out[i] = uint8_t((v << 2) | (v >> 4));
    }
    return true;
}

} // namespace raptua
