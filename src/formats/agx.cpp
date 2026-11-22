#include "formats/agx.h"

#include <cstring>

namespace raptua {

namespace {
constexpr size_t kScreen = 320 * 200;
uint16_t rd16(const uint8_t* p) { return uint16_t(p[0] | p[1] << 8); }
} // namespace

bool decode_agx(const Bytes& d, AgxFrame& out, bool first) {
    out = AgxFrame{};
    size_t p = 0;
    if (first) {
        if (d.empty()) return false;
        out.clear = true;
        out.fill = d[0];
        p = 1;
    }
    while (p + 8 <= d.size()) {
        uint16_t marker = rd16(&d[p]);
        if (marker == 0) return true;
        uint16_t offset = rd16(&d[p + 4]), length = rd16(&d[p + 6]);
        p += 8;
        if (p + length > d.size() || size_t(offset) + length > kScreen) return false;
        out.runs.push_back({offset, length, uint32_t(out.pixels.size())});
        out.pixels.insert(out.pixels.end(), d.begin() + long(p), d.begin() + long(p + length));
        p += length;
    }
    return true;   // no end marker: whatever ran to the end is the frame
}

void apply_agx(const AgxFrame& f, uint8_t* screen) {
    if (f.clear) std::memset(screen, f.fill, kScreen);
    for (const AgxRun& r : f.runs) std::memcpy(screen + r.offset, f.pixels.data() + r.data, r.length);
}

} // namespace raptua
