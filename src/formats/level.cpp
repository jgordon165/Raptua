#include "formats/level.h"

#include <cstring>

namespace raptua {

namespace {
int32_t rd32(const uint8_t* p) {
    return int32_t(uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24);
}
int16_t rd16(const uint8_t* p) { return int16_t(uint16_t(p[0] | p[1] << 8)); }
} // namespace

bool decode_level(const Bytes& d, Level& out) {
    constexpr size_t kTilesAt = 12, kTilesEnd = kTilesAt + kMapW * kMapH * 4;
    if (d.size() < kTilesEnd) return false;
    uint32_t actor_off = uint32_t(rd32(&d[4]));
    uint32_t actor_cnt = uint32_t(rd32(&d[8]));
    for (size_t i = 0; i < out.cells.size(); ++i) {
        const uint8_t* p = &d[kTilesAt + i * 4];
        out.cells[i] = {uint16_t(rd16(p)), uint16_t(rd16(p + 2))};
    }
    out.actors.clear();
    if (actor_off < kTilesEnd || uint64_t(actor_off) + uint64_t(actor_cnt) * 24 > d.size()) return false;
    for (uint32_t a = 0; a < actor_cnt; ++a) {
        const uint8_t* p = &d[actor_off + a * 24];
        out.actors.push_back({rd32(p), rd32(p + 4), rd32(p + 8), rd32(p + 12), rd32(p + 16), rd32(p + 20)});
    }
    return true;
}

bool decode_sprite_lib(const Bytes& d, std::vector<SpriteDef>& out) {
    out.clear();
    if (d.empty() || d.size() % kSpriteDefSize) return false;
    for (size_t r = 0; r < d.size() / kSpriteDefSize; ++r) {
        const uint8_t* p = &d[r * kSpriteDefSize];
        SpriteDef s;
        s.name.assign(reinterpret_cast<const char*>(p), strnlen(reinterpret_cast<const char*>(p), 16));
        for (int i = 0; i < 26; ++i) s.f[size_t(i)] = rd32(p + 16 + i * 4);
        for (int t = 0; t < 6; ++t)
            for (int i = 0; i < 24; ++i) s.table[size_t(t)][size_t(i)] = rd16(p + 120 + t * 48 + i * 2);
        for (int i = 0; i < 30; ++i) {
            s.path_x[size_t(i)] = rd16(p + 408 + i * 2);
            s.path_y[size_t(i)] = rd16(p + 468 + i * 2);
        }
        out.push_back(std::move(s));
    }
    return true;
}

bool decode_flats(const Bytes& d, std::vector<FlatDef>& out) {
    out.clear();
    if (d.size() % 8) return false;
    for (size_t i = 0; i < d.size(); i += 8)
        out.push_back({rd16(&d[i]), rd16(&d[i + 2]), rd16(&d[i + 4]), rd16(&d[i + 6])});
    return true;
}

} // namespace raptua
